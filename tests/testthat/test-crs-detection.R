# CRS detection and the R DuckDB fallback for GeoParquet inputs.
#
# Fixtures (tests/testthat/data/):
#   - atlanta.parquet      GeoParquet 2.0 (native GEOMETRY)
#   - atlanta.v1.1.parquet GeoParquet 1.1 (WKB + 'geo' metadata)
# Both are EPSG:4326.

# Skip unless DuckDB, its R bindings, and the spatial extension are usable.
.skip_if_no_duckdb_spatial <- function() {
  skip_on_cran()
  skip_if_not_installed("duckdb")
  skip_if_not_installed("DBI")
  ok <- tryCatch({
    con <- DBI::dbConnect(duckdb::duckdb())
    on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
    DBI::dbExecute(con, "INSTALL spatial; LOAD spatial;")
    TRUE
  }, error = function(e) FALSE)
  if (!isTRUE(ok)) skip("DuckDB spatial extension unavailable")
}

test_that(".duckdb_detect_file_crs resolves WGS84 for GeoParquet 1.1 and 2.0", {
  .skip_if_no_duckdb_spatial()

  f20 <- test_path("data", "atlanta.parquet")
  f11 <- test_path("data", "atlanta.v1.1.parquet")

  expect_equal(freestiler:::.duckdb_detect_file_crs(f20), "EPSG:4326")
  expect_equal(freestiler:::.duckdb_detect_file_crs(f11), "EPSG:4326")
})

test_that("freestile_file (duckdb engine, R backend) tiles GeoParquet 1.1 and 2.0", {
  .skip_if_no_duckdb_spatial()
  skip_if_not_installed("sf")

  old <- options(freestiler.duckdb_backend = "r")
  on.exit(options(old), add = TRUE)

  fixtures <- c(
    test_path("data", "atlanta.parquet"),
    test_path("data", "atlanta.v1.1.parquet")
  )

  for (f in fixtures) {
    out <- tempfile(fileext = ".pmtiles")
    result <- freestile_file(
      f, out,
      engine = "duckdb", layer_name = "parcels", tile_format = "mlt",
      min_zoom = 8L, max_zoom = 12L, quiet = TRUE
    )
    expect_true(file.exists(out))
    expect_gt(file.info(out)$size, 0)
    unlink(out)
  }
})
