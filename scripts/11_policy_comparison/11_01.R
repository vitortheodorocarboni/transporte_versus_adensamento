################################################################################
##################################            ##################################
############## 11.01) COMPARE WELFARE GAINS ACROSS POLICY SCENARIOS #############
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

# Retrieving transport scenario welfare variation file
transport_input <- results_path("transport_scenario", "transport_variation.parquet")

# Retrieving land-use scenario welfare variation file
land_use_input <- results_path("land_use_scenario", "land_use_variation.parquet")

# Setting policy comparison output directory
output_directory <- results_path("policy_comparison")

# Setting per-zone comparison output file path
comparison_output_file <- file.path(output_directory, "scenario_comparison.parquet")

# Setting comparison summary output file path
summary_output_file <- file.path(output_directory, "scenario_comparison_summary.parquet")


################################################################################
##### III. Data
################################################################################

# Reading transport scenario welfare variation (one row per OD zone)
transport_variation <- read_geoparquet_sf(transport_input) %>%
  st_drop_geometry() %>%
  select(zona, transport_welfare = welfare)

# Reading land-use scenario welfare variation (one row per OD zone)
land_use_variation <- read_geoparquet_sf(land_use_input) %>%
  select(zona, land_use_welfare = welfare)


################################################################################
##### IV. Comparison parameters
################################################################################

# Setting the welfare advantage threshold, in percentage points
advantage_threshold <- 0.01


################################################################################
##### V. Comparing welfare gains across scenarios
################################################################################

# Joining both scenarios and classifying the locally dominant policy
scenario_comparison <- land_use_variation %>%
  left_join(transport_variation, by = "zona") %>%
  mutate(
    welfare_difference = transport_welfare - land_use_welfare,
    advantage          = case_when(
      welfare_difference >  advantage_threshold ~ "transport",
      welfare_difference < -advantage_threshold ~ "land_use",
      TRUE                                      ~ "tie"
    )
  ) %>%
  select(
    zona,
    transport_welfare,
    land_use_welfare,
    welfare_difference,
    advantage,
    geometry
  )

# Counting the OD zones in which each policy dominates
scenario_comparison_summary <- scenario_comparison %>%
  st_drop_geometry() %>%
  group_by(advantage) %>%
  summarise(
    zones      = n(),
    mean_transport_welfare = mean(transport_welfare),
    mean_land_use_welfare  = mean(land_use_welfare),
    mean_welfare_difference = mean(welfare_difference),
    .groups = "drop"
  )


################################################################################
##### VI. Exporting outputs
################################################################################

# Creating output directory
dir.create(
  path         = output_directory,
  recursive    = TRUE,
  showWarnings = FALSE
)

# Saving per-zone scenario comparison as GeoParquet file
write_parquet(
  x    = scenario_comparison,
  sink = comparison_output_file
)

# Saving scenario comparison summary as Parquet file
write_parquet(
  x    = scenario_comparison_summary,
  sink = summary_output_file
)
