################################################################################
##################################            ##################################
############### 04.02) DOWNLOAD GEOSAMPA CADASTRAL LOTS DATASET ################
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

# Setting cadastral lots metadata page
lots_metadata <- "https://metadados.geosampa.prefeitura.sp.gov.br/geonetwork/srv/por/catalog.search#/metadata/62c1113c-36a4-43d1-b763-81ec63b58116"

# Setting cadastral lots processed output directory
lots_output_directory <- processed_path("cadastres", "lots")

# Setting cadastral lots processed output Parquet file
lots_output <- file.path(lots_output_directory, "cadastral_lots_layer.parquet")


################################################################################
##### III. GeoSampa download parameters
################################################################################

# Setting GeoSampa per-layer file download endpoint
geosampa_base_url <- "https://download.geosampa.prefeitura.sp.gov.br/PaginasPublicas/downloadArquivo.aspx"

# Setting the list of all 96  districts of São Paulo, in the exact form used by GeoSampa
district_codes <- c(
  "01_AGUA_RASA",         "02_ALTO_DE_PINHEIROS",  "03_ANHANGUERA",
  "04_ARICANDUVA",        "05_ARTUR_ALVIM",        "06_BARRA_FUNDA",
  "07_BELA_VISTA",        "08_BELEM",              "09_BOM_RETIRO",
  "10_BRAS",              "11_BRASILANDIA",        "12_BUTANTA",
  "13_CACHOEIRINHA",      "14_CAMBUCI",            "15_CAMPO_BELO",
  "16_CAMPO_GRANDE",      "17_CAMPO_LIMPO",        "18_CANGAIBA",
  "19_CAPAO_REDONDO",     "20_CARRAO",             "21_CASA_VERDE",
  "22_CIDADE_ADEMAR",     "23_CIDADE_DUTRA",       "24_CIDADE_LIDER",
  "25_CIDADE_TIRADENTES", "26_CONSOLACAO",         "27_CURSINO",
  "28_ERMELINO_MATARAZZO","29_FREGUESIA_DO_O",     "30_GRAJAU",
  "31_GUAIANASES",        "32_MOEMA",              "33_IGUATEMI",
  "34_IPIRANGA",          "35_ITAIM_BIBI",         "36_ITAIM_PAULISTA",
  "37_ITAQUERA",          "38_JABAQUARA",          "39_JACANA",
  "40_JAGUARA",           "41_JAGUARE",            "42_JARAGUA",
  "43_JARDIM_ANGELA",     "44_JARDIM_HELENA",      "45_JARDIM_PAULISTA",
  "46_JARDIM_SAO_LUIS",   "47_JOSE_BONIFACIO",     "48_LAPA",
  "49_LIBERDADE",         "50_LIMAO",              "51_MANDAQUI",
  "52_MARSILAC",          "53_MOOCA",              "54_MORUMBI",
  "55_PARELHEIROS",       "56_PARI",               "57_PARQUE_DO_CARMO",
  "58_PEDREIRA",          "59_PENHA",              "60_PERDIZES",
  "61_PERUS",             "62_PINHEIROS",          "63_PIRITUBA",
  "64_PONTE_RASA",        "65_RAPOSO_TAVARES",     "66_REPUBLICA",
  "67_RIO_PEQUENO",       "68_SACOMA",             "69_SANTA_CECILIA",
  "70_SANTANA",           "71_SANTO_AMARO",        "72_SAO_LUCAS",
  "73_SAO_MATEUS",        "74_SAO_MIGUEL",         "75_SAO_RAFAEL",
  "76_SAPOPEMBA",         "77_SAUDE",              "78_SE",
  "79_SOCORRO",           "80_TATUAPE",            "81_TREMEMBE",
  "82_TUCURUVI",          "83_VILA_ANDRADE",       "84_VILA_CURUCA",
  "85_VILA_FORMOSA",      "86_VILA_GUILHERME",     "87_VILA_JACUI",
  "88_VILA_LEOPOLDINA",   "89_VILA_MARIA",         "90_VILA_MARIANA",
  "91_VILA_MATILDE",      "92_VILA_MEDEIROS",      "93_VILA_PRUDENTE",
  "94_VILA_SONIA",        "95_SAO_DOMINGOS",       "96_LAJEADO"
)


################################################################################
##### IV. Functions
################################################################################

# Creating a function to build the GeoSampa per-district download URL
build_district_url <- function(district_code) {

  # Building the GeoSampa internal file name (without extension)
  file_name <- paste0("SIRGAS_GPKG_LOTES_", district_code)

  # Returning the full download URL
  paste0(
    geosampa_base_url,
    "?orig=DownloadCamadas",
    "&arq=12_Cadastro%5C%5CLotes%5C%5CGPKG_ZIP%5C%5C", file_name,
    "&arqTipo=GPKG_ZIP"
  )
}

# Creating a function to download one district's ZIP, extract its GPKG, read
# it into memory, and clean up the intermediate files
download_district <- function(district_code, temp_dir) {

  # Setting paths for the ZIP and the unzip subdirectory
  zip_file       <- file.path(temp_dir, paste0("SIRGAS_GPKG_LOTES_", district_code, ".zip"))
  unzip_subdir   <- file.path(temp_dir, district_code)

  # Removing any previous artefacts for this district
  if (file.exists(zip_file)) file.remove(zip_file)
  if (dir.exists(unzip_subdir)) unlink(unzip_subdir, recursive = TRUE, force = TRUE)

  # Downloading the GPKG ZIP for the district
  download.file(
    url      = build_district_url(district_code = district_code),
    destfile = zip_file,
    method   = "libcurl",
    mode     = "wb",
    quiet    = TRUE,
    headers  = c("User-Agent" = "Mozilla/5.0")
  )

  # Creating the unzip subdirectory
  dir.create(
    path         = unzip_subdir,
    recursive    = TRUE,
    showWarnings = FALSE
  )

  # Extracting the ZIP contents
  unzip(
    zipfile = zip_file,
    exdir   = unzip_subdir
  )

  # Locating the GPKG file inside the unzip directory
  gpkg_file <- list.files(
    path       = unzip_subdir,
    pattern    = "\\.gpkg$",
    full.names = TRUE
  )

  # Reading the GPKG file
  district_sf <- st_read(
    dsn   = gpkg_file[1],
    quiet = TRUE
  )

  # Deriving the district name from the district code
  district_name <- sub(
    pattern     = "^\\d+_",
    replacement = "",
    x           = district_code
  )
  district_name <- gsub(
    pattern     = "_",
    replacement = " ",
    x           = district_name
  )

  # Adding the district name as a new column
  district_sf$district <- district_name

  # Cleaning up the temporary ZIP and unzip subdirectory
  file.remove(zip_file)
  unlink(unzip_subdir, recursive = TRUE, force = TRUE)

  # Returning the district sf object
  district_sf
}


################################################################################
##### V. Downloading data
################################################################################

# Extending R download timeout for the large GeoSampa downloads
options(timeout = 3600)

# Creating cadastral lots output directory
dir.create(
  path         = lots_output_directory,
  recursive    = TRUE,
  showWarnings = FALSE
)

# Creating temporary download directory
temp_directory <- tempfile(pattern = "geosampa_lots_")
dir.create(
  path         = temp_directory,
  recursive    = TRUE,
  showWarnings = FALSE
)

# Reporting overall plan
message(
  "Downloading GeoSampa cadastral lots across ",
  length(district_codes), " districts."
)

# Allocating list of per-district sf objects
district_pages <- vector(mode = "list", length = length(district_codes))

# Iterating over each district
for (i in seq_along(district_codes)) {

  # Picking current district code
  district_code <- district_codes[i]

  # Reporting current district
  message(
    "District ", district_code,
    " (", i, "/", length(district_codes), ") ..."
  )

  # Downloading and reading current district
  district_pages[[i]] <- download_district(
    district_code = district_code,
    temp_dir      = temp_directory
  )

  # Reporting feature count for current district
  message("  ", nrow(district_pages[[i]]), " lots.")
}

# Combining all districts into a single sf object (no deduplication needed:
# each lot belongs to exactly one administrative district)
lots_raw <- do.call(
  what = rbind,
  args = district_pages
)

# Cleaning up temporary download directory
unlink(
  x         = temp_directory,
  recursive = TRUE,
  force     = TRUE
)


################################################################################
##### VI. Processing into the cadastral lots layer
################################################################################

# Creating lot codes by pasting the three SQL components, renaming the
# geometry column, and dropping duplicates by lot code
lots_sf <- lots_raw %>%
  mutate(
    lot_code = paste0(
      lo_setor,
      lo_quadra,
      lo_lote
    )
  ) %>%
  rename(
    geometry = geom
  ) %>%
  arrange(lot_code) %>%
  distinct(lot_code, .keep_all = TRUE)


################################################################################
##### VII. Exporting output
################################################################################

# Removing previous Parquet file
if (file.exists(lots_output)) {
  file.remove(lots_output)
}

# Saving cadastral lots layer as GeoParquet file
write_parquet(
  x    = lots_sf,
  sink = lots_output
)


# Reporting combined feature count
message(
  "Saved ", nrow(lots_sf),
  " cadastral lots from ", length(district_codes),
  " districts to '", lots_output, "'."
)
