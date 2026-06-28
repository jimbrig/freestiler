# freestiler fork

This fork mirrors upstream `walkerke/freestiler` for the R package while
always compiling native builds with Rust GeoParquet and Rust DuckDB enabled.

## purpose

- produce PMTiles from `sf`, file input, and DuckDB SQL
- preserve upstream architecture (`rextendr` + standalone `src/rust` crates)
- keep Windows source builds reliable
- focus on R package workflows only

## build, install, test, check

- install from github: `pak::pak("jimbrig/freestiler")`
- install from local source into the user library: `source("install.R")`
- feature-enabled isolated build (into `build/library/`): `source("build.R")`
- run tests: `devtools::test()`
- run a test file: `testthat::test_file("tests/testthat/<file>.R")`
- run package checks: `devtools::check()`

## docs and metadata

- refresh DESCRIPTION/NAMESPACE via attachment config: `attachment::att_amend_desc()`
- regenerate docs: `devtools::document()`
- build pkgdown site (if needed): `pkgdown::build_site()`

## repo guardrails

- keep `tools/config.R` aligned to always-on native `duckdb` + `geoparquet`
- avoid one-off helper APIs that diverge from upstream unless strictly needed
- keep CI centered on R package build/test/release (Windows build required)
- do not commit build artifacts under `build/` or check output under `dev/check/`
