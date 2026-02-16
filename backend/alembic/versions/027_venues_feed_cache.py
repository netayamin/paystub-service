"""Add venues table (venue normalization) and feed_cache table (materialized feed).

Revision ID: 027
Revises: 026
Create Date: (run alembic upgrade head)

- venues: canonical venue_id, venue_name; deduplicates across drop_events.
- feed_cache: precomputed just-opened + feed segments for fast API reads.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "027"
down_revision: Union[str, None] = "026"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "venues",
        sa.Column("venue_id", sa.String(64), primary_key=True),
        sa.Column("venue_name", sa.String(256), nullable=True),
        sa.Column("first_seen_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column("last_seen_at", sa.DateTime(timezone=True), server_default=sa.func.now(), onupdate=sa.func.now()),
    )
    op.create_table(
        "feed_cache",
        sa.Column("cache_key", sa.String(64), primary_key=True),
        sa.Column("payload_json", sa.Text(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), onupdate=sa.func.now()),
    )


def downgrade() -> None:
    op.drop_table("feed_cache")
    op.drop_table("venues")
