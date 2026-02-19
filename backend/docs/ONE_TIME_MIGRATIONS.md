# One-time data migrations

No schema change (Alembic handles schema). These scripts adjust **data** after a logic change. Run once per environment when you deploy the related change.

---

## migrate_closed_events_to_aggregation.py

**When:** After deploying the change that "when an event closes we write to aggregation and remove it from drop_events."

**What it does:** Finds all existing `CLOSED` events in `drop_events`, writes them into `venue_metrics` and `market_metrics`, then deletes those CLOSED rows and the corresponding `NEW_DROP` rows. Shrinks `drop_events` and aligns existing data with the new rule.

**Run once (per DB):**

```bash
cd backend
poetry run python scripts/migrate_closed_events_to_aggregation.py
```

**Dry run (see counts only):**

```bash
poetry run python scripts/migrate_closed_events_to_aggregation.py --dry-run
```

Safe to run with the backend up (uses its own session). No schema changes.
