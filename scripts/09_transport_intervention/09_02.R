################################################################################
##################################            ##################################
######################### 09.02) CREATE LINE 6-ORANGE DATASET #####################
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

# Retrieving planned metro stations file path
stations_input <- raw_path("metro", "geoportal_estacao_metro_projetada.parquet")

# Retrieving planned metro lines file path
lines_input <- raw_path("metro", "geoportal_linha_metro_projetada.parquet")

# Setting line 6 output directory path
output_directory <- processed_path("interventions", "transport_intervention", "line_6")

# Setting output stations file
stations_output <- file.path(output_directory, "line6_stations.parquet")

# Setting output line file
line_output <- file.path(output_directory, "line6_line.parquet")

# Setting output line points file
points_output <- file.path(output_directory, "line6_points.parquet")


################################################################################
##### III. Data
################################################################################

# Reading planned metro stations
metro_stations <- read_geoparquet_sf(stations_input) %>%
  st_transform(31983)

# Reading planned metro lines
metro_lines <- read_geoparquet_sf(lines_input) %>%
  st_transform(4326)


################################################################################
##### IV. Line 6-Orange Stations
################################################################################

# Setting initial Line 6-Orange planned stations
line6_initial_stations <- c(
  "SÃO JOAQUIM",
  "BELA VISTA",
  "14 BIS",
  "HIGIENÓPOLIS-MACKENZIE",
  "FAAP-PACAEMBU",
  "PUC-CARDOSO DE ALMEIDA",
  "PERDIZES",
  "SESC POMPEIA",
  "ÁGUA BRANCA",
  "SANTA MARINA",
  "FREGUESIA DO Ó",
  "JOÃO PAULO I",
  "ITABERABA-HOSPITAL VILA PENTEADO",
  "VILA CARDOSO",
  "BRASILÂNDIA"
)

# Setting initial Line 6-Orange station names for GTFS
line6_gtfs_station_names <- c(
  "São Joaquim",
  "Bela Vista",
  "14 Bis",
  "Higienópolis-mackenzie",
  "FAAP-Pacaembu",
  "PUC-Cardoso de Almeida",
  "Perdizes",
  "Sesc Pompeia",
  "Água Branca",
  "Santa Marina",
  "Freguesia do Ó",
  "João Paulo I",
  "Itaberaba-Hospital Vila Penteado",
  "Vila Cardoso",
  "Brasilândia"
)

# Filtering Line 6-Orange planned stations
line6_stations <- metro_stations %>% 
  filter(
    nm_linha_metro_trem    == "LARANJA",
    nm_estacao_metro_trem %in% line6_initial_stations
  ) %>% 
  mutate(
    station_order = match(
      x     = nm_estacao_metro_trem,
      table = line6_initial_stations
    ),
    stop_name = line6_gtfs_station_names[station_order]
  ) %>% 
  arrange(station_order)

# Adding geographical coordinates in EPSG:4326
line6_stations_coordinates <- line6_stations %>% 
  st_transform(4326) %>% 
  st_coordinates()

# Adding station IDs and coordinates
line6_stations <- line6_stations %>% 
  mutate(
    stop_id  = row_number(),
    stop_lon = round(x = line6_stations_coordinates[,1], digits = 6),
    stop_lat = round(x = line6_stations_coordinates[,2], digits = 6)
  ) %>% 
  select(
    stop_id,
    stop_name,
    stop_lat,
    stop_lon,
    cd_identificador,
    nm_estacao_metro_trem,
    nm_linha_metro_trem,
    sg_estacao_metro_trem
  )


################################################################################
##### V. Line 6-Orange line
################################################################################

# Filtering Line 6-Orange planned stations
line6_line <- metro_lines %>% 
  filter(
    nm_linha_metro_trem == "LARANJA",
    cd_identificador    == 21
  )

# Retrieving geographical coordinates of the line, oriented so that vertex
# sequence_0 starts at São Joaquim (origin of trip METRÔ L6-0, which heads to
# Brasilândia) and sequence_1 starts at Brasilândia. The native vertex order
# returned by st_coordinates() depends on how GeoSampa serialises the line
# geometry and is not guaranteed; we detect direction empirically by checking
# which endpoint is closer to the São Joaquim station, and reverse the order
# if the line came in Brasilândia-first.
line6_points <- st_as_sf(
  x      = as.data.frame(st_coordinates(line6_line)),
  coords = c("X", "Y"),
  crs    = 4326
)

sao_joaquim_pt <- line6_stations %>%
  filter(nm_estacao_metro_trem == "SÃO JOAQUIM") %>%
  st_transform(4326) %>%
  st_geometry() %>%
  .[[1]] %>%
  st_coordinates()

dist_first <- sqrt(sum((st_coordinates(line6_points)[1, ]               - sao_joaquim_pt[1, ])^2))
dist_last  <- sqrt(sum((st_coordinates(line6_points)[nrow(line6_points), ] - sao_joaquim_pt[1, ])^2))

if (dist_first > dist_last) {
  # Native order starts at Brasilândia — flip so sequence_0 starts at São Joaquim
  line6_points <- line6_points[rev(seq_len(nrow(line6_points))), ]
}

line6_points <- line6_points %>%
  # Adding ID columns
  mutate(
    shape_pt_sequence_0 = row_number(),
    shape_pt_sequence_1 = sort(shape_pt_sequence_0, decreasing = TRUE)
  ) %>%
  select(
    shape_pt_sequence_0,
    shape_pt_sequence_1
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

# Saving stations as GeoParquet file
write_parquet(
  x    = line6_stations,
  sink = stations_output
)

# Saving line as GeoParquet file
write_parquet(
  x    = line6_line,
  sink = line_output
)

# Saving line points as GeoParquet file
write_parquet(
  x    = line6_points,
  sink = points_output
)
