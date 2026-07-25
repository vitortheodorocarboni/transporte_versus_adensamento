################################################################################
##################################            ##################################
######### 09.04) COPY-PASTE THE OSM PBF TO THE COUNTERFACTUAL R5R CORE #########
##################################            ##################################
################################################################################

################################################################################
##### I. Directories and files
################################################################################

# Loading project paths
source(file.path("scripts", "_config", "paths.R"))

# Retrieving baseline r5r core directory path
baseline_directory <- raw_path("travel_times", "r5r_core")

# Retrieving baseline OSM file path
baseline_file <- file.path(baseline_directory, "sao_paulo.osm.pbf")

# Setting counterfactual r5r core directory path
counterfactual_directory <- processed_path("interventions", "transport_intervention", "r5r_core")

# Setting counterfactual OSM file path
counterfacutal_file <- file.path(counterfactual_directory, "sao_paulo.osm.pbf")


################################################################################
##### II. Copying file
################################################################################

# Creating counterfactual r5r core directory
dir.create(
  path         = counterfactual_directory,
  recursive    = TRUE,
  showWarnings = FALSE
)

# Copying baseline OSM PBF to counterfactual r5r core
file.copy(
  from      = baseline_file,
  to        = counterfacutal_file,
  overwrite = TRUE
)


# Reporting copy summary
copied_size_mb <- file.info(counterfacutal_file)$size / 1e6
message(
  "OSM PBF copied successfully to counterfactual r5r core. ",
  "Size: ", round(copied_size_mb, 1), " MB."
)
