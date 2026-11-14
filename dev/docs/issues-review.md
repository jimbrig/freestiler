# Issues review (fork tracker)

Working notes to deepen [#2](https://github.com/jimbrig/freestiler/issues/2)–[#9](https://github.com/jimbrig/freestiler/issues/9)
with grounded code paths, upstream links, and decision context. Durable product
decisions stay in [`recipe_decisions.md`](recipe_decisions.md),
[`product-gaps.md`](product-gaps.md), and
[`.cursor/plans/tileset_pipeline_architecture_8565565c.plan.md`](../../.cursor/plans/tileset_pipeline_architecture_8565565c.plan.md).

**Status legend:** `open` = still needed · `partial` = some pieces landed ·
`blocked` = waiting on another issue · `later` = Theme B/C.

**Branch note (2026-11-14):** LayeredTiler stack (upstream PRs #31–#33) is on
`wip/layered-tiler-absorb` — affects #5 memory story and enables #3 without
peak ≈ sum-of-layers. Not on `main` until CI/R rebuild prove it.

---

## Map

| Issue | Theme | Status | Depends on |
|------:|-------|--------|------------|
| [#2](https://github.com/jimbrig/freestiler/issues/2) | A tracker | open | — |
| [#3](https://github.com/jimbrig/freestiler/issues/3) | A | open | LayeredTiler absorb (in flight) |
| [#7](https://github.com/jimbrig/freestiler/issues/7) | A | open | ideally with #3 |
| [#4](https://github.com/jimbrig/freestiler/issues/4) | A | open | — |
| [#5](https://github.com/jimbrig/freestiler/issues/5) | A tech | **partial** | spool done; rest open |
| [#6](https://github.com/jimbrig/freestiler/issues/6) | A tech | open | pairs with #4 auto |
| [#8](https://github.com/jimbrig/freestiler/issues/8) | B | blocked | #2 / #3+#7+#4 |
| [#9](https://github.com/jimbrig/freestiler/issues/9) | B conven. | later | not encoder-blocking |
| Theme C | C | **no issue yet** | open after #3/#7 |

Upstream watch (not fork issues): [walkerke#17](https://github.com/walkerke/freestiler/issues/17),
[#16](https://github.com/walkerke/freestiler/issues/16),
[#34](https://github.com/walkerke/freestiler/issues/34),
[#30](https://github.com/walkerke/freestiler/issues/30);
PRs [#31](https://github.com/walkerke/freestiler/pull/31)–[#33](https://github.com/walkerke/freestiler/pull/33).

---

## [#2](https://github.com/jimbrig/freestiler/issues/2) — Theme A tracker

> Source: <https://github.com/jimbrig/freestiler/issues/2>

Epic for file/query parity before recipes (B) and dynamic XYZ (C). Checklist:
#3, #7, #4, #5, #6. Keep #8/#9 out of this epic.

### Grounding

| Path | Role |
|------|------|
| [`src/rust/freestiler-core/src/engine.rs`](../../src/rust/freestiler-core/src/engine.rs) | `TileConfig`, `generate_tiles` / `generate_tiles_into`, `LayeredTiler` |
| [`src/rust/freestiler-core/src/file_input.rs`](../../src/rust/freestiler-core/src/file_input.rs) | parquet / DuckDB file / query → one `LayerData` each |
| [`src/rust/freestiler-core/src/streaming.rs`](../../src/rust/freestiler-core/src/streaming.rs) | point-only streaming + `TileSpool` |
| [`R/freestile.R`](../../R/freestile.R) | `freestile` / `freestile_file` / `freestile_query` |
| [`dev/docs/ideas.md`](ideas.md) | encoder API gaps write-up |
| [`AGENTS.md`](../../AGENTS.md) | Themes A/B/C product framing |

### Decisions already locked

- Rust-first: capability in `freestiler-core`, then CLI, then thin R.
- Absorb LayeredTiler rather than invent a parallel multi-layer design.
- Recipes (#8) blocked until file/query path is not sf-shaped.

### Suggested issue body upgrades

- Link architecture plan + `product-gaps.md`.
- Note LayeredTiler absorb branch status under #5 / #3.
- Add “Theme C tracking issue: open when #3+#7 land.”

---

## [#3](https://github.com/jimbrig/freestiler/issues/3) — Multi-layer from files/queries without sf

> Source: <https://github.com/jimbrig/freestiler/issues/3>

### Problem (precise)

The **kernel already multi-layer encodes** (`Vec<LayerData>` +
`encode_tile_multilayer` + PMTiles `vector_layers`). The hole is **ingest**:

- R: `.normalize_layers()` only accepts `sf` / `freestile_layer(sf)`.
- Rust file/query helpers each return `vec![one LayerData]`.
- `pmtiles merge` cannot build overlapping zoom bands; those must be one write.

Two distinct multi-layer problems (do not conflate):

1. Several **sources** → several `source-layer` names in one archive.
2. Several **OGR layers inside one GPKG** → needs `layer=` / `ST_Read(..., layer=)`.

### Code anchors

| Piece | Location |
|-------|----------|
| Multilayer encode | `mvt::encode_tile_multilayer` / `mlt::encode_tile_multilayer` |
| Layer type | `tiler::LayerData` (`name`, features, zooms — **no encode knobs yet**) |
| R normalize | `R/freestile.R` `.normalize_layers` |
| File ingest | `file_input::{parquet,duckdb_file,duckdb_query}_to_layers` |
| Layered memory | `engine::LayeredTiler` (branch `wip/layered-tiler-absorb`) |

### Target API shape (core-first)

Serializable **LayerSpec** (path XOR query):

- `path` or `query` (+ optional `db_path`)
- `layer_name`, `min_zoom`, `max_zoom`
- optional OGR `layer`, `engine` / auto, `columns` / SQL projection
- per-layer knobs → see #7

Feed specs into `LayeredTiler` one at a time (lazy load → tile → drop). Thin R:
`freestile()` accepts a list of specs; `freestile_file`/`query` become wrappers.

### Upstream

- [walkerke#17](https://github.com/walkerke/freestiler/issues/17) — same pain; Python
  `freestile_layers` in [PR #33](https://github.com/walkerke/freestiler/pull/33).
  Fork win: **R + DuckDB/GeoParquet specs** on the same tiler.

### Out of scope (first PR)

Per-tile bbox streaming so peak ≠ decoded layer size. Document peak honestly
(#5). Do **not** encode-each-source-then-merge.

### Acceptance

- Two file sources (e.g. parquet + FGB) → one archive, overlapping zooms,
  correct `vector_layers`, no `sf` round-trip.
- Small fixtures (TIGER-scale).
- Shared DuckDB connection when several queries hit the same hive.

### Open design questions

- Spec as JSON (CLI) vs R list-of-lists first? Plan: **core JSON type**, R maps to it.
- Hive directory as one layer vs explicit query? Prefer explicit query /
  `read_parquet('dir/**/*.parquet', hive_partitioning=1)`.

---

## [#7](https://github.com/jimbrig/freestiler/issues/7) — Per-layer encode knobs

> Source: <https://github.com/jimbrig/freestiler/issues/7>

### Problem

`TileConfig` is process-wide: one `drop_rate`, `cluster_*`, `coalesce`,
`simplification`, `base_zoom`, `gzip_level`. Mixed themes (TIGER no-drop +
parcels `drop_rate ≈ 4`) cannot share an archive even on the sf multi-layer path.

### Code anchors

```rust
// engine.rs — global today
pub struct TileConfig {
    pub tile_format: TileFormat,
    pub min_zoom: u8,
    pub max_zoom: u8,
    pub base_zoom: Option<u8>,
    pub simplification: bool,
    pub drop_rate: Option<f64>,
    pub cluster_distance: Option<f64>,
    pub cluster_maxzoom: Option<u8>,
    pub coalesce: bool,
    pub gzip_level: Option<u32>,
}
```

`LayerData` only carries zooms today, not encode options.

### Goal

`LayerEncodeOptions` (or fields on LayerSpec / LayerData): at least
`drop_rate`, `base_zoom`; likely `simplification`, `coalesce`, cluster fields.
Kernel applies per layer inside `generate_tiles_into` / LayeredTiler.

Keep process defaults for single-layer calls so existing R APIs stay stable.

### Sequencing

Land **with or immediately after #3** — otherwise multi-layer files are not
usable for mixed cartography. `gzip_level` can stay archive-global (compression
of the finished tile blob) even when drop/cluster are per-layer.

### Tippecanoe / tylertoo mapping (for recipes later)

Familiar surface: `-z/-Z`, `-r` drop-rate, `-B` base zoom, coalesce, cluster.
Recipes (#8) should emit **these same names**, not a parallel vocabulary
([`recipe_decisions.md`](recipe_decisions.md)).

---

## [#4](https://github.com/jimbrig/freestiler/issues/4) — Auto file engine; stop sf CRS fallback

> Source: <https://github.com/jimbrig/freestiler/issues/4>

### Current behavior (verify against code)

| Path | Behavior |
|------|----------|
| `freestile_file(engine="geoparquet")` | default → `parquet_to_layers` only |
| Rust DuckDB file | extension split: parquet → `read_parquet`; else `ST_Read` + flatten |
| GeoParquet CRS fail | R can fall back to **`sf::st_read` of entire file** — worst large-file footgun |
| R DuckDB fallback | materialize as `sf` → `freestile()` |
| GPKG | `ST_Read` default OGR layer only |

DuckDB’s bundled GDAL ≠ system GDAL on PATH. gpio/tylertoo are parquet-only by
product choice; this fork is not.

### Goal

- Default `engine = "auto"`: parquet → crate, then DuckDB `read_parquet` on
  CRS/type failure; `.fgb`/`.gpkg`/`.shp`/`.geojson` → `ST_Read`.
- Explicit OGR `layer=`.
- Never `sf::st_read` as CRS fallback; use DuckDB `ST_Transform`.
- Warn/refuse large R→sf DuckDB backend.
- Optional `columns=` / min-schema (often dominates bytes vs vertices).

### Acceptance

- `freestile_file("x.fgb")` works without forcing `engine="duckdb"`.
- Document `SELECT * FROM ST_Drivers()` on the Windows DuckDB DLL.
- No silent full-file `sf` load on CRS mismatch.

### Upstream

- [walkerke#34](https://github.com/walkerke/freestiler/issues/34) — zstd /
  parquet vs `ST_Read` confusion (this fork already enables zstd; auto engine
  is the product answer).

### Refs

- [`file_input.rs`](../../src/rust/freestiler-core/src/file_input.rs)
- [`ideas.md`](ideas.md) “File inputs beyond GeoParquet”
- [Distributing GeoParquet](https://raw.githubusercontent.com/opengeospatial/geoparquet/refs/heads/main/format-specs/distributing-geoparquet.md)

---

## [#5](https://github.com/jimbrig/freestiler/issues/5) — Bound tiling memory

> Source: <https://github.com/jimbrig/freestiler/issues/5>

### Stale claim in original issue body

> “Default write path: `generate_tiles` returns `Vec` of every encoded tile”

**No longer true** after upstream spool absorb: `generate_tiles` writes into
`TileSpool`; `generate_pmtiles` uses `write_pmtiles_from_spool`. Peak is still
**decoded `LayerData` (+ simplify/cluster maps)**, not the finished archive.

LayeredTiler (branch): multilayer peak ≈ **largest layer**, not sum
([PR #33](https://github.com/walkerke/freestiler/pull/33)).

### Still true / still open

| Peak source | Status |
|-------------|--------|
| Full `Vec<Feature>` after ingest | open |
| `drop::compute_spatial_indices` over full layer | open |
| Point cluster precompute all zooms | open |
| Point streaming only (`streaming.rs`); polygons rejected | open ([upstream#16](https://github.com/walkerke/freestiler/issues/16)) |
| Encoded archive in RAM | **done** (spool) |
| Multilayer sum-of-layers | **done on branch** (LayeredTiler) |
| DuckDB `memory_limit` / threads knobs | open |
| `columns=` min-schema | open (also #4) |
| Honest peak docs | open (partially fixed in `ideas.md`) |

### Cheap next vs hard later

**Cheap:** DuckDB `memory_limit`/`threads`, `spill_dir`, `columns=`, docs.

**Hard (do not pretend first PR):** two-pass drop, per-tile bbox from covering /
RTree, polygon streaming, gpio-style hard error on vertex bombs.

### Tylertoo reference

Bounded memory ≈ largest row group + winner tables (two-pass):
[tylertoo bounded-memory](https://geoparquet-io.github.io/tylertoo/diving-deeper/bounded-memory/)
(docs URLs move; also see [tylertoo](https://github.com/geoparquet-io/tylertoo)
and [OVERVIEWS_SPEC](https://github.com/geoparquet-io/tylertoo/blob/main/context/OVERVIEWS_SPEC.md)).

### Suggested issue edit

Strike or annotate the stale “returns Vec of every tile” bullet; credit spool +
LayeredTiler; leave remaining checklist.

---

## [#6](https://github.com/jimbrig/freestiler/issues/6) — GeoParquet 1.1 vs 2.0 fixtures + CRS errors

> Source: <https://github.com/jimbrig/freestiler/issues/6>

### Why it matters

Readers disagree on: GeoParquet 1.1 vs 2.0, WKB vs native parquet spatial types,
CRS in file vs column metadata. GDAL can report EPSG:4326 with nonsense extents
(axis/type mismatch). Crate path requires resolvable WGS84
(`check_crs_is_wgs84`); DuckDB can `ST_Transform`.

### Goal

- Small **in-tree** 1.1 and 2.0 fixtures (`tests/` / `inst/extdata`) — not
  machine-local `dev/references/` paths.
- Errors name the failure mode (missing `geo` metadata, native types, CRS
  location).
- `engine="auto"` (#4) tries the other engine on recoverable failure.

### Refs

- [GeoMermaids geoparquet cookbook](https://www.geomermaids.com/cookbook/geoparquet/)
- [Distributing GeoParquet](https://raw.githubusercontent.com/opengeospatial/geoparquet/refs/heads/main/format-specs/distributing-geoparquet.md)
- [GPQ Workbench](https://github.com/gsueur/geopq-workbench)
- [GDAL Parquet driver](https://gdal.org/en/stable/drivers/vector/parquet.md)

### Pairing

Implement alongside or just after #4 so auto-fallback has something to fall back
to in tests.

---

## [#8](https://github.com/jimbrig/freestiler/issues/8) — Recipes / diagnostics / map packaging

> Source: <https://github.com/jimbrig/freestiler/issues/8>
>
> Title still says “lift … from artifactviewer” — **product decision is fresh
> design informed by that prior art, not a code lift**
> ([`recipe_decisions.md`](recipe_decisions.md)).

### Blocked on

Enough of Theme A (#3, #7, #4 at minimum) that recipes do not wrap the sf-only API.

### What a recipe is (locked)

| User supplies | System produces |
|---------------|-----------------|
| Source (path/DSN) | Encode args: zooms, `drop_rate`, coalesce, … |
| Optional encode overrides (same `freestile_*` names) | First-paint: `bounds`, `center`, `zoom` (**always**) |
| Optional viewport (default 1280×800) | Provenance: measurements + constants + rationale |

**Not** public knobs: `detail_px`, `underzoom_margin`, `features_per_tile`,
theme/intent enums.

Pipeline: measure (GDAL) → sample sizes (DuckDB) → derive → recipe JSON →
`freestile_*` + map camera.

### Implementation shape

- Core types + serde JSON first; R thin wrap later.
- Explore math in `dev/` until validated; no premature `R/recipe*.R` in the package.
- Emit TileJSON / style **skeletons** for [mapgl](https://github.com/walkerke/mapgl)
  and [maplibre-yaml](https://docs.maplibre-yaml.org/) — do not reimplement those clients.
- Overviews (`geo:overviews`) = Theme B **phase 2**, not recipe v1
  ([OVERVIEWS_SPEC](https://github.com/geoparquet-io/tylertoo/blob/main/context/OVERVIEWS_SPEC.md)).

### Suggested issue edits

- Retitle: “Theme B: recipe measure/derive + sidecar (fresh design)”.
- Strike “lift artifactviewer”; cite `recipe_decisions.md` + `tile-recipe-spec.md`
  (refresh the latter so it does not re-ask settled first-paint questions).
- Explicit non-goals: Portolan/STAC, tylertoo runtime dep, overview writer v1.

### Open

- drop_rate ↔ freestiler area-gate calibration.
- When dense small polygons need representation ladder / multi-layer / overviews
  instead of drop alone.
- Exact JSON schema shape (fields stable; serialization still exploratory).

---

## [#9](https://github.com/jimbrig/freestiler/issues/9) — Large-file PMTiles HTTP

> Source: <https://github.com/jimbrig/freestiler/issues/9>

> "`serve_tiles()` is httpuv with CORS and Range; it loads ranges into R and struggles past ~1 GB. `dev/examples/tiles_serve.R` already prefers bunx/npx `http-server`.
>
> Not blocking encoder work. When touched: wrap the large-file path in-package (processx + bunx/npx); document httpuv as the convenience server. Evaluate goServeR / plumber2 as optional later — extra Windows compile vs API surface, not a replacement for tiling."

### Notes

- `httpuv` does not natively support HTTP range requests (`Range` / `206`) out of
  the box; a custom Rook handler is what both
  [`walkerke/freestiler`](https://github.com/walkerke/freestiler) and
  [`walkerke/pmtiles`](https://github.com/walkerke/pmtiles) use. Odd for
  `pmtiles` given it already wraps the Go CLI `serve`.
- `pmtiles` R package: `pm_serve()` (raw archive for PMTiles.js),
  `pm_serve_zxy()` (Z/X/Y + TileJSON). Useful references, not required deps.
- Alternatives: processx + `bunx`/`npx http-server --cors -c-1` (already in
  [`dev/examples/tiles_serve.R`](../examples/tiles_serve.R)); goServeR (Go via
  cgo — GPL + Go toolchain cost); Rust `axum`/`hyper` static Range in a future CLI.
- **Do not conflate** with Theme C dynamic encode. Also distinct from
  Martin / `pmtiles serve` XYZ in front of an existing archive.

### Architecture plan commitment

1. httpuv for small archives (~≤1 GB) and Shiny-adjacent demos.
2. Promote processx + http-server path into package `serve_tiles` for large files.
3. Document Caddy / object storage / Martin / `pmtiles serve` for production.
4. Skip goServeR as a hard dependency; optional Suggests/docs only.
5. When Rust CLI exists: `freestiler serve --static`.

### Requirements (any static host)

`Accept-Ranges: bytes`, correct `206`, CORS allowing `Range`/`If-Match`, expose
`ETag`/`Content-Range`. See [Protomaps cloud storage](https://docs.protomaps.com/pmtiles/cloud-storage).

### References / resources

Original freestiler serve:

- [walkerke/freestiler `R/serve.R`](https://github.com/walkerke/freestiler/blob/main/R/serve.R)
- This fork: [`R/serve.R`](../../R/serve.R), [`dev/examples/tiles_serve.R`](../examples/tiles_serve.R)

`walkerke/pmtiles`:

- [`R/pm_serve.R`](https://github.com/walkerke/pmtiles/blob/main/R/pm_serve.R)
- [`R/pm_serve_zxy.R`](https://github.com/walkerke/pmtiles/blob/main/R/pm_serve_zxy.R)
- [`R/pm_view.R`](https://github.com/walkerke/pmtiles/blob/main/R/pm_view.R)

Packages:

- [httpuv](https://github.com/rstudio/httpuv) · [docs](https://rstudio.github.io/httpuv/)
- [nanonext](https://github.com/r-lib/nanonext) · [docs](https://r-lib.github.io/nanonext/)
- [ambiorix](https://github.com/ambiorix-web/ambiorix) · [docs](https://ambiorix.dev/docs/)
- [servr](https://github.com/yihui/servr) · [docs](https://pkg.yihui.org/servr/)
- [plumber2](https://github.com/posit-dev/plumber2/) · [docs](https://plumber2.posit.co/)
- [fiery](https://github.com/thomasp85/fiery) · [docs](https://fiery.data-imaginist.com/)
- [goServeR](https://github.com/sounkou-bioinfo/goServeR)

Related issues:

- httpuv [range requests #259](https://github.com/rstudio/httpuv/issues/259)
- servr [httpuv static #35](https://github.com/yihui/servr/issues/35)

Other:

- [PMTiles spec](https://github.com/protomaps/PMTiles)
- [HTTP Range requests (MDN)](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/Range_requests)
- [Martin PMTiles sources](https://maplibre.org/martin/sources-pmtiles/)
- [Protomaps local serve](https://docs.protomaps.com/pmtiles/)

---

## Theme C — Dynamic MVT/MLT (no fork issue yet)

**Open a tracking issue when #3+#7 are far enough.** Distinct from #9.

### Shape (from plan)

1. Core: `encode_tile_from_source(z,x,y, LayerSpec|catalog)` — bbox SQL /
   covering prune → existing encoders.
2. CLI: `freestiler serve --dynamic` (axum).
3. Thin R httpuv/plumber2 XYZ for notebooks/Shiny.
4. Not a Martin clone; recommend Martin/`pmtiles serve` for serving **baked**
   archives as XYZ.

### Kernel today

`encode_tile` / `encode_tile_multilayer` already encode one `{z,x,y}` from
in-memory features. Missing: fetch bbox from DuckDB/GeoParquet → encode → HTTP.

### Refs

- [Martin](https://maplibre.org/martin/) (esp. DuckDB sources — unstable reference)
- [pg_tileserv](https://github.com/CrunchyData/pg_tileserv) — minimal HTTP→SQL→MVT lesson
- Upstream streaming limits: [walkerke#16](https://github.com/walkerke/freestiler/issues/16)

---

## Suggested GitHub hygiene (next pass)

1. Comment on #5 with spool/LayeredTiler status (stale Vec claim).
2. Comment on #3 that LayeredTiler absorb is on `wip/layered-tiler-absorb`.
3. Retitle/edit #8 away from “lift artifactviewer”.
4. Open Theme C tracker when ready (link from #2).
5. Keep this file as the expandable workbook; promote settled bullets into issue
   bodies so the tracker stays the source of truth for implementers.
