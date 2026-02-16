"""Venue rolling metrics: drop frequency and rarity (rarely-opens = unique opportunity)."""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "030"
down_revision: Union[str, None] = "029"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "venue_rolling_metrics",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("venue_id", sa.String(64), nullable=False),
        sa.Column("venue_name", sa.String(256), nullable=True),
        sa.Column("as_of_date", sa.Date(), nullable=False),
        sa.Column("window_days", sa.Integer(), nullable=False, server_default="14"),
        sa.Column("computed_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("total_new_drops", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("days_with_drops", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("drop_frequency_per_day", sa.Float(), nullable=True),
        sa.Column("rarity_score", sa.Float(), nullable=True),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_venue_rolling_metrics_venue_id", "venue_rolling_metrics", ["venue_id"], unique=False)
    op.create_index("ix_venue_rolling_metrics_as_of_date", "venue_rolling_metrics", ["as_of_date"], unique=False)
    op.create_unique_constraint(
        "uq_venue_rolling_venue_as_of",
        "venue_rolling_metrics",
        ["venue_id", "as_of_date"],
    )


def downgrade() -> None:
    op.drop_constraint("uq_venue_rolling_venue_as_of", "venue_rolling_metrics", type_="unique")
    op.drop_index("ix_venue_rolling_metrics_as_of_date", table_name="venue_rolling_metrics")
    op.drop_index("ix_venue_rolling_metrics_venue_id", table_name="venue_rolling_metrics")
    op.drop_table("venue_rolling_metrics")
