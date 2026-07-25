################################################################################
##################################            ##################################
####################### 10.02) GEOLOCATE 2025 IPTU DATA ########################
##################################            ##################################
################################################################################

################################################################################
##### I. Packages
################################################################################

# # Installing packages
# install.packages("arrow")
# install.packages("enderecobr")
# install.packages("geoarrow")
# install.packages("geocodebr")
# install.packages("sf")
# install.packages("tidyverse")

# Loading libraries
library(arrow)
library(enderecobr)
library(geoarrow)
library(geocodebr)
library(sf)
library(tidyverse)


################################################################################
##### II. Directories and files
################################################################################

# Loading project paths
source(file.path("scripts", "_config", "paths.R"))

# Retrieving IPTU input ZIP archive (produced by 10_01.R)
iptu_zip <- raw_path("cadastres", "iptu", "iptu_2025.zip")

# Setting CSV entry name inside the ZIP (GeoSampa's original filename)
iptu_csv_name <- "IPTU_2025.csv"

# Retrieving cadastral lots file (produced by 04_02.R)
lots_input <- processed_path("cadastres", "lots", "cadastral_lots_layer.parquet")

# Retrieving cadastral blocks file (produced by 04_01.R)
blocks_input <- processed_path("cadastres", "blocks", "cadastral_blocks_layer.parquet")

# Setting output data directory
output_directory <- processed_path("built_area")

# Setting output data file
output_file <- file.path(output_directory, "iptu_2025_georreferenced.parquet")


################################################################################
##### III. Data
################################################################################


# Creating a temporary directory to unzip the IPTU CSV into
unzip_directory <- tempfile(pattern = "iptu_2025_")
dir.create(
  path         = unzip_directory,
  recursive    = TRUE,
  showWarnings = FALSE
)

# Cleaning up the temporary directory when the script exits
on.exit(
  unlink(x = unzip_directory, recursive = TRUE, force = TRUE),
  add = TRUE
)

# Extracting the IPTU CSV from the ZIP archive
unzip(
  zipfile   = iptu_zip,
  exdir     = unzip_directory,
  overwrite = TRUE
)

# Locating the extracted CSV file
iptu_input <- file.path(unzip_directory, iptu_csv_name)

# Reading IPTU dataset
iptu_raw <- read.csv(
  file             = iptu_input,
  sep              = ";",
  fileEncoding     = "Latin1",
  na.strings       = c("", "NA"),
  colClasses       = "character",
  stringsAsFactors = FALSE,
  check.names      = FALSE
) %>%
  as_tibble()

# Reading cadastral lots layer (with centroids)
lots_sf <- read_geoparquet_sf(lots_input) %>%
  st_transform(31983) %>%
  st_centroid() %>%
  as_tibble()

# Reading cadastral blocks layer (with centroids)
blocks_sf <- read_geoparquet_sf(blocks_input) %>%
  st_transform(31983) %>%
  st_centroid() %>%
  as_tibble()


################################################################################
##### IV. Standardizing IPTU addresses
################################################################################

# Renaming IPTU columns
iptu_df <- iptu_raw %>% 
  transmute(
    sql_number                  = str_replace_all(`NUMERO DO CONTRIBUINTE`, "\\D", ""),
    year                        = as.integer(`ANO DO EXERCICIO`),
    registration_date           = as.Date(`DATA DO CADASTRAMENTO`, format = "%d/%m/%y"),
    address_street              = `NOME DE LOGRADOURO DO IMOVEL`,
    address_number              = `NUMERO DO IMOVEL`,
    address_complement          = `COMPLEMENTO DO IMOVEL`,
    neighborhood                = `BAIRRO DO IMOVEL`,
    zip_code                    = str_pad(str_replace_all(`CEP DO IMOVEL`, "\\D", ""), width = 8, side = "left", pad = "0"),
    corrected_construction_year = as.integer(`ANO DA CONSTRUCAO CORRIGIDO`),
    property_reference          = `REFERENCIA DO IMOVEL`,
    construction_type           = `TIPO DE PADRAO DA CONSTRUCAO`,
    land_area                   = as.numeric(`AREA DO TERRENO`),
    built_area                  = as.numeric(`AREA CONSTRUIDA`),
    occupied_area               = as.numeric(`AREA OCUPADA`),
    floor_count                 = as.integer(`QUANTIDADE DE PAVIMENTOS`),
    land_value                  = as.numeric(`VALOR DO M2 DO TERRENO`),
    construction_value          = as.numeric(`VALOR DO M2 DE CONSTRUCAO`)
  )

# Computing codes from the SQL number to match with cadastral layers
iptu_df <- iptu_df %>% 
  mutate(
    # Computing lot code
    lot_code   = str_sub(sql_number, end = -2),
    # Computing block code
    block_code = str_sub(sql_number, 1, 6)
  ) %>% 
  # Adding state and municipality columns
  mutate(
    state        = "SP",
    municipality = "São Paulo"
  )

# Specifying address fields for standardization
address_fields_enderecobr <- correspondencia_campos(
  logradouro  = "address_street",
  numero      = "address_number",
  complemento = "address_complement",
  cep         = "zip_code",
  bairro      = "neighborhood",
  municipio   = "municipality",
  estado      = "state"
)

# Standardizing addresses
iptu_std <- padronizar_enderecos(
  enderecos           = iptu_df,
  campos_do_endereco  = address_fields_enderecobr,
  formato_estados     = "por_extenso",
  formato_numeros     = "character",
  manter_cols_extras  = TRUE,
  combinar_logradouro = FALSE,
  checar_tipos        = FALSE
)

# Renaming standardized columns
iptu_std <- iptu_std %>% 
  select(
    sql_number,
    lot_code,
    block_code,
    year,
    registration_date,
    corrected_construction_year,
    property_reference,
    construction_type,
    land_area,
    built_area,
    occupied_area,
    floor_count,
    land_value,
    construction_value,
    logradouro_padr,
    numero_padr,
    complemento_padr,
    cep_padr,
    bairro_padr,
    municipio_padr,
    estado_padr
  ) %>% 
  rename(
    address_street     = logradouro_padr,
    address_number     = numero_padr,
    address_complement = complemento_padr,
    zip_code           = cep_padr,
    neighborhood       = bairro_padr,
    municipality       = municipio_padr,
    state              = estado_padr
  )

# Specifying columns of interest
desired_columns <- c(
  "sql_number",
  "lot_code",
  "block_code",
  "year",
  "registration_date",
  "corrected_construction_year",
  "property_reference",
  "construction_type",
  "land_area",
  "built_area",
  "occupied_area",
  "floor_count",
  "land_value",
  "construction_value",
  "address_street",
  "address_number",
  "address_complement",
  "zip_code",
  "neighborhood",
  "municipality",
  "state",
  "geometry"
)


################################################################################
##### V. Geocoding by lot code
################################################################################

# Merging IPTU and cadastral data by the lot code
iptu_lots <- iptu_std %>% 
  left_join(lots_sf, by = "lot_code")

# Keeping only successful joins
iptu_lots_done <- iptu_lots %>% 
  filter(!is.na(district)) %>%
  select(
    all_of(desired_columns)
  ) %>% 
  st_as_sf() %>% 
  st_transform(31983) %>% 
  as_tibble()

# Keeping only cases unmatched by the lot code
iptu_lots_left <- iptu_lots %>% 
  filter(is.na(district)) %>%
  select(
    -geometry,
    -district
  )


################################################################################
##### VI. Geocoding by address
################################################################################

# Teaching geocodebr to match the columns of my data frame 
campos_geocodebr <- definir_campos(
  logradouro = "address_street",
  numero     = "address_number",
  cep        = "zip_code",
  localidade = "neighborhood",
  municipio  = "municipality",
  estado     = "state"
)

# Geocoding all addresses
iptu_cnefe <- geocode(
  enderecos          = iptu_lots_left,
  campos_endereco    = campos_geocodebr,
  resultado_completo = TRUE,
  resolver_empates   = TRUE,
  resultado_sf       = TRUE,
  verboso            = FALSE,
  cache              = TRUE
) %>%
  st_transform(31983) %>% 
  as_tibble()

# Keeping only bad matches (non-"numero" and non-"numero_aproximado" cases)
iptu_cnefe_left <- iptu_cnefe %>%
  filter(!precisao %in% c("numero", "numero_aproximado")) %>% 
  select(
    all_of(desired_columns),
    -geometry
  )

# Keeping only good matches ("numero" and "numero_aproximado" cases)
iptu_cnefe_done <- iptu_cnefe %>%
  filter(precisao %in% c("numero", "numero_aproximado")) %>%
  select(
    all_of(desired_columns),
    -block_code
  )


################################################################################
##### VII. Geocoding by block code
################################################################################

# Merging IPTU and cadastral data by the block code (blocks_sf is already
# deduplicated on block_code by 04_01)
iptu_blocks <- iptu_cnefe_left %>%
  left_join(blocks_sf, by = "block_code")

# Keeping only successful joins
iptu_blocks_done <- iptu_blocks %>%
  filter(!is.na(tx_tipo_quadra)) %>%
  select(
    all_of(desired_columns),
    -block_code,
    -tx_tipo_quadra
  )


################################################################################
##### VIII. Appending outputs from different geocoding processes
################################################################################

# Binding all geocoded data
iptu_georreferenced <- bind_rows(
  iptu_lots_done,
  iptu_cnefe_done,
  iptu_blocks_done
) %>% 
  st_as_sf()


################################################################################
##### IX. Exporting outputs
################################################################################

# Creating output directory
dir.create(
  path         = output_directory,
  recursive    = TRUE,
  showWarnings = FALSE
)

# Saving geolocated dataset as GeoParquet file
write_parquet(
  x    = iptu_georreferenced,
  sink = output_file
)
