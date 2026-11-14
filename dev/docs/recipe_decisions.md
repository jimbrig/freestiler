# Recipe system — product decisions

Status: agreed direction from discussion. Implementation still exploratory.

## Problem

`freestile_*` today is a 1:1 encode API. Defaults (`min_zoom=0`, `max_zoom=14`,
no `drop_rate`) are often wrong and expensive. For a new source you have no
principled way to choose zooms or drop rate.

## Goal

**Data → sensible PMTiles args (+ initial map view) with minimal thinking.**

A recipe must either:

1. **Abstract complexity** — derive encode args and first-paint view from the
   data (plus fixed package internals), or  
2. **Make remaining choices explicit and unambiguous** — plain names, obvious
   meaning, rare overrides.

It must **not** replace `min_zoom` / `drop_rate` with a *larger* set of harder
concepts (`detail_px`, `underzoom_margin`, …) as the thing users have to learn.

## What a recipe produces (outputs)

These are the things you care about; they are what get automated:

| Output | Purpose |
| --- | --- |
| `min_zoom`, `max_zoom`, `base_zoom` | Encode + archive range |
| `drop_rate` (or NULL) | Encode thinning |
| `coalesce`, `simplification`, `tile_format`, … | Other encode flags |
| `layer_name` | Source layer |
| **`bounds`** | Initial map extent (from data bbox) |
| **`center`**, **`zoom`** (first paint) | Initial map camera — derived, not hardcoded in the app |

First-paint view is **always** computed. It is not an optional side path.
Streamlining data → tiles → map without hand-setting extent/zoom is a core
reason for recipes.

## What the user supplies (public surface)

Keep this small and obvious:

| Input | Required? | Meaning |
| --- | --- | --- |
| **Source** (path / DSN) | Yes | The data — GDAL reads identity from it automatically |
| **Encode overrides** | Optional | `min_zoom`, `max_zoom`, `drop_rate`, … — same names as `freestile_*` |
| **Viewport** (width × height, optional padding) | Optional | Refine first-paint / fit; **default 1280×800** |

The user does **not** supply GDAL fields, layer schema, or CRS — those are
**properties of the source**, measured via `gdalraster::GDALVector` (or
equivalent) from the DSN. A basic `recipe_measure(dsn)` wraps that open/read/
close cycle. Overrides are only for encode/camera when the caller already knows
better than the derivation.

Optional later (still clear, not cryptic):

- `layer` — when the DSN exposes multiple layers  
- `columns` — min-schema for tiling  
- `overview` / stronger `drop_rate` — performance vs fidelity tradeoff for thumbnails  

## What stays inside the package (not the API)

Internals with defaults, recorded in the recipe JSON for provenance — **not**
promoted as the primary knobs:

- display tile size for fit math (512 MapLibre-common; 256 alternative)  
- `underzoom_margin` (default 1)  
- `detail_px` (default 2) — visibility from sampled size  
- hard zoom ceiling (~22)  
- sample size for feature-size stats  
- earth / mercator math (inlined)

## Source measurement (GDAL + DuckDB)

**Measure** = intrinsic to the source (GDAL). **Sample** = streamed stats
(DuckDB). **Derive** = zoom/drop/view from measured + conventions.

For hive-partitioned GeoParquet (`state_fips=13/county_fips=*`):

| Step | Tool | Path |
| --- | --- | --- |
| Measure | `gdalraster::GDALVector` on `.../_metadata` | N, bbox, geom, CRS, schema |
| Sample | DuckDB | `.../county_fips=*/parcels.parquet` |

Package target: **`recipe_measure(dsn)`** using GDALVector bindings.
Until that lands, `gdal vector info --format=json` is an acceptable probe for
the same fields — different access path, same contract.

**Do not** point DuckDB at `_metadata` (external refs). **Do not** glob a
partition parent that also holds sibling formats (`.fgb`, `.pmtiles`, etc.).
Single-file parquet sources use one path for both GDAL and DuckDB.

## Always-on pipeline

```
source
  → measure (GDAL: N, bbox, geom, CRS, schema)
  → sample sizes (stream: median envelope / area)
  → derive encode args + first-paint (bounds, center, zoom)
  → recipe document
  → (later) freestile_* + map that reads camera from recipe
```

Fit / first-paint is **always** in that derive step. Viewport default applies
when the caller does not pass one.

## Relationship to `freestile_*`

| Today | With recipe |
| --- | --- |
| You choose every encode arg | Recipe fills them |
| Map hardcodes bounds/zoom | Map reads recipe (or PMTiles header filled from recipe) |
| Overrides = guess | Overrides = same `freestile_*` names when you insist |

Recipe **fills** the existing API; it does not invent a competing ambiguous API.

## Explicit non-goals (for now)

- Theme names (parcel / TIGER / county) as inputs  
- Replacing zoom/drop with only “advanced” cartographic knobs on the main path  
- Overview GeoParquet / representation ladder as required for v1 (may warn when gap is large)

## `min_zoom` vs `max_zoom` (agreed framing)

**`min_zoom` is the primary recipe output.** It drives overview presence,
first-paint fit, and low-zoom tile cost (together with `drop_rate`). Getting
`min_zoom` wrong means empty coarse views, wrong initial camera, or expensive
useless low-zoom tiles.

**`max_zoom` is a pre-bake depth choice, not a map display ceiling.** Map
clients overzoom native tiles past the archive’s `max_zoom` — the layer keeps
rendering; the client magnifies the highest available tile. Baking z=17+ adds
encode time and archive size with diminishing value for overview-oriented
tilesets. **`base_zoom = max_zoom`** remains a sensible default: all features
kept at the finest baked zoom; overzoom handles deeper map interaction.

Vector tiles are **visualization LOD**, not analysis geometry. Flood-zone
intersection, parcel area, topology, etc. should use source data (parquet, sf,
DuckDB) — not PMTiles — even when the map is zoomed in.

Three names share “max zoom” in the wild; recipes should record which is which
when relevant, but v1 is single-source:

| Name | Role |
| --- | --- |
| PMTiles / encode `max_zoom` | Last native tile zoom baked into the archive |
| Source `maxzoom` (MapLibre) | Last zoom the client requests native tiles; above → overzoom |
| Style layer `maxzoom` | Layer visibility cutoff (exclusive); can hide a layer if set too low |

## Multi-layer tilesets — example use case, not core design

Recipes are **per source / per layer**: measure one input, derive encode args
for that input, emit one recipe document. The system does **not** embed
multi-layer composition rules (admin hierarchy, CONUS vs state vs parcel
visibility bands, style switching).

**Example use case (documentation / workflow, not baked logic):** a distributor
already publishes optimized layers (states, counties, parcels) each with its
own recipe-derived encode args. Combining them into one PMTiles archive is
then straightforward — each layer keeps the zoom range its recipe computed
(e.g. states low `min_zoom`, parcels higher `min_zoom`, similar `max_zoom`).
A separate style spec uses layer `minzoom` / `maxzoom` to show the right layer
at the right scale. Recipes made that composition easier because each layer’s
encode args were derived independently from its data, not guessed.

Do not add CONUS-scale heuristics, layer-type presets, or style generation to
the recipe core for v1.

## Open implementation detail (not product ambiguity)

How polygon `drop_rate` maps to freestiler’s **area-gate** drop (vs tippecanoe
count budgets) — internal calibration from sampled sizes. Users still see
`drop_rate` as the familiar freestile argument.
