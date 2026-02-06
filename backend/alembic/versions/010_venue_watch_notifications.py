"""Add venue_watch_notifications for new-venues-found alerts in sidebar

Revision ID: 010
Revises: 009
Create Date: (run alembic upgrade head)

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "010"
down_revision: Union[str, None] = "009"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "venue_watch_notifications",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("session_id", sa.String(64), nullable=False),
        sa.Column("criteria_summary", sa.String(255), nullable=False),
        sa.Column("date_str", sa.String(10), nullable=False),
        sa.Column("party_size", sa.Integer(), nullable=False),
        sa.Column("time_filter", sa.String(32), nullable=True),
        sa.Column("new_count", sa.Integer(), nullable=False),
        sa.Column("new_names_json", sa.Text(), nullable=False),
        sa.Column("read_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    op.create_index("ix_venue_watch_notifications_session_id", "venue_watch_notifications", ["session_id"], unique=False)


def downgrade() -> None:
    op.drop_table("venue_watch_notifications")
