################################################################################
##################################            ##################################
######### 02.01) COUNT RESIDENT AND WORKPLACE WORKERS PER OD ZONE ##############
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

# Retrieving 2023 OD processed survey dataset file path
survey_input_directory <- processed_path("shapes", "od_2023_survey.parquet")

# Retrieving 2023 OD processed shapes dataset file path
shapes_input_directory <- processed_path("shapes", "od_2023_shapes.parquet")

# Setting output data directory path
output_directory <- processed_path("workers")

# Setting output data file path
output_file <- file.path(output_directory, "workers.parquet")


################################################################################
##### III. Data
################################################################################

# Reading 2023 OD survey dataset
survey <- read_parquet(survey_input_directory)

# Reading 2023 OD shapes dataset
shapes <- read_geoparquet_sf(shapes_input_directory)


################################################################################
##### IV. Computing residents per OD zone
################################################################################

# Marking zones located in São Paulo
zones_sp <- sort(shapes$zona)

# Keeping working population currently living in the city of São Paulo
survey_residents_sp <- survey %>%
  filter(
    zona     %in% zones_sp,
    cd_ativi %in% c(1, 2, 3)
  ) %>%
  # Keeping only one observation per person in the survey
  distinct(id_pess, .keep_all = TRUE)

# Aggregating residents by OD zone
residents_dataset <- survey_residents_sp %>%
  group_by(zona) %>%
  summarise(
    residents = round(sum(fe_pess, na.rm = TRUE), 0),
    .groups   = "drop"
  ) %>%
  arrange(zona)


################################################################################
##### V. Computing workplaces per OD zone
################################################################################

# Uniting primary and secondary workplace zones if one of those is in São Paulo
survey_workzone_sp <- survey %>%
  mutate(
    workzone_sp = case_when(
      munitra1 == 36                   ~ zonatra1,
      munitra2 == 36                   ~ zonatra2,
      munitra1 != 36 & munitra2 != 36  ~ NA
    )
  )

# Keeping only active workers whose workplace is in São Paulo
survey_workplaces_sp <- survey_workzone_sp %>%
  filter(
    cd_ativi    %in% c(1, 2, 3),
    workzone_sp %in% zones_sp
  ) %>%
  # Keeping only one observation per person in the survey
  distinct(id_pess, .keep_all = TRUE)

# Aggregating workers by work zone
workplaces_dataset <- survey_workplaces_sp %>%
  group_by(workzone_sp) %>%
  summarise(
    workplaces = round(sum(fe_pess, na.rm = TRUE), 0),
    .groups    = "drop"
  ) %>%
  rename(
    zona = workzone_sp
  ) %>%
  arrange(zona)


################################################################################
##### VI. Building combined workers dataset
################################################################################

# Joining residents and workplaces onto the full set of São Paulo OD zones,
workers_dataset <- st_drop_geometry(shapes) %>%
  select(zona) %>%
  left_join(residents_dataset, by = "zona") %>%
  left_join(workplaces_dataset, by = "zona") %>%
  # Filling zones with no residents and/or no workplaces with zeros
  mutate(
    residents  = replace_na(residents, 0),
    workplaces = replace_na(workplaces, 0)
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

# Saving workers dataset as Parquet file
write_parquet(
  x    = workers_dataset,
  sink = output_file
)
