# Install freestiler into the active user library (.libPaths()[1]) via pak, with
# the Rust GeoParquet + DuckDB backends compiled in.
#
# Unlike build.R (which installs into an isolated build/library for testing),
# this installs the package where library(freestiler) finds it normally.
#
# Robustness: this is hardened against ANY personal ~/.R/Makevars[.win]. A
# user-level `PKG_LIBS = ...` is read after the package's own Makevars and
# *replaces* it, which would drop `-lfreestiler` and break the final DLL link
# (undefined reference to `R_init_freestiler_extendr`). Pointing R_MAKEVARS_USER
# at an empty file makes the package's generated src/Makevars.win authoritative
# regardless of the user's environment. This can only be done at the install
# invocation, not in package source, so we do it here.
#
# Run in a fresh session (e.g. `Rscript install.R`) so freestiler is not already
# loaded/locked in the target library.

stopifnot(
  requireNamespace("pak", quietly = TRUE),
  requireNamespace("withr", quietly = TRUE),
  requireNamespace("pkgbuild", quietly = TRUE)
)

# --- source to install -------------------------------------------------------
# Defaults to the current package source tree; override with FREESTILER_SOURCE.
source_root <- Sys.getenv("FREESTILER_SOURCE", unset = ".")

# --- empty user Makevars => full isolation from any ~/.R/Makevars[.win] -------
empty_makevars <- tempfile(fileext = ".mk")
file.create(empty_makevars)

# The Rtools GNU toolchain is located via pkgbuild::with_build_tools(), so this
# works wherever Rtools is installed (C:, D:, or custom) instead of assuming a
# fixed C:/rtools45 path. Cargo's windows-gnu linker is resolved from PATH.
withr::with_envvar(
  c(
    R_MAKEVARS_USER = empty_makevars,
    NOT_CRAN = "true"
  ),
  pkgbuild::with_build_tools(
    pak::local_install(
      root = source_root,
      ask = FALSE,
      upgrade = FALSE
    ),
    required = TRUE
  )
)

# --- verify the Rust backends are compiled in --------------------------------
loadNamespace("freestiler")
has_rust <- freestiler:::.has_rust_duckdb()
has_geoparquet <- freestiler:::.has_rust_geoparquet()

cli <- requireNamespace("cli", quietly = TRUE)
rust_msg <- sprintf("Rust DuckDB backend compiled in: %s", has_rust)
geo_msg <- sprintf("GeoParquet backend compiled in: %s", has_geoparquet)
if (cli) {
  cli::cli_alert_info(rust_msg)
  cli::cli_alert_info(geo_msg)
} else {
  message(rust_msg)
  message(geo_msg)
}

if (!isTRUE(has_rust) || !isTRUE(has_geoparquet)) {
  stop(
    "Install completed but a required Rust capability is missing. ",
    "Expected both DuckDB and GeoParquet to be compiled in.",
    call. = FALSE
  )
}
