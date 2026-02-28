"""
Discovery workload config. .env is the source of truth; these defaults apply only when
the env var is unset. All values read at import time.

Env vars: DISCOVERY_WINDOW_DAYS, DISCOVERY_TIME_SLOTS, DISCOVERY_PARTY_SIZES,
DISCOVERY_MAX_CONCURRENT_BUCKETS, DISCOVERY_BUCKET_COOLDOWN_SECONDS,
DISCOVERY_TICK_SECONDS, NOTIFIED_DEDUPE_MINUTES, DISCOVERY_RESY_PER_PAGE,
DISCOVERY_RESY_MAX_PAGES, DISCOVERY_DATE_TIMEZONE.
"""
import os
from dataclasses import dataclass
from typing import List


def _int(key: str, default: int, min_val: int | None = None, max_val: int | None = None) -> int:
    raw = os.environ.get(key)
    if raw is None:
        v = default
    else:
        try:
            v = int(raw.strip())
        except ValueError:
            v = default
    if min_val is not None and v < min_val:
        v = min_val
    if max_val is not None and v > max_val:
        v = max_val
    return v


def _list_int(key: str, default: List[int]) -> List[int]:
    raw = os.environ.get(key)
    if not raw:
        return default
    out = []
    for s in raw.split(","):
        s = s.strip()
        if not s:
            continue
        try:
            out.append(int(s))
        except ValueError:
            continue
    return out if out else default


def _list_str(key: str, default: List[str], allowed: List[str] | None = None) -> List[str]:
    raw = os.environ.get(key)
    if not raw:
        return default
    out = [s.strip() for s in raw.split(",") if s.strip()]
    if not out:
        return default
    if allowed is not None:
        out = [s for s in out if s in allowed]
        if not out:
            return default
    return out


# -----------------------------------------------------------------------------
# Discovery window and buckets (set in .env; defaults below only when unset)
# -----------------------------------------------------------------------------
DISCOVERY_DATE_TIMEZONE = os.environ.get("DISCOVERY_DATE_TIMEZONE", "America/New_York").strip() or "America/New_York"
DISCOVERY_WINDOW_DAYS = _int("DISCOVERY_WINDOW_DAYS", 14, min_val=1, max_val=14)
DISCOVERY_TIME_SLOTS = _list_str(
    "DISCOVERY_TIME_SLOTS",
    ["15:00", "20:30"],
    allowed=["13:00", "15:00", "19:00", "20:30"],
)
DISCOVERY_PARTY_SIZES = _list_int("DISCOVERY_PARTY_SIZES", [2, 4])

# -----------------------------------------------------------------------------
# Scheduler: concurrency, cooldown, tick (.env is source of truth)
# -----------------------------------------------------------------------------
DISCOVERY_MAX_CONCURRENT_BUCKETS = _int("DISCOVERY_MAX_CONCURRENT_BUCKETS", 7, min_val=1, max_val=28)
DISCOVERY_BUCKET_COOLDOWN_SECONDS = _int(
    "DISCOVERY_BUCKET_COOLDOWN_SECONDS", 10, min_val=5, max_val=300
)
DISCOVERY_TICK_SECONDS = _int("DISCOVERY_TICK_SECONDS", 2, min_val=1, max_val=60)
# Don't create a new DropEvent (or re-notify) for the same (bucket_id, slot_id) within this many minutes (TTL dedupe).
NOTIFIED_DEDUPE_MINUTES = _int("NOTIFIED_DEDUPE_MINUTES", 30, min_val=5, max_val=1440)

# -----------------------------------------------------------------------------
# Resy API: results per bucket (.env is source of truth)
# -----------------------------------------------------------------------------
DISCOVERY_RESY_PER_PAGE = _int("DISCOVERY_RESY_PER_PAGE", 100, min_val=20, max_val=200)
DISCOVERY_RESY_MAX_PAGES = _int("DISCOVERY_RESY_MAX_PAGES", 5, min_val=1, max_val=10)


@dataclass(frozen=True)
class DiscoveryConfig:
    """Snapshot of discovery config for passing around (e.g. tests)."""
    window_days: int
    time_slots: List[str]
    party_sizes: List[int]
    max_concurrent_buckets: int
    bucket_cooldown_seconds: int
    tick_seconds: int
    resy_per_page: int
    resy_max_pages: int
    notified_dedupe_minutes: int


def get_discovery_config() -> DiscoveryConfig:
    return DiscoveryConfig(
        window_days=DISCOVERY_WINDOW_DAYS,
        time_slots=DISCOVERY_TIME_SLOTS,
        party_sizes=DISCOVERY_PARTY_SIZES,
        max_concurrent_buckets=DISCOVERY_MAX_CONCURRENT_BUCKETS,
        bucket_cooldown_seconds=DISCOVERY_BUCKET_COOLDOWN_SECONDS,
        tick_seconds=DISCOVERY_TICK_SECONDS,
        resy_per_page=DISCOVERY_RESY_PER_PAGE,
        resy_max_pages=DISCOVERY_RESY_MAX_PAGES,
        notified_dedupe_minutes=NOTIFIED_DEDUPE_MINUTES,
    )
