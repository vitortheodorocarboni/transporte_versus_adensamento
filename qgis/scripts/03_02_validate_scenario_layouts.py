################################################################################
##################################            ##################################
####################### 03.02) VALIDATE SCENARIO LAYOUTS #######################
##################################            ##################################
################################################################################

# This script validates the ordered contextual and main legend layers in every
# transport and land-use text layout stored in the QGIS project.

################################################################################
##### I. Packages
################################################################################

# Loading libraries
from __future__ import annotations
from pathlib import Path
from xml.etree import ElementTree as ET
import os
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

# Defining the QGIS project input file
qgis_project_file = project_root_directory / "qgis" / "projects" / "everything.qgz"

# Defining the scenario layout-template input files
scenario_template_files = {
    "texto_transporte_": (
        project_root_directory / "qgis" / "templates" / "layout_transport.qpt"
    ),
    "texto_adensamento_": (
        project_root_directory / "qgis" / "templates" / "layout_land_use.qpt"
    ),
}


################################################################################
##### III. Parameters
################################################################################

# Defining expected scenario layouts and their main result layers
expected_layout_layers = {
    "texto_transporte_residentes": "Transporte residentes",
    "texto_transporte_empregos": "Transporte empregos",
    "texto_transporte_preco": "Transporte preço",
    "texto_transporte_salario": "Transporte salário",
    "texto_transporte_renda": "Transporte renda",
    "texto_transporte_produtividade": "Transporte produtividade",
    "texto_transporte_amenidades": "Transporte amenidades",
    "texto_transporte_acessibilidade": "Transporte acessibilidade",
    "texto_transporte_acessibilidade_firmas": "Transporte acessibilidade firmas",
    "texto_transporte_bem_estar": "Transporte bem-estar",
    "texto_transporte_produto": "Transporte produto",
    "texto_adensamento_residentes": "Adensamento residentes",
    "texto_adensamento_empregos": "Adensamento empregos",
    "texto_adensamento_preco": "Adensamento preço",
    "texto_adensamento_salario": "Adensamento salário",
    "texto_adensamento_renda": "Adensamento renda",
    "texto_adensamento_produtividade": "Adensamento produtividade",
    "texto_adensamento_amenidades": "Adensamento amenidades",
    "texto_adensamento_acessibilidade": "Adensamento acessibilidade",
    "texto_adensamento_acessibilidade_firmas": "Adensamento acessibilidade firmas",
    "texto_adensamento_bem_estar": "Adensamento bem-estar",
    "texto_adensamento_produto": "Adensamento produto",
}

# Defining expected contextual legend names and displayed labels by scenario
expected_context_layers = {
    "texto_transporte_": [
        ("Limites municipais", "Limites municipais"),
        ("Limites distritais", "Limites distritais"),
        ("Linhas de metrô e trem", "Linhas de metrô e trem"),
        ("Zonas desconsideradas preto", "Zonas OD desconsideradas"),
        ("Legenda linha 6", "Linha 6-Laranja"),
    ],
    "texto_adensamento_": [
        ("Limites municipais", "Limites municipais"),
        ("Limites distritais", "Limites distritais"),
        ("Linhas de metrô e trem", "Linhas de metrô e trem"),
        ("Zonas desconsideradas preto", "Zonas OD desconsideradas"),
    ],
}

# Defining the expected canonical template layout and main layer
expected_template_layers = {
    "texto_transporte_": (
        "texto_transporte_bem_estar",
        "Transporte bem-estar",
    ),
    "texto_adensamento_": (
        "texto_adensamento_bem_estar",
        "Adensamento bem-estar",
    ),
}

# Defining the expected total number of stored project layouts
expected_project_layout_count = 43


################################################################################
##### IV. Functions
################################################################################


# Defining the project XML reading function
def read_project_xml() -> ET.Element:
    """Read and parse the validated QGS member stored in the project archive."""

    # Opening the QGIS project archive
    with zipfile.ZipFile(
        qgis_project_file,
        "r",
    ) as archive:
        # Reading the first corrupt archive entry, when present
        corrupt_entry = archive.testzip()

        # Stopping when the project archive contains a corrupt entry
        if corrupt_entry is not None:
            # Stopping because layout validation requires a valid archive
            raise RuntimeError(f"Corrupt QGIS archive entry: {corrupt_entry}")

        # Reading the editable project XML
        project_xml = archive.read("everything.qgs")

    # Parsing and returning the complete project XML tree
    return ET.fromstring(project_xml)


# Defining the unique project-layer record extraction function
def project_layer_records(
    project_xml_root: ET.Element,
) -> dict[str, list[dict[str, str]]]:
    """Map displayed layer names to identifiers, sources and providers."""

    # Initializing project-layer records by displayed name
    records: dict[str, list[dict[str, str]]] = {}

    # Processing every stored project map layer
    for map_layer in project_xml_root.findall("./projectlayers/maplayer"):
        # Reading the displayed layer name
        layer_name = map_layer.findtext("layername") or ""

        # Reading the internal QGIS layer identifier
        layer_id = map_layer.findtext("id") or ""

        # Reading the stored layer data source
        layer_source = (map_layer.findtext("datasource") or "").replace(
            "\\",
            "/",
        )

        # Reading the stored layer provider
        layer_provider = map_layer.findtext("provider") or ""

        # Initializing the current layer-name record collection
        records.setdefault(
            layer_name,
            [],
        )

        # Storing the current complete layer record
        records[layer_name].append(
            {
                "id": layer_id,
                "source": layer_source,
                "provider": layer_provider,
            }
        )

    # Returning all project-layer records by displayed name
    return records


# Defining the unique project-layer record selection function
def unique_layer_record(
    records: dict[str, list[dict[str, str]]],
    layer_name: str,
) -> dict[str, str]:
    """Return the unique project-layer record for one displayed name."""

    # Reading every project-layer record with the requested name
    matching_records = records.get(
        layer_name,
        [],
    )

    # Stopping unless the requested project layer is unique
    if len(matching_records) != 1:
        # Stopping because layout references require an unambiguous layer
        raise RuntimeError(
            f"Found {len(matching_records)} project layers named {layer_name!r}, "
            "expected exactly 1."
        )

    # Returning the unique current project-layer record
    return matching_records[0]


# Defining the stored layout extraction function
def stored_layouts(
    project_xml_root: ET.Element,
) -> dict[str, ET.Element]:
    """Map unique stored layout names to their XML elements."""

    # Initializing stored project layouts by name
    layouts: dict[str, ET.Element] = {}

    # Processing every stored project layout
    for layout in project_xml_root.findall("./Layouts/Layout"):
        # Reading the current stored layout name
        layout_name = layout.get(
            "name",
            "",
        )

        # Stopping when a stored layout name occurs more than once
        if layout_name in layouts:
            # Stopping because layout validation would be ambiguous
            raise RuntimeError(f"Duplicate layout name: {layout_name}")

        # Storing the current unique layout element
        layouts[layout_name] = layout

    # Returning all unique stored project layouts
    return layouts


# Defining the legend-node displayed-label extraction function
def displayed_legend_label(legend_node: ET.Element) -> str:
    """Return the customized or fallback visible label for one legend node."""

    # Locating the explicit visible legend-title option
    visible_label_option = legend_node.find(".//Option[@name='legend/title-label']")

    # Returning the explicit visible legend label when present
    if visible_label_option is not None:
        # Reading the explicit visible legend label
        visible_label = visible_label_option.get(
            "value",
            "",
        )

        # Returning the nonempty explicit visible legend label
        if visible_label:
            # Returning the configured visible label
            return visible_label

    # Locating the cached legend-name option
    cached_label_option = legend_node.find(".//Option[@name='cached_name']")

    # Returning the cached legend label when present
    if cached_label_option is not None:
        # Reading the cached legend label
        cached_label = cached_label_option.get(
            "value",
            "",
        )

        # Returning the nonempty cached legend label
        if cached_label:
            # Returning the cached visible label
            return cached_label

    # Returning the displayed project-layer name as the final fallback
    return legend_node.get(
        "name",
        "",
    )


# Defining the scenario-layout structure validation function
def validate_layout_structure(
    layout: ET.Element,
    main_layer_name: str,
    context_specifications: list[tuple[str, str]],
    records: dict[str, list[dict[str, str]]],
) -> list[str]:
    """Return structural validation errors for one scenario layout."""

    # Initializing layout-specific validation errors
    errors: list[str] = []

    # Reading ordered legend layer-tree nodes
    legend_nodes = layout.findall(".//layer-tree-layer")

    # Defining the expected ordered layer names
    expected_layer_names = [
        context_name for context_name, _ in context_specifications
    ] + [main_layer_name]

    # Reading the observed ordered legend layer names
    observed_layer_names = [
        legend_node.get(
            "name",
            "",
        )
        for legend_node in legend_nodes
    ]

    # Recording a legend-order error when names differ
    if observed_layer_names != expected_layer_names:
        # Storing the complete observed and expected name sequences
        errors.append(f"legend names {observed_layer_names} != {expected_layer_names}")

    # Defining the expected ordered displayed labels
    expected_displayed_labels = [
        context_label for _, context_label in context_specifications
    ] + ["Variação (%):"]

    # Reading the observed ordered displayed legend labels
    observed_displayed_labels = [
        displayed_legend_label(legend_node) for legend_node in legend_nodes
    ]

    # Recording a visible-label error when labels differ
    if observed_displayed_labels != expected_displayed_labels:
        # Storing the complete observed and expected label sequences
        errors.append(
            f"legend labels {observed_displayed_labels} != "
            f"{expected_displayed_labels}"
        )

    # Validating every available expected legend node
    for legend_node, layer_name in zip(
        legend_nodes,
        expected_layer_names,
    ):
        # Reading the unique current project-layer record
        layer_record = unique_layer_record(
            records=records,
            layer_name=layer_name,
        )

        # Defining legend-node metadata expected from the project layer
        expected_metadata = {
            "id": layer_record["id"],
            "source": layer_record["source"],
            "providerKey": layer_record["provider"],
        }

        # Processing each required legend-node metadata field
        for attribute_name, expected_value in expected_metadata.items():
            # Reading the current stored legend-node metadata value
            observed_value = legend_node.get(
                attribute_name,
                "",
            ).replace(
                "\\",
                "/",
            )

            # Recording a metadata mismatch
            if observed_value != expected_value:
                # Storing the detailed metadata validation error
                errors.append(
                    f"{layer_name}: {attribute_name} {observed_value!r} "
                    f"!= {expected_value!r}"
                )

    # Reading all layout items with nonempty UUIDs
    layout_item_uuids = [
        layout_item.get(
            "uuid",
            "",
        )
        for layout_item in layout.findall(".//LayoutItem")
        if layout_item.get("uuid")
    ]

    # Recording an error when layout-item UUIDs are duplicated internally
    if len(layout_item_uuids) != len(set(layout_item_uuids)):
        # Storing the duplicated layout-item UUID error
        errors.append("duplicate LayoutItem UUIDs within layout")

    # Reading map layout items
    map_items = layout.findall(".//LayoutItem[@type='65639']")

    # Recording an error unless exactly one map item is stored
    if len(map_items) != 1:
        # Storing the observed map-item count
        errors.append(f"map item count {len(map_items)} != 1")

    # Validating the current visibility-mode contract when one map exists
    if len(map_items) == 1 and map_items[0].get("keepLayerSet") != "false":
        # Recording the contract delegated to the export-stage configuration
        errors.append("map keepLayerSet must remain false before export configuration")

    # Returning every layout-specific validation error
    return errors


################################################################################
##### V. Layout validation
################################################################################


# Defining the main scenario-layout validation function
def main() -> int:
    """Validate all configured scenario layouts and report mismatches."""

    # Reading and parsing the complete project XML
    project_xml_root = read_project_xml()

    # Reading current project-layer records
    layer_records = project_layer_records(project_xml_root)

    # Reading all uniquely named stored project layouts
    layouts = stored_layouts(project_xml_root)

    # Initializing global validation errors
    validation_errors: list[str] = []

    # Recording an error when the project layout count differs from its contract
    if len(layouts) != expected_project_layout_count:
        # Storing the observed and expected project layout counts
        validation_errors.append(
            f"project layout count {len(layouts)} != "
            f"{expected_project_layout_count}"
        )

    # Processing each scenario template
    for scenario_prefix, template_file in scenario_template_files.items():
        # Parsing the current scenario layout template
        template_layout = ET.parse(template_file).getroot()

        # Reading the expected template layout and main-layer names
        expected_template_name, expected_main_layer = expected_template_layers[
            scenario_prefix
        ]

        # Initializing template-specific errors
        template_errors: list[str] = []

        # Recording an error when the template stores an unexpected layout name
        if template_layout.get("name") != expected_template_name:
            # Storing the observed and expected template names
            template_errors.append(
                f"name {template_layout.get('name')!r} != "
                f"{expected_template_name!r}"
            )

        # Validating the complete template structure
        template_errors.extend(
            validate_layout_structure(
                layout=template_layout,
                main_layer_name=expected_main_layer,
                context_specifications=expected_context_layers[scenario_prefix],
                records=layer_records,
            )
        )

        # Reporting the current template validation result
        if template_errors:
            # Reporting all template-specific validation errors
            print(f"{template_file.name}: check: " + "; ".join(template_errors))
        else:
            # Reporting successful template validation
            print(f"{template_file.name}: ok")

        # Storing every template-specific error with its filename
        validation_errors.extend(
            f"{template_file.name}: {error}" for error in template_errors
        )

    # Initializing UUIDs across all target layout items
    target_layout_item_uuids: list[str] = []

    # Processing each expected layout name and main layer
    for layout_name, main_layer in expected_layout_layers.items():
        # Defining the current scenario prefix
        scenario_prefix = (
            "texto_transporte_"
            if layout_name.startswith("texto_transporte_")
            else "texto_adensamento_"
        )

        # Initializing layout-specific errors
        layout_errors: list[str] = []

        # Recording an error when the expected layout is unavailable
        if layout_name not in layouts:
            # Storing the missing layout error
            layout_errors.append("layout is missing")

        # Validating the available stored layout
        else:
            # Reading the current stored layout element
            layout = layouts[layout_name]

            # Validating the complete layout structure
            layout_errors.extend(
                validate_layout_structure(
                    layout=layout,
                    main_layer_name=main_layer,
                    context_specifications=expected_context_layers[scenario_prefix],
                    records=layer_records,
                )
            )

            # Collecting every nonempty target layout-item UUID
            target_layout_item_uuids.extend(
                layout_item.get(
                    "uuid",
                    "",
                )
                for layout_item in layout.findall(".//LayoutItem")
                if layout_item.get("uuid")
            )

        # Reporting the current layout validation result
        if layout_errors:
            # Reporting all layout-specific validation errors
            print(f"{layout_name}: check: " + "; ".join(layout_errors))
        else:
            # Reporting successful layout validation
            print(f"{layout_name}: ok")

        # Storing every layout-specific error with its layout name
        validation_errors.extend(f"{layout_name}: {error}" for error in layout_errors)

    # Recording an error when target layout-item UUIDs collide globally
    if len(target_layout_item_uuids) != len(set(target_layout_item_uuids)):
        # Storing the global target layout UUID-collision error
        validation_errors.append("target layouts contain duplicate LayoutItem UUIDs")

    # Reporting the total number of validation errors
    if validation_errors:
        # Reporting the nonzero validation error count
        print(f"checks={len(validation_errors)}")

        # Returning the failure script status
        return 1

    # Reporting successful validation
    print("checks=0")

    # Reporting the number of validated scenario layouts
    print(f"validated_layouts={len(expected_layout_layers)}")

    # Reporting the number of unique target layout-item UUIDs
    print(f"unique_layout_item_uuids={len(set(target_layout_item_uuids))}")

    # Returning the successful script status
    return 0


################################################################################
##### VI. Execution
################################################################################

# Running the script during whole-file execution
if __name__ == "__main__":
    # Stopping because the required validation condition is not met
    raise SystemExit(main())
