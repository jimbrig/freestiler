# Package index

## Tile Generation

Create PMTiles archives from spatial data

- [`freestile()`](http://docs.jimbrig.com/freestiler/reference/freestile.md)
  : Create vector tiles from spatial data
- [`freestile_file()`](http://docs.jimbrig.com/freestiler/reference/freestile_file.md)
  : Create vector tiles from a spatial file
- [`freestile_query()`](http://docs.jimbrig.com/freestiler/reference/freestile_query.md)
  : Create vector tiles from a DuckDB SQL query
- [`freestile_layer()`](http://docs.jimbrig.com/freestiler/reference/freestile_layer.md)
  : Create a layer specification with per-layer zoom range
- [`freestile_h3()`](http://docs.jimbrig.com/freestiler/reference/freestile_h3.md)
  : Create vector tiles with dynamic H3 hexagonal binning

## Viewing Tiles

Serve and view PMTiles locally

- [`serve_tiles()`](http://docs.jimbrig.com/freestiler/reference/serve_tiles.md)
  : Serve PMTiles files via local HTTP server with CORS
- [`stop_server()`](http://docs.jimbrig.com/freestiler/reference/stop_server.md)
  : Stop a local tile server
- [`view_tiles()`](http://docs.jimbrig.com/freestiler/reference/view_tiles.md)
  : Quickly view a PMTiles file on an interactive map
- [`view_h3_tiles()`](http://docs.jimbrig.com/freestiler/reference/view_h3_tiles.md)
  : View an H3 hexagonal-binning PMTiles archive
