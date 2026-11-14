# dev/

Maintainer-only tree. Not part of the R package tarball (root `.Rbuildignore`).

## Tracked (session-durable)

| path | purpose |
|------|---------|
| `docs/` | Planning notes meant to survive across sessions (`ideas.md`, product gaps, recipe questions) |
| `scripts/` | Small maintainer helpers (`pkg_check.R`, `pkg_docs.R`) |
| `config_attachment.yaml` | `attachment::att_amend_desc()` config |

Treat tracked `docs/` like code: prefer stable decisions, open questions, and
public URLs. Do not document machine-local paths, gitignored scratch trees, or
ephemeral experiment filenames as if they were the design record.

## Untracked (local only)

`examples/`, `sandbox/`, `extdata/`, `references/`, and `check/` are gitignored
scratch/output areas. They are not a documentation surface and must not be
required for future agents to understand product direction.

## Entrypoints

Install / build / test / check live at the repo root via `just` and `tools/`.
`build/` keeps only a tracked README; all install artifacts stay gitignored.
