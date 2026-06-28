# Build freestiler from source on Windows with the Rust GeoParquet + DuckDB
# backends compiled in.
#
# This build is deliberately isolated from the user environment. Any personal
# ~/.R/Makevars[.win] that defines `PKG_LIBS` (e.g. a global `-lgdal` for
# building sf/terra from source) is read after, and *replaces*, the package's
# own `PKG_LIBS` during linking, which drops `-lfreestiler` and breaks the final
# DLL link (undefined reference to `R_init_freestiler_extendr`). Pointing
# R_MAKEVARS_USER at an empty file makes the package's generated src/Makevars.win
# authoritative again, regardless of what the user has configured.
#
# The Rtools GNU toolchain (which Cargo needs for the x86_64-pc-windows-gnu
# target) is located via pkgbuild::with_build_tools(), so it works regardless of
# where Rtools is installed (C:, D:, or a custom location) rather than assuming a
# fixed C:/rtools45 path.

stopifnot(
  requireNamespace("withr", quietly = TRUE),
  requireNamespace("pkgbuild", quietly = TRUE)
)

# --- target library ----------------------------------------------------------
# Installed into a project-local library under build/ (kept separate from the
# user library so an existing install is never clobbered and DLL locks are
# avoided). Override with FREESTILER_LIB. This folder already holds the
# resolved dependency tree (sf, DBI, ...) from prior builds.
lib <- Sys.getenv("FREESTILER_LIB", unset = file.path("build", "library"))
dir.create(lib, recursive = TRUE, showWarnings = FALSE)

# --- empty user Makevars => full isolation from ~/.R/Makevars ----------------
empty_makevars <- tempfile(fileext = ".mk")
file.create(empty_makevars)

withr::with_envvar(
  c(
    R_MAKEVARS_USER = empty_makevars,
    NOT_CRAN = "true"
  ),
  pkgbuild::with_build_tools(
    install.packages(
      ".",
      repos = NULL,
      type = "source",
      lib = lib,
      INSTALL_opts = c("--no-multiarch")
    ),
    required = TRUE
  )
)

# --- verify the Rust backends are compiled in --------------------------------
withr::with_libpaths(lib, {
  loadNamespace("freestiler")
  cli <- requireNamespace("cli", quietly = TRUE)
  has_rust <- freestiler:::.has_rust_duckdb()
  has_geoparquet <- freestiler:::.has_rust_geoparquet()

  rust_msg <- sprintf("Rust DuckDB backend compiled in: %s", has_rust)
  geo_msg <- sprintf("GeoParquet feature compiled in: %s", has_geoparquet)
  if (cli) {
    cli::cli_alert_info(rust_msg)
    cli::cli_alert_info(geo_msg)
  } else {
    message(rust_msg)
    message(geo_msg)
  }

  if (!isTRUE(has_rust) || !isTRUE(has_geoparquet)) {
    stop(
      "Feature-enabled build is missing required Rust capabilities. ",
      "Expected both DuckDB and GeoParquet to be compiled in.",
      call. = FALSE
    )
  }
})

# Force the Rust backend so any fallback to the R duckdb package errors loudly.
options(freestiler.duckdb_backend = "rust")
