################################################################################
##################################            ##################################
######################### 04.01) EXPORT SCENARIO MAPS ##########################
##################################            ##################################
################################################################################

# This script exports the validated transport and land-use layouts stored in the
# dissertation QGIS project with explicit scenario-specific map-layer sets.

################################################################################
##### I. Packages
################################################################################

# Loading libraries
from __future__ import annotations
from osgeo import gdal
from pathlib import Path
from qgis.PyQt.QtGui import QImage
from qgis.core import (
    QgsApplication,
    QgsLayerTree,
    QgsLayerTreeLayer,
    QgsLayoutExporter,
    QgsLayoutItemLegend,
    QgsLayoutItemMap,
    QgsPrintLayout,
    QgsProject,
)
import csv
import hashlib
import os
import shutil
import sys
import tempfile

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
        for candidate_directory in (
            search_origin,
            *search_origin.parents,
        ):
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

# Reading the optional map-output directory override
configured_map_output_directory = os.getenv("DISSERTACAO_MAP_OUTPUT_DIRECTORY")

# Defining the map-output directory
map_output_directory = (
    Path(configured_map_output_directory).expanduser().resolve()
    if configured_map_output_directory
    else project_root_directory / "paper" / "maps"
)

# Reading the optional export-report file override
configured_export_report_file = os.getenv("DISSERTACAO_MAP_EXPORT_REPORT_FILE")

# Defining the export-validation report file
export_report_file = (
    Path(configured_export_report_file).expanduser().resolve()
    if configured_export_report_file
    else (
        project_root_directory
        / "qgis"
        / "classifications"
        / "scenario_map_export_validation.csv"
    )
)


# Defining the portable QGIS-prefix discovery function
def discover_qgis_prefix_directory() -> Path:
    """Locate a QGIS installation prefix from configuration or Python."""

    # Reading the optional explicit QGIS-prefix configuration
    configured_qgis_prefix = os.getenv("QGIS_PREFIX_PATH")

    # Initializing the ordered QGIS-prefix candidates
    qgis_prefix_candidates: list[Path] = []

    # Prioritizing the explicitly configured QGIS prefix
    if configured_qgis_prefix:
        # Adding the configured QGIS prefix to the search
        qgis_prefix_candidates.append(
            Path(configured_qgis_prefix).expanduser().resolve()
        )

    # Inferring the QGIS prefix from the active Python installation
    python_inferred_prefix = Path(sys.prefix).resolve().parent / "qgis"

    # Adding the Python-inferred QGIS prefix to the search
    qgis_prefix_candidates.append(python_inferred_prefix)

    # Defining the standard Windows QGIS installation directory
    windows_qgis_directory = Path(
        os.environ.get(
            "ProgramFiles",
            "C:/Program Files",
        )
    )

    # Searching installed QGIS directories from newest name to oldest
    installed_qgis_directories = sorted(
        windows_qgis_directory.glob("QGIS *"),
        reverse=True,
    )

    # Adding standard Windows QGIS prefixes to the search
    qgis_prefix_candidates.extend(
        qgis_directory / "apps" / "qgis"
        for qgis_directory in installed_qgis_directories
    )

    # Initializing the collection of prefixes already inspected
    inspected_qgis_prefixes: set[Path] = set()

    # Inspecting every configured or inferred QGIS prefix
    for qgis_prefix_candidate in qgis_prefix_candidates:
        # Resolving the current QGIS-prefix candidate
        resolved_qgis_prefix = qgis_prefix_candidate.resolve()

        # Skipping QGIS prefixes already inspected
        if resolved_qgis_prefix in inspected_qgis_prefixes:
            # Continuing with the next QGIS-prefix candidate
            continue

        # Recording the QGIS prefix as inspected
        inspected_qgis_prefixes.add(resolved_qgis_prefix)

        # Defining the expected QGIS-resource marker
        qgis_resource_marker = resolved_qgis_prefix / "resources" / "qgis.db"

        # Returning the first QGIS prefix containing its resource database
        if qgis_resource_marker.is_file():
            # Returning the validated QGIS prefix
            return resolved_qgis_prefix

    # Stopping when no valid QGIS installation prefix is available
    raise FileNotFoundError(
        "Could not locate a QGIS installation prefix. Set QGIS_PREFIX_PATH or "
        "run the script with the Python environment bundled with QGIS."
    )


# Discovering the local QGIS installation prefix
qgis_prefix_directory = discover_qgis_prefix_directory()


################################################################################
##### III. Parameters
################################################################################

# Defining the image-export resolution
export_resolution_dpi = 300

# Defining the final JPEG quality
jpeg_quality = 95

# Defining the expected number of exported scenario maps
expected_export_count = 22

# Defining the shared ordered analytical variables and layer suffixes
scenario_variable_specifications = [
    ("residentes", "residentes"),
    ("empregos", "empregos"),
    ("preco", "preço"),
    ("salario", "salário"),
    ("renda", "renda"),
    ("produtividade", "produtividade"),
    ("amenidades", "amenidades"),
    ("acessibilidade", "acessibilidade"),
    ("acessibilidade_firmas", "acessibilidade firmas"),
    ("bem_estar", "bem-estar"),
    ("produto", "produto"),
]

# Defining scenario layout prefixes, layer prefixes and contextual layers
scenario_specifications = {
    "transport": {
        "layout_prefix": "texto_transporte_",
        "layer_prefix": "Transporte ",
        "context_layers": [
            "Limites municipais",
            "Limites distritais",
            "Linhas de metrô e trem",
            "Zonas desconsideradas preto",
            "Legenda linha 6",
        ],
        "context_labels": {
            "Limites municipais": "Limites municipais",
            "Limites distritais": "Limites distritais",
            "Linhas de metrô e trem": "Linhas de metrô e trem",
            "Zonas desconsideradas preto": "Zonas OD desconsideradas",
            "Legenda linha 6": "Linha 6-Laranja",
        },
        "background_layers": [
            "OSM Standard",
        ],
    },
    "land_use": {
        "layout_prefix": "texto_adensamento_",
        "layer_prefix": "Adensamento ",
        "context_layers": [
            "Limites municipais",
            "Limites distritais",
            "Linhas de metrô e trem",
            "Zonas desconsideradas preto",
        ],
        "context_labels": {
            "Limites municipais": "Limites municipais",
            "Limites distritais": "Limites distritais",
            "Linhas de metrô e trem": "Linhas de metrô e trem",
            "Zonas desconsideradas preto": "Zonas OD desconsideradas",
        },
        "background_layers": [
            "OSM Standard",
        ],
    },
}

# Initializing the ordered map-export specifications
map_export_specifications: list[dict[str, object]] = []

# Constructing every scenario-specific map-export specification
for scenario_name, scenario_specification in scenario_specifications.items():
    # Processing every ordered analytical variable
    for file_suffix, layer_suffix in scenario_variable_specifications:
        # Constructing the stored layout name
        layout_name = str(scenario_specification["layout_prefix"]) + file_suffix

        # Constructing the target result-layer name
        target_layer_name = str(scenario_specification["layer_prefix"]) + layer_suffix

        # Constructing the referenced output filename
        output_file_name = f"{layout_name}.jpeg"

        # Storing the complete map-export specification
        map_export_specifications.append(
            {
                "scenario": scenario_name,
                "layout": layout_name,
                "target_layer": target_layer_name,
                "context_layers": list(scenario_specification["context_layers"]),
                "context_labels": dict(scenario_specification["context_labels"]),
                "background_layers": list(scenario_specification["background_layers"]),
                "output_file": output_file_name,
            }
        )

# Defining the ordered export-validation report fields
export_report_fields = [
    "scenario",
    "layout",
    "target_layer",
    "context_layers",
    "map_layers",
    "output_file",
    "width_pixels",
    "height_pixels",
    "dpi",
    "jpeg_quality",
    "bytes",
    "sha256",
    "status",
]


################################################################################
##### IV. Functions
################################################################################


# Defining the unique project-layer lookup function
def unique_layer_by_name(
    project: QgsProject,
    layer_name: str,
):
    """Return the unique valid project layer with the requested visible name."""

    # Reading all project layers with the requested visible name
    matching_layers = project.mapLayersByName(layer_name)

    # Stopping unless the requested layer name is unique
    if len(matching_layers) != 1:
        # Stopping because map configuration requires one exact layer
        raise RuntimeError(
            f"Project contains {len(matching_layers)} layers named "
            f"{layer_name!r}; expected exactly 1."
        )

    # Reading the unique matching project layer
    matching_layer = matching_layers[0]

    # Stopping when the required layer is invalid
    if not matching_layer.isValid():
        # Stopping because invalid layers cannot be exported reliably
        raise RuntimeError(f"Project layer is invalid: {layer_name}")

    # Returning the unique valid project layer
    return matching_layer


# Defining the unique layout lookup function
def unique_layout_by_name(
    project: QgsProject,
    layout_name: str,
) -> QgsPrintLayout:
    """Return the unique stored print layout with the requested name."""

    # Reading all stored print layouts
    stored_layouts = project.layoutManager().printLayouts()

    # Selecting stored layouts with the requested name
    matching_layouts = [
        layout for layout in stored_layouts if layout.name() == layout_name
    ]

    # Stopping unless the requested layout name is unique
    if len(matching_layouts) != 1:
        # Stopping because export requires one exact stored layout
        raise RuntimeError(
            f"Project contains {len(matching_layouts)} layouts named "
            f"{layout_name!r}; expected exactly 1."
        )

    # Returning the unique stored print layout
    return matching_layouts[0]


# Defining the unique layout-item lookup function
def unique_layout_item(
    layout: QgsPrintLayout,
    item_class,
):
    """Return the unique layout item belonging to the requested QGIS class."""

    # Selecting all layout items with the requested class
    matching_items = [item for item in layout.items() if isinstance(item, item_class)]

    # Stopping unless the requested layout item is unique
    if len(matching_items) != 1:
        # Stopping because export requires one exact layout item
        raise RuntimeError(
            f"Layout {layout.name()!r} contains {len(matching_items)} "
            f"{item_class.__name__} items; expected exactly 1."
        )

    # Returning the unique matching layout item
    return matching_items[0]


# Defining the stored legend-layer name reading function
def legend_layer_names(
    legend: QgsLayoutItemLegend,
) -> list[str]:
    """Read ordered layer names from one stored layout legend model."""

    # Reading the stored legend root group
    legend_root_group = legend.model().rootGroup()

    # Reading ordered layer nodes from the legend model
    legend_layer_nodes = [
        child_node
        for child_node in legend_root_group.children()
        if isinstance(child_node, QgsLayerTreeLayer)
    ]

    # Reading each legend node's linked layer name
    stored_layer_names = [
        (
            legend_layer_node.layer().name()
            if legend_layer_node.layer() is not None
            else legend_layer_node.name()
        )
        for legend_layer_node in legend_layer_nodes
    ]

    # Returning the ordered stored legend-layer names
    return stored_layer_names


# Defining the single-layout configuration function
def configure_layout(
    project: QgsProject,
    export_specification: dict[str, object],
) -> tuple[QgsPrintLayout, list[str], QgsLayerTree]:
    """Lock one stored layout to its exact contextual and result layers."""

    # Reading the configured stored layout name
    layout_name = str(export_specification["layout"])

    # Reading the configured target result-layer name
    target_layer_name = str(export_specification["target_layer"])

    # Reading the configured contextual layer names
    context_layer_names = [
        str(layer_name) for layer_name in export_specification["context_layers"]
    ]

    # Reading the configured contextual legend labels
    context_layer_labels = {
        str(layer_name): str(layer_label)
        for layer_name, layer_label in dict(
            export_specification["context_labels"]
        ).items()
    }

    # Stopping when contextual labels do not match contextual layers exactly
    if set(context_layer_labels) != set(context_layer_names):
        # Stopping because every contextual legend node requires one label
        raise RuntimeError(
            f"Layout {layout_name!r} context-label keys differ from "
            "its contextual layer names."
        )

    # Reading the configured background layer names
    background_layer_names = [
        str(layer_name) for layer_name in export_specification["background_layers"]
    ]

    # Constructing the complete expected legend-layer sequence
    expected_legend_layer_names = context_layer_names + [target_layer_name]

    # Constructing the complete expected map-layer sequence
    expected_map_layer_names = expected_legend_layer_names + background_layer_names

    # Reading the unique stored project layout
    layout = unique_layout_by_name(
        project=project,
        layout_name=layout_name,
    )

    # Reading the unique map item
    layout_map = unique_layout_item(
        layout=layout,
        item_class=QgsLayoutItemMap,
    )

    # Reading the unique legend item
    layout_legend = unique_layout_item(
        layout=layout,
        item_class=QgsLayoutItemLegend,
    )

    # Reading the stored legend-layer sequence
    stored_legend_layer_names = legend_layer_names(
        legend=layout_legend,
    )

    # Stopping when the stored legend does not match its export contract
    if stored_legend_layer_names != expected_legend_layer_names:
        # Stopping because export must not conceal a stale stored legend
        raise RuntimeError(
            f"Layout {layout_name!r} legend contains "
            f"{stored_legend_layer_names}, expected "
            f"{expected_legend_layer_names}."
        )

    # Resolving every contextual, target and background layer uniquely
    configured_layers = [
        unique_layer_by_name(
            project=project,
            layer_name=layer_name,
        )
        for layer_name in expected_map_layer_names
    ]

    # Indexing configured map layers by their unique visible names
    configured_layers_by_name = {layer.name(): layer for layer in configured_layers}

    # Locking the map to the explicit layer set
    layout_map.setKeepLayerSet(True)

    # Applying the explicit ordered map-layer set
    layout_map.setLayers(configured_layers)

    # Refreshing the configured map item
    layout_map.refresh()

    # Linking the legend explicitly to the configured map item
    layout_legend.setLinkedMap(layout_map)

    # Creating a fresh runtime legend root from the validated stored sequence
    runtime_legend_root = QgsLayerTree()

    # Rebuilding every contextual and target legend node in memory
    for legend_layer_name in expected_legend_layer_names:
        # Adding the current project layer to the runtime legend
        legend_layer_node = runtime_legend_root.addLayer(
            configured_layers_by_name[legend_layer_name]
        )

        # Defining the contextual or target legend label
        legend_layer_label = context_layer_labels.get(
            legend_layer_name,
            "Variação (%):",
        )

        # Storing the visible legend title label
        legend_layer_node.setCustomProperty(
            "legend/title-label",
            legend_layer_label,
        )

        # Storing the cached visible legend label
        legend_layer_node.setCustomProperty(
            "cached_name",
            legend_layer_label,
        )

    # Replacing only the in-memory legend model with the validated sequence
    layout_legend.model().setRootGroup(runtime_legend_root)

    # Refreshing the configured legend item
    layout_legend.refresh()

    # Expanding the legend box to display every stored class
    layout_legend.adjustBoxSize()

    # Reading the applied map-layer sequence
    applied_layer_names = [layer.name() for layer in layout_map.layers()]

    # Stopping when QGIS did not preserve the requested layer sequence
    if applied_layer_names != expected_map_layer_names:
        # Stopping because the rendered content would differ from the contract
        raise RuntimeError(
            f"Layout {layout_name!r} map contains {applied_layer_names}, "
            f"expected {expected_map_layer_names}."
        )

    # Returning the configured layout, applied layers and live legend tree
    return layout, applied_layer_names, runtime_legend_root


# Defining the expected image-dimension function
def expected_image_dimensions(
    layout: QgsPrintLayout,
    resolution_dpi: int,
) -> tuple[int, int]:
    """Calculate full-page pixel dimensions for one layout export."""

    # Reading the complete layout page collection
    page_collection = layout.pageCollection()

    # Stopping unless the layout contains exactly one page
    if page_collection.pageCount() != 1:
        # Stopping because the output contract expects one image per layout
        raise RuntimeError(
            f"Layout {layout.name()!r} contains "
            f"{page_collection.pageCount()} pages; expected exactly 1."
        )

    # Reading the single layout page
    layout_page = page_collection.page(0)

    # Reading the page size in layout units
    page_size = layout_page.pageSize()

    # Converting page width from millimeters to pixels
    expected_width = int(page_size.width() / 25.4 * resolution_dpi)

    # Converting page height from millimeters to pixels
    expected_height = int(page_size.height() / 25.4 * resolution_dpi)

    # Returning the expected full-page pixel dimensions
    return expected_width, expected_height


# Defining the lossless render-conversion function
def convert_rendered_image_to_jpeg(
    rendered_image_file: Path,
    jpeg_image_file: Path,
    expected_width: int,
    expected_height: int,
) -> None:
    """Convert one validated lossless QGIS render to the final JPEG format."""

    # Stopping when the expected lossless render is unavailable
    if not rendered_image_file.is_file():
        # Stopping because QGIS did not produce its staging render
        raise RuntimeError(f"Rendered image not found: {rendered_image_file}")

    # Loading the lossless QGIS render through Qt
    rendered_image = QImage(str(rendered_image_file))

    # Stopping when Qt cannot decode the lossless render
    if rendered_image.isNull():
        # Stopping because the lossless render cannot be converted safely
        raise RuntimeError(f"Could not decode rendered image: {rendered_image_file}")

    # Stopping when rendered dimensions differ from the page contract
    if (
        rendered_image.width() != expected_width
        or rendered_image.height() != expected_height
    ):
        # Stopping because the lossless render was cropped or rescaled
        raise RuntimeError(
            f"Rendered image {rendered_image_file.name!r} has dimensions "
            f"{rendered_image.width()}x{rendered_image.height()}, expected "
            f"{expected_width}x{expected_height}."
        )

    # Saving the final JPEG with explicit quality
    jpeg_saved = rendered_image.save(
        str(jpeg_image_file),
        "JPEG",
        jpeg_quality,
    )

    # Stopping when Qt cannot create the final JPEG
    if not jpeg_saved:
        # Stopping because no validated final-format output is available
        raise RuntimeError(f"Could not convert render to JPEG: {jpeg_image_file}")

    # Removing the intermediate lossless render
    rendered_image_file.unlink()


# Defining the exported-image validation function
def validate_exported_image(
    image_file: Path,
    expected_width: int,
    expected_height: int,
) -> dict[str, object]:
    """Validate JPEG signature, dimensions and content hash."""

    # Stopping when the expected image file is unavailable
    if not image_file.is_file():
        # Stopping because export did not produce its required output
        raise RuntimeError(f"Exported image not found: {image_file}")

    # Reading the complete exported image payload
    image_payload = image_file.read_bytes()

    # Stopping when the exported payload lacks a JPEG signature
    if not image_payload.startswith(b"\xff\xd8\xff"):
        # Stopping because the output file is not a valid JPEG payload
        raise RuntimeError(f"Exported image is not JPEG: {image_file}")

    # Loading the exported image through Qt
    exported_image = QImage(str(image_file))

    # Stopping when Qt cannot decode the exported image
    if exported_image.isNull():
        # Stopping because the exported image cannot be inspected
        raise RuntimeError(f"Could not decode exported image: {image_file}")

    # Reading the exported image width
    width_pixels = exported_image.width()

    # Reading the exported image height
    height_pixels = exported_image.height()

    # Stopping when exported dimensions differ from the full-page contract
    if width_pixels != expected_width or height_pixels != expected_height:
        # Stopping because the exported page was cropped or rescaled
        raise RuntimeError(
            f"Exported image {image_file.name!r} has dimensions "
            f"{width_pixels}x{height_pixels}, expected "
            f"{expected_width}x{expected_height}."
        )

    # Calculating the exported image SHA-256 hash
    image_sha256 = hashlib.sha256(image_payload).hexdigest()

    # Constructing the exported image profile
    image_profile = {
        "width_pixels": width_pixels,
        "height_pixels": height_pixels,
        "bytes": len(image_payload),
        "sha256": image_sha256,
    }

    # Returning the validated exported image profile
    return image_profile


# Defining the single-map staging function
def stage_map_export(
    project: QgsProject,
    export_specification: dict[str, object],
    staging_directory: Path,
) -> dict[str, object]:
    """Configure, export and validate one scenario map in staging."""

    # Reading the configured stored layout name
    layout_name = str(export_specification["layout"])

    # Reading the configured output filename
    output_file_name = str(export_specification["output_file"])

    # Reporting the current map preparation
    print(f"preparing={layout_name}", flush=True)

    # Configuring the stored layout with its explicit map-layer set
    layout, applied_layer_names, runtime_legend_root = configure_layout(
        project=project,
        export_specification=export_specification,
    )

    # Retaining the runtime legend tree through image export
    _active_legend_root = runtime_legend_root

    # Defining the staged image output file
    staged_image_file = staging_directory / output_file_name

    # Defining the lossless QGIS staging-render file
    staged_render_file = (
        staging_directory / Path(output_file_name).with_suffix(".png").name
    )

    # Defining the full-page image-export settings
    export_settings = QgsLayoutExporter.ImageExportSettings()

    # Applying the configured export resolution
    export_settings.dpi = export_resolution_dpi

    # Calculating the expected full-page output dimensions
    expected_width, expected_height = expected_image_dimensions(
        layout=layout,
        resolution_dpi=export_resolution_dpi,
    )

    # Silencing the known nonfatal GDAL metadata-update warning
    gdal.PushErrorHandler("CPLQuietErrorHandler")

    # Exporting the configured layout with guaranteed error-handler restoration
    try:
        # Exporting the configured layout to the staging directory
        export_result = QgsLayoutExporter(layout).exportToImage(
            str(staged_render_file),
            export_settings,
        )

    # Restoring the prior GDAL error handler after image export
    finally:
        # Restoring normal GDAL error reporting
        gdal.PopErrorHandler()

    # Stopping when QGIS reports an image-export failure
    if export_result != QgsLayoutExporter.ExportResult.Success:
        # Stopping because the staged output cannot be trusted
        raise RuntimeError(f"Export failed for {layout_name!r}: {export_result}")

    # Converting the validated lossless render to the final JPEG format
    convert_rendered_image_to_jpeg(
        rendered_image_file=staged_render_file,
        jpeg_image_file=staged_image_file,
        expected_width=expected_width,
        expected_height=expected_height,
    )

    # Validating the staged JPEG output
    image_profile = validate_exported_image(
        image_file=staged_image_file,
        expected_width=expected_width,
        expected_height=expected_height,
    )

    # Constructing the validated map-export record
    export_record = {
        "scenario": export_specification["scenario"],
        "layout": layout_name,
        "target_layer": export_specification["target_layer"],
        "context_layers": ";".join(
            str(layer_name) for layer_name in export_specification["context_layers"]
        ),
        "map_layers": ";".join(applied_layer_names),
        "output_file": output_file_name,
        "width_pixels": image_profile["width_pixels"],
        "height_pixels": image_profile["height_pixels"],
        "dpi": export_resolution_dpi,
        "jpeg_quality": jpeg_quality,
        "bytes": image_profile["bytes"],
        "sha256": image_profile["sha256"],
        "status": "ok",
        "staged_image_file": staged_image_file,
    }

    # Reporting successful staged-image validation
    print(
        f"validated={output_file_name}|"
        f"{image_profile['width_pixels']}x"
        f"{image_profile['height_pixels']}|"
        f"{image_profile['bytes']} bytes",
        flush=True,
    )

    # Returning the validated map-export record
    return export_record


# Defining the export-report writing function
def write_export_report(
    export_records: list[dict[str, object]],
    report_file: Path,
) -> None:
    """Write the complete map-export validation report atomically."""

    # Creating the export-report directory
    report_file.parent.mkdir(
        parents=True,
        exist_ok=True,
    )

    # Defining the temporary report output file
    temporary_report_file = report_file.with_suffix(report_file.suffix + ".tmp")

    # Opening the temporary report output file
    with temporary_report_file.open(
        "w",
        newline="",
        encoding="utf-8",
    ) as report_handle:
        # Creating the export-report writer
        report_writer = csv.DictWriter(
            report_handle,
            fieldnames=export_report_fields,
        )

        # Writing the export-report header
        report_writer.writeheader()

        # Writing the public fields from every validated export record
        report_writer.writerows(
            {
                field_name: export_record[field_name]
                for field_name in export_report_fields
            }
            for export_record in export_records
        )

    # Replacing the prior report with the complete temporary output
    temporary_report_file.replace(report_file)


# Defining the staged-export installation function
def install_staged_exports(
    export_records: list[dict[str, object]],
    output_directory: Path,
) -> None:
    """Replace final maps only after every staged export was validated."""

    # Creating the final map-output directory
    output_directory.mkdir(
        parents=True,
        exist_ok=True,
    )

    # Installing every validated staged image
    for export_record in export_records:
        # Reading the staged image file
        staged_image_file = Path(export_record["staged_image_file"])

        # Defining the final image output file
        final_image_file = output_directory / str(export_record["output_file"])

        # Copying the validated image while preserving existing file permissions
        shutil.copyfile(
            staged_image_file,
            final_image_file,
        )

        # Removing the installed staged image
        staged_image_file.unlink()


################################################################################
##### V. Map export
################################################################################


# Defining the main scenario-map export function
def main(
    output_directory: Path = map_output_directory,
    report_file: Path = export_report_file,
) -> int:
    """Export all validated transport and land-use scenario maps."""

    # Stopping when the export specification count differs from its contract
    if len(map_export_specifications) != expected_export_count:
        # Stopping because the exporter would omit or duplicate a required map
        raise RuntimeError(
            f"Configured {len(map_export_specifications)} map exports; "
            f"expected {expected_export_count}."
        )

    # Reading all configured output filenames
    output_file_names = [
        str(export_specification["output_file"])
        for export_specification in map_export_specifications
    ]

    # Stopping when configured output filenames are duplicated
    if len(output_file_names) != len(set(output_file_names)):
        # Stopping because one map could overwrite another
        raise RuntimeError("Map export specifications contain duplicate outputs.")

    # Defining the native Qt rendering platform for the operating system
    rendering_platform = "windows" if os.name == "nt" else "offscreen"

    # Reading any explicitly configured Qt rendering platform
    configured_rendering_platform = os.environ.get("QT_QPA_PLATFORM")

    # Stopping when Windows was configured with a font-breaking platform
    if (
        os.name == "nt"
        and configured_rendering_platform
        and configured_rendering_platform != rendering_platform
    ):
        # Stopping because offscreen Windows rendering corrupts layout text
        raise RuntimeError(
            "Windows scenario-map export requires QT_QPA_PLATFORM=windows; "
            f"received {configured_rendering_platform!r}."
        )

    # Configuring the validated Qt rendering platform
    os.environ["QT_QPA_PLATFORM"] = rendering_platform

    # Configuring the validated QGIS installation prefix
    QgsApplication.setPrefixPath(
        str(qgis_prefix_directory),
        True,
    )

    # Initializing the noninteractive QGIS application
    qgis_application = QgsApplication([], False)

    # Loading QGIS providers and rendering resources
    qgis_application.initQgis()

    # Exporting all maps while guaranteeing QGIS shutdown
    try:
        # Reading the singleton QGIS project
        project = QgsProject.instance()

        # Reporting the project input file
        print(f"project={qgis_project_file}", flush=True)

        # Stopping when QGIS cannot read the dissertation project
        if not project.read(str(qgis_project_file)):
            # Stopping because no layouts can be exported safely
            raise RuntimeError(f"Could not read project: {qgis_project_file}")

        # Reading every invalid project layer
        invalid_layer_names = [
            layer.name()
            for layer in project.mapLayers().values()
            if not layer.isValid()
        ]

        # Stopping when the project contains any invalid layer
        if invalid_layer_names:
            # Stopping because invalid contextual data can corrupt outputs
            raise RuntimeError(
                "Project contains invalid layers: " + ", ".join(invalid_layer_names)
            )

        # Creating the staging parent directory
        output_directory.parent.mkdir(
            parents=True,
            exist_ok=True,
        )

        # Creating an isolated staging directory for the complete batch
        with tempfile.TemporaryDirectory(
            prefix="scenario_map_exports_",
            dir=output_directory.parent,
        ) as temporary_directory:
            # Defining the isolated staging directory
            staging_directory = Path(temporary_directory)

            # Initializing validated map-export records
            export_records: list[dict[str, object]] = []

            # Staging and validating every configured map export
            for export_specification in map_export_specifications:
                # Storing the validated staged map record
                export_records.append(
                    stage_map_export(
                        project=project,
                        export_specification=export_specification,
                        staging_directory=staging_directory,
                    )
                )

            # Stopping unless every configured map was validated
            if len(export_records) != expected_export_count:
                # Stopping before any final output can be replaced
                raise RuntimeError(
                    f"Validated {len(export_records)} exports; expected "
                    f"{expected_export_count}."
                )

            # Installing all validated staged maps
            install_staged_exports(
                export_records=export_records,
                output_directory=output_directory,
            )

            # Writing the complete export-validation report
            write_export_report(
                export_records=export_records,
                report_file=report_file,
            )

        # Reporting the completed export count
        print(f"exported_maps={expected_export_count}")

        # Reporting the final map-output directory
        print(f"output_directory={output_directory}")

        # Reporting the export-validation report
        print(f"report={report_file}")

        # Returning the successful script status
        return 0

    # Releasing QGIS resources after success or failure
    finally:
        # Clearing the in-memory project
        QgsProject.instance().clear()

        # Shutting down the QGIS application
        qgis_application.exitQgis()


################################################################################
##### VI. Execution
################################################################################

# Running the script during whole-file execution
if __name__ == "__main__":
    # Stopping because the required export condition is not met
    raise SystemExit(main())
