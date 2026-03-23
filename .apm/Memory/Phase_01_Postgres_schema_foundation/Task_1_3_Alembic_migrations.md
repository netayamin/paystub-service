---
agent: Agent_Backend_Data
task_ref: Task 1.3 - Alembic migrations
status: Completed
ad_hoc_delegation: false
compatibility_issues: false
important_findings: true
---

# Task Log: Task 1.3 - Alembic migrations

## Summary

Added revision `048` for `drop_events` evidence columns, `discovery_buckets.successful_poll_count`, CHECK on `eligibility_evidence`, and a BEFORE INSERT trigger so legacy bulk inserts keep working until Task 2.1. Updated ORM models, `tables.py` (`user_notifications` on `ALL_TABLE_NAMES` only), `models.__init__`, and `alembic/env.py` model imports so metadata matches `ALL_TABLE_NAMES`. Verified `poetry run alembic upgrade head` against local Postgres.

## Details

- **048** (`backend/alembic/versions/048_drop_events_eligibility_and_bucket_poll_count.py`): `discovery_buckets.successful_poll_count` added first to shorten lock overlap with concurrent readers; then nullable columns on `drop_events`, `UPDATE` backfills, `NOT NULL`, `ck_drop_events_eligibility_evidence`, trigger `tr_drop_events_insert_defaults` + function `trfn_drop_events_insert_defaults()`.
- **ORM:** `DropEvent` new fields; `DiscoveryBucket.successful_poll_count` with `server_default="0"`.
- **`tables.py`:** `user_notifications` appended to `ALL_TABLE_NAMES` only (not discovery/full reset lists).
- **`app/models/__init__.py`:** `UserNotification` export.
- **`alembic/env.py`:** Import remaining mapped models (including `UserNotification`) so `Base.metadata.tables` equals `ALL_TABLE_NAMES` per existing assert.

## Output

- `backend/alembic/versions/048_drop_events_eligibility_and_bucket_poll_count.py` (new)
- `backend/app/models/drop_event.py`, `discovery_bucket.py`, `db/tables.py`, `models/__init__.py`, `alembic/env.py` (updated)
- Local DB: `alembic_version` = `048` after upgrade

## Issues

- First `alembic upgrade head` attempt hit **Postgres deadlock** (`ALTER TABLE discovery_buckets ADD COLUMN` vs concurrent session). **Resolved** by reordering 048 to add `successful_poll_count` before `drop_events` work and retrying (no app container was running; likely another client on the DB).

## Next Steps

- Task 1.4: feed/hot-path indexes (e.g. partial on `user_facing_opened_at` per design).
- Task 2.1: populate new `drop_events` fields from real poll evidence in `buckets.py`; optional removal or narrowing of insert trigger once all writers set columns explicitly.

## Important Findings

- **Insert trigger:** Required so `pg_insert(DropEvent).values(chunk)` in `buckets.py` (still omitting new columns per task scope) does not violate NOT NULL/CHECK after deploy.
- **048 ordering:** Adding `discovery_buckets` column before long `drop_events` DDL reduced deadlock risk when another session holds locks across both tables.
- **`env.py`:** Assert `Base.metadata.tables == ALL_TABLE_NAMES` requires every mapped model to be imported; previously incomplete imports would fail once `user_notifications` was added to `ALL_TABLE_NAMES`.
