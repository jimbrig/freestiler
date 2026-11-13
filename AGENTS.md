# freestiler fork

This fork mirrors upstream `walkerke/freestiler` for the R package while
always compiling native builds with Rust GeoParquet and Rust DuckDB enabled.
Python packaging is not part of this fork (see upstream for that).

## purpose

- produce PMTiles from `sf`, file input, and DuckDB SQL
- preserve upstream architecture (`rextendr` + standalone `src/rust` crates)
- keep Windows source builds reliable
- focus on R package workflows only

## build, install, test, check

Preferred entrypoint is [`just`](https://github.com/casey/just) from the repo root:

- `just install` — local source install into the user library (`tools/install.R`)
- `just build` — feature-enabled isolated build into `build/library/` (`tools/build.R`)
- `just test` — `devtools::test()`
- `just check` — `devtools::check()`
- `just document` — `devtools::document()`
- `just smoke` — `tools/feature-smoke.R` requiring Rust DuckDB + GeoParquet
- `just site` — local pkgdown build into gitignored `docs/`

Also:

- install from github: `pak::pak("jimbrig/freestiler")`
- run a test file: `testthat::test_file("tests/testthat/<file>.R")`

## docs and metadata

- refresh DESCRIPTION/NAMESPACE via attachment config: `attachment::att_amend_desc()`
- regenerate docs: `just document` or `devtools::document()`
- site config: `pkgdown/_pkgdown.yml`; CI deploys to the `gh-pages` branch

## repo guardrails

- keep `tools/config.R` aligned to always-on native `duckdb` + `geoparquet`
- avoid one-off helper APIs that diverge from upstream unless strictly needed
- keep CI centered on R package build/test/release (Windows build required)
- do not commit build artifacts under `build/`, site output under `docs/`, or check output under `dev/check/`
- do not commit `dev/references/` clones or the Python tree (removed from this fork)
