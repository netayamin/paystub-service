"""Drop venue_watch tables: venue_watch_notifications, venue_notify_requests, venue_watches.

Revision ID: 025
Revises: 024
Create Date: (run alembic upgrade head)

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "025"
down_revision: Union[str, None] = "024"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.drop_table("venue_watch_notifications")
    op.drop_table("venue_notify_requests")
    op.drop_table("venue_watches")


def downgrade() -> None:
    # Recreate minimal table shapes for rollback (columns from latest migrations)
    op.create_table(
        "venue_watches",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("criteria_key", sa.String(128), nullable=False),
        sa.Column("interval_minutes", sa.Integer(), nullable=False),
        sa.Column("session_id", sa.String(64), nullable=True),
        sa.Column("venue_names_json", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_venue_watches_criteria_key", "venue_watches", ["criteria_key"], unique=False)
    op.create_index("ix_venue_watches_session_id", "venue_watches", ["session_id"], unique=False)
    op.create_unique_constraint("uq_venue_watch_session_criteria", "venue_watches", ["session_id", "criteria_key"])

    op.create_table(
        "venue_notify_requests",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("session_id", sa.String(64), nullable=False),
        sa.Column("title", sa.String(255), nullable=True),
        sa.Column("venue_name", sa.String(255), nullable=False),
        sa.Column("resy_venue_id", sa.Integer(), nullable=True),
        sa.Column("date_str", sa.String(10), nullable=False),
        sa.Column("party_size", sa.Integer(), nullable=False),
        sa.Column("time_filter", sa.String(32), nullable=True),
        sa.Column("status", sa.String(16), nullable=False),
        sa.Column("result_json", sa.Text(), nullable=True),
        sa.Column("last_checked_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_venue_notify_requests_session_id", "venue_notify_requests", ["session_id"], unique=False)

    op.create_table(
        "venue_watch_notifications",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("session_id", sa.String(64), nullable=False),
        sa.Column("criteria_summary", sa.String(255), nullable=False),
        sa.Column("date_str", sa.String(10), nullable=False),
        sa.Column("party_size", sa.Integer(), nullable=False),
        sa.Column("time_filter", sa.String(32), nullable=True),
        sa.Column("new_count", sa.Integer(), nullable=False),
        sa.Column("new_names_json", sa.Text(), nullable=False),
        sa.Column("new_venues_json", sa.Text(), nullable=True),
        sa.Column("read_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_venue_watch_notifications_session_id", "venue_watch_notifications", ["session_id"], unique=False)
