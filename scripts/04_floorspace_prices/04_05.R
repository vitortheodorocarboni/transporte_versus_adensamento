################################################################################
##################################            ##################################
######################### 04.05) GEOLOCATE ITBI DATA ###########################
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

# Retrieving itbi input data file (produced by 04_04.R)
itbi_input <- processed_path("floorspace_prices", "itbi_single_data_frame.parquet")

# Retrieving cadastral lots file (produced by 04_02.R)
lots_input <- processed_path("cadastres", "lots", "cadastral_lots_layer.parquet")

# Retrieving cadastral blocks file (produced by 04_01.R)
blocks_input <- processed_path("cadastres", "blocks", "cadastral_blocks_layer.parquet")

# Setting output data directory path
output_directory <- processed_path("floorspace_prices")

# Setting output data file path
output_file <- file.path(output_directory, "itbi_geocoded.parquet")


################################################################################
##### III. Data
################################################################################

# Reading ITBI dataset
itbi <- read_parquet(itbi_input)

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
##### IV. Standardizing ITBI addresses
################################################################################

# Computing codes from the SQL number to match with cadastral layers
itbi_df <- itbi %>% 
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
  ) %>% 
  # Enforcing correct variable format. Other columns are already character
  # from the all-character coerce in 04_04; only zip_code needs to be numeric
  # for padronizar_enderecos to recognise it as a CEP.
  mutate(
    zip_code = as.numeric(zip_code)
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
itbi_std <- padronizar_enderecos(
  enderecos           = itbi_df,
  campos_do_endereco  = address_fields_enderecobr,
  formato_estados     = "por_extenso",
  formato_numeros     = "character",
  manter_cols_extras  = TRUE,
  combinar_logradouro = FALSE,
  checar_tipos        = FALSE
)

# Renaming standardized address columns and keeping only the fields needed downstream 
itbi_std <- itbi_std %>%
  select(
    itbi_ref_year,
    itbi_ref_month,
    sql_number,
    lot_code,
    block_code,
    transaction_type,
    transaction_date,
    transaction_proportion,
    property_type,
    built_area,
    declared_value,
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

# Specifying columns of interest carried through each geocoding branch
desired_columns <- c(
  "itbi_ref_year",
  "itbi_ref_month",
  "sql_number",
  "lot_code",
  "block_code",
  "transaction_type",
  "transaction_date",
  "transaction_proportion",
  "property_type",
  "built_area",
  "declared_value",
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

# Merging ITBI and cadastral data by the lot code
itbi_lots <- itbi_std %>% 
  left_join(lots_sf, by = "lot_code")

# Keeping only successful joins
itbi_lots_done <- itbi_lots %>% 
  filter(!is.na(district)) %>%
  select(
    all_of(desired_columns)
  ) %>% 
  st_as_sf() %>% 
  st_transform(31983) %>% 
  as_tibble()

# Keeping only cases unmatched by the lot code
itbi_lots_left <- itbi_lots %>% 
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
itbi_cnefe <- geocode(
  enderecos          = itbi_lots_left,
  campos_endereco    = campos_geocodebr,
  resultado_completo = TRUE,
  resolver_empates   = TRUE,
  resultado_sf       = TRUE,
  verboso            = FALSE,
  cache              = TRUE
) %>%
  st_transform(31983) %>% 
  as_tibble()

# Keeping only bad matches (non-“numero” and non-“numero_aproximado” cases)
itbi_cnefe_left <- itbi_cnefe %>%
  filter(!precisao %in% c("numero", "numero_aproximado")) %>% 
  select(
    all_of(desired_columns),
    -geometry
  )
  
# Keeping only good matches (“numero” and “numero_aproximado” cases)
itbi_cnefe_done <- itbi_cnefe %>%
  filter(precisao %in% c("numero", "numero_aproximado")) %>%
  select(
    all_of(desired_columns),
    -block_code
  )


################################################################################
##### VII. Geocoding by block code
################################################################################

# Merging ITBI and cadastral data by the block code
itbi_blocks <- itbi_cnefe_left %>% 
  left_join(blocks_sf, by = "block_code") 

# Keeping only successful joins
itbi_blocks_done <- itbi_blocks %>% 
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
itbi_geocoded <- bind_rows(
  itbi_lots_done,
  itbi_cnefe_done,
  itbi_blocks_done
) %>%
  st_as_sf()

# Counting ungeocoded ITBI entries
itbi_uncoded <- nrow(itbi_df) - nrow(itbi_geocoded)


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
  x    = itbi_geocoded,
  sink = output_file
)
