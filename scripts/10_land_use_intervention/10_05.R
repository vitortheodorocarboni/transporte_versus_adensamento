################################################################################
##################################            ##################################
######### 10.05) COMPUTE PPP CENTRO HISTORICO COUNTERFACTUAL DENSITIES #########
##################################            ##################################
################################################################################

################################################################################
##### I. Packages
################################################################################

# # Installing packages
# install.packages("arrow")
# install.packages("geoarrow")
# install.packages("sf")
# install.packages("tidyverse")

# Loading libraries
library(arrow)
library(geoarrow)
library(sf)
library(tidyverse)


################################################################################
##### II. Directories and files
################################################################################

# Loading project paths
source(file.path("scripts", "_config", "paths.R"))

# Retrieving model inversion output file
inversion_input <- results_path("baseline_scenario", "model_inversion.parquet")

# Retrieving IPTU built-area dataset
iptu_input <- processed_path("built_area", "iptu_2025_od.parquet")

# Retrieving SINAPI-SP construction cost benchmark
sinapi_input <- processed_path("interventions", "land_use_intervention", "sinapi_sp_2025_m2_cost.parquet")

# Setting counterfactual densities output directory
output_directory <- processed_path("interventions", "land_use_intervention")

# Setting counterfactual densities output file path
density_output_file <- file.path(output_directory, "counterfactual_density.parquet")

# Setting spatial object of affected zones output file path
affected_output_file <- file.path(output_directory, "affected_zones.parquet")


################################################################################
##### III. Data
################################################################################

# Reading model inversion output (one row per OD zone in the CSM sample)
inversion_sf <- read_geoparquet_sf(inversion_input) %>%
  select(zona, density_land_development)

# Reading IPTU built-area dataset (one row per OD zone)
iptu_od <- read_geoparquet_sf(iptu_input) %>%
  st_drop_geometry()

# Reading SINAPI-SP construction cost benchmark (scalar, R$/m²)
m2_cost <- read_parquet(sinapi_input) %>%
  pull(m2_cost)


################################################################################
##### IV. Policy parameters
################################################################################

# Specifying OD zones affected by the PPP Centro Histórico intervention
zones_affected <- c(
  "od_001",
  "od_002",
  "od_003",
  "od_004",
  "od_005",
  "od_006",
  "od_035",
  "od_036"
)

# Setting public budget for the intervention 
budget <- 10.3e9


################################################################################
##### V. Computing the densification rate
################################################################################

# Computing the baseline floorspace on the affected ring 
baseline_floorspace <- iptu_od %>%
  filter(zona %in% zones_affected) %>%
  pull(built_area) %>%
  sum(na.rm = TRUE)

# Computing the additional floorspace the budget can build at SINAPI cost (m²)
additional_floorspace <- budget / m2_cost

# Computing the resulting densification rate
densification_rate <- additional_floorspace / baseline_floorspace


################################################################################
##### VI. Building the counterfactual density dataset
################################################################################

# Building the per-zone counterfactual density table
counterfactual_density <- inversion_sf %>%
  rename(baseline_density = density_land_development) %>%
  mutate(
    affected               = zona %in% zones_affected,
    counterfactual_density = if_else(
      condition = affected,
      true      = baseline_density * (1 + densification_rate),
      false     = baseline_density
    )
  ) %>%
  select(
    zona,
    affected,
    baseline_density,
    counterfactual_density
    )

# Separating affected zones
affected_sf <- counterfactual_density %>% 
  filter(affected) %>% 
  select(zona)


################################################################################
##### VII. Exporting outputs
################################################################################

# Creating output directory
dir.create(
  path         = output_directory,
  recursive    = TRUE,
  showWarnings = FALSE
)

# Saving counterfactual density dataset as GeoParquet file
write_parquet(
  x    = counterfactual_density,
  sink = density_output_file
)

# Saving affected zones as GeoParquet file
write_parquet(
  x    = affected_sf,
  sink = affected_output_file
)
