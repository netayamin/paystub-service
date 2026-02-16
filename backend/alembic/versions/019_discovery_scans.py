"""Add discovery_scans table for Just opened up (auto-scan next 3 days)

Revision ID: 019
Revises: 018
Create Date: (run alembic upgrade head)

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "019"
down_revision: Union[str, None] = "018"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "discovery_scans",
        sa.Column("date_str", sa.String(10), primary_key=True),
        sa.Column("venues_json", sa.Text(), nullable=False),
        sa.Column("scanned_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )


def downgrade() -> None:
    op.drop_table("discovery_scans")
