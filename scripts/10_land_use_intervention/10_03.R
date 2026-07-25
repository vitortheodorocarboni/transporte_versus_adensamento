################################################################################
##################################            ##################################
############### 10.03) AGGREGATE IPTU DATA AT THE OD GRID LEVEL ################
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

# Retrieving geolocated IPTU data file
iptu_file <- processed_path("built_area", "iptu_2025_georreferenced.parquet")

# Retrieving 2023 OD processed shapes file
od_file <- processed_path("shapes", "od_2023_shapes.parquet")

# Setting output data directory path
output_directory <- processed_path("built_area")

# Setting output data file path
output_file <- file.path(output_directory, "iptu_2025_od.parquet")


################################################################################
##### III. Data
################################################################################

# Reading 2023 OD shapes dataset
od <- read_geoparquet_sf(od_file)

# Reading IPTU geolocated dataset
iptu <- read_geoparquet_sf(iptu_file) %>%
  st_transform(st_crs(od))


################################################################################
##### IV. Aggregating IPTU data
################################################################################

# Tagging each point with its containing OD zone
iptu_od <- st_join(
  x    = iptu,
  y    = od %>% select(zona),
  left = FALSE
) %>% 
  # Aggregating IPTU records at the OD zone level
  st_set_geometry(NULL) %>%
  group_by(zona) %>%
  summarize(
    built_area         = sum(built_area, na.rm = TRUE),
    land_area          = sum(land_area, na.rm = TRUE),
    occupied_area      = sum(occupied_area, na.rm = TRUE),
    land_value         = median(land_value, na.rm = TRUE),
    construction_value = median(construction_value, na.rm = TRUE),
    .groups = "drop"
  )

# Merging everything in a single object (zones with no IPTU records get sums = 0
# and medians = NA)
iptu_od <- od %>%
  left_join(iptu_od, by = "zona") %>%
  mutate(
    built_area    = replace_na(built_area, 0),
    land_area     = replace_na(land_area, 0),
    occupied_area = replace_na(occupied_area, 0)
  ) %>%
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

# Saving IPTU OD dataset as GeoParquet file
write_parquet(
  x    = iptu_od,
  sink = output_file
)
