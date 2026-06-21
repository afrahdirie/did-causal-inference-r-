# 02_naive_vs_did.R
# Show why randomisation breaking matters: naive estimates are biased, DiD is not.
# Then validate the DiD identifying assumption (parallel trends) with an event study.

library(tidyverse)
library(broom)
library(fixest)   # fast fixed-effects regression with clustered SEs



panel <- readRDS("outputs/rollout_panel.rds")

cell <- panel %>%
  group_by(treated, post) %>%
  summarise(mean_rate = mean(conversion_rate), .groups = "drop")

get <- function(tr, po) cell$mean_rate[cell$treated == tr & cell$post == po]

# ---- Three estimators of the same effect ----
naive_cross_section <- get(TRUE, TRUE) - get(FALSE, TRUE)   # treated vs control, post only
naive_pre_post      <- get(TRUE, TRUE) - get(TRUE, FALSE)    # treated, after vs before
did_2x2             <- (get(TRUE, TRUE) - get(TRUE, FALSE)) -
  (get(FALSE, TRUE) - get(FALSE, FALSE))

estimates <- tibble(
  method = c("Naive cross-section (post only)",
             "Naive pre/post (treated only)",
             "Difference-in-differences (2x2)"),
  estimate_pp = c(naive_cross_section, naive_pre_post, did_2x2) * 100,
  note = c("biased by baseline city differences",
           "biased by the common time trend",
           "differences both out - recovers the truth")
)

cat("True effect baked into the simulation: +2.00pp\n\n")
print(estimates)

# ---- DiD as a regression with two-way fixed effects and SEs clustered by city ----
# conversion_rate ~ treated:post, absorbing city and week fixed effects.
did_model <- feols(
  conversion_rate ~ treated_post | city_id + week,
  data = panel,
  cluster = ~city_id
)

cat("\nTwo-way fixed-effects DiD (clustered by city):\n")
print(summary(did_model))

# Scale ONLY the rate-scale columns to percentage points.
# (Do not scale statistic or p.value - those are unitless.)
did_tidy <- tidy(did_model, conf.int = TRUE) %>%
  mutate(across(c(estimate, std.error, conf.low, conf.high), ~ .x * 100)) %>%
  rename_with(~ paste0(.x, "_pp"), c(estimate, std.error, conf.low, conf.high))

write_csv(estimates, "outputs/did_estimates.csv")
write_csv(did_tidy, "outputs/did_model.csv")

# ---- Parallel-trends / event study ----
# Estimate the treated-vs-control gap in each week relative to the week BEFORE
# rollout (rel_week = -1, the reference). Flat, near-zero coefficients BEFORE
# rollout support parallel trends; a jump from week 0 onward is the effect.
#
# IMPORTANT: the reference period must be passed to i() via ref = -1. fixest's i()
# does NOT use a factor's relevel(), so keep rel_week numeric and set ref here.
es_data <- panel %>%
  mutate(rel_week = week - 13)        # numeric; 0 = first treated week

event_study <- feols(
  conversion_rate ~ i(rel_week, treated, ref = -1) | city_id + week,
  data = es_data,
  cluster = ~city_id
)

# Built-in event-study plot - handles the reference period correctly.
# Note: the y-axis is on the conversion-rate scale, so 0.02 = 2pp.
png("outputs/event_study.png", width = 800, height = 500)
iplot(
  event_study,
  main = "Event study: treated vs control gap by week",
  xlab = "Weeks relative to rollout",
  ylab = "Estimated gap (conversion rate)"
)
dev.off()

# Tidy coefficients for the CSV, in percentage points, with the reference
# week shown explicitly as 0 so the baseline is visible.
es_coef <- tidy(event_study, conf.int = TRUE) %>%
  mutate(rel_week = as.integer(str_extract(term, "(?<=rel_week::)-?\\d+"))) %>%
  filter(!is.na(rel_week)) %>%
  mutate(across(c(estimate, conf.low, conf.high), ~ .x * 100)) %>%
  bind_rows(tibble(rel_week = -1, estimate = 0, conf.low = 0, conf.high = 0)) %>%
  arrange(rel_week) %>%
  select(rel_week, estimate, conf.low, conf.high)

# Optional ggplot version (percentage-point axis), saved alongside.
p <- ggplot(es_coef, aes(rel_week, estimate)) +
  geom_hline(yintercept = 0, linetype = "dashed") +
  geom_vline(xintercept = -0.5, linetype = "dotted", colour = "grey50") +
  geom_pointrange(aes(ymin = conf.low, ymax = conf.high)) +
  labs(
    title = "Event study: treated vs control gap by week",
    subtitle = "Coefficients flat near zero before week 0 (rollout) support parallel trends",
    x = "Weeks relative to rollout", y = "Estimated gap (pp)"
  ) +
  theme_bw()

ggsave("outputs/event_study_ggplot.png", p, width = 8, height = 5)
write_csv(es_coef, "outputs/event_study_coefficients.csv")

cat("\nInterpretation:\n")
cat("- The naive estimates over-state the effect; DiD recovers ~+2pp.\n")
cat("- Pre-rollout event-study coefficients sit near zero (parallel trends hold).\n")
cat("- A clear step up from week 0 onward is the treatment effect.\n")
cat("\nCaveat: this rollout switches all treated cities on at once. With STAGGERED\n")
cat("adoption, two-way fixed-effects DiD can be biased; use a modern estimator\n")
cat("(Callaway & Sant'Anna, or Sun & Abraham) instead.\n")