"""Add watch_list table for hourly Resy availability checks

Revision ID: 005
Revises: 004
Create Date: (run alembic upgrade head)

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "005"
down_revision: Union[str, None] = "004"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "watch_list",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("venue_id", sa.Integer(), nullable=False),
        sa.Column("venue_name", sa.String(255), nullable=True),
        sa.Column("party_size", sa.Integer(), nullable=False, server_default="2"),
        sa.Column("preferred_slot", sa.String(32), nullable=True),
        sa.Column("notify_only", sa.Boolean(), nullable=False, server_default="true"),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    op.create_index("ix_watch_list_venue_id", "watch_list", ["venue_id"], unique=False)


def downgrade() -> None:
    op.drop_table("watch_list")
