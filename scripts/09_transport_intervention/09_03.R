################################################################################
##################################            ##################################
############### 09.03) REMAKE GTFS DATASET AFTER LINE 6-ORANGE ###############
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

# Retrieving GTFS data file
gtfs_input <- raw_path("travel_times", "r5r_core", "sptrans_gtfs.zip")

# Retrieving Line 6-Orange directory path
line6_directory <- processed_path("interventions", "transport_intervention", "line_6")

# Retrieving Line 6-Orange stations path
line6_stations_input <- file.path(line6_directory, "line6_stations.parquet")

# Retrieving Line 6-Orange line points path
line6_points_input <- file.path(line6_directory, "line6_points.parquet")

# Setting output data directory path
output_directory <- processed_path("interventions", "transport_intervention", "r5r_core")

# Setting output GTFS ZIP file path
gtfs_output <- file.path(output_directory, "sptrans_line6_gtfs.zip")


################################################################################
##### III. Data
################################################################################

# Reading Line 6-Orange stations file
line6_stations <- read_geoparquet_sf(line6_stations_input)

# Reading Line 6-Orange line points file
line6_points <- read_geoparquet_sf(line6_points_input)

# Separating line6_points which starts in São Joaquim station
line6_points_0 <- line6_points %>% 
  arrange(shape_pt_sequence_0) %>% 
  select(-shape_pt_sequence_1)

# Separating line6_points which starts in Brasilândia station
line6_points_1 <- line6_points %>% 
  arrange(shape_pt_sequence_1) %>% 
  select(-shape_pt_sequence_0)

# Reading GTFS tables (forcing UTF-8 to preserve Portuguese accents)
agency_original          <- read.csv(unz(gtfs_input, "agency.txt"),          colClasses = "character", encoding = "UTF-8")
calendar_original        <- read.csv(unz(gtfs_input, "calendar.txt"),        colClasses = "character", encoding = "UTF-8")
fare_attributes_original <- read.csv(unz(gtfs_input, "fare_attributes.txt"), colClasses = "character", encoding = "UTF-8")
fare_rules_original      <- read.csv(unz(gtfs_input, "fare_rules.txt"),      colClasses = "character", encoding = "UTF-8")
frequencies_original     <- read.csv(unz(gtfs_input, "frequencies.txt"),     colClasses = "character", encoding = "UTF-8")
routes_original          <- read.csv(unz(gtfs_input, "routes.txt"),          colClasses = "character", encoding = "UTF-8")
shapes_original          <- read.csv(unz(gtfs_input, "shapes.txt"),          colClasses = "character", encoding = "UTF-8")
stop_times_original      <- read.csv(unz(gtfs_input, "stop_times.txt"),      colClasses = "character", encoding = "UTF-8")
stops_original           <- read.csv(unz(gtfs_input, "stops.txt"),           colClasses = "character", encoding = "UTF-8")
trips_original           <- read.csv(unz(gtfs_input, "trips.txt"),           colClasses = "character", encoding = "UTF-8")


################################################################################
##### IV. Remaking agency table
################################################################################

# Copying original file
agency_new <- agency_original


################################################################################
##### V. Remaking calendar table
################################################################################

# Copying original file
calendar_new <- calendar_original


################################################################################
##### VI. Remaking fare attributes table
################################################################################

# Copying original file
fare_attributes_new <- fare_attributes_original


################################################################################
##### VII. Remaking fare rules table
################################################################################

# Generating fare IDs
fare_ids <- c("Metrô", "Ônibus + Metrô", "Ônibus + Metrô + CPTM")

# Generating route IDs
route_ids <- rep(x = "METRÔ L6", times = 3)

# Creating GTFS file with Line 6-Orange attributes
line6_fare_rules <- tibble(
  "fare_id"        = fare_ids,
  "route_id"       = route_ids,
  "origin_id"      = "",
  "destination_id" = "",
  "contains_id"    = ""
)

# Appending to original GTFS file
fare_rules_new <- fare_rules_original %>% 
  rows_append(line6_fare_rules) %>% 
  # Sorting dataset
  arrange(fare_id, route_id)


################################################################################
##### VIII. Remaking frequencies table
################################################################################

# Adjusting start times (hourly windows from 04:00 to 23:00)
start_times <- rep(
  times = 2,
  x     = sprintf("%02d:00:00", 4:23)
)

# Adjusting end times (HH:59:00 to match SPTrans convention used by L1-L5)
end_times <- rep(
  times = 2,
  x     = sprintf("%02d:59:00", 4:23)
)

# Generating trip IDs
trip_ids <- c(
  rep(x = "METRÔ L6-0", (length(start_times) / 2)),
  rep(x = "METRÔ L6-1", (length(start_times) / 2))
)

# Generating headway seconds
headway_seconds <- rep(x = "75", times = length(trip_ids))

# Creating GTFS file with Line 6-Orange attributes
line6_frequencies <- tibble(
  "trip_id"      = trip_ids,
  "start_time"   = start_times,
  "end_time"     = end_times,
  "headway_secs" = headway_seconds
)

# Appending to original GTFS file
frequencies_new <- frequencies_original %>% 
  rows_append(line6_frequencies) %>% 
  # Sorting dataset
  arrange(trip_id, start_time, end_time)

  
################################################################################
##### IX. Remaking routes table
################################################################################

# Creating GTFS file with Line 6-Orange attributes
line6_routes <- tibble(
  "route_id"         = "METRÔ L6",
  "agency_id"        = "1",
  "route_short_name" = "METRÔ L6",
  "route_long_name"  = "SÃO JOAQUIM - BRASILÂNDIA",
  "route_type"       = "1",
  "route_color"      = "FF6600",
  "route_text_color" = "FFFFFF"
  )

# Appending to original GTFS file
routes_new <- routes_original %>% 
  rows_append(line6_routes) %>% 
  # Sorting dataset
  arrange(route_id)


################################################################################
##### X. Remaking stops table
################################################################################

# Generating stop IDs
stop_ids <- NA
for(name in 1:length(line6_stations$stop_name)){
  stop_ids[name] <- max(as.integer(stops_original$stop_id)) + name
}

# Creating GTFS file with Line 6-Orange attributes
line6_stops <- line6_stations %>% 
  st_drop_geometry() %>% 
  mutate(
    stop_id   = stop_ids,
    stop_desc = ""
  ) %>% 
  select(
    stop_id,
    stop_name,
    stop_desc,
    stop_lat,
    stop_lon
  )

# Appending to original GTFS file (keeping stop_id/lat/lon as character to avoid round-trip)
stops_new <- stops_original %>%
  rows_append(
    line6_stops %>% mutate(across(everything(), as.character))
  ) %>%
  arrange(as.integer(stop_id))


################################################################################
##### XI. Remaking stop times table
################################################################################

# Generating trip IDs
trip_ids2 <- c(
  rep("METRÔ L6-0", length(line6_stations$stop_name)),
  rep("METRÔ L6-1", length(line6_stations$stop_name))
  )

# Setting Line 6-Orange target runtime to 23 min terminal-to-terminal
line6_runtime_seconds <- 23 * 60

# Spreading the terminal-to-terminal runtime across all station stops
line6_stop_offsets <- round(
  seq(
    from       = 0,
    to         = line6_runtime_seconds,
    length.out = length(line6_stations$stop_name)
  )
)

# Adjusting arrival times
arrival_times <- rep(
  times = 2,
  x     = format(
    format = "%H:%M:%S",
    x      = as.POSIXct("04:00:00", format = "%H:%M:%S") + line6_stop_offsets
    )
  )

# Adjusting departure times
departure_times <- rep(
  times = 2,
  x     = format(
    format = "%H:%M:%S",
    x      = as.POSIXct("04:00:00", format = "%H:%M:%S") + line6_stop_offsets
    )
  )

# Generating stop IDs
stop_ids2 <- as.character(
  c(line6_stops$stop_id, sort(x = as.integer(line6_stops$stop_id), decreasing = TRUE))
  )

# Generating stop sequence
stops_sequence <- rep(
  x     = 1:length(line6_stops$stop_id),
  times = 2
)

# Creating GTFS file with Line 6-Orange attributes
line6_stop_times <- tibble(
  "trip_id"        = trip_ids2,
  "arrival_time"   = arrival_times,
  "departure_time" = departure_times,
  "stop_id"        = stop_ids2,
  "stop_sequence"  = stops_sequence
)

# Appending to original GTFS file (keeping character types; sorting by trip and sequence)
stop_times_new <- stop_times_original %>%
  rows_append(
    line6_stop_times %>% mutate(across(everything(), as.character))
  ) %>%
  arrange(trip_id, as.integer(stop_sequence))


################################################################################
##### XII. Remaking trips table
################################################################################

# Generating shape IDs
shape_ids <- NA
for(name in 1:2){
  shape_ids[name] <- as.character(max(as.numeric(trips_original$shape_id)) + name)
}

# Creating GTFS file with Line 6-Orange attributes
# (trip_id L6-0 runs São Joaquim -> Brasilândia; trip_id L6-1 runs Brasilândia -> São Joaquim)
line6_trips <- tibble(
  "route_id"      = c("METRÔ L6", "METRÔ L6"),
  "service_id"    = "USD",
  "trip_id"       = c("METRÔ L6-0", "METRÔ L6-1"),
  "trip_headsign" = c("BRASILÂNDIA", "SÃO JOAQUIM"),
  "direction_id"  = as.character(c(0, 1)),
  "shape_id"      = shape_ids
)

# Appending to original GTFS file
trips_new <- trips_original %>% 
  rows_append(line6_trips) %>% 
  arrange(route_id, direction_id)


################################################################################
##### XIII. Remaking shapes table
################################################################################

# Generating shape IDs
shape_ids2_0 <- as.integer(rep(shape_ids[1], max(line6_points_0$shape_pt_sequence_0)))
shape_ids2_1 <- as.integer(rep(shape_ids[2], max(line6_points_1$shape_pt_sequence_1)))

# Generating shape points latitude
shape_pt_lat_0 <- round(st_coordinates(line6_points_0)[,2], 6)
shape_pt_lat_1 <- round(st_coordinates(line6_points_1)[,2], 6)

# Generating shape points latitude
shape_pt_lon_0 <- round(st_coordinates(line6_points_0)[,1], 6)
shape_pt_lon_1 <- round(st_coordinates(line6_points_1)[,1], 6)

# Generating shape points sequence
shape_pt_sequence_0 <- as.integer(line6_points_0$shape_pt_sequence_0)
shape_pt_sequence_1 <- as.integer(line6_points_1$shape_pt_sequence_1)

# Creating function to calculate cumulative distance between shape points
calculate_distance <- function(sf_points) {
  
  # Reprojecting to EPSG 31983 (for meters)
  proj <- st_transform(sf_points, 31983)
  
  # Computing distances between consecutive points
  dists <- c(
    0,
    as.numeric(
      st_distance(
        x          = proj[-nrow(proj), ],
        y          = proj[-1, ],
        by_element = TRUE
      )
    )
  )
  
  # Computing cumulative distance
  cumdist <- cumsum(dists)
}

# Creating GTFS file with Line 6-Orange attributes (São Joaquim -> Brasilândia)
line6_shapes_0 <- tibble(
  "shape_id"            = shape_ids2_0,
  "shape_pt_lat"        = shape_pt_lat_0,
  "shape_pt_lon"        = shape_pt_lon_0,
  "shape_pt_sequence"   = shape_pt_sequence_0,
  "shape_dist_traveled" = calculate_distance(line6_points_0)
)

# Creating GTFS file with Line 6-Orange attributes (Brasilândia -> São Joaquim)
line6_shapes_1 <- tibble(
  "shape_id"            = shape_ids2_1,
  "shape_pt_lat"        = shape_pt_lat_1,
  "shape_pt_lon"        = shape_pt_lon_1,
  "shape_pt_sequence"   = shape_pt_sequence_1,
  "shape_dist_traveled" = calculate_distance(line6_points_1)
)

# Appending to original GTFS file (keeping character types to avoid 60 MB round-trip)
shapes_new <- shapes_original %>%
  rows_append(line6_shapes_0 %>% mutate(across(everything(), as.character))) %>%
  rows_append(line6_shapes_1 %>% mutate(across(everything(), as.character)))


################################################################################
##### XIV. Exporting outputs
################################################################################

# Creating output directory
dir.create(
  path         = output_directory,
  recursive    = TRUE,
  showWarnings = FALSE
)

# Creating temporary GTFS directory
gtfs_directory <- tempfile(pattern = "sptrans_line6_gtfs_")
dir.create(
  path         = gtfs_directory,
  recursive    = TRUE,
  showWarnings = FALSE
)

# Creating function to write each new table as .txt (UTF-8 to preserve Portuguese accents)
write_gtfs <- function(df, name) {
  write.csv(
    x            = df,
    file         = file.path(gtfs_directory, name),
    row.names    = FALSE,
    quote        = TRUE,
    fileEncoding = "UTF-8"
  )
}

# Saving all tables as TXT file
write_gtfs(agency_new,          "agency.txt")
write_gtfs(calendar_new,        "calendar.txt")
write_gtfs(fare_attributes_new, "fare_attributes.txt")
write_gtfs(fare_rules_new,      "fare_rules.txt")
write_gtfs(frequencies_new,     "frequencies.txt")
write_gtfs(routes_new,          "routes.txt")
write_gtfs(shapes_new,          "shapes.txt")
write_gtfs(stops_new,           "stops.txt")
write_gtfs(stop_times_new,      "stop_times.txt")
write_gtfs(trips_new,           "trips.txt")

# Removing previous GTFS ZIP file
if (file.exists(gtfs_output)) {
  file.remove(gtfs_output)
}

# Creating function to quote paths for PowerShell
quote_powershell <- function(path) {
  paste0(
    "'",
    gsub(
      pattern     = "'",
      replacement = "''",
      x           = path,
      fixed       = TRUE
    ),
    "'"
  )
}

# Saving GTFS tables as ZIP file
zip_command <- paste(
  "Get-ChildItem",
  "-LiteralPath", quote_powershell(gtfs_directory),
  "-Filter '*.txt'",
  "|",
  "Compress-Archive",
  "-DestinationPath", quote_powershell(gtfs_output),
  "-Force"
)

# Running ZIP command
zip_status <- system2(
  command = "powershell",
  args    = c(
    "-NoProfile",
    "-Command",
    zip_command
  )
)


# Removing temporary GTFS directory
unlink(
  x         = gtfs_directory,
  recursive = TRUE
)
