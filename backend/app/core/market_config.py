"""
Market (city) configuration.  Defines search areas for discovery.

Active markets are controlled by the DISCOVERY_MARKETS env var (comma-separated
slugs).  Defaults to "nyc" only for backward compatibility.

Bounding boxes can be overridden per-market via
  DISCOVERY_MARKET_{SLUG}_BOX=south_lat,west_lng,north_lat,east_lng
e.g.  DISCOVERY_MARKET_MIAMI_BOX=25.68,-80.32,25.92,-80.10

To enable Miami Beach add to backend/.env:
  DISCOVERY_MARKETS=nyc,miami
"""
from __future__ import annotations

import logging
import os
from dataclasses import dataclass

_log = logging.getLogger(__name__)


@dataclass(frozen=True)
class Market:
    slug: str           # short id used as bucket_id prefix, e.g. "nyc", "miami"
    display_name: str   # human-readable label returned in API responses
    bounding_box: tuple # (south_lat, west_lng, north_lat, east_lng)
    timezone: str       # IANA timezone for "today" computation
    location_slug: str  # Resy city slug used when building venue page URLs


# Built-in market definitions.  Override bounding_box via env var.
BUILTIN_MARKETS: dict[str, Market] = {
    "nyc": Market(
        slug="nyc",
        display_name="New York City",
        bounding_box=(40.691, -74.030, 40.882, -73.910),
        timezone="America/New_York",
        location_slug="new-york-ny",
    ),
    "miami": Market(
        slug="miami",
        display_name="Miami Beach & Surrounding",
        # Covers South Beach, Mid Beach, North Beach, Wynwood, Brickell,
        # Downtown Miami, Coral Gables, and surrounding dining corridors.
        bounding_box=(25.700, -80.320, 25.920, -80.115),
        timezone="America/New_York",
        location_slug="miami-fl",
    ),
}


def _parse_box(val: str) -> tuple[float, float, float, float] | None:
    """Parse "s,w,n,e" env value into a 4-float tuple."""
    try:
        parts = [float(x.strip()) for x in val.split(",")]
        if len(parts) == 4:
            return tuple(parts)  # type: ignore[return-value]
    except ValueError:
        pass
    return None


def get_market(slug: str) -> Market:
    """Return Market for slug, applying any bounding-box override from env."""
    base = BUILTIN_MARKETS.get(slug)
    if base is None:
        raise KeyError(
            f"Unknown market slug {slug!r}.  "
            f"Available: {list(BUILTIN_MARKETS)}.  "
            "Add it to BUILTIN_MARKETS in market_config.py to register a new city."
        )
    env_key = f"DISCOVERY_MARKET_{slug.upper()}_BOX"
    override_raw = os.environ.get(env_key, "").strip()
    if override_raw:
        parsed = _parse_box(override_raw)
        if parsed:
            return Market(
                slug=base.slug,
                display_name=base.display_name,
                bounding_box=parsed,
                timezone=base.timezone,
                location_slug=base.location_slug,
            )
        _log.warning(
            "%s=%r is invalid (expected 4 floats: south,west,north,east); "
            "using default bounding box for %s",
            env_key, override_raw, slug,
        )
    return base


def get_active_markets() -> list[Market]:
    """
    Return active Market objects in the order listed in DISCOVERY_MARKETS.
    Defaults to [nyc] when the env var is not set.
    """
    raw = os.environ.get("DISCOVERY_MARKETS", "nyc").strip()
    slugs = [s.strip() for s in raw.split(",") if s.strip()]
    if not slugs:
        slugs = ["nyc"]
    markets: list[Market] = []
    for s in slugs:
        try:
            markets.append(get_market(s))
        except KeyError:
            _log.warning("DISCOVERY_MARKETS: unknown market %r — skipping", s)
    if not markets:
        _log.warning("DISCOVERY_MARKETS resolved to nothing; falling back to nyc")
        markets = [get_market("nyc")]
    return markets


def market_slugs() -> list[str]:
    """Return active market slugs (convenience helper)."""
    return [m.slug for m in get_active_markets()]
