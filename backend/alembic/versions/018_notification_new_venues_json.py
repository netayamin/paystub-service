"""Add new_venues_json to venue_watch_notifications for image_url and resy_url

Revision ID: 018
Revises: 017
Create Date: (run alembic upgrade head)

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "018"
down_revision: Union[str, None] = "017"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "venue_watch_notifications",
        sa.Column("new_venues_json", sa.Text(), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("venue_watch_notifications", "new_venues_json")
