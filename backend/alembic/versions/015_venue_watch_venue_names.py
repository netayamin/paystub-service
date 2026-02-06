"""Add venue_names_json to venue_watches for watch-specific venue list

Revision ID: 015
Revises: 014
Create Date: (run alembic upgrade head)

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "015"
down_revision: Union[str, None] = "014"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "venue_watches",
        sa.Column("venue_names_json", sa.Text(), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("venue_watches", "venue_names_json")
