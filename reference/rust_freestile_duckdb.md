# Create tiles from a file via DuckDB spatial (requires duckdb feature)

Create tiles from a file via DuckDB spatial (requires duckdb feature)

## Usage

``` r
rust_freestile_duckdb(
  input_path,
  output_path,
  layer_name,
  tile_format,
  min_zoom,
  max_zoom,
  base_zoom,
  do_simplify,
  drop_rate,
  cluster_distance,
  cluster_maxzoom,
  do_coalesce,
  quiet
)
```

## Arguments

- input_path:

  Path to the spatial file

- output_path:

  Path for output .pmtiles file

- layer_name:

  Layer name

- tile_format:

  "mvt" or "mlt"

- min_zoom:

  Minimum zoom level

- max_zoom:

  Maximum zoom level

- base_zoom:

  Base zoom level (negative = use max_zoom)

- do_simplify:

  Whether to simplify geometries

- drop_rate:

  Exponential drop rate (negative = off)

- cluster_distance:

  Pixel distance for clustering (negative = off)

- cluster_maxzoom:

  Max zoom for clustering (negative = use max_zoom - 1)

- do_coalesce:

  Whether to coalesce features

- quiet:

  Whether to suppress progress
