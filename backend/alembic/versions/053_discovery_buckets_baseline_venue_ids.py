"""Add baseline_venue_ids_json to discovery_buckets for venue-level drop guard.

revision = '053'
revises = '052'
"""

from alembic import op
import sqlalchemy as sa


revision = "053"
down_revision = "052"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "discovery_buckets",
        sa.Column("baseline_venue_ids_json", sa.Text(), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("discovery_buckets", "baseline_venue_ids_json")
