"""Discovery blueprint: discovery_buckets + drop_events (bucket = date + time_slot; slot_id + dedupe).

Revision ID: 023
Revises: 022
Create Date: (run alembic upgrade head)

- discovery_buckets: one row per (date_str, time_slot); baseline/prev as JSON arrays of slot_id.
- drop_events: emitted drops with dedupe_key for idempotent insert.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "023"
down_revision: Union[str, None] = "022"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "discovery_buckets",
        sa.Column("bucket_id", sa.String(20), primary_key=True),
        sa.Column("date_str", sa.String(10), nullable=False),
        sa.Column("time_slot", sa.String(5), nullable=False),
        sa.Column("baseline_slot_ids_json", sa.Text(), nullable=True),
        sa.Column("prev_slot_ids_json", sa.Text(), nullable=True),
        sa.Column("scanned_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    op.create_index("ix_discovery_buckets_date_str", "discovery_buckets", ["date_str"])

    op.create_table(
        "drop_events",
        sa.Column("id", sa.Integer(), autoincrement=True, primary_key=True),
        sa.Column("bucket_id", sa.String(20), nullable=False),
        sa.Column("slot_id", sa.String(64), nullable=False),
        sa.Column("opened_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("venue_id", sa.String(64), nullable=True),
        sa.Column("venue_name", sa.String(256), nullable=True),
        sa.Column("payload_json", sa.Text(), nullable=True),
        sa.Column("dedupe_key", sa.String(128), nullable=False),
    )
    op.create_index("ix_drop_events_bucket_id", "drop_events", ["bucket_id"])
    op.create_index("ix_drop_events_slot_id", "drop_events", ["slot_id"])
    op.create_index("ix_drop_events_opened_at", "drop_events", ["opened_at"])
    op.create_unique_constraint("uq_drop_events_dedupe_key", "drop_events", ["dedupe_key"])


def downgrade() -> None:
    op.drop_table("drop_events")
    op.drop_table("discovery_buckets")
