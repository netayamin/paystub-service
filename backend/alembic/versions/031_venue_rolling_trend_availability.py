"""Venue rolling: trend (last 7d vs prev 7d) and availability_rate_14d."""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "031"
down_revision: Union[str, None] = "030"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("venue_rolling_metrics", sa.Column("total_last_7d", sa.Integer(), nullable=True))
    op.add_column("venue_rolling_metrics", sa.Column("total_prev_7d", sa.Integer(), nullable=True))
    op.add_column("venue_rolling_metrics", sa.Column("trend_pct", sa.Float(), nullable=True))
    op.add_column("venue_rolling_metrics", sa.Column("availability_rate_14d", sa.Float(), nullable=True))


def downgrade() -> None:
    op.drop_column("venue_rolling_metrics", "availability_rate_14d")
    op.drop_column("venue_rolling_metrics", "trend_pct")
    op.drop_column("venue_rolling_metrics", "total_prev_7d")
    op.drop_column("venue_rolling_metrics", "total_last_7d")
