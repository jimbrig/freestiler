//! Shared polygon quantization for the tile encoders.
//!
//! Both the MVT and MLT encoders round coordinates to the integer tile grid.
//! That rounding can collapse narrow polygons to zero area (dropping them at
//! some zooms but not others, depending on how their edges land on the grid)
//! and can flip or degenerate ring winding. This module centralizes the
//! rounding so both encoders get the same guarantees:
//!
//! - Consecutive duplicate vertices are removed.
//! - Zero-area interior rings are dropped.
//! - Ring winding is normalized to the MVT convention (exterior rings have
//!   positive signed area by the surveyor's formula in y-down tile
//!   coordinates; interior rings negative).
//! - A polygon whose exterior collapses below one pixel is replaced by a
//!   one-pixel square at its centroid instead of being dropped, so thin
//!   features stay continuously visible across zoom levels.

use geo_types::{LineString, MultiPolygon, Polygon};

/// Tile coordinate extent (pixels per tile side)
pub const EXTENT: u32 = 4096;

/// Convert a longitude to tile-local X coordinate (0..4096)
pub fn lon_to_tile_coord(lon: f64, west: f64, east: f64) -> i32 {
    ((lon - west) / (east - west) * EXTENT as f64).round() as i32
}

/// Convert a latitude to tile-local Y coordinate (0..4096, Y-down)
pub fn lat_to_tile_coord(lat: f64, south: f64, north: f64) -> i32 {
    // Interpolate in Mercator Y space (not linear latitude) for correct projection
    let lat_merc = lat.to_radians().tan().asinh();
    let south_merc = south.to_radians().tan().asinh();
    let north_merc = north.to_radians().tan().asinh();
    ((north_merc - lat_merc) / (north_merc - south_merc) * EXTENT as f64).round() as i32
}

/// A polygon quantized to integer tile coordinates.
///
/// Rings are open (no closing duplicate vertex), deduplicated, and oriented:
/// exterior positive signed area, interiors negative (y-down tile space).
#[derive(Clone, Debug, PartialEq)]
pub struct QuantPolygon {
    pub exterior: Vec<(i32, i32)>,
    pub interiors: Vec<Vec<(i32, i32)>>,
}

/// Quantize a polygon, substituting a one-pixel square at the centroid if the
/// exterior ring collapses on the tile grid.
pub fn quantize_polygon_or_dot(
    poly: &Polygon<f64>,
    west: f64,
    south: f64,
    east: f64,
    north: f64,
) -> QuantPolygon {
    let ext = quantize_ring(poly.exterior(), west, south, east, north);
    if ext.len() < 3 || signed_area2(&ext) == 0 {
        return dot_polygon(ring_center(&ext));
    }

    let mut exterior = ext;
    if signed_area2(&exterior) < 0 {
        exterior.reverse();
    }

    let interiors = poly
        .interiors()
        .iter()
        .filter_map(|ring| {
            let mut coords = quantize_ring(ring, west, south, east, north);
            let area2 = if coords.len() < 3 {
                0
            } else {
                signed_area2(&coords)
            };
            if area2 == 0 {
                return None;
            }
            if area2 > 0 {
                coords.reverse();
            }
            Some(coords)
        })
        .collect();

    QuantPolygon {
        exterior,
        interiors,
    }
}

/// Quantize every part of a multipolygon. Collapsed parts become one-pixel
/// squares; squares that land on the same pixel are deduplicated.
pub fn quantize_multipolygon(
    mp: &MultiPolygon<f64>,
    west: f64,
    south: f64,
    east: f64,
    north: f64,
) -> Vec<QuantPolygon> {
    let mut seen_dots: Vec<(i32, i32)> = Vec::new();
    let mut out = Vec::with_capacity(mp.0.len());
    for poly in &mp.0 {
        let qp = quantize_polygon_or_dot(poly, west, south, east, north);
        if let Some(center) = qp.dot_center() {
            if seen_dots.contains(&center) {
                continue;
            }
            seen_dots.push(center);
        }
        out.push(qp);
    }
    out
}

impl QuantPolygon {
    /// If this polygon is a substituted one-pixel dot, return its anchor pixel.
    fn dot_center(&self) -> Option<(i32, i32)> {
        if self.interiors.is_empty() && self.exterior.len() == 4 && {
            let (x, y) = self.exterior[0];
            self.exterior == dot_exterior(x, y)
        } {
            Some(self.exterior[0])
        } else {
            None
        }
    }
}

/// One-pixel square polygon anchored at `center` (positive signed area).
pub fn dot_polygon(center: (i32, i32)) -> QuantPolygon {
    QuantPolygon {
        exterior: dot_exterior(center.0, center.1),
        interiors: Vec::new(),
    }
}

fn dot_exterior(x: i32, y: i32) -> Vec<(i32, i32)> {
    vec![(x, y), (x + 1, y), (x + 1, y + 1), (x, y + 1)]
}

/// Quantize a ring to integer tile coordinates, dropping the closing
/// duplicate and consecutive vertices that land on the same pixel.
fn quantize_ring(
    ring: &LineString<f64>,
    west: f64,
    south: f64,
    east: f64,
    north: f64,
) -> Vec<(i32, i32)> {
    let source = if ring.0.len() >= 2 && ring.0.first() == ring.0.last() {
        &ring.0[..ring.0.len() - 1]
    } else {
        &ring.0[..]
    };

    let mut coords: Vec<(i32, i32)> = Vec::with_capacity(source.len());
    for c in source {
        let p = (
            lon_to_tile_coord(c.x, west, east),
            lat_to_tile_coord(c.y, south, north),
        );
        if coords.last() == Some(&p) {
            continue;
        }
        coords.push(p);
    }

    // The last vertex may snap onto the first
    while coords.len() >= 2 && coords.first() == coords.last() {
        coords.pop();
    }

    remove_spikes(&mut coords);

    coords
}

/// Iteratively remove spikes: vertices whose cyclic neighbors coincide, i.e.
/// the ring walks out to a point and retraces itself (`A -> B -> A`).
/// Quantization commonly creates these from narrow appendages, and they make
/// the ring self-intersecting. Removing a spike tip leaves a consecutive
/// duplicate pair, which is deduplicated before re-scanning; multi-vertex
/// needles (`A -> B -> C -> B -> A`) unwind over successive passes. A ring
/// that is entirely spike degenerates below three vertices and is handled by
/// the caller (collapse to dot, or drop for interior rings).
fn remove_spikes(coords: &mut Vec<(i32, i32)>) {
    loop {
        if coords.len() < 3 {
            return;
        }
        let n = coords.len();
        let spike = (0..n).find(|&i| coords[(i + n - 1) % n] == coords[(i + 1) % n]);
        let Some(tip) = spike else {
            return;
        };
        coords.remove(tip);

        // Removing the tip leaves its two (equal) neighbors adjacent; dedupe
        // cyclically so the scan above sees a clean ring.
        let mut i = 0;
        while coords.len() >= 2 && i < coords.len() {
            if coords[i] == coords[(i + 1) % coords.len()] {
                coords.remove(i);
            } else {
                i += 1;
            }
        }
    }
}

/// Twice the signed area of an open ring by the surveyor's formula, computed
/// directly in y-down tile coordinates (MVT convention: exterior > 0).
fn signed_area2(coords: &[(i32, i32)]) -> i64 {
    let n = coords.len();
    if n < 3 {
        return 0;
    }
    let mut sum = 0i64;
    for i in 0..n {
        let (x1, y1) = coords[i];
        let (x2, y2) = coords[(i + 1) % n];
        sum += x1 as i64 * y2 as i64 - x2 as i64 * y1 as i64;
    }
    sum
}

/// Integer centroid (vertex mean) of a quantized ring, used to anchor the
/// dot substituted for a collapsed polygon. Falls back to the origin for an
/// empty ring (cannot occur for rings coming from real geometries).
fn ring_center(coords: &[(i32, i32)]) -> (i32, i32) {
    if coords.is_empty() {
        return (0, 0);
    }
    let n = coords.len() as i64;
    let sx: i64 = coords.iter().map(|&(x, _)| x as i64).sum();
    let sy: i64 = coords.iter().map(|&(_, y)| y as i64).sum();
    (
        (sx as f64 / n as f64).round() as i32,
        (sy as f64 / n as f64).round() as i32,
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use geo_types::{polygon, Coord};

    const W: f64 = 0.0;
    const S: f64 = 0.0;
    const E: f64 = 1.0;
    const N: f64 = 1.0;

    /// Degrees per tile pixel for the 1x1-degree test tile
    const PX: f64 = 1.0 / EXTENT as f64;

    #[test]
    fn wide_polygon_survives_quantization() {
        let poly = polygon![
            (x: 0.1, y: 0.1),
            (x: 0.9, y: 0.1),
            (x: 0.9, y: 0.9),
            (x: 0.1, y: 0.9),
            (x: 0.1, y: 0.1),
        ];
        let qp = quantize_polygon_or_dot(&poly, W, S, E, N);
        assert_eq!(qp.exterior.len(), 4);
        assert!(signed_area2(&qp.exterior) > 0);
    }

    #[test]
    fn reversed_exterior_winding_is_normalized() {
        // Same square as above, vertices in the opposite order
        let poly = polygon![
            (x: 0.1, y: 0.1),
            (x: 0.1, y: 0.9),
            (x: 0.9, y: 0.9),
            (x: 0.9, y: 0.1),
            (x: 0.1, y: 0.1),
        ];
        let qp = quantize_polygon_or_dot(&poly, W, S, E, N);
        assert!(signed_area2(&qp.exterior) > 0);
    }

    #[test]
    fn interior_ring_winding_is_normalized_and_opposite() {
        let mut poly = polygon![
            (x: 0.1, y: 0.1),
            (x: 0.9, y: 0.1),
            (x: 0.9, y: 0.9),
            (x: 0.1, y: 0.9),
            (x: 0.1, y: 0.1),
        ];
        poly.interiors_push(LineString::from(vec![
            Coord { x: 0.4, y: 0.4 },
            Coord { x: 0.6, y: 0.4 },
            Coord { x: 0.6, y: 0.6 },
            Coord { x: 0.4, y: 0.6 },
            Coord { x: 0.4, y: 0.4 },
        ]));
        let qp = quantize_polygon_or_dot(&poly, W, S, E, N);
        assert_eq!(qp.interiors.len(), 1);
        assert!(signed_area2(&qp.exterior) > 0);
        assert!(signed_area2(&qp.interiors[0]) < 0);
    }

    #[test]
    fn sub_pixel_polygon_becomes_dot_not_dropped() {
        // A strip 1000 pixels long but 0.2 pixels tall: both long edges round
        // to the same tile row, which previously dropped the feature.
        let poly = polygon![
            (x: 0.1, y: 0.5),
            (x: 0.1 + 1000.0 * PX, y: 0.5),
            (x: 0.1 + 1000.0 * PX, y: 0.5 + 0.2 * PX),
            (x: 0.1, y: 0.5 + 0.2 * PX),
            (x: 0.1, y: 0.5),
        ];
        let qp = quantize_polygon_or_dot(&poly, W, S, E, N);
        assert_eq!(qp.exterior.len(), 4);
        assert!(signed_area2(&qp.exterior) > 0);
        // Anchored at the strip's centroid
        let (cx, _cy) = qp.exterior[0];
        assert!((cx - 910).abs() <= 2, "dot x = {cx}, expected near 910");
    }

    #[test]
    fn fully_collapsed_polygon_becomes_dot() {
        // Smaller than one pixel in both dimensions
        let poly = polygon![
            (x: 0.5, y: 0.5),
            (x: 0.5 + 0.1 * PX, y: 0.5),
            (x: 0.5 + 0.1 * PX, y: 0.5 + 0.1 * PX),
            (x: 0.5, y: 0.5 + 0.1 * PX),
            (x: 0.5, y: 0.5),
        ];
        let qp = quantize_polygon_or_dot(&poly, W, S, E, N);
        assert_eq!(qp.exterior.len(), 4);
        assert_eq!(signed_area2(&qp.exterior), 2);
    }

    #[test]
    fn zero_area_interior_ring_is_dropped() {
        let mut poly = polygon![
            (x: 0.1, y: 0.1),
            (x: 0.9, y: 0.1),
            (x: 0.9, y: 0.9),
            (x: 0.1, y: 0.9),
            (x: 0.1, y: 0.1),
        ];
        // Sub-pixel hole collapses to zero area on the grid
        poly.interiors_push(LineString::from(vec![
            Coord { x: 0.5, y: 0.5 },
            Coord {
                x: 0.5 + 0.1 * PX,
                y: 0.5,
            },
            Coord {
                x: 0.5 + 0.1 * PX,
                y: 0.5 + 0.1 * PX,
            },
            Coord {
                x: 0.5,
                y: 0.5 + 0.1 * PX,
            },
            Coord { x: 0.5, y: 0.5 },
        ]));
        let qp = quantize_polygon_or_dot(&poly, W, S, E, N);
        assert!(qp.interiors.is_empty());
    }

    #[test]
    fn multipolygon_dedupes_coincident_dots() {
        let tiny = |x0: f64, y0: f64| {
            polygon![
                (x: x0, y: y0),
                (x: x0 + 0.1 * PX, y: y0),
                (x: x0 + 0.1 * PX, y: y0 + 0.1 * PX),
                (x: x0, y: y0 + 0.1 * PX),
                (x: x0, y: y0),
            ]
        };
        // Two slivers on the same pixel, one on a different pixel
        let mp = MultiPolygon(vec![
            tiny(0.5, 0.5),
            tiny(0.5 + 0.2 * PX, 0.5),
            tiny(0.25, 0.25),
        ]);
        let parts = quantize_multipolygon(&mp, W, S, E, N);
        assert_eq!(parts.len(), 2);
    }

    #[test]
    fn needle_spike_is_removed() {
        // A square with a zero-width needle sticking out of its top edge:
        // the ring walks out to the needle tip and retraces itself.
        let poly = polygon![
            (x: 0.1, y: 0.1),
            (x: 0.2, y: 0.1),
            (x: 0.2, y: 0.2),
            (x: 0.15, y: 0.2),
            (x: 0.15, y: 0.25),
            (x: 0.15, y: 0.2),
            (x: 0.1, y: 0.2),
            (x: 0.1, y: 0.1),
        ];
        let qp = quantize_polygon_or_dot(&poly, W, S, E, N);
        let tip_y = lat_to_tile_coord(0.25, S, N);
        assert!(
            !qp.exterior.iter().any(|&(_, y)| y == tip_y),
            "needle tip should be removed, got {:?}",
            qp.exterior
        );
        assert_eq!(qp.exterior.len(), 5);
        assert!(signed_area2(&qp.exterior) > 0);
    }

    #[test]
    fn multi_vertex_needle_unwinds_completely() {
        // The needle has an intermediate vertex (A -> B -> C -> B -> A); spike
        // removal must unwind it over successive passes.
        let poly = polygon![
            (x: 0.1, y: 0.1),
            (x: 0.2, y: 0.1),
            (x: 0.2, y: 0.2),
            (x: 0.15, y: 0.2),
            (x: 0.15, y: 0.22),
            (x: 0.15, y: 0.25),
            (x: 0.15, y: 0.22),
            (x: 0.15, y: 0.2),
            (x: 0.1, y: 0.2),
            (x: 0.1, y: 0.1),
        ];
        let qp = quantize_polygon_or_dot(&poly, W, S, E, N);
        let top_edge_y = lat_to_tile_coord(0.2, S, N);
        for &(_, y) in &qp.exterior {
            assert!(
                y >= top_edge_y.min(lat_to_tile_coord(0.1, S, N))
                    && y <= top_edge_y.max(lat_to_tile_coord(0.1, S, N)),
                "needle vertex survived: {:?}",
                qp.exterior
            );
        }
        assert!(signed_area2(&qp.exterior) > 0);
    }

    #[test]
    fn collinear_out_and_back_ring_is_collapsed_to_dot() {
        // Three distinct pixels, all on one row: nonzero vertex count but
        // zero area. Previously emitted as a degenerate (invalid) polygon.
        let poly = polygon![
            (x: 0.1, y: 0.5),
            (x: 0.9, y: 0.5),
            (x: 0.5, y: 0.5),
            (x: 0.1, y: 0.5),
        ];
        let qp = quantize_polygon_or_dot(&poly, W, S, E, N);
        assert_eq!(qp.exterior.len(), 4);
        assert!(signed_area2(&qp.exterior) > 0);
    }
}
