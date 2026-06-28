#!/usr/bin/env Rscript

.parse_args <- function(args) {
  out <- list(
    lib = NULL,
    require_rust_duckdb = FALSE,
    require_geoparquet = FALSE
  )

  i <- 1L
  while (i <= length(args)) {
    arg <- args[[i]]
    if (identical(arg, "--lib")) {
      if (i == length(args)) {
        stop("--lib requires a path argument", call. = FALSE)
      }
      out$lib <- args[[i + 1L]]
      i <- i + 2L
      next
    }
    if (identical(arg, "--require-rust-duckdb")) {
      out$require_rust_duckdb <- TRUE
      i <- i + 1L
      next
    }
    if (identical(arg, "--require-geoparquet")) {
      out$require_geoparquet <- TRUE
      i <- i + 1L
      next
    }
    stop(sprintf("Unknown argument: %s", arg), call. = FALSE)
  }

  out
}

.emit <- function(level, text) {
  if (requireNamespace("cli", quietly = TRUE)) {
    switch(
      level,
      info = cli::cli_alert_info(text),
      success = cli::cli_alert_success(text),
      warning = cli::cli_alert_warning(text),
      danger = cli::cli_alert_danger(text),
      message(text)
    )
  } else {
    message(sprintf("[%s] %s", toupper(level), text))
  }
}

.assert <- function(cond, msg) {
  if (!isTRUE(cond)) {
    if (requireNamespace("cli", quietly = TRUE)) {
      cli::cli_abort(msg, call = rlang::caller_env())
    } else {
      stop(msg, call. = FALSE)
    }
  }
}

.write_test_geoparquet <- function(sf_obj, path) {
  attrs <- sf::st_drop_geometry(sf_obj)
  wkb_raw <- lapply(sf::st_as_binary(sf::st_geometry(sf_obj)), unclass)
  geom_array <- arrow::Array$create(wkb_raw, type = arrow::binary())
  tbl <- do.call(arrow::arrow_table, c(as.list(attrs), list(geometry = geom_array)))
  arrow::write_parquet(tbl, path)
}

.run_geoparquet_smoke <- function() {
  if (!requireNamespace("sf", quietly = TRUE)) {
    .emit("warning", "Skipping GeoParquet smoke test: package 'sf' not installed.")
    return(invisible(FALSE))
  }
  if (!requireNamespace("arrow", quietly = TRUE)) {
    .emit("warning", "Skipping GeoParquet smoke test: package 'arrow' not installed.")
    return(invisible(FALSE))
  }

  nc <- sf::st_read(system.file("shape/nc.shp", package = "sf"), quiet = TRUE)
  parquet_path <- tempfile(fileext = ".parquet")
  output <- tempfile(fileext = ".pmtiles")
  on.exit(unlink(c(parquet_path, output), force = TRUE), add = TRUE)

  .write_test_geoparquet(nc, parquet_path)
  freestiler::freestile_file(
    input = parquet_path,
    output = output,
    layer_name = "counties",
    tile_format = "mvt",
    min_zoom = 0L,
    max_zoom = 6L,
    quiet = TRUE
  )

  .assert(file.exists(output), "GeoParquet smoke test failed: output file not created.")
  .assert(file.info(output)$size > 0L, "GeoParquet smoke test failed: output file is empty.")
  .emit("success", "GeoParquet smoke test passed.")
  invisible(TRUE)
}

.run_duckdb_smoke <- function() {
  output <- tempfile(fileext = ".pmtiles")
  on.exit(unlink(output, force = TRUE), add = TRUE)

  old <- options(freestiler.duckdb_backend = "rust")
  on.exit(options(old), add = TRUE)

  freestiler::freestile_query(
    query = paste(
      "SELECT * FROM (VALUES",
      "('a', 1, ST_Point(-78.6, 35.8)),",
      "('b', 2, ST_Point(-80.2, 36.1)),",
      "('c', 3, ST_Point(-82.5, 34.2))",
      ") AS t(label, score, geometry)"
    ),
    output = output,
    layer_name = "points",
    tile_format = "mvt",
    min_zoom = 0L,
    max_zoom = 6L,
    quiet = TRUE,
    streaming = "always"
  )

  .assert(file.exists(output), "Rust DuckDB smoke test failed: output file not created.")
  .assert(file.info(output)$size > 0L, "Rust DuckDB smoke test failed: output file is empty.")
  .emit("success", "Rust DuckDB smoke test passed.")
  invisible(TRUE)
}

cfg <- .parse_args(commandArgs(trailingOnly = TRUE))

if (!is.null(cfg$lib)) {
  lib <- normalizePath(cfg$lib, mustWork = FALSE)
  .libPaths(c(lib, .libPaths()))
  .emit("info", sprintf("Using library path: %s", lib))
}

.assert(requireNamespace("freestiler", quietly = TRUE), "Package 'freestiler' is not installed.")

has_rust_duckdb <- freestiler:::.has_rust_duckdb()
has_geoparquet <- freestiler:::.has_rust_geoparquet()

.emit("info", sprintf("Rust DuckDB available: %s", has_rust_duckdb))
.emit("info", sprintf("GeoParquet available: %s", has_geoparquet))

if (isTRUE(cfg$require_rust_duckdb)) {
  .assert(has_rust_duckdb, "Rust DuckDB feature is required but not available.")
}
if (isTRUE(cfg$require_geoparquet)) {
  .assert(has_geoparquet, "GeoParquet feature is required but not available.")
}

if (has_geoparquet) {
  .run_geoparquet_smoke()
}
if (has_rust_duckdb) {
  .run_duckdb_smoke()
}

.emit("success", "Feature smoke checks completed.")
