"""
Feed curation: ranked board, top opportunities, hot right now.

Moves logic from frontend to backend so the API returns ready-to-render segments.
Uses market-aware hotlists (NYC / Miami) from app.core.hotspots.
"""
from __future__ import annotations

from datetime import date, datetime, timedelta, timezone

from app.core.hotspots import is_hotspot, top_priority_names
from app.services.discovery.eligibility import (
    qualified_for_home_feed,
    rank_strength_multiplier,
    stronger_eligibility_evidence,
)
from app.services.discovery.feed_display import attach_feed_card_display_fields

TOP_OPPORTUNITIES_MAX = 4
HOT_RIGHT_NOW_MAX = 12
BRAND_NEW_SECONDS = 300
JUST_DROPPED_SECONDS = 600

# Strip before JSON responses — not part of the public contract.
_FEED_INTERNAL_KEYS = (
    "_priority",
    "_top_score",
    "_ticker_score",
    "_from_just_opened_contrib",
    "_has_still_open_contrib",
    "_snag_feed_qualified",
)


def sanitize_feed_cards_for_client(cards: list[dict]) -> None:
    """Remove internal ranking fields from card dicts (mutates in place)."""
    for c in cards:
        for k in _FEED_INTERNAL_KEYS:
            c.pop(k, None)


def _snag_score_display_int(top_raw: float) -> int:
    """
    Map _top_opportunity_score (additive model, typically ~0–9) to 1–99 for clients.
    Keeps spread without a fake floor: weak ≈ low 20s, iconic ≈ 90s.
    """
    r = max(0.0, float(top_raw))
    v = int(round(14.0 + r * 11.5))
    return min(99, max(1, v))


def attach_snag_display_scores(cards: list[dict]) -> None:
    """Set snag_score on each card from _top_opportunity_score (before sanitize strips _top_score)."""
    for c in cards:
        ts = c.get("_top_score")
        r = float(ts) if isinstance(ts, (int, float)) else 0.0
        c["snag_score"] = _snag_score_display_int(r)


def snag_feed_meta() -> dict:
    """Public contract hint for clients (live home feed, 14-day window)."""
    return {
        "version": "snag_live_feed_v1",
        "horizon_days": 14,
        "live_drops_key": "ranked_board",
        "mobile_note": (
            "When mobile=1, ranked_board is capped quality-ranked live drops "
            "(ticker_board slice from build_feed)."
        ),
    }


def _normalize_name(name: str | None) -> str:
    if not name or not isinstance(name, str):
        return ""
    return name.strip().lower()




def _venue_key(v: dict) -> str:
    return str(v.get("venue_id") or v.get("name") or "").strip() or "Venue"


def _earliest_slot_date(card: dict) -> date | None:
    """Earliest reservation date for this card (from date_str or slots)."""
    dates: list[str] = []
    if card.get("date_str"):
        dates.append(card["date_str"])
    for s in card.get("slots") or []:
        if isinstance(s, dict) and s.get("date_str"):
            dates.append(s["date_str"])
    if not dates:
        return None
    try:
        return min(date.fromisoformat(d.strip()) for d in dates if d and isinstance(d, str))
    except (ValueError, TypeError):
        return None


def likely_open_label(card: dict, today: date) -> str | None:
    """
    Return a short label for UI: "Will likely open today" / "Will likely open tomorrow" / "Will likely open soon"
    based on the card's earliest reservation date. Uses our slot dates (no prediction model).
    """
    earliest = _earliest_slot_date(card)
    if not earliest:
        return None
    if earliest == today:
        return "Will likely open today"
    tomorrow = today + timedelta(days=1)
    if earliest == tomorrow:
        return "Will likely open tomorrow"
    days_ahead = (earliest - today).days
    if 2 <= days_ahead <= 7:
        return "Will likely open soon"
    return None


def attach_likely_open_labels(cards: list[dict], today: date) -> None:
    """Set likely_open_label on each card in place."""
    for c in cards:
        c["likely_open_label"] = likely_open_label(c, today)


def _time_only(dt_str: str) -> str:
    """Extract time 'HH:MM' or 'HH:MM:SS' from 'YYYY-MM-DD HH:MM:SS'. Always present from just-opened."""
    if not dt_str or not isinstance(dt_str, str):
        return "—"
    s = dt_str.strip()
    if " " in s:
        s = s.split(" ", 1)[1]
    return s[:5] if len(s) >= 5 else s  # "16:30" or "16:30:00" -> "16:30"


def _first_time(venue: dict) -> str:
    times = venue.get("availability_times") or []
    if not times:
        return "—"
    return _time_only(times[0])


def _consolidate_cards(
    just_opened_flat: list[tuple[str, str, str, str | None, dict]],
    still_open_flat: list[tuple[str, str, str, str | None, dict]],
) -> list[dict]:
    """Group by venue name (normalized); one card per venue with slots[] and earliest detected_at."""
    by_name: dict[str, dict] = {}
    def _make_card(key: str, date_str: str, payload: dict) -> dict:
        return {
            "id": f"consolidated-{key}",
            "name": (payload.get("name") or "").strip() or key,
            # venue_id is Resy's stable ID — kept so metrics can be matched by ID not just name
            "venue_id": payload.get("venue_id"),
            "venueKey": key,
            "location": payload.get("neighborhood") or "NYC",
            "date_str": date_str,
            "slots": [],
            "party_sizes_available": list(payload.get("party_sizes_available") or []),
            "image_url": payload.get("image_url"),
            "created_at": payload.get("detected_at"),
            "detected_at": payload.get("detected_at"),
            "resy_popularity_score": payload.get("resy_popularity_score"),
            "rating_average": payload.get("rating_average"),
            "rating_count": payload.get("rating_count"),
            "market": payload.get("market") or "nyc",
            "resy_slug": payload.get("resy_slug"),
            "eligibility_evidence": payload.get("eligibility_evidence"),
            "user_facing_opened_at": payload.get("user_facing_opened_at"),
            "bucket_successful_poll_count": payload.get("bucket_successful_poll_count"),
            "_from_just_opened_contrib": False,
            "_has_still_open_contrib": False,
            "_snag_feed_qualified": False,
        }

    for item in just_opened_flat:
        key, date_str, time_str, resy_url, payload = item
        name = (payload.get("name") or "").strip() or key
        norm = _normalize_name(name) or key
        if norm not in by_name:
            by_name[norm] = _make_card(key, date_str, payload)
        card = by_name[norm]
        card["_from_just_opened_contrib"] = True
        ev = payload.get("eligibility_evidence")
        if ev:
            card["eligibility_evidence"] = stronger_eligibility_evidence(
                card.get("eligibility_evidence"), ev
            )
        ufo = payload.get("user_facing_opened_at")
        if ufo:
            cur = card.get("user_facing_opened_at")
            if not cur or ufo > cur:
                card["user_facing_opened_at"] = ufo
        bsp = payload.get("bucket_successful_poll_count")
        if bsp is not None:
            card["bucket_successful_poll_count"] = max(
                int(card.get("bucket_successful_poll_count") or 0),
                int(bsp or 0),
            )
        slot = {"date_str": date_str, "time": time_str, "resyUrl": resy_url}
        if not any(s.get("date_str") == date_str and s.get("time") == time_str for s in card["slots"]):
            card["slots"].append(slot)
        if payload.get("detected_at"):
            if not card.get("detected_at") or payload["detected_at"] < card["detected_at"]:
                card["detected_at"] = payload["detected_at"]
                card["created_at"] = payload["detected_at"]
        for ps in payload.get("party_sizes_available") or []:
            if ps not in card["party_sizes_available"]:
                card["party_sizes_available"].append(ps)
        # Carry venue_id from any slot that has it
        if payload.get("venue_id") and not card.get("venue_id"):
            card["venue_id"] = payload["venue_id"]

    for item in still_open_flat:
        key, date_str, time_str, resy_url, payload = item
        name = (payload.get("name") or "").strip() or key
        norm = _normalize_name(name) or key
        if norm not in by_name:
            by_name[norm] = _make_card(key, date_str, payload)
        card = by_name[norm]
        card["_has_still_open_contrib"] = True
        slot = {"date_str": date_str, "time": time_str, "resyUrl": resy_url}
        if not any(s.get("date_str") == date_str and s.get("time") == time_str for s in card["slots"]):
            card["slots"].append(slot)
        if payload.get("detected_at"):
            if not card.get("detected_at") or payload["detected_at"] < card["detected_at"]:
                card["detected_at"] = payload["detected_at"]
                card["created_at"] = payload["detected_at"]
        for ps in payload.get("party_sizes_available") or []:
            if ps not in card["party_sizes_available"]:
                card["party_sizes_available"].append(ps)
        if payload.get("venue_id") and not card.get("venue_id"):
            card["venue_id"] = payload["venue_id"]

    for card in by_name.values():
        if card.get("_from_just_opened_contrib"):
            card["_snag_feed_qualified"] = qualified_for_home_feed(
                card.get("eligibility_evidence"),
                card.get("bucket_successful_poll_count"),
            )

    # Sort slots by date then time; set resyUrl to first slot
    result = []
    for card in by_name.values():
        card["party_sizes_available"].sort()
        card["slots"].sort(key=lambda s: (s.get("date_str") or "", s.get("time") or ""))
        card["resyUrl"] = (card["slots"][0].get("resyUrl") if card["slots"] else None) or None
        result.append(card)
    return result


def _quality_score(card: dict, is_hot: bool) -> float:
    """
    Shared quality score: curated hotspot list + Resy popularity + rating.
    ``is_hot`` is **only** true when the venue is on our editorial hotlist (NYC_HOTSPOT_NAMES),
    not Resy popularity — that keeps "elite" / carousel badges aligned with the list.

    Weights (additive):
      hotspot    2.0   — on our curated hard-to-get list (is_hotspot)
      popularity ×1.5  — Resy's own demand signal
      quality    ×0.8  — Resy rating × review credibility
    """
    if not card.get("slots"):
        return 0.0

    hot        = 2.0 if is_hot else 0.0
    pop        = card.get("resy_popularity_score")
    popularity = float(pop) * 1.5 if isinstance(pop, (int, float)) and pop > 0 else 0.0
    rating     = card.get("rating_average") or 0
    count      = card.get("rating_count") or 0
    quality    = (float(rating) / 5.0) * min(1.0, count / 300) * 0.8

    return hot + popularity + quality


def _priority_score(card: dict, is_hot: bool) -> float:
    return _quality_score(card, is_hot)


def _ticker_score(card: dict, is_hot: bool) -> float:
    return _quality_score(card, is_hot)


def _rank_evidence_multiplier(card: dict) -> float:
    """Downrank just-opened cards with weaker diff evidence; still_open-only stays neutral."""
    if not card.get("_from_just_opened_contrib"):
        return 1.0
    return rank_strength_multiplier(card.get("eligibility_evidence"))


def _snag_include_in_live_segments(card: dict) -> bool:
    """Drop weak just-opened-only rows from ranked/ticker; still_open (or mixed) always kept."""
    if card.get("_has_still_open_contrib"):
        return True
    if not card.get("_from_just_opened_contrib"):
        return True
    return bool(card.get("_snag_feed_qualified"))


def _is_ticker_worthy(card: dict, is_hot: bool) -> bool:
    """
    Real-Time Ticker: only venues on the curated hotlist (same as feedHot).
    Padding to MIN_TICKER_ITEMS uses ranked_board below if the list is short.
    """
    if not card.get("slots"):
        return False
    return bool(is_hot)


def _top_opportunity_score(card: dict) -> float:
    """Top Drops score: same quality signal as the main feed."""
    return _quality_score(card, bool(card.get("feedHot")))


def build_feed(
    just_opened: list[dict],
    still_open: list[dict],
) -> dict:
    """
    Build feed segments from just_opened + still_open (by-date snapshot shape).
    Returns:
      - ranked_board: all cards sorted by priority (feed_hot set on each)
      - top_opportunities: up to 4 cards (priority names first, then hot, then fill)
      - hot_right_now: curated hotlist only (feedHot), excluding top_opportunities, max HOT_RIGHT_NOW_MAX
    """
    jo_flat: list[tuple[str, str, str, str | None, dict]] = []
    for day in just_opened or []:
        for v in day.get("venues") or []:
            if not isinstance(v, dict):
                continue
            key = _venue_key(v)
            date_str = day.get("date_str") or ""
            resy_url = v.get("resy_url") or v.get("book_url")
            payload = dict(v)
            payload["date_str"] = date_str
            payload["_from_just_opened"] = True
            times = v.get("availability_times") or []
            if not times:
                jo_flat.append((key, date_str, "—", resy_url, payload))
            else:
                for dt_str in times:
                    time_str = _time_only(dt_str)
                    jo_flat.append((key, date_str, time_str, resy_url, payload))

    so_flat: list[tuple[str, str, str, str | None, dict]] = []
    for day in still_open or []:
        for v in day.get("venues") or []:
            if not isinstance(v, dict):
                continue
            key = _venue_key(v)
            date_str = day.get("date_str") or ""
            resy_url = v.get("resy_url") or v.get("book_url")
            payload = dict(v)
            payload["date_str"] = date_str
            payload["_from_just_opened"] = False
            times = v.get("availability_times") or []
            if not times:
                so_flat.append((key, date_str, "—", resy_url, payload))
            else:
                for dt_str in times:
                    time_str = _time_only(dt_str)
                    so_flat.append((key, date_str, time_str, resy_url, payload))

    cards = _consolidate_cards(jo_flat, so_flat)
    cards = [c for c in cards if _snag_include_in_live_segments(c)]
    now_ts = datetime.now(timezone.utc)

    for c in cards:
        mkt = c.get("market") or "nyc"
        # feedHot: curated hotlist only (NYC_HOTSPOT_NAMES / is_hotspot). Do not use
        # Resy popularity here — it was marking random busy places as "hot".
        curated = is_hotspot(c.get("name"), mkt)
        c["feedHot"] = curated
        c["is_hotspot"] = curated
        c["_priority"] = _priority_score(c, curated) * _rank_evidence_multiplier(c)

    ranked = sorted(cards, key=lambda x: -(x.get("_priority") or 0))

    # Score every card for Top Drops (quality + scarcity, no freshness bias)
    for c in cards:
        c["_top_score"] = _top_opportunity_score(c)
    attach_snag_display_scores(cards)
    attach_feed_card_display_fields(cards, now_ts)
    quality_ranked = sorted(cards, key=lambda x: -(x.get("_top_score") or 0))

    # Top opportunities:
    #   1. Named priority restaurants (iconic / hardest-to-get) that are live right now
    #   2. Fill remaining slots from quality_ranked (best score first, no freshness bias)
    priority_picks = []
    used_ids: set[str] = set()
    for pname in top_priority_names("nyc"):
        if len(priority_picks) >= TOP_OPPORTUNITIES_MAX:
            break
        # Find the highest quality-scored match for this priority name.
        # Use word-level matching to avoid "misi" matching "misipasta" etc.
        for d in quality_ranked:
            if d.get("id") in used_ids:
                continue
            n = _normalize_name(d.get("name"))
            n_words = set(n.split())
            p_words = set(pname.split())
            # Match if all priority words appear as whole words in the venue name,
            # or the full priority string is a prefix/suffix of the venue name.
            word_match = p_words.issubset(n_words)
            phrase_match = (n == pname or n.startswith(pname + " ") or n.endswith(" " + pname))
            if word_match or phrase_match:
                priority_picks.append(d)
                used_ids.add(d["id"])
                break

    seen_ids = {d["id"] for d in priority_picks}
    top_list = list(priority_picks)

    # Fill remaining slots from quality_ranked — hotspot venues first, then best scored
    for d in quality_ranked:
        if len(top_list) >= TOP_OPPORTUNITIES_MAX:
            break
        if d["id"] not in seen_ids:
            top_list.append(d)
            seen_ids.add(d["id"])

    top_opportunities = top_list[:TOP_OPPORTUNITIES_MAX]
    top_ids = {d["id"] for d in top_opportunities}

    hot_only = [d for d in ranked if d.get("feedHot")]
    # Hottest carousel: hotlist venues only (no padding with Resy-"hot" or generic ranked cards).
    hot_right_now = [d for d in hot_only if d["id"] not in top_ids][:HOT_RIGHT_NOW_MAX]

    # Ticker board: quality-filtered subset for the Real-Time Ticker.
    # Only venues that pass _is_ticker_worthy(), sorted by _ticker_score.
    # Falls back to top-ranked if very few pass (keeps the ticker populated).
    ticker_worthy = [c for c in cards if _is_ticker_worthy(c, c.get("feedHot", False))]
    MIN_TICKER_ITEMS = 15
    if len(ticker_worthy) < MIN_TICKER_ITEMS:
        # Pad with best-ranked venues not already included
        ticker_ids = {c["id"] for c in ticker_worthy}
        for c in ranked:
            if len(ticker_worthy) >= MIN_TICKER_ITEMS:
                break
            if c["id"] not in ticker_ids:
                ticker_worthy.append(c)
                ticker_ids.add(c["id"])

    for c in ticker_worthy:
        c["_ticker_score"] = _ticker_score(c, c.get("feedHot", False)) * _rank_evidence_multiplier(
            c
        )
    ticker_board = sorted(ticker_worthy, key=lambda x: -(x.get("_ticker_score") or 0))

    return {
        "ranked_board": ranked,
        "ticker_board": ticker_board,
        "top_opportunities": top_opportunities,
        "hot_right_now": hot_right_now,
    }
