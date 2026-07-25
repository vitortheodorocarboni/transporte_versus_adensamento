################################################################################
##################################            ##################################
######################## 08.03) RELATIVE VARIATION FUNCTION #####################
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
##### II. Paths
################################################################################

# Loading project paths
source(file.path("scripts", "_config", "paths.R"))

# Retrieving baseline scenario file (produced by 08_02.R)
baseline_input <- results_path("baseline_scenario", "baseline_scenario.parquet")


################################################################################
##### III. Function
################################################################################

# Computing relative variation (in %) from the baseline scenario
relative_variation_baseline <- function(
  zona,
  residents_cf,
  workplaces_cf,
  floorspace_price_cf,
  wage_cf,
  productivity_cf,
  amenities_cf,
  market_access_cf,
  firm_market_access_cf,
  welfare_cf,
  aggregate_welfare_cf,
  total_population_cf,
  output_cf,
  income_cf,
  share_commercial_floorspace_cf,
  share_population_cf
) {
  # Reading baseline scenario from disk (geometry dropped; only the table is
  # needed for the per-zona comparison)
  baseline_df <- read_parquet(baseline_input) %>%
    as_tibble() %>%
    select(-any_of("geometry"))

  # Assembling counterfactual frame
  counterfactual_df <- tibble(
    zona                         = zona,
    residents                    = residents_cf,
    workplaces                   = workplaces_cf,
    share_population             = share_population_cf,
    floorspace_price             = floorspace_price_cf,
    wage                         = wage_cf,
    income                       = income_cf,
    productivity                 = productivity_cf,
    amenities                    = amenities_cf,
    market_access                = market_access_cf,
    firm_market_access           = firm_market_access_cf,
    welfare                      = welfare_cf,
    aggregate_welfare            = aggregate_welfare_cf,
    total_population             = total_population_cf,
    output                       = output_cf,
    share_commercial_floorspace  = share_commercial_floorspace_cf
  )

  # Aligning baseline to the counterfactual ordering by `zona`
  baseline_aligned_df <- counterfactual_df %>%
    select(zona) %>%
    left_join(baseline_df, by = "zona")

  # Computing percentage variations column by column
  outcome_cols <- setdiff(names(counterfactual_df), "zona")
  variation_df <- tibble(zona = counterfactual_df$zona)
  for (col in outcome_cols) {
    variation_df[[col]] <-
      (counterfactual_df[[col]] - baseline_aligned_df[[col]]) /
      na_if(baseline_aligned_df[[col]], 0) * 100
  }

  variation_df
}
