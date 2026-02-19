"""Scalable discovery: projection (slot_availability) + sessions (availability_sessions).

- slot_availability: current state per (bucket_id, slot_id). Soft state (open/closed + timestamps). No deletes.
- availability_sessions: one row per open window (opened_at, closed_at). Append/update only.
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "034"
down_revision: Union[str, None] = "033"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "slot_availability",
        sa.Column("bucket_id", sa.String(20), nullable=False),
        sa.Column("slot_id", sa.String(64), nullable=False),
        sa.Column("state", sa.String(16), nullable=False, server_default="open"),
        sa.Column("opened_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("closed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("last_seen_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("venue_id", sa.String(64), nullable=True),
        sa.Column("venue_name", sa.String(256), nullable=True),
        sa.Column("payload_json", sa.Text(), nullable=True),
        sa.Column("run_id", sa.String(64), nullable=True),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("time_bucket", sa.String(16), nullable=True),
        sa.Column("slot_date", sa.String(10), nullable=True),
        sa.Column("slot_time", sa.String(32), nullable=True),
        sa.Column("provider", sa.String(32), nullable=True, server_default="resy"),
        sa.Column("neighborhood", sa.String(128), nullable=True),
        sa.Column("price_range", sa.String(32), nullable=True),
        sa.PrimaryKeyConstraint("bucket_id", "slot_id"),
    )
    op.create_index("ix_slot_availability_state", "slot_availability", ["state"], unique=False)
    op.create_index("ix_slot_availability_opened_at", "slot_availability", ["opened_at"], unique=False)
    op.create_index("ix_slot_availability_bucket_state", "slot_availability", ["bucket_id", "state"], unique=False)

    op.create_table(
        "availability_sessions",
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
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_availability_sessions_bucket_slot", "availability_sessions", ["bucket_id", "slot_id"], unique=False)
    op.create_index("ix_availability_sessions_closed_at", "availability_sessions", ["closed_at"], unique=False)


def downgrade() -> None:
    op.drop_index("ix_availability_sessions_closed_at", table_name="availability_sessions")
    op.drop_index("ix_availability_sessions_bucket_slot", table_name="availability_sessions")
    op.drop_table("availability_sessions")
    op.drop_index("ix_slot_availability_bucket_state", table_name="slot_availability")
    op.drop_index("ix_slot_availability_opened_at", table_name="slot_availability")
    op.drop_index("ix_slot_availability_state", table_name="slot_availability")
    op.drop_table("slot_availability")
