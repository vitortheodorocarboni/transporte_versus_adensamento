################################################################################
##################################            ##################################
########### 11.02) DECOMPOSE WELFARE GAINS INTO ECONOMIC CHANNELS ###############
##################################            ##################################
################################################################################

# Welfare in the CSM admits the exact identity u_i = B_i * W_i * Q_i^-(1 - alpha),
# where B is amenities, W is urban accessibility and Q is the floorspace price.
# Taking logs and differencing between the original and the counterfactual
# equilibrium yields the log-linear decomposition
#   hat(u) = hat(B) + hat(W) - (1 - alpha) * hat(Q).
# Accessibility is decomposed further by shift-share into a wage subchannel and a
# travel-time subchannel, plus a non-linear interaction residual, by building two
# intermediate counterfactuals in which only wages or only travel times move.

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

# Retrieving baseline scenario equilibrium file
baseline_input <- results_path("baseline_scenario", "baseline_scenario.parquet")

# Retrieving transport scenario equilibrium file
transport_input <- results_path("transport_scenario", "transport_scenario.parquet")

# Retrieving land-use scenario equilibrium file
land_use_input <- results_path("land_use_scenario", "land_use_scenario.parquet")

# Retrieving calibrated model parameters file
parameters_input <- processed_path("parameters", "all_parameters", "all_parameters.parquet")

# Retrieving baseline travel-time matrix
baseline_matrix_input <- processed_path("travel_times", "matrix_full.parquet")

# Retrieving transport counterfactual travel-time matrix
counterfactual_matrix_input <- processed_path(
  "interventions",
  "transport_intervention",
  "matrix",
  "counterfactual_matrix_full.parquet"
)

# Setting policy comparison output directory
output_directory <- results_path("policy_comparison")

# Setting per-zone decomposition output file path
zone_output_file <- file.path(output_directory, "welfare_decomposition_zone.parquet")

# Setting aggregate decomposition output file path
aggregate_output_file <- file.path(output_directory, "welfare_decomposition_aggregate.parquet")


################################################################################
##### III. Data
################################################################################

# Reading baseline scenario equilibrium (one row per OD zone)
baseline <- read_geoparquet_sf(baseline_input) %>%
  st_drop_geometry() %>%
  select(zona, residents, wage, amenities, market_access, floorspace_price, welfare) %>%
  arrange(zona)

# Reading transport scenario equilibrium (one row per OD zone)
transport <- read_geoparquet_sf(transport_input) %>%
  st_drop_geometry() %>%
  select(zona, wage, amenities, market_access, floorspace_price, welfare) %>%
  arrange(zona)

# Reading land-use scenario equilibrium (one row per OD zone)
land_use <- read_geoparquet_sf(land_use_input) %>%
  st_drop_geometry() %>%
  select(zona, wage, amenities, market_access, floorspace_price, welfare) %>%
  arrange(zona)

# Reading the baseline travel-time matrix in long format
baseline_matrix_long <- read_parquet(baseline_matrix_input)

# Reading the transport counterfactual travel-time matrix in long format
counterfactual_matrix_long <- read_parquet(counterfactual_matrix_input)


################################################################################
##### IV. Model parameters
################################################################################

# Reading the calibrated parameters
parameters <- read_parquet(parameters_input)

# Extracting the non-housing expenditure share
alpha <- parameters$value[parameters$parameter == "alpha"]

# Extracting the Frechet parameter
theta <- parameters$value[parameters$parameter == "theta"]

# Extracting the commuting cost parameter
epsilon <- parameters$value[parameters$parameter == "epsilon"]


################################################################################
##### V. Welfare channel decomposition (amenities, accessibility, price)
################################################################################

# Creating a function that decomposes a scenario against the baseline equilibrium
decompose_scenario <- function(scenario, baseline, alpha) {
  tibble(
    zona                      = scenario$zona,
    welfare_log_pct           = 100 * (log(scenario$welfare) - log(baseline$welfare)),
    amenities                 = 100 * (log(scenario$amenities) - log(baseline$amenities)),
    accessibility_total       = 100 * (log(scenario$market_access) - log(baseline$market_access)),
    floorspace_price          = -(1 - alpha) * 100 *
      (log(scenario$floorspace_price) - log(baseline$floorspace_price))
  )
}

# Decomposing the transport scenario
transport_decomposition <- decompose_scenario(transport, baseline, alpha)

# Decomposing the land-use scenario
land_use_decomposition <- decompose_scenario(land_use, baseline, alpha)


################################################################################
##### VI. Accessibility shift-share decomposition (wages vs travel times)
################################################################################

# Fixing the CSM zone ordering used across vectors and matrices
csm_zones <- sort(baseline$zona)

# Creating a function that builds a square travel-time matrix on the CSM sub-grid
build_travel_time_matrix <- function(matrix_long, zones) {
  matrix_wide <- matrix_long %>%
    filter(sample == 1) %>%
    select(from_id, to_id, travel_time) %>%
    pivot_wider(names_from = to_id, values_from = travel_time) %>%
    column_to_rownames("from_id") %>%
    as.matrix()
  matrix_wide[zones, zones]
}

# Building the baseline travel-time matrix
baseline_matrix <- build_travel_time_matrix(baseline_matrix_long, csm_zones)

# Building the transport counterfactual travel-time matrix
counterfactual_matrix <- build_travel_time_matrix(counterfactual_matrix_long, csm_zones)

# Applying the lower envelope so counterfactual times never exceed baseline times,
# matching the matrix passed to the transport equilibrium solver
counterfactual_matrix <- pmin(counterfactual_matrix, baseline_matrix)

# Creating a function that extracts a wage vector in the CSM zone ordering
build_wage_vector <- function(scenario, zones) {
  setNames(scenario$wage, scenario$zona)[zones]
}

# Building the wage vectors for each scenario
baseline_wage <- build_wage_vector(baseline, csm_zones)
transport_wage <- build_wage_vector(transport, csm_zones)
land_use_wage <- build_wage_vector(land_use, csm_zones)

# Creating a function that recovers the accessibility index from wages and times
accessibility_index <- function(wage_vector, travel_time_matrix, theta, epsilon) {
  inner <- exp(-theta * epsilon * travel_time_matrix) %*% (wage_vector^theta)
  as.numeric(inner)^(1 / theta)
}

# Recovering the baseline accessibility index
baseline_accessibility <- accessibility_index(baseline_wage, baseline_matrix, theta, epsilon)

# Recovering the accessibility index of each scenario at its full counterfactual
transport_accessibility <- accessibility_index(transport_wage, counterfactual_matrix, theta, epsilon)
land_use_accessibility <- accessibility_index(land_use_wage, baseline_matrix, theta, epsilon)

# Recovering the wage-only accessibility (counterfactual wages, baseline times)
transport_accessibility_wage <- accessibility_index(transport_wage, baseline_matrix, theta, epsilon)
land_use_accessibility_wage <- accessibility_index(land_use_wage, baseline_matrix, theta, epsilon)

# Recovering the time-only accessibility (baseline wages, counterfactual times)
transport_accessibility_time <- accessibility_index(baseline_wage, counterfactual_matrix, theta, epsilon)
land_use_accessibility_time <- accessibility_index(baseline_wage, baseline_matrix, theta, epsilon)

# Creating a function that splits the accessibility change into shift-share channels
shift_share_accessibility <- function(full, wage_only, time_only, baseline) {
  hat_total <- 100 * (log(full) - log(baseline))
  wage_channel <- 100 * (log(wage_only) - log(baseline))
  time_channel <- 100 * (log(time_only) - log(baseline))
  tibble(
    zona                      = csm_zones,
    accessibility_wage        = wage_channel,
    accessibility_commute     = time_channel,
    accessibility_interaction = hat_total - wage_channel - time_channel
  )
}

# Splitting the transport accessibility change into its subchannels
transport_shift_share <- shift_share_accessibility(
  transport_accessibility,
  transport_accessibility_wage,
  transport_accessibility_time,
  baseline_accessibility
)

# Splitting the land-use accessibility change into its subchannels
land_use_shift_share <- shift_share_accessibility(
  land_use_accessibility,
  land_use_accessibility_wage,
  land_use_accessibility_time,
  baseline_accessibility
)


################################################################################
##### VII. Assembling the per-zone decomposition
################################################################################

# Creating a function that joins channel and shift-share decompositions per zone
assemble_decomposition <- function(decomposition, shift_share, scenario_label) {
  decomposition %>%
    left_join(shift_share, by = "zona") %>%
    mutate(scenario = scenario_label) %>%
    select(
      scenario,
      zona,
      welfare_log_pct,
      amenities,
      accessibility_total,
      accessibility_wage,
      accessibility_commute,
      accessibility_interaction,
      floorspace_price
    )
}

# Stacking both scenarios into a single per-zone decomposition table
welfare_decomposition_zone <- bind_rows(
  assemble_decomposition(transport_decomposition, transport_shift_share, "transport"),
  assemble_decomposition(land_use_decomposition, land_use_shift_share, "land_use")
)


################################################################################
##### VIII. Aggregating the decomposition (resident-weighted)
################################################################################

# Computing baseline resident weights
resident_weight <- baseline$residents / sum(baseline$residents)

# Creating a function that aggregates a per-zone decomposition by resident weights
aggregate_decomposition <- function(decomposition, weight) {
  decomposition %>%
    summarise(across(
      c(
        amenities,
        accessibility_total,
        accessibility_wage,
        accessibility_commute,
        accessibility_interaction,
        floorspace_price,
        welfare_log_pct
      ),
      \(x) sum(weight * x)
    ))
}

# Aggregating each scenario decomposition
transport_aggregate <- aggregate_decomposition(transport_decomposition %>%
  left_join(transport_shift_share, by = "zona"), resident_weight)
land_use_aggregate <- aggregate_decomposition(land_use_decomposition %>%
  left_join(land_use_shift_share, by = "zona"), resident_weight)

# Building the aggregate decomposition table, one channel per row
welfare_decomposition_aggregate <- tibble(
  channel = c(
    "amenities",
    "accessibility_total",
    "accessibility_wage",
    "accessibility_commute",
    "accessibility_interaction",
    "floorspace_price",
    "total"
  ),
  transport = c(
    transport_aggregate$amenities,
    transport_aggregate$accessibility_total,
    transport_aggregate$accessibility_wage,
    transport_aggregate$accessibility_commute,
    transport_aggregate$accessibility_interaction,
    transport_aggregate$floorspace_price,
    transport_aggregate$welfare_log_pct
  ),
  land_use = c(
    land_use_aggregate$amenities,
    land_use_aggregate$accessibility_total,
    land_use_aggregate$accessibility_wage,
    land_use_aggregate$accessibility_commute,
    land_use_aggregate$accessibility_interaction,
    land_use_aggregate$floorspace_price,
    land_use_aggregate$welfare_log_pct
  )
)


################################################################################
##### IX. Exporting outputs
################################################################################

# Creating output directory
dir.create(
  path         = output_directory,
  recursive    = TRUE,
  showWarnings = FALSE
)

# Saving the per-zone welfare decomposition as Parquet file
write_parquet(
  x    = welfare_decomposition_zone,
  sink = zone_output_file
)

# Saving the aggregate welfare decomposition as Parquet file
write_parquet(
  x    = welfare_decomposition_aggregate,
  sink = aggregate_output_file
)
