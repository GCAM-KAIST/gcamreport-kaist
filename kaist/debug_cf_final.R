# Final debug to show the averaging bug
library(tidyverse)

# Define approx_fun
approx_fun <- function(year, value, rule = 1) {
  tryCatch({
    stats::approx(as.vector(year), value, rule = rule, xout = year)$y
  }, error = function(e) {
    return(rep(NA, length(year)))
  })
}

cat("========== The Bug: Duplicate vintages get averaged ==========\n\n")

# Create test data simulating bind_rows result
test_data <- tibble(
  technology = "wind",
  region = "South Korea",
  vintage = c(
    # From cf_rgn replacement (step 3)
    2025, 2030, 2035, 2040, 2045, 2050,
    # From cf_iea (step 4) - SAME vintages, different CF!
    2025, 2030, 2035, 2040, 2045, 2050
  ),
  cf = c(
    # cf_rgn values (correct regional CF)
    0.23, 0.23, 0.23, 0.23, 0.23, 0.23,
    # cf_iea values (global average CF - lower)
    0.08, 0.08, 0.08, 0.08, 0.08, 0.08
  )
)

cat("After bind_rows - duplicates exist:\n")
test_data %>%
  arrange(vintage, desc(cf)) %>%
  print()

cat("\n\nAfter approx_fun (stats::approx averages duplicates):\n")
result <- test_data %>%
  group_by(technology, region) %>%
  mutate(cf_result = approx_fun(vintage, cf, rule = 2)) %>%
  ungroup() %>%
  distinct(technology, region, vintage, cf_result)

print(result)

cat("\n========== Summary ==========\n")
cat("Configured regional CF (cf_rgn): 0.23\n")
cat("Global average CF (cf_iea): 0.08\n")
cat("After approx_fun averaging: (0.23 + 0.08) / 2 =", (0.23 + 0.08) / 2, "\n\n")

cat("This is close to the observed Auto CF of ~0.152!\n")
cat("The actual cf_iea value depends on GCAM's secondary energy output,\n")
cat("but the mechanism is confirmed: duplicate vintage entries cause averaging.\n")
