"""Drop discovery_scans table — fresh start; discovery uses discovery_buckets + drop_events only.

Revision ID: 024
Revises: 023
Create Date: (run alembic upgrade head)

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "024"
down_revision: Union[str, None] = "023"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.drop_table("discovery_scans")


def downgrade() -> None:
    op.create_table(
        "discovery_scans",
        sa.Column("date_str", sa.String(10), primary_key=True),
        sa.Column("venues_json", sa.Text(), nullable=False),
        sa.Column("previous_venues_json", sa.Text(), nullable=True),
        sa.Column("hot_drops_json", sa.Text(), nullable=True),
        sa.Column("scanned_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
