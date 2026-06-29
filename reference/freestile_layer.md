# Create a layer specification with per-layer zoom range

Wraps an sf object with optional per-layer zoom range overrides for use
in multi-layer tile generation.

## Usage

``` r
freestile_layer(input, min_zoom = NULL, max_zoom = NULL)
```

## Arguments

- input:

  An sf data frame.

- min_zoom:

  Integer. Minimum zoom level for this layer. If NULL, uses the global
  min_zoom from
  [`freestile()`](http://docs.jimbrig.com/freestiler/reference/freestile.md).

- max_zoom:

  Integer. Maximum zoom level for this layer. If NULL, uses the global
  max_zoom from
  [`freestile()`](http://docs.jimbrig.com/freestiler/reference/freestile.md).

## Value

A freestile_layer object (list with class attribute).

## Examples

``` r
if (FALSE) { # \dontrun{
library(sf)
nc <- st_read(system.file("shape/nc.shp", package = "sf"))
roads <- st_read("roads.shp")

freestile(
  list(
    counties = freestile_layer(nc, min_zoom = 0, max_zoom = 10),
    roads = freestile_layer(roads, min_zoom = 8, max_zoom = 14)
  ),
  "layers.pmtiles"
)
} # }
```
