# Create tiles from a DuckDB SQL query (requires duckdb feature)

Create tiles from a DuckDB SQL query (requires duckdb feature)

## Usage

``` r
rust_freestile_duckdb_query(
  sql,
  db_path,
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
  quiet,
  streaming_mode
)
```

## Arguments

- sql:

  SQL query that returns a geometry column

- db_path:

  Path to DuckDB database (empty string = in-memory)

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

- streaming_mode:

  "auto", "always", or "never"
