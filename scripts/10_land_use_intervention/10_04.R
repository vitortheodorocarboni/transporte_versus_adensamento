################################################################################
##################################            ##################################
######################### 10.04) DOWNLOAD SINAPI-SP DATA ######################
##################################            ##################################
################################################################################

################################################################################
##### I. Packages
################################################################################

# # Installing packages
# install.packages("arrow")
# install.packages("curl")
# install.packages("jsonlite")
# install.packages("tibble")

# Loading libraries
library(arrow)
library(curl)
library(jsonlite)
library(tibble)


################################################################################
##### II. Directories and files
################################################################################

# Loading project paths
source(file.path("scripts", "_config", "paths.R"))

# Setting output data directory
output_directory <- processed_path("interventions", "land_use_intervention")

# Setting output data file (single numeric m2_cost benchmark, wrapped as a
# one-row tibble for Parquet)
output_file <- file.path(output_directory, "sinapi_sp_2025_m2_cost.parquet")


################################################################################
##### III. SINAPI API parameters
################################################################################

# Defining SINAPI reference year
sinapi_year <- 2025

# Defining SINAPI SIDRA table
sinapi_table <- 2296

# Defining São Paulo UF code
sinapi_state <- 35

# Defining SINAPI variable for "Custo médio m² - moeda corrente"
sinapi_variable <- 48

# Defining first and last monthly periods
first_period <- paste0(sinapi_year, "01")
last_period  <- paste0(sinapi_year, "12")

# Building SIDRA API URL
sinapi_url <- paste0(
  "https://apisidra.ibge.gov.br/values",
  "/t/", sinapi_table,
  "/n3/", sinapi_state,
  "/p/", first_period, "-", last_period,
  "/v/", sinapi_variable,
  "?formato=json"
)


################################################################################
##### IV. Downloading data
################################################################################

# Creating API request configuration object
sinapi_handle <- new_handle()

# Adding request header
handle_setheaders(
  handle       = sinapi_handle,
  "User-Agent" = "Mozilla/5.0"
)

# Downloading SINAPI data from SIDRA API
sinapi_response <- curl_fetch_memory(
  url    = sinapi_url,
  handle = sinapi_handle
)

# Converting JSON response to a data frame
sinapi_json <- fromJSON(rawToChar(sinapi_response$content))


################################################################################
##### V. Computing the annual m2 cost benchmark
################################################################################

# Dropping the SIDRA header row and extracting the monthly cost vector
monthly_costs <- as.numeric(sinapi_json$V[-1])

# Computing the annual mean of monthly current SINAPI-SP m2 costs
m2_cost <- mean(monthly_costs, na.rm = TRUE)

# Reporting the benchmark
message(
  "SINAPI-SP ", sinapi_year, " annual mean m2 cost: R$ ",
  format(round(m2_cost, 2), nsmall = 2, big.mark = ".", decimal.mark = ",")
)


################################################################################
##### VI. Exporting outputs
################################################################################

# Creating output directory
dir.create(
  path         = output_directory,
  recursive    = TRUE,
  showWarnings = FALSE
)

# Saving the m2 cost benchmark as Parquet file
write_parquet(
  x    = tibble(m2_cost = m2_cost),
  sink = output_file
)
