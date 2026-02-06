"""Add venue_search_snapshots for check-for-new-venues diff

Revision ID: 006
Revises: 005
Create Date: (run alembic upgrade head)

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "006"
down_revision: Union[str, None] = "005"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "venue_search_snapshots",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("criteria_key", sa.String(256), nullable=False),
        sa.Column("venue_names_json", sa.Text(), nullable=True),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    op.create_index("ix_venue_search_snapshots_criteria_key", "venue_search_snapshots", ["criteria_key"], unique=True)


def downgrade() -> None:
    op.drop_table("venue_search_snapshots")
