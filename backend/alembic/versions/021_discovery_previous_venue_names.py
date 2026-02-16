"""Add previous_venue_names_json for scalable comparison (names only, no full payload)

Revision ID: 021
Revises: 020
Create Date: (run alembic upgrade head)

Storing previous snapshot as a JSON array of venue names keeps comparison fast and
avoids loading/storing duplicate full payloads. Just-opened = current names not in previous set.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "021"
down_revision: Union[str, None] = "020"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "discovery_scans",
        sa.Column("previous_venue_names_json", sa.Text(), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("discovery_scans", "previous_venue_names_json")
