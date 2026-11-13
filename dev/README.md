# dev/

Local planning, experiments, and reference material for this fork.
Not part of the R package build (see root `.Rbuildignore`).

## layout

| path | purpose |
|------|---------|
| `docs/` | Encoder/recipe notes tracked with the repo (`ideas.md`, specs) |
| `scripts/` | Maintainer R helpers (`pkg_check.R`, `pkg_docs.R`, …) |
| `examples/` | Scratch serving / workflow scripts |
| `sandbox/` | One-off recipe experiments (usually untracked outputs) |
| `extdata/` | Large local fixtures (keep out of git) |
| `references/` | External clones for study (gitignored; do not commit) |
| `check/` | Local `devtools::check()` output (gitignored) |

## entrypoints

Package install/build/test live at the repo root via `just` (see `justfile`) and `tools/`.
