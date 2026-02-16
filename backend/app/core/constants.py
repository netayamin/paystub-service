"""
Centralized constants for scheduler and discovery (Encapsulate What Changes).

Change job IDs or intervals here instead of scattering literals across main and routes.
"""
# Scheduler job IDs (must match ids used in main.py add_job)
DISCOVERY_BUCKET_JOB_ID = "discovery_bucket"
DISCOVERY_SLIDING_WINDOW_JOB_ID = "discovery_sliding_window"

# Discovery: queue + re-enqueue model. Tick every N seconds; each tick dispatches up to MAX_CONCURRENT_BUCKETS
# buckets that are "ready" (cooldown elapsed). When a bucket finishes it re-enters the queue (cooldown = 30s).
DISCOVERY_TICK_SECONDS = 10
DISCOVERY_BUCKET_COOLDOWN_SECONDS = 30
DISCOVERY_MAX_CONCURRENT_BUCKETS = 8
# Legacy name for "next scan" fallback (scheduler interval)
DISCOVERY_POLL_INTERVAL_SECONDS = DISCOVERY_TICK_SECONDS

# Drops opened within this many minutes appear in JUST OPENED; older drops appear in STILL OPEN only
JUST_OPENED_WITHIN_MINUTES = 10
