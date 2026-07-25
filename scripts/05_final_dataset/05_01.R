################################################################################
##################################            ##################################
######################## 05.01) FORMATING FINAL DATASET ########################
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

# Retrieving 2023 OD processed shapes file
shapes_input <- processed_path("shapes", "od_2023_shapes.parquet")

# Retrieving workers file (contains both residents and workplaces per zone)
workers_input <- processed_path("workers", "workers.parquet")

# Retrieving floorspace-prices file
prices_input <- processed_path("floorspace_prices", "price_dataset.parquet")

# Retrieving land-area file
land_area_input <- processed_path("land_area", "land_area_dataset.parquet")

# Setting OD dataset output directory path
output_directory <- processed_path("final_dataset")

# Setting complete-dataset output file path
complete_output_file <- file.path(output_directory, "od_complete.parquet")

# Setting sample-dataset output file path
sample_output_file <- file.path(output_directory, "od_sample.parquet")

# Setting excluded zones output file path
excluded_output_file <- processed_path("shapes", "od_excluded.parquet")


################################################################################
##### III. Data
################################################################################

# Setting expected number of São Paulo OD zones
n_zones_expected <- 343

# Reading 2023 OD shapes
shapes <- read_geoparquet_sf(shapes_input)

# Reading workers grid (residents and workplaces in a single tibble)
workers <- read_parquet(workers_input)

# Reading floorspace-prices grid
prices <- read_parquet(prices_input)

# Reading land-area grid
land_area <- read_parquet(land_area_input)


################################################################################
##### IV. Joining datasets
################################################################################

# Joining all input grids by OD zone
od_all <- shapes %>%
  left_join(workers,    by = "zona") %>%
  left_join(prices,     by = "zona") %>%
  left_join(land_area,  by = "zona") %>%
  # Rescaling residents (L_i) so that sum(L_i) == sum(L_j)
  mutate(
    residents_weighted = residents * sum(workplaces, na.rm = TRUE) /
      sum(residents, na.rm = TRUE)
  ) %>%
  rename(
    n_transactions = n_trans
  ) %>%
  # Selecting the final ordered column set
  select(
    zona,
    residents,
    residents_weighted,
    workplaces,
    price,
    n_transactions,
    land_area_km,
    land_area_ha,
    land_area_pct
  )


################################################################################
##### V. Flagging analysis sample
################################################################################

# Keeping zones for which there are data
od_sample <- od_all %>%
  filter(
    !is.na(residents)      & residents      >  0,
    !is.na(workplaces)     & workplaces     >  0,
    !is.na(n_transactions) & n_transactions >= 100,
    !is.na(land_area_km)   & land_area_km   >  0
    )

# Marking excluded zones
zones_sample <- od_all$zona %in% od_sample$zona

# Flagging excluded zones in the complete dataset
od_complete <- od_all %>% 
  mutate(sample = zones_sample)

# Separating excluded zones
od_excluded <- od_complete %>% 
  filter(zones_sample == FALSE) %>% 
  select(zona)

nrow(
od_all %>% 
  filter(
    # !is.na(workplaces)     & workplaces     >  0,
    !is.na(residents)      & residents      >  0,
    
    # !is.na(n_transactions) & n_transactions >= 100,
    
  )
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

# Saving complete dataset as GeoParquet file
write_parquet(
  x    = od_complete,
  sink = complete_output_file
)

# Saving sample dataset as GeoParquet file
write_parquet(
  x    = od_sample,
  sink = sample_output_file
)

# Saving excluded dataset as GeoParquet file
write_parquet(
  x    = od_excluded,
  sink = excluded_output_file
)
