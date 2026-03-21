"""
Server-computed display strings and flags for feed cards.

Clients should render these as-is (no duplicate metric/score math in apps).
"""
from __future__ import annotations

from datetime import datetime, timezone


def _parse_detected_at(card: dict) -> datetime | None:
    det = card.get("detected_at") or card.get("created_at")
    if not det or not isinstance(det, str):
        return None
    try:
        dt = datetime.fromisoformat(det.replace("Z", "+00:00"))
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt
    except (ValueError, TypeError):
        return None


def seconds_since_detected(card: dict, now: datetime) -> int | None:
    dt = _parse_detected_at(card)
    if dt is None:
        return None
    return max(0, int((now - dt).total_seconds()))


def _rarity_int(card: dict) -> int:
    raw = card.get("rarity_score")
    if not isinstance(raw, (int, float)) or raw <= 0:
        return 0
    r = float(raw)
    if r <= 1:
        r *= 100
    return int(max(0, min(100, round(r))))


def _is_scarcity_rare(card: dict) -> bool:
    rate = card.get("availability_rate_14d")
    return isinstance(rate, (int, float)) and 0 < float(rate) < 0.15


def crown_badge_label(card: dict) -> str:
    ri = _rarity_int(card)
    fh = card.get("feedHot") is True
    if fh or ri >= 88:
        return "LEGENDARY"
    if ri >= 70 or _is_scarcity_rare(card):
        return "ULTRA RARE"
    if ri >= 50:
        return "RARE"
    return "HOT"


def _vanish_short_seconds(sec: float | int | None) -> str | None:
    if not isinstance(sec, (int, float)) or sec <= 0:
        return None
    s = float(sec)
    if s < 60:
        return "<1m"
    mins = int(s // 60)
    if mins < 60:
        return f"{mins}m"
    h = max(1, mins // 60)
    return f"{h}h"


def _active_days_short(card: dict) -> str | None:
    d = card.get("days_with_drops")
    if not isinstance(d, int) or d <= 0:
        return None
    return f"{d}/14d"


def _trend_percent_points(raw) -> float | None:
    if raw is None:
        return None
    try:
        p = float(raw)
    except (TypeError, ValueError):
        return None
    if abs(p) < 1e-9:
        return None
    if -1 <= p <= 1:
        return p * 100
    return p


def _trend_short_label(card: dict) -> str | None:
    pts = _trend_percent_points(card.get("trend_pct"))
    if pts is None or abs(pts) < 5:
        return None
    r = int(round(pts))
    return f"+{r}% wk" if r > 0 else f"{r}% wk"


def _heat_label(card: dict) -> str:
    p = card.get("trend_pct")
    if p is None:
        return "Steady"
    try:
        normalized = float(p)
    except (TypeError, ValueError):
        return "Steady"
    if -1 <= normalized <= 1:
        normalized *= 100
    if normalized >= 80:
        return "Peak Demand"
    if normalized >= 50:
        return "Exploding"
    if normalized >= 20:
        return "Rising Heat"
    if normalized > 0:
        return "Warming"
    if normalized < 0:
        return "Cooling"
    return "Steady"


def metrics_subtitle_line(card: dict) -> str | None:
    parts: list[str] = []
    v = _vanish_short_seconds(card.get("avg_drop_duration_seconds"))
    if v:
        parts.append(f"Gone in {v}")
    ad = _active_days_short(card)
    if ad:
        parts.append(f"Open {ad}")
    ts = _trend_short_label(card)
    if ts:
        parts.append(ts)
    if not parts and card.get("trend_pct") is not None:
        parts.append(_heat_label(card))
    return " · ".join(parts) if parts else None


def rarity_tier_name(pts: int) -> str:
    if pts >= 90:
        return "Ultra Rare"
    if pts >= 70:
        return "Rare"
    if pts >= 50:
        return "Uncommon"
    return "Limited"


def rarity_headline_line(card: dict) -> str | None:
    pts = _rarity_int(card)
    if pts <= 0:
        return None
    return f"{rarity_tier_name(pts)} · {pts}"


def opportunity_row_primary_metric(card: dict) -> str | None:
    rh = rarity_headline_line(card)
    if rh:
        return rh
    pop = card.get("resy_popularity_score")
    if isinstance(pop, (int, float)) and float(pop) > 0:
        pct = int(min(0.99, float(pop)) * 100)
        return f"Demand {pct}%"
    return None


def speed_tier(card: dict) -> str | None:
    sec = card.get("avg_drop_duration_seconds")
    if not isinstance(sec, (int, float)) or sec <= 0:
        return None
    s = float(sec)
    if s < 180:
        return "fast"
    if s < 900:
        return "med"
    return "slow"


def rating_reviews_compact(card: dict) -> str | None:
    rc = card.get("rating_count")
    if isinstance(rc, float) and rc > 0:
        rc = int(rc)
    if not isinstance(rc, int) or rc <= 0:
        return None
    if rc >= 1000:
        return f"{rc / 1000.0:.1f}k".rstrip("0").rstrip(".")
    return str(rc)


def metrics_secondary_compact_line(card: dict) -> str | None:
    parts: list[str] = []
    ad = _active_days_short(card)
    if ad:
        parts.append(ad)
    ts = _trend_short_label(card)
    if ts:
        parts.append(ts)
    elif card.get("trend_pct") is not None:
        parts.append(_heat_label(card))
    return " · ".join(parts) if parts else None


def freshness_short_label(card: dict, now: datetime) -> str | None:
    sec = seconds_since_detected(card, now)
    if sec is None:
        return None
    if sec < 60:
        return "Just dropped"
    if sec < 3600:
        return f"{sec // 60}m ago"
    if sec < 86400:
        return f"{sec // 3600}h ago"
    return None


def velocity_primary_label(card: dict, now: datetime) -> str:
    avg = card.get("avg_drop_duration_seconds")
    elapsed = seconds_since_detected(card, now)
    if isinstance(avg, (int, float)) and float(avg) > 0 and elapsed is not None:
        left = max(0, int(float(avg)) - elapsed)
        if left > 0:
            mm, ss = left // 60, left % 60
            return f"{mm:02d}:{ss:02d}"
        return "Grab it now"
    return freshness_short_label(card, now) or "Live"


def velocity_urgent(card: dict, now: datetime) -> bool:
    elapsed = seconds_since_detected(card, now)
    if elapsed is None:
        return False
    return elapsed < 600


def _hero_slot_time_phrase(card: dict) -> str:
    slots = card.get("slots") or []
    if not slots or not isinstance(slots[0], dict):
        return "tonight"
    raw_t = (slots[0].get("time") or "").strip()
    if not raw_t:
        return "tonight"
    seg = raw_t.replace("–", "-").split("-")[0].strip()
    parts = seg.split(":")
    try:
        h = int(parts[0])
    except (ValueError, IndexError):
        return "tonight"
    m = int(parts[1][:2]) if len(parts) > 1 else 0
    h12 = 12 if h % 12 == 0 else h % 12
    ampm = "AM" if h < 12 else "PM"
    if m > 0:
        return f"tonight at {h12}:{m:02d} {ampm}"
    return f"tonight at {h12} {ampm}"


def hero_description_line(card: dict) -> str:
    sizes = card.get("party_sizes_available") or []
    party = str(sorted(sizes)[0]) if sizes else "2"
    time_phrase = _hero_slot_time_phrase(card)
    rc = card.get("rating_count")
    if isinstance(rc, float) and rc > 0:
        rc = int(rc)
    high_rarity = _rarity_int(card) >= 70
    if (isinstance(rc, int) and rc > 500) or high_rarity:
        return (
            f"Rare table for {party} around {time_phrase}. "
            "Our scans show this spot rarely drops—grab it fast."
        )
    return f"Table for {party} around {time_phrase}."


def hero_scan_metrics_line(card: dict) -> str | None:
    parts: list[str] = []
    v = _vanish_short_seconds(card.get("avg_drop_duration_seconds"))
    if v:
        parts.append(f"Tables gone in ~{v}")
    ad = _active_days_short(card)
    if ad:
        parts.append(f"open {ad}")
    ts = _trend_short_label(card)
    if ts:
        parts.append(ts)
    return " · ".join(parts) if parts else None


def hero_score_caption(card: dict) -> str | None:
    sg = card.get("snag_score")
    if isinstance(sg, float):
        sg = int(sg)
    if isinstance(sg, int):
        n = max(1, min(99, sg))
        return f"Opportunity score {n}/99"
    ri = _rarity_int(card)
    if ri > 0:
        return f"Scan score {ri}/100"
    return None


def top_opportunity_demand_label(card: dict) -> str:
    if card.get("feedHot") is True:
        return "HIGH DEMAND"
    raw = card.get("rarity_score")
    r = 0.0
    if isinstance(raw, (int, float)) and float(raw) > 0:
        r = float(raw) * 100 if float(raw) <= 1 else float(raw)
    rate = float(card.get("availability_rate_14d") or 1)
    if r >= 80 or rate < 0.1:
        return "VERY HIGH DEMAND"
    if r >= 50 or rate < 0.25:
        return "HIGH DEMAND"
    return "POPULAR"


def top_opportunity_subtitle_line(card: dict) -> str:
    parts: list[str] = []
    v = _vanish_short_seconds(card.get("avg_drop_duration_seconds"))
    if v:
        parts.append(f"Tables ~{v}")
    ad = _active_days_short(card)
    if ad:
        parts.append(ad)
    ts = _trend_short_label(card)
    if ts:
        parts.append(ts)
    if parts:
        return " · ".join(parts)
    rc = card.get("rating_count")
    if isinstance(rc, float) and rc > 0:
        rc = int(rc)
    if (isinstance(rc, int) and rc > 500) or card.get("feedHot") is True:
        return "Usually fully booked"
    ri = _rarity_int(card)
    if ri > 0:
        return rarity_tier_name(ri)
    return "Popular"


def top_opportunity_freshness_badge(card: dict, now: datetime) -> str | None:
    sec = seconds_since_detected(card, now)
    if sec is None:
        return None
    if sec < 5 * 60:
        return "Just now"
    if sec < 30 * 60:
        return "Last 30 mins"
    if sec < 60 * 60:
        return "Last hour"
    return None


def show_top_opportunity_new_badge(card: dict, now: datetime) -> bool:
    sec = seconds_since_detected(card, now)
    return sec is not None and sec < 600


def flame_fill_count(card: dict) -> int:
    if card.get("feedHot") is True:
        return 3
    ri = _rarity_int(card)
    if ri >= 75:
        return 3
    if ri >= 45:
        return 2
    return 1


def live_stream_velocity_badge(card: dict, now: datetime) -> str:
    avg = card.get("avg_drop_duration_seconds")
    if isinstance(avg, (int, float)) and float(avg) > 0:
        d = float(avg)
        if d < 60:
            return f"{int(d)}S"
        return f"{int(d / 60)}M"
    sec = seconds_since_detected(card, now)
    if sec is None:
        return "—"
    if sec < 60:
        return f"{sec}S"
    return f"{sec // 60}M"


def scarcity_label_line(card: dict) -> str | None:
    rate = card.get("availability_rate_14d")
    if not isinstance(rate, (int, float)) or float(rate) <= 0:
        return None
    r = float(rate)
    dwd = card.get("days_with_drops")
    if isinstance(dwd, int) and dwd > 0:
        days = dwd
    else:
        days = int(round(r * 14.0))
    if r < 0.15:
        return f"Rare · open {days}/14 days"
    if r < 0.4:
        return f"Uncommon · open {days}/14 days"
    return f"Available · open {days}/14 days"


def latest_drop_subtitle_metrics(card: dict) -> str | None:
    parts: list[str] = []
    sl = scarcity_label_line(card)
    if sl:
        parts.append(sl)
    v = _vanish_short_seconds(card.get("avg_drop_duration_seconds"))
    if v:
        parts.append(f"Gone in {v}")
    return " · ".join(parts) if parts else None


def footnote_metrics_compact_line(card: dict) -> str | None:
    parts: list[str] = []
    ad = _active_days_short(card)
    if ad:
        parts.append(ad)
    v = _vanish_short_seconds(card.get("avg_drop_duration_seconds"))
    if v:
        parts.append(f"~{v}")
    return " · ".join(parts) if parts else None


def rare_drop_detail_line(card: dict) -> str | None:
    parts: list[str] = []
    v = _vanish_short_seconds(card.get("avg_drop_duration_seconds"))
    if v:
        parts.append(f"~{v} open")
    ts = _trend_short_label(card)
    if ts:
        parts.append(ts)
    return " · ".join(parts) if parts else None


def forecast_metrics_compact_for_likely_item(item: dict) -> str | None:
    parts: list[str] = []
    dwd = item.get("days_with_drops")
    if isinstance(dwd, int) and dwd > 0:
        parts.append(f"{dwd}/14d active")
    ri = _rarity_int(item)
    if ri > 0:
        parts.append(f"rarity {ri}")
    ts = _trend_short_label(item)
    if ts:
        parts.append(ts)
    return " · ".join(parts) if parts else None


def attach_feed_card_display_fields(cards: list[dict], now: datetime | None = None) -> None:
    """Mutates cards: labels, badges, velocity, exclusivity — for client display only."""
    t = now or datetime.now(timezone.utc)
    for c in cards:
        c["crown_badge_label"] = crown_badge_label(c)
        c["show_exclusive_badge"] = (c.get("feedHot") is True) or (_rarity_int(c) >= 65)
        ms = metrics_subtitle_line(c)
        if ms:
            c["metrics_subtitle"] = ms
        else:
            c.pop("metrics_subtitle", None)
        rh = rarity_headline_line(c)
        if rh:
            c["rarity_headline"] = rh
        else:
            c.pop("rarity_headline", None)
        rpm = opportunity_row_primary_metric(c)
        if rpm:
            c["row_primary_metric"] = rpm
        else:
            c.pop("row_primary_metric", None)
        st = speed_tier(c)
        if st:
            c["speed_tier"] = st
        else:
            c.pop("speed_tier", None)
        rr = rating_reviews_compact(c)
        if rr:
            c["rating_reviews_compact"] = rr
        else:
            c.pop("rating_reviews_compact", None)
        m2 = metrics_secondary_compact_line(c)
        if m2:
            c["metrics_secondary_compact"] = m2
        else:
            c.pop("metrics_secondary_compact", None)
        c["velocity_urgent"] = velocity_urgent(c, t)
        c["velocity_primary_label"] = velocity_primary_label(c, t)
        fl = freshness_short_label(c, t)
        if fl:
            c["freshness_label"] = fl
        else:
            c.pop("freshness_label", None)
        jd = seconds_since_detected(c, t)
        c["brand_new_drop"] = jd is not None and jd < 300
        c["feeds_rare_carousel"] = _is_scarcity_rare(c) or (_rarity_int(c) >= 65)
        c["hero_description"] = hero_description_line(c)
        hsm = hero_scan_metrics_line(c)
        if hsm:
            c["hero_scan_metrics_line"] = hsm
        else:
            c.pop("hero_scan_metrics_line", None)
        hsc = hero_score_caption(c)
        if hsc:
            c["hero_score_caption"] = hsc
        else:
            c.pop("hero_score_caption", None)
        c["top_opportunity_demand_label"] = top_opportunity_demand_label(c)
        c["top_opportunity_subtitle_line"] = top_opportunity_subtitle_line(c)
        tb = top_opportunity_freshness_badge(c, t)
        if tb:
            c["top_opportunity_freshness_badge"] = tb
        else:
            c.pop("top_opportunity_freshness_badge", None)
        c["show_new_badge"] = show_top_opportunity_new_badge(c, t)
        c["flame_count"] = flame_fill_count(c)
        c["live_stream_velocity_badge"] = live_stream_velocity_badge(c, t)
        rd = rare_drop_detail_line(c)
        if rd:
            c["rare_drop_detail_line"] = rd
        else:
            c.pop("rare_drop_detail_line", None)
        sl = scarcity_label_line(c)
        if sl:
            c["scarcity_label"] = sl
        else:
            c.pop("scarcity_label", None)
        ldm = latest_drop_subtitle_metrics(c)
        if ldm:
            c["latest_drop_subtitle_metrics"] = ldm
        else:
            c.pop("latest_drop_subtitle_metrics", None)
        fmc = footnote_metrics_compact_line(c)
        if fmc:
            c["footnote_metrics_compact"] = fmc
        else:
            c.pop("footnote_metrics_compact", None)
        th = _trend_short_label(c)
        if th:
            c["trend_headline_short"] = th
        else:
            c.pop("trend_headline_short", None)
        rp = _rarity_int(c)
        if rp > 0:
            c["rarity_points"] = rp
        else:
            c.pop("rarity_points", None)
