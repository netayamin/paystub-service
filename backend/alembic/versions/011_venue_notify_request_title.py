"""Add title to venue_notify_requests for user-defined notification labels

Revision ID: 011
Revises: 010
Create Date: (run alembic upgrade head)

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "011"
down_revision: Union[str, None] = "010"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("venue_notify_requests", sa.Column("title", sa.String(255), nullable=True))


def downgrade() -> None:
    op.drop_column("venue_notify_requests", "title")
