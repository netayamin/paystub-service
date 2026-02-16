"""Venue and market metrics tables for aggregate-before-prune (Phase 2).

Stores per-venue per-day and market-level aggregates so we keep valuable data for
rankings, scarcity scores, and predictions after pruning drop_events.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "029"
down_revision: Union[str, None] = "028"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "venue_metrics",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("venue_id", sa.String(64), nullable=False),
        sa.Column("venue_name", sa.String(256), nullable=True),
        sa.Column("window_date", sa.Date(), nullable=False),
        sa.Column("computed_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("new_drop_count", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("closed_count", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("prime_time_drops", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("off_peak_drops", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("avg_drop_duration_seconds", sa.Float(), nullable=True),
        sa.Column("median_drop_duration_seconds", sa.Float(), nullable=True),
        sa.Column("scarcity_score", sa.Float(), nullable=True),
        sa.Column("volatility_score", sa.Float(), nullable=True),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_venue_metrics_venue_id", "venue_metrics", ["venue_id"], unique=False)
    op.create_index("ix_venue_metrics_window_date", "venue_metrics", ["window_date"], unique=False)
    op.create_index(
        "uq_venue_metrics_venue_window",
        "venue_metrics",
        ["venue_id", "window_date"],
        unique=True,
    )

    op.create_table(
        "market_metrics",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("window_date", sa.Date(), nullable=False),
        sa.Column("metric_type", sa.String(64), nullable=False),
        sa.Column("value_json", sa.Text(), nullable=True),
        sa.Column("computed_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_market_metrics_window_date", "market_metrics", ["window_date"], unique=False)
    op.create_index("ix_market_metrics_metric_type", "market_metrics", ["metric_type"], unique=False)
    op.create_unique_constraint(
        "uq_market_metrics_window_type",
        "market_metrics",
        ["window_date", "metric_type"],
    )


def downgrade() -> None:
    op.drop_constraint("uq_market_metrics_window_type", "market_metrics", type_="unique")
    op.drop_index("ix_market_metrics_metric_type", table_name="market_metrics")
    op.drop_index("ix_market_metrics_window_date", table_name="market_metrics")
    op.drop_table("market_metrics")
    op.drop_index("uq_venue_metrics_venue_window", table_name="venue_metrics")
    op.drop_index("ix_venue_metrics_window_date", table_name="venue_metrics")
    op.drop_index("ix_venue_metrics_venue_id", table_name="venue_metrics")
    op.drop_table("venue_metrics")
