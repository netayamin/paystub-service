"""user_behavior_events for conversion funnel; venue_metrics.closed_duration_sum_sq for volatility."""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "052"
down_revision: Union[str, None] = "051"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "venue_metrics",
        sa.Column("closed_duration_sum_sq", sa.Float(), nullable=True),
    )
    op.create_table(
        "user_behavior_events",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("recipient_id", sa.String(length=128), nullable=False),
        sa.Column("event_type", sa.String(length=64), nullable=False),
        sa.Column("occurred_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("venue_id", sa.String(length=64), nullable=True),
        sa.Column("venue_name", sa.String(length=256), nullable=True),
        sa.Column("drop_event_id", sa.Integer(), nullable=True),
        sa.Column("notification_id", sa.Integer(), nullable=True),
        sa.Column("time_to_action_seconds", sa.Integer(), nullable=True),
        sa.Column("market", sa.String(length=32), nullable=True),
        sa.Column("metadata_json", sa.Text(), nullable=True),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_user_behavior_events_recipient_occurred", "user_behavior_events", ["recipient_id", "occurred_at"], unique=False)
    op.create_index("ix_user_behavior_events_event_type_occurred", "user_behavior_events", ["event_type", "occurred_at"], unique=False)
    op.create_index("ix_user_behavior_events_occurred_at", "user_behavior_events", ["occurred_at"], unique=False)


def downgrade() -> None:
    op.drop_index("ix_user_behavior_events_occurred_at", table_name="user_behavior_events")
    op.drop_index("ix_user_behavior_events_event_type_occurred", table_name="user_behavior_events")
    op.drop_index("ix_user_behavior_events_recipient_occurred", table_name="user_behavior_events")
    op.drop_table("user_behavior_events")
    op.drop_column("venue_metrics", "closed_duration_sum_sq")
