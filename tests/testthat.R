# tests/testthat.R
require(testthat)
require(here)

# Set up the environment (Mocking the API key if missing for local runs)
if (Sys.getenv("YT_API_KEY") == "") {
  message("⚠️  No API Key found; skipping live contract tests.")
}

message("\n🚀 Starting ETL Pipeline Test Suite...")
message("=========================================")

# Run tests using the 'Summary' reporter
# This gives you the 'Progress bar' and a final table of results
results <- test_dir(
  path = here("tests", "testthat"),
  reporter = "summary",
  stop_on_failure = FALSE # We want the full report even if one fails
)

# Convert results to a data frame for a custom summary table
res_df <- as.data.frame(results)

message("\n=========================================")
message("📊 TEST SUMMARY REPORT")
message("=========================================")
message(sprintf("✅ Passed:  %d", sum(res_df$passed)))
message(sprintf("❌ Failed:  %d", sum(res_df$failed)))
message(sprintf("⚠️  Skipped: %d", sum(res_df$skipped)))
message("=========================================")

# Exit with an error code if any tests failed (Crucial for GitHub Actions)
if (sum(res_df$failed) > 0) {
  message("🚨 Build Failed: Review the errors above.")
  quit(status = 1)
} else {
  message("🎉 All systems go! Ready for deployment.")
  quit(status = 0)
}
