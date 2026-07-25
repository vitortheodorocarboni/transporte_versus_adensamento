################################################################################
##################################            ##################################
############## 09.01) DOWNLOAD GEOSAMPA PROJECTED METRO DATASETS ###############
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

# Setting metro output data directory
output_directory <- raw_path("metro")

# Setting projected metro stations output GeoParquet file
stations_output <- file.path(output_directory, "geoportal_estacao_metro_projetada.parquet")

# Setting projected metro lines output GeoParquet file
lines_output <- file.path(output_directory, "geoportal_linha_metro_projetada.parquet")


################################################################################
##### III. GeoSampa API parameters
################################################################################

# Setting projected metro stations metadata page
stations_metadata <- "https://metadados.geosampa.prefeitura.sp.gov.br/geonetwork/srv/por/catalog.search#/metadata/3253d15c-6aff-443f-8925-31e311fcd23e"

# Setting projected metro lines metadata page
lines_metadata <- "https://metadados.geosampa.prefeitura.sp.gov.br/geonetwork/srv/por/catalog.search#/metadata/4d15d6f0-3f4f-4894-af7e-0da7ab19025a"

# Setting GeoSampa WFS endpoint
geosampa_url <- "http://wfs.geosampa.prefeitura.sp.gov.br/geoserver/geoportal/wfs"

# Setting projected metro stations layer name in GeoSampa
stations_layer <- "geoportal:estacao_metro_projetada"

# Setting projected metro lines layer name in GeoSampa
lines_layer <- "geoportal:linha_metro_projetada"


################################################################################
##### IV. Functions
################################################################################

# Creating a function to build GeoSampa WFS GPKG URLs
build_geosampa_url <- function(layer) {
  
  # Building WFS URL
  url <- paste0(
    geosampa_url,
    "?service=WFS",
    "&version=1.1.0",
    "&request=GetFeature",
    "&typeName=", URLencode(URL = layer, reserved = TRUE),
    "&srsName=EPSG:31983",
    "&outputFormat=", URLencode(URL = "gpkg", reserved = TRUE)
  )
  
  # Returning URL
  url
}

# Creating a function to download a GeoSampa layer as a GPKG file
download_geosampa_layer <- function(layer, output_file) {
  
  # Creating output directory
  dir.create(
    path         = dirname(output_file),
    recursive    = TRUE,
    showWarnings = FALSE
  )
  
  # Creating temporary GPKG file
  temp_file <- tempfile(fileext = ".gpkg")
  
  # Downloading GeoSampa GPKG file
  download.file(
    url      = build_geosampa_url(layer = layer),
    destfile = temp_file,
    method   = "libcurl",
    mode     = "wb",
    quiet    = FALSE,
    headers  = c("User-Agent" = "Mozilla/5.0")
  )
  
  # Reading downloaded GPKG file
  downloaded_layer <- st_read(
    dsn   = temp_file,
    quiet = TRUE
  )
  
  # Removing previous output file
  if (file.exists(output_file)) {
    file.remove(output_file)
  }

  # Saving downloaded layer as GeoParquet file (geoarrow registers the
  # geometry extension type so arrow::write_parquet emits GeoParquet 1.x)
  write_parquet(
    x    = downloaded_layer,
    sink = output_file
  )
  
  # Removing temporary GPKG file
  file.remove(temp_file)
  
  # Reporting download result
  message(
    "Saved ",
    nrow(downloaded_layer),
    " features from ",
    layer,
    " to ",
    output_file
  )
  
  # Returning output file
  output_file
}


################################################################################
##### V. Downloading data
################################################################################

# Extending R download timeout for GeoSampa spatial layers
options(timeout = 3600)

# Downloading projected metro stations GPKG file from GeoSampa
download_geosampa_layer(
  layer       = stations_layer,
  output_file = stations_output
)

# Downloading projected metro lines GPKG file from GeoSampa
download_geosampa_layer(
  layer       = lines_layer,
  output_file = lines_output
)
