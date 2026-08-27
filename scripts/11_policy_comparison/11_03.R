################################################################################
##################################            ##################################
############### 11.03) COMPUTE COST-BENEFIT OF POLICY SCENARIOS #################
##################################            ##################################
################################################################################

# Each scenario is monetised through the compensating variation: the relative
# change in aggregate welfare is the relative income change that leaves a
# representative worker indifferent between the original and the counterfactual
# equilibrium. Multiplying it by a reference annual wage and by the model worker
# count yields an annual city-wide flow, whose present value is compared against
# the common public budget across horizons and discount rates.

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

# Retrieving baseline scenario equilibrium file
baseline_input <- results_path("baseline_scenario", "baseline_scenario.parquet")

# Retrieving transport scenario equilibrium file
transport_input <- results_path("transport_scenario", "transport_scenario.parquet")

# Retrieving land-use scenario equilibrium file
land_use_input <- results_path("land_use_scenario", "land_use_scenario.parquet")

# Setting policy comparison output directory
output_directory <- results_path("policy_comparison")

# Setting compensating variation output file path
compensating_variation_output_file <- file.path(output_directory, "compensating_variation.parquet")

# Setting benefit-cost ratio output file path
benefit_cost_output_file <- file.path(output_directory, "benefit_cost_ratio.parquet")

# Setting the Figure 17 output path
bcr_plot_directory <- project_path("paper", "plots")
bcr_plot_output_file <- file.path(
  bcr_plot_directory,
  "policy_comparison_bcr_sensitivity_pt.png"
)


################################################################################
##### III. Data
################################################################################

# Reading the baseline aggregate welfare level (constant across OD zones)
baseline_welfare <- read_parquet(baseline_input) %>%
  pull(aggregate_welfare) %>%
  first()

# Reading the transport aggregate welfare level
transport_welfare <- read_parquet(transport_input) %>%
  pull(aggregate_welfare) %>%
  first()

# Reading the land-use aggregate welfare level
land_use_welfare <- read_parquet(land_use_input) %>%
  pull(aggregate_welfare) %>%
  first()


################################################################################
##### IV. Cost-benefit parameters
################################################################################

# Setting the reference annual income per worker, in R$ (mean per-capita
# household income of São Paulo from the Pesquisa OD 2023, weighted by the
# household expansion factors)
reference_annual_wage <- 32626.98

# Setting the worker count represented in the model
total_workers <- 6352835

# Setting the common public budget of the two interventions, in R$
budget <- 10.3e9

# Setting the evaluation horizons, in years
horizons <- c(20, 30, 50)

# Setting the real annual discount rates
discount_rates <- c(0.03, 0.05, 0.08)


################################################################################
##### V. Computing the compensating variation
################################################################################

# Building the relative aggregate welfare change of each scenario
compensating_variation <- tibble(
  scenario = c("transport", "land_use"),
  relative_welfare_change = c(
    transport_welfare / baseline_welfare - 1,
    land_use_welfare / baseline_welfare - 1
  )
) %>%
  mutate(
    annual_cv_per_worker = relative_welfare_change * reference_annual_wage,
    annual_cv_total      = annual_cv_per_worker * total_workers
  )


################################################################################
##### VI. Computing the benefit-cost ratios
################################################################################

# Creating a function that discounts a constant annual flow to present value
present_value <- function(annual_flow, horizon, discount_rate) {
  if_else(
    discount_rate == 0,
    annual_flow * horizon,
    annual_flow * (1 - (1 + discount_rate)^(-horizon)) / discount_rate
  )
}

# Building the benefit-cost ratio grid over horizons and discount rates
benefit_cost_ratio <- compensating_variation %>%
  select(scenario, annual_cv_total) %>%
  expand_grid(
    horizon       = horizons,
    discount_rate = discount_rates
  ) %>%
  mutate(
    present_value      = present_value(annual_cv_total, horizon, discount_rate),
    benefit_cost_ratio = present_value / budget
  ) %>%
  select(
    scenario,
    horizon,
    discount_rate,
    present_value,
    benefit_cost_ratio
  )


################################################################################
##### VII. Plotting benefit-cost ratios
################################################################################

# Formatting values with the Brazilian decimal separator used in the dissertation
format_decimal_pt <- function(x) {
  formatC(x, format = "f", digits = 2, decimal.mark = ",")
}

# Building the data displayed in Figure 17 from the exact Parquet output object
bcr_plot_data <- benefit_cost_ratio %>%
  mutate(
    scenario = recode(
      scenario,
      transport = "Transporte",
      land_use  = "Adensamento"
    ),
    scenario = factor(scenario, levels = c("Transporte", "Adensamento")),
    horizon = factor(horizon, levels = horizons),
    discount_rate_label = paste0(
      "Taxa real de desconto: ",
      round(discount_rate * 100),
      "%"
    )
  )

# Drawing the sensitivity grid used as Figure 17 in the dissertation
bcr_plot <- ggplot(
  bcr_plot_data,
  aes(x = horizon, y = benefit_cost_ratio, fill = scenario)
) +
  geom_hline(
    yintercept = 1,
    linetype = "dashed",
    colour = "#777777",
    linewidth = 0.4
  ) +
  geom_col(
    position = position_dodge(width = 0.78),
    width = 0.68
  ) +
  geom_text(
    aes(label = format_decimal_pt(benefit_cost_ratio)),
    position = position_dodge(width = 0.78),
    vjust = -0.35,
    size = 3
  ) +
  facet_wrap(~discount_rate_label, nrow = 1) +
  scale_fill_manual(
    values = c(
      "Transporte" = "#BA1F33",
      "Adensamento" = "#2B6CB0"
    )
  ) +
  scale_y_continuous(
    name = "Razão benefício-custo (B/C)",
    limits = c(0, 3.6),
    breaks = 0:3,
    expand = expansion(mult = c(0, 0))
  ) +
  labs(
    x = "Horizonte (anos)",
    fill = NULL
  ) +
  theme_minimal(base_size = 10) +
  theme(
    panel.grid.minor = element_blank(),
    panel.grid.major.x = element_blank(),
    strip.text = element_text(face = "bold"),
    legend.position = "bottom",
    legend.text = element_text(size = 9),
    axis.title = element_text(size = 10),
    axis.text = element_text(size = 9)
  )


################################################################################
##### VIII. Exporting outputs
################################################################################

# Creating output directory
dir.create(
  path         = output_directory,
  recursive    = TRUE,
  showWarnings = FALSE
)

# Creating the directory for the dissertation figure
dir.create(
  path         = bcr_plot_directory,
  recursive    = TRUE,
  showWarnings = FALSE
)

# Saving the compensating variation table as Parquet file
write_parquet(
  x    = compensating_variation,
  sink = compensating_variation_output_file
)

# Saving the benefit-cost ratio grid as Parquet file
write_parquet(
  x    = benefit_cost_ratio,
  sink = benefit_cost_output_file
)

# Saving Figure 17 at its original 2520 x 1320 pixel resolution
ggsave(
  filename = bcr_plot_output_file,
  plot     = bcr_plot,
  width    = 8.4,
  height   = 4.4,
  units    = "in",
  dpi      = 300,
  bg       = "white"
)
