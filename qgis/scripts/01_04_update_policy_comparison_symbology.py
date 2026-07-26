################################################################################
##################################            ##################################
####################### 01.04) UPDATE POLICY COMPARISON ########################
##################################            ##################################
################################################################################

# This script applies the policy-comparison categories to the corresponding
# QGIS layer and exports a record of colors and observation counts.

################################################################################
##### I. Packages
################################################################################

# Loading libraries
from __future__ import annotations
from collections import Counter
from pathlib import Path
from xml.etree import ElementTree as ET
import csv
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

# Defining the QGIS project file
qgis_project_file = project_root_directory / "qgis" / "projects" / "everything.qgz"

# Defining the policy-comparison Parquet input file
policy_comparison_input_file = (
    project_root_directory
    / "data"
    / "results"
    / "policy_comparison"
    / "policy_comparison_winner_map.parquet"
)

# Defining the category-report output file
category_report_file = (
    project_root_directory
    / "qgis"
    / "classifications"
    / "policy_comparison_winner_classes_applied.csv"
)


################################################################################
##### III. Parameters
################################################################################

# Defining the policy-comparison layer name
target_layer_name = "Comparação cenários"

# Defining the policy-comparison layer source stored in the QGIS project
target_layer_source = (
    "../../data/results/policy_comparison/"
    "policy_comparison_winner_map.parquet"
    "|layername=policy_comparison_winner_map"
)

# Defining the policy-comparison classification field
classification_field_name = "winner"

# Defining the ordered policy-comparison categories
category_specifications = [
    (
        "0",
        "Vence o transporte",
        "0",
        "0,51,111,255",
    ),
    (
        "1",
        "Vence o adensamento",
        "1",
        "229,208,90,255",
    ),
    (
        "2",
        "Empate",
        "2",
        "113,116,115,255",
    ),
]


################################################################################
##### IV. Functions
################################################################################


# Defining the symbol-color update function
def update_symbol_color(
    renderer_node: ET.Element,
    symbol_name: str,
    color_rgba: str,
) -> None:
    """Update every color option associated with one renderer symbol."""

    # Locating the requested renderer symbol
    symbol_node = renderer_node.find(f"./symbols/symbol[@name='{symbol_name}']")

    # Stopping when the requested symbol is unavailable
    if symbol_node is None:
        # Stopping because the category references a missing symbol
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


################################################################################
##### V. Symbology update
################################################################################


# Defining the main policy-comparison update function
def main() -> None:
    """Apply policy-comparison categories and export their audit report."""

    # Creating the category-report output directory
    category_report_file.parent.mkdir(
        parents=True,
        exist_ok=True,
    )

    # Reading policy-comparison outcomes
    winner_values = (
        pq.read_table(
            source=policy_comparison_input_file,
            columns=[classification_field_name],
        )
        .column(classification_field_name)
        .to_pylist()
    )

    # Counting observations by policy-comparison outcome
    winner_counts = Counter(winner_values)

    # Defining the expected policy-comparison outcomes
    expected_winner_values = {
        category_label for _, category_label, _, _ in category_specifications
    }

    # Defining the observed policy-comparison outcomes
    observed_winner_values = set(winner_counts)

    # Stopping when the data contain missing or unexpected outcomes
    if observed_winner_values != expected_winner_values:
        # Stopping because renderer categories must match the data exactly
        raise ValueError(
            f"Observed winner values {sorted(map(str, observed_winner_values))} "
            f"differ from expected values {sorted(expected_winner_values)}."
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

    # Initializing the updated-layer counter
    updated_layer_count = 0

    # Initializing the category-report records
    report_records: list[dict[str, object]] = []

    # Inspecting every map layer in the QGIS project
    for map_layer in project_xml_root.findall("./projectlayers/maplayer"):
        # Reading the current layer name
        layer_name = map_layer.findtext("layername") or ""

        # Reading the current layer source
        layer_source = (map_layer.findtext("datasource") or "").replace(
            "\\",
            "/",
        )

        # Skipping layers unrelated to the policy comparison
        if (
            layer_name != target_layer_name
            and "policy_comparison_winner_map" not in layer_source
        ):
            # Skipping to the next iteration
            continue

        # Locating the categorized renderer
        renderer_node = map_layer.find("renderer-v2")

        # Stopping when the target layer is not categorized
        if renderer_node is None or renderer_node.get("type") != "categorizedSymbol":
            # Stopping when the target layer is not categorized
            raise RuntimeError(
                "policy_comparison_winner_map is not using " "categorized symbology."
            )

        # Setting the category classification field
        renderer_node.set(
            "attr",
            classification_field_name,
        )

        # Locating the map-layer data-source node
        layer_source_node = map_layer.find("datasource")

        # Stopping when the target layer has no data-source node
        if layer_source_node is None:
            # Stopping because the portable layer source cannot be stored
            raise RuntimeError("Policy-comparison layer has no datasource node.")

        # Updating the layer to the versioned policy-comparison input
        layer_source_node.text = target_layer_source

        # Locating the renderer category container
        categories_node = renderer_node.find("./categories")

        # Stopping when the renderer category container is unavailable
        if categories_node is None:
            # Stopping because renderer has no categories node
            raise RuntimeError("Renderer has no categories node.")

        # Reading existing category nodes
        category_nodes = categories_node.findall("./category")

        # Locating the renderer symbol container
        symbols_node = renderer_node.find("./symbols")

        # Stopping when the renderer symbol container is unavailable
        if symbols_node is None:
            # Stopping because categorized rendering requires stored symbols
            raise RuntimeError("Renderer has no symbols node.")

        # Reading existing renderer symbols
        symbol_nodes = symbols_node.findall("./symbol")

        # Stopping when fewer categories exist than required
        if len(category_nodes) < len(category_specifications) or len(
            symbol_nodes
        ) < len(category_specifications):
            # Stopping because the renderer has too few reusable entries
            raise RuntimeError(
                "Renderer has fewer categories or symbols than expected."
            )

        # Applying each ordered category specification
        for category_index, (
            category_value,
            category_label,
            symbol_name,
            color_rgba,
        ) in enumerate(category_specifications):
            # Selecting the current category node
            category_node = category_nodes[category_index]

            # Selecting the current symbol node
            symbol_node = symbol_nodes[category_index]

            # Normalizing the current renderer symbol name
            symbol_node.set(
                "name",
                symbol_name,
            )

            # Updating the stored category value
            category_node.set(
                "value",
                category_value,
            )

            # Updating the visible category label
            category_node.set(
                "label",
                category_label,
            )

            # Linking the requested renderer symbol
            category_node.set(
                "symbol",
                symbol_name,
            )

            # Enabling category rendering
            category_node.set(
                "render",
                "true",
            )

            # Updating the linked symbol color
            update_symbol_color(
                renderer_node=renderer_node,
                symbol_name=symbol_name,
                color_rgba=color_rgba,
            )

            # Recording the category audit information
            report_records.append(
                {
                    "layer": layer_name,
                    "attribute": classification_field_name,
                    "value": category_value,
                    "data_value": category_label,
                    "label": category_label,
                    "symbol": symbol_name,
                    "color_rgba": color_rgba,
                    "observations": winner_counts.get(
                        category_label,
                        0,
                    ),
                }
            )

        # Removing obsolete extra categories
        for extra_category in category_nodes[len(category_specifications) :]:
            # Removing the current extra category
            categories_node.remove(extra_category)

        # Removing obsolete extra symbols
        for extra_symbol in symbol_nodes[len(category_specifications) :]:
            # Removing the current extra symbol
            symbols_node.remove(extra_symbol)

        # Incrementing the updated-layer counter
        updated_layer_count += 1

    # Stopping unless exactly one target layer was updated
    if updated_layer_count != 1:
        # Stopping because the target layer must be unique
        raise RuntimeError(
            f"Updated {updated_layer_count} policy-comparison layers, expected 1."
        )

    # Stopping when category counts do not cover every input row
    if sum(winner_counts.values()) != len(winner_values):
        # Stopping because the category audit is internally inconsistent
        raise RuntimeError("Policy-comparison category counts are inconsistent.")

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
        # Storing the temporary archive path
        temporary_project_file = Path(temporary_handle.name)

    # Writing and replacing the project archive atomically
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

        # Replacing the existing QGIS project
        temporary_project_file.replace(qgis_project_file)

    # Removing any unused temporary archive
    finally:
        # Checking the result of exists
        if temporary_project_file.exists():
            # Removing the remaining temporary archive
            temporary_project_file.unlink()

    # Sorting report records by the declared category order
    report_records.sort(
        key=lambda record: next(
            index
            for index, specification in enumerate(category_specifications)
            if specification[0] == record["value"]
        )
    )

    # Defining the ordered report fields
    report_fields = [
        "layer",
        "attribute",
        "value",
        "data_value",
        "label",
        "symbol",
        "color_rgba",
        "observations",
    ]

    # Opening the category-report output file
    with category_report_file.open(
        "w",
        newline="",
        encoding="utf-8",
    ) as report_handle:
        # Creating the category-report CSV writer
        report_writer = csv.DictWriter(
            report_handle,
            fieldnames=report_fields,
        )

        # Writing the category-report header
        report_writer.writeheader()

        # Writing every category-report record
        report_writer.writerows(report_records)

    # Reporting successful layer updating
    print("Updated policy comparison winner categories.")

    # Reporting the category audit output file
    print(f"Wrote {category_report_file}")


################################################################################
##### VI. Execution
################################################################################

# Running the script during whole-file execution
if __name__ == "__main__":
    # Running the main script workflow
    main()
