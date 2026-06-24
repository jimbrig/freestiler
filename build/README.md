# build/

Local, project-scoped R library for source builds of `freestiler` with the
Rust **GeoParquet** and **DuckDB** backends compiled in. Kept separate from the
user library so the r-universe install is never clobbered and DLL locks are
avoided.

The contents of this folder are git-ignored (see `.gitignore`); only this
README and that ignore file are tracked.

## Building

From the repo root:

```r
source("build.R")
```

`build.R` installs into `build/r-lib-zstd-r46/` with `NOT_CRAN=true`,
`FREESTILER_GEOPARQUET=true`, and `FREESTILER_DUCKDB=true`, fully isolated from
`~/.R/Makevars` (which sets a GDAL `PKG_LIBS` that would otherwise break the
link). The only thing inherited from the local setup is the rtools45 GNU
toolchain.

## Using the build

```r
.libPaths(c("build/r-lib-zstd-r46", .libPaths()))
library(freestiler)
freestiler:::.has_rust_duckdb()   # TRUE when the Rust DuckDB backend is present
```

Dependencies (`sf`, `DBI`, `duckdb`, ...) resolve from the regular user library,
so keep the existing `.libPaths()` appended rather than replaced.
