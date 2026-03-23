"""
Scoring and copy for "Likely to open" — venues with no open slots *now* that we
**predict** are most likely to show new tables soon.

Signals (all from observed Resy releases, not cancellations):
- **Recency**: last drop_event time — closed now but dropped hours ago → strong "cycles again" signal
- **Recent week**: total_last_7d, trend_pct vs prior week
- **Churn**: drop_frequency_per_day
- **Habit**: availability_rate_14d, days_with_drops

`probability` (1–99) is a **forecast score** ranked against other candidates — not a calibrated
P(slot in the next hour). Copy is written as a prediction; the model is heuristic.
"""
from __future__ import annotations

import math
from datetime import datetime, timedelta, timezone
from typing import Any
from zoneinfo import ZoneInfo

from app.core.discovery_config import DISCOVERY_DATE_TIMEZONE
from app.services.discovery.feed_display import forecast_metrics_compact_for_likely_item

_FALLBACK_PREDICTED_TIMES = ("Evening", "Dinner", "Late Night", "Afternoon")


def score_likely_open_rank(
    availability_rate_14d: float | None,
    days_with_drops: int | None,
    drop_frequency_per_day: float | None,
    trend_pct: float | None,
    total_last_7d: int | None,
    hours_since_last_drop: float | None = None,
) -> float:
    """
    Higher = stronger forecast that new slots will appear soon (while currently closed).
    Typical range ~0.05–1.3.
    """
    ar = float(availability_rate_14d or 0.0)
    dwd = int(days_with_drops or 0)
    freq = float(drop_frequency_per_day or 0.0)
    last7 = int(total_last_7d or 0)

    # Baseline: this place does release tables on a recurring calendar
    habit = 0.28 * ar + 0.14 * (dwd / 14.0)

    # Steady churn → expect another release after a dry spell
    intensity = 0.20 * min(1.0, freq / 3.0)

    # Momentum: more activity this week than last → forecast uptick
    momentum = 0.0
    if trend_pct is not None:
        t = float(trend_pct)
        momentum = 0.20 * max(-1.0, min(1.0, t * 2.5))

    # Raw pulse last 7d — forward-looking slice of the window
    recent = 0.0
    if last7 > 0:
        recent = 0.20 * min(1.0, math.log1p(last7) / math.log1p(45.0))

    # Recency of last observed release (venue closed *now* in caller’s filter)
    recency = 0.0
    if hours_since_last_drop is not None and hours_since_last_drop >= 0:
        h = float(hours_since_last_drop)
        if h <= 4:
            recency = 0.24
        elif h <= 12:
            recency = 0.20
        elif h <= 24:
            recency = 0.16
        elif h <= 48:
            recency = 0.12
        elif h <= 96:
            recency = 0.08
        elif h <= 168:
            recency = 0.04

    return habit + intensity + momentum + recent + recency


def likely_open_index_1_99(item: dict[str, Any]) -> int:
    """Display score 1–99 — higher = stronger predicted chance of a new opening soon."""
    raw = score_likely_open_rank(
        item.get("availability_rate_14d"),
        item.get("days_with_drops"),
        item.get("drop_frequency_per_day"),
        item.get("trend_pct"),
        item.get("total_last_7d"),
        item.get("hours_since_last_drop"),
    )
    scaled = int(round(min(1.28, max(0.08, raw)) * 77))
    return min(99, max(1, scaled))


def confidence_label(item: dict[str, Any]) -> str:
    """How strong the forecast is given data depth + recency + momentum."""
    dwd = int(item.get("days_with_drops") or 0)
    ar = float(item.get("availability_rate_14d") or 0.0)
    last7 = int(item.get("total_last_7d") or 0)
    trend = item.get("trend_pct")
    h = item.get("hours_since_last_drop")

    if h is not None and float(h) <= 24 and last7 >= 2:
        return "High"
    if dwd >= 6 and ar >= 0.35:
        return "High"
    if last7 >= 5 and trend is not None and float(trend) > 0.06:
        return "High"
    if dwd <= 2 and last7 <= 1 and (h is None or float(h) > 168):
        return "Low"
    if dwd <= 3 and ar < 0.15:
        return "Low"
    return "Medium"


def reason_text(item: dict[str, Any]) -> str:
    """Predictive copy grounded in metrics + last-drop recency."""
    dwd = int(item.get("days_with_drops") or 0)
    ar = float(item.get("availability_rate_14d") or 0.0)
    freq = float(item.get("drop_frequency_per_day") or 0.0)
    trend = item.get("trend_pct")
    last7 = int(item.get("total_last_7d") or 0)
    total = int(item.get("total_new_drops") or 0)
    h_raw = item.get("hours_since_last_drop")

    if h_raw is not None:
        try:
            h = float(h_raw)
        except (TypeError, ValueError):
            h = None
        if h is not None and h >= 0:
            if h <= 6:
                return (
                    f"Last release ~{max(1, int(h))}h ago and nothing’s open now — "
                    "we predict another table drop soon."
                )
            if h <= 24:
                return (
                    f"Tables dropped within the last day; still empty on the feed — "
                    "forecast: another opening likely."
                )
            if h <= 72:
                return (
                    "Recent activity with no slots showing now — model expects another release "
                    "in the next cycle."
                )

    if trend is not None and float(trend) > 0.12:
        return (
            f"Release pace is up vs last week ({last7} events in 7d) — "
            "predicting continued openings while you’re seeing none."
        )
    if trend is not None and float(trend) < -0.12:
        return (
            "Slower than the prior week — softer forecast, but still a watch "
            "if you need this spot."
        )
    if ar >= 0.45 and dwd >= 5:
        return (
            f"Opens on {dwd} of the last 14 days — strong habit; we expect new slots "
            "to appear again."
        )
    if freq >= 0.75 and dwd >= 3:
        return (
            f"High churn (~{freq:.1f} releases/day) — when the list is empty, "
            "another drop is usually close."
        )
    if total >= 8 and dwd >= 4:
        return (
            f"{total} releases in 14d — steady venue; predicted to cycle open again."
        )
    if dwd <= 3:
        return (
            f"Rare pattern ({dwd} active days) — lower confidence, but worth an alert "
            "when it does fire."
        )
    return (
        f"Nothing open now; from {dwd} active days in 14d we forecast another release "
        "worth watching."
    )


def _tz_suffix() -> str:
    if "New_York" in DISCOVERY_DATE_TIMEZONE:
        return "ET"
    if "/" in DISCOVERY_DATE_TIMEZONE:
        return DISCOVERY_DATE_TIMEZONE.rsplit("/", 1)[-1].replace("_", " ")
    return ""


def _format_clock_hour_12(hour: int) -> str:
    h = int(hour) % 24
    if h == 0:
        return "12am"
    if h < 12:
        return f"{h}am"
    if h == 12:
        return "12pm"
    return f"{h - 12}pm"


def _typical_window_clock_label(modal_hour: int) -> str:
    """e.g. 'Typically 6pm–7pm ET' from modal local hour."""
    a = _format_clock_hour_12(modal_hour)
    b = _format_clock_hour_12((modal_hour + 1) % 24)
    suf = _tz_suffix()
    if suf:
        return f"Typically {a}–{b} {suf}"
    return f"Typically {a}–{b}"


def _next_modal_start_local(now_local: datetime, modal_h: int) -> datetime:
    """Next calendar occurrence of `modal_h`:00 in the same TZ as `now_local`."""
    c = now_local.replace(hour=int(modal_h) % 24, minute=0, second=0, microsecond=0)
    if c > now_local:
        return c
    return c + timedelta(days=1)


def _predicted_drop_hint(modal_hour: int | None, now_utc: datetime) -> str | None:
    """Short relative timing copy (e.g. next hour / few hours), using discovery TZ."""
    if modal_hour is None:
        return None
    try:
        tz = ZoneInfo(DISCOVERY_DATE_TIMEZONE)
    except Exception:
        tz = timezone.utc
    now_local = now_utc.astimezone(tz)
    mh = int(modal_hour) % 24
    start_min = mh * 60
    now_min = now_local.hour * 60 + now_local.minute
    end_min = start_min + 120
    if start_min <= now_min < min(end_min, 24 * 60):
        return "In the usual window now — check often"

    nxt = _next_modal_start_local(now_local, mh)
    hrs = (nxt - now_local).total_seconds() / 3600.0
    if hrs < 1.25:
        return "Often within the next hour"
    if hrs < 3.5:
        return "Often within the next few hours"
    if hrs < 12:
        return f"Next usual wave in ~{max(1, int(round(hrs)))}h"
    if hrs < 20:
        return "Usually later today around the typical time"
    return "Same clock time most days — worth a watch"


def enrich_likely_open_item(item: dict[str, Any], index: int) -> None:
    """Mutates item: name, probability (forecast score), confidence, reason, predicted_drop_time."""
    if not (item.get("name") or "").strip():
        item["name"] = (item.get("venue_name") or "").strip()
    item["probability"] = likely_open_index_1_99(item)
    item["confidence"] = confidence_label(item)
    item["reason"] = reason_text(item)
    fm = forecast_metrics_compact_for_likely_item(item)
    if fm:
        item["forecast_metrics_compact"] = fm
    else:
        item.pop("forecast_metrics_compact", None)
    modal_hour = item.get("modal_drop_hour")
    now_utc = datetime.now(timezone.utc)
    if modal_hour is not None:
        try:
            mh = int(modal_hour) % 24
        except (TypeError, ValueError):
            mh = None
        if mh is not None:
            item["predicted_drop_time"] = _typical_window_clock_label(mh)
            hint = _predicted_drop_hint(mh, now_utc)
            if hint:
                item["predicted_drop_hint"] = hint
            else:
                item.pop("predicted_drop_hint", None)
        else:
            item["predicted_drop_time"] = _FALLBACK_PREDICTED_TIMES[index % len(_FALLBACK_PREDICTED_TIMES)]
            item.pop("predicted_drop_hint", None)
    else:
        item["predicted_drop_time"] = _FALLBACK_PREDICTED_TIMES[index % len(_FALLBACK_PREDICTED_TIMES)]
        item.pop("predicted_drop_hint", None)
    # Internal ranking only — don’t expose to clients
    item.pop("hours_since_last_drop", None)
    item.pop("modal_drop_hour", None)
