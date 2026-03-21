"""
Feed curation: ranked board, top opportunities, hot right now.

Moves logic from frontend to backend so the API returns ready-to-render segments.
Uses market-aware hotlists (NYC / Miami) from app.core.hotspots.
"""
from __future__ import annotations

from datetime import date, datetime, timedelta, timezone

from app.core.hotspots import is_hotspot, top_priority_names

TOP_OPPORTUNITIES_MAX = 4
HOT_RIGHT_NOW_MAX = 12
HOT_RIGHT_NOW_COLS = 5  # frontend grid columns; pad so last row is full
MIN_SECOND_ROW_CARDS = 8  # at least 2 rows
BRAND_NEW_SECONDS = 300
JUST_DROPPED_SECONDS = 600


def _normalize_name(name: str | None) -> str:
    if not name or not isinstance(name, str):
        return ""
    return name.strip().lower()


def is_hot_restaurant(name: str | None, market: str = "nyc") -> bool:
    return is_hotspot(name, market)



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
        }

    for item in just_opened_flat:
        key, date_str, time_str, resy_url, payload = item
        name = (payload.get("name") or "").strip() or key
        norm = _normalize_name(name) or key
        if norm not in by_name:
            by_name[norm] = _make_card(key, date_str, payload)
        card = by_name[norm]
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

    # Sort slots by date then time; set resyUrl to first slot
    result = []
    for card in by_name.values():
        card["party_sizes_available"].sort()
        card["slots"].sort(key=lambda s: (s.get("date_str") or "", s.get("time") or ""))
        card["resyUrl"] = (card["slots"][0].get("resyUrl") if card["slots"] else None) or None
        result.append(card)
    return result


def _normalize_rarity(raw) -> float:
    """
    rarity_score is stored on a 0-100 scale (100 / (1 + drops_per_day)).
    Normalize to 0-1 for scoring so all additive/multiplicative weights
    stay in the same magnitude as the hotspot bonus (2.0) and quality (~0-1).
    """
    if not isinstance(raw, (int, float)) or raw <= 0:
        return 0.0
    return min(1.0, float(raw) / 100.0)


def _speed_bonus(avg_duration_seconds) -> float:
    """
    Reward venues whose drops disappear fast — a proxy for real-time demand.
    Drops gone in <5 min → full bonus 0.5; gone in >60 min → no bonus.
    Returns 0.0 if data is unavailable.
    """
    if not isinstance(avg_duration_seconds, (int, float)) or avg_duration_seconds <= 0:
        return 0.0
    minutes = float(avg_duration_seconds) / 60.0
    if minutes <= 5:
        return 0.5
    if minutes <= 15:
        return 0.35
    if minutes <= 30:
        return 0.2
    if minutes <= 60:
        return 0.05
    return 0.0


def _priority_score(card: dict, is_hot: bool) -> float:
    """
    General ranked-board score: freshness × scarcity × availability × popularity.

    rarity_score is stored 0-100; normalised to 0-1 before use so the
    hotspot bonus (2.5) and popularity multiplier remain meaningful.
    """
    rarity = _normalize_rarity(card.get("rarity_score"))
    if rarity > 0:
        scarcity = 1.0 + rarity * 3.0  # range 1.0 – 4.0
    else:
        scarcity = 2.5 if is_hot else 1.0

    availability = 1.0 if card.get("slots") else 0.01

    detected = card.get("detected_at") or card.get("created_at")
    if detected:
        try:
            dt = datetime.fromisoformat(detected.replace("Z", "+00:00"))
            if dt.tzinfo is None:
                dt = dt.replace(tzinfo=timezone.utc)
            minutes_ago = (datetime.now(timezone.utc) - dt).total_seconds() / 60
        except Exception:
            minutes_ago = 999
    else:
        minutes_ago = 999

    # Freshness: strong boost for "just dropped" (< 10 min) so they always surface
    if minutes_ago <= 10:
        freshness = 2.0
    elif minutes_ago <= 30:
        freshness = 1.5
    else:
        freshness = 1.0 / (1.0 + minutes_ago / 60)

    pop = card.get("resy_popularity_score")
    popularity = (0.5 + float(pop)) if isinstance(pop, (int, float)) else 1.0

    return scarcity * availability * freshness * popularity


def _ticker_score(card: dict, is_hot: bool) -> float:
    """
    Score for the Real-Time Ticker ranked board.
    Balances quality (hotspot + rarity + popularity + rating + speed) with
    a modest freshness bonus so genuinely new availability surfaces without
    letting unknown restaurants dominate.

    Weights (additive):
      hotspot    2.0   — on our curated hard-to-get list
      rarity    ×1.5   — rarity_score normalised 0-1
      popularity×1.2   — Resy demand signal
      quality   ×0.8   — rating × credibility (review count)
      speed      0-0.5 — how fast the drop disappears (demand proxy)
      freshness  0-0.5 — small boost for < 15 min; decays to 0 after 1 h
    """
    if not card.get("slots"):
        return 0.0

    hot        = 2.0 if is_hot else 0.0
    scarcity   = _normalize_rarity(card.get("rarity_score")) * 1.5
    pop        = card.get("resy_popularity_score")
    popularity = float(pop) * 1.2 if isinstance(pop, (int, float)) and pop > 0 else 0.0
    rating     = card.get("rating_average") or 0
    count      = card.get("rating_count") or 0
    quality    = (float(rating) / 5.0) * min(1.0, count / 300) * 0.8
    speed      = _speed_bonus(card.get("avg_drop_duration_seconds"))

    detected = card.get("detected_at") or card.get("created_at")
    if detected:
        try:
            dt = datetime.fromisoformat(detected.replace("Z", "+00:00"))
            if dt.tzinfo is None:
                dt = dt.replace(tzinfo=timezone.utc)
            mins = (datetime.now(timezone.utc) - dt).total_seconds() / 60
        except Exception:
            mins = 999
    else:
        mins = 999
    freshness = 0.5 if mins <= 15 else (0.3 if mins <= 60 else 0.0)

    return hot + scarcity + popularity + quality + speed + freshness


def _is_ticker_worthy(card: dict, is_hot: bool) -> bool:
    """
    Returns True if a venue deserves to appear in the Real-Time Ticker.
    Hotspot restaurants always qualify. Others must pass at least one
    quality signal so unknown low-demand restaurants are filtered out.
    rarity_score thresholds use the 0-100 stored scale (not normalised).
    """
    if not card.get("slots"):
        return False
    if is_hot:
        return True  # our curated list always qualifies

    pop = card.get("resy_popularity_score")
    if isinstance(pop, (int, float)) and pop >= 0.25:
        return True

    # rarity_score stored 0-100; threshold 20/100 = 0.20 normalised
    rarity = card.get("rarity_score")
    if isinstance(rarity, (int, float)) and rarity >= 20:
        return True

    rating = card.get("rating_average") or 0
    count  = card.get("rating_count") or 0
    if float(rating) >= 4.3 and count >= 80:
        return True

    return False


def _top_opportunity_score(card: dict) -> float:
    """
    Score for Top Drops (Crown Jewels) section: quality + scarcity, NOT freshness.

    We deliberately ignore when a slot was detected so that a random
    low-quality restaurant freshly detected 2 minutes ago never outranks
    an iconic hard-to-get restaurant detected 20 minutes ago.

    Factors (additive, all 0-based):
      • hotspot bonus  — curated hard-to-get list                (0 or 2.0)
      • rarity         — rarity_score normalised 0-1             (×2.0, max 2.0)
      • speed          — drop disappears fast = real demand       (0–0.5)
      • popularity     — Resy's own demand signal                 (×1.5, max ~1.5)
      • quality        — rating × review credibility              (max ~0.9)
    """
    if not card.get("slots"):
        return 0.0

    hot_bonus  = 2.0 if card.get("feedHot") else 0.0
    scarcity   = _normalize_rarity(card.get("rarity_score")) * 2.0
    speed      = _speed_bonus(card.get("avg_drop_duration_seconds"))
    pop        = card.get("resy_popularity_score")
    popularity = float(pop) * 1.5 if isinstance(pop, (int, float)) and pop > 0 else 0.0
    rating     = card.get("rating_average") or 0
    count      = card.get("rating_count") or 0
    credibility = min(1.0, count / 300)
    quality    = (float(rating) / 5.0) * credibility

    return hot_bonus + scarcity + speed + popularity + quality


def build_feed(
    just_opened: list[dict],
    still_open: list[dict],
) -> dict:
    """
    Build feed segments from just_opened + still_open (by-date snapshot shape).
    Returns:
      - ranked_board: all cards sorted by priority (feed_hot set on each)
      - top_opportunities: up to 4 cards (priority names first, then hot, then fill)
      - hot_right_now: hot cards excluding top_opportunities, deduped by name, max HOT_RIGHT_NOW_MAX
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
    now_ts = datetime.now(timezone.utc)

    for c in cards:
        mkt = c.get("market") or "nyc"
        # Hybrid feedHot: curated editorial list OR strong data signals.
        # This means unlisted restaurants with proven Resy demand also surface.
        curated = is_hot_restaurant(c.get("name"), mkt)
        pop = c.get("resy_popularity_score")
        rarity = c.get("rarity_score")
        rating = c.get("rating_average") or 0
        count = c.get("rating_count") or 0
        data_hot = (
            (isinstance(pop, (int, float)) and pop >= 0.65)
            or (isinstance(rarity, (int, float)) and rarity >= 70 and float(rating) >= 4.3 and count >= 100)
        )
        is_hot = curated or data_hot
        c["feedHot"] = is_hot
        c["_priority"] = _priority_score(c, is_hot)

    ranked = sorted(cards, key=lambda x: -(x.get("_priority") or 0))

    # Score every card for Top Drops (quality + scarcity, no freshness bias)
    for c in cards:
        c["_top_score"] = _top_opportunity_score(c)
    quality_ranked = sorted(cards, key=lambda x: -(x.get("_top_score") or 0))

    # Top opportunities:
    #   1. Named priority restaurants (iconic / hardest-to-get) that are live right now
    #   2. Fill remaining slots from quality_ranked (best score first, no freshness bias)
    priority_picks = []
    used_ids: set[str] = set()
    for market in ("nyc", "miami"):
        if len(priority_picks) >= TOP_OPPORTUNITIES_MAX:
            break
        for pname in top_priority_names(market):
            if len(priority_picks) >= TOP_OPPORTUNITIES_MAX:
                break
            # Find the highest quality-scored match for this priority name.
            # Use word-level matching to avoid "misi" matching "misipasta" etc.
            for d in quality_ranked:
                if d.get("id") in used_ids:
                    continue
                if (d.get("market") or "nyc") != market:
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
    # Hot right now: hot cards not in top 4, then pad with non-hot so frontend can fill rows (min 8, multiple of 5)
    hot_right_now = [d for d in hot_only if d["id"] not in top_ids][:HOT_RIGHT_NOW_MAX]
    seen_hrn_ids = {d["id"] for d in hot_right_now}
    non_hot = [d for d in ranked if not d.get("feedHot") and d["id"] not in top_ids and d["id"] not in seen_hrn_ids]
    if len(hot_right_now) < MIN_SECOND_ROW_CARDS:
        need = MIN_SECOND_ROW_CARDS - len(hot_right_now)
        hot_right_now = hot_right_now + non_hot[:need]
        seen_hrn_ids = {d["id"] for d in hot_right_now}
        non_hot = [d for d in non_hot if d["id"] not in seen_hrn_ids]
    target_len = max(MIN_SECOND_ROW_CARDS, ((len(hot_right_now) + HOT_RIGHT_NOW_COLS - 1) // HOT_RIGHT_NOW_COLS) * HOT_RIGHT_NOW_COLS)
    if len(hot_right_now) < target_len:
        extra = target_len - len(hot_right_now)
        hot_right_now = hot_right_now + non_hot[:extra]

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
        c["_ticker_score"] = _ticker_score(c, c.get("feedHot", False))
    ticker_board = sorted(ticker_worthy, key=lambda x: -(x.get("_ticker_score") or 0))

    return {
        "ranked_board": ranked,
        "ticker_board": ticker_board,
        "top_opportunities": top_opportunities,
        "hot_right_now": hot_right_now,
    }
