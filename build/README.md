# build/

Gitignored output for the isolated source install (`just build` /
`tools/build.R` → `library/`). Keeps the user library and DLL locks out of the
way while compiling always-on Rust DuckDB + GeoParquet.

Only this README and `.gitignore` are tracked. Do not commit install trees,
tarballs, or cargo targets.

Maintainer commands and smoke checks live in the root `justfile` and
[`AGENTS.md`](../AGENTS.md).
