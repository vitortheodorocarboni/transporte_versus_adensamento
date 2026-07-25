################################################################################
##################################            ##################################
################ 06.04) COMPLETE AND OUTPUT TRAVEL-TIME MATRIX #################
##################################            ##################################
################################################################################

################################################################################
##### I. Packages
################################################################################

# # Installing packages
# install.packages("arrow")
# install.packages("geoarrow")
# install.packages("geosphere")
# install.packages("sf")
# install.packages("tidyverse")

# Loading libraries
library(arrow)
library(geoarrow)
library(geosphere)
library(sf)
library(tidyverse)

# Disabling s2 geometry to avoid degenerate-vertex errors during st_centroid
sf::sf_use_s2(FALSE)


################################################################################
##### II. Directories and files
################################################################################

# Loading project paths
source(file.path("scripts", "_config", "paths.R"))

# Retrieving raw r5r output (from 06_03)
r5r_input <- processed_path("travel_times", "r5r_output.parquet")

# Retrieving complete OD dataset (sample flag and zone geometry, from 05_01)
od_input <- processed_path("final_dataset", "od_complete.parquet")

# Setting travel-times output directory
output_directory <- processed_path("travel_times")

# Setting output file path
matrix_full_output <- file.path(output_directory, "matrix_full.parquet")


################################################################################
##### III. Data
################################################################################

# Reading raw r5r output
r5r_long <- read_parquet(r5r_input) %>%
  as_tibble() %>%
  rename(travel_time = travel_time_p50)

# Reading complete OD dataset
od_dataset <- read_geoparquet_sf(od_input)

# Extracting zone-level sample flag
zone_sample <- od_dataset %>%
  st_drop_geometry() %>%
  select(zona, sample) %>%
  arrange(zona)

# Listing all OD zones
all_zones <- zone_sample$zona

# Listing CSM-kept OD zones
csm_zones <- zone_sample %>%
  filter(sample) %>%
  pull(zona)

# Reporting basic counts
n_zones <- length(all_zones)
n_csm   <- length(csm_zones)
message("OD zones: ", n_zones, " total, ", n_csm, " kept for CSM (sample).")


################################################################################
##### IV. Computing zone-centroid distances
################################################################################

# Computing OD zone centroids in WGS 84
zone_coords <- od_dataset %>%
  select(zona) %>%
  st_centroid() %>%
  st_transform(4326) %>%
  mutate(
    lon = st_coordinates(.)[, 1],
    lat = st_coordinates(.)[, 2]
  ) %>%
  st_drop_geometry() %>%
  arrange(match(zona, all_zones))

# Computing haversine distance matrix between centroids (meters)
dist_mat <- distm(
  x   = zone_coords[, c("lon", "lat")],
  fun = distHaversine
)
rownames(dist_mat) <- zone_coords$zona
colnames(dist_mat) <- zone_coords$zona

# Building long-form distance table (used as a tidy lookup, not as output)
dist_long <- as_tibble(dist_mat, rownames = "from_id") %>%
  pivot_longer(
    cols      = -from_id,
    names_to  = "to_id",
    values_to = "distance"
  )


################################################################################
##### V. Reconstructing the full grid in long form
################################################################################

# Building the full Cartesian product (343 x 343 OD pairs)
full_grid <- expand_grid(
  from_id = all_zones,
  to_id   = all_zones
)

# Joining observed travel times and setting same-zone diagonals to 0
travel_times_long <- full_grid %>%
  left_join(r5r_long, by = c("from_id", "to_id")) %>%
  mutate(
    travel_time = if_else(from_id == to_id, 0, travel_time)
  )

# Reporting missingness on the full grid and on the CSM sub-grid
n_missing_full <- sum(is.na(travel_times_long$travel_time))
n_missing_csm  <- travel_times_long %>%
  filter(from_id %in% csm_zones, to_id %in% csm_zones, is.na(travel_time)) %>%
  nrow()
message(
  "Missing pairs to impute: ", n_missing_full,
  " on full grid; ", n_missing_csm, " on CSM sub-grid."
)


################################################################################
##### VI. Imputing missing travel times via weighted k-NN
################################################################################

# Setting hyperparameters
k_neighbors <- 5L
p_inv_dist  <- 1
zero_dist   <- 1e-6

# Identifying pairs to impute
missing_pairs <- travel_times_long %>%
  filter(is.na(travel_time)) %>%
  select(from_id, to_id)

# Building observed-only long-form lookup
observed_long <- travel_times_long %>%
  filter(!is.na(travel_time)) %>%
  select(from_id, to_id, travel_time)

# Imputing each missing pair as the inverse-distance-weighted average of the
# travel times from the k nearest other origins to the same destination
imputed_pairs <- missing_pairs %>%
  cross_join(tibble(cand_origin = all_zones)) %>%
  filter(from_id != cand_origin) %>%
  # Looking up observed time from candidate origin to destination
  left_join(
    observed_long,
    by = c("cand_origin" = "from_id", "to_id" = "to_id")
  ) %>%
  filter(!is.na(travel_time)) %>%
  # Looking up haversine distance from missing origin to candidate origin
  left_join(
    dist_long,
    by = c("from_id" = "from_id", "cand_origin" = "to_id")
  ) %>%
  filter(is.finite(distance)) %>%
  group_by(from_id, to_id) %>%
  slice_min(distance, n = k_neighbors, with_ties = FALSE) %>%
  mutate(distance = pmax(distance, zero_dist)) %>%
  summarise(
    travel_time = sum((1 / distance^p_inv_dist) * travel_time) /
                  sum(1 / distance^p_inv_dist),
    .groups     = "drop"
  )



################################################################################
##### VII. Building the complete long-form dataset with sample flag
################################################################################

# Updating travel_times_long with the imputed values
travel_times_complete <- travel_times_long %>%
  rows_update(
    y  = imputed_pairs %>% select(from_id, to_id, travel_time),
    by = c("from_id", "to_id")
  )


# Adding pair-level sample flag (1 iff both endpoints are sample = 1)
matrix_full <- travel_times_complete %>%
  left_join(
    zone_sample %>% rename(from_sample = sample),
    by = c("from_id" = "zona")
  ) %>%
  left_join(
    zone_sample %>% rename(to_sample = sample),
    by = c("to_id" = "zona")
  ) %>%
  mutate(
    sample = as.integer(from_sample == 1 & to_sample == 1)
  ) %>%
  select(from_id, to_id, travel_time, sample) %>%
  arrange(from_id, to_id)

# Reporting pair-level sample composition
message("--- Pair-level sample composition ---")
print(table(matrix_full$sample, useNA = "always"))


################################################################################
##### VIII. Exporting output
################################################################################

# Creating output directory
dir.create(
  path         = output_directory,
  recursive    = TRUE,
  showWarnings = FALSE
)

# Saving long-form full grid as Parquet file
write_parquet(
  x    = matrix_full,
  sink = matrix_full_output
)
