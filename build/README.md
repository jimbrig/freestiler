# build/

Local, project-scoped R library for source builds of `freestiler` with the
Rust **GeoParquet** and **DuckDB** backends compiled in. Kept separate from the
user library so an existing install is never clobbered and DLL locks are
avoided.

The contents of this folder are git-ignored (see `.gitignore`); only this
README and that ignore file are tracked.

## Building

From the repo root:

```r
source("build.R")
```

`build.R` installs into `build/library/` with `NOT_CRAN=true`, fully isolated
from any personal `~/.R/Makevars[.win]` (a global `PKG_LIBS` there would
otherwise replace the package's link flags and break the build). This fork's
native builds always compile GeoParquet and Rust DuckDB support. The only thing
inherited from the local setup is the Rtools45 GNU toolchain.

To install into your normal library instead (so plain `library(freestiler)`
works everywhere), use `install.R` from the repo root rather than this isolated
build.

## Using the build

```r
.libPaths(c("build/library", .libPaths()))
library(freestiler)
freestiler:::.has_rust_duckdb()      # TRUE when the Rust DuckDB backend is present
freestiler:::.has_rust_geoparquet()  # TRUE when the GeoParquet backend is present
```

Dependencies (`sf`, `DBI`, `duckdb`, ...) resolve from the regular user library,
so keep the existing `.libPaths()` appended rather than replaced.

## Smoke-checking features

Run the same smoke checks used by CI against the local build library:

```bash
Rscript tools/feature-smoke.R --lib build/library --require-rust-duckdb --require-geoparquet
```

<!-- CHECKPOINT id="ckpt_mqyemged_juqgmp" time="2026-06-28T23:12:43.141Z" note="auto" fixes=0 questions=0 highlights=0 sections="" -->
