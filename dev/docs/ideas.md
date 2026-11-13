# Ideas/Notes & Relevant Resources

## Root-level workflow gaps (before recipes / overviews)

Encoder/API limitations. Close these before recipes or overview intermediates.
The tiling kernel already accepts `Vec<LayerData>` with per-layer zoom bands
(`engine.rs` `generate_tiles`). The holes are how R/Rust *feed* that kernel
and how much it holds in RAM.

### Multi-layer without loading `sf`

**What is actually true today**

- `rust_freestile()` takes a list of layers; `encode_tile_multilayer` writes
  several MVT/MLT layers into one tile blob; PMTiles metadata gets
  `vector_layers` with per-layer min/max zoom. Overlapping bands (states
  z0–8 and counties z3–8 in the same archive) already work.
- The only R entry that builds that list is `freestile()` →
  `.normalize_layers()`, which rejects anything that is not `sf` or
  `freestile_layer` (which still wraps `sf`).
- `parquet_to_layers` / `duckdb_file_to_layers` / `duckdb_query_to_layers`
  each return `vec![one LayerData]`. File and query wrappers never loop.

So “add multi-layer files” is not a new encoder. It is: (1) an R spec
type for path/query + zooms, (2) a Rust loop that appends `LayerData`,
(3) one `generate_pmtiles` call. Skipping R is necessary but not
sufficient: the kernel still keeps **every layer’s features** in process
at once.

**Two different “multi-layer” problems**

1. Several *sources* (states.parquet + counties.fgb + roads query) →
   several `source-layer` names in one archive.
2. Several *OGR layers inside one GPKG*. `ST_Read('x.gpkg')` is the
   default layer only. Need `ST_Read(..., layer = 'counties')` (or an
   explicit `layer` argument). Hive parquet under one name is still
   **one** tile layer, not multi-layer.

`pmtiles merge` only concatenates disjoint pyramids. Overlapping z/x/y
must be encoded together because each tile is one blob with multiple
internal layers.

**Global knobs that make naive multi-layer wrong**

`TileConfig` is process-wide: one `drop_rate`, one `cluster_*`, one
`coalesce`, one `simplification` flag. A TIGER overlay that must not
drop, next to parcels with `drop_rate ≈ 4`, cannot be expressed even
on the sf path. Per-layer encode options are part of the file API, not
a later recipe nicety.

**Memory if you only wire files into the current kernel**

Peak ≈ sum of decoded `geo_types` geometries + property vectors +
per-zoom `simplified_geoms` + `tile_map` + **all encoded tiles** in a
`Vec` until `write_pmtiles` (`generate_pmtiles` collects `all_tiles`).
Avoiding R does not avoid that. True bounded multi-layer means, for
each z/x/y, bbox-filter each source and encode that tile (needs covering
bboxes / a spatial index). Drop/cluster still want a global rank unless
you move ranking into SQL like the point streaming path.

**Recommended API shape**

Unify on a layer spec, then one writer:

- `path` or `query` (not both), optional `db_path`
- `layer_name`, `min_zoom`, `max_zoom`, optional `base_zoom` / `drop_rate`
- `engine` or auto from path
- optional OGR `layer` for GPKG

Do not special-case `freestile_file()` as the only multi-input function;
`freestile()` should accept the spec list so sf remains a small-data
escape hatch, not the multi-layer design center.

**Do not** encode each source to a temp `.pmtiles` and merge. **Do**
share one DuckDB connection across layers when several queries hit the
same hive.

### File inputs beyond GeoParquet

**Why other tools look parquet-only**

gpio/tylertoo implemented a GeoParquet reader and a Hilbert/row-group
prep story. That is product scope, not a law of tiling. DuckDB spatial
is an OGR client plus a native parquet reader.

**What this package already does**

In `file_input.rs`, non-`.parquet`/`.pq`/`.geoparquet` uses
`ST_Read(..., open_options=['FLATTEN_NESTED_ATTRIBUTES=YES'])`; parquet
uses `read_parquet()` because DuckDB’s bundled GDAL has **no Parquet
driver**. The R default is still `engine = "geoparquet"`, which always
calls `rust_freestile_file` → `parquet_to_layers`. An FGB on the default
engine fails (or, on CRS errors in the parquet engine, falls back to
`sf::st_read` of the **entire** file — the worst large-file behavior in
the package).

The R DuckDB backend (`engine = "duckdb"` when Rust DuckDB is off)
already chooses `read_parquet` vs `ST_Read`, then **loads the result
as sf** and calls `freestile()`. On this fork that path should be rare;
treat it as a footgun and warn or refuse above a size threshold.

**`engine = "auto"` recommendation**

| Source | Reader | Notes |
| --- | --- | --- |
| `.parquet` / hive glob | GeoParquet crate first; DuckDB `read_parquet` if CRS/types fail | Hive is a query (`read_parquet('dir/**/*.parquet', hive_partitioning=1)`), not `freestile_file` on a directory unless you add that |
| `.fgb`, `.gpkg`, `.shp`, `.geojson`, … | DuckDB `ST_Read` | Pass `layer=` for GPKG; do not `sf::st_read` as CRS fallback |
| Anything else | Try `ST_Read`; error with `ST_Drivers()` hint | |

**DuckDB ST_Read is not system GDAL.** Driver set is whatever the
bundled `libduckdb` was built with (OpenFileGDB vs FileGDB, etc.).
Verify on the Windows DLL with `SELECT * FROM ST_Drivers()`. `/vsicurl/`
may or may not work. Weird formats belong in a GDAL preprocess
(gdalraster → FGB/parquet) then this package, not a silent third engine
on day one.

**Parquet crate vs DuckDB parquet:** crate is WKB-oriented and currently
requires resolvable WGS84 metadata (`check_crs_is_wgs84`). DuckDB maps
GeoParquet onto `GEOMETRY` and `ST_Transform`. Native parquet spatial
types (1.1 vs 2.0) are why both should remain; auto-fallback is the
product, not picking a winner.

**Min-schema:** `ST_Read` / `SELECT *` will pull every column. For
parcels that is the difference between a viable tile and a multi-GB
attribute bomb. File API should accept `sql` or `columns=` even for
“file” inputs (artifactviewer already wraps hive as `freestile_query`).

### Bounded memory / chunk caps

**Honest accounting of this codebase**

1. **Ingest:** Arrow batches or DuckDB rows are decoded into
   `Vec<Feature>` (`geo_types` polygons). Batching at read does not cap
   peak unless you *drop* the batch after tiling it.
2. **Drop:** Hilbert/spatial indices over the full layer
   (`drop::compute_spatial_indices`). Global `drop_rate` ⇒ you need a
   total order, not a local chunk.
3. **Cluster:** precomputes `HashMap<zoom, Vec<Feature>>` for all points.
4. **Per zoom:** parallel VW simplify into another geometry vec; assign
   every feature to tiles; clip/encode.
5. **Archive:** `generate_tiles` returns `Vec<(TileCoord, bytes)>` of
   **every tile** before `write_pmtiles`. The point `streaming` path
   already spools tiles (`TileSpool`); the default path does not.
6. **Named `streaming`:** `CREATE TEMP TABLE` of **all points**, Morton
   rank in SQL, then per-zoom ordered scan. No Rust `Feature` vec, but
   DuckDB still holds O(N) points. Polygon/line rejected. No clustering.
   Auto threshold 1e6 features.

So “add a chunk size” without changing the kernel only shrinks *read
transients*, not peak. tylertoo’s bound is different: peak ≈ **largest
row group + winner tables**; pass 1 assigns levels from bboxes/sort
keys; pass 2 re-reads and writes batches; `--read-batch-size` default
8192; `--profile auto|speed|bounded` spills output Arrow IPC; export
processes partition **waves**. See
https://geoparquet-io.github.io/tylertoo/diving-deeper/bounded-memory/

**What is cheap vs hard here**

Cheap, high leverage:

- Spool encoded tiles to disk like the point pipeline (cuts peak by the
  size of the archive).
- `SET memory_limit` / threads on the DuckDB connection (caps the
  SQL engine, not Rust geometries).
- Refuse or warn on the R-sf DuckDB fallback.
- `columns=` / min-schema (often dominates bytes vs vertices).
- `engine = "auto"` so FGB never hits the parquet+sf CRS fallback.

Medium:

- Arrow `read_batch_size` on the GeoParquet crate path (already iterates
  record batches, then appends to one `Vec`).
- Point streaming for `freestile_file` on point parquet, not only query.

Hard (the real cap):

- Two-pass drop (pass 1: bbox + rank key; pass 2: reread winners) or
  SQL-side retain like Morton streaming, generalized to polygons via
  bbox + area rank.
- Per-tile bbox fetch from GeoParquet covering stats / DuckDB RTree so
  `LayerData` is never the full layer.
- Until drop/cluster are SQL- or two-pass, document **peak ≈ decoded
  layer(s) + encoded archive** and treat `memory_limit` as DuckDB-only.

**Suggested user-facing knobs (names as design, not committed API)**

- `memory_limit` — DuckDB
- `read_batch_size` — Arrow / ST_Read batching
- `spill_dir` — tile spool + optional DuckDB temp
- `streaming = "auto"|"always"|"never"` — extend beyond points
  incrementally; do not pretend polygons stream today

gpio “max bytes per chunk” maps onto `read_batch_size` plus a **hard
error** if a single feature/row-group exceeds the cap (vertex bombs),
not a silent stall.

## Make `artifactviewer`'s "tileset recipe" Concept a more robust implementation

See [dev/references/artifactviewer](../references/artifactviewer) and various example workflows related to that from its examples folder as well as throughout G:/SpatialData/catalog or G:/SpatialData/_archive as well.

## "Overviews"

See links below related to examples of overviews in tylertoo and the custom geoparquet and flatgeobuf examples also.

## GeoParquet Interoperability and Nuances

This section deals with the interoperability and current state of the GeoParquet specification and nuances relevant to its use as a possible input source format for this package and how it is read by the underlying bindings to duckdb and/or geoparquet rust crates.

For a specific in-depth look into these nuances as it relates to GDAL vs. DuckDB vs. `gpio` etc. see the symlink'd reference [here](../references/tiger) (uses TIGER as an example dataset).

The main item related to freestiler here would simply be the ability to have a more flexible GeoParuqt reader supported given the specification's current state of flux between versions 1.1 and 2.0 and how metadata and CRS information is handled and the divergence between core tooling such as GDAL's Parquet driver (which supports applying GeoParquet's 2.0 native Parquet spatial types, but not any other aspect of the 2.0 specification including the version written to the file, etc.) and how this all affects the ability to read and write GeoParquet files with a consistent and reliable API.

This may have already been resolved or addressed for the particular issue regarding the different methods that DuckDB vs. native GeoParuqet read a GeoParquet 2.0 versioned input source, as it seems like both engines work with a 2.0 input source now whereas in the past I encountered issues related to duckdb attempting to read the data and not detecting a CRS in the expected location, etc.

So this is more or less a general comment pertaining to providing optimal flexibilty of input sources that are GeoParquet and a good resource for this is how the [GPQ Workbench (geopq-workbench)](https://github.com/gsueur/geopq-workbench) Desktop application handles this and provides very flexible reading across all GeoParquet versions, encodings, etc.

See also these resources on this exact topic from GeoMermaids:

- https://www.geomermaids.com/cookbook/reading/
- https://www.geomermaids.com/cookbook/geoparquet/

and the original GeoParquet best practices:

- [Distributing GeoParquet Best Practices](https://raw.githubusercontent.com/opengeospatial/geoparquet/refs/heads/main/format-specs/distributing-geoparquet.md)

it should also be noted the GDAL specific nuance related to the CRS as well, i.e. see the output below for a 2.0 GeoParquet input source:

```powershell
➜ gdal vector info G:\SpatialData\_archive\tiger\parquet_v2.0\tl_2025_us_state.v2.parquet
INFO: Open of `G:\SpatialData\_archive\tiger\parquet_v2.0\tl_2025_us_state.v2.parquet'
      using driver `Parquet' successful.

Layer name: tl_2025_us_state.v2
Geometry: Multi Polygon
Feature Count: 49
Extent: (-671604551436814304028451120606636464366061660299656192103590393396896035589919414244307964172914637647252718864843161010117589743084309988391614614849191936.000000, -19931520357091704125079374090812266452464462356380303066054619741023361487226383938795964098567940398706898277320622080.000000) - (0.000000, -0.000000)
Layer Coordinate Reference System:
  - name: WGS 84
  - ID: EPSG:4326
  - type: Geographic 2D
  - area of use: World, west -180.00, south -90.00, east 180.00, north 90.00
Data axis to CRS axis mapping: 2,1
Geometry Column = geometry
geoid: String (0.0)
state_fips: String (0.0)
state_abbr: String (0.0)
state_name: String (0.0)
area_land_m2: Integer64 (0.0)
area_water_m2: Integer64 (0.0)
```


## Serving Tiles via HTTP

Currently the package supports serving tiles via HTTP as seen in the [R/serve.R](../../R/serve.R) file's source code which uses an `httpuv` based implementation which is somewhat limited. The other primary way I have been serving tiles locally is using `bunx http-server` called from `processx`, i.e. I added an example to [dev/examples/tiles_serve.R](../examples//tiles_serve.R). However, I recently came across this interesting library [sounkou-bioinfo/goServeR](https://github.com/sounkou-bioinfo/goServeR) which applies a sophisticated HTTP(S) File Server with range request support bakes in and unbounded CORS using `Go` and compilled C source code around the Go server. I will need to evaluate this further and see if it is a good fit for the package as there are various tradeoffs to consider, but that approach would provide the most robust support for managing the underlying HTTP server while leveraging as performant and multi-threaded implementation as possible via golang. Definitely worth considering.

Another idea would be a more complete solution (likely in addition to the more basic lightweight http file serving approach) that could use a more official `plumber2` full supporting API tile server implementation (note: `plumber2` NOT `plumber` - https://github.com/posit-dev/plumber2/).

## GDAL PMTiles Driver & `/vsipmtiles/`

See the [GDAL PMTiles Driver](https://gdal.org/en/stable/drivers/vector/pmtiles.html) (only supports MVT currently and may be limited compared to other tooling etc.) as well as the dedicated section on [the /vsipmtiles/ virtual file system](https://gdal.org/en/stable/drivers/vector/pmtiles.html#vsipmtiles-virtual-file-system).


## Resources & References

Original Core Packages by walkerke:

- https://github.com/walkerke/freestiler
- https://github.com/walkerke/pmtiles
- https://github.com/walkerke/mapgl

freestiler related:

- https://github.com/opengeos/freestiler-wasm

GeoParquet Specific:

- https://geoparquet.io/
- https://github.com/geoparquet/geoparquet-io (`gpio`)
- https://raw.githubusercontent.com/opengeospatial/geoparquet/refs/heads/main/format-specs/distributing-geoparquet.md
- https://geoparquet.geomermaids.com/
- https://www.geomermaids.com/cookbook/reading/
- https://www.geomermaids.com/cookbook/geoparquet/
- https://gdal.org/en/stable/drivers/vector/parquet.md
- https://github.com/gsueur/geopq-workbench

Vector Tilesets:

- https://geoparquet-io.github.io/tylertoo/ & https://github.com/geoparquet-io/tylertoo (assumes GeoParquet via `gpio` as inputs; uses tippecanoe logic with an overview file, has in depth docs and details about all of the nuances and technicalities around both the encodings and performance as well as the cartography involved)

- https://gdal.org/en/stable/drivers/vector/pmtiles.html

Example Implementations of "Overviews":

- https://geoparquet-io.github.io/tylertoo/diving-deeper/overview-file/
- https://github.com/yharby/geoparquet-overviews
- https://github.com/reearth/flatgeobuf-overviews

Misc:

- https://geoparquet-io.github.io/tylertoo/diving-deeper/preparing-input/
- https://geoparquet-io.github.io/tylertoo/diving-deeper/tuning-zoom/
- https://geoparquet-io.github.io/tylertoo/diving-deeper/bounded-memory/
- https://geoparquet-io.github.io/tylertoo/diving-deeper/tippecanoe/
- https://geoparquet-io.github.io/tylertoo/demo/
- https://geoparquet-io.github.io/tylertoo/architecture/

