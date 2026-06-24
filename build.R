# Build freestiler from source on Windows with the Rust GeoParquet + DuckDB
# backends compiled in.
#
# This build is deliberately isolated from the user environment. In particular
# it ignores ~/.R/Makevars[.win]: that file sets `PKG_LIBS = -L... -lgdal` for
# building GDAL-linked packages (sf/terra), and a user-level `PKG_LIBS`
# *replaces* the package's own `PKG_LIBS` during linking, which drops
# `-lfreestiler` and breaks the final DLL link (undefined reference to
# `R_init_freestiler_extendr`). Pointing R_MAKEVARS_USER at an empty file makes
# the package's generated src/Makevars.win authoritative again.
#
# The only thing inherited from the local setup is the rtools45 GNU toolchain,
# which Cargo needs for the x86_64-pc-windows-gnu target.

stopifnot(requireNamespace("withr", quietly = TRUE))

# --- rtools45 GNU toolchain (for the windows-gnu Rust target) ----------------
rtools_bins <- Filter(dir.exists, c(
  "C:/rtools45/x86_64-w64-mingw32.static.posix/bin",
  "C:/rtools45/usr/bin"
))

# --- target library ----------------------------------------------------------
# Installed into a project-local library under build/ (kept separate from the
# user library so the r-universe install is never clobbered and DLL locks are
# avoided). Override with FREESTILER_LIB. This folder already holds the
# resolved dependency tree (sf, DBI, ...) from prior builds.
lib <- Sys.getenv("FREESTILER_LIB", unset = file.path("build", "r-lib-zstd-r46"))
dir.create(lib, recursive = TRUE, showWarnings = FALSE)

# --- empty user Makevars => full isolation from ~/.R/Makevars ----------------
empty_makevars <- tempfile(fileext = ".mk")
file.create(empty_makevars)

withr::with_envvar(
  c(
    R_MAKEVARS_USER = empty_makevars,
    PATH = paste(c(rtools_bins, Sys.getenv("PATH")), collapse = .Platform$path.sep),
    NOT_CRAN = "true",
    FREESTILER_GEOPARQUET = "true",
    FREESTILER_DUCKDB = "true"
  ),
  {
    install.packages(
      ".",
      repos = NULL,
      type = "source",
      lib = lib,
      INSTALL_opts = c("--no-multiarch")
    )
  }
)

# --- verify the Rust backends are compiled in --------------------------------
withr::with_libpaths(lib, {
  loadNamespace("freestiler")
  cli <- requireNamespace("cli", quietly = TRUE)
  has_rust <- freestiler:::.has_rust_duckdb()
  msg <- sprintf("Rust DuckDB backend compiled in: %s", has_rust)
  if (cli) cli::cli_alert_info(msg) else message(msg)
})

# Force the Rust backend so any fallback to the R duckdb package errors loudly.
options(freestiler.duckdb_backend = "rust")
