# Debug the complete CF flow to understand duplicate issue
library(tidyverse)
library(here)

source(file.path(here(), "kaist/config.R"))

# Load data files
load(file.path(here(), "data/cf_gcam_v7.0.rda"))
load(file.path(here(), "data/cf_rgn_v7.0.rda"))

cat("========== Step 1: tmp1 from cf_gcam ==========\n")
# Simulate tmp1 creation (line 4768-4774)
tmp1 <- cf_gcam_v7.0 %>%
  select(technology, cf = `2100`) %>%
  mutate(region = "USA", vintage = 2025) %>%
  tidyr::complete(tidyr::nesting(technology, cf),
                  vintage = seq(2025, 2100, by = 5),
                  region = c("South Korea"))  # Simplified

tmp1 %>%
  filter(grepl("^wind$", technology)) %>%
  select(technology, region, vintage, cf) %>%
  print()

cat("\n========== Step 2: tmp2 from cf_rgn ==========\n")
# Simulate tmp2 creation (line 4776-4777)
tmp2 <- cf_rgn_v7.0 %>%
  filter(region == "South Korea", grepl("^wind$", stub.technology)) %>%
  select(region, technology = stub.technology, vintage = year, cf.rgn = capacity.factor)

print(tmp2)

cat("\n========== Step 3: After left_join and replace ==========\n")
# Simulate the left_join and replace (line 4787-4791)
step3 <- tmp1 %>%
  filter(grepl("^wind$", technology)) %>%
  left_join(tmp2, by = c("technology", "vintage", "region")) %>%
  mutate(cf = replace(cf, !is.na(cf.rgn), cf.rgn[!is.na(cf.rgn)]))

step3 %>% select(technology, region, vintage, cf, cf.rgn) %>% print()

cat("\n========== Step 4: Simulate cf_iea ==========\n")
# cf_iea has historical CF expanded to all vintages (line 4738-4744)
# Let's assume cf_iea for wind is around 0.25 (global average)
cf_iea_simulated <- tibble(
  technology = "wind",
  cf = 0.08,  # Testing with a lower value to see effect
  vintage = c(1990, 1995, 2000, 2005, 2010, 2015, 2020, 2025, 2030, 2035, 2040, 2045, 2050),
  region = "South Korea"
)

cat("Simulated cf_iea (assuming global avg CF = 0.08):\n")
print(cf_iea_simulated)

cat("\n========== Step 5: After bind_rows ==========\n")
# Simulate bind_rows (line 4793)
step5 <- bind_rows(step3, cf_iea_simulated)

step5 %>%
  filter(grepl("^wind$", technology), vintage %in% c(2025, 2030, 2035)) %>%
  select(technology, region, vintage, cf) %>%
  arrange(vintage, cf) %>%
  print()

cat("\nNotice: vintage 2030 appears TWICE with different CF values!\n")

cat("\n========== Step 6: After approx_fun (the bug) ==========\n")
# Define approx_fun
approx_fun <- function(year, value, rule = 1) {
  stats::approx(as.vector(year), value, rule = rule, xout = year)$y
}

# This is what causes the averaging of duplicates
step6 <- step5 %>%
  filter(grepl("^wind$", technology)) %>%
  tidyr::complete(tidyr::nesting(technology, region),
                  vintage = sort(c(1990, 1995, 2000, 2005, 2010, 2015, 2020, 2025, 2030, 2035, 2040, 2045, 2050))) %>%
  group_by(technology, region) %>%
  mutate(cf_final = approx_fun(vintage, cf, rule = 2)) %>%
  ungroup()

cat("After approx_fun - see how CF for 2030 becomes averaged:\n")
step6 %>%
  filter(vintage %in% c(2025, 2030, 2035)) %>%
  select(technology, region, vintage, cf, cf_final) %>%
  distinct(vintage, .keep_all = TRUE) %>%
  print()

cat("\n========== Summary ==========\n")
cat("cf_rgn for wind South Korea: 0.23\n")
cat("cf_iea simulated (global avg): 0.08\n")
cat("After approx_fun averaging: (0.23 + 0.08) / 2 =", (0.23 + 0.08) / 2, "\n")
cat("\nThis explains why Auto CF (~0.15) is lower than configured CF (0.23)!\n")
