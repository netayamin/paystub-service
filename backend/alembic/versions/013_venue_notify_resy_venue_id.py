"""Add resy_venue_id to venue_notify_requests for ID-based matching

Revision ID: 013
Revises: 012
Create Date: (run alembic upgrade head)

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "013"
down_revision: Union[str, None] = "012"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "venue_notify_requests",
        sa.Column("resy_venue_id", sa.Integer(), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("venue_notify_requests", "resy_venue_id")
