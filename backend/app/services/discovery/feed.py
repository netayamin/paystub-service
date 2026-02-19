"""
Feed curation: ranked board, top opportunities, hot right now.

Moves logic from frontend to backend so the API returns ready-to-render segments.
"""
from __future__ import annotations

from datetime import datetime, timezone

# High-demand NYC restaurants (match frontend HOT_RESTAURANTS for is_hot)
HOT_RESTAURANTS = frozenset([
    "carbone", "i sodi", "don angie", "lilia", "torrisi", "parm", "via carota",
    "l'artusi", "rezdôra", "cecconi's", "barbuto", "marea",
    "4 charles prime rib", "le bernardin", "eleven madison park", "per se",
    "the grill", "the pool", "balthazar", "daniel", "jean-georges",
    "monkey bar",
    "sushi nakazawa", "cote", "odo", "yoshino", "noda", "sushi noz",
    "torien", "bondst", "blue ribbon sushi",
    "le coucou", "frenchette", "buvette", "la mercerie", "chez zou",
    "claudette", "la pecora bianca",
    "peter luger", "quality meats", "sparks",
    "altro paradiso", "laser wolf", "the four horsemen", "sailor",
    "penny", "hags", "joji", "claud", "dame", "the river café",
    "cervo's", "misi", "pastis", "minetta tavern", "scarr's pizza",
    "rosella", "gaia", "tatiana", "gramercy tavern", "the spotted pig",
    "gage & tollner", "francie", "gem", "nura", "place des fêtes",
    "superiority burger", "estela", "king",
    "aska", "oxalis", "olmsted", "al di là", "hometown bbq",
])

# Names that get a slot in Top Opportunities when present (match frontend)
TOP_OPPORTUNITY_PRIORITY_NAMES = ("monkey bar", "i sodi", "tatiana")

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


def is_hot_restaurant(name: str | None) -> bool:
    n = _normalize_name(name)
    if not n:
        return False
    for hot in HOT_RESTAURANTS:
        if hot in n or n in hot:
            return True
    return False


def _is_top_priority(name: str | None) -> bool:
    n = _normalize_name(name)
    if not n:
        return False
    return any(p in n or n in p for p in TOP_OPPORTUNITY_PRIORITY_NAMES)


def _venue_key(v: dict) -> str:
    return str(v.get("venue_id") or v.get("name") or "").strip() or "Venue"


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
    for item in just_opened_flat:
        key, date_str, time_str, resy_url, payload = item
        name = (payload.get("name") or "").strip() or key
        norm = _normalize_name(name) or key
        if norm not in by_name:
            by_name[norm] = {
                "id": f"consolidated-{norm}",
                "name": name,
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
            }
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

    for item in still_open_flat:
        key, date_str, time_str, resy_url, payload = item
        name = (payload.get("name") or "").strip() or key
        norm = _normalize_name(name) or key
        if norm not in by_name:
            by_name[norm] = {
                "id": f"consolidated-{norm}",
                "name": name,
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
            }
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

    # Sort slots by date then time; set resyUrl to first slot
    result = []
    for card in by_name.values():
        card["party_sizes_available"].sort()
        card["slots"].sort(key=lambda s: (s.get("date_str") or "", s.get("time") or ""))
        card["resyUrl"] = (card["slots"][0].get("resyUrl") if card["slots"] else None) or None
        result.append(card)
    return result


def _priority_score(card: dict, is_hot: bool) -> float:
    heat = 2.0 if is_hot else 1.0
    availability = 1.0 if (card.get("slots")) else 0.01
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
    freshness = 1.0 / (1.0 + minutes_ago / 30)
    pop = card.get("resy_popularity_score")
    popularity = (0.5 + float(pop)) if isinstance(pop, (int, float)) else 1.0
    return heat * availability * freshness * popularity


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
        is_hot = is_hot_restaurant(c.get("name"))
        c["feedHot"] = is_hot
        c["_priority"] = _priority_score(c, is_hot)

    ranked = sorted(cards, key=lambda x: -(x.get("_priority") or 0))

    # Top opportunities: priority names first, then hot, then fill to 4
    priority_picks = []
    used_ids = set()
    for pname in TOP_OPPORTUNITY_PRIORITY_NAMES:
        for d in ranked:
            if d.get("id") in used_ids:
                continue
            n = _normalize_name(d.get("name"))
            if pname in n or n in pname:
                priority_picks.append(d)
                used_ids.add(d["id"])
                break
    seen_ids = {d["id"] for d in priority_picks}
    hot_only = [d for d in ranked if d.get("feedHot")]
    rest_hot = [d for d in hot_only if d["id"] not in seen_ids]
    rest_other = [d for d in ranked if not d.get("feedHot") and d["id"] not in seen_ids]
    top_list = list(priority_picks)
    for d in rest_hot:
        if len(top_list) >= TOP_OPPORTUNITIES_MAX:
            break
        top_list.append(d)
    for d in rest_other:
        if len(top_list) >= TOP_OPPORTUNITIES_MAX:
            break
        top_list.append(d)
    top_opportunities = top_list[:TOP_OPPORTUNITIES_MAX]
    top_ids = {d["id"] for d in top_opportunities}

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

    return {
        "ranked_board": ranked,
        "top_opportunities": top_opportunities,
        "hot_right_now": hot_right_now,
    }
