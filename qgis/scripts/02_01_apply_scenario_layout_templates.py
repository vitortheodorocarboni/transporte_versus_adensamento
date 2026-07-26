################################################################################
##################################            ##################################
######################## 02.01) APPLY SCENARIO LAYOUTS #########################
##################################            ##################################
################################################################################

# This script applies the transport and land-use layout templates to all
# scenario-specific text layouts stored in the dissertation QGIS project.

################################################################################
##### I. Packages
################################################################################

# Loading libraries
from __future__ import annotations
from html import unescape
from pathlib import Path
from xml.etree import ElementTree as ET
from xml.sax.saxutils import escape
import os
import re
import tempfile
import uuid
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

# Defining the internal project XML filename
project_xml_filename = "everything.qgs"


################################################################################
##### III. Parameters
################################################################################

# Defining scenario templates, target layouts and main data sources
scenario_specifications = {
    "transport": {
        "template": project_root_directory
        / "qgis"
        / "templates"
        / "layout_transport.qpt",
        "template_layout": "texto_transporte_bem_estar",
        "layer_prefix": "Transporte ",
        "context_layers": [
            "Limites municipais",
            "Limites distritais",
            "Linhas de metrô e trem",
            "Zonas desconsideradas preto",
            "Legenda linha 6",
        ],
        "layouts": {
            "texto_transporte_residentes": "Transporte residentes",
            "texto_transporte_empregos": "Transporte empregos",
            "texto_transporte_preco": "Transporte preço",
            "texto_transporte_salario": "Transporte salário",
            "texto_transporte_renda": "Transporte renda",
            "texto_transporte_produtividade": "Transporte produtividade",
            "texto_transporte_amenidades": "Transporte amenidades",
            "texto_transporte_acessibilidade": "Transporte acessibilidade",
            "texto_transporte_acessibilidade_firmas": (
                "Transporte acessibilidade firmas"
            ),
            "texto_transporte_bem_estar": "Transporte bem-estar",
            "texto_transporte_produto": "Transporte produto",
        },
        "main_source": (
            "../../data/results/transport_scenario/" "transport_variation.parquet"
        ),
    },
    "land_use": {
        "template": project_root_directory
        / "qgis"
        / "templates"
        / "layout_land_use.qpt",
        "template_layout": "texto_adensamento_bem_estar",
        "layer_prefix": "Adensamento ",
        "context_layers": [
            "Limites municipais",
            "Limites distritais",
            "Linhas de metrô e trem",
            "Zonas desconsideradas preto",
        ],
        "layouts": {
            "texto_adensamento_residentes": "Adensamento residentes",
            "texto_adensamento_empregos": "Adensamento empregos",
            "texto_adensamento_preco": "Adensamento preço",
            "texto_adensamento_salario": "Adensamento salário",
            "texto_adensamento_renda": "Adensamento renda",
            "texto_adensamento_produtividade": "Adensamento produtividade",
            "texto_adensamento_amenidades": "Adensamento amenidades",
            "texto_adensamento_acessibilidade": "Adensamento acessibilidade",
            "texto_adensamento_acessibilidade_firmas": (
                "Adensamento acessibilidade firmas"
            ),
            "texto_adensamento_bem_estar": "Adensamento bem-estar",
            "texto_adensamento_produto": "Adensamento produto",
        },
        "main_source": (
            "../../data/results/land_use_scenario/" "land_use_variation.parquet"
        ),
    },
}


################################################################################
##### IV. Functions
################################################################################


# Defining the QGIS project reading function
def read_project() -> tuple[str, dict[str, bytes]]:
    """Read the editable project XML and preserve all QGZ payload entries."""

    # Initializing the preserved project payload
    payload: dict[str, bytes] = {}

    # Opening the QGIS project archive
    with zipfile.ZipFile(qgis_project_file, "r") as archive:
        # Stopping when the project archive contains a corrupt entry
        if archive.testzip() is not None:
            # Stopping because the project archive failed its integrity test
            raise RuntimeError("The QGIS project archive contains a corrupt entry.")

        # Processing each archived filename
        for name in archive.namelist():
            # Preserving the current archived entry
            payload[name] = archive.read(name)

    # Stopping when the editable project XML is unavailable
    if project_xml_filename not in payload:
        # Stopping because the expected QGS member was not found
        raise RuntimeError(f"Project archive has no {project_xml_filename!r} member.")

    # Returning the editable XML and preserved archive payload
    return payload[project_xml_filename].decode("utf-8"), payload


# Defining the QGIS project writing function
def write_project(project_xml: str, payload: dict[str, bytes]) -> None:
    """Write updated XML to a temporary archive and replace the project."""

    # Updating the editable project XML payload
    payload[project_xml_filename] = project_xml.encode("utf-8")

    # Creating the temporary QGIS project archive
    with tempfile.NamedTemporaryFile(
        delete=False,
        suffix=".qgz",
        dir=qgis_project_file.parent,
    ) as handle:
        # Storing the temporary project path
        temp_path = Path(handle.name)

    # Writing and replacing the QGIS project atomically
    try:
        # Opening the temporary QGIS project archive
        with zipfile.ZipFile(
            temp_path,
            "w",
            compression=zipfile.ZIP_DEFLATED,
        ) as archive:
            # Processing each archived name and content
            for name, content in payload.items():
                # Writing the current archived entry
                archive.writestr(name, content)

        # Replacing the QGIS project with the validated temporary archive
        temp_path.replace(qgis_project_file)

    # Removing any unused temporary archive
    finally:
        # Checking whether the temporary archive remains
        if temp_path.exists():
            # Removing the unused temporary archive
            temp_path.unlink()


# Defining the layout-span extraction function
def layout_spans(project_xml: str) -> dict[str, tuple[int, int]]:
    """Map every stored layout name to its XML character span."""

    # Defining the starts
    starts = list(re.finditer(r'<Layout name="([^"]+)"', project_xml))
    # Defining the spans
    spans: dict[str, tuple[int, int]] = {}
    # Processing each index and match
    for index, match in enumerate(starts):
        # Reading the current stored layout name
        stored_layout_name = match.group(1)

        # Stopping when a layout name occurs more than once
        if stored_layout_name in spans:
            # Stopping because layout replacement would be ambiguous
            raise RuntimeError(f"Duplicate layout name: {stored_layout_name}")

        # Defining the end
        end = (
            starts[index + 1].start()
            if index + 1 < len(starts)
            else project_xml.find("</Layouts>", match.start())
        )
        # Comparing end with the expected value
        if end == -1:
            # Defining the end
            end = len(project_xml)
        # Storing the current layout span
        spans[stored_layout_name] = (match.start(), end)
    # Returning the spans
    return spans


# Defining the project-layer record extraction function
def project_layer_records(
    project_xml: str,
) -> dict[str, list[dict[str, str]]]:
    """Map layer names to their QGIS identifiers, sources and providers."""

    # Initializing project-layer records by displayed name
    records: dict[str, list[dict[str, str]]] = {}

    # Processing every stored map-layer block
    for match in re.finditer(r"(?s)<maplayer.*?</maplayer>", project_xml):
        # Reading the current map-layer XML block
        block = match.group(0)

        # Locating the displayed layer name
        layer_name_match = re.search(r"<layername>([^<]+)</layername>", block)

        # Locating the internal QGIS layer identifier
        layer_id_match = re.search(r"<id>([^<]+)</id>", block)

        # Locating the stored layer data source
        layer_source_match = re.search(r"<datasource>(.*?)</datasource>", block)

        # Locating the stored layer provider
        layer_provider_match = re.search(
            r"<provider[^>]*>([^<]+)</provider>",
            block,
        )

        # Skipping incomplete project-layer records
        if not (
            layer_name_match
            and layer_id_match
            and layer_source_match
            and layer_provider_match
        ):
            # Continuing with the next map-layer block
            continue

        # Reading the displayed layer name
        layer_name = layer_name_match.group(1)

        # Initializing the current layer-name collection
        records.setdefault(
            layer_name,
            [],
        )

        # Storing the complete current project-layer record
        records[layer_name].append(
            {
                "id": layer_id_match.group(1),
                "source": layer_source_match.group(1).replace("\\", "/"),
                "provider": layer_provider_match.group(1),
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

    # Returning the unique project-layer record
    return matching_records[0]


# Defining the legend-node extraction function
def legend_nodes(layout_xml: str) -> list[re.Match[str]]:
    """Extract ordered layer-tree nodes from one layout XML block."""

    # Returning the list
    return list(
        re.finditer(r"(?s)<layer-tree-layer\b[^>]*>.*?</layer-tree-layer>", layout_xml)
    )


# Defining the XML-attribute update function
def set_attr(node: str, attr_name: str, value: str) -> str:
    """Set or insert one attribute in a layer-tree XML node."""

    # Escaping the requested value for a double-quoted XML attribute
    escaped_value = escape(
        unescape(value),
        entities={'"': "&quot;"},
    )

    # Checking the result of search
    if re.search(rf'\b{attr_name}="[^"]*"', node):
        # Returning text with the requested XML replacement
        return re.sub(
            rf'\b{attr_name}="[^"]*"',
            f'{attr_name}="{escaped_value}"',
            node,
            count=1,
        )

    # Returning the updated XML node
    return node.replace(
        "<layer-tree-layer",
        f'<layer-tree-layer {attr_name}="{escaped_value}"',
        1,
    )


# Defining the custom-option update function
def upsert_option(node: str, option_name: str, value: str) -> str:
    """Set or insert one string option in a layer-tree XML node."""

    # Escaping the requested value for a double-quoted XML attribute
    escaped_value = escape(
        unescape(value),
        entities={'"': "&quot;"},
    )

    # Defining the pattern
    pattern = (
        rf'(<Option name="{re.escape(option_name)}" type="QString" value=")[^"]*("/>)'
    )
    # Checking the result of search
    if re.search(pattern, node):
        # Returning text with the requested XML replacement
        return re.sub(pattern, rf"\g<1>{escaped_value}\2", node)

    # Defining the custom-property map search expression
    map_option_pattern = (
        r"(?s)(<customproperties>\s*<Option type=\"Map\">)"
        r"(.*?)(\s*</Option>\s*</customproperties>)"
    )
    # Locating the custom-property map
    map_option = re.search(
        map_option_pattern,
        node,
    )
    # Defining the inserted option line
    option_line = (
        f'\n                <Option name="{option_name}" '
        f'type="QString" value="{escaped_value}"/>'
    )
    # Checking the required state of map option
    if map_option:
        # Returning the calculated value
        return node[: map_option.end(2)] + option_line + node[map_option.end(2) :]

    # Defining the customproperties
    customproperties = (
        "\n            <customproperties>\n"
        '              <Option type="Map">'
        f"{option_line}\n"
        "              </Option>\n"
        "            </customproperties>\n"
        "          "
    )
    # Returning the updated XML node
    return node.replace("</layer-tree-layer>", customproperties + "</layer-tree-layer>")


# Defining the legend-node name extraction function
def legend_node_name(node: str) -> str:
    """Extract the displayed layer name from one legend node."""

    # Locating the opening layer-tree tag
    opening_tag_match = re.match(
        r"<layer-tree-layer\b([^>]*)>",
        node,
    )

    # Stopping when the legend node has no valid opening tag
    if opening_tag_match is None:
        # Stopping because the legend node cannot be interpreted
        raise RuntimeError("Legend node has no valid layer-tree opening tag.")

    # Locating the displayed layer-name attribute
    layer_name_match = re.search(
        r'\bname="([^"]*)"',
        opening_tag_match.group(1),
    )

    # Stopping when the legend node has no displayed layer name
    if layer_name_match is None:
        # Stopping because project-layer resolution requires a name
        raise RuntimeError("Legend node has no layer-name attribute.")

    # Returning the displayed legend layer name
    return layer_name_match.group(1)


# Defining the template-context extraction function
def scenario_context_and_main(
    template_layout: str,
    expected_layer_prefix: str,
) -> tuple[list[str], str]:
    """Separate contextual legend nodes from the scenario main node."""

    # Reading every ordered legend node from the template
    nodes = [match.group(0) for match in legend_nodes(template_layout)]

    # Reading all legend-node names
    node_names = [legend_node_name(node) for node in nodes]

    # Locating nodes belonging to the expected scenario
    scenario_node_indices = [
        index
        for index, node_name in enumerate(node_names)
        if node_name.startswith(expected_layer_prefix)
    ]

    # Stopping unless exactly one expected scenario node exists
    if len(scenario_node_indices) != 1:
        # Stopping because the template scenario layer is ambiguous or absent
        raise RuntimeError(
            f"Template has {len(scenario_node_indices)} legend nodes beginning "
            f"with {expected_layer_prefix!r}, expected exactly 1."
        )

    # Reading the expected scenario-node index
    scenario_node_index = scenario_node_indices[0]

    # Stopping when the scenario node is not the final legend layer
    if scenario_node_index != len(nodes) - 1:
        # Stopping because later legend nodes would otherwise be discarded
        raise RuntimeError("Template scenario layer is not the final legend node.")

    # Returning contextual nodes and the scenario-specific main node
    return nodes[:scenario_node_index], nodes[scenario_node_index]


# Defining the contextual legend-node synchronization function
def synchronize_context_nodes(
    context_nodes: list[str],
    expected_context_names: list[str],
    records: dict[str, list[dict[str, str]]],
) -> list[str]:
    """Synchronize contextual legend nodes with current project layers."""

    # Reading the ordered contextual layer names from the template
    observed_context_names = [legend_node_name(node) for node in context_nodes]

    # Stopping when template context differs from its declared contract
    if observed_context_names != expected_context_names:
        # Stopping because contextual legend order must be explicit
        raise RuntimeError(
            f"Template context {observed_context_names} differs from expected "
            f"context {expected_context_names}."
        )

    # Initializing synchronized contextual legend nodes
    synchronized_nodes: list[str] = []

    # Processing each ordered contextual legend node
    for context_node, context_name in zip(
        context_nodes,
        expected_context_names,
    ):
        # Reading the unique current project-layer record
        context_record = unique_layer_record(
            records=records,
            layer_name=context_name,
        )

        # Synchronizing the contextual layer identifier
        synchronized_node = set_attr(
            context_node,
            "id",
            context_record["id"],
        )

        # Synchronizing the contextual layer data source
        synchronized_node = set_attr(
            synchronized_node,
            "source",
            context_record["source"],
        )

        # Synchronizing the contextual layer provider
        synchronized_node = set_attr(
            synchronized_node,
            "providerKey",
            context_record["provider"],
        )

        # Storing the synchronized contextual node
        synchronized_nodes.append(synchronized_node)

    # Returning the synchronized contextual legend nodes
    return synchronized_nodes


# Defining the scenario main-node update function
def update_main_node(
    main_node: str,
    layer_name: str,
    layer_record: dict[str, str],
) -> str:
    """Point the template main node to one scenario result layer."""

    # Synchronizing the scenario layer identifier
    node = set_attr(
        main_node,
        "id",
        layer_record["id"],
    )

    # Synchronizing the scenario layer name
    node = set_attr(
        node,
        "name",
        layer_name,
    )

    # Synchronizing the scenario layer source
    node = set_attr(
        node,
        "source",
        layer_record["source"],
    )

    # Synchronizing the scenario layer provider
    node = set_attr(
        node,
        "providerKey",
        layer_record["provider"],
    )

    # Setting the stable cached legend title
    node = upsert_option(
        node,
        "cached_name",
        "Variação (%):",
    )

    # Setting the stable visible legend title
    node = upsert_option(
        node,
        "legend/title-label",
        "Variação (%):",
    )

    # Returning the synchronized scenario legend node
    return node


# Defining the legend replacement function
def replace_legend(
    template_layout: str, context_nodes: list[str], main_node: str
) -> str:
    """Replace template legend nodes with scenario-specific nodes."""

    # Extracting the configured layout structure
    nodes = legend_nodes(template_layout)
    # Handling the absence of nodes
    if not nodes:
        # Stopping because no legend nodes in template
        raise RuntimeError("No legend nodes in template.")
    # Defining the replacement
    replacement = "\n".join(context_nodes + [main_node])
    # Returning the calculated value
    return (
        template_layout[: nodes[0].start()]
        + replacement
        + template_layout[nodes[-1].end() :]
    )


# Defining the deterministic UUID replacement function
def assign_layout_uuids(
    layout_xml: str,
    target_layout_name: str,
) -> str:
    """Assign deterministic unique UUIDs to one generated layout."""

    # Defining the replacements
    replacements: dict[str, str] = {}

    # Defining the deterministic UUID replacement function
    def replace(match: re.Match[str]) -> str:
        """Return one stable replacement UUID within the current layout."""

        # Reading the original template UUID
        original_uuid = match.group(0)

        # Creating one replacement per original UUID and target layout
        if original_uuid not in replacements:
            # Defining the stable UUID seed
            uuid_seed = (
                f"dissertation:qgis:layout:{target_layout_name}:"
                f"{original_uuid.lower()}"
            )

            # Generating the deterministic replacement UUID
            deterministic_uuid = uuid.uuid5(
                uuid.NAMESPACE_URL,
                uuid_seed,
            )

            # Storing the braced deterministic UUID
            replacements[original_uuid] = "{" + str(deterministic_uuid) + "}"

        # Returning the stable replacement UUID
        return replacements[original_uuid]

    # Defining the UUID search expression
    uuid_pattern = (
        r"\{[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-"
        r"[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-"
        r"[0-9a-fA-F]{12}\}"
    )
    # Returning layout XML with deterministic unique identifiers
    return re.sub(
        uuid_pattern,
        replace,
        layout_xml,
    )


# Defining the template-layout name extraction function
def layout_name(template_layout: str) -> str:
    """Extract the stored name from one layout template."""

    # Locating the requested XML element
    match = re.search(r'<Layout name="([^"]+)"', template_layout)
    # Handling the absence of match
    if not match:
        # Stopping because template layout name not found
        raise RuntimeError("Template layout name not found.")
    # Returning the extracted regular-expression value
    return match.group(1)


################################################################################
##### V. Layout application
################################################################################


# Defining the main scenario-layout application function
def main() -> int:
    """Apply both scenario templates to every configured target layout."""

    # Reading the editable project XML and preserved archive payload
    project_xml, payload = read_project()

    # Reading all current project-layer records
    layer_records = project_layer_records(project_xml)

    # Initializing the changed-layout collection
    changed: list[str] = []

    # Initializing the expected target-layout collection
    expected_target_layouts: set[str] = set()

    # Processing each scenario configuration
    for scenario_name, config in scenario_specifications.items():
        # Reading the configured template XML
        template_xml = config["template"].read_text(encoding="utf-8")

        # Reading the template layout name
        template_name = layout_name(template_xml)

        # Stopping when the template name differs from its declared contract
        if template_name != config["template_layout"]:
            # Stopping because an unintended template file may be configured
            raise RuntimeError(
                f"Template {scenario_name!r} stores layout {template_name!r}, "
                f"expected {config['template_layout']!r}."
            )

        # Separating contextual and scenario-specific template legend nodes
        context_nodes, template_main = scenario_context_and_main(
            template_layout=template_xml,
            expected_layer_prefix=config["layer_prefix"],
        )

        # Synchronizing contextual nodes with current project-layer records
        synchronized_context_nodes = synchronize_context_nodes(
            context_nodes=context_nodes,
            expected_context_names=config["context_layers"],
            records=layer_records,
        )

        # Processing each configured target layout and result layer
        for target_layout, target_layer in config["layouts"].items():
            # Recording the expected target layout
            expected_target_layouts.add(target_layout)

            # Reading the current project layout spans
            spans = layout_spans(project_xml)

            # Stopping when the configured target layout is unavailable
            if target_layout not in spans:
                # Stopping because the expected stored layout cannot be replaced
                raise RuntimeError(f"Layout not found: {target_layout}")

            # Reading the unique current scenario-layer record
            target_layer_record = unique_layer_record(
                records=layer_records,
                layer_name=target_layer,
            )

            # Stopping when the scenario layer source differs from its contract
            if target_layer_record["source"] != config["main_source"]:
                # Stopping because the layout would reference unexpected data
                raise RuntimeError(
                    f"Layer {target_layer!r} points to "
                    f"{target_layer_record['source']!r}, expected "
                    f"{config['main_source']!r}."
                )

            # Reading the current target-layout span
            start, end = spans[target_layout]

            # Synchronizing the scenario-specific legend node
            main_node = update_main_node(
                main_node=template_main,
                layer_name=target_layer,
                layer_record=target_layer_record,
            )

            # Replacing template legend nodes with the synchronized sequence
            new_layout = replace_legend(
                template_layout=template_xml,
                context_nodes=synchronized_context_nodes,
                main_node=main_node,
            )

            # Renaming the generated layout to its configured target name
            new_layout = re.sub(
                rf'(<Layout name="){re.escape(template_name)}(")',
                rf"\g<1>{target_layout}\2",
                new_layout,
                count=1,
            )

            # Assigning deterministic UUIDs unique to the target layout
            new_layout = assign_layout_uuids(
                layout_xml=new_layout,
                target_layout_name=target_layout,
            )

            # Reading generated legend-node names
            generated_legend_names = [
                legend_node_name(node.group(0)) for node in legend_nodes(new_layout)
            ]

            # Defining the expected generated legend-node names
            expected_legend_names = config["context_layers"] + [target_layer]

            # Stopping when the generated legend sequence differs from its contract
            if generated_legend_names != expected_legend_names:
                # Stopping because the generated layout would have a wrong legend
                raise RuntimeError(
                    f"Generated legend for {target_layout!r} is "
                    f"{generated_legend_names}, expected {expected_legend_names}."
                )

            # Comparing the stored and generated target layouts
            if project_xml[start:end] != new_layout:
                # Replacing the stored target-layout XML
                project_xml = project_xml[:start] + new_layout + project_xml[end:]

                # Recording the changed target layout
                changed.append(target_layout)

    # Stopping when target layout names are duplicated across scenarios
    configured_layout_count = sum(
        len(config["layouts"]) for config in scenario_specifications.values()
    )

    # Checking the uniqueness of all configured layout names
    if len(expected_target_layouts) != configured_layout_count:
        # Stopping because multiple scenarios target the same stored layout
        raise RuntimeError("Scenario specifications contain duplicate target layouts.")

    # Parsing the complete generated project XML before any archive replacement
    try:
        # Validating that the generated project remains well-formed XML
        ET.fromstring(project_xml)

    # Converting XML parser failures into an explicit project-write error
    except ET.ParseError as error:
        # Stopping before an invalid QGIS project can be written
        raise RuntimeError(f"Generated QGIS project XML is invalid: {error}") from error

    # Writing the project only when at least one target layout changed
    if changed:
        # Writing the updated project through atomic replacement
        write_project(project_xml, payload)

    # Reporting every changed target layout
    print("changed_layouts=" + ",".join(changed))

    # Returning the successful script status
    return 0


################################################################################
##### VI. Execution
################################################################################

# Running the script during whole-file execution
if __name__ == "__main__":
    # Stopping because the required validation condition is not met
    raise SystemExit(main())
