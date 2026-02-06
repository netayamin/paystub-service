"""Add venue_notify_requests: notify when specific venue is available

Revision ID: 009
Revises: 008
Create Date: (run alembic upgrade head)

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "009"
down_revision: Union[str, None] = "008"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "venue_notify_requests",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("session_id", sa.String(64), nullable=False),
        sa.Column("venue_name", sa.String(255), nullable=False),
        sa.Column("date_str", sa.String(10), nullable=False),
        sa.Column("party_size", sa.Integer(), nullable=False, server_default="2"),
        sa.Column("time_filter", sa.String(32), nullable=True),
        sa.Column("status", sa.String(16), nullable=False, server_default="pending"),
        sa.Column("result_json", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    op.create_index("ix_venue_notify_requests_session_id", "venue_notify_requests", ["session_id"], unique=False)


def downgrade() -> None:
    op.drop_table("venue_notify_requests")
