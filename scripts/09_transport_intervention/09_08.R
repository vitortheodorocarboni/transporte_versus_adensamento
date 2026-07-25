################################################################################
##################################            ##################################
########################## 09.08) TRANSPORT SCENARIO ###########################
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

# Loading relative variation function
source(file.path("scripts", "08_baseline_scenario", "08_03.R"))

# Retrieving OD final dataset file
od_input <- processed_path("final_dataset", "od_sample.parquet")

# Retrieving baseline travel-times file
baseline_matrix_input <- processed_path("travel_times", "matrix_full.parquet")

# Retrieving counterfactual travel-times file
matrix_input <- processed_path("interventions", "transport_intervention", "matrix", "counterfactual_matrix_full.parquet")

# Retrieving calibrated parameters file
parameters_input <- processed_path("parameters", "all_parameters", "all_parameters.parquet")

# Retrieving model inversion file (produced by 08_01.R)
inversion_input <- results_path("baseline_scenario", "model_inversion.parquet")

# Setting output directory
output_directory <- results_path("transport_scenario")

# Setting transport scenario output file
output_scenario_file <- file.path(output_directory, "transport_scenario.parquet")

# Setting transport relative variation output file
output_variation_file <- file.path(output_directory, "transport_variation.parquet")


################################################################################
##### III. Data
################################################################################

# Reading OD complete dataset
od_df <- read_geoparquet_sf(od_input) %>%
  arrange(zona)

# Reading baseline travel-times matrix
csm_zones <- sort(od_df$zona)
baseline_matrix <- read_parquet(baseline_matrix_input) %>%
  filter(sample == 1) %>%
  select(from_id, to_id, travel_time) %>%
  pivot_wider(names_from = to_id, values_from = travel_time) %>%
  column_to_rownames("from_id") %>%
  as.matrix()
baseline_matrix <- baseline_matrix[csm_zones, csm_zones]

# Reading counterfactual travel-times matrix
matrix <- read_parquet(matrix_input) %>%
  filter(sample == 1) %>%
  select(from_id, to_id, travel_time) %>%
  pivot_wider(names_from = to_id, values_from = travel_time) %>%
  column_to_rownames("from_id") %>%
  as.matrix()
matrix <- matrix[csm_zones, csm_zones]

# Reading calibrated parameters file
parameters_df <- read_parquet(parameters_input)

# Reading inversion model results file
inversion <- read_geoparquet_sf(inversion_input)


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

# Applying lower-envelope correction (additive transit cannot lengthen any OD pair;
# enforces t_ij_counterfactual <= t_ij_baseline before passing to solveModel)
matrix <- pmin(matrix, baseline_matrix)


################################################################################
##### V. Solving model
################################################################################

# Solving model using inverted parameters
model_results <- solveModel(
  # Variables
  N         = n_zones,
  t_ij      = matrix,
  L_i       = od_df$residents_weighted,
  L_j       = od_df$workplaces,
  K         = od_df$land_area_km,
  varphi    = inversion$density_land_development,
  a         = inversion$production_fundamentals,
  b         = inversion$residential_fundamentals,
  w_eq      = inversion$wage,
  u_eq      = inversion$welfare,
  Q_eq      = inversion$floorspace_price,
  ttheta_eq = inversion$share_commercial_floorspace,
  # Calibrated parameters
  alpha   = parameters$alpha,
  beta    = parameters$beta,
  theta   = parameters$theta,
  mu      = parameters$mu,
  delta   = parameters$delta,
  lambda  = parameters$lambda,
  rho     = parameters$rho,
  eta     = parameters$eta,
  epsilon = parameters$epsilon,
  zeta    = parameters$zeta,
  varrho  = parameters$varrho,
  sh_city = parameters$sh_city,
  tol     = parameters$tol,
  maxiter = parameters$maxiter,
  verbose = TRUE
)

# Converting model outputs into a data frame
scenario_df <- tibble(
  zona                         = od_shapes$zona,
  residents                    = as.numeric(model_results$L_i),
  workplaces                   = as.numeric(model_results$L_j),
  share_population             = as.numeric(model_results$lambda_i),
  floorspace_price             = as.numeric(model_results$Q),
  wage                         = as.numeric(model_results$w),
  income                       = as.numeric(model_results$ybar),
  productivity                 = as.numeric(model_results$A),
  amenities                    = as.numeric(model_results$B),
  market_access                = as.numeric(model_results$W_i),
  firm_market_access           = as.numeric(model_results$FCMA),
  welfare                      = as.numeric(model_results$u),
  aggregate_welfare            = as.numeric(model_results$U),
  total_population             = as.numeric(model_results$L_bar),
  output                       = as.numeric(model_results$Y),
  share_commercial_floorspace  = as.numeric(model_results$ttheta)
)

# Adding columns for OD zones shapes and area
scenario_sf <- od_shapes %>%
  left_join(od_land_area, by = "zona") %>% 
  left_join(scenario_df, by = "zona") %>% 
  # Keeping columns of interest
  select(
    zona,
    residents,
    workplaces,
    share_population,
    land_area_km,
    land_area_ha,
    floorspace_price,
    wage,
    income,
    productivity,
    amenities,
    market_access,
    firm_market_access,
    welfare,
    aggregate_welfare,
    total_population,
    output,
    share_commercial_floorspace
  )


################################################################################
##### VI. Measuring relative variation against baseline
################################################################################

# Computing relative variation (in %) against the baseline scenario
variation_df <- relative_variation_baseline(
  zona                     = scenario_df$zona,
  residents_cf             = scenario_df$residents,
  workplaces_cf            = scenario_df$workplaces,
  floorspace_price_cf      = scenario_df$floorspace_price,
  wage_cf                  = scenario_df$wage,
  productivity_cf          = scenario_df$productivity,
  amenities_cf             = scenario_df$amenities,
  market_access_cf         = scenario_df$market_access,
  firm_market_access_cf    = scenario_df$firm_market_access,
  welfare_cf               = scenario_df$welfare,
  aggregate_welfare_cf     = scenario_df$aggregate_welfare,
  total_population_cf      = scenario_df$total_population,
  output_cf                = scenario_df$output,
  income_cf                = scenario_df$income,
  share_commercial_floorspace_cf = scenario_df$share_commercial_floorspace,
  share_population_cf      = scenario_df$share_population
)

# Adding columns for OD zones shapes and area
variation_sf <- od_shapes %>%
  left_join(od_land_area, by = "zona") %>%
  left_join(variation_df, by = "zona")


################################################################################
##### VII. Exporting outputs
################################################################################

# Creating output directory
dir.create(
  path         = output_directory,
  recursive    = TRUE,
  showWarnings = FALSE
)

# Saving scenario as GeoParquet file
write_parquet(
  x    = scenario_sf,
  sink = output_scenario_file
)

# Saving relative variation as GeoParquet file
write_parquet(
  x    = variation_sf,
  sink = output_variation_file
)
