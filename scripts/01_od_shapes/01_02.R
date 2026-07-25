################################################################################
##################################            ##################################
########## 01.02) TREAT RAW 2023 OD DATASET TO GET SHAPES AND SURVEY ###########
##################################            ##################################
################################################################################

################################################################################
##### I. Packages
################################################################################

# # Installing packages
# install.packages("arrow")
# install.packages("data.table")
# install.packages("geoarrow")
# install.packages("haven")
# install.packages("sf")
# install.packages("tidyverse")

# Loading libraries
library(arrow)
library(data.table)
library(geoarrow)
library(haven)
library(sf)
library(tidyverse)


################################################################################
##### II. Directories and files
################################################################################

# Loading project paths
source(file.path("scripts", "_config", "paths.R"))

# Retrieving 2023 OD source ZIP file
zip_file <- raw_path("od_2023", "Site_190225_PesquisaOD2023.zip")

# Setting temporary extraction directory
temp_directory <- tempfile(pattern = "od_2023_")

# Setting 2023 OD shapefile sidecar files (needed by st_read)
shapefile_files <- c(
  "Zonas_2023.shp",
  "Zonas_2023.shx",
  "Zonas_2023.dbf",
  "Zonas_2023.prj",
  "Zonas_2023.cpg"
)

# Setting 2023 OD survey file
survey_file <- "Banco2023_divulgacao_190225.sav"

# Retrieving 2023 OD spatial data file (inside temp directory)
shapes_input <- file.path(temp_directory, "Zonas_2023.shp")

# Retrieving 2023 OD survey data file (inside temp directory)
survey_input <- file.path(temp_directory, survey_file)

# Setting output data directory path
output_directory <- processed_path("shapes")

# Setting output spatial data file path
shapes_output <- file.path(output_directory, "od_2023_shapes.parquet")

# Setting output survey data file path
survey_output <- file.path(output_directory, "od_2023_survey.parquet")


################################################################################
##### III. Data
################################################################################

# Creating temporary extraction directory
dir.create(
  path         = temp_directory,
  recursive    = TRUE,
  showWarnings = FALSE
)

# Listing files inside the source ZIP
zip_contents <- unzip(
  zipfile = zip_file,
  list    = TRUE
)

# Resolving the archive paths of the files needed
needed_basenames <- c(shapefile_files, survey_file)
needed_archive_paths <- zip_contents$Name[
  basename(path = zip_contents$Name) %in% needed_basenames
]

# Extracting only the files needed from the source ZIP
unzip(
  zipfile   = zip_file,
  files     = needed_archive_paths,
  exdir     = temp_directory,
  junkpaths = TRUE,
  overwrite = TRUE
)

# Reading 2023 OD survey
survey <- read_sav(survey_input)

# Reading 2023 OD shapefile
shapes <- st_read(shapes_input)

# Removing temporary extraction directory
unlink(
  x         = temp_directory,
  recursive = TRUE,
  force     = TRUE
)


################################################################################
##### IV. Functions
################################################################################

# Creating function to parse values of "zona" columns as "od_XXX"
parse_zona <- function(zona_column) {
  ifelse(
    test = is.na(zona_column),
    yes  = NA,
    no   = paste0(
      "od_",
      str_pad(
        string = as.character(zona_column),
        width  = 3,
        pad    = 0
      )
    )
  )
}


################################################################################
##### V. Treating shapes dataset
################################################################################

# Filtering OD zones located in the municipality of São Paulo
shapes_complete <- shapes %>%
  filter(NumeroMuni == 36)

# Setting "zona" column as character
shapes_complete <- shapes_complete %>% 
  rename(
    zona = NumeroZona
  ) %>%
  mutate(
    zona = as.integer(zona),
    zona = parse_zona(zona)
  ) %>%
  select(zona) %>% 
  st_transform(31983)


################################################################################
##### VI. Treating survey dataset
################################################################################

# Fixing SAV labels
survey_complete <- survey %>% 
  as_tibble() %>%
  zap_labels()

# Correcting variable types
survey_complete <- survey_complete %>% 
  # Putting column names in lowercase
  rename_with(tolower) %>% 
  mutate(
    zona     = as.integer(zona),
    zona_o   = as.integer(zona_o),
    zona_d   = as.integer(zona_d),
    zonatra1 = as.integer(zonatra1),
    zonatra2 = as.integer(zonatra2)
  ) %>% 
  rename(
    raca = raça
  )

# Setting "zona" columns as character
survey_complete <- survey_complete %>% 
  mutate(
    zona     = parse_zona(zona),
    zona_o   = parse_zona(zona_o),
    zona_d   = parse_zona(zona_d),
    zonatra1 = parse_zona(zonatra1),
    zonatra2 = parse_zona(zonatra2)
  )

# Adding "id" column
survey_complete <- survey_complete %>% 
  rowid_to_column("id") %>% 
  relocate(id)


################################################################################
##### VII. Exporting outputs
################################################################################

# Creating output directory
dir.create(
  path         = output_directory,
  recursive    = TRUE,
  showWarnings = FALSE
)

# Saving shapes as GeoParquet file
write_parquet(
  x    = shapes_complete,
  sink = shapes_output
)

# Saving survey as Parquet file
write_parquet(
  x    = survey_complete,
  sink = survey_output
)


################################################################################
##### VIII. Cleaning raw OD directory (keeping only the source ZIP)
################################################################################

# Setting raw OD directory
raw_od_directory <- raw_path("od_2023")

# Listing entries inside the raw OD directory
raw_od_entries <- list.files(
  path       = raw_od_directory,
  full.names = TRUE,
  recursive  = FALSE,
  all.files  = TRUE,
  no..       = TRUE
)

# Removing every entry except the source ZIP file
entries_to_remove <- raw_od_entries[
  normalizePath(raw_od_entries, winslash = "/", mustWork = FALSE) !=
    normalizePath(zip_file,      winslash = "/", mustWork = FALSE)
]
unlink(
  x         = entries_to_remove,
  recursive = TRUE,
  force     = TRUE
)
