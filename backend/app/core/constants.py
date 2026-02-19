"""
Centralized constants for scheduler and discovery (Encapsulate What Changes).

Change job IDs or intervals here instead of scattering literals across main and routes.
Discovery concurrency/cooldown come from discovery_config (env-driven for light vs full).
"""
from app.core.discovery_config import (
    DISCOVERY_BUCKET_COOLDOWN_SECONDS,
    DISCOVERY_MAX_CONCURRENT_BUCKETS,
)

# Scheduler job IDs (must match ids used in main.py add_job)
DISCOVERY_BUCKET_JOB_ID = "discovery_bucket"
DISCOVERY_SLIDING_WINDOW_JOB_ID = "discovery_sliding_window"

# Discovery: queue + re-enqueue model. Tick every N seconds; each tick dispatches up to MAX_CONCURRENT_BUCKETS
# buckets that are "ready" (cooldown elapsed). Values from discovery_config (env: DISCOVERY_MAX_CONCURRENT_BUCKETS, etc.).
DISCOVERY_TICK_SECONDS = 10
# Legacy name for "next scan" fallback (scheduler interval)
DISCOVERY_POLL_INTERVAL_SECONDS = DISCOVERY_TICK_SECONDS

# Drops opened within this many minutes appear in JUST OPENED; older drops appear in STILL OPEN only
JUST_OPENED_WITHIN_MINUTES = 10
