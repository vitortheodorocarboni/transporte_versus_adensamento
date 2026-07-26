################################################################################
##################################            ##################################
####################### 01.03) UPDATE LAND USE SYMBOLOGY #######################
##################################            ##################################
################################################################################

# This script recalculates adaptive, zero-centered classes for the eleven
# land-use-scenario result layers and exports their class audit report.

################################################################################
##### I. Packages
################################################################################

# Loading libraries
from __future__ import annotations
from pathlib import Path
from xml.etree import ElementTree as ET
import copy
import csv
import math
import os
import pyarrow.parquet as pq
import tempfile
import zipfile

################################################################################
##### II. Paths and files
################################################################################


# Defining the interactive-safe project-root discovery function
def discover_project_root_directory() -> Path:
    """Locate the dissertation root from configuration or execution context."""

    # Reading the optional explicit project-root configuration
    configured_project_root = os.getenv("DISSERTACAO_PROJECT_ROOT")

    # Initializing the ordered search origins
    search_origins: list[Path] = []

    # Prioritizing the explicitly configured project root
    if configured_project_root:
        # Adding the configured project root to the search
        search_origins.append(Path(configured_project_root).expanduser().resolve())

    # Reading the executing file without assuming that __file__ is available
    executing_file = globals().get("__file__")

    # Adding the script directory when running from a saved file
    if executing_file:
        # Adding the resolved script directory to the search
        search_origins.append(Path(executing_file).resolve().parent)

    # Adding the current directory for interactive execution
    search_origins.append(Path.cwd().resolve())

    # Initializing the collection of directories already inspected
    inspected_directories: set[Path] = set()

    # Inspecting every configured or inferred search origin
    for search_origin in search_origins:
        # Inspecting the origin and each of its parent directories
        for candidate_directory in (search_origin, *search_origin.parents):
            # Skipping directories already inspected from another origin
            if candidate_directory in inspected_directories:
                # Continuing with the next candidate directory
                continue

            # Recording the candidate directory as inspected
            inspected_directories.add(candidate_directory)

            # Defining the expected QGIS-project marker
            qgis_project_marker = (
                candidate_directory / "qgis" / "projects" / "everything.qgz"
            )

            # Defining the expected scripts-configuration marker
            scripts_configuration_marker = (
                candidate_directory / "scripts" / "_config" / "paths.R"
            )

            # Returning the first directory containing both project markers
            if qgis_project_marker.is_file() and scripts_configuration_marker.is_file():
                # Returning the validated project root
                return candidate_directory

    # Stopping when no search origin belongs to the dissertation project
    raise FileNotFoundError(
        "Could not locate the dissertation project root. Set "
        "DISSERTACAO_PROJECT_ROOT or run the script from inside the project."
    )


# Discovering the dissertation project root
project_root_directory = discover_project_root_directory()

# Defining the QGIS project input and output file
qgis_project_file = project_root_directory / "qgis" / "projects" / "everything.qgz"

# Defining the land-use-scenario Parquet input file
land_use_results_input_file = (
    project_root_directory
    / "data"
    / "results"
    / "land_use_scenario"
    / "land_use_variation.parquet"
)

# Defining the land-use-symbology audit output file
symbology_report_file = (
    project_root_directory
    / "qgis"
    / "classifications"
    / "land_use_scenario_classes_complete.csv"
)


################################################################################
##### III. Parameters
################################################################################

# Defining the land-use-layer name prefix
layer_name_prefix = "Adensamento "

# Defining the land-use-layer data-source prefix
layer_source_prefix = "../../data/results/land_use_scenario/"

# Defining the expected number of land-use result layers
expected_layer_count = 11

# Defining the ordered negative-side color palette
negative_colors = [
    "103,0,13,255",
    "165,15,21,255",
    "222,45,38,255",
    "252,146,114,255",
    "254,229,217,255",
]
# Defining the ordered positive-side color palette
positive_colors = [
    "222,235,247,255",
    "158,202,225,255",
    "66,146,198,255",
    "8,81,156,255",
    "8,48,107,255",
]
# Defining the single positive-class color
single_positive_color = "222,235,247,255"


################################################################################
##### IV. Functions
################################################################################


# Defining the numeric-value reading function
def read_numeric_values(
    parquet_input_file: Path,
    field_name: str,
) -> list[float]:
    """Read and sort finite values from one land-use result column."""

    # Reading the selected land-use-result column
    results_table = pq.read_table(
        source=parquet_input_file,
        columns=[field_name],
    )

    # Restricting the selected column to finite numeric values
    numeric_values = sorted(
        float(value)
        for value in results_table.column(field_name).to_pylist()
        if value is not None and math.isfinite(float(value))
    )

    # Stopping when the selected field contains no finite observations
    if not numeric_values:
        # Stopping because an empty field cannot be classified
        raise ValueError(f"Field {field_name!r} has no finite observations.")

    # Returning the sorted numeric values
    return numeric_values


# Defining the Jenks natural-break calculation function
def calculate_jenks_breaks(
    values: list[float],
    class_count: int,
) -> list[float]:
    """Calculate optimal Jenks partitions and numeric class separators."""

    # Sorting the numeric values
    sorted_values = sorted(float(value) for value in values)

    # Counting observations in the numeric vector
    observation_count = len(sorted_values)

    # Stopping when the numeric vector is empty
    if observation_count == 0:
        # Stopping because cannot classify an empty vector
        raise ValueError("Cannot classify an empty vector.")

    # Stopping when fewer than two classes were requested
    if class_count < 2:
        # Stopping because Jenks requires at least two classes
        raise ValueError("Jenks classification requires at least two classes.")

    # Counting distinct observations
    distinct_observation_count = len(set(sorted_values))

    # Stopping when distinct observations cannot populate every class
    if distinct_observation_count < class_count:
        # Stopping because empty or zero-width classes would be unavoidable
        raise ValueError(
            f"Jenks classification requested {class_count} classes for only "
            f"{distinct_observation_count} distinct values."
        )

    # Initializing cumulative value sums
    cumulative_sums = [0.0]

    # Initializing cumulative squared-value sums
    cumulative_squared_sums = [0.0]

    # Accumulating the two moment sequences
    for observation_value in sorted_values:
        # Storing the cumulative value sum
        cumulative_sums.append(cumulative_sums[-1] + observation_value)

        # Storing the cumulative squared-value sum
        cumulative_squared_sums.append(
            cumulative_squared_sums[-1] + observation_value * observation_value
        )

    # Initializing optimal within-class variances
    variance_matrix = [
        [float("inf")] * observation_count for _ in range(class_count + 1)
    ]

    # Initializing optimal class-start indices
    class_start_matrix = [[-1] * observation_count for _ in range(class_count + 1)]

    # Calculating every one-class prefix solution
    for end_index in range(observation_count):
        # Counting observations in the current prefix
        current_count = end_index + 1

        # Reading the current prefix sum
        current_sum = cumulative_sums[end_index + 1]

        # Reading the current squared-value prefix sum
        current_squared_sum = cumulative_squared_sums[end_index + 1]

        # Storing the nonnegative one-class variance
        variance_matrix[1][end_index] = max(
            0.0,
            current_squared_sum - current_sum * current_sum / current_count,
        )

    # Solving every classification from two through the requested class count
    for current_class_count in range(2, class_count + 1):
        # Processing every feasible final observation
        for end_index in range(current_class_count - 1, observation_count):
            # Evaluating every feasible start of the final class
            for start_index in range(current_class_count - 1, end_index + 1):
                # Avoiding a split between observations with the same value
                if sorted_values[start_index - 1] == sorted_values[start_index]:
                    # Continuing with the next candidate class start
                    continue

                # Reading the optimal variance before the final class
                preceding_variance = variance_matrix[current_class_count - 1][
                    start_index - 1
                ]

                # Skipping infeasible preceding partitions
                if not math.isfinite(preceding_variance):
                    # Continuing with the next candidate class start
                    continue

                # Counting observations in the candidate final class
                current_count = end_index - start_index + 1

                # Calculating the candidate final-class sum
                current_sum = (
                    cumulative_sums[end_index + 1] - cumulative_sums[start_index]
                )

                # Calculating the candidate final-class squared-value sum
                current_squared_sum = (
                    cumulative_squared_sums[end_index + 1]
                    - cumulative_squared_sums[start_index]
                )

                # Calculating the nonnegative candidate final-class variance
                current_variance = max(
                    0.0,
                    current_squared_sum - current_sum * current_sum / current_count,
                )

                # Calculating the candidate total within-class variance
                candidate_variance = preceding_variance + current_variance

                # Retaining a strictly improved partition
                if candidate_variance < variance_matrix[current_class_count][end_index]:
                    # Storing the improved total variance
                    variance_matrix[current_class_count][end_index] = candidate_variance

                    # Storing the improved final-class start
                    class_start_matrix[current_class_count][end_index] = start_index

    # Stopping when no complete Jenks partition was found
    if not math.isfinite(variance_matrix[class_count][observation_count - 1]):
        # Stopping because the dynamic-programming solution is unavailable
        raise RuntimeError("Could not calculate a complete Jenks partition.")

    # Initializing recovered class-start indices
    recovered_start_indices: list[int] = []

    # Initializing the Jenks backtracking endpoint
    end_index = observation_count - 1

    # Backtracking every class after the first
    for current_class_count in range(class_count, 1, -1):
        # Reading the optimal start of the current class
        start_index = class_start_matrix[current_class_count][end_index]

        # Stopping when the stored partition is incomplete
        if start_index < 1:
            # Stopping because the dynamic-programming backtracking failed
            raise RuntimeError("Jenks partition backtracking is incomplete.")

        # Recording the recovered class start
        recovered_start_indices.append(start_index)

        # Moving the endpoint to the preceding class
        end_index = start_index - 1

    # Restoring class starts from the second through the final class
    recovered_start_indices.reverse()

    # Initializing breaks with the exact observed minimum
    class_breaks = [sorted_values[0]]

    # Converting every partition boundary into a numeric separator
    for start_index in recovered_start_indices:
        # Reading the final value assigned to the preceding class
        preceding_value = sorted_values[start_index - 1]

        # Reading the first value assigned to the following class
        following_value = sorted_values[start_index]

        # Calculating a separator between the adjacent observed values
        class_separator = preceding_value + (following_value - preceding_value) / 2

        # Falling back to the following value when no midpoint is representable
        if class_separator <= preceding_value:
            # Using the next-class value as the exact separator
            class_separator = following_value

        # Storing the recovered numeric separator
        class_breaks.append(class_separator)

    # Appending the exact observed maximum
    class_breaks.append(sorted_values[-1])

    # Stopping when the resulting class intervals are not strictly increasing
    if any(
        lower_bound >= upper_bound
        for lower_bound, upper_bound in zip(class_breaks, class_breaks[1:])
    ):
        # Stopping because the resulting intervals cannot be rendered safely
        raise RuntimeError("Jenks produced a zero-width or decreasing class.")

    # Returning the exact and strictly increasing class breaks
    return class_breaks


# Defining the adaptive-classification function
def classify_values(
    values: list[float],
) -> tuple[str, list[float], list[str]]:
    """Select the scenario classification from the value distribution."""

    # Defining the negatives
    negatives = [value for value in values if value < 0]
    # Defining the positives
    positives = [value for value in values if value >= 0]

    # Handling the absence of negatives
    if not negatives:
        # Returning the calculated result objects
        return (
            "jenks_positive_5_classes",
            calculate_jenks_breaks(
                values=values,
                class_count=5,
            ),
            positive_colors,
        )

    # Handling the absence of positives
    if not positives:
        # Returning the calculated result objects
        return (
            "jenks_negative_5_classes",
            calculate_jenks_breaks(
                values=values,
                class_count=5,
            ),
            negative_colors,
        )

    # Checking whether either sign has fewer than fifteen observations
    if min(len(negatives), len(positives)) < 15:
        # Checking len against the required threshold
        if len(negatives) < len(positives):
            # Defining the breaks
            breaks = [
                min(negatives),
                0.0,
            ] + calculate_jenks_breaks(
                values=positives,
                class_count=5,
            )[1:]
            # Returning the calculated result objects
            return (
                "one_negative_plus_jenks_positive_6_classes",
                breaks,
                [negative_colors[-1]] + positive_colors,
            )

        # Defining the breaks
        breaks = calculate_jenks_breaks(
            values=negatives,
            class_count=5,
        )[:-1] + [
            0.0,
            max(positives),
        ]
        # Returning the calculated result objects
        return (
            "jenks_negative_5_plus_one_positive_6_classes",
            breaks,
            negative_colors + [single_positive_color],
        )

    # Defining the breaks
    breaks = (
        calculate_jenks_breaks(
            values=negatives,
            class_count=5,
        )[:-1]
        + [0.0]
        + calculate_jenks_breaks(
            values=positives,
            class_count=5,
        )[1:]
    )
    # Returning the calculated result objects
    return "jenks_by_sign_10_classes", breaks, negative_colors + positive_colors


# Defining the class-label formatting function
def format_class_label_number(value: float) -> str:
    """Format one class endpoint for the visible map legend."""

    # Defining the abs value
    abs_value = abs(value)
    # Checking abs value against the required threshold
    if abs_value >= 10:
        # Defining the text
        text = f"{value:.2f}"
    # Checking abs value against the required threshold
    elif abs_value >= 1:
        # Defining the text
        text = f"{value:.3f}"
    else:
        # Defining the text
        text = f"{value:.4f}"
    # Returning the updated XML node
    return text.rstrip("0").rstrip(".").replace(".", ",")


# Defining the class-observation counting function
def count_class_observations(
    values: list[float],
    lower_bound: float,
    upper_bound: float,
    is_last_class: bool,
) -> int:
    """Count observations covered by one renderer class."""

    # Checking the required state of is last
    if is_last_class:
        # Returning the sum
        return sum(lower_bound <= value <= upper_bound for value in values)

    # Returning the sum
    return sum(lower_bound <= value < upper_bound for value in values)


# Defining the classification-validation function
def validate_classification(
    values: list[float],
    class_breaks: list[float],
    class_colors: list[str],
) -> list[int]:
    """Validate exact coverage and return observations in every class."""

    # Stopping when the break and color counts are inconsistent
    if len(class_breaks) != len(class_colors) + 1:
        # Stopping because every class requires two consecutive endpoints
        raise ValueError("Class breaks and colors have inconsistent lengths.")

    # Stopping when any class endpoint is nonfinite
    if not all(math.isfinite(class_break) for class_break in class_breaks):
        # Stopping because QGIS cannot render nonfinite class endpoints
        raise ValueError("Classification contains a nonfinite endpoint.")

    # Stopping when any class has zero or negative width
    if any(
        lower_bound >= upper_bound
        for lower_bound, upper_bound in zip(class_breaks, class_breaks[1:])
    ):
        # Stopping because graduated classes must be strictly increasing
        raise ValueError("Classification contains a zero-width or decreasing class.")

    # Stopping when the first endpoint differs from the observed minimum
    if class_breaks[0] != min(values):
        # Stopping because the first observation would not anchor the renderer
        raise ValueError("The first class endpoint differs from the observed minimum.")

    # Stopping when the final endpoint differs from the observed maximum
    if class_breaks[-1] != max(values):
        # Stopping because the last observation would not anchor the renderer
        raise ValueError("The final class endpoint differs from the observed maximum.")

    # Counting observations in every class
    class_observation_counts = [
        count_class_observations(
            values=values,
            lower_bound=class_breaks[class_index],
            upper_bound=class_breaks[class_index + 1],
            is_last_class=(class_index == len(class_colors) - 1),
        )
        for class_index in range(len(class_colors))
    ]

    # Stopping when the classes do not cover every observation exactly once
    if sum(class_observation_counts) != len(values):
        # Stopping because the renderer would omit or duplicate observations
        raise ValueError(
            "Classification does not cover every finite observation exactly once."
        )

    # Returning the validated class observation counts
    return class_observation_counts


# Defining the renderer-color update function
def set_symbol_color(renderer: ET.Element, symbol_name: str, color: str) -> None:
    """Update every stored color option for one renderer symbol."""

    # Defining the symbol
    symbol = renderer.find(f"./symbols/symbol[@name='{symbol_name}']")
    # Stopping when the requested symbol is unavailable
    if symbol is None:
        # Stopping because the renderer range references a missing symbol
        raise RuntimeError(f"Renderer symbol {symbol_name!r} is unavailable.")

    # Reading every color option for the requested symbol
    color_options = symbol.findall(".//Option[@name='color']")

    # Stopping when the requested symbol has no configurable color
    if not color_options:
        # Stopping because the renderer symbol cannot receive the palette
        raise RuntimeError(f"Renderer symbol {symbol_name!r} has no color option.")

    # Processing each option
    for option in color_options:
        # Updating the current stored attribute
        option.set("value", color)


# Defining the renderer-class count function
def set_class_count(renderer: ET.Element, count: int) -> list[ET.Element]:
    """Resize renderer ranges and symbols to the requested class count."""

    # Defining the ranges parent
    ranges_parent = renderer.find("./ranges")
    # Defining the symbols parent
    symbols_parent = renderer.find("./symbols")
    # Checking whether both renderer containers are available
    if ranges_parent is None or symbols_parent is None:
        # Stopping because renderer is missing ranges or symbols
        raise RuntimeError("Renderer is missing ranges or symbols.")

    # Defining the ranges
    ranges = ranges_parent.findall("./range")
    # Defining the symbols
    symbols = symbols_parent.findall("./symbol")
    # Checking the combined requirements for ranges and symbols
    if not ranges or not symbols:
        # Stopping because renderer has no ranges or symbols
        raise RuntimeError("Renderer has no ranges or symbols.")

    # Repeating the operation while the condition holds
    while len(ranges) < count:
        # Defining the new range
        new_range = copy.deepcopy(ranges[-1])
        # Updating the current stored attribute
        new_range.set("symbol", str(len(ranges)))
        # Storing the current result
        ranges_parent.append(new_range)
        # Defining the ranges
        ranges = ranges_parent.findall("./range")

    # Repeating the operation while the condition holds
    while len(symbols) < count:
        # Defining the new symbol
        new_symbol = copy.deepcopy(symbols[-1])
        # Updating the current stored attribute
        new_symbol.set("name", str(len(symbols)))
        # Storing the current result
        symbols_parent.append(new_symbol)
        # Defining the symbols
        symbols = symbols_parent.findall("./symbol")

    # Processing each extra
    for extra in ranges_parent.findall("./range")[count:]:
        # Finalizing the temporary-file operation
        ranges_parent.remove(extra)
    # Processing each extra
    for extra in symbols_parent.findall("./symbol")[count:]:
        # Finalizing the temporary-file operation
        symbols_parent.remove(extra)

    # Reading the final renderer range collection
    ranges = ranges_parent.findall("./range")

    # Reading the final renderer symbol collection
    symbols = symbols_parent.findall("./symbol")

    # Normalizing every range and symbol identifier
    for class_index, (range_node, symbol_node) in enumerate(zip(ranges, symbols)):
        # Defining the normalized symbol identifier
        symbol_name = str(class_index)

        # Linking the renderer range to the normalized symbol
        range_node.set(
            "symbol",
            symbol_name,
        )

        # Renaming the renderer symbol consistently
        symbol_node.set(
            "name",
            symbol_name,
        )

    # Returning the normalized renderer ranges
    return ranges


################################################################################
##### V. Symbology update
################################################################################


# Defining the main land-use-symbology update function
def main() -> None:
    """Update land-use classes and export their audit information."""

    # Creating the symbology-report output directory
    symbology_report_file.parent.mkdir(
        parents=True,
        exist_ok=True,
    )

    # Opening the QGIS project archive
    with zipfile.ZipFile(qgis_project_file, "r") as source_zip:
        # Defining the entries
        entries = {
            entry.filename: source_zip.read(entry.filename)
            for entry in source_zip.infolist()
        }

    # Parsing the QGIS project XML
    root = ET.fromstring(entries["everything.qgs"])
    # Defining the report rows
    report_rows: list[dict[str, object]] = []
    # Defining the updated layers
    updated_layers = 0

    # Initializing the collection of updated layer names
    updated_layer_names: set[str] = set()

    # Processing each map layer
    for map_layer in root.findall("./projectlayers/maplayer"):
        # Defining the name
        name = map_layer.findtext("layername") or ""
        # Defining the datasource
        datasource = (map_layer.findtext("datasource") or "").replace(
            "\\",
            "/",
        )
        # Handling the absence of startswith
        if not name.startswith(layer_name_prefix):
            # Skipping to the next iteration
            continue
        # Skipping layers outside the land-use result source
        if not datasource.startswith(layer_source_prefix):
            # Skipping to the next iteration
            continue

        # Defining the renderer
        renderer = map_layer.find("renderer-v2")
        # Checking the combined requirements for renderer
        if renderer is None or renderer.get("type") != "graduatedSymbol":
            # Skipping to the next iteration
            continue

        # Defining the field
        field = renderer.get("attr")
        # Handling the absence of field
        if not field:
            # Skipping to the next iteration
            continue

        # Extracting the physical Parquet source path
        parquet_relative_path = datasource.split(
            "|",
            1,
        )[0]

        # Resolving the physical Parquet input file
        parquet_input_file = (
            qgis_project_file.parent / parquet_relative_path
        ).resolve()

        # Stopping when the layer source differs from the configured result file
        if parquet_input_file != land_use_results_input_file.resolve():
            # Stopping because the XML and script would classify different data
            raise RuntimeError(
                f"Layer {name!r} points to {parquet_input_file}, not "
                f"{land_use_results_input_file.resolve()}."
            )

        # Calculating the result with numeric values
        values = read_numeric_values(
            parquet_input_file=parquet_input_file,
            field_name=field,
        )
        # Defining the method and breaks and colors
        method, breaks, colors = classify_values(values)

        # Validating exact classification coverage before changing the renderer
        class_observation_counts = validate_classification(
            values=values,
            class_breaks=breaks,
            class_colors=colors,
        )

        # Defining the ranges
        ranges = set_class_count(renderer, len(colors))

        # Processing each index and range node
        for index, range_node in enumerate(ranges):
            # Defining the lower
            lower = breaks[index]
            # Defining the upper
            upper = breaks[index + 1]
            # Defining the lower text
            lower_text = repr(float(lower))
            # Defining the upper text
            upper_text = repr(float(upper))
            # Updating the current stored attribute
            range_node.set("lower", lower_text)
            # Updating the current stored attribute
            range_node.set("upper", upper_text)
            # Updating the current stored attribute
            range_node.set(
                "label",
                f"{format_class_label_number(lower)} - "
                f"{format_class_label_number(upper)}",
            )
            # Defining the symbol name
            symbol_name = range_node.get("symbol", str(index))
            # Applying the set symbol color operation to the current object
            set_symbol_color(renderer, symbol_name, colors[index])
            # Storing the current result
            report_rows.append(
                {
                    "layer": name,
                    "attribute": field,
                    "method": method,
                    "class": index + 1,
                    "lower": lower_text,
                    "upper": upper_text,
                    "label": range_node.get("label", ""),
                    "color_rgba": colors[index],
                    "observations": class_observation_counts[index],
                }
            )

        # Updating the updated layers
        updated_layers += 1

        # Recording the updated layer name
        updated_layer_names.add(name)

    # Comparing updated layers with the expected value
    if (
        updated_layers != expected_layer_count
        or len(updated_layer_names) != expected_layer_count
    ):
        # Stopping because the required validation condition is not met
        raise RuntimeError(
            f"Updated {updated_layers} land-use layer entries and "
            f"{len(updated_layer_names)} unique names; expected "
            f"{expected_layer_count} of each."
        )

    # Defining the entries
    entries["everything.qgs"] = ET.tostring(
        root, encoding="utf-8", xml_declaration=True
    )

    # Creating the temporary QGIS project archive
    with tempfile.NamedTemporaryFile(
        delete=False, suffix=".qgz", dir=qgis_project_file.parent
    ) as tmp:
        # Defining the tmp path
        tmp_path = Path(tmp.name)

    # Writing the updated project through an atomic replacement
    try:
        # Opening the QGIS project archive
        with zipfile.ZipFile(
            tmp_path, "w", compression=zipfile.ZIP_DEFLATED
        ) as output_zip:
            # Processing each filename and content
            for filename, content in entries.items():
                # Writing the current output content
                output_zip.writestr(filename, content)
        # Finalizing the temporary-file operation
        tmp_path.replace(qgis_project_file)
    finally:
        # Checking the result of exists
        if tmp_path.exists():
            # Finalizing the temporary-file operation
            tmp_path.unlink()

    # Defining the fieldnames
    fieldnames = [
        "layer",
        "attribute",
        "method",
        "class",
        "lower",
        "upper",
        "label",
        "color_rgba",
        "observations",
    ]

    # Sorting report rows for deterministic output
    report_rows.sort(
        key=lambda record: (
            record["layer"],
            int(record["class"]),
        )
    )
    # Opening the configured report output file
    with symbology_report_file.open("w", newline="", encoding="utf-8") as handle:
        # Creating the CSV report writer
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        # Writing the current output content
        writer.writeheader()
        # Writing the current output content
        writer.writerows(report_rows)

    # Reporting the current result
    print(f"Updated {updated_layers} layers.")
    # Reporting the current result
    print(f"Wrote {symbology_report_file}")


################################################################################
##### VI. Execution
################################################################################

# Running the script during whole-file execution
if __name__ == "__main__":
    # Running the main script workflow
    main()
