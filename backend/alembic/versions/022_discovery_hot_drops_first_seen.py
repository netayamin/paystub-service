"""Add hot_drops_json: persist first-seen time per drop so we don't refresh 'opened' when slot stays open.

Revision ID: 022
Revises: 021
Create Date: (run alembic upgrade head)

hot_drops_json = [ {"name": "Venue A", "detected_at": "ISO"}, ... ] for venues still open;
we keep the original detected_at until the venue disappears from current snapshot.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "022"
down_revision: Union[str, None] = "021"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "discovery_scans",
        sa.Column("hot_drops_json", sa.Text(), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("discovery_scans", "hot_drops_json")
