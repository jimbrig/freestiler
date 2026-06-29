# Create vector tiles from spatial data (multi-layer support)

Create vector tiles from spatial data (multi-layer support)

## Usage

``` r
rust_freestile(
  layers,
  output_path,
  tile_format,
  global_min_zoom,
  global_max_zoom,
  base_zoom,
  do_simplify,
  generate_ids,
  quiet,
  drop_rate,
  cluster_distance,
  cluster_maxzoom,
  do_coalesce
)
```

## Arguments

- layers:

  List of layer lists, each containing: name, geometries, geom_types,
  prop_names, prop_types, prop_char_values, prop_num_values,
  prop_int_values, prop_lgl_values, min_zoom, max_zoom

- output_path:

  Path for output .pmtiles file

- tile_format:

  "mvt" or "mlt"

- global_min_zoom:

  Minimum zoom level

- global_max_zoom:

  Maximum zoom level

- do_simplify:

  Whether to simplify geometries at lower zooms

- generate_ids:

  Whether to generate sequential feature IDs

- quiet:

  Whether to suppress progress messages

- drop_rate:

  Exponential drop rate (negative = off)

- cluster_distance:

  Pixel distance for clustering (negative = off)

- cluster_maxzoom:

  Max zoom for clustering (negative = use max_zoom - 1)

- do_coalesce:

  Whether to coalesce features with same attributes
