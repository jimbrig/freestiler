usethis::use_github_links(overwrite = TRUE)
usethis::use_air()

desc::desc_normalize()

desc::desc_add_author(
  given = "Kyle",
  family = "Walker",
  email = "kyle@walker-data.com",
  role = c("aut", "rev")
)

desc::desc_add_author(
  given = "Jimmy",
  family = "Briggs",
  email = "jimmy.briggs@noclocks.dev",
  role = c("ctb", "cre"),
  orcid = "0000-0002-7489-8787"
)

desc::desc_change_maintainer(
  given = "Jimmy",
  family = "Briggs",
  email = "jimmy.briggs@noclocks.dev",
  orcid = "0000-0002-7489-8787"
)

desc::desc_set(
  "Title" = "Create Vector Tiles from Spatial Data",
  "Description" = "A forked, windows-specific build of the original freestiler package which provides features to create vector
    tile archives in 'PMTiles' format from 'sf' spatial data frames. Supports 'Mapbox Vector Tile' ('MVT') and
    'MapLibre Tile' ('MLT') output formats. Uses a 'Rust' backend via 'extendr' for fast, in-memory tiling with zero
    external system dependencies."
)

desc::desc_bump_version(which = "minor")

desc::desc_normalize()
desc::desc_validate()

usethis::use_pkgdown_github_pages()
usethis::use_github_action("check-standard")
usethis::use_r_universe_badge()

attachment::att_amend_desc()
