"""Regression tests for issue #13: thin polygons must not flicker across zooms.

Sub-pixel-width polygons used to collapse on the integer tile grid at some
zoom levels (depending on how their edges landed on the grid) and get dropped,
so features flickered in and out as the map zoomed. They are now replaced by a
one-pixel square at their centroid, and ring winding is normalized so decoded
polygons are valid.
"""

import gzip
import math

import geopandas as gpd
import pytest
from shapely.geometry import box, shape

from freestiler import freestile

pmtiles_reader = pytest.importorskip("pmtiles.reader")
mvt = pytest.importorskip("mapbox_vector_tile")

LAT, LON = 43.41, -90.239


def _tile_xy(lon, lat, z):
    n = 2**z
    return (
        int((lon + 180) / 360 * n),
        int((1 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2 * n),
    )


def _features_per_zoom(path, name, zooms):
    """Map zoom -> decoded shapely geometry for the named feature (or None)."""
    out = {}
    with open(path, "rb") as f:
        reader = pmtiles_reader.Reader(pmtiles_reader.MmapSource(f))
        for z in zooms:
            found = None
            cx, cy = _tile_xy(LON, LAT, z)
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    raw = reader.get(z, cx + dx, cy + dy)
                    if not raw:
                        continue
                    layers = mvt.decode(gzip.decompress(raw))
                    for ft in layers.get("layer", {}).get("features", []):
                        if ft["properties"].get("name") == name:
                            g = shape(ft["geometry"])
                            if not g.is_empty:
                                found = g
            out[z] = found
    return out


def test_thin_strip_present_at_every_zoom(tmp_path):
    dlon = 1.0 / (111_320 * math.cos(math.radians(LAT)))
    dlat = 1.0 / 110_540
    strip = box(LON, LAT, LON + 1500 * dlon, LAT + 30 * dlat)  # 30 m wide
    block = box(LON, LAT - 400 * dlat, LON + 400 * dlon, LAT - 50 * dlat)
    gdf = gpd.GeoDataFrame(
        {"name": ["thin_strip_30m", "normal_block"]},
        geometry=[strip, block],
        crs="EPSG:4326",
    )

    output = tmp_path / "thin.pmtiles"
    freestile(
        gdf,
        output,
        layer_name="layer",
        min_zoom=4,
        max_zoom=14,
        tile_format="mvt",
        quiet=True,
    )

    zooms = range(4, 15)
    for name in ("thin_strip_30m", "normal_block"):
        per_zoom = _features_per_zoom(output, name, zooms)
        for z, geom in per_zoom.items():
            assert geom is not None, f"{name} missing at zoom {z}"
            assert geom.is_valid, f"{name} invalid at zoom {z}"
            assert geom.area > 0, f"{name} zero-area at zoom {z}"
