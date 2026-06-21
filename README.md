# Quasi-Experimental Causal Inference: When Randomisation Breaks

A companion to the A/B testing project. Here a marketplace feature **cannot** be A/B tested cleanly, so the effect is recovered with **difference-in-differences (DiD)** instead. As with the A/B project, the data is synthetic with a **known true effect**, so we can check whether the method recovers it, and show that the obvious naive comparisons do not.

## The problem

A recommendation change creates **interference**. A treated user's behaviour shifts which restaurants and delivery slots are available to other users, so a user-level A/B split would contaminate the control group (a SUTVA violation). The pragmatic answer is to roll the feature out **city by city** and compare cities over time.

But the cities weren't randomised. Treated cities were chosen, and conversion drifts over time for everyone. Those two facts break the naive comparisons in opposite directions.

## The core result

The true effect baked into the simulation is **+2.0pp**. The project shows three ways to estimate it, two of which are fooled:

| Estimator | What it compares | Result | Why it's wrong / right |
|---|---|---|---|
| Naive cross-section | Treated vs control cities, after rollout | **~+4.6pp** | Biased: treated cities were already higher before the feature existed |
| Naive pre/post | Treated cities, before vs after | **~+3.2pp** | Biased: conversion was trending up for everyone anyway |
| **Difference-in-differences** | Treated change minus control change | **~+1.9pp** | Differences out both the city gap and the time trend, recovering the truth |

The intuition: the control cities' before-to-after change tells you what would have happened to the treated cities without the feature. DiD is just "treated change minus that counterfactual." Each naive estimator forgets one of the two things that were changing.

## Validating the assumption

DiD is only valid if the two groups would have moved in parallel absent the feature (the parallel-trends assumption). The project tests this with an **event study**, estimating the treated-vs-control gap week by week relative to rollout. Coefficients sit flat near zero before rollout (supporting parallel trends), then step up by about 2pp after. The plot is saved to `outputs/event_study.png`.

## Methods used

- 2x2 difference-in-differences (group means) for intuition
- Two-way fixed-effects DiD (`fixest::feols`) absorbing **city and week fixed effects**, with **standard errors clustered by city** (the level at which treatment is assigned)
- Event-study / dynamic-effects specification to test parallel trends

## Repository structure

```text
did-causal-inference-r/
├── README.md
├── R/
│   ├── 01_simulate_rollout.R   # synthetic geo rollout with confounding + known effect
│   └── 02_naive_vs_did.R       # naive estimators, FE-DiD with clustered SEs, event study
└── outputs/
    ├── did_estimates.csv            # the three estimators side by side
    ├── did_model.csv                # fixed-effects DiD coefficient (pp)
    ├── event_study.png              # parallel-trends check (fixest iplot, rate scale)
    ├── event_study_ggplot.png       # same, percentage-point axis
    └── event_study_coefficients.csv
```

## How to run

```r
source("R/01_simulate_rollout.R")
source("R/02_naive_vs_did.R")
```

Requires `tidyverse`, `broom`, and `fixest`.

## Honest limitations

- Parallel trends is an assumption, not a fact. The event study makes it checkable in the pre-period but cannot prove it would have held afterwards.
- This rollout switches all treated cities on at the same time. With staggered adoption, classic two-way fixed-effects DiD can be biased by negative weighting across cohorts; a modern estimator (Callaway and Sant'Anna, or Sun and Abraham) should be used instead. The code flags this.
- With only 20 clusters, clustered standard errors are somewhat conservative. Appropriate here, but worth noting.
- The data is synthetic. The known designed effect is what lets the pipeline validate that DiD recovers the truth where naive estimates fail.
