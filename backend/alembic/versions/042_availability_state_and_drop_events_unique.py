"""availability_state (one row per bucket+slot, no history) + drop_events unique on (bucket, slot, venue, detected_minute)."""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "042"
down_revision: Union[str, None] = "041"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # availability_state: latest snapshot only per (bucket_id, slot_id). Replaces session history.
    op.create_table(
        "availability_state",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("bucket_id", sa.String(20), nullable=False),
        sa.Column("slot_id", sa.String(64), nullable=False),
        sa.Column("opened_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("closed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("duration_seconds", sa.Integer(), nullable=True),
        sa.Column("venue_id", sa.String(64), nullable=True),
        sa.Column("venue_name", sa.String(256), nullable=True),
        sa.Column("slot_date", sa.String(10), nullable=True),
        sa.Column("provider", sa.String(32), nullable=True, server_default="resy"),
        sa.Column("aggregated_at", sa.DateTime(timezone=True), nullable=True),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("bucket_id", "slot_id", name="uq_availability_state_bucket_slot"),
    )
    op.create_index("ix_availability_state_bucket_id", "availability_state", ["bucket_id"])
    op.create_index("ix_availability_state_slot_id", "availability_state", ["slot_id"])
    op.create_index("ix_availability_state_closed_at", "availability_state", ["closed_at"])

    # drop_events: unique on (bucket_id, slot_id, venue_id, detected_minute) to prevent flapping duplicates.
    # Use (opened_at AT TIME ZONE 'UTC') so date_trunc is immutable (required for unique index).
    op.execute(
        sa.text(
            "CREATE UNIQUE INDEX uq_drop_events_bucket_slot_venue_minute ON drop_events "
            "(bucket_id, slot_id, COALESCE(venue_id, ''), (date_trunc('minute', (opened_at AT TIME ZONE 'UTC'))))"
        )
    )


def downgrade() -> None:
    op.execute(sa.text("DROP INDEX IF EXISTS uq_drop_events_bucket_slot_venue_minute"))
    op.drop_index("ix_availability_state_closed_at", table_name="availability_state")
    op.drop_index("ix_availability_state_slot_id", table_name="availability_state")
    op.drop_index("ix_availability_state_bucket_id", table_name="availability_state")
    op.drop_table("availability_state")
