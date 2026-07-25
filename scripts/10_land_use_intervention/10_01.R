################################################################################
##################################            ##################################
################### 10.01) DOWNLOAD 2025 GEOSAMPA IPTU DATA ###################
##################################            ##################################
################################################################################

################################################################################
##### I. Directories and files
################################################################################

# Loading project paths
source(file = file.path("scripts", "_config", "paths.R"))

# Setting IPTU output data directory
output_directory <- raw_path("cadastres", "iptu")

# Setting IPTU output ZIP archive (GeoSampa archive, kept as-is)
output_zip <- file.path(output_directory, "iptu_2025.zip")


################################################################################
##### II. GeoSampa API parameters
################################################################################

# Setting IPTU reference year
iptu_year <- 2025

# Setting GeoSampa download endpoint
geosampa_url <- "https://download.geosampa.prefeitura.sp.gov.br/PaginasPublicas/downloadArquivo.aspx"

# Setting IPTU file path in GeoSampa
geosampa_file <- paste0(
  "12_Cadastro\\\\IPTU_INTER\\\\XLS_CSV\\\\IPTU_",
  iptu_year
)

# Setting IPTU download URL
iptu_url <- paste0(
  geosampa_url,
  "?orig=DownloadCamadas",
  "&arq=", URLencode(URL = geosampa_file, reserved = TRUE),
  "&arqTipo=XLS_CSV"
)


################################################################################
##### III. Downloading data
################################################################################

# Creating output directory
dir.create(
  path         = output_directory,
  recursive    = TRUE,
  showWarnings = FALSE
)

# Removing any previously downloaded archive
if (file.exists(output_zip)) {
  file.remove(output_zip)
}

# Downloading IPTU ZIP file from GeoSampa directly to the output path
download.file(
  url      = iptu_url,
  destfile = output_zip,
  method   = "libcurl",
  mode     = "wb",
  quiet    = FALSE,
  headers  = c("User-Agent" = "Mozilla/5.0")
)


################################################################################
##### IV. Checking output
################################################################################


# Reporting final ZIP size
message(
  "IPTU archive downloaded successfully. Size: ",
  round(file.info(output_zip)$size / 1024^2, 2), " MB."
)
