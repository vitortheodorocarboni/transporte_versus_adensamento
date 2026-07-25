################################################################################
##################################            ##################################
############################ 08.01) MODEL INVERSION ############################
##################################            ##################################
################################################################################

################################################################################
##### I. Packages
################################################################################

# # Installing packages
# install.packages("arrow")
# install.packages("geoarrow")
# install.packages("IGC.CSM")
# install.packages("sf")
# install.packages("tidyverse")

# Loading libraries
library(arrow)
library(geoarrow)
library(IGC.CSM)
library(sf)
library(tidyverse)


################################################################################
##### II. Directories and files
################################################################################

# Loading project paths
source(file.path("scripts", "_config", "paths.R"))

# Retrieving OD final dataset file
od_input <- processed_path("final_dataset", "od_sample.parquet")

# Retrieving baseline travel-times file (long-form full grid; this script
# filters to sample == 1 and pivots to a square matrix indexed by zona)
matrix_input <- processed_path("travel_times", "matrix_full.parquet")

# Retrieving calibrated parameters file
parameters_input <- processed_path("parameters", "all_parameters", "all_parameters.parquet")

# Setting model inversion output directory
output_directory <- results_path("baseline_scenario")

# Setting model inversion output file
output_file <- file.path(output_directory, "model_inversion.parquet")


################################################################################
##### III. Data
################################################################################

# Reading OD complete dataset
od_df <- read_geoparquet_sf(od_input) %>%
  arrange(zona)

# Reading travel-times matrix (filter to CSM pairs and pivot to square matrix
# indexed by the same zona ordering as od_df)
csm_zones <- sort(od_df$zona)
matrix <- read_parquet(matrix_input) %>%
  filter(sample == 1) %>%
  select(from_id, to_id, travel_time) %>%
  pivot_wider(names_from = to_id, values_from = travel_time) %>%
  column_to_rownames("from_id") %>%
  as.matrix()
matrix <- matrix[csm_zones, csm_zones]

# Reading calibrated parameters file
parameters_df <- read_parquet(parameters_input)


################################################################################
##### IV. Preparation for running the CSM
################################################################################

# Separating OD shapes
od_shapes <- od_df %>%
  select(zona) %>% 
  arrange(zona)

# Counting number of zones
n_zones <- length(od_df$zona)

# Separating land area variables
od_land_area <- od_df %>% 
  st_drop_geometry() %>% 
  select(
    zona,
    land_area_km,
    land_area_ha
  )

# Parsing parameters as named lists
parameters <- parameters_df %>%
  select(parameter, value) %>%
  deframe() %>%
  as.list()


################################################################################
##### V. Model inversion
################################################################################

# Inverting the model
inversion <- inversionModel(
  # Variables
  N    = n_zones,
  t_ij = matrix,
  L_i  = od_df$residents_weighted,
  L_j  = od_df$workplaces,
  Q    = od_df$price,
  K    = od_df$land_area_km,
  # Calibrated parameters
  alpha   = parameters$alpha,
  beta    = parameters$beta,
  theta   = parameters$theta,
  delta   = parameters$delta,
  rho     = parameters$rho,
  lambda  = parameters$lambda,
  epsilon = parameters$epsilon,
  mu      = parameters$mu,
  eta     = parameters$eta,
  nu_init = parameters$nu_init,
  tol     = parameters$tol,
  maxiter = parameters$maxiter,
  verbose = TRUE
)

# Converting into a data frame
inversion_df <- as_tibble(inversion) %>% 
  # Renaming columns
  rename(
    residents                   = L_i,
    workplaces                  = L_j,
    floorspace_price            = Q_norm,
    wage                        = w,
    production_fundamentals     = a,
    residential_fundamentals    = b,
    density_land_development    = varphi,
    productivity                = A,
    amenities                   = B,
    welfare                     = u,
    aggregate_welfare           = U,
    share_commercial_floorspace = ttheta
  ) %>% 
  # Adding OD zone index column
  mutate(
    zona = od_shapes$zona
  )

# Adding columns for OD zones shapes and area
inversion_sf <- od_shapes %>%
  left_join(od_land_area, by = "zona") %>% 
  left_join(inversion_df, by = "zona") %>% 
  # Keeping columns of interest
  select(
    zona,
    residents,
    workplaces,
    land_area_km,
    land_area_ha,
    floorspace_price,
    wage,
    production_fundamentals,
    residential_fundamentals,
    density_land_development,
    productivity,
    amenities,
    welfare,
    aggregate_welfare,
    share_commercial_floorspace
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

# Saving inversion data frame as GeoParquet file
write_parquet(
  x    = inversion_sf,
  sink = output_file
)
