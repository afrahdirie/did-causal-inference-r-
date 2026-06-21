# 01_simulate_rollout.R
# Simulate a marketplace feature rollout where clean randomisation is NOT possible.
#
# Why no A/B test? A recommendation change creates interference between users,
# restaurants and supply, so a user-level split would contaminate control. Instead
# the feature is rolled out city by city, and we recover the effect with
# difference-in-differences (DiD).
#
# The data is synthetic with a KNOWN true effect, so we can check whether DiD
# recovers it - and show that naive comparisons do not.
#
# Confounding is baked in deliberately:
#   1. Treated cities have a HIGHER baseline conversion (they were chosen, not
#      randomised) -> a naive treated-vs-control comparison is biased upward.
#   2. Conversion drifts upward over time for everyone -> a naive before-vs-after
#      comparison is biased by the time trend.
# DiD removes both because it differences out fixed city levels and common time
# shocks. Pre-period trends are parallel by construction, so DiD is identified.

library(tidyverse)

set.seed(42)

n_cities  <- 20
n_weeks   <- 24
post_start <- 13          # treated cities switch the feature on at week 13
true_effect <- 0.02       # GROUND TRUTH: +2 percentage points

cities <- tibble(
  city_id = 1:n_cities,
  treated = city_id <= 10,                                  # 10 treated, 10 control
  # Confounder 1: treated cities start higher.
  city_baseline = if_else(treated, 0.23, 0.20) + rnorm(n_cities, 0, 0.005)
)

# Common time structure: a gentle upward trend plus shared weekly shocks.
weeks <- tibble(
  week = 1:n_weeks,
  time_trend = 0.001 * (week - 1),
  week_shock = rnorm(n_weeks, 0, 0.003)
)

panel <- expand_grid(city_id = 1:n_cities, week = 1:n_weeks) %>%
  left_join(cities, by = "city_id") %>%
  left_join(weeks, by = "week") %>%
  mutate(
    post = week >= post_start,
    treated_post = treated & post,
    effect = if_else(treated_post, true_effect, 0),
    conversion_rate = city_baseline + time_trend + week_shock + effect +
      rnorm(n(), 0, 0.004),
    conversion_rate = pmin(pmax(conversion_rate, 0), 1)
  ) %>%
  select(city_id, week, treated, post, treated_post, conversion_rate)

# Quick look at the four DiD cells.
cell_means <- panel %>%
  group_by(treated, post) %>%
  summarise(mean_rate = mean(conversion_rate), .groups = "drop")

print(cell_means)

dir.create("outputs", showWarnings = FALSE)
saveRDS(panel, "outputs/rollout_panel.rds")
write_csv(panel, "outputs/rollout_panel.csv")

cat("Synthetic rollout panel saved (", n_cities, "cities x", n_weeks, "weeks).\n")
cat("True effect baked in: +", true_effect * 100, "percentage points.\n", sep = "")
