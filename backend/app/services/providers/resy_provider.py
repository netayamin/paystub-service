"""Resy availability provider. Inclusive merged hits for opportunity state + bookable slots for discovery."""
from datetime import date

from app.core.discovery_config import DISCOVERY_RESY_MAX_PAGES, DISCOVERY_RESY_PER_PAGE
from app.services.providers.types import NormalizedSlotResult, PollAvailabilityOutcome, slot_id
from app.services.resy import _extract_venue, _has_availability, fetch_inclusive_merged_hits


class ResyProvider:
    provider_id = "resy"

    def search_availability(
        self,
        date_str: str,
        time_slot: str,
        party_sizes: list[int],
        market: str = "nyc",
    ) -> PollAvailabilityOutcome:
        """Fetch Resy: full merged hit list (BOOKABLE + UNBOOKABLE) plus normalized bookable slots."""
        from app.services.resy.config import get_bounding_box_for_market

        bbox = get_bounding_box_for_market(market)

        try:
            day = date.fromisoformat(date_str)
        except ValueError:
            return PollAvailabilityOutcome(slots=[], raw_merged_hits=[], raw_error_count=0)

        merged, err_count = fetch_inclusive_merged_hits(
            day,
            party_sizes,
            time_filter=time_slot,
            time_window_hours=1,
            per_page=DISCOVERY_RESY_PER_PAGE,
            max_pages=DISCOVERY_RESY_MAX_PAGES,
            bounding_box=bbox,
        )

        ps0 = party_sizes[0] if party_sizes else 2
        by_slot: dict[str, NormalizedSlotResult] = {}
        for h in merged:
            if not _has_availability(h):
                continue
            v = _extract_venue(h, date_str=date_str, party_size=ps0)
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
                        set(existing.get("party_sizes_available") or []) | {int(p) for p in party_sizes if p}
                    )
                    continue
                payload = dict(v)
                payload["availability_times"] = [actual_time]
                payload["party_sizes_available"] = sorted({int(p) for p in party_sizes if p})
                payload["market"] = market
                if "resy_url" not in payload and "book_url" not in payload:
                    payload["book_url"] = payload.get("resy_url")
                by_slot[sid] = NormalizedSlotResult(
                    slot_id=sid,
                    venue_id=vid,
                    venue_name=name,
                    payload=payload,
                )

        return PollAvailabilityOutcome(
            slots=list(by_slot.values()),
            raw_merged_hits=merged,
            raw_error_count=err_count,
        )
