# Product gaps (public planning)

Notes on what freestiler (as a PMTiles encoder) does not yet cover in a full
spatial-data → map pipeline. No private paths or machine-specific layouts.

## What freestiler owns today

- In-process Rust encode: clip / simplify / drop / cluster / coalesce → MVT or MLT
- Write PMTiles archives from `sf`, GeoParquet, DuckDB SQL (streaming points)
- Thin local HTTP for archives (`serve_tiles`) and quick mapgl previews

## Gaps that show up in real SDI work

1. **Ingest parity** — Multi-layer and per-layer encode options are uneven between
   in-memory (`sf`) and file/query paths. Large workflows need path/SQL layer
   specs without materializing everything in R.
2. **Cartographic defaults** — Untuned encodes (no `drop_rate`, generous zooms)
   produce oversized tilesets that are slow or unusable in browsers. Tippecanoe-
   / tylertoo-class “recipe” discipline is not packaged as a first-class object.
3. **Intermediates** — Optional overview ladders (`geo:overviews` GeoParquet as
   used by tylertoo) sit between raw features and PMTiles; freestiler goes
   straight to tiles.
4. **Metadata contracts** — PMTiles metadata exists; rich TileJSON / field docs /
   style skeletons for MapLibre clients are incomplete as a product surface.
5. **Style and map packaging** — Encoding stops at the archive. Constructing a
   valid MapLibre style (sources, `source-layer`, paint/layout) is left to
   mapgl hand-wiring, YAML map tools, or other packages. Spec-layer style
   object models (MapLibre v8 JSON) are a separate concern from tiling.
6. **Serving** — Static archive HTTP ≠ dynamic `{z}/{x}/{y}` from DuckDB/GeoParquet.
7. **Provenance / diagnostics** — Measuring inputs (CRS, geometry types, zoom fit,
   size estimates) before encode is mostly ad hoc.

## Ecosystem consumers (do not reimplement)

| Consumer | Role relative to freestiler |
|----------|----------------------------|
| [mapgl](https://github.com/walkerke/mapgl) | R MapLibre client; primary preview path today |
| [maplibre-yaml](https://docs.maplibre-yaml.org/) | Declarative MapLibre maps from YAML; good target for emitted TileJSON/style skeletons |
| [tylertoo](https://github.com/geoparquet-io/tylertoo) | GeoParquet → overviews → PMTiles; bounded-memory reference |
| [Martin](https://maplibre.org/martin/) | Production tile server (PostGIS/PMTiles/…); complementary, not a goal to clone |

## Sequencing reminder

Core/library capability first (ingest parity, memory, recipes/metadata), then
CLI and thin R bindings, then dynamic serve and richer map packaging.
