################################################################################
##################################            ##################################
####################### 03.01) VALIDATE RESULT SYMBOLOGY #######################
##################################            ##################################
################################################################################

# This script validates exact renderer structure, class coverage and source-data
# contracts for the baseline, transport and land-use layers in the QGIS project.

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

# Defining the validation-report output file
validation_report_file = (
    project_root_directory
    / "qgis"
    / "classifications"
    / "results_symbology_validation.csv"
)


################################################################################
##### III. Parameters
################################################################################

# Defining the required number of observations in every result layer
expected_observation_count = 325

# Defining the expected result-group prefixes and source directories
result_group_specifications = {
    "base": {
        "layer_prefix": "Base ",
        "source_prefix": "../../data/results/baseline_scenario/",
    },
    "transport": {
        "layer_prefix": "Transporte ",
        "source_prefix": "../../data/results/transport_scenario/",
    },
    "adensamento": {
        "layer_prefix": "Adensamento ",
        "source_prefix": "../../data/results/land_use_scenario/",
    },
}

# Defining the exact baseline layer contracts
baseline_layer_specifications = {
    "Base acessibilidade": (
        "baseline_scenario.parquet",
        "market_access",
    ),
    "Base acessibilidade firmas": (
        "baseline_scenario.parquet",
        "firm_market_access",
    ),
    "Base amenidades": (
        "model_inversion.parquet",
        "amenities",
    ),
    "Base bem-estar": (
        "baseline_scenario.parquet",
        "welfare",
    ),
    "Base densidade construtiva": (
        "model_inversion.parquet",
        "density_land_development",
    ),
    "Base fundamentos produtivos": (
        "model_inversion.parquet",
        "production_fundamentals",
    ),
    "Base fundamentos residenciais": (
        "model_inversion.parquet",
        "residential_fundamentals",
    ),
    "Base produtividade": (
        "model_inversion.parquet",
        "productivity",
    ),
    "Base produto": (
        "baseline_scenario.parquet",
        "output",
    ),
    "Base renda": (
        "baseline_scenario.parquet",
        "income",
    ),
    "Base salário": (
        "model_inversion.parquet",
        "wage",
    ),
}

# Defining the shared scenario layer attributes
scenario_layer_attributes = {
    "acessibilidade": "market_access",
    "acessibilidade firmas": "firm_market_access",
    "amenidades": "amenities",
    "bem-estar": "welfare",
    "empregos": "workplaces",
    "preço": "floorspace_price",
    "produtividade": "productivity",
    "produto": "output",
    "renda": "income",
    "residentes": "residents",
    "salário": "wage",
}

# Initializing the exact result-layer contracts
result_layer_specifications: dict[str, dict[str, str]] = {}

# Registering every baseline layer contract
for layer_name, (
    source_file_name,
    attribute_name,
) in baseline_layer_specifications.items():
    # Constructing the exact baseline source
    expected_source = (
        result_group_specifications["base"]["source_prefix"] + source_file_name
    )

    # Storing the baseline layer contract
    result_layer_specifications[layer_name] = {
        "group": "base",
        "source": expected_source,
        "attribute": attribute_name,
    }

# Registering every transport layer contract
for layer_suffix, attribute_name in scenario_layer_attributes.items():
    # Constructing the transport layer name
    layer_name = f"Transporte {layer_suffix}"

    # Storing the transport layer contract
    result_layer_specifications[layer_name] = {
        "group": "transport",
        "source": (
            result_group_specifications["transport"]["source_prefix"]
            + "transport_variation.parquet"
        ),
        "attribute": attribute_name,
    }

# Registering every land-use layer contract
for layer_suffix, attribute_name in scenario_layer_attributes.items():
    # Constructing the land-use layer name
    layer_name = f"Adensamento {layer_suffix}"

    # Storing the land-use layer contract
    result_layer_specifications[layer_name] = {
        "group": "adensamento",
        "source": (
            result_group_specifications["adensamento"]["source_prefix"]
            + "land_use_variation.parquet"
        ),
        "attribute": attribute_name,
    }

# Defining the ordered validation-report fields
validation_report_fields = [
    "group",
    "layer",
    "source",
    "expected_source",
    "provider",
    "renderer_type",
    "attribute",
    "expected_attribute",
    "classes",
    "expected_classes",
    "parquet_rows",
    "numeric_observations",
    "missing_observations",
    "invalid_observations",
    "nonfinite_observations",
    "covered_observations",
    "exactly_once_observations",
    "uncovered_observations",
    "multiply_covered_observations",
    "empty_classes",
    "min_value",
    "first_lower",
    "exact_minimum",
    "max_value",
    "last_upper",
    "exact_maximum",
    "strictly_increasing_ranges",
    "contiguous_ranges",
    "canonical_boundaries",
    "zero_boundary",
    "valid_symbol_references",
    "status",
    "issues",
]


################################################################################
##### IV. Functions
################################################################################


# Defining the normalized-datasource function
def normalize_datasource(datasource: str) -> str:
    """Normalize one QGIS datasource path without changing its relativity."""

    # Separating the file path from optional provider parameters
    datasource_path = datasource.split("|", 1)[0]

    # Normalizing path separators for exact contract comparison
    normalized_datasource = datasource_path.replace("\\", "/")

    # Returning the normalized datasource
    return normalized_datasource


# Defining the QGIS-project XML reading function
def read_qgis_project_root(project_file: Path) -> ET.Element:
    """Read and parse the unique QGS member in one QGIS project archive."""

    # Stopping when the configured project archive is unavailable
    if not project_file.is_file():
        # Stopping because validation requires an existing project archive
        raise FileNotFoundError(f"QGIS project not found: {project_file}")

    # Opening the QGIS project archive
    with zipfile.ZipFile(project_file, "r") as archive:
        # Listing the project XML members
        project_members = [
            member_name
            for member_name in archive.namelist()
            if member_name.lower().endswith(".qgs")
        ]

        # Stopping unless the archive contains exactly one project XML
        if len(project_members) != 1:
            # Stopping because the project member would be ambiguous
            raise ValueError(
                "The QGIS archive must contain exactly one QGS member; found "
                f"{len(project_members)}."
            )

        # Reading the unique project XML payload
        project_xml = archive.read(project_members[0])

    # Parsing the project XML payload
    project_root = ET.fromstring(project_xml)

    # Returning the parsed project root
    return project_root


# Defining the finite-value profile function
def read_field_profile(
    parquet_file: Path,
    attribute_name: str,
) -> dict[str, object]:
    """Read one Parquet field and profile every stored observation."""

    # Reading the requested Parquet field
    parquet_table = pq.read_table(
        parquet_file,
        columns=[attribute_name],
    )

    # Converting the complete field to Python values
    stored_values = parquet_table.column(attribute_name).to_pylist()

    # Initializing the finite numeric values
    numeric_values: list[float] = []

    # Initializing missing-observation count
    missing_observations = 0

    # Initializing invalid-observation count
    invalid_observations = 0

    # Initializing nonfinite-observation count
    nonfinite_observations = 0

    # Profiling every stored field value
    for stored_value in stored_values:
        # Counting missing observations explicitly
        if stored_value is None:
            # Updating the missing-observation count
            missing_observations += 1

            # Continuing with the next stored value
            continue

        # Attempting to convert the stored value to a float
        try:
            # Converting the stored value to a numeric value
            numeric_value = float(stored_value)

        # Handling values that cannot be interpreted numerically
        except (TypeError, ValueError):
            # Updating the invalid-observation count
            invalid_observations += 1

            # Continuing with the next stored value
            continue

        # Counting nonfinite numeric observations explicitly
        if not math.isfinite(numeric_value):
            # Updating the nonfinite-observation count
            nonfinite_observations += 1

            # Continuing with the next stored value
            continue

        # Storing the finite numeric observation
        numeric_values.append(numeric_value)

    # Constructing the complete field profile
    field_profile = {
        "parquet_rows": parquet_table.num_rows,
        "numeric_values": numeric_values,
        "missing_observations": missing_observations,
        "invalid_observations": invalid_observations,
        "nonfinite_observations": nonfinite_observations,
    }

    # Returning the complete field profile
    return field_profile


# Defining the renderer-range parsing function
def parse_renderer_ranges(
    renderer_node: ET.Element | None,
) -> tuple[list[dict[str, object]], list[str]]:
    """Parse graduated renderer ranges and record malformed endpoints."""

    # Initializing parsed range records
    parsed_ranges: list[dict[str, object]] = []

    # Initializing range parsing issues
    issues: list[str] = []

    # Returning an empty result when no renderer is available
    if renderer_node is None:
        # Recording the missing renderer
        issues.append("missing_renderer")

        # Returning the empty parsing result
        return parsed_ranges, issues

    # Reading every stored renderer range
    range_nodes = renderer_node.findall("./ranges/range")

    # Recording the absence of graduated ranges
    if not range_nodes:
        # Recording the missing ranges
        issues.append("missing_ranges")

    # Parsing every stored renderer range
    for range_index, range_node in enumerate(range_nodes):
        # Reading the raw lower endpoint
        lower_text = range_node.get("lower")

        # Reading the raw upper endpoint
        upper_text = range_node.get("upper")

        # Initializing the parsed lower endpoint
        lower_value = float("nan")

        # Initializing the parsed upper endpoint
        upper_value = float("nan")

        # Parsing the lower endpoint when available
        try:
            # Converting the lower endpoint to float
            lower_value = float(lower_text)

        # Recording a missing or invalid lower endpoint
        except (TypeError, ValueError):
            # Recording the lower-endpoint issue
            issues.append(f"invalid_lower_{range_index + 1}")

        # Parsing the upper endpoint when available
        try:
            # Converting the upper endpoint to float
            upper_value = float(upper_text)

        # Recording a missing or invalid upper endpoint
        except (TypeError, ValueError):
            # Recording the upper-endpoint issue
            issues.append(f"invalid_upper_{range_index + 1}")

        # Recording nonfinite lower endpoints
        if not math.isfinite(lower_value):
            # Recording the nonfinite lower-endpoint issue
            issues.append(f"nonfinite_lower_{range_index + 1}")

        # Recording nonfinite upper endpoints
        if not math.isfinite(upper_value):
            # Recording the nonfinite upper-endpoint issue
            issues.append(f"nonfinite_upper_{range_index + 1}")

        # Defining canonical lower-endpoint serialization
        canonical_lower = (
            lower_text == repr(lower_value) if math.isfinite(lower_value) else False
        )

        # Defining canonical upper-endpoint serialization
        canonical_upper = (
            upper_text == repr(upper_value) if math.isfinite(upper_value) else False
        )

        # Storing the parsed range record
        parsed_ranges.append(
            {
                "lower": lower_value,
                "upper": upper_value,
                "lower_text": lower_text or "",
                "upper_text": upper_text or "",
                "canonical": canonical_lower and canonical_upper,
                "symbol": range_node.get("symbol") or "",
                "label": range_node.get("label") or "",
                "render": range_node.get("render", "true"),
            }
        )

    # Returning parsed ranges and their issues
    return parsed_ranges, issues


# Defining the expected-class count function
def expected_class_count(
    group_name: str,
    values: list[float],
) -> int:
    """Return the class-count contract implied by the updater methodology."""

    # Returning the fixed baseline class count
    if group_name == "base":
        # Returning ten baseline quantile classes
        return 10

    # Counting strictly negative observations
    negative_observations = sum(value < 0 for value in values)

    # Counting zero and positive observations
    nonnegative_observations = sum(value >= 0 for value in values)

    # Returning five classes for a one-sided distribution
    if negative_observations == 0 or nonnegative_observations == 0:
        # Returning the one-sided Jenks class count
        return 5

    # Returning six classes when either side has fewer than fifteen values
    if min(negative_observations, nonnegative_observations) < 15:
        # Returning the scarce-sign class count
        return 6

    # Returning the general five-by-five diverging class count
    return 10


# Defining the exact coverage calculation function
def calculate_exact_coverage(
    values: list[float],
    ranges: list[dict[str, object]],
) -> dict[str, object]:
    """Assign values to half-open classes without numeric tolerance."""

    # Initializing the class-observation counts
    class_observation_counts = [0 for _range in ranges]

    # Initializing the observation match counts
    observation_match_counts: list[int] = []

    # Matching every value against every renderer class
    for value in values:
        # Initializing the current observation match count
        observation_match_count = 0

        # Inspecting every renderer class
        for range_index, range_record in enumerate(ranges):
            # Reading the lower class endpoint
            lower_bound = float(range_record["lower"])

            # Reading the upper class endpoint
            upper_bound = float(range_record["upper"])

            # Identifying the final renderer class
            is_last_class = range_index == len(ranges) - 1

            # Matching the final class with an inclusive upper endpoint
            if is_last_class:
                # Defining the final-class membership
                belongs_to_class = lower_bound <= value <= upper_bound

            # Matching intermediate classes with exclusive upper endpoints
            else:
                # Defining the intermediate-class membership
                belongs_to_class = lower_bound <= value < upper_bound

            # Counting the current class match
            if belongs_to_class:
                # Updating the class-observation count
                class_observation_counts[range_index] += 1

                # Updating the observation match count
                observation_match_count += 1

        # Storing the current observation match count
        observation_match_counts.append(observation_match_count)

    # Counting observations covered by at least one class
    covered_observations = sum(
        match_count >= 1 for match_count in observation_match_counts
    )

    # Counting observations covered exactly once
    exactly_once_observations = sum(
        match_count == 1 for match_count in observation_match_counts
    )

    # Counting observations not covered by any class
    uncovered_observations = sum(
        match_count == 0 for match_count in observation_match_counts
    )

    # Counting observations covered by multiple classes
    multiply_covered_observations = sum(
        match_count > 1 for match_count in observation_match_counts
    )

    # Counting empty renderer classes
    empty_classes = sum(
        observation_count == 0 for observation_count in class_observation_counts
    )

    # Constructing the exact coverage profile
    coverage_profile = {
        "covered_observations": covered_observations,
        "exactly_once_observations": exactly_once_observations,
        "uncovered_observations": uncovered_observations,
        "multiply_covered_observations": (multiply_covered_observations),
        "empty_classes": empty_classes,
    }

    # Returning the exact coverage profile
    return coverage_profile


# Defining the empty validation-row function
def empty_validation_row(
    layer_name: str,
    layer_specification: dict[str, str],
) -> dict[str, object]:
    """Create one complete blank validation row for a required layer."""

    # Constructing the blank validation row
    validation_row = {field_name: "" for field_name in validation_report_fields}

    # Recording the expected layer group
    validation_row["group"] = layer_specification["group"]

    # Recording the expected layer name
    validation_row["layer"] = layer_name

    # Recording the expected datasource
    validation_row["expected_source"] = layer_specification["source"]

    # Recording the expected renderer attribute
    validation_row["expected_attribute"] = layer_specification["attribute"]

    # Recording the failed status
    validation_row["status"] = "check"

    # Returning the blank validation row
    return validation_row


# Defining the layer-candidate matching function
def is_result_layer_candidate(
    layer_name: str,
    datasource: str,
) -> bool:
    """Identify layers that occupy one configured result-layer namespace."""

    # Normalizing the current layer datasource
    normalized_datasource = normalize_datasource(datasource)

    # Inspecting every result-group namespace
    for group_specification in result_group_specifications.values():
        # Reading the configured layer-name prefix
        layer_prefix = group_specification["layer_prefix"]

        # Reading the configured source-directory prefix
        source_prefix = group_specification["source_prefix"]

        # Returning true for a name-and-source namespace match
        if layer_name.startswith(layer_prefix) and normalized_datasource.startswith(
            source_prefix
        ):
            # Returning the positive candidate result
            return True

    # Returning the negative candidate result
    return False


# Defining the exact layer-validation function
def validate_result_layer(
    map_layer: ET.Element,
    layer_name: str,
    layer_specification: dict[str, str],
    project_file: Path,
) -> dict[str, object]:
    """Validate one project layer against its exact data and renderer contract."""

    # Initializing the validation row
    validation_row = empty_validation_row(
        layer_name=layer_name,
        layer_specification=layer_specification,
    )

    # Initializing the layer issues
    issues: list[str] = []

    # Reading the raw datasource
    datasource = map_layer.findtext("datasource") or ""

    # Normalizing the datasource
    normalized_datasource = normalize_datasource(datasource)

    # Recording the normalized datasource
    validation_row["source"] = normalized_datasource

    # Recording a datasource mismatch
    if normalized_datasource != layer_specification["source"]:
        # Recording the exact source-contract issue
        issues.append("source_mismatch")

    # Reading the layer provider
    provider_name = map_layer.findtext("provider") or ""

    # Recording the layer provider
    validation_row["provider"] = provider_name

    # Recording an unexpected layer provider
    if provider_name != "ogr":
        # Recording the provider-contract issue
        issues.append("provider_mismatch")

    # Reading the graduated renderer
    renderer_node = map_layer.find("renderer-v2")

    # Reading the renderer type
    renderer_type = renderer_node.get("type", "") if renderer_node is not None else ""

    # Recording the renderer type
    validation_row["renderer_type"] = renderer_type

    # Recording an unexpected renderer type
    if renderer_type != "graduatedSymbol":
        # Recording the renderer-type issue
        issues.append("renderer_type")

    # Reading the renderer attribute
    attribute_name = renderer_node.get("attr", "") if renderer_node is not None else ""

    # Recording the renderer attribute
    validation_row["attribute"] = attribute_name

    # Recording a renderer-attribute mismatch
    if attribute_name != layer_specification["attribute"]:
        # Recording the exact attribute-contract issue
        issues.append("attribute_mismatch")

    # Parsing every renderer range without tolerance
    ranges, range_issues = parse_renderer_ranges(
        renderer_node=renderer_node,
    )

    # Extending the layer issues with range parsing issues
    issues.extend(range_issues)

    # Recording the stored renderer class count
    validation_row["classes"] = len(ranges)

    # Defining the full Parquet path
    parquet_file = (project_file.parent / normalized_datasource).resolve()

    # Checking that the resolved source remains inside the project root
    source_inside_project = parquet_file.is_relative_to(project_root_directory)

    # Recording a source path that escapes the project
    if not source_inside_project:
        # Recording the unsafe source-path issue
        issues.append("source_outside_project")

    # Recording an unavailable Parquet source
    if not parquet_file.is_file():
        # Recording the missing source-file issue
        issues.append("missing_source_file")

    # Initializing the finite numeric values
    numeric_values: list[float] = []

    # Reading the source field only when path and attribute are usable
    if source_inside_project and parquet_file.is_file() and bool(attribute_name):
        # Attempting to read and profile the configured source field
        try:
            # Reading the complete field profile
            field_profile = read_field_profile(
                parquet_file=parquet_file,
                attribute_name=attribute_name,
            )

        # Recording source-schema or field-reading failures
        except (KeyError, OSError, ValueError) as error:
            # Recording the field-reading issue
            issues.append(f"field_read_error:{type(error).__name__}")

        # Recording the successfully read field profile
        else:
            # Reading the finite numeric values
            numeric_values = list(field_profile["numeric_values"])

            # Recording the complete Parquet row count
            validation_row["parquet_rows"] = field_profile["parquet_rows"]

            # Recording the finite numeric-observation count
            validation_row["numeric_observations"] = len(numeric_values)

            # Recording the missing-observation count
            validation_row["missing_observations"] = field_profile[
                "missing_observations"
            ]

            # Recording the invalid-observation count
            validation_row["invalid_observations"] = field_profile[
                "invalid_observations"
            ]

            # Recording the nonfinite-observation count
            validation_row["nonfinite_observations"] = field_profile[
                "nonfinite_observations"
            ]

            # Recording an unexpected Parquet row count
            if field_profile["parquet_rows"] != expected_observation_count:
                # Recording the row-count contract issue
                issues.append("parquet_row_count")

            # Recording missing stored observations
            if field_profile["missing_observations"] != 0:
                # Recording the missing-observation issue
                issues.append("missing_observations")

            # Recording nonnumeric stored observations
            if field_profile["invalid_observations"] != 0:
                # Recording the invalid-observation issue
                issues.append("invalid_observations")

            # Recording nonfinite numeric observations
            if field_profile["nonfinite_observations"] != 0:
                # Recording the nonfinite-observation issue
                issues.append("nonfinite_observations")

            # Recording an unexpected finite-observation count
            if len(numeric_values) != expected_observation_count:
                # Recording the finite-observation count issue
                issues.append("numeric_observation_count")

    # Calculating the methodological class-count contract
    expected_classes = (
        expected_class_count(
            group_name=layer_specification["group"],
            values=numeric_values,
        )
        if numeric_values
        else ""
    )

    # Recording the expected class count
    validation_row["expected_classes"] = expected_classes

    # Recording a class-count mismatch
    if expected_classes != "" and len(ranges) != expected_classes:
        # Recording the class-count contract issue
        issues.append("class_count")

    # Defining strict range ordering
    strictly_increasing_ranges = bool(ranges) and all(
        math.isfinite(float(range_record["lower"]))
        and math.isfinite(float(range_record["upper"]))
        and float(range_record["lower"]) < float(range_record["upper"])
        for range_record in ranges
    )

    # Recording strict range ordering
    validation_row["strictly_increasing_ranges"] = strictly_increasing_ranges

    # Recording invalid range ordering
    if not strictly_increasing_ranges:
        # Recording the strict-ordering issue
        issues.append("range_order")

    # Defining exact numeric and serialized boundary contiguity
    contiguous_ranges = bool(ranges) and all(
        float(current_range["upper"]) == float(next_range["lower"])
        and current_range["upper_text"] == next_range["lower_text"]
        for current_range, next_range in zip(ranges, ranges[1:])
    )

    # Recording exact range contiguity
    validation_row["contiguous_ranges"] = contiguous_ranges

    # Recording noncontiguous ranges
    if not contiguous_ranges:
        # Recording the range-contiguity issue
        issues.append("range_contiguity")

    # Defining canonical endpoint serialization
    canonical_boundaries = bool(ranges) and all(
        bool(range_record["canonical"]) for range_record in ranges
    )

    # Recording canonical endpoint serialization
    validation_row["canonical_boundaries"] = canonical_boundaries

    # Recording noncanonical endpoint serialization
    if not canonical_boundaries:
        # Recording the canonical-serialization issue
        issues.append("boundary_serialization")

    # Reading every renderer symbol name
    renderer_symbol_names = (
        [
            symbol_node.get("name", "")
            for symbol_node in renderer_node.findall("./symbols/symbol")
        ]
        if renderer_node is not None
        else []
    )

    # Reading every range symbol reference
    range_symbol_references = [str(range_record["symbol"]) for range_record in ranges]

    # Defining valid one-to-one symbol references
    valid_symbol_references = (
        bool(ranges)
        and len(renderer_symbol_names) == len(ranges)
        and len(set(renderer_symbol_names)) == len(renderer_symbol_names)
        and len(set(range_symbol_references)) == len(range_symbol_references)
        and set(range_symbol_references) == set(renderer_symbol_names)
        and all(
            bool(range_record["label"]) and range_record["render"] == "true"
            for range_record in ranges
        )
    )

    # Recording renderer symbol-reference validity
    validation_row["valid_symbol_references"] = valid_symbol_references

    # Recording invalid symbol references
    if not valid_symbol_references:
        # Recording the symbol-reference issue
        issues.append("symbol_references")

    # Defining the scenario zero-boundary contract
    if (
        layer_specification["group"] != "base"
        and numeric_values
        and any(value < 0 for value in numeric_values)
        and any(value >= 0 for value in numeric_values)
    ):
        # Checking the presence of a canonically serialized zero boundary
        zero_boundary = any(
            range_record["upper_text"] == "0.0" for range_record in ranges[:-1]
        )

    # Treating the zero boundary as unnecessary for other distributions
    else:
        # Recording the nonapplicable zero-boundary contract as satisfied
        zero_boundary = True

    # Recording the zero-boundary contract
    validation_row["zero_boundary"] = zero_boundary

    # Recording a missing scenario zero boundary
    if not zero_boundary:
        # Recording the zero-boundary issue
        issues.append("zero_boundary")

    # Calculating exact class coverage when values and ranges are available
    if numeric_values and ranges:
        # Calculating the exact coverage profile
        coverage_profile = calculate_exact_coverage(
            values=numeric_values,
            ranges=ranges,
        )

        # Recording every exact coverage metric
        for metric_name, metric_value in coverage_profile.items():
            # Storing the current coverage metric
            validation_row[metric_name] = metric_value

        # Recording incomplete observation coverage
        if coverage_profile["covered_observations"] != expected_observation_count:
            # Recording the incomplete-coverage issue
            issues.append("coverage")

        # Recording observations not assigned exactly once
        if coverage_profile["exactly_once_observations"] != expected_observation_count:
            # Recording the nonunique-coverage issue
            issues.append("exactly_once_coverage")

        # Recording empty renderer classes
        if coverage_profile["empty_classes"] != 0:
            # Recording the empty-class issue
            issues.append("empty_classes")

        # Calculating the exact observed minimum
        minimum_value = min(numeric_values)

        # Calculating the exact observed maximum
        maximum_value = max(numeric_values)

        # Reading the first renderer lower endpoint
        first_lower = float(ranges[0]["lower"])

        # Reading the final renderer upper endpoint
        last_upper = float(ranges[-1]["upper"])

        # Recording the exact observed minimum
        validation_row["min_value"] = repr(minimum_value)

        # Recording the first renderer lower endpoint
        validation_row["first_lower"] = ranges[0]["lower_text"]

        # Defining exact minimum matching
        exact_minimum = first_lower == minimum_value

        # Recording exact minimum matching
        validation_row["exact_minimum"] = exact_minimum

        # Recording an inexact minimum endpoint
        if not exact_minimum:
            # Recording the minimum-endpoint issue
            issues.append("minimum_endpoint")

        # Recording the exact observed maximum
        validation_row["max_value"] = repr(maximum_value)

        # Recording the final renderer upper endpoint
        validation_row["last_upper"] = ranges[-1]["upper_text"]

        # Defining exact maximum matching
        exact_maximum = last_upper == maximum_value

        # Recording exact maximum matching
        validation_row["exact_maximum"] = exact_maximum

        # Recording an inexact maximum endpoint
        if not exact_maximum:
            # Recording the maximum-endpoint issue
            issues.append("maximum_endpoint")

    # Removing duplicate issue labels while preserving their order
    unique_issues = list(dict.fromkeys(issues))

    # Recording the final validation status
    validation_row["status"] = "ok" if not unique_issues else "check"

    # Recording the actionable issue summary
    validation_row["issues"] = ";".join(unique_issues)

    # Returning the complete layer validation row
    return validation_row


# Defining the validation-report writing function
def write_validation_report(
    rows: list[dict[str, object]],
    report_file: Path,
) -> None:
    """Write validation rows atomically as a UTF-8 CSV report."""

    # Creating the validation-report output directory
    report_file.parent.mkdir(
        parents=True,
        exist_ok=True,
    )

    # Defining the temporary validation-report file
    temporary_report_file = report_file.with_suffix(report_file.suffix + ".tmp")

    # Opening the temporary report output file
    with temporary_report_file.open(
        "w",
        newline="",
        encoding="utf-8",
    ) as handle:
        # Creating the validation-report writer
        writer = csv.DictWriter(
            handle,
            fieldnames=validation_report_fields,
        )

        # Writing the validation-report header
        writer.writeheader()

        # Writing every validation-report row
        writer.writerows(rows)

    # Replacing the prior report with the complete temporary output
    temporary_report_file.replace(report_file)


################################################################################
##### V. Symbology validation
################################################################################


# Defining the main result-symbology validation function
def main(
    project_file: Path = qgis_project_file,
    report_file: Path = validation_report_file,
) -> int:
    """Validate all required result layers and export an exact audit report."""

    # Reading and parsing the configured QGIS project
    project_root = read_qgis_project_root(project_file=project_file)

    # Reading every project map layer
    map_layers = project_root.findall("./projectlayers/maplayer")

    # Indexing project layers by visible name
    map_layers_by_name: dict[str, list[ET.Element]] = {}

    # Registering every project layer by visible name
    for map_layer in map_layers:
        # Reading the current visible layer name
        layer_name = map_layer.findtext("layername") or ""

        # Adding the current layer to its name index
        map_layers_by_name.setdefault(layer_name, []).append(map_layer)

    # Initializing validation-report rows
    validation_rows: list[dict[str, object]] = []

    # Initializing observed required-layer counts
    observed_group_counts = {
        group_name: 0 for group_name in result_group_specifications
    }

    # Validating every exact result-layer contract
    for layer_name, layer_specification in result_layer_specifications.items():
        # Reading all project layers with the required visible name
        matching_layers = map_layers_by_name.get(layer_name, [])

        # Handling a missing required layer
        if not matching_layers:
            # Creating the missing-layer validation row
            validation_row = empty_validation_row(
                layer_name=layer_name,
                layer_specification=layer_specification,
            )

            # Recording the missing-layer issue
            validation_row["issues"] = "missing_layer"

            # Storing the missing-layer validation row
            validation_rows.append(validation_row)

            # Continuing with the next required layer
            continue

        # Validating the first project layer with the required name
        validation_row = validate_result_layer(
            map_layer=matching_layers[0],
            layer_name=layer_name,
            layer_specification=layer_specification,
            project_file=project_file,
        )

        # Recording duplicate visible layer names
        if len(matching_layers) != 1:
            # Reading the existing issue summary
            existing_issues = str(validation_row["issues"])

            # Appending the duplicate-layer issue
            validation_row["issues"] = ";".join(
                issue
                for issue in (
                    existing_issues,
                    "duplicate_layer_name",
                )
                if issue
            )

            # Recording the failed validation status
            validation_row["status"] = "check"

        # Updating the observed required-layer count
        observed_group_counts[layer_specification["group"]] += 1

        # Storing the complete validation row
        validation_rows.append(validation_row)

    # Identifying unexpected layers in the configured result namespaces
    for map_layer in map_layers:
        # Reading the current visible layer name
        layer_name = map_layer.findtext("layername") or ""

        # Reading the current layer datasource
        datasource = map_layer.findtext("datasource") or ""

        # Skipping layers outside result namespaces
        if not is_result_layer_candidate(
            layer_name=layer_name,
            datasource=datasource,
        ):
            # Continuing with the next map layer
            continue

        # Skipping layers already represented by an exact contract
        if layer_name in result_layer_specifications:
            # Continuing with the next map layer
            continue

        # Identifying the unexpected layer group
        unexpected_group = next(
            group_name
            for group_name, group_specification in result_group_specifications.items()
            if (
                layer_name.startswith(group_specification["layer_prefix"])
                and normalize_datasource(datasource).startswith(
                    group_specification["source_prefix"]
                )
            )
        )

        # Constructing the unexpected-layer report row
        unexpected_row = {field_name: "" for field_name in validation_report_fields}

        # Recording the unexpected layer group
        unexpected_row["group"] = unexpected_group

        # Recording the unexpected layer name
        unexpected_row["layer"] = layer_name

        # Recording the unexpected datasource
        unexpected_row["source"] = normalize_datasource(datasource)

        # Recording the failed status
        unexpected_row["status"] = "check"

        # Recording the unexpected-layer issue
        unexpected_row["issues"] = "unexpected_result_layer"

        # Storing the unexpected-layer report row
        validation_rows.append(unexpected_row)

    # Sorting validation rows by group and layer
    validation_rows.sort(
        key=lambda row: (
            str(row["group"]),
            str(row["layer"]),
        )
    )

    # Writing the complete validation report atomically
    write_validation_report(
        rows=validation_rows,
        report_file=report_file,
    )

    # Selecting all failed validation rows
    failed_rows = [row for row in validation_rows if row["status"] != "ok"]

    # Reporting the validated required-layer count
    print(f"validated_layers={len(result_layer_specifications)}")

    # Reporting exact observed group counts
    print(
        "group_counts="
        + ",".join(
            (f"{group_name}:" f"{observed_group_counts[group_name]}")
            for group_name in result_group_specifications
        )
    )

    # Reporting the required observation contract
    print(f"expected_observations={expected_observation_count}")

    # Reporting the number of failed validation rows
    print(f"checks={len(failed_rows)}")

    # Reporting the validation-report location
    print(f"wrote={report_file}")

    # Reporting every failed validation row
    for failed_row in failed_rows:
        # Reporting the actionable layer issue summary
        print(
            f"CHECK {failed_row['group']} {failed_row['layer']}: "
            f"{failed_row['issues']}"
        )

    # Returning failure when any validation contract was violated
    if failed_rows:
        # Returning the failure script status
        return 1

    # Returning the successful script status
    return 0


################################################################################
##### VI. Execution
################################################################################

# Running the script during whole-file execution
if __name__ == "__main__":
    # Stopping because the required validation condition is not met
    raise SystemExit(main())
