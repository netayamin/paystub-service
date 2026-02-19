"""Resy availability provider. Wraps existing search_with_availability and normalizes to slots."""
from datetime import date

from app.core.discovery_config import DISCOVERY_RESY_MAX_PAGES, DISCOVERY_RESY_PER_PAGE
from app.services.providers.types import NormalizedSlotResult, slot_id
from app.services.resy import search_with_availability


class ResyProvider:
    provider_id = "resy"

    def search_availability(
        self,
        date_str: str,
        time_slot: str,
        party_sizes: list[int],
    ) -> list[NormalizedSlotResult]:
        """Fetch Resy availability and return one NormalizedSlotResult per (venue, time) slot."""
        try:
            day = date.fromisoformat(date_str)
        except ValueError:
            return []
        by_slot: dict[str, NormalizedSlotResult] = {}
        for party_size in party_sizes:
            result = search_with_availability(
                day,
                party_size,
                query="",
                time_filter=time_slot,
                time_window_hours=3,
                per_page=DISCOVERY_RESY_PER_PAGE,
                max_pages=DISCOVERY_RESY_MAX_PAGES,
            )
            if result.get("error"):
                continue
            for v in result.get("venues") or []:
                vid = str(v.get("venue_id") or v.get("name") or "")
                name = (v.get("name") or "").strip()
                times = v.get("availability_times") or []
                for actual_time in times:
                    if not actual_time or not isinstance(actual_time, str):
                        continue
                    actual_time = actual_time.strip()
                    sid = slot_id(self.provider_id, vid, actual_time)
                    if sid in by_slot:
                        existing = by_slot[sid].payload
                        existing["party_sizes_available"] = sorted(
                            set(existing.get("party_sizes_available") or []) | {party_size}
                        )
                        continue
                    payload = dict(v)
                    payload["availability_times"] = [actual_time]
                    payload["party_sizes_available"] = [party_size]
                    if "resy_url" not in payload and "book_url" not in payload:
                        payload["book_url"] = payload.get("resy_url")
                    by_slot[sid] = NormalizedSlotResult(
                        slot_id=sid,
                        venue_id=vid,
                        venue_name=name,
                        payload=payload,
                    )
        return list(by_slot.values())
