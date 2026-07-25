################################################################################
##################################            ##################################
############### 04.06) AGGREGATE PRICE DATA AT THE OD GRID LEVEL ###############
##################################            ##################################
################################################################################

################################################################################
##### I. Packages
################################################################################

# # Installing packages
# install.packages("arrow")
# install.packages("geoarrow")
# install.packages("rbcb")
# install.packages("sf")
# install.packages("tidyverse")

# Loading libraries
library(arrow)
library(geoarrow)
library(rbcb)
library(sf)
library(tidyverse)


################################################################################
##### II. Directories and files
################################################################################

# Loading project paths
source(file.path("scripts", "_config", "paths.R"))

# Retrieving geolocated ITBI transactions file (produced by 04_04.R)
itbi_file <- processed_path("floorspace_prices", "itbi_geocoded.parquet")

# Retrieving 2023 OD processed shapes file
od_file <- processed_path("shapes", "od_2023_shapes.parquet")

# Setting output data directory path
output_directory <- processed_path("floorspace_prices")

# Setting output data file path
output_file <- file.path(output_directory, "price_dataset.parquet")


################################################################################
##### III. Data
################################################################################

# Reading 2023 OD shapes dataset
od <- read_geoparquet_sf(od_file)

# Reading geolocated ITBI transactions
itbi <- read_geoparquet_sf(itbi_file)


################################################################################
##### IV. Adjusting declared values for inflation
################################################################################

# Defining the analytical window for the price series
start_date <- as.Date("2005-01-01")
end_date   <- as.Date("2025-12-31")

# Deriving the inflation base month (YYYY-MM) from the final date
base_month <- format(end_date, "%Y-%m")

# Downloading IPCA monthly series (BCB SGS code 433)
ipca_series <- get_series(
  code       = 433,
  start_date = start_date,
  end_date   = end_date
) %>%
  mutate(
    ipca_ref_month = format(date, "%Y-%m")
  ) %>%
  select(
    ipca_ref_month,
    ipca = `433`
  )

# Obtaining base inflation index from the final month of the period of interest
base_ipca <- ipca_series %>%
  filter(ipca_ref_month == base_month) %>%
  pull(ipca)

# Creating a helper that parses ITBI transaction dates after the all-character coerce
parse_itbi_date <- function(x) {
  d <- suppressWarnings(as.Date(x))
  serial_idx <- is.na(d) & !is.na(x) & grepl("^\\d+(\\.\\d+)?$", x)
  if (any(serial_idx)) {
    serials <- suppressWarnings(as.numeric(x[serial_idx]))
    d[serial_idx] <- as.Date(serials, origin = "1899-12-30")
  }
  d
}

# Joining IPCA index to the ITBI data frame and deflating declared values
itbi_adjusted <- itbi %>%
  mutate(
    # Restoring proper types after the all-character read
    itbi_ref_month         = as.numeric(itbi_ref_month),
    itbi_ref_year          = as.numeric(itbi_ref_year),
    transaction_date       = parse_itbi_date(transaction_date),
    transaction_proportion = as.numeric(transaction_proportion),
    built_area             = as.numeric(built_area),
    declared_value         = as.numeric(declared_value)
  ) %>%
  # Building the IPCA reference month key from the actual transaction date
  mutate(
    ipca_ref_month = format(transaction_date, "%Y-%m")
  ) %>%
  left_join(ipca_series, by = "ipca_ref_month") %>%
  # Computing real (deflated) transaction values, expressed in the base month's BRL
  mutate(
    real_value = declared_value * (base_ipca / ipca)
  ) %>%
  select(
    -ipca_ref_month,
    -ipca
  )


################################################################################
##### V. Filtering transactions and computing price per m^2
################################################################################

# Filtering transactions to the analytical sample
itbi_filtered <- itbi_adjusted %>%
  filter(
    # By built area
    built_area > 0,
    # By transaction date (matches the period of interest defined above)
    transaction_date >= start_date & transaction_date <= end_date,
    # By transaction type
    transaction_type == "1.Compra e venda",
    # By transaction proportion
    transaction_proportion == 100,
    # By property type (whitespace-tolerant comparison)
    trimws(property_type) %in% c(
      "RESIDENCIAL VERTICAL",
      "RESIDENCIAL HORIZONTAL",
      "COMERCIAL VERTICAL",
      "COMERCIAL HORIZONTAL"
    ),
    # By deflated transaction value
    real_value > 0
  )

# Calculating price per square meter and keeping only the columns needed downstream
itbi_m2 <- itbi_filtered %>%
  mutate(
    price_m2 = real_value / built_area
  ) %>% 
  select(
    price_m2
  )


################################################################################
##### VI. Aggregating floor price data at the OD zone level
################################################################################

# Tagging each transaction point with its containing OD zone
itbi_od <- st_join(
  x    = itbi_m2,
  y    = od %>% select(zona),
  left = FALSE
) %>%
  # Aggregating transactions at the OD zone level
  st_set_geometry(NULL) %>%
  group_by(zona) %>%
  summarize(
    n_trans = n(),
    price   = median(price_m2, na.rm = TRUE),
    .groups = "drop"
  )

# Merging everything in a single object (zones with zero transactions receive NA)
price_dataset <- od %>%
  left_join(itbi_od, by = "zona") %>%
  as_tibble() %>%
  select(
    zona,
    n_trans,
    price
  ) %>%
  mutate(
    n_trans = replace_na(n_trans, 0)
  ) %>%
  arrange(zona)


################################################################################
##### VII. Exporting outputs
################################################################################

# Creating output directory
dir.create(
  path         = output_directory,
  recursive    = TRUE,
  showWarnings = FALSE
)

# Saving price dataset as Parquet file
write_parquet(
  x    = price_dataset,
  sink = output_file
)
