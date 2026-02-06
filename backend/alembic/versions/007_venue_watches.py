"""Add venue_watches for background check every 1–2 min

Revision ID: 007
Revises: 006
Create Date: (run alembic upgrade head)

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "007"
down_revision: Union[str, None] = "006"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "venue_watches",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("criteria_key", sa.String(256), nullable=False),
        sa.Column("interval_minutes", sa.Integer(), nullable=False, server_default="2"),
        sa.Column("last_checked_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("last_result_json", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    op.create_index("ix_venue_watches_criteria_key", "venue_watches", ["criteria_key"], unique=True)


def downgrade() -> None:
    op.drop_table("venue_watches")
