################################################################################
##################################            ##################################
################## 07.01) ESTIMATING COMMUTING SEMIELASTICITY ##################
##################################            ##################################
################################################################################

################################################################################
##### I. Packages
################################################################################

# # Installing packages
# install.packages("arrow")
# install.packages("fixest")
# install.packages("geoarrow")
# install.packages("geodist")
# install.packages("sf")
# install.packages("tidyverse")

# Loading libraries
library(arrow)
library(fixest)
library(geoarrow)
library(geodist)
library(sf)
library(tidyverse)


################################################################################
##### II. Directories and files
################################################################################

# Loading project paths
source(file.path("scripts", "_config", "paths.R"))

# Retrieving 2023 OD processed survey dataset file
survey_input <- processed_path("shapes", "od_2023_survey.parquet")

# Retrieving 2023 OD processed shapes dataset file
shapes_input <- processed_path("shapes", "od_2023_shapes.parquet")

# Retrieving long-form 343 x 343 travel-time grid between 2023 OD pairs
times_input <- processed_path("travel_times", "matrix_full.parquet")

# Setting output directory path
output_directory <- processed_path("parameters", "commuting_semielasticity")

# Setting output file path
output_file <- file.path(output_directory, "outcomes_coefficient.parquet")


################################################################################
##### III. Data
################################################################################

# Reading 2023 OD survey dataset
survey <- read_parquet(survey_input)

# Reading 2023 OD shapes dataset
shapes <- read_geoparquet_sf(shapes_input) %>%
  mutate(
    zona = as.character(zona)
  ) %>%
  arrange(zona)

# Reading long-form travel-time grid
times_df <- read_parquet(times_input) %>%
  mutate(
    from_id = as.character(from_id),
    to_id   = as.character(to_id)
  ) %>%
  rename(time = travel_time) %>%
  select(from_id, to_id, time) %>%
  arrange(from_id, to_id)


################################################################################
##### IV. Preparing the OD survey
################################################################################

# Creating column of work zones in the municipality of São Paulo
survey_work <- survey %>%
  filter(cd_ativi %in% c(1, 2, 3)) %>%
  mutate(
    work_zone = case_when(
      munitra1 == 36                   ~ as.character(zonatra1),
      munitra2 == 36                   ~ as.character(zonatra2),
      munitra1 != 36 & munitra2 != 36  ~ NA_character_
    ),
    zona = as.character(zona)
  ) %>%
  filter(muni_dom == 36) %>%
  # Keeping only the variables needed to build the observed flows
  select(
    id_pess,
    zona,
    muni_dom,
    work_zone,
    cd_ativi,
    fe_pess
  ) %>%
  distinct(id_pess, .keep_all = TRUE)

# Separating OD zones located in São Paulo
zones_sp <- shapes %>%
  pull(zona) %>%
  sort()



################################################################################
##### V. Building observed commuting flows
################################################################################

# Keeping only persons who live and work in São Paulo
survey_sp <- survey_work %>%
  filter(
    zona      %in% zones_sp,
    work_zone %in% zones_sp
  )

# Aggregating observed flows by origin-destination pair
observed_flows <- survey_sp %>%
  group_by(
    from_id = zona,
    to_id   = work_zone
    ) %>%
  # Counting the weighted number of flows in each origin-destination pair
  summarise(
    flow = round(sum(fe_pess, na.rm = TRUE), 0),
    .groups  = "drop"
  ) %>%
  arrange(from_id, to_id)

# Adding zero-flow OD pairs
flows_df <- expand_grid(
  from_id = zones_sp,
  to_id   = zones_sp
  ) %>%
  left_join(
    y  = observed_flows,
    by = c("from_id", "to_id")
  ) %>%
  mutate(
    flow = replace_na(flow, 0)
  ) %>%
  arrange(from_id, to_id)


################################################################################
##### VI. Adding travel times
################################################################################

# Adding travel times to flows
flows_times <- flows_df %>%
  left_join(
    y  = times_df,
    by = c("from_id", "to_id")
  ) %>%
  arrange(from_id, to_id)


################################################################################
##### VII. Adding euclidian distances
################################################################################

# Retrieving centroid coordinates from the OD zones
centroids <- shapes %>%
  st_centroid() %>%
  st_transform(4326) %>%
  st_coordinates() %>%
  as_tibble() %>%
  rename(
    longitude = X,
    latitude  = Y
  )

# Computing matrix of geodesic distances between pairs of centroids
distances_matrix <- geodist(centroids, measure = "geodesic")

# Converting distance matrix to long data frame
distances_df <- distances_matrix %>%
  as.data.frame() %>%
  setNames(zones_sp) %>%
  mutate(from_id = zones_sp) %>%
  pivot_longer(
    cols      = -from_id,
    names_to  = "to_id",
    values_to = "distance"
  ) %>%
  mutate(
    from_id = as.character(from_id),
    to_id   = as.character(to_id)
  )

# Final gravity dataset
gravity_df <- flows_times %>%
  left_join(distances_df, by = c("from_id", "to_id")) %>%
  arrange(from_id, to_id)


################################################################################
##### VIII. Estimating commuting semielasticity
################################################################################

# Removing own-flows and pairs with missing travel time
gravity_estim <- gravity_df %>%
  filter(
    from_id != to_id,
    !is.na(time)
  )

# Estimating commuting semielasticity with PPML and fixed effects
gravity_model <- fepois(
  fml  = flow ~ time | from_id + to_id,
  data = gravity_estim,
  vcov = ~ from_id + to_id
)

# Retrieving estimated commuting semielasticity
commuting_semielasticity <- as.numeric(coef(gravity_model)["time"])


################################################################################
##### IX. Exporting outputs
################################################################################

# Creating output directory
dir.create(
  path         = output_directory,
  recursive    = TRUE,
  showWarnings = FALSE
)

# Saving estimated coefficient as Parquet file
write_parquet(
  x    = tibble(commuting_semielasticity = commuting_semielasticity),
  sink = output_file
)
