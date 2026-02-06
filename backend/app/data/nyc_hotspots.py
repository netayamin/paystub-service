"""
NYC restaurant hotspots / hardest reservations on Resy.
Venue IDs can be found from Resy URLs (e.g. resy.com/cities/ny/places/12345) or browser network tab.
Add or edit entries; names are for display, venue_id is what the API uses.
"""
from typing import TypedDict


class Hotspot(TypedDict):
    venue_id: int
    name: str
    slug: str
    note: str


# Famous NYC spots (venue_id are placeholders – replace with real IDs from Resy)
NYC_HOTSPOTS: list[Hotspot] = [
    {"venue_id": 35676, "name": "Cote", "slug": "cote", "note": "Korean steakhouse"},
    {"venue_id": 12345, "name": "Carbone", "slug": "carbone", "note": "Italian, very hard"},
    {"venue_id": 23456, "name": "Don Angie", "slug": "don-angie", "note": "Italian"},
    {"venue_id": 34567, "name": "Four Horsemen", "slug": "four-horsemen", "note": "Wine bar"},
    {"venue_id": 45678, "name": "Via Carota", "slug": "via-carota", "note": "Italian"},
    {"venue_id": 56789, "name": "Lilia", "slug": "lilia", "note": "Italian"},
    {"venue_id": 67890, "name": "Dame", "slug": "dame", "note": "Seafood"},
    {"venue_id": 78901, "name": "Torrisi", "slug": "torrisi", "note": "Italian"},
    {"venue_id": 89012, "name": "Sushi Noz", "slug": "sushi-noz", "note": "Omakase"},
    {"venue_id": 90123, "name": "Le Bernardin", "slug": "le-bernardin", "note": "Fine dining"},
]


def get_hotspots() -> list[dict]:
    """Return hotspots for agent/API (list of dicts)."""
    return [dict(h) for h in NYC_HOTSPOTS]


def get_venue_id_by_name_or_slug(name_or_slug: str) -> int | None:
    """Resolve venue by name or slug (case-insensitive)."""
    key = name_or_slug.strip().lower()
    for h in NYC_HOTSPOTS:
        if key in (h["name"].lower(), h["slug"].lower()):
            return h["venue_id"]
    return None
