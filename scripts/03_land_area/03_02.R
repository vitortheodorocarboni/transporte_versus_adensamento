################################################################################
##################################            ##################################
##################### 03.02) COMPUTE LAND AREA PER OD ZONE #####################
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

# Retrieving 2023 OD processed shapes file path
od_input <- processed_path("shapes", "od_2023_shapes.parquet")

# Retrieving blocks dataset file path
blocks_input <- raw_path("land_area", "perimetro_zona_lei_18177_24.parquet")

# Retrieving plazas dataset file path
plazas_input <- raw_path("land_area", "GEOSAMPA_v_praca_largo.parquet")

# Setting output data directory path
output_directory <- processed_path("land_area")

# Setting output data file path
output_file <- file.path(output_directory, "land_area_dataset.parquet")


################################################################################
##### III. Data
################################################################################

# Reading 2023 OD od dataset
od <- read_geoparquet_sf(od_input)

# Reading blocks dataset (GeoSampa WFS layers are saved in EPSG:31983 but the
# CRS is not written by the GeoJSON pages, so we set it explicitly)
blocks <- read_geoparquet_sf(blocks_input) %>%
  st_set_crs(31983)

# Reading plazas dataset
plazas <- read_geoparquet_sf(plazas_input) %>%
  st_transform(31983)


################################################################################
##### IV. Subtracting restricted and aggregating to OD grid level
################################################################################

# Subtracting blocks marked as "Zona de Ocupação Especial", "Zona Especial de Preservação" or "Zona Especial de Preservação Ambiental"
blocks_zoning <- blocks %>%
  filter(
    !cd_zoneamento_perimetro %in% c(
      "Praça/Canteiro",
      "ZOE",
      "ZEP",
      "ZEPAM"
      )
    ) %>%
  select(
    id,
    geometry
  )

# Calculating precise intersections between blocks and OD zones
intersection_blocks_od <- st_intersection(blocks_zoning, od) %>% 
  # Computing intersection area, in squared kilometers
  mutate(
    intersection_area = as.numeric(st_area(geometry)) / 1e6
  ) %>% 
  st_drop_geometry() %>%
  # Aggregating total intersection area per zone, in squared kilometers
  group_by(zona) %>%
  summarise(
    total_area = sum(intersection_area, na.rm = TRUE)
  )

# Merging intersections back to the OD zone grid
od_blocks <- od %>%
  left_join(intersection_blocks_od, by = "zona") %>%
  mutate(
    blocks_area = replace_na(total_area, 0)
  ) %>% 
  st_drop_geometry()


################################################################################
##### V. Computing areas of public square oer OD zone
################################################################################

# Keeping only id and geometry columns in the public squares layer
plazas_short <- plazas %>%
  select(
    id,
    geometry
  )

# Calculating precise intersections between restricted areas and OD zones
intersection_plazas_od <- st_intersection(plazas_short, od) %>% 
  # Computing intersection area, in squared kilometers
  mutate(
    intersection_area = as.numeric(st_area(geometry)) / 1e6
  ) %>% 
  st_drop_geometry() %>%
  # Aggregating total intersection area per zone, in squared kilometers
  group_by(zona) %>%
  summarise(
    plazas_area = sum(intersection_area, na.rm = TRUE)
  )

# Merging intersections back to the OD zone grid
od_plazas <- od %>%
  left_join(intersection_plazas_od, by = "zona") %>%
  mutate(
    plazas_area = replace_na(plazas_area, 0)
  ) %>% 
  st_drop_geometry()


################################################################################
##### VI. Creating land area dataset
################################################################################

# Merging blocks and restricted areas
land_area_dataset <- od %>% 
  left_join(od_blocks[, c("zona", "blocks_area")], by = "zona") %>%
  left_join(od_plazas[, c("zona", "plazas_area")], by = "zona") %>%
  # Computing land area (km^2, ha, and as a share of the unrestricted block
  # area; if a zone has no unrestricted blocks the share is set to NA to
  # avoid a 0/0 division)
  mutate(
    land_area_km  = blocks_area - plazas_area,
    land_area_ha  = land_area_km * 100,
    land_area_pct = if_else(
      condition = blocks_area > 0,
      true      = round(land_area_km / blocks_area, 4),
      false     = NA_real_
    )
  ) %>%
  as_tibble() %>% 
  select(
    zona,
    land_area_km,
    land_area_ha,
    land_area_pct
  ) 


################################################################################
##### VII. Exporting outputs
################################################################################

# Creating output directory
dir.create(
  path         = output_directory,
  recursive    = TRUE,
  showWarnings = FALSE
)

# Saving land area dataset as Parquet file
write_parquet(
  x    = land_area_dataset,
  sink = output_file
)
