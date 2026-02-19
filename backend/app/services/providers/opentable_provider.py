"""OpenTable availability provider. Uses MultiSearchResults GQL endpoint."""
import logging
from typing import Any

import httpx

from app.services.providers.types import NormalizedSlotResult, slot_id

logger = logging.getLogger(__name__)

OT_GQL_URL = "https://www.opentable.com/dapi/fe/gql?optype=query&opname=MultiSearchResults"
OT_OPERATION_HASH = "0c6adc98c9f25677df52a71550a3dfe63cd72c1c1167a04af83a4dd141f2f33c"

# Default NYC (Manhattan)
DEFAULT_LAT = 40.747654
DEFAULT_LON = -73.98629
DEFAULT_METRO_ID = 8


def _build_body(date_str: str, time_param: str, party_size: int) -> dict:
    variables = {
        "backwardMinutes": 180,
        "diningType": "ALL",
        "forwardMinutes": 180,
        "groupsRids": False,
        "isAffiliateSearch": False,
        "isRestrefRequest": False,
        "maxCarouselResults": 3,
        "maxSearchResults": 50,
        "skipCarouselResults": 3,
        "skipSearchResults": 0,
        "sortBy": "WEB_CONVERSION",
        "withAnytimeAvailability": True,
        "withCarouselResults": True,
        "withFallbackToListingMode": False,
        "shouldShowHighlights": True,
        "latitude": DEFAULT_LAT,
        "longitude": DEFAULT_LON,
        "date": date_str,
        "debug": False,
        "device": "desktop",
        "metroId": DEFAULT_METRO_ID,
        "originalTerm": "Manhattan",
        "partySize": party_size,
        "time": time_param,
        "tld": "com",
        "userLatitude": DEFAULT_LAT,
        "userLongitude": DEFAULT_LON,
        "countryCode": "US",
    }
    return {
        "operationName": "MultiSearchResults",
        "variables": variables,
        "extensions": {"persistedQuery": {"version": 1, "sha256Hash": OT_OPERATION_HASH}},
    }


def _parse_response(
    data: dict[str, Any],
    provider_id: str,
    time_param: str,
    party_size: int,
) -> list[NormalizedSlotResult]:
    """Parse OpenTable GQL response into normalized slots. Safe for any dict shape."""
    if not isinstance(data, dict):
        return []
    restaurants = (
        (data.get("data") or {})
        .get("restaurantSearchV2", {})
        .get("searchResults", {})
        .get("restaurants") or []
    )
    if not isinstance(restaurants, list):
        restaurants = []
    results: list[NormalizedSlotResult] = []
    for r in restaurants:
        try:
            if not isinstance(r, dict):
                continue
            rid = r.get("restaurantId")
            name = (r.get("name") or "").strip()
            if not name:
                continue
            vid = str(rid) if rid is not None else name
            actual_time = time_param
            sid = slot_id(provider_id, vid, actual_time)
            urls = r.get("urls") or {}
            profile = urls.get("profileLink") or {}
            book_url = (profile.get("link") or "").strip()
            if book_url and not book_url.startswith("http"):
                book_url = ("https://www.opentable.com" + book_url) if book_url.startswith("/") else ("https://www.opentable.com/" + book_url)
            neighborhood = ""
            nb = r.get("neighborhood")
            if isinstance(nb, dict):
                neighborhood = (nb.get("name") or "").strip()
            image_url = ""
            photos = r.get("photos") or {}
            pv3 = photos.get("profileV3") or {}
            med = pv3.get("medium") or pv3.get("legacy") or pv3.get("small")
            if isinstance(med, dict) and med.get("url"):
                image_url = (med.get("url") or "").strip()
                if image_url and not image_url.startswith("http"):
                    image_url = "https:" + image_url
            price_band = r.get("priceBand") or {}
            price_range = (price_band.get("name") or "").strip() if isinstance(price_band, dict) else ""
            payload: dict[str, Any] = {
                "name": name,
                "neighborhood": neighborhood,
                "availability_times": [actual_time],
                "book_url": book_url or None,
                "resy_url": book_url or None,
                "image_url": image_url or None,
                "price_range": price_range or None,
                "party_sizes_available": [party_size],
            }
            results.append(
                NormalizedSlotResult(
                    slot_id=sid,
                    venue_id=vid,
                    venue_name=name,
                    payload=payload,
                )
            )
        except Exception as e:
            logger.debug("OpenTable skip malformed restaurant: %s", e)
            continue
    return results


class OpenTableProvider:
    provider_id = "opentable"

    async def search_availability_async(
        self,
        date_str: str,
        time_slot: str,
        party_sizes: list[int],
    ) -> list[NormalizedSlotResult]:
        """Async fetch: does not block the event loop. Use from API routes."""
        party_size = party_sizes[0] if party_sizes else 2
        time_param = time_slot.strip() if time_slot else "19:30"
        if len(time_param) == 5 and ":" in time_param:
            time_param = time_param + ":00"
        body = _build_body(date_str, time_param, party_size)
        try:
            async with httpx.AsyncClient(timeout=30.0) as client:
                resp = await client.post(OT_GQL_URL, json=body)
                resp.raise_for_status()
                data = resp.json()
        except Exception as e:
            logger.warning("OpenTable search failed: %s", e)
            return []
        return _parse_response(data, self.provider_id, time_param, party_size)

    def search_availability(
        self,
        date_str: str,
        time_slot: str,
        party_sizes: list[int],
    ) -> list[NormalizedSlotResult]:
        """Sync fetch for use in sync jobs (e.g. discovery buckets)."""
        party_size = party_sizes[0] if party_sizes else 2
        time_param = time_slot.strip() if time_slot else "19:30"
        if len(time_param) == 5 and ":" in time_param:
            time_param = time_param + ":00"
        body = _build_body(date_str, time_param, party_size)
        try:
            with httpx.Client(timeout=30.0) as client:
                resp = client.post(OT_GQL_URL, json=body)
                resp.raise_for_status()
                data = resp.json()
        except Exception as e:
            logger.warning("OpenTable search failed: %s", e)
            return []
        return _parse_response(data, self.provider_id, time_param, party_size)
