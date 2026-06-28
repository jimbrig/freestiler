# freestiler <a href="https://walker-data.com/freestiler/"><img src="man/figures/logo.png" align="right" height="139" alt="freestiler logo" /></a>

<!-- badges: start -->
[![R Package](https://github.com/jimbrig/freestiler/actions/workflows/r-package.yml/badge.svg)](https://github.com/jimbrig/freestiler/actions/workflows/r-package.yml)
[![R-universe version](https://jimbrig.r-universe.dev/freestiler/badges/version)](https://jimbrig.r-universe.dev/freestiler)
[![pages-build-deployment](https://github.com/jimbrig/freestiler/actions/workflows/pages/pages-build-deployment/badge.svg)](https://github.com/jimbrig/freestiler/actions/workflows/pages/pages-build-deployment)
<!-- badges: end -->

**freestiler** creates [PMTiles](https://github.com/protomaps/PMTiles) vector tilesets from R. Give it an sf object, a file on disk, or a DuckDB SQL query, and it writes a single `.pmtiles` file you can serve from anywhere. The tiling engine is written in Rust and runs in-process, so there's nothing else to install.

## About this fork

This is an R-only fork of [walkerke/freestiler](https://github.com/walkerke/freestiler). It tracks upstream's R package and API, with one deliberate difference: native builds **always statically compile both Rust backends into the package**:

- **Rust DuckDB** (`duckdb-rs`, bundled) — powers `freestile_query()` and the `engine = "duckdb"` file reader, enabling out-of-R-memory, file-to-file and SQL-to-tiles workflows.
- **GeoParquet** (native Rust reader) — powers direct `.parquet` tiling via `freestile_file()`.

Upstream ships these off by default on Windows; here they are always on, including on Windows (built with the Rtools45 GNU/UCRT toolchain). Because DuckDB is statically linked, the result is a single self-contained DLL with **no external runtime dependencies** — once installed, `library(freestiler)` gives you the full feature set with no PATH or runtime setup. Python packaging is intentionally not part of this fork.

## Installation

This fork is Windows-focused and always compiles the Rust GeoParquet and DuckDB
backends in. Install it from GitHub with [pak](https://pak.r-lib.org):

```r
# install.packages("pak")
pak::pak("jimbrig/freestiler")
```

From a local clone of this repo:

```r
pak::local_install()
```

Once an r-universe binary has built, you can install it without a Rust
toolchain:

```r
install.packages(
  "freestiler",
  repos = c("https://jimbrig.r-universe.dev", "https://cloud.r-project.org")
)
```

> The upstream package (Rust DuckDB off by default on Windows) is on
> [CRAN](https://cran.r-project.org/package=freestiler) and
> [walkerke.r-universe.dev](https://walkerke.r-universe.dev).

### Verifying the Rust backends

```r
library(freestiler)
freestiler:::.has_rust_duckdb()
freestiler:::.has_rust_geoparquet()
```

### Building from source (maintainers)

`install.R` and `build.R` are convenience scripts for source builds. They locate
Rtools via `pkgbuild`, isolate the build from any personal `~/.R/Makevars`, and
verify both Rust backends are compiled in:

- `source("install.R")` — install into your normal library
- `source("build.R")` — install into an isolated `build/library/` for testing

`tools/feature-smoke.R` runs the same feature checks used in CI.

## Quick start

The main function is `freestile()`. Let's tile the North Carolina counties dataset that ships with sf:

```r
library(sf)
library(freestiler)

nc <- st_read(system.file("shape/nc.shp", package = "sf"))

freestile(nc, "nc_counties.pmtiles", layer_name = "counties")
```

That's useful for checking your installation, but the same API handles much bigger data. Here we tile all 242,000 US block groups from [tigris](https://github.com/walkerke/tigris):

```r
library(tigris)
options(tigris_use_cache = TRUE)

bgs <- block_groups(cb = TRUE)

freestile(
  bgs,
  "us_bgs.pmtiles",
  layer_name = "bgs",
  min_zoom = 4,
  max_zoom = 12
)
```

## Viewing tiles

The quickest way to view a tileset is `view_tiles()`, which starts a local server and opens an interactive map:

```r
view_tiles("us_bgs.pmtiles")
```

For more control, use `serve_tiles()` to start a local server and build your map with [mapgl](https://walker-data.com/mapgl/):

```r
library(mapgl)

serve_tiles("us_bgs.pmtiles")

maplibre(hash = TRUE) |>
  add_pmtiles_source(
    id = "bgs-src",
    url = "http://localhost:8080/us_bgs.pmtiles",
    promote_id = "GEOID"
  ) |>
  add_fill_layer(
    id = "bgs-fill",
    source = "bgs-src",
    source_layer = "bgs",
    fill_color = "navy",
    fill_opacity = 0.5,
    hover_options = list(
      fill_color = "#ffffcc",
      fill_opacity = 0.9
    )
  )
```

The built-in server handles CORS and range requests automatically. For tilesets larger than ~1 GB, use an external server like `npx http-server /path --cors -c-1` for better performance. See the [Mapping with mapgl](https://walker-data.com/freestiler/articles/mapping.html) article for a full walkthrough.

## DuckDB queries

If your data lives in DuckDB, `freestile_query()` lets you filter, join, and transform with SQL before tiling:

```r
freestile_query(
  query = "SELECT * FROM read_parquet('blocks.parquet') WHERE state = 'NC'",
  output = "nc_blocks.pmtiles",
  layer_name = "blocks"
)
```

For very large point datasets, the streaming pipeline avoids loading the full result into memory. On a recent run, `freestile_query()` streamed 146 million US job points from DuckDB into a 2.3 GB PMTiles archive in about 12 minutes:

```r
freestile_query(
  query = "SELECT naics, state, ST_Point(lon, lat) AS geometry FROM jobs_dots",
  output = "us_jobs_dots.pmtiles",
  db_path = db_path,
  layer_name = "jobs",
  tile_format = "mvt",
  min_zoom = 4,
  max_zoom = 14,
  base_zoom = 14,
  drop_rate = 2.5,
  source_crs = "EPSG:4326",
  streaming = "always",
  overwrite = TRUE
)
```

## Direct file input

You can tile spatial files without loading them into R first:

```r
# GeoParquet
freestile_file("census_blocks.parquet", "blocks.pmtiles")

# GeoPackage, Shapefile, or other formats via DuckDB
freestile_file("counties.gpkg", "counties.pmtiles", engine = "duckdb")
```

For GeoParquet, the direct file path is powered by the Rust `geoparquet`
backend, which this fork always compiles in. `freestile_file()` reads
WKB-based GeoParquet directly without materializing the data in the R session
first.

## Dynamic hexagonal binning

For dense point datasets, `freestile_h3()` aggregates points into H3 hexagons at zoom-appropriate resolutions: low zooms show coarse hexes summarizing whole regions, intermediate zooms show progressively finer hexes, and `base_zoom` and above reveal the underlying points. Aggregation rules are user-defined SQL (`COUNT(*)`, `SUM(pop)`, `AVG(value)`, ...).

```r
freestile_h3(
  pts,
  "wind.pmtiles",
  agg = c(n = "COUNT(*)", total_mw = "SUM(capacity_mw)"),
  min_zoom = 2, max_zoom = 12, base_zoom = 10
)

view_h3_tiles("wind.pmtiles", agg_column = "n")
```

Pass `fade = TRUE` to cross-fade between resolutions instead of swapping cleanly. Requires DuckDB and its [H3 community extension](https://duckdb.org/community_extensions/extensions/h3); see the [Hexagonal binning with H3](https://walker-data.com/freestiler/articles/h3-hexagonal-binning.html) article.

## Multi-layer tilesets

```r
pts <- st_centroid(nc)

freestile(
  list(
    counties = freestile_layer(nc, min_zoom = 0, max_zoom = 10),
    centroids = freestile_layer(pts, min_zoom = 6, max_zoom = 14)
  ),
  "nc_layers.pmtiles"
)
```

## Tile formats

freestiler defaults to [Mapbox Vector Tiles (MVT)](https://github.com/mapbox/vector-tile-spec), the widely-supported protobuf format that works with both MapLibre GL JS and Mapbox GL JS. The experimental [MapLibre Tiles (MLT)](https://github.com/maplibre/maplibre-tile-spec) format is also available via `tile_format = "mlt"` and can produce smaller files for polygon and line data.

## Learn more

- [Getting Started](https://walker-data.com/freestiler/articles/getting-started.html) - full tutorial
- [Mapping with mapgl](https://walker-data.com/freestiler/articles/mapping.html) - viewing and styling tiles with mapgl
- [MapLibre Tiles (MLT)](https://walker-data.com/freestiler/articles/maplibre-tiles.html) - MLT vs MVT and when to use each
