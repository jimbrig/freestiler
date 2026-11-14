# freestiler fork

R-oriented fork of `walkerke/freestiler` with **always-on** Rust GeoParquet +
DuckDB on native builds (including Windows). Python is not maintained here.

## purpose

- PMTiles from `sf`, files, and DuckDB SQL via `rextendr` + `src/rust` crates
- Keep Windows source builds reliable (`tools/config.R`, Rtools GNU)
- Prefer implementing capability in **`freestiler-core` first**, then thin R
  (and optionally a Rust CLI). Avoid R-only APIs that cannot be expressed in core.

## build, install, test, check

[`just`](https://github.com/casey/just) from the repo root:

| Recipe | Action |
|--------|--------|
| `just install` | `tools/install.R` → user library |
| `just build` | `tools/build.R` → `build/library/` |
| `just test` | `devtools::test()` |
| `just check` | `devtools::check()` |
| `just document` | `devtools::document()` |
| `just smoke` | feature-smoke requiring Rust DuckDB + GeoParquet |
| `just site` | local pkgdown into gitignored `docs/` |

Also: `pak::pak("jimbrig/freestiler")`, `testthat::test_file("tests/testthat/<file>.R")`.

Windows link note: `src/Makevars.win.in` must keep `-lsynchronization` for Rust
std futex APIs (`WaitOnAddress` / `WakeByAddress*`).

## docs and metadata

- `attachment::att_amend_desc()` when refreshing DESCRIPTION/NAMESPACE
- Site config: `pkgdown/_pkgdown.yml`; CI deploys to **`gh-pages`** (do not commit `docs/`)
- Planning notes: `dev/docs/` (not part of the R package tarball). Treat tracked
  notes like code: durable decisions, open questions, public URLs — never
  machine-local paths or gitignored scratch trees as the design record.

## product themes (near-term)

1. **A — API parity** — multi-layer / engines / knobs for file+query paths (core + LayeredTiler-style memory); thin R after
2. **B — recipes / diagnostics / map packaging** — encode config + TileJSON/style skeletons; docs that prove maps
3. **C — dynamic MVT/MLT** — single-tile encode from DuckDB/GeoParquet; serve surface after A

Do not invent parallel multi-layer designs when upstream `LayeredTiler` (PR stack) can be absorbed into core.

## repo guardrails

- Always-on `duckdb` + `geoparquet` in `tools/config.R` for native non-WASM builds
- Windows CI (`r-package.yml`) required; feature smoke must assert both backends
- No committed `python/`, `docs/` site output, `build/` artifacts, or `dev/references/` clones
- No CRAN submission paperwork in-tree (`cran-comments.md`); this fork is GitHub / r-universe oriented
- Do not document agent-private filesystem paths in this repository
