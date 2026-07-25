################################################################################
##################################            ##################################
###################### 07.02) COMPUTE HOUSING CONSUMPTION ######################
##################################            ##################################
################################################################################

################################################################################
##### I. Packages
################################################################################

# # Installing packages
# install.packages("arrow")
# install.packages("sidrar")
# install.packages("tidyverse")

# Loading libraries
library(arrow)
library(sidrar)
library(tidyverse)


################################################################################
##### II. Directories and files
################################################################################

# Loading project paths
source(file.path("scripts", "_config", "paths.R"))

# Setting output data directory
output_directory <- processed_path("parameters", "housing_consumption")

# Setting output data file
output_file <- file.path(output_directory, "housing_consumption.parquet")


################################################################################
##### III. SIDRA parameters
################################################################################

# Setting SIDRA API query for POF 2018 expenditure data in Sao Paulo state
sidra_api_query <- paste0(
  "/t/6715",
  "/n3/35",
  "/v/1201",
  "/p/2018",
  "/c339/7999",
  "/c12190/103538,103541,8009",
  "/f/c",
  "/h/y",
  "/d/m"
)

# Setting SIDRA expenditure type codes
total_consumption_code <- "103538"
rent_code              <- "103541"
condo_code             <- "8009"


################################################################################
##### IV. Data
################################################################################

# Downloading POF 2018 expenditure data for Sao Paulo
sidra_6715 <- get_sidra(api = sidra_api_query)

# Identifying the expenditure type code column
expense_code_column <- names(sidra_6715)[ncol(sidra_6715)]

# Formatting expenditure data
housing_consumption_data <- sidra_6715 %>%
  transmute(
    expense_code = .data[[expense_code_column]],
    value        = as.numeric(Valor)
  )



################################################################################
##### V. Computing housing consumption share
################################################################################

# Computing housing consumption share from rent and condominium expenses
housing_consumption <- housing_consumption_data %>%
  summarise(
    total_consumption         = value[expense_code == total_consumption_code],
    rent_consumption          = value[expense_code == rent_code],
    condo_consumption         = value[expense_code == condo_code],
    housing_consumption       = rent_consumption + condo_consumption,
    housing_consumption_share = housing_consumption / total_consumption,
  ) %>%
  select(housing_consumption_share)


################################################################################
##### VI. Exporting outputs
################################################################################

# Creating output directory
dir.create(
  path         = output_directory,
  recursive    = TRUE,
  showWarnings = FALSE
)

# Saving housing consumption share as Parquet file
write_parquet(
  x    = housing_consumption,
  sink = output_file
)
