# Tile recipe — notes (pre-implementation)

Status: **exploratory**. No package API yet. Experiment against real data first
(`dev/scripts/recipe_explore.R`). Do not treat this file as a settled design.

## What we are trying to learn

For a given spatial source, can we go from **measurable facts about the data**
to a sensible set of `freestile_*` arguments — and what else (if anything)
must be supplied by a human or by fixed SDI conventions?

That question is not answered yet. The code that was briefly added to `R/`
baked in too many answers. It has been removed.

## What freestile needs (the only hard target)

Whatever a "recipe" becomes, the *output that encodes* is eventually:

| Argument | Role |
| --- | --- |
| `layer_name` | source-layer name |
| `min_zoom`, `max_zoom` | pyramid range |
| `base_zoom` | drop curve anchor (defaults to max_zoom) |
| `drop_rate` | thinning strength, or NULL |
| `coalesce` | merge same-attr features in a tile |
| `simplification` | usually TRUE |
| `tile_format` | mvt / mlt |
| `cluster_*` | points only, or NULL |
| `engine` / `streaming` | how to read |

Plus source locator (path / query / columns).

A recipe document should record those values **and** enough provenance that
you can see why they were chosen. The shape of that document is still open.

## What can be measured from data alone

These come from the file / query (DuckDB / GDAL / parquet footers). No human
input required if metadata is present:

- feature count `N`
- bbox / extent
- geometry type / family
- CRS
- field names (and optionally types)
- GeoParquet covering / geo metadata when present
- optional: sampled feature size (bbox diagonal / length) — costs a scan

## What is *not* in the data (and is currently confusing)

These showed up in the aborted R code as "assumptions." Some may become
fixed package conventions; some may stay human inputs; some may turn out to
be **outputs of derivation**, not inputs. Undecided:

| Item | Why it appeared | Open question |
| --- | --- | --- |
| Viewport W×H, padding | Used to estimate "whole extent fits the map" zoom | Is first-paint fit even part of freestiler's job? If yes, whose viewport? |
| `target_features_per_tile` | Used to back-solve min_zoom / drop_rate | Likely should **not** be a user knob if the system is doing its job — but then what objective replaces it? |
| `detail_pixels` / coord precision | Used for max useful zoom | Precision might be measurable or theme-default; "how many px until a feature reads" is a map convention |
| `prefer_coalesce` | Forced coalesce for "overview" style | Coalesce is an encode flag — when should it flip automatically? |
| probe_depth / sample_n | Implementation detail of measurement | Should not be part of a recipe; just how hard we look |

The aborted design treated several of these as **inputs with defaults**, which
made it look like the system needed more knobs than the data. That obscured
the real goal: **minimize** what humans must supply.

## What "derive" might mean (sketch only)

Ideas under test, not committed:

1. Measure `N`, bbox, geometry family, (optional) size distribution.
2. Compute candidate zooms from geometry / density / precision formulas.
3. Map candidates → `min_zoom`, `max_zoom`, `drop_rate` (and maybe coalesce).
4. Record measurements + any conventions used + rationale.

Hard open problems (tylertoo review still relevant here):

- Dense small polygons over large extents: drop_rate alone cannot invent
  visibility at continental zooms (need representation change, multi-layer,
  or aggregates — not in freestiler encode knobs today).
- Whether viewport-fit belongs in this package at all.

## How to experiment

Use `dev/scripts/recipe_explore.R` against real paths. It:

1. Measures what it can (prints clearly).
2. Shows intermediate zoom calculations with **every constant named**.
3. Suggests a candidate encode block as a *hypothesis*, not a package API.
4. Writes a JSON dump for side-by-side comparison across sources.

Iterate there until the story is clear. Only then design package surface.

## Related

- Prior conversation notes and tylertoo lessons: chat history; tylertoo clone
  under `dev/references/tylertoo/`
- Encoder gaps before fancy recipes: GitHub issues #2–#7
