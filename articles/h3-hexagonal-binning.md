# Dynamic hexagonal binning with H3

When a dataset has tens of thousands of points concentrated in a few
places, neither rendering every individual point nor clustering them
into a single “200,000+” badge tells you what you actually want to know.
[`freestile_h3()`](http://docs.jimbrig.com/freestiler/reference/freestile_h3.md)
aggregates points into [H3 hexagons](https://h3geo.org/) at
zoom-appropriate resolutions: low zooms show coarse hexagons summarizing
whole regions, intermediate zooms show progressively finer hexagons, and
`base_zoom` and above show the underlying points. The aggregation rule
is yours to choose — count, sum, mean, max, anything DuckDB SQL
supports.

This produces the same conceptual UX as point clustering, but with a hex
grid instead of a distance-based cluster. The resulting `.pmtiles`
archive serves identically — drop it on a static host and use
[view_h3_tiles()](#viewing) (or your own
[mapgl](https://walker-data.com/mapgl/) style) to render it.

### Requirements

[`freestile_h3()`](http://docs.jimbrig.com/freestiler/reference/freestile_h3.md)
needs:

- The `DBI` and `duckdb` R packages.
- DuckDB’s [H3 community
  extension](https://duckdb.org/community_extensions/extensions/h3). On
  first call, DuckDB downloads the extension automatically
  (`INSTALL h3 FROM community`), so you need network access the first
  time.

``` r

install.packages(c("DBI", "duckdb", "mapgl"))
```

### Your first hex tileset

Let’s tile some simulated points spread across the southeastern US.

``` r

library(freestiler)
library(sf)

set.seed(1)
pts <- st_as_sf(
  data.frame(
    x = runif(50000, -100, -80),
    y = runif(50000, 30, 45),
    capacity_mw = rnorm(50000, 100, 25)
  ),
  coords = c("x", "y"),
  crs = 4326
)

freestile_h3(
  pts,
  "demo.pmtiles",
  min_zoom = 2,
  max_zoom = 12,
  base_zoom = 10
)
```

[`freestile_h3()`](http://docs.jimbrig.com/freestiler/reference/freestile_h3.md)
writes one [MVT source-layer per H3 resolution](#layer-naming)
(`h3_r03`, `h3_r04`, …) plus a `points` source-layer for the raw data.
With the default `fade = FALSE`, those layers have **disjoint zoom
windows**, so the map cleanly swaps hexagon resolutions as you zoom and
replaces hexagons with individual points at `base_zoom`.

### Choosing aggregations

The `agg` argument controls what summary properties each hexagon
carries. The simplest case is just counting points per hex:

``` r

freestile_h3(pts, "demo.pmtiles", agg = "count")
```

For richer summaries, pass a named character vector of SQL aggregations:

``` r

freestile_h3(
  pts, "demo.pmtiles",
  agg = c(
    n        = "COUNT(*)",
    avg_mw   = "AVG(capacity_mw)",
    total_mw = "SUM(capacity_mw)"
  )
)
```

Or a named list of `c(fn, column)` if you’d rather not write SQL:

``` r

freestile_h3(
  pts, "demo.pmtiles",
  agg = list(
    n        = c("count", "*"),
    avg_mw   = c("mean", "capacity_mw"),
    total_mw = c("sum",  "capacity_mw")
  )
)
```

Supported function names: `count`, `sum`, `mean` (alias `avg`), `min`,
`max`, `median`.

### Viewing

[`view_h3_tiles()`](http://docs.jimbrig.com/freestiler/reference/view_h3_tiles.md)
reads the metadata, detects all the `h3_r*` layers + the points layer,
and builds a `mapgl` map with a consistent color scale across hex
resolutions. For first looks it accepts a quick-look default ramp; for
production maps, pass an explicit `stops`:

``` r

view_h3_tiles(
  "demo.pmtiles",
  agg_column = "n",
  stops = list(
    values = c(1, 10, 100, 1000, 10000),
    colors = viridisLite::viridis(5)
  )
)
```

The default color scale (`stops = NULL`) uses `1, 10, 100, 1000, 10000`
with the `viridis` palette — sensible for a first look, but you’ll
almost always want to derive `stops` from your data’s range for a
finished map.

### DuckDB SQL input

If your points already live in DuckDB (or a Parquet/GeoPackage/Shapefile
that DuckDB can read), skip the sf roundtrip and pass SQL directly:

``` r

freestile_h3(
  "SELECT geometry, capacity_mw FROM read_parquet('turbines.parquet')",
  "turbines.pmtiles",
  agg = c(n = "COUNT(*)", total_mw = "SUM(capacity_mw)"),
  source_crs = "EPSG:4326"
)
```

Multi-statement SQL is supported — setup statements (`INSTALL`, `LOAD`,
`CREATE VIEW`, etc.) run first, and the final `SELECT` is the input:

``` r

freestile_h3(
  paste(
    "CREATE TEMP VIEW src AS SELECT * FROM read_parquet('turbines.parquet');",
    "SELECT geometry, capacity_mw FROM src WHERE capacity_mw > 1"
  ),
  "turbines.pmtiles",
  source_crs = "EPSG:4326"
)
```

Always pass `source_crs` explicitly when your SQL returns non-WGS84
geometry. If you omit it,
[`freestile_h3()`](http://docs.jimbrig.com/freestiler/reference/freestile_h3.md)
assumes EPSG:4326 and warns once.

### Cross-fade between resolutions

By default, hexagon resolutions swap cleanly at zoom boundaries. If you
want the transitions to blend visually — coarser hexes fading out as
finer ones fade in — pass `fade = TRUE`:

``` r

freestile_h3(
  pts, "demo_fade.pmtiles",
  agg = "count",
  min_zoom = 2, max_zoom = 12, base_zoom = 10,
  fade = TRUE,        # default fade_overlap = 1
)
view_h3_tiles("demo_fade.pmtiles", agg_column = "count")
```

With `fade = TRUE`, adjacent hex layers overlap by `fade_overlap` zoom
levels.
[`view_h3_tiles()`](http://docs.jimbrig.com/freestiler/reference/view_h3_tiles.md)
detects this and emits a trapezoidal `fill_opacity` envelope for each
layer so the renderer cross-fades between resolutions.

Use a larger `fade_overlap` (e.g. `2`) for slower, more diffuse blends;
use `fade_overlap = 1` (the default) for a tight handoff.

### Layer naming

Each MVT source-layer is named `"<hex_layer_prefix>_r<resolution>"`. The
default prefix is `"h3"`, so you’ll see layer ids like `h3_r03`,
`h3_r04`, …, `h3_r09`. The raw-points layer defaults to `"points"`. You
can change either:

``` r

freestile_h3(
  pts, "demo.pmtiles",
  hex_layer_prefix = "wind",   # produces "wind_r03", "wind_r04", ...
  point_layer_name = "turbines"
)
```

### Customizing the zoom -\> H3 resolution mapping

The defaults pair each tile zoom with an H3 resolution whose hexagon
edge length roughly matches a tile pixel at that zoom. You can override
the mapping with `h3_resolutions`:

``` r

# Use only res 4 at zoom 0-3, res 6 at zoom 4-6, then points at 7+.
freestile_h3(
  pts, "demo.pmtiles",
  min_zoom = 0, max_zoom = 10, base_zoom = 7,
  h3_resolutions = c(4, 4, 4, 4, 6, 6, 6)
)
```

The override accepts:

- `NULL` — use built-in defaults
- An unnamed integer vector with one entry per hex zoom
  (`length(min_zoom:(base_zoom - 1))`), mapped positionally
- A sparse named integer vector keyed by actual zoom number; defaults
  fill the gaps

All resolutions must be integers in `0:15`. The same resolution
appearing in non-contiguous zoom runs is rejected (the resulting layer
names would collide on `h3_rNN`).

### Limitations in this release

- Points only. Polygon or line aggregations (via centroids or
  `h3_polygon_to_cells`) may come in a future release.
- `MULTIPOINT` is not handled; use `sf::st_cast(x, "POINT")` first (or
  `ST_Centroid` in SQL).
- The default
  [`view_h3_tiles()`](http://docs.jimbrig.com/freestiler/reference/view_h3_tiles.md)
  color scale is a quick-look ramp; pass `stops` explicitly for
  production maps.
