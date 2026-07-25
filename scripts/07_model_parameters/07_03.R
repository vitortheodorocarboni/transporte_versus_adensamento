################################################################################
##################################            ##################################
###################### 07.03) CALIBRATING CSM PARAMETERS #######################
##################################            ##################################
################################################################################

################################################################################
##### I. Packages
################################################################################

# # Installing packages
# install.packages("arrow")
# install.packages("tidyverse")

# Loading libraries
library(arrow)
library(tidyverse)


################################################################################
##### II. Directories and files
################################################################################

# Loading project paths
source(file.path("scripts", "_config", "paths.R"))

# Retrieving commuting semielasticity parameter file path
commuting_semielasticity_input <- processed_path("parameters", "commuting_semielasticity", "outcomes_coefficient.parquet")

# Retrieving housing consumption parameter file path
housing_consumption_input <- processed_path("parameters", "housing_consumption", "housing_consumption.parquet")

# Setting calibrated parameters output directory path
output_directory <- processed_path("parameters", "all_parameters")

# Setting calibrated parameters output file path
output_file <- file.path(output_directory, "all_parameters.parquet")


################################################################################
##### III. Data
################################################################################

# Retrieving commuting semielasticity parameter
commuting_semielasticity <- read_parquet(commuting_semielasticity_input) %>%
  pull(commuting_semielasticity)

# Retrieving housing consumption share
housing_consumption <- read_parquet(housing_consumption_input) %>%
  pull(housing_consumption_share)


################################################################################
##### IV. Calibrating parameters
################################################################################

# Calibrating non-housing share in household consumption
alpha <- 1 - housing_consumption

# Calibrating Frechet parameter
frechet <- 6.83

# Calibrating parameter that transforms travel times to commuting costs
commuting_cost_utility <- abs(commuting_semielasticity) / frechet

# Creating a data frame with all parameter values
parameters <- tribble(
    ~parameter,     ~value,                 ~description,
    "alpha",        alpha,                  "Expenditure share on non-housing consumption",
    "beta",         0.8,                    "Output elasticity with respect to labor",
    "theta",        frechet,                "Frechet parameter governing commuting and residential choice sensitivity",
    "delta",        0.3585,                 "Spatial decay parameter for agglomeration externalities",
    "rho",          0.9094,                 "Spatial decay parameter for congestion externalities",
    "lambda",       0.071,                  "Agglomeration force parameter",
    "epsilon",      commuting_cost_utility, "Parameter transforming travel times into commuting costs",
    "mu",           0.75,                   "Curvature parameter in the floorspace supply function",
    "eta",          0.1548,                 "Congestion force parameter",
    "nu_init",      0.05,                   "Convergence parameter used in iterative equilibrium updating",
    "tol",          1e-10,                  "Tolerance threshold for convergence",
    "maxiter",      1500,                   "Maximum number of iterations allowed for convergence",
    "zeta",         0.95,                   "Convergence damping parameter in counterfactual equilibrium solving",
    "varrho",       0,                      "Migration elasticity set to zero for a closed-city equilibrium",
    "sh_city",      1,                      "City population share set to one for a closed-city equilibrium"
  )


################################################################################
##### V. Exporting outputs
################################################################################

# Creating output directory
dir.create(
  path         = output_directory,
  recursive    = TRUE,
  showWarnings = FALSE
)

# Saving parameter calibration data frame as Parquet file
write_parquet(
  x    = parameters,
  sink = output_file
)
