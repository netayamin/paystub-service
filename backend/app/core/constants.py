"""
Centralized constants for scheduler and discovery (Encapsulate What Changes).

Change job IDs or intervals here instead of scattering literals across main and routes.
Discovery concurrency/cooldown come from discovery_config (env-driven for light vs full).
"""
from app.core.discovery_config import (
    DISCOVERY_BUCKET_COOLDOWN_SECONDS,
    DISCOVERY_MAX_CONCURRENT_BUCKETS,
    DISCOVERY_TICK_SECONDS,
)

# Scheduler job IDs (must match ids used in main.py add_job)
DISCOVERY_BUCKET_JOB_ID = "discovery_bucket"
DISCOVERY_SLIDING_WINDOW_JOB_ID = "discovery_sliding_window"
PUSH_JOB_ID = "push_new_drops"
PUSH_INTERVAL_SECONDS = 60

# Discovery tick from .env (discovery_config); legacy name for "next scan" fallback
DISCOVERY_POLL_INTERVAL_SECONDS = DISCOVERY_TICK_SECONDS

# Drops opened within this many minutes appear in JUST OPENED; older drops appear in STILL OPEN only
JUST_OPENED_WITHIN_MINUTES = 10

# Scalability: hard caps so DB and response size stay bounded (avoid timeouts)
DISCOVERY_JUST_OPENED_LIMIT = 2000  # max slot_availability rows per just-opened request
DISCOVERY_STILL_OPEN_LIMIT = 3000   # max slot_availability rows for still-open
DISCOVERY_ROLLING_METRICS_LIMIT = 4000  # max venue_rolling_metrics rows for feed enrichment
DISCOVERY_FEED_LIMIT = 100          # max rows for GET /feed
DISCOVERY_MAX_VENUES_PER_DATE = 500  # cap venues per date in just-opened/still-open
# Retention: run slot/drop/session pruning every N discovery ticks (in addition to daily sliding window)
DISCOVERY_PRUNE_EVERY_N_TICKS = 5   # ~50s at 10s tick; keeps tables bounded, avoids DB bloat
# drop_events: prune rows older than this (and already pushed) so table does not grow unbounded
DROP_EVENTS_RETENTION_DAYS = 7
# venue_metrics, market_metrics: keep this many days of history (daily prune in sliding window)
METRICS_RETENTION_DAYS = 90
# venues: prune rows not seen in this many days (daily prune in sliding window)
VENUES_RETENTION_DAYS = 90
