# Tests for freestile_h3() and view_h3_tiles().
#
# These tests exercise the R-only multi-layer assembly path: sf or SQL input
# -> DuckDB H3 aggregation -> per-resolution sf layers -> freestile().

.has_h3_extension <- function() {
  if (!requireNamespace("DBI", quietly = TRUE) ||
      !requireNamespace("duckdb", quietly = TRUE)) {
    return(FALSE)
  }
  tryCatch({
    con <- DBI::dbConnect(duckdb::duckdb())
    on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
    DBI::dbExecute(con, "INSTALL h3 FROM community; LOAD h3;")
    DBI::dbGetQuery(con, "SELECT h3_latlng_to_cell(0, 0, 5) AS h3 LIMIT 1")
    TRUE
  }, error = function(e) FALSE)
}

skip_if_no_h3 <- function() {
  skip_on_cran()
  skip_if_not_installed("sf")
  skip_if_not_installed("DBI")
  skip_if_not_installed("duckdb")
  skip_if_not(.has_h3_extension(),
    message = "DuckDB H3 community extension not available")
}

.make_points <- function(n = 2000, seed = 1L) {
  set.seed(seed)
  sf::st_as_sf(
    data.frame(
      x = stats::runif(n, -100, -80),
      y = stats::runif(n, 30, 45),
      w = stats::rnorm(n, 100, 10),
      cat = sample(letters[1:3], n, replace = TRUE)
    ),
    coords = c("x", "y"),
    crs = 4326
  )
}

test_that("freestile_h3() default agg produces expected layer set", {
  skip_if_no_h3()

  pts <- .make_points()
  output <- tempfile(fileext = ".pmtiles")
  on.exit(unlink(output), add = TRUE)

  result <- freestile_h3(
    pts, output,
    min_zoom = 2L, max_zoom = 8L, base_zoom = 6L,
    quiet = TRUE
  )
  expect_equal(result, output)
  expect_true(file.exists(output))
  expect_true(file.info(output)$size > 0)

  meta <- pmtiles_metadata(output)
  expect_false(is.null(meta))
  layer_ids <- vapply(meta$metadata$vector_layers, function(x) x$id, character(1))
  expect_true(any(grepl("^h3_r\\d{2}$", layer_ids)))
  expect_true("points" %in% layer_ids)

  # Default: disjoint windows.
  hex_layers <- meta$metadata$vector_layers[
    grepl("^h3_r\\d{2}$", layer_ids)
  ]
  hex_layers <- hex_layers[order(vapply(hex_layers, function(x)
    x$minzoom %||% x$min_zoom %||% 0L, numeric(1)))]
  if (length(hex_layers) > 1L) {
    for (i in seq_len(length(hex_layers) - 1L)) {
      a_max <- hex_layers[[i]]$maxzoom %||% hex_layers[[i]]$max_zoom
      b_min <- hex_layers[[i + 1L]]$minzoom %||% hex_layers[[i + 1L]]$min_zoom
      expect_lt(a_max, b_min)
    }
  }
})

test_that("freestile_h3() custom agg expressions become MVT properties", {
  skip_if_no_h3()

  pts <- .make_points()
  output <- tempfile(fileext = ".pmtiles")
  on.exit(unlink(output), add = TRUE)

  freestile_h3(
    pts, output,
    agg = c(n = "COUNT(*)", avg_w = "AVG(w)", total_w = "SUM(w)"),
    min_zoom = 2L, max_zoom = 6L, base_zoom = 5L,
    quiet = TRUE
  )

  meta <- pmtiles_metadata(output)
  hex_layers <- Filter(function(x) grepl("^h3_r\\d{2}$", x$id),
    meta$metadata$vector_layers)
  expect_true(length(hex_layers) > 0L)
  fields <- names(hex_layers[[1L]]$fields)
  expect_true(all(c("n", "avg_w", "total_w") %in% fields))
})

test_that("freestile_h3() agg list form works", {
  skip_if_no_h3()

  pts <- .make_points()
  output <- tempfile(fileext = ".pmtiles")
  on.exit(unlink(output), add = TRUE)

  freestile_h3(
    pts, output,
    agg = list(n = c("count", "*"), avg_w = c("mean", "w")),
    min_zoom = 2L, max_zoom = 5L, base_zoom = 4L,
    quiet = TRUE
  )

  meta <- pmtiles_metadata(output)
  hex_layers <- Filter(function(x) grepl("^h3_r\\d{2}$", x$id),
    meta$metadata$vector_layers)
  fields <- names(hex_layers[[1L]]$fields)
  expect_true(all(c("n", "avg_w") %in% fields))
})

test_that("freestile_h3() rejects MULTIPOINT input", {
  skip_if_no_h3()

  pts <- .make_points()
  mp <- sf::st_cast(sf::st_combine(sf::st_geometry(pts)), "MULTIPOINT")
  mp_sf <- sf::st_sf(id = 1L, geometry = mp)

  output <- tempfile(fileext = ".pmtiles")
  expect_error(
    freestile_h3(mp_sf, output, min_zoom = 0L, max_zoom = 4L, quiet = TRUE),
    "MULTIPOINT"
  )
})

test_that("freestile_h3() rejects non-point sf", {
  skip_if_no_h3()

  nc <- sf::st_read(system.file("shape/nc.shp", package = "sf"), quiet = TRUE)
  output <- tempfile(fileext = ".pmtiles")
  expect_error(
    freestile_h3(nc, output, min_zoom = 0L, max_zoom = 4L, quiet = TRUE),
    "POINT geometry"
  )
})

test_that("base_zoom = min_zoom produces only the points layer", {
  skip_if_no_h3()

  pts <- .make_points(n = 500L)
  output <- tempfile(fileext = ".pmtiles")
  on.exit(unlink(output), add = TRUE)

  freestile_h3(
    pts, output,
    min_zoom = 2L, max_zoom = 5L, base_zoom = 2L,
    quiet = TRUE
  )

  meta <- pmtiles_metadata(output)
  layer_ids <- vapply(meta$metadata$vector_layers, function(x) x$id, character(1))
  expect_false(any(grepl("^h3_r\\d{2}$", layer_ids)))
  expect_true("points" %in% layer_ids)
})

test_that("base_zoom default resolves to max_zoom - 2", {
  skip_if_no_h3()

  pts <- .make_points(n = 500L)
  output <- tempfile(fileext = ".pmtiles")
  on.exit(unlink(output), add = TRUE)

  freestile_h3(
    pts, output,
    min_zoom = 0L, max_zoom = 6L,  # base_zoom defaults to 4
    quiet = TRUE
  )

  meta <- pmtiles_metadata(output)
  layer_ids <- vapply(meta$metadata$vector_layers, function(x) x$id, character(1))
  hex_ids <- layer_ids[grepl("^h3_r\\d{2}$", layer_ids)]
  expect_true(length(hex_ids) > 0L)

  pts_layer <- Filter(function(x) x$id == "points", meta$metadata$vector_layers)[[1L]]
  pts_min <- pts_layer$minzoom %||% pts_layer$min_zoom
  expect_equal(as.integer(pts_min), 4L)
})

test_that("explicit out-of-range base_zoom errors", {
  skip_if_no_h3()

  pts <- .make_points(n = 100L)
  output <- tempfile(fileext = ".pmtiles")
  expect_error(
    freestile_h3(pts, output, min_zoom = 2L, max_zoom = 6L, base_zoom = 10L,
      quiet = TRUE),
    "base_zoom"
  )
  expect_error(
    freestile_h3(pts, output, min_zoom = 2L, max_zoom = 6L, base_zoom = 0L,
      quiet = TRUE),
    "base_zoom"
  )
})

test_that("CRS reprojection for sf input works", {
  skip_if_no_h3()

  pts <- .make_points(n = 500L)
  pts_3857 <- sf::st_transform(pts, 3857)

  output <- tempfile(fileext = ".pmtiles")
  on.exit(unlink(output), add = TRUE)

  freestile_h3(
    pts_3857, output,
    min_zoom = 2L, max_zoom = 6L, base_zoom = 5L,
    quiet = TRUE
  )

  meta <- pmtiles_metadata(output)
  bbox4326 <- sf::st_bbox(pts)
  # Hex boundaries extend a few degrees beyond the underlying points at coarse
  # resolutions; we just verify the bbox is in the right neighborhood, not
  # exact. The test is that reprojection happened (not a no-op).
  expect_lt(abs(meta$min_longitude - bbox4326["xmin"]), 5)
  expect_lt(abs(meta$max_longitude - bbox4326["xmax"]), 5)
  expect_gt(meta$min_longitude, -110)
  expect_lt(meta$max_longitude, -70)
})

test_that("fade = TRUE produces overlapping zoom windows", {
  skip_if_no_h3()

  pts <- .make_points()
  output <- tempfile(fileext = ".pmtiles")
  on.exit(unlink(output), add = TRUE)

  freestile_h3(
    pts, output,
    min_zoom = 2L, max_zoom = 8L, base_zoom = 6L,
    fade = TRUE, fade_overlap = 1L,
    quiet = TRUE
  )

  meta <- pmtiles_metadata(output)
  hex_layers <- Filter(function(x) grepl("^h3_r\\d{2}$", x$id),
    meta$metadata$vector_layers)
  hex_layers <- hex_layers[order(vapply(hex_layers, function(x)
    x$minzoom %||% x$min_zoom %||% 0L, numeric(1)))]
  skip_if(length(hex_layers) < 2L,
    "Need at least 2 hex layers to test overlap")
  for (i in seq_len(length(hex_layers) - 1L)) {
    a_max <- hex_layers[[i]]$maxzoom %||% hex_layers[[i]]$max_zoom
    b_min <- hex_layers[[i + 1L]]$minzoom %||% hex_layers[[i + 1L]]$min_zoom
    expect_gte(a_max, b_min)
  }
})

test_that("fade_overlap = 2 produces wider overlap than default", {
  skip_if_no_h3()

  pts <- .make_points(n = 500L)
  out1 <- tempfile(fileext = ".pmtiles")
  out2 <- tempfile(fileext = ".pmtiles")
  on.exit({unlink(out1); unlink(out2)}, add = TRUE)

  freestile_h3(pts, out1,
    min_zoom = 0L, max_zoom = 10L, base_zoom = 8L,
    fade = TRUE, fade_overlap = 1L, quiet = TRUE)
  freestile_h3(pts, out2,
    min_zoom = 0L, max_zoom = 10L, base_zoom = 8L,
    fade = TRUE, fade_overlap = 2L, quiet = TRUE)

  width <- function(path) {
    meta <- pmtiles_metadata(path)
    hex <- Filter(function(x) grepl("^h3_r\\d{2}$", x$id),
      meta$metadata$vector_layers)
    if (length(hex) == 0L) return(0L)
    spans <- vapply(hex, function(x) {
      (x$maxzoom %||% x$max_zoom) - (x$minzoom %||% x$min_zoom)
    }, numeric(1))
    max(spans)
  }
  expect_gt(width(out2), width(out1))
})

test_that("h3_resolutions named override is honored", {
  skip_if_no_h3()

  pts <- .make_points(n = 500L)
  output <- tempfile(fileext = ".pmtiles")
  on.exit(unlink(output), add = TRUE)

  freestile_h3(
    pts, output,
    min_zoom = 0L, max_zoom = 6L, base_zoom = 5L,
    h3_resolutions = c(`0` = 0L, `1` = 0L, `2` = 1L, `3` = 1L, `4` = 2L),
    quiet = TRUE
  )

  meta <- pmtiles_metadata(output)
  layer_ids <- vapply(meta$metadata$vector_layers, function(x) x$id, character(1))
  hex_ids <- sort(layer_ids[grepl("^h3_r\\d{2}$", layer_ids)])
  expect_equal(hex_ids, c("h3_r00", "h3_r01", "h3_r02"))
})

test_that("h3_resolutions unnamed override length must match", {
  pts <- .make_points(n = 100L)
  output <- tempfile(fileext = ".pmtiles")
  expect_error(
    freestile_h3(pts, output,
      min_zoom = 0L, max_zoom = 6L, base_zoom = 5L,
      h3_resolutions = c(1L, 2L, 3L),  # need 5 entries for zooms 0..4
      quiet = TRUE),
    "length"
  )
})

test_that("h3_resolutions rejects names outside the hex zoom range", {
  pts <- .make_points(n = 100L)
  output <- tempfile(fileext = ".pmtiles")
  expect_error(
    freestile_h3(pts, output,
      min_zoom = 0L, max_zoom = 6L, base_zoom = 4L,
      h3_resolutions = c(`10` = 5L),
      quiet = TRUE),
    "zoom"
  )
})

test_that("h3_resolutions rejects values outside 0..15", {
  pts <- .make_points(n = 100L)
  output <- tempfile(fileext = ".pmtiles")
  expect_error(
    freestile_h3(pts, output,
      min_zoom = 0L, max_zoom = 4L, base_zoom = 3L,
      h3_resolutions = c(`0` = 99L),
      quiet = TRUE),
    "0..15"
  )
})

test_that("non-contiguous repeated resolution errors", {
  pts <- .make_points(n = 100L)
  output <- tempfile(fileext = ".pmtiles")
  expect_error(
    freestile_h3(pts, output,
      min_zoom = 0L, max_zoom = 6L, base_zoom = 5L,
      h3_resolutions = c(5L, 5L, 6L, 5L, 5L),  # res 5 appears in two runs
      quiet = TRUE),
    "non-contiguous"
  )
})

test_that("SQL input path produces a non-empty archive", {
  skip_if_no_h3()

  # Inline VALUES query expressing points directly.
  sql <- paste(
    "SELECT * FROM (VALUES",
    paste(sprintf("(%d, ST_Point(%f, %f), %f)",
      seq_len(50),
      stats::runif(50, -100, -80),
      stats::runif(50, 30, 45),
      stats::rnorm(50, 100, 10)
    ), collapse = ", "),
    ") AS t(id, geometry, w)"
  )

  output <- tempfile(fileext = ".pmtiles")
  on.exit(unlink(output), add = TRUE)

  freestile_h3(
    sql, output,
    agg = c(n = "COUNT(*)", avg_w = "AVG(w)"),
    source_crs = "EPSG:4326",
    min_zoom = 2L, max_zoom = 5L, base_zoom = 4L,
    quiet = TRUE
  )
  expect_true(file.exists(output))
  expect_gt(file.info(output)$size, 0L)
})

test_that("SQL input without source_crs warns", {
  skip_if_no_h3()

  sql <- paste(
    "SELECT 1 AS id, ST_Point(-78.6, 35.8) AS geometry",
    "UNION ALL SELECT 2, ST_Point(-79.0, 36.0)"
  )
  output <- tempfile(fileext = ".pmtiles")
  on.exit(unlink(output), add = TRUE)

  expect_warning(
    freestile_h3(sql, output,
      min_zoom = 0L, max_zoom = 4L, base_zoom = 3L, quiet = TRUE),
    "source_crs"
  )
})

test_that("invalid agg specification errors", {
  pts <- .make_points(n = 100L)
  output <- tempfile(fileext = ".pmtiles")
  expect_error(
    freestile_h3(pts, output, agg = c("COUNT(*)"),  # missing name
      min_zoom = 0L, max_zoom = 4L, quiet = TRUE),
    "named"
  )
  expect_error(
    freestile_h3(pts, output,
      agg = list(n = c("nonsense", "w")),
      min_zoom = 0L, max_zoom = 4L, quiet = TRUE),
    "aggregation function"
  )
})

test_that("SQL input with EPSG:3857 source_crs preserves x/y axis order", {
  skip_if_no_h3()

  # Two points around (-100, 35) and (-95, 40) in WGS84. The corresponding
  # EPSG:3857 coordinates (computed once and hard-coded; verified via
  # sf::st_transform).
  sql <- paste(
    "SELECT 1 AS id, ST_Point(-11131949.08, 4163881.14)::GEOMETRY AS geometry",
    "UNION ALL SELECT 2, ST_Point(-10575287.13, 4865942.28)::GEOMETRY"
  )
  output <- tempfile(fileext = ".pmtiles")
  on.exit(unlink(output), add = TRUE)

  freestile_h3(sql, output,
    source_crs = "EPSG:3857",
    min_zoom = 0L, max_zoom = 4L, base_zoom = 3L,
    quiet = TRUE
  )

  meta <- pmtiles_metadata(output)
  # Bounds should land in roughly the right neighborhood. Coarse H3 hexes
  # extend several degrees past their constituent points, so we just verify
  # the bbox is in the correct geographic ballpark. If axis order were
  # swapped, the bounds would land somewhere absurd (e.g. lat > 70 or lon
  # outside [-180, 0]).
  expect_gt(meta$min_longitude, -115)
  expect_lt(meta$max_longitude, -85)
  expect_gt(meta$min_latitude, 25)
  expect_lt(meta$max_latitude, 50)
})

test_that("sf input with no attribute columns succeeds (regression)", {
  skip_if_no_h3()

  pts <- .make_points(n = 200L)
  pts_geom_only <- sf::st_sf(geometry = sf::st_geometry(pts))
  expect_equal(ncol(sf::st_drop_geometry(pts_geom_only)), 0L)

  output <- tempfile(fileext = ".pmtiles")
  on.exit(unlink(output), add = TRUE)

  expect_no_error(
    freestile_h3(
      pts_geom_only, output,
      min_zoom = 2L, max_zoom = 5L, base_zoom = 4L,
      quiet = TRUE
    )
  )
  expect_true(file.exists(output))
  expect_gt(file.info(output)$size, 0L)
})

test_that("custom hex_layer_prefix round-trips through view_h3_tiles()", {
  skip_if_no_h3()
  skip_if_not_installed("mapgl")
  skip_if_not_installed("httpuv")

  pts <- .make_points(n = 500L)
  output <- tempfile(fileext = ".pmtiles")
  on.exit({
    unlink(output)
    try(stop_server(), silent = TRUE)
  }, add = TRUE)

  freestile_h3(
    pts, output,
    hex_layer_prefix = "my_h3",      # contains underscore on purpose
    point_layer_name = "raw_points",
    min_zoom = 2L, max_zoom = 5L, base_zoom = 4L,
    quiet = TRUE
  )

  meta <- pmtiles_metadata(output)
  layer_ids <- vapply(meta$metadata$vector_layers, function(x) x$id, character(1))
  expect_true(any(grepl("^my_h3_r\\d{2}$", layer_ids)))
  expect_true("raw_points" %in% layer_ids)

  m <- view_h3_tiles(output,
    agg_column = "count",
    stops = list(values = c(1, 10, 100),
                 colors = c("#fef0d9", "#fdcc8a", "#d7301f")),
    hex_layer_prefix = "my_h3",
    point_layer_name = "raw_points",
    port = 8284
  )
  expect_s3_class(m, "htmlwidget")

  # Confirm the style has at least one hex fill layer and the raw-points
  # circle layer — i.e. view_h3_tiles() found them under the custom names.
  style_layer_ids <- vapply(m$x$layers, function(l) l$id %||% "", character(1))
  expect_true(any(grepl("^hex-my_h3_r\\d{2}$", style_layer_ids)))
  expect_true(any(grepl("^points-raw_points$", style_layer_ids)))
})

test_that("view_h3_tiles() emits non-empty mapgl style zoom intervals", {
  skip_if_no_h3()
  skip_if_not_installed("mapgl")
  skip_if_not_installed("httpuv")

  pts <- .make_points(n = 500L)
  output <- tempfile(fileext = ".pmtiles")
  on.exit({
    unlink(output)
    try(stop_server(), silent = TRUE)
  }, add = TRUE)

  freestile_h3(
    pts, output,
    min_zoom = 2L, max_zoom = 6L, base_zoom = 5L,
    quiet = TRUE
  )

  m <- view_h3_tiles(output, agg_column = "count",
    stops = list(values = c(1, 10, 100),
                 colors = c("#fef0d9", "#fdcc8a", "#d7301f")),
    port = 8285)

  # Every style layer with both minzoom/maxzoom must satisfy
  # maxzoom > minzoom (MapLibre: maxzoom is exclusive, so equal -> never
  # visible). This is the regression for the off-by-one fix.
  for (lyr in m$x$layers) {
    if (!is.null(lyr$minzoom) && !is.null(lyr$maxzoom)) {
      expect_gt(lyr$maxzoom, lyr$minzoom)
    }
  }
})

test_that("view_h3_tiles() smoke test builds a mapgl map", {
  skip_if_no_h3()
  skip_if_not_installed("mapgl")
  skip_if_not_installed("httpuv")

  pts <- .make_points(n = 500L)
  output <- tempfile(fileext = ".pmtiles")
  on.exit({
    unlink(output)
    try(stop_server(), silent = TRUE)
  }, add = TRUE)

  freestile_h3(
    pts, output,
    min_zoom = 2L, max_zoom = 6L, base_zoom = 5L,
    quiet = TRUE
  )

  m <- view_h3_tiles(output, agg_column = "count",
    stops = list(values = c(1, 10, 100), colors = c("#fef0d9", "#fdcc8a", "#d7301f")),
    port = 8281)
  expect_s3_class(m, "htmlwidget")
})
