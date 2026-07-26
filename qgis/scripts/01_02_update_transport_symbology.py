################################################################################
##################################            ##################################
###################### 01.02) UPDATE TRANSPORT SYMBOLOGY #######################
##################################            ##################################
################################################################################

# This script recalculates adaptive, zero-centered classes for the eleven
# transport-scenario result layers and exports their class audit report.

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

# Defining the transport-scenario Parquet input file
transport_results_input_file = (
    project_root_directory
    / "data"
    / "results"
    / "transport_scenario"
    / "transport_variation.parquet"
)

# Defining the transport-symbology audit output file
symbology_report_file = (
    project_root_directory
    / "qgis"
    / "classifications"
    / "transport_scenario_classes_complete.csv"
)


################################################################################
##### III. Parameters
################################################################################

# Defining the transport-layer name prefix
layer_name_prefix = "Transporte "

# Defining the transport-layer data-source prefix
layer_source_prefix = "../../data/results/transport_scenario/"

# Defining the expected number of transport result layers
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
    """Read and sort finite values from one transport result column."""

    # Reading the selected transport-result column
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

    # Separating strictly negative values
    negative_values = [value for value in values if value < 0]

    # Separating zero and positive values
    positive_values = [value for value in values if value >= 0]

    # Applying a five-class positive sequence when negatives are absent
    if not negative_values:
        # Returning the calculated result objects
        return (
            "jenks_positive_5_classes",
            calculate_jenks_breaks(
                values=values,
                class_count=5,
            ),
            positive_colors,
        )

    # Applying a five-class negative sequence when positives are absent
    if not positive_values:
        # Returning the calculated result objects
        return (
            "jenks_negative_5_classes",
            calculate_jenks_breaks(
                values=values,
                class_count=5,
            ),
            negative_colors,
        )

    # Applying a one-sided exception when one sign is scarce
    if (
        min(
            len(negative_values),
            len(positive_values),
        )
        < 15
    ):
        # Applying one negative class when negative values are scarce
        if len(negative_values) < len(positive_values):
            # Combining one negative class with five positive classes
            class_breaks = [
                min(negative_values),
                0.0,
            ] + calculate_jenks_breaks(
                values=positive_values,
                class_count=5,
            )[1:]

            # Returning the negative-exception classification
            return (
                "one_negative_plus_jenks_positive_6_classes",
                class_breaks,
                [negative_colors[-1]] + positive_colors,
            )

        # Combining five negative classes with one positive class
        class_breaks = calculate_jenks_breaks(
            values=negative_values,
            class_count=5,
        )[:-1] + [
            0.0,
            max(positive_values),
        ]

        # Returning the positive-exception classification
        return (
            "jenks_negative_5_plus_one_positive_6_classes",
            class_breaks,
            negative_colors + [single_positive_color],
        )

    # Combining five negative and five positive Jenks classes
    class_breaks = (
        calculate_jenks_breaks(
            values=negative_values,
            class_count=5,
        )[:-1]
        + [0.0]
        + calculate_jenks_breaks(
            values=positive_values,
            class_count=5,
        )[1:]
    )

    # Returning the general zero-centered classification
    return (
        "jenks_by_sign_10_classes",
        class_breaks,
        negative_colors + positive_colors,
    )


# Defining the class-label formatting function
def format_class_label_number(
    value: float,
) -> str:
    """Format one class endpoint for the visible map legend."""

    # Calculating the absolute endpoint value
    absolute_value = abs(value)

    # Formatting values of at least ten with two decimals
    if absolute_value >= 10:
        # Defining the formatted value
        formatted_value = f"{value:.2f}"

    # Formatting values of at least one with three decimals
    elif absolute_value >= 1:
        # Defining the formatted value
        formatted_value = f"{value:.3f}"

    # Formatting values below one with four decimals
    else:
        # Defining the formatted value
        formatted_value = f"{value:.4f}"

    # Removing unnecessary decimal zeros
    trimmed_value = formatted_value.rstrip("0").rstrip(".")

    # Converting the decimal separator for the map legend
    label_value = trimmed_value.replace(
        ".",
        ",",
    )

    # Returning the formatted endpoint
    return label_value


# Defining the class-observation counting function
def count_class_observations(
    values: list[float],
    lower_bound: float,
    upper_bound: float,
    is_last_class: bool,
) -> int:
    """Count observations covered by one renderer class."""

    # Counting the final class with an inclusive upper bound
    if is_last_class:
        # Defining the observation count
        observation_count = sum(lower_bound <= value <= upper_bound for value in values)

    # Counting other classes with an exclusive upper bound
    else:
        # Defining the observation count
        observation_count = sum(lower_bound <= value < upper_bound for value in values)

    # Returning the class observation count
    return observation_count


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
def update_symbol_color(
    renderer_node: ET.Element,
    symbol_name: str,
    color_rgba: str,
) -> None:
    """Update every stored color option for one renderer symbol."""

    # Locating the requested renderer symbol
    symbol_node = renderer_node.find(f"./symbols/symbol[@name='{symbol_name}']")

    # Stopping when the requested symbol is unavailable
    if symbol_node is None:
        # Stopping because the renderer range references a missing symbol
        raise RuntimeError(f"Renderer symbol {symbol_name!r} is unavailable.")

    # Reading every color option for the requested symbol
    color_options = symbol_node.findall(".//Option[@name='color']")

    # Stopping when the requested symbol has no configurable color
    if not color_options:
        # Stopping because the renderer symbol cannot receive the palette
        raise RuntimeError(f"Renderer symbol {symbol_name!r} has no color option.")

    # Updating every color option for the requested symbol
    for color_option in color_options:
        # Storing the requested RGBA color
        color_option.set(
            "value",
            color_rgba,
        )


# Defining the renderer-class count function
def set_renderer_class_count(
    renderer_node: ET.Element,
    class_count: int,
) -> list[ET.Element]:
    """Resize renderer ranges and symbols to the requested class count."""

    # Locating the renderer range container
    ranges_node = renderer_node.find("./ranges")

    # Locating the renderer symbol container
    symbols_node = renderer_node.find("./symbols")

    # Stopping when either renderer container is unavailable
    if ranges_node is None or symbols_node is None:
        # Stopping because renderer is missing ranges or symbols
        raise RuntimeError("Renderer is missing ranges or symbols.")

    # Reading existing renderer ranges
    range_nodes = ranges_node.findall("./range")

    # Reading existing renderer symbols
    symbol_nodes = symbols_node.findall("./symbol")

    # Stopping when the renderer has no reusable classes
    if not range_nodes or not symbol_nodes:
        # Stopping because renderer has no ranges or symbols
        raise RuntimeError("Renderer has no ranges or symbols.")

    # Extending renderer ranges to the requested count
    while len(range_nodes) < class_count:
        # Copying the final existing range
        new_range_node = copy.deepcopy(range_nodes[-1])

        # Assigning the next symbol index
        new_range_node.set(
            "symbol",
            str(len(range_nodes)),
        )

        # Appending the copied renderer range
        ranges_node.append(new_range_node)

        # Refreshing the renderer range collection
        range_nodes = ranges_node.findall("./range")

    # Extending renderer symbols to the requested count
    while len(symbol_nodes) < class_count:
        # Copying the final existing symbol
        new_symbol_node = copy.deepcopy(symbol_nodes[-1])

        # Assigning the next symbol name
        new_symbol_node.set(
            "name",
            str(len(symbol_nodes)),
        )

        # Appending the copied renderer symbol
        symbols_node.append(new_symbol_node)

        # Refreshing the renderer symbol collection
        symbol_nodes = symbols_node.findall("./symbol")

    # Removing renderer ranges beyond the requested count
    for extra_range in ranges_node.findall("./range")[class_count:]:
        # Removing the current extra range
        ranges_node.remove(extra_range)

    # Removing renderer symbols beyond the requested count
    for extra_symbol in symbols_node.findall("./symbol")[class_count:]:
        # Removing the current extra symbol
        symbols_node.remove(extra_symbol)

    # Reading the final renderer range collection
    range_nodes = ranges_node.findall("./range")

    # Reading the final renderer symbol collection
    symbol_nodes = symbols_node.findall("./symbol")

    # Normalizing every range and symbol identifier
    for class_index, (range_node, symbol_node) in enumerate(
        zip(range_nodes, symbol_nodes)
    ):
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
    return range_nodes


################################################################################
##### V. Symbology update
################################################################################


# Defining the main transport-symbology update function
def main() -> None:
    """Update transport classes and export their audit information."""

    # Creating the symbology-report output directory
    symbology_report_file.parent.mkdir(
        parents=True,
        exist_ok=True,
    )

    # Reading every entry from the QGIS project archive
    with zipfile.ZipFile(
        qgis_project_file,
        "r",
    ) as source_archive:
        # Preserving every archived project entry
        project_payload = {
            entry.filename: source_archive.read(entry.filename)
            for entry in source_archive.infolist()
        }

    # Parsing the QGIS project XML
    project_xml_root = ET.fromstring(project_payload["everything.qgs"])

    # Initializing the class-report records
    report_records: list[dict[str, object]] = []

    # Initializing the updated-layer counter
    updated_layer_count = 0

    # Initializing the collection of updated layer names
    updated_layer_names: set[str] = set()

    # Processing every map layer in the QGIS project
    for map_layer in project_xml_root.findall("./projectlayers/maplayer"):
        # Reading the current layer name
        layer_name = map_layer.findtext("layername") or ""

        # Reading the current layer source
        layer_source = (map_layer.findtext("datasource") or "").replace(
            "\\",
            "/",
        )

        # Skipping layers outside the transport group
        if not layer_name.startswith(layer_name_prefix):
            # Skipping to the next iteration
            continue

        # Skipping layers outside the transport result source
        if not layer_source.startswith(layer_source_prefix):
            # Skipping to the next iteration
            continue

        # Locating the graduated renderer
        renderer_node = map_layer.find("renderer-v2")

        # Skipping layers without a graduated renderer
        if renderer_node is None or renderer_node.get("type") != "graduatedSymbol":
            # Skipping to the next iteration
            continue

        # Reading the renderer classification field
        field_name = renderer_node.get("attr")

        # Skipping renderers without a classification field
        if not field_name:
            # Skipping to the next iteration
            continue

        # Extracting the physical Parquet source path
        parquet_relative_path = layer_source.split(
            "|",
            1,
        )[0]

        # Resolving the physical Parquet input file
        parquet_input_file = (
            qgis_project_file.parent / parquet_relative_path
        ).resolve()

        # Stopping when the layer source differs from the configured result file
        if parquet_input_file != transport_results_input_file.resolve():
            # Stopping because the XML and script would classify different data
            raise RuntimeError(
                f"Layer {layer_name!r} points to {parquet_input_file}, not "
                f"{transport_results_input_file.resolve()}."
            )

        # Reading finite classification values
        numeric_values = read_numeric_values(
            parquet_input_file=parquet_input_file,
            field_name=field_name,
        )

        # Selecting the adaptive classification
        (
            classification_method,
            class_breaks,
            class_colors,
        ) = classify_values(values=numeric_values)

        # Validating exact classification coverage before changing the renderer
        class_observation_counts = validate_classification(
            values=numeric_values,
            class_breaks=class_breaks,
            class_colors=class_colors,
        )

        # Resizing the renderer to the selected class count
        range_nodes = set_renderer_class_count(
            renderer_node=renderer_node,
            class_count=len(class_colors),
        )

        # Updating every selected renderer class
        for class_index, range_node in enumerate(range_nodes):
            # Reading the current lower class endpoint
            lower_bound = class_breaks[class_index]

            # Reading the current upper class endpoint
            upper_bound = class_breaks[class_index + 1]

            # Serializing the lower endpoint exactly
            lower_text = repr(float(lower_bound))

            # Serializing the upper endpoint exactly
            upper_text = repr(float(upper_bound))

            # Updating the renderer lower endpoint
            range_node.set(
                "lower",
                lower_text,
            )

            # Updating the renderer upper endpoint
            range_node.set(
                "upper",
                upper_text,
            )

            # Constructing the visible class label
            class_label = (
                f"{format_class_label_number(lower_bound)} - "
                f"{format_class_label_number(upper_bound)}"
            )

            # Updating the visible class label
            range_node.set(
                "label",
                class_label,
            )

            # Reading the linked renderer symbol name
            symbol_name = range_node.get(
                "symbol",
                str(class_index),
            )

            # Updating the linked renderer symbol color
            update_symbol_color(
                renderer_node=renderer_node,
                symbol_name=symbol_name,
                color_rgba=class_colors[class_index],
            )

            # Reading the validated observation count
            observation_count = class_observation_counts[class_index]

            # Recording the current class audit information
            report_records.append(
                {
                    "layer": layer_name,
                    "attribute": field_name,
                    "method": classification_method,
                    "class": class_index + 1,
                    "lower": lower_text,
                    "upper": upper_text,
                    "label": class_label,
                    "color_rgba": class_colors[class_index],
                    "observations": observation_count,
                }
            )

        # Incrementing the updated-layer counter
        updated_layer_count += 1

        # Recording the updated layer name
        updated_layer_names.add(layer_name)

    # Stopping when the expected layer count was not updated
    if (
        updated_layer_count != expected_layer_count
        or len(updated_layer_names) != expected_layer_count
    ):
        # Stopping because the required validation condition is not met
        raise RuntimeError(
            f"Updated {updated_layer_count} transport layer entries and "
            f"{len(updated_layer_names)} unique names; expected "
            f"{expected_layer_count} of each."
        )

    # Serializing the updated QGIS project XML
    project_payload["everything.qgs"] = ET.tostring(
        project_xml_root,
        encoding="utf-8",
        xml_declaration=True,
    )

    # Creating a temporary QGIS project archive
    with tempfile.NamedTemporaryFile(
        delete=False,
        suffix=".qgz",
        dir=qgis_project_file.parent,
    ) as temporary_handle:
        # Storing the temporary project path
        temporary_project_file = Path(temporary_handle.name)

    # Writing and replacing the QGIS project atomically
    try:
        # Writing the updated project archive
        with zipfile.ZipFile(
            temporary_project_file,
            "w",
            compression=zipfile.ZIP_DEFLATED,
        ) as output_archive:
            # Writing every preserved project entry
            for archive_name, archive_content in project_payload.items():
                # Writing the current project entry
                output_archive.writestr(
                    archive_name,
                    archive_content,
                )

        # Replacing the existing project with the updated archive
        temporary_project_file.replace(qgis_project_file)

    # Removing an unused temporary archive after any failure
    finally:
        # Checking the result of exists
        if temporary_project_file.exists():
            # Removing the remaining temporary archive
            temporary_project_file.unlink()

    # Sorting report records for deterministic output
    report_records.sort(
        key=lambda record: (
            record["layer"],
            int(record["class"]),
        )
    )

    # Defining the ordered report fields
    report_fields = [
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

    # Opening the symbology-report output file
    with symbology_report_file.open(
        "w",
        newline="",
        encoding="utf-8",
    ) as report_handle:
        # Creating the symbology-report CSV writer
        report_writer = csv.DictWriter(
            report_handle,
            fieldnames=report_fields,
        )

        # Writing the report header
        report_writer.writeheader()

        # Writing every class-report record
        report_writer.writerows(report_records)

    # Reporting the number of updated layers
    print(f"Updated {updated_layer_count} layers.")

    # Reporting the audit output file
    print(f"Wrote {symbology_report_file}")


################################################################################
##### VI. Execution
################################################################################

# Running the script during whole-file execution
if __name__ == "__main__":
    # Running the main script workflow
    main()
