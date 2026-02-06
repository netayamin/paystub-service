"""Resy API client: lowest level, sends request only. No validation."""
import json
from typing import Any

import httpx

from app.services.resy.config import ResyConfig, VENUE_SEARCH_TEST_BOUNDING_BOX


class ResyClient:
    """Resy venue search and book client."""

    def __init__(self, config: ResyConfig | None = None) -> None:
        self._config = config or ResyConfig()

    def _credentials_error(self) -> dict[str, Any]:
        return {"error": "Resy credentials not configured. Add RESY_API_KEY and RESY_AUTH_TOKEN to .env."}

    def _headers_no_content_type(self) -> dict[str, str]:
        """Headers without Content-Type so we can send form-encoded body."""
        h = self._config.headers()
        return {k: v for k, v in h.items() if k.lower() != "content-type"}

    def _post(self, path: str, json_body: dict[str, Any], *, timeout: float = 20.0) -> dict[str, Any]:
        if not self._config.is_configured():
            return self._credentials_error()
        url = f"{self._config.base_url}{path}"
        try:
            with httpx.Client(timeout=timeout) as c:
                r = c.post(url, json=json_body, headers=self._config.headers())
        except Exception as e:
            return {"error": str(e)}
        if not r.is_success:
            return {"error": f"Resy API error: {r.status_code}", "detail": (r.text[:500] if r.text else None)}
        try:
            return r.json() if r.content else {}
        except Exception:
            return {"_raw_body": (r.text[:2000] if r.text else "")}

    def _post_form(
        self, path: str, data: dict[str, str], *, timeout: float = 20.0
    ) -> dict[str, Any]:
        """POST with application/x-www-form-urlencoded body (e.g. for /3/book)."""
        if not self._config.is_configured():
            return self._credentials_error()
        url = f"{self._config.base_url}{path}"
        headers = self._headers_no_content_type()
        try:
            with httpx.Client(timeout=timeout) as c:
                r = c.post(url, data=data, headers=headers)
        except Exception as e:
            return {"error": str(e)}
        if not r.is_success:
            return {"error": f"Resy API error: {r.status_code}", "detail": (r.text[:500] if r.text else None)}
        try:
            return r.json() if r.content else {}
        except Exception:
            return {"_raw_body": (r.text[:2000] if r.text else "")}

    def book(
        self,
        book_token: str,
        payment_method_id: int,
        *,
        source_id: str = "resy.com-venue-details",
        venue_marketing_opt_in: bool = True,
        rwg_token: str | None = None,
        merchant_changed: str = "1",
    ) -> dict[str, Any]:
        """Book a reservation. book_token must come from Resy's find/slot-details endpoint (see docs/RESY_BOOK.md)."""
        data: dict[str, str] = {
            "book_token": book_token,
            "struct_payment_method": json.dumps({"id": payment_method_id}),
            "source_id": source_id,
            "venue_marketing_opt_in": "1" if venue_marketing_opt_in else "0",
            "merchant_changed": merchant_changed,
        }
        if rwg_token:
            data["rwg_token"] = rwg_token
        return self._post_form("/3/book", data)

    def search_with_availability(
        self,
        day: str,
        party_size: int = 2,
        *,
        query: str = "",
        per_page: int = 100,
        max_pages: int = 5,
        time_filter: str | None = None,
        venue_filter: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        """POST venue search; uses API response total_pages to fetch all pages, returns merged hits. Capped at max_pages (default 5 = up to 500)."""
        slot_filter: dict[str, Any] = {"day": day, "party_size": party_size}
        if time_filter:
            slot_filter["time_filter"] = time_filter
        all_hits: list[dict[str, Any]] = []
        page_num = 1
        total_pages = 1
        while page_num <= total_pages and page_num <= max_pages:
            payload: dict[str, Any] = {
                "availability": True,
                "page": page_num,
                "per_page": per_page,
                "slot_filter": slot_filter,
                "types": ["venue"],
                "order_by": "availability",
                "geo": {"bounding_box": VENUE_SEARCH_TEST_BOUNDING_BOX},
                "query": query,
            }
            if venue_filter:
                payload["venue_filter"] = venue_filter
            raw = self._post("/3/venuesearch/search", payload)
            if raw.get("error"):
                if all_hits:
                    return {"search": {"hits": all_hits}}
                return raw
            search = raw.get("search") or {}
            hits = search.get("hits") or []
            all_hits.extend(hits)
            if page_num == 1:
                # API may return total_pages at top level, in search, or in search.pagination
                pagination = search.get("pagination") or {}
                api_total = (
                    raw.get("total_pages")
                    or search.get("total_pages")
                    or pagination.get("total_pages")
                )
                if api_total is not None:
                    total_pages = min(int(api_total), max_pages)
                else:
                    total_pages = max_pages
            # If we got a full page, there may be more (fallback when API omits total_pages)
            if page_num == total_pages and len(hits) >= per_page and page_num < max_pages:
                total_pages = page_num + 1
            if page_num >= total_pages:
                break
            page_num += 1
        return {"search": {"hits": all_hits}}
