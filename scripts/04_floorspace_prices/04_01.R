################################################################################
##################################            ##################################
############## 04.01) DOWNLOAD GEOSAMPA CADASTRAL BLOCKS DATASET ###############
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

# Setting cadastral blocks metadata page
blocks_metadata <- "https://metadados.geosampa.prefeitura.sp.gov.br/geonetwork/srv/por/catalog.search#/metadata/4ca0d339-8510-4f4d-aac4-a5f6ee570c0b"

# Setting cadastral blocks processed output directory
blocks_output_directory <- processed_path("cadastres", "blocks")

# Setting cadastral blocks processed output Parquet file
blocks_output <- file.path(blocks_output_directory, "cadastral_blocks_layer.parquet")


################################################################################
##### III. GeoSampa API parameters
################################################################################

# Setting GeoSampa WFS endpoint
geosampa_url <- "http://wfs.geosampa.prefeitura.sp.gov.br/geoserver/geoportal/wfs"

# Setting cadastral blocks layer name in GeoSampa
blocks_layer <- "geoportal:quadra_fiscal"

# Setting São Paulo city bounding box in EPSG:31983 (SIRGAS 2000 UTM 23S)
sp_bbox <- c(
  xmin = 305000,
  ymin = 7330000,
  xmax = 375000,
  ymax = 7440000
)

# Setting partition grid dimensions (4 x 4 = 16 tiles)
n_tiles_x <- 4
n_tiles_y <- 4


################################################################################
##### IV. Functions
################################################################################

# Creating a function to build a single GeoSampa WFS feature count URL
build_count_url <- function(layer) {
  paste0(
    geosampa_url,
    "?service=WFS",
    "&version=2.0.0",
    "&request=GetFeature",
    "&typeName=", URLencode(URL = layer, reserved = TRUE),
    "&resultType=hits"
  )
}

# Creating a function to count GeoSampa WFS features
count_geosampa_features <- function(layer) {

  # Creating temporary metadata file
  hits_file <- tempfile(fileext = ".xml")

  # Downloading WFS feature count
  download.file(
    url      = build_count_url(layer = layer),
    destfile = hits_file,
    method   = "libcurl",
    mode     = "wb",
    quiet    = TRUE,
    headers  = c("User-Agent" = "Mozilla/5.0")
  )

  # Reading WFS feature count response
  hits_text <- paste(
    readLines(con = hits_file, warn = FALSE),
    collapse = ""
  )

  # Extracting feature count (WFS 2.0.0 returns 'numberMatched')
  feature_count <- as.integer(sub(
    pattern     = ".*numberMatched=\"([0-9]+)\".*",
    replacement = "\\1",
    x           = hits_text
  ))

  # Removing temporary metadata file
  file.remove(hits_file)

  # Returning feature count
  feature_count
}

# Creating a function to build a single GeoSampa WFS BBOX query URL
build_geosampa_bbox_url <- function(layer, xmin, ymin, xmax, ymax) {
  paste0(
    geosampa_url,
    "?service=WFS",
    "&version=1.1.0",
    "&request=GetFeature",
    "&typeName=", URLencode(URL = layer, reserved = TRUE),
    "&srsName=EPSG:31983",
    "&outputFormat=", URLencode(URL = "gpkg", reserved = TRUE),
    "&BBOX=", paste(xmin, ymin, xmax, ymax, "EPSG:31983", sep = ",")
  )
}

# Creating a function to build a spatial grid of bounding boxes covering the São Paulo extent
build_tile_grid <- function(bbox, n_x, n_y) {

  # Computing tile width and height
  dx <- (bbox["xmax"] - bbox["xmin"]) / n_x
  dy <- (bbox["ymax"] - bbox["ymin"]) / n_y

  # Building grid of tile bounding boxes
  grid <- expand.grid(
    i = seq_len(n_x) - 1L,
    j = seq_len(n_y) - 1L
  )
  grid$xmin <- bbox["xmin"] + grid$i * dx
  grid$xmax <- grid$xmin + dx
  grid$ymin <- bbox["ymin"] + grid$j * dy
  grid$ymax <- grid$ymin + dy

  # Returning grid
  grid
}

# Creating a function to download a GeoSampa layer via BBOX-based spatial partitioning
download_geosampa_layer <- function(layer, bbox, n_x, n_y) {

  # Building tile grid
  tile_grid <- build_tile_grid(bbox = bbox, n_x = n_x, n_y = n_y)

  # Reporting number of tiles
  message(
    "Downloading GeoSampa layer '", layer,
    "' across ", nrow(tile_grid), " spatial tiles."
  )

  # Creating temporary download directory
  temp_directory <- tempfile(pattern = "geosampa_")
  dir.create(
    path         = temp_directory,
    recursive    = TRUE,
    showWarnings = FALSE
  )

  # Downloading each tile
  tile_pages <- lapply(seq_len(nrow(tile_grid)), function(k) {

    # Reporting current tile
    message("Downloading tile ", k, " of ", nrow(tile_grid))

    # Creating temporary GPKG tile file
    tile_file <- file.path(
      temp_directory,
      paste0("tile_", k, ".gpkg")
    )

    # Downloading GPKG tile
    download.file(
      url      = build_geosampa_bbox_url(
        layer = layer,
        xmin  = tile_grid$xmin[k],
        ymin  = tile_grid$ymin[k],
        xmax  = tile_grid$xmax[k],
        ymax  = tile_grid$ymax[k]
      ),
      destfile = tile_file,
      method   = "libcurl",
      mode     = "wb",
      quiet    = FALSE,
      headers  = c("User-Agent" = "Mozilla/5.0")
    )

    # Reading GPKG tile (returns NULL if tile is empty or unreadable
    tile_sf <- tryCatch(
      st_read(dsn = tile_file, quiet = TRUE),
      error = function(e) NULL
    )

    # Reporting tile feature count
    if (!is.null(tile_sf)) {
      message("  Tile ", k, ": ", nrow(tile_sf), " features.")
    } else {
      message("  Tile ", k, ": empty or unreadable, skipping.")
    }

    # Returning tile sf object
    tile_sf
  })

  # Removing empty or unreadable tiles
  tile_pages <- tile_pages[!sapply(tile_pages, is.null)]

  # Stopping execution if no tile returned data

  # Combining tiles
  layer_data <- do.call(
    what = rbind,
    args = tile_pages
  )

  # Deduplicating features that fall on tile boundaries
  layer_data <- layer_data[!duplicated(st_drop_geometry(layer_data)), ]

  # Cleaning up temporary download directory
  unlink(
    x         = temp_directory,
    recursive = TRUE,
    force     = TRUE
  )

  # Returning combined sf layer
  layer_data
}


################################################################################
##### V. Downloading data
################################################################################

# Extending R download timeout for large GeoSampa spatial layers
options(timeout = 3600)

# Creating cadastral blocks output directory
dir.create(
  path         = blocks_output_directory,
  recursive    = TRUE,
  showWarnings = FALSE
)

# Downloading cadastral blocks from GeoSampa via spatial partitioning
blocks_raw <- download_geosampa_layer(
  layer = blocks_layer,
  bbox  = sp_bbox,
  n_x   = n_tiles_x,
  n_y   = n_tiles_y
)


################################################################################
##### VI. Verifying download completeness
################################################################################

# Counting downloaded features and comparing with WFS feature count
expected_blocks <- count_geosampa_features(layer = blocks_layer)

# Reporting download completeness
message(
  "Downloaded ", nrow(blocks_raw),
  " out of ", expected_blocks,
  " features (",
  round(100 * nrow(blocks_raw) / expected_blocks, 2),
  "%)."
)

# Warning if the download is incomplete


################################################################################
##### VII. Processing into the cadastral blocks layer
################################################################################

# Creating block codes by pasting the two SQL components and dropping duplicates by block code
blocks_sf <- blocks_raw %>%
  mutate(
    block_code = paste0(
      cd_setor_fiscal,
      cd_quadra_fiscal
    )
  ) %>%
  arrange(block_code) %>%
  distinct(block_code, .keep_all = TRUE)

# Standardising the geometry column name to "geometry"
st_geometry(blocks_sf) <- "geometry"


################################################################################
##### VIII. Exporting output
################################################################################

# Removing previous Parquet file
if (file.exists(blocks_output)) {
  file.remove(blocks_output)
}

# Saving cadastral blocks layer as GeoParquet file
write_parquet(
  x    = blocks_sf,
  sink = blocks_output
)

