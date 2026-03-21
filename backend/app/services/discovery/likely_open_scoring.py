"""
Scoring and copy for "Likely to open" — venues that are closed now but historically
release tables again.

We do NOT have cancellation data; we only observe drop_events / rolling metrics.
The UI "probability" is a composite *index* (1–99) of how strong the historical
pattern is for another release soon — not P(table in the next hour).

Ranking blends:
- Calendar habit (availability_rate_14d, days_with_drops)
- Churn intensity (drop_frequency_per_day)
- Momentum (trend_pct: last 7d vs prior 7d)
- Recent pulse (total_last_7d, log-scaled)
"""
from __future__ import annotations

import math
from typing import Any

_PREDICTED_TIMES = ("Evening", "Dinner", "Midnight", "10:00 AM")


def score_likely_open_rank(
    availability_rate_14d: float | None,
    days_with_drops: int | None,
    drop_frequency_per_day: float | None,
    trend_pct: float | None,
    total_last_7d: int | None,
) -> float:
    """
    Higher = better candidate for "may release again soon" while nothing is open.
    Typical range ~0.05–1.0+.
    """
    ar = float(availability_rate_14d or 0.0)
    dwd = int(days_with_drops or 0)
    freq = float(drop_frequency_per_day or 0.0)
    last7 = int(total_last_7d or 0)

    # Steady pattern across the 14d window
    habit = 0.40 * ar + 0.22 * (dwd / 14.0)

    # How "busy" the venue is in the window (releases per day), capped
    intensity = 0.28 * min(1.0, freq / 3.0)

    # Positive trend → more drops lately than the week before → boost
    momentum = 0.0
    if trend_pct is not None:
        t = float(trend_pct)
        momentum = 0.14 * max(-1.0, min(1.0, t * 2.5))

    # Raw activity last 7 days (diminishing returns)
    recent = 0.0
    if last7 > 0:
        recent = 0.12 * min(1.0, math.log1p(last7) / math.log1p(45.0))

    return habit + intensity + momentum + recent


def likely_open_index_1_99(item: dict[str, Any]) -> int:
    """Single 1–99 index for clients; maps rank score into a display band."""
    raw = score_likely_open_rank(
        item.get("availability_rate_14d"),
        item.get("days_with_drops"),
        item.get("drop_frequency_per_day"),
        item.get("trend_pct"),
        item.get("total_last_7d"),
    )
    # raw often 0.15–1.05; stretch into 1–99
    scaled = int(round(min(1.05, max(0.08, raw)) * 92))
    return min(99, max(1, scaled))


def confidence_label(item: dict[str, Any]) -> str:
    """Data sufficiency + pattern strength — not medical 'confidence'."""
    dwd = int(item.get("days_with_drops") or 0)
    ar = float(item.get("availability_rate_14d") or 0.0)
    last7 = int(item.get("total_last_7d") or 0)
    trend = item.get("trend_pct")

    if dwd >= 6 and ar >= 0.35:
        return "High"
    if last7 >= 5 and trend is not None and float(trend) > 0.06:
        return "High"
    if dwd <= 2 and last7 <= 1:
        return "Low"
    if dwd <= 3 and ar < 0.15:
        return "Low"
    return "Medium"


def reason_text(item: dict[str, Any]) -> str:
    """Plain-language explanation tied only to metrics we store."""
    dwd = int(item.get("days_with_drops") or 0)
    ar = float(item.get("availability_rate_14d") or 0.0)
    freq = float(item.get("drop_frequency_per_day") or 0.0)
    trend = item.get("trend_pct")
    last7 = int(item.get("total_last_7d") or 0)
    total = int(item.get("total_new_drops") or 0)

    if trend is not None and float(trend) > 0.12:
        return (
            f"More table releases in the last 7 days than the week before "
            f"({last7} events recently). Another opening may follow while none is showing now."
        )
    if trend is not None and float(trend) < -0.12:
        return (
            "Releases have slowed compared to the prior week — pattern is weaker, "
            "but still worth a watch with nothing open right now."
        )
    if ar >= 0.45 and dwd >= 5:
        return (
            f"Releases appeared on {dwd} of the last 14 days — recurring activity "
            "suggests another slot may appear."
        )
    if freq >= 0.75 and dwd >= 3:
        return (
            f"High release churn in the window (~{freq:.1f} per day on average) — "
            "another drop often follows when the list is empty."
        )
    if total >= 8 and dwd >= 4:
        return (
            f"{total} releases observed in the 14-day window — steady enough to keep on radar."
        )
    if dwd <= 3:
        return (
            f"Only {dwd} days with releases in the last 14 — rarer pattern; "
            "act fast when a table does show up."
        )
    return (
        f"Based on {dwd} days with observed releases in the last 14 days — "
        "nothing open now; we surface spots that often cycle again."
    )


def enrich_likely_open_item(item: dict[str, Any], index: int) -> None:
    """Mutates item: name, probability (index), confidence, reason, predicted_drop_time."""
    if not (item.get("name") or "").strip():
        item["name"] = (item.get("venue_name") or "").strip()
    item["probability"] = likely_open_index_1_99(item)
    item["confidence"] = confidence_label(item)
    item["reason"] = reason_text(item)
    item["predicted_drop_time"] = _PREDICTED_TIMES[index % len(_PREDICTED_TIMES)]
