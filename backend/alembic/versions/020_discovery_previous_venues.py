"""Add previous_venues_json to discovery_scans for just-opened diff

Revision ID: 020
Revises: 019
Create Date: (run alembic upgrade head)

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "020"
down_revision: Union[str, None] = "019"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("discovery_scans", sa.Column("previous_venues_json", sa.Text(), nullable=True))


def downgrade() -> None:
    op.drop_column("discovery_scans", "previous_venues_json")
