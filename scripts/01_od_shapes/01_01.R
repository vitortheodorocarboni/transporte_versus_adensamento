################################################################################
##################################            ##################################
#################### 01.01) DOWNLOAD RAW 2023 OD SURVEY DATA ###################
##################################            ##################################
################################################################################

################################################################################
##### I. Directories and files
################################################################################

# Loading project paths
source(file = file.path("scripts", "_config", "paths.R"))

# Setting 2023 OD raw data directory
output_directory <- raw_path("od_2023")

# Setting 2023 OD source ZIP file
zip_file <- file.path(output_directory, "Site_190225_PesquisaOD2023.zip")


################################################################################
##### II. Source information
################################################################################

# Setting Metro-SP source page
source_page <- "https://transparencia.metrosp.com.br/dataset/pesquisa-origem-e-destino-2023-anexos"

# Setting Metro-SP source resource page
resource_page <- paste0(
  source_page,
  "/resource/04bd5c3a-1391-4c33-bda7-6feb3d500c16"
)

# Setting Metro-SP source ZIP URL
zip_url <- "https://transparencia.metrosp.com.br/sites/default/files/Site_190225_PesquisaOD2023.zip"

# Setting 2023 OD survey file names
survey_files <- c(
  "Banco2023_divulgacao_190225.dbf",
  "Banco2023_divulgacao_190225.sav",
  "Layout_BD_OD2023_190225.xlsx"
)

# Setting 2023 OD map image file names
map_image_files <- c(
  "ZonasOD2023.jpg",
  "MapaGeral_ZonasOD2023_com-numeracao_190225.jpg",
  "MapaZoom_ZonasOD2023_com-numeracao_190225.jpg"
)

# Setting 2023 OD MapInfo metadata file names
metadata_files <- c(
  "Distritos_2023.DAT",
  "Distritos_2023.ID",
  "Distritos_2023.IND",
  "Distritos_2023.MAP",
  "Distritos_2023.TAB",
  "Municipios_2023.DAT",
  "Municipios_2023.ID",
  "Municipios_2023.jpg",
  "Municipios_2023.MAP",
  "Municipios_2023.TAB",
  "Zonas_2023.DAT",
  "Zonas_2023.ID",
  "Zonas_2023.IND",
  "Zonas_2023.MAP",
  "Zonas_2023.TAB"
)

# Setting 2023 OD shapefile file names
shapefile_files <- c(
  "Distritos_2023_region.dbf",
  "Distritos_2023_region.prj",
  "Distritos_2023_region.shp",
  "Distritos_2023_region.shx",
  "Municipios_2023.cpg",
  "Municipios_2023.dbf",
  "Municipios_2023.prj",
  "Municipios_2023.shp",
  "Municipios_2023.shx",
  "Zonas_2023.cpg",
  "Zonas_2023.dbf",
  "Zonas_2023.prj",
  "Zonas_2023.shp",
  "Zonas_2023.shx"
)

# Setting 2023 OD table file names
table_files <- c(
  "Corresp2017_2023_190225.xlsx",
  "Lista de tabelas OD2023-190225.docx",
  "Tabelas_Site_OD2023_REV_190225.xlsx"
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

# Removing previous source ZIP file
if (file.exists(zip_file)) {
  file.remove(zip_file)
}

# Extending R download timeout for the source ZIP file
options(timeout = max(600, getOption("timeout")))

# Downloading 2023 OD ZIP file from Metro-SP
download.file(
  url      = zip_url,
  destfile = zip_file,
  method   = "libcurl",
  mode     = "wb",
  quiet    = FALSE,
  headers  = c("User-Agent" = "Mozilla/5.0")
)
