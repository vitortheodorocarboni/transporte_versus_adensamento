################################################################################
##################################            ##################################
##################### 04.04) BUILD THE ITBI MASTER DATASET #####################
##################################            ##################################
################################################################################

################################################################################
##### I. Packages
################################################################################

# # Installing packages
# install.packages("arrow")
# install.packages("furrr")
# install.packages("future")
# install.packages("openxlsx2")
# install.packages("tidyverse")

# Loading libraries
library(arrow)
library(furrr)
library(future)
library(openxlsx2)
library(tidyverse)


################################################################################
##### II. Directories and files
################################################################################

# Loading project paths
source(file.path("scripts", "_config", "paths.R"))

# Retrieving ITBI guides ZIP archive (produced by 04_03.R)
input_zip <- raw_path("floorspace_prices", "itbi_guides.zip")

# Setting processed output directory
output_directory <- processed_path("floorspace_prices")

# Setting processed output Parquet file
output_file <- file.path(output_directory, "itbi_single_data_frame.parquet")


################################################################################
##### III. Data
################################################################################


# Creating a temporary directory to unzip the xlsx files into
unzip_directory <- tempfile(pattern = "itbi_guides_")
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

# Extracting all xlsx files from the ZIP archive
unzip(
  zipfile   = input_zip,
  exdir     = unzip_directory,
  overwrite = TRUE
)

# Listing all unzipped ITBI Excel files
itbi_files <- list.files(
  path       = unzip_directory,
  pattern    = "\\.xlsx$",
  recursive  = TRUE,
  full.names = TRUE
)

# Naming the file vector by the 4-digit reference year extracted from each filename
itbi_files <- setNames(
  object = itbi_files,
  nm     = str_extract(basename(itbi_files), "\\d{4}")
)


################################################################################
##### IV. Reading specifications
################################################################################

# Specifying sheets, in the annual datasets, that contain solely metadata
meta_sheets <- c(
  "LEGENDA",
  "EXPLICAÇÕES",
  "Tabela de USOS",
  "Tabela de PADRÕES"
)

# Ensuring that every column name in each data-only sheet will be correct (for there are some typos)
desired_cols <- c(
  "N° do Cadastro (SQL)",
  "Nome do Logradouro",
  "Número",
  "Complemento",
  "Bairro",
  "Referência",
  "CEP",
  "Natureza de Transação",
  "Valor de Transação (declarado pelo contribuinte)",
  "Data de Transação",
  "Valor Venal de Referência",
  "Proporção Transmitida (%)",
  "Valor Venal de Referência (proporcional)",
  "Base de Cálculo adotada",
  "Tipo de Financiamento",
  "Valor Financiado",
  "Cartório de Registro",
  "Matrícula do Imóvel",
  "Situação do SQL",
  "Área do Terreno (m2)",
  "Testada (m)",
  "Fração Ideal",
  "Área Construída (m2)",
  "Uso (IPTU)",
  "Descrição do uso (IPTU)",
  "Padrão (IPTU)",
  "Descrição do padrão (IPTU)",
  "ACC (IPTU)"
)


################################################################################
##### V. Functions
################################################################################

# Creating function to read one data sheet from a pre-loaded openxlsx2
# workbook. The 20 ITBI workbooks share the same structure (12 monthly
# sheets with 28 columns in a fixed order), but row 1 is sometimes a
# header ("N° do Cadastro (SQL)" in A1) and sometimes a data row — 2 of
# the 240 sheets ship without a header (JAN-2024 and OUT-2024). The
# function detects this per sheet, reads positionally (so any header-
# text typos do not matter), stamps the canonical names, and coerces
# every column to character so list_rbind() never breaks on cell-by-cell
# type mismatches. Numeric/Date columns are restored in section VII.
read_and_reheader <- function(wb, sheet_name) {

  # Detecting whether the sheet starts with a header row
  cell_a1 <- wb_to_df(
    wb,
    sheet     = sheet_name,
    cols      = 1,
    rows      = 1,
    col_names = FALSE
  )[1, 1]
  has_header <- isTRUE(as.character(cell_a1) == "N° do Cadastro (SQL)")

  # Reading all 28 columns starting at the first data row
  df_raw <- wb_to_df(
    wb,
    sheet        = sheet_name,
    cols         = 1:28,
    start_row    = if (has_header) 2 else 1,
    col_names    = FALSE,
    detect_dates = TRUE
  )

  # Stamping the canonical column names by position
  names(df_raw) <- desired_cols

  # Coercing every column to character to guarantee clean list_rbind()
  # (openxlsx2 may type the same column as <double> in one sheet and
  # <character> in another) and reintroducing leading zeroes on SQL/CEP
  df_clean <- df_raw %>%
    mutate(across(everything(), as.character)) %>%
    mutate(
      `N° do Cadastro (SQL)` = str_pad(
        string = `N° do Cadastro (SQL)`,
        width  = 11,
        side   = "left",
        pad    = "0"
      ),
      CEP = str_pad(
        string = CEP,
        width  = 8,
        side   = "left",
        pad    = "0"
      )
    )

  return(df_clean)
}

# Creating function to process one year file in full
process_year_file <- function(fp) {

  # Loading the workbook a single time (faster than reopening per sheet)
  wb <- wb_load(fp)

  # Identifying data-only sheets by excluding metadata tabs
  data_sheets <- setdiff(wb_get_sheet_names(wb), meta_sheets)

  # Reading and cleaning each sheet, then row-binding into a year tibble
  map(data_sheets, ~ read_and_reheader(wb, .x)) %>%
    set_names(data_sheets) %>%
    list_rbind(names_to = "itbi_ref_month")
}


################################################################################
##### VI. Binding month sheets into one year sheet, then, one master data frame
################################################################################

# Setting parallel execution plan (workers capped to leave one core free)
plan(
  strategy = multisession,
  workers  = max(1L, parallel::detectCores() - 1L)
)

# Restoring sequential plan when the script exits, even on error
on.exit(plan(strategy = sequential), add = TRUE)

# Reading all year files in parallel and row-binding into the master tibble
itbi_df <- future_map(
  .x       = itbi_files,
  .f       = process_year_file,
  .options = furrr_options(seed = TRUE)
) %>%
  list_rbind(names_to = "itbi_ref_year")

# Renaming columns of interest
itbi_refactored <- itbi_df %>%
  rename(
    sql_number             = `N° do Cadastro (SQL)`,
    address_street         = `Nome do Logradouro`,
    address_number         = Número,
    address_complement     = Complemento,
    zip_code               = CEP,
    neighborhood           = Bairro,
    transaction_type       = `Natureza de Transação`,
    transaction_date       = `Data de Transação`,
    transaction_proportion = `Proporção Transmitida (%)`,
    property_type          = `Descrição do padrão (IPTU)`,
    built_area             = `Área Construída (m2)`,
    declared_value         = `Valor de Transação (declarado pelo contribuinte)`
  ) %>%
  select(
    itbi_ref_year,
    itbi_ref_month,
    sql_number,
    address_street,
    address_number,
    address_complement,
    zip_code,
    neighborhood,
    transaction_type,
    transaction_date,
    transaction_proportion,
    property_type,
    built_area,
    declared_value
  )


################################################################################
##### VII. Exporting outputs
################################################################################

# Creating output directory
dir.create(
  path         = output_directory,
  recursive    = TRUE,
  showWarnings = FALSE
)

# Saving ITBI transactions dataset as Parquet file
write_parquet(
  x    = itbi_refactored,
  sink = output_file
)
