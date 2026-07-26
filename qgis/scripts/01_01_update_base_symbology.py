################################################################################
##################################            ##################################
######################### 01.01) UPDATE BASE SYMBOLOGY #########################
##################################            ##################################
################################################################################

# This script recalculates quantile classes for the baseline result layers,
# updates their QGIS renderers and exports an auditable class report.

################################################################################
##### I. Packages
################################################################################

# Loading libraries
from __future__ import annotations
from pathlib import Path
from xml.etree import ElementTree as ET
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

# Defining the symbology audit output file
symbology_report_file = (
    project_root_directory
    / "qgis"
    / "classifications"
    / "base_results_symbology_classes.csv"
)


################################################################################
##### III. Parameters
################################################################################

# Defining the baseline-layer name prefix
layer_name_prefix = "Base "

# Defining the baseline-layer data-source prefix
layer_source_prefix = "../../data/results/baseline_scenario/"

# Defining the expected number of baseline result layers
expected_layer_count = 11


################################################################################
##### IV. Functions
################################################################################


# Defining the numeric-value reading function
def read_numeric_values(
    parquet_input_file: Path,
    field_name: str,
) -> list[float]:
    """Read and sort finite values from one Parquet column."""

    # Reading the selected Parquet column
    parquet_table = pq.read_table(
        source=parquet_input_file,
        columns=[field_name],
    )

    # Extracting values from the selected column
    column_values = parquet_table.column(field_name).to_pylist()

    # Restricting the column to finite numeric values
    numeric_values = sorted(
        float(value)
        for value in column_values
        if value is not None and math.isfinite(float(value))
    )

    # Stopping when the selected field contains no finite observations
    if not numeric_values:
        # Stopping because an empty field cannot be classified
        raise ValueError(f"Field {field_name!r} has no finite observations.")

    # Returning the sorted numeric values
    return numeric_values


# Defining the linear quantile function
def calculate_quantile(
    sorted_values: list[float],
    probability: float,
) -> float:
    """Calculate a linearly interpolated empirical quantile."""

    # Stopping when the numeric vector is empty
    if not sorted_values:
        # Stopping because cannot classify an empty vector
        raise ValueError("Cannot classify an empty vector.")

    # Returning the only value when the vector has length one
    if len(sorted_values) == 1:
        # Returning the sorted values
        return sorted_values[0]

    # Calculating the fractional quantile position
    quantile_position = probability * (len(sorted_values) - 1)

    # Calculating the lower interpolation index
    lower_index = math.floor(quantile_position)

    # Calculating the upper interpolation index
    upper_index = math.ceil(quantile_position)

    # Returning an observed value when interpolation is unnecessary
    if lower_index == upper_index:
        # Returning the sorted values
        return sorted_values[lower_index]

    # Calculating the upper-value interpolation weight
    upper_weight = quantile_position - lower_index

    # Interpolating the requested quantile
    quantile_value = (
        sorted_values[lower_index] * (1 - upper_weight)
        + sorted_values[upper_index] * upper_weight
    )

    # Returning the interpolated quantile
    return quantile_value


# Defining the class-label formatting function
def format_class_label_number(
    value: float,
) -> str:
    """Format one class endpoint with an adaptive decimal precision."""

    # Calculating the absolute endpoint value
    absolute_value = abs(value)

    # Formatting values of at least one hundred without decimals
    if absolute_value >= 100:
        # Defining the formatted value
        formatted_value = f"{value:.0f}"

    # Formatting values of at least ten with two decimals
    elif absolute_value >= 10:
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

    # Removing unnecessary trailing decimal zeros
    trimmed_value = formatted_value.rstrip("0").rstrip(".")

    # Converting the decimal separator for the map legend
    label_value = trimmed_value.replace(
        ".",
        ",",
    )

    # Returning the formatted label endpoint
    return label_value


# Defining the class-observation counting function
def count_class_observations(
    values: list[float],
    lower_bound: float,
    upper_bound: float,
    is_last_class: bool,
) -> int:
    """Count values covered by one graduated renderer class."""

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
) -> list[int]:
    """Validate exact coverage and return observations in every class."""

    # Stopping when fewer than two class endpoints are available
    if len(class_breaks) < 2:
        # Stopping because at least one graduated class is required
        raise ValueError("Classification requires at least two endpoints.")

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
            is_last_class=(class_index == len(class_breaks) - 2),
        )
        for class_index in range(len(class_breaks) - 1)
    ]

    # Stopping when the classes do not cover every observation exactly once
    if sum(class_observation_counts) != len(values):
        # Stopping because the renderer would omit or duplicate observations
        raise ValueError(
            "Classification does not cover every finite observation exactly once."
        )

    # Returning the validated class observation counts
    return class_observation_counts


# Defining the renderer-color extraction function
def extract_symbol_color(
    renderer_node: ET.Element,
    symbol_name: str,
) -> str:
    """Extract the stored RGBA color for one renderer symbol."""

    # Defining the symbol search expression
    symbol_xpath = f"./symbols/symbol[@name='{symbol_name}']"

    # Locating the requested symbol
    symbol_node = renderer_node.find(symbol_xpath)

    # Stopping when the requested symbol is unavailable
    if symbol_node is None:
        # Stopping because the renderer range references a missing symbol
        raise RuntimeError(f"Renderer symbol {symbol_name!r} is unavailable.")

    # Locating the symbol color option
    color_option = symbol_node.find(".//Option[@name='color']")

    # Stopping when the requested symbol has no configurable color
    if color_option is None:
        # Stopping because the renderer symbol has no auditable fill color
        raise RuntimeError(f"Renderer symbol {symbol_name!r} has no color option.")

    # Reading the stored color value
    stored_color = color_option.get(
        "value",
        "",
    )

    # Extracting the RGBA component
    color_rgba = stored_color.split(
        ",rgb:",
        1,
    )[0]

    # Returning the RGBA color
    return color_rgba


################################################################################
##### V. Symbology update
################################################################################


# Defining the main symbology update function
def main() -> None:
    """Update baseline graduated classes and export their audit report."""

    # Creating the symbology-report output directory
    symbology_report_file.parent.mkdir(
        parents=True,
        exist_ok=True,
    )

    # Defining the QGIS project directory
    qgis_project_directory = qgis_project_file.parent

    # Reading every file stored in the QGIS project archive
    with zipfile.ZipFile(
        qgis_project_file,
        "r",
    ) as source_archive:
        # Reading the project XML bytes
        project_xml_bytes = source_archive.read("everything.qgs")

        # Preserving every archived project entry
        project_payload = {
            entry.filename: source_archive.read(entry.filename)
            for entry in source_archive.infolist()
        }

    # Parsing the QGIS project XML
    project_xml_root = ET.fromstring(project_xml_bytes)

    # Initializing the class-report records
    report_records: list[dict[str, object]] = []

    # Initializing the updated-layer counter
    updated_layer_count = 0

    # Initializing the collection of updated layer names
    updated_layer_names: set[str] = set()

    # Processing each map layer in the QGIS project
    for map_layer in project_xml_root.findall("./projectlayers/maplayer"):
        # Reading the map-layer name
        layer_name = map_layer.findtext("layername") or ""

        # Reading the map-layer data source
        layer_source = (map_layer.findtext("datasource") or "").replace(
            "\\",
            "/",
        )

        # Skipping layers outside the baseline group
        if not layer_name.startswith(layer_name_prefix):
            # Skipping to the next iteration
            continue

        # Skipping baseline layers outside the result directory
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

        # Reading the existing renderer ranges
        range_nodes = renderer_node.findall("./ranges/range")

        # Skipping renderers without class ranges
        if not range_nodes:
            # Skipping to the next iteration
            continue

        # Extracting the physical Parquet source path
        parquet_relative_path = layer_source.split(
            "|",
            1,
        )[0]

        # Resolving the physical Parquet input file
        parquet_input_file = (qgis_project_directory / parquet_relative_path).resolve()

        # Reading finite values from the classification field
        numeric_values = read_numeric_values(
            parquet_input_file=parquet_input_file,
            field_name=field_name,
        )

        # Counting existing renderer classes
        class_total = len(range_nodes)

        # Calculating quantile breaks for all class endpoints
        class_breaks = [
            calculate_quantile(
                sorted_values=numeric_values,
                probability=class_index / class_total,
            )
            for class_index in range(class_total + 1)
        ]

        # Validating exact classification coverage before changing the renderer
        class_observation_counts = validate_classification(
            values=numeric_values,
            class_breaks=class_breaks,
        )

        # Updating every renderer class
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

            # Reading the validated observation count
            observation_count = class_observation_counts[class_index]

            # Recording the current class audit information
            report_records.append(
                {
                    "layer": layer_name,
                    "source": str(
                        parquet_input_file.relative_to(project_root_directory)
                    ),
                    "attribute": field_name,
                    "class_index": class_index + 1,
                    "classes": class_total,
                    "lower": lower_text,
                    "upper": upper_text,
                    "label": class_label,
                    "color_rgba": extract_symbol_color(
                        renderer_node=renderer_node,
                        symbol_name=symbol_name,
                    ),
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
        # Stopping because the baseline layer contract was not satisfied
        raise RuntimeError(
            f"Updated {updated_layer_count} baseline layer entries and "
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
            int(record["class_index"]),
        )
    )

    # Defining the ordered report fields
    report_fields = [
        "layer",
        "source",
        "attribute",
        "class_index",
        "classes",
        "lower",
        "upper",
        "label",
        "color_rgba",
        "observations",
    ]

    # Opening the class-report output file
    with symbology_report_file.open(
        "w",
        newline="",
        encoding="utf-8",
    ) as report_handle:
        # Creating the class-report CSV writer
        report_writer = csv.DictWriter(
            report_handle,
            fieldnames=report_fields,
        )

        # Writing the class-report header
        report_writer.writeheader()

        # Writing all class-report records
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
