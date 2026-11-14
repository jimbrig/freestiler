# Tile recipe — notes (pre-implementation)

Status: **exploratory**. No package API yet. Do not treat this file as a
settled design. Local throwaway probes are not part of the contract; only the
open questions and encode targets below are meant to survive across sessions.

## What we are trying to learn

For a given spatial source, can we go from **measurable facts about the data**
to a sensible set of `freestile_*` arguments — and what else (if anything)
must be supplied by a human or by fixed SDI conventions?

That question is not answered yet. Transient R helpers that baked in too many
answers were removed on purpose.

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

These showed up in aborted helpers as "assumptions." Some may become fixed
package conventions; some may stay human inputs; some may turn out to be
**outputs of derivation**, not inputs. Undecided:

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

Hard open problems ([tylertoo](https://github.com/geoparquet-io/tylertoo) still
relevant here):

- Dense small polygons over large extents: drop_rate alone cannot invent
  visibility at continental zooms (need representation change, multi-layer,
  or aggregates — not in freestiler encode knobs today).
- Whether viewport-fit belongs in this package at all.

## Experiment criteria (durable)

Any probe that informs a future API should, at minimum:

1. Measure what it can and print the measurements clearly.
2. Name every constant used in zoom / drop calculations.
3. Emit a candidate encode argument block as a *hypothesis*, not an API.
4. Keep enough provenance to compare candidates across sources.

Promote findings into this note (or into package code/tests) when they stabilize.
Do not treat untracked local scripts as documentation.

## Related

- Product gaps: [`product-gaps.md`](product-gaps.md)
- Public reference: [tylertoo](https://github.com/geoparquet-io/tylertoo)
- Encoder gaps before fancy recipes: GitHub issues #2–#7
