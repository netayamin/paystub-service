"""
Typed definitions for Resy API responses.

The venue search endpoint (POST /3/venuesearch/search) returns a list of hits.
Each hit has the shape described below; we extract a smaller venue object for
discovery and just-opened feeds, including a resy_url built from url_slug + location.
"""

from typing import Any, TypedDict


class ResySlotDate(TypedDict, total=False):
    """Slot date range from availability.slots[].date."""
    start: str  # e.g. "2026-02-18 20:30:00"
    end: str


class ResySlotConfig(TypedDict, total=False):
    """Slot config from availability.slots[].config (used for booking token)."""
    id: int
    token: str  # e.g. "rgs://resy/40703/1571962/2/2026-02-18/..."
    type: str  # e.g. "The Bar Room"


class ResySlot(TypedDict, total=False):
    """One availability slot from Resy search hit.availability.slots[]."""
    date: ResySlotDate
    config: ResySlotConfig
    has_add_ons: bool
    display_config: dict[str, Any]
    shift: dict[str, Any]
    is_global_dining_access: bool
    template: dict[str, Any]
    reservation_config: dict[str, Any]
    exclusive: dict[str, Any]


class ResyLocation(TypedDict, total=False):
    """Location object on a hit (city/region)."""
    name: str
    id: int
    code: str
    url_slug: str  # e.g. "new-york-ny" — used to build venue page URL


class ResySearchHit(TypedDict, total=False):
    """
    One hit from Resy venue search response (search.hits[]).
    Can be top-level venue (id, name, url_slug, location, availability) or nested under "venue".
    """
    id: int | dict[str, Any]  # sometimes {"resy": 60029}
    name: str
    url_slug: str  # venue slug for URL, e.g. "le-gratin"
    location: ResyLocation
    neighborhood: str
    availability: dict[str, Any]  # { "slots": ResySlot[] }
    venue: dict[str, Any]  # optional nested venue object
    images: list[str]
    hero_image: str
    image_url: str
    slug: str
    url: str
    resy_url: str


class ResyVenueExtract(TypedDict, total=False):
    """
    Extracted venue we return from search_with_availability and store in discovery.
    Used by just-opened feed; resy_url is the Resy booking page for this venue/date/party_size.
    """
    name: str
    neighborhood: str
    availability_times: list[str]
    venue_id: str | int
    image_url: str
    resy_slug: str
    resy_url: str
    detected_at: str
    party_sizes_available: list[int]
