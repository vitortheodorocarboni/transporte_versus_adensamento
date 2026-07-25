################################################################################
##################################            ##################################
############### 03.01) DOWNLOAD GEOSAMPA LAND AREA DATASETS ####################
##################################            ##################################
################################################################################

################################################################################
##### I. Packages
################################################################################

# # Installing packages
# install.packages("arrow")
# install.packages("geoarrow")
# install.packages("sf")

# Loading libraries
library(arrow)
library(geoarrow)
library(sf)


################################################################################
##### II. Directories and files
################################################################################

# Loading project paths
source(file.path("scripts", "_config", "paths.R"))

# Setting land area output data directory
output_directory <- raw_path("land_area")

# Setting zoning output Parquet file
zoning_output <- file.path(output_directory, "perimetro_zona_lei_18177_24.parquet")

# Setting plazas output Parquet file
plazas_output <- file.path(output_directory, "GEOSAMPA_v_praca_largo.parquet")

# Setting zoning metadata page
zoning_metadata <- "https://metadados.geosampa.prefeitura.sp.gov.br/geonetwork/srv/por/catalog.search#/metadata/afc0cff0-933f-4bd1-8269-cf4ac3762571"

# Setting plazas metadata page
plazas_metadata <- "https://metadados.geosampa.prefeitura.sp.gov.br/geonetwork/srv/por/catalog.search#/metadata/3ee2d4de-1006-4d53-902c-6ee6b3e621c4"


################################################################################
##### III. GeoSampa API parameters
################################################################################

# Setting GeoSampa WFS endpoint
geosampa_url <- "http://wfs.geosampa.prefeitura.sp.gov.br/geoserver/geoportal/wfs"

# Setting zoning layer name in GeoSampa
zoning_layer <- "geoportal:perimetro_zona_lei_18177_24"

# Setting plazas layer name in GeoSampa
plazas_layer <- "geoportal:GEOSAMPA_v_praca_largo"

# Setting number of features per request
page_size <- 10000


################################################################################
##### IV. Functions
################################################################################

# Creating a function to build GeoSampa WFS URLs
build_geosampa_url <- function(layer, result_type = "results", start_index = NULL) {
  
  # Creating base WFS URL
  url <- paste0(
    geosampa_url,
    "?service=WFS",
    "&version=2.0.0",
    "&request=GetFeature",
    "&typeName=", URLencode(URL = layer, reserved = TRUE),
    "&srsName=EPSG:31983",
    "&outputFormat=", URLencode(URL = "application/json", reserved = TRUE),
    "&resultType=", result_type
  )
  
  # Adding pagination parameters for data requests
  if (!is.null(start_index)) {
    url <- paste0(
      url,
      "&count=", page_size,
      "&startIndex=", start_index
    )
  }
  
  # Returning URL
  url
}

# Creating a function to count GeoSampa WFS features
count_geosampa_features <- function(layer) {
  
  # Creating temporary metadata file
  hits_file <- tempfile(fileext = ".xml")
  
  # Downloading WFS feature count
  download.file(
    url      = build_geosampa_url(layer = layer, result_type = "hits"),
    destfile = hits_file,
    method   = "libcurl",
    mode     = "wb",
    quiet    = FALSE,
    headers  = c("User-Agent" = "Mozilla/5.0")
  )
  
  # Reading WFS feature count response
  hits_text <- paste(
    readLines(con = hits_file, warn = FALSE),
    collapse = ""
  )
  
  # Extracting feature count
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

# Creating a function to download GeoSampa layers as GeoParquet files
download_geosampa_layer <- function(layer, output_file) {
  
  # Counting features available in GeoSampa
  feature_count <- count_geosampa_features(layer = layer)
  
  # Creating pagination start indexes
  start_indexes <- seq(
    from = 0,
    to   = feature_count - 1,
    by   = page_size
  )
  
  # Creating temporary download directory
  temp_directory <- tempfile(pattern = "geosampa_")
  dir.create(
    path         = temp_directory,
    recursive    = TRUE,
    showWarnings = FALSE
  )
  
  # Downloading and reading each GeoJSON page
  layer_pages <- lapply(start_indexes, function(start_index) {
    
    # Creating temporary GeoJSON file
    geojson_file <- file.path(
      temp_directory,
      paste0("page_", start_index, ".geojson")
    )
    
    # Downloading GeoJSON page
    download.file(
      url      = build_geosampa_url(layer = layer, start_index = start_index),
      destfile = geojson_file,
      method   = "libcurl",
      mode     = "wb",
      quiet    = FALSE,
      headers  = c("User-Agent" = "Mozilla/5.0")
    )
    
    # Reading GeoJSON page
    st_read(
      dsn   = geojson_file,
      quiet = TRUE
    )
  })
  
  # Combining GeoJSON pages
  layer_data <- do.call(
    what = rbind,
    args = layer_pages
  )
  
  # Removing previous Parquet file
  if (file.exists(output_file)) {
    file.remove(output_file)
  }

  # Saving complete layer as GeoParquet file (geoarrow registers the geometry
  # extension type so arrow::write_parquet emits GeoParquet 1.x)
  write_parquet(
    x    = layer_data,
    sink = output_file
  )
  
  # Removing temporary download directory
  unlink(
    x         = temp_directory,
    recursive = TRUE,
    force     = TRUE
  )
}


################################################################################
##### V. Downloading data
################################################################################

# Extending R download timeout for GeoSampa spatial layers
options(timeout = 3600)

# Creating output directory
dir.create(
  path         = output_directory,
  recursive    = TRUE,
  showWarnings = FALSE
)

# Downloading zoning GPKG file from GeoSampa
download_geosampa_layer(
  layer       = zoning_layer,
  output_file = zoning_output
)

# Downloading plazas GPKG file from GeoSampa
download_geosampa_layer(
  layer       = plazas_layer,
  output_file = plazas_output
)


################################################################################
##### VI. Checking outputs
################################################################################

print(read_geoparquet_sf(zoning_output))

print(read_geoparquet_sf(plazas_output))
