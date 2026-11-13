# freestiler maintainer tasks (Windows-friendly)
set windows-shell := ["powershell.exe", "-NoLogo", "-NoProfile", "-Command"]
set dotenv-load := false

default:
    @just --list

# install into the active user library with Rust duckdb + geoparquet
install:
    Rscript tools/install.R

# isolated install into build/library/
build:
    Rscript tools/build.R

# package unit tests
test:
    Rscript -e "devtools::test()"

# R CMD check
check:
    Rscript -e "devtools::check()"

# regenerate Rd / NAMESPACE
document:
    Rscript -e "devtools::document()"

# assert Rust duckdb + geoparquet are compiled in
smoke:
    Rscript tools/feature-smoke.R --require-rust-duckdb --require-geoparquet

# local pkgdown site into docs/ (gitignored; CI publishes gh-pages)
site:
    Rscript -e "pkgdown::build_site(new_process = FALSE)"
