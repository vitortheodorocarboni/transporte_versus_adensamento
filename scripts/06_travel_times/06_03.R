################################################################################
##################################            ##################################
################ 06.03) RUN R5R TRAVEL-TIME MATRIX SIMULATION ##################
##################################            ##################################
################################################################################

################################################################################
##### I. Packages
################################################################################

# Allocating memory to the Java Virtual Machine
options(java.parameters = "-Xmx8G")

# # Installing packages
# install.packages("arrow")
# install.packages("geoarrow")
# install.packages("rJava")
# install.packages("rJavaEnv")
# install.packages("r5r")
# install.packages("sf")
# install.packages("tidyverse")

# Loading libraries
library(arrow)
library(geoarrow)
library(rJava)
library(rJavaEnv)
library(r5r)
library(sf)
library(tidyverse)


################################################################################
##### II. Directories and files
################################################################################

# Loading project paths
source(file.path("scripts", "_config", "paths.R"))

# Setting r5r input data directory
r5_directory <- raw_path("travel_times", "r5r_core")

# Retrieving 2023 OD shapes file
shapes_input <- processed_path("shapes", "od_2023_shapes.parquet")

# Setting travel-times output directory
output_directory <- processed_path("travel_times")

# Setting r5r output file path
r5r_output <- file.path(output_directory, "r5r_output.parquet")


################################################################################
##### III. Data
################################################################################

# Building the transit network used for routing in R5
r5r_core <- build_network(
  data_path = r5_directory,
  verbose   = TRUE,
  overwrite = FALSE
)

# Reading 2023 OD centroids
od <- read_geoparquet_sf(shapes_input) %>%
  select(zona) %>%
  st_centroid() %>%
  # Reprojecting to WGS 84 EPSG 4326 (required by r5r)
  st_transform(4326)


################################################################################
##### IV. Running matrix simulation
################################################################################

# Computing the geographical coordinates of the centroids
od_centroid <- od %>%
  mutate(
    lat = st_coordinates(.)[,2],
    lon = st_coordinates(.)[,1]
  ) %>%
  rename(
    id = zona
  ) %>%
  as_tibble() %>%
  select(-geometry) %>%
  arrange(id)

# Setting transport modes (walk and/or take public transit)
transport_mode <- c("WALK", "TRANSIT")

# Setting egress mode after the last transit leg
mode_egress <- "WALK"

# Setting departure time (Monday, December 1st, 2025 at 08:00 local time)
departure_datetime <- as.POSIXct(
  x      = "2025-12-01 08:00:00",
  format = "%Y-%m-%d %H:%M:%S",
  tz     = "America/Sao_Paulo"
)

# Setting maximum trip duration (minutes)
max_trip_duration <- 240

# Setting maximum number of public-transit legs (transfers + 1)
max_rides <- 4

# Setting departure time window
time_window <- 60

# Setting percentile of the travel-time distribution to report (median)
percentiles <- 50

# Setting Monte Carlo draws per minute
draws_per_minute <- 5

# Setting walking speed (km/h; r5r default is 3.6 = 1 m/s)
walk_speed <- 3.6

# Computing travel times
travel_times <- travel_time_matrix(
  r5r_network        = r5r_core,
  origins            = od_centroid,
  destinations       = od_centroid,
  mode               = transport_mode,
  mode_egress        = mode_egress,
  departure_datetime = departure_datetime,
  time_window        = time_window,
  percentiles        = percentiles,
  draws_per_minute   = draws_per_minute,
  max_trip_duration  = max_trip_duration,
  max_rides          = max_rides,
  walk_speed         = walk_speed,
  progress           = TRUE
) %>%
  # Sorting the output data frame
  arrange(from_id, to_id)


################################################################################
##### V. Exporting outputs
################################################################################

# Creating travel-times output directory
dir.create(
  path         = output_directory,
  recursive    = TRUE,
  showWarnings = FALSE
)

# Saving r5r raw output as Parquet file
write_parquet(
  x    = travel_times,
  sink = r5r_output
)

# Stopping Java and releasing memory
stop_r5(r5r_core)
.jgc(R.gc = TRUE)
