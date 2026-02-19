"""Normalized types for all availability providers. Same shape regardless of Resy/OpenTable/etc."""
import hashlib
from typing import Any

# Payload is a dict that must include at least:
#   - availability_times: list[str]  (e.g. "20:30:00" or "2026-02-18 20:30:00")
#   - resy_url or book_url: str      (booking link; feed/API normalize to resy_url)
# Optional: name, neighborhood, image_url, price_range, party_sizes_available, etc.


def slot_id(provider_id: str, venue_id: str, actual_time: str) -> str:
    """Stable slot key for diff: one id per provider + venue + time. 32-char hash."""
    raw = f"{provider_id}|{venue_id or ''}|{actual_time or ''}"
    return hashlib.sha256(raw.encode()).hexdigest()[:32]


def normalize_book_url(payload: dict[str, Any]) -> str | None:
    """Get booking URL from payload (resy_url or book_url)."""
    return payload.get("resy_url") or payload.get("book_url") if isinstance(payload, dict) else None


class NormalizedSlotResult:
    """One slot row returned by any provider. Used by fetch_for_bucket to build baseline/curr."""

    __slots__ = ("slot_id", "venue_id", "venue_name", "payload")

    def __init__(
        self,
        *,
        slot_id: str,
        venue_id: str,
        venue_name: str,
        payload: dict[str, Any],
    ):
        self.slot_id = slot_id
        self.venue_id = venue_id
        self.venue_name = venue_name
        self.payload = payload

    def to_row(self) -> dict[str, Any]:
        """Format for buckets: { slot_id, venue_id, venue_name, payload }."""
        return {
            "slot_id": self.slot_id,
            "venue_id": self.venue_id,
            "venue_name": self.venue_name,
            "payload": self.payload,
        }
