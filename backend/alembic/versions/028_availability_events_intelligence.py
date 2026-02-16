"""Availability event intelligence: event_type (NEW_DROP/CLOSED), closed_at, drop_duration_seconds, time_bucket, slot identity.

Phase 1 of market intelligence: store transitions and duration, not just drops.
- NEW_DROP: slot became available (existing behavior).
- CLOSED: slot was available, now gone; we store closed_at and drop_duration_seconds.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "028"
down_revision: Union[str, None] = "027"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("drop_events", sa.Column("event_type", sa.String(20), nullable=False, server_default="NEW_DROP"))
    op.add_column("drop_events", sa.Column("closed_at", sa.DateTime(timezone=True), nullable=True))
    op.add_column("drop_events", sa.Column("drop_duration_seconds", sa.Integer(), nullable=True))
    op.add_column("drop_events", sa.Column("time_bucket", sa.String(16), nullable=True))  # prime | off_peak
    op.add_column("drop_events", sa.Column("slot_date", sa.String(10), nullable=True))   # YYYY-MM-DD
    op.add_column("drop_events", sa.Column("slot_time", sa.String(32), nullable=True))   # time part of slot
    op.add_column("drop_events", sa.Column("provider", sa.String(32), nullable=True, server_default="resy"))
    op.add_column("drop_events", sa.Column("neighborhood", sa.String(128), nullable=True))
    op.add_column("drop_events", sa.Column("price_range", sa.String(32), nullable=True))
    op.create_index("ix_drop_events_event_type", "drop_events", ["event_type"], unique=False)
    op.create_index("ix_drop_events_closed_at", "drop_events", ["closed_at"], unique=False)


def downgrade() -> None:
    op.drop_index("ix_drop_events_closed_at", table_name="drop_events")
    op.drop_index("ix_drop_events_event_type", table_name="drop_events")
    op.drop_column("drop_events", "price_range")
    op.drop_column("drop_events", "neighborhood")
    op.drop_column("drop_events", "provider")
    op.drop_column("drop_events", "slot_time")
    op.drop_column("drop_events", "slot_date")
    op.drop_column("drop_events", "time_bucket")
    op.drop_column("drop_events", "drop_duration_seconds")
    op.drop_column("drop_events", "closed_at")
    op.drop_column("drop_events", "event_type")
