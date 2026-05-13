# Debug script to understand CF calculation issue
library(tidyverse)
library(here)

# Test what happens with duplicate vintage entries in approx_fun

# Simulate the scenario:
# After bind_rows, we have duplicate entries for wind, South Korea, 2030
test_data <- tibble(
  technology = "wind",
  region = "South Korea",
  vintage = c(2025, 2030, 2035, 2030),  # 2030 appears twice!
  cf = c(0.23, 0.23, 0.23, 0.15)  # cf_rgn=0.23, cf_iea=0.15 for 2030
)

cat("Test data (simulating bind_rows with duplicates):\n")
print(test_data)

# This is what gcamreport does:
approx_fun <- function(year, value, rule = 1) {
  if (rule == 1 | rule == 2) {
    res <- tryCatch(
      {
        stats::approx(as.vector(year), value, rule = rule, xout = year)$y
      },
      error = function(e) {
        message("An error occured: ", conditionMessage(e))
        return(NA)
      }
    )
  }
  return(res)
}

result <- test_data %>%
  group_by(technology, region) %>%
  mutate(cf_interpolated = approx_fun(vintage, cf, rule = 2)) %>%
  ungroup()

cat("\nAfter approx_fun:\n")
print(result)

cat("\n\nActual stats::approx behavior with duplicates:\n")
x <- c(2025, 2030, 2035, 2030)  # duplicate 2030
y <- c(0.23, 0.23, 0.23, 0.15)  # different values

cat("Input x (vintages):", x, "\n")
cat("Input y (cf values):", y, "\n")

# stats::approx requires sorted, unique x values
# When there are duplicates, it may take the first occurrence or fail
tryCatch({
  result_approx <- stats::approx(x, y, xout = c(2025, 2030, 2035), rule = 2)
  cat("approx output for 2030:", result_approx$y[2], "\n")
}, error = function(e) {
  cat("Error:", conditionMessage(e), "\n")
})

# Test with sorted data
cat("\n\nWith sorted and averaged duplicates:\n")
sorted_data <- tibble(vintage = x, cf = y) %>%
  group_by(vintage) %>%
  summarise(cf = mean(cf)) %>%  # average duplicates
  arrange(vintage)
print(sorted_data)

result_approx2 <- stats::approx(sorted_data$vintage, sorted_data$cf,
                                 xout = c(2025, 2030, 2035), rule = 2)
cat("approx output for 2030 (averaged):", result_approx2$y[2], "\n")
