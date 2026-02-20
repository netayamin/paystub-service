"""
Discovery workload config: env-driven so the same code can run "light" (e.g. t3.micro)
or "full" (larger instance). All values read at import time.
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
# Discovery window and buckets
# -----------------------------------------------------------------------------
# Timezone for "today" in the discovery window (pruning, window start). Use the app's primary
# market (e.g. America/New_York for NYC) so users see results for their calendar "today" even
# when the server runs in UTC (e.g. 8pm ET = next day UTC; without this we'd prune "today").
DISCOVERY_DATE_TIMEZONE = os.environ.get("DISCOVERY_DATE_TIMEZONE", "America/New_York").strip() or "America/New_York"

# Number of days in the discovery window (today + N-1). Fewer = fewer buckets.
DISCOVERY_WINDOW_DAYS = _int("DISCOVERY_WINDOW_DAYS", 14, min_val=1, max_val=14)

# Time slots per day ("15:00" = ~lunch/afternoon, "19:00" = prime). One slot = half the buckets.
DISCOVERY_TIME_SLOTS = _list_str(
    "DISCOVERY_TIME_SLOTS",
    ["15:00", "19:00"],
    allowed=["15:00", "19:00"],
)

# Party sizes to query per bucket. Fewer = fewer API calls per bucket.
DISCOVERY_PARTY_SIZES = _list_int("DISCOVERY_PARTY_SIZES", [2, 4])

# -----------------------------------------------------------------------------
# Scheduler: concurrency and cooldown
# -----------------------------------------------------------------------------
# Max buckets polled in parallel. Lower = less memory/CPU spike (e.g. 2 for t3.micro).
DISCOVERY_MAX_CONCURRENT_BUCKETS = _int(
    "DISCOVERY_MAX_CONCURRENT_BUCKETS", 8, min_val=1, max_val=28
)

# Seconds before a bucket can be polled again after it finishes.
DISCOVERY_BUCKET_COOLDOWN_SECONDS = _int(
    "DISCOVERY_BUCKET_COOLDOWN_SECONDS", 30, min_val=10, max_val=300
)

# -----------------------------------------------------------------------------
# Resy API: results per bucket
# -----------------------------------------------------------------------------
# Venues per page and max pages per search. Lower = less data per bucket (e.g. 50 and 2 for light).
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
    resy_per_page: int
    resy_max_pages: int


def get_discovery_config() -> DiscoveryConfig:
    return DiscoveryConfig(
        window_days=DISCOVERY_WINDOW_DAYS,
        time_slots=DISCOVERY_TIME_SLOTS,
        party_sizes=DISCOVERY_PARTY_SIZES,
        max_concurrent_buckets=DISCOVERY_MAX_CONCURRENT_BUCKETS,
        bucket_cooldown_seconds=DISCOVERY_BUCKET_COOLDOWN_SECONDS,
        resy_per_page=DISCOVERY_RESY_PER_PAGE,
        resy_max_pages=DISCOVERY_RESY_MAX_PAGES,
    )
