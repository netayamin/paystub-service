"""Add session_id to venue_watches, unique (session_id, criteria_key)

Revision ID: 008
Revises: 007
Create Date: (run alembic upgrade head)

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "008"
down_revision: Union[str, None] = "007"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("venue_watches", sa.Column("session_id", sa.String(64), nullable=True))
    op.create_index("ix_venue_watches_session_id", "venue_watches", ["session_id"], unique=False)
    op.drop_index("ix_venue_watches_criteria_key", table_name="venue_watches")
    op.create_index("ix_venue_watches_criteria_key", "venue_watches", ["criteria_key"], unique=False)
    op.create_unique_constraint("uq_venue_watch_session_criteria", "venue_watches", ["session_id", "criteria_key"])


def downgrade() -> None:
    op.drop_constraint("uq_venue_watch_session_criteria", "venue_watches", type_="unique")
    op.drop_index("ix_venue_watches_criteria_key", table_name="venue_watches")
    op.create_index("ix_venue_watches_criteria_key", "venue_watches", ["criteria_key"], unique=True)
    op.drop_index("ix_venue_watches_session_id", table_name="venue_watches")
    op.drop_column("venue_watches", "session_id")
