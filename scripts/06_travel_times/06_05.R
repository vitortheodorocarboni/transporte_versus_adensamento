################################################################################
##################################            ##################################
############### 06.05) MAP TRAVEL-TIME MATRIX SUMMARY BY OD ZONE ##############
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

# Retrieving full long-form travel-time grid (from 06_04; contains all
# 343 x 343 pairs plus the pair-level CSM sample flag)
matrix_input <- processed_path("travel_times", "matrix_full.parquet")

# Retrieving complete OD dataset (sample flag and zone geometry, from 05_01)
od_input <- processed_path("final_dataset", "od_complete.parquet")

# Setting travel-times output directory
output_directory <- processed_path("travel_times")

# Setting output file path
matrix_summary_output <- file.path(output_directory, "matrix_sample_zone_means.parquet")


################################################################################
##### III. Data
################################################################################

# Reading complete OD dataset
od_dataset <- read_geoparquet_sf(od_input)

# Extracting OD zones kept in the CSM sample
od_sample <- od_dataset %>%
  filter(sample) %>%
  select(zona) %>%
  arrange(zona)

# Reading long-form travel-time grid and filtering to the CSM sub-grid
csm_zones <- sort(od_sample$zona)
matrix_sample <- read_parquet(matrix_input) %>%
  filter(sample == 1) %>%
  select(from_id, to_id, travel_time) %>%
  pivot_wider(
    names_from  = to_id,
    values_from = travel_time
  ) %>%
  column_to_rownames(var = "from_id") %>%
  as.matrix()
matrix_sample <- matrix_sample[csm_zones, csm_zones]

# Listing matrix zones
matrix_origin_zones      <- rownames(matrix_sample)
matrix_destination_zones <- colnames(matrix_sample)




################################################################################
##### IV. Computing row and column means
################################################################################

# Computing mean travel time by origin (row mean) and by destination (column mean)
matrix_summary <- tibble(
  zona                  = matrix_origin_zones,
  row_mean_travel_time  = as.numeric(rowMeans(matrix_sample)),
  col_mean_travel_time  = as.numeric(colMeans(matrix_sample))
)

# Joining matrix summaries to OD polygons
matrix_summary_sf <- od_sample %>%
  left_join(matrix_summary, by = "zona") %>%
  arrange(zona)



################################################################################
##### V. Exporting outputs
################################################################################

# Creating output directory
dir.create(
  path         = output_directory,
  recursive    = TRUE,
  showWarnings = FALSE
)

# Saving matrix summary as GeoParquet file
write_parquet(
  x    = matrix_summary_sf,
  sink = matrix_summary_output
)
