"""Hot-path indexes on canonical user_facing_opened_at; market composite per TARGET_SCHEMA §3.

Indexes and target queries:
- ix_drop_events_user_facing_opened_at: time-window scans (get_just_opened*, TTL dedupe, aggregate_open_drops).
- ix_drop_events_push_sent_user_facing_opened_at (partial): prune_old_drop_events time branch (pushed rows).
  (push_job uses btree on user_facing_opened_at + push_sent_at IS NULL filter.)
- ix_drop_events_market_user_facing_opened_at: replaces ix_drop_events_market; market + recency (feed/ranking).
- ix_drop_events_bucket_id_user_facing_opened_at: per-bucket recent drops (poll TTL dedupe).
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "049"
down_revision: Union[str, None] = "048"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.drop_index("ix_drop_events_opened_at", table_name="drop_events")
    op.drop_index("ix_drop_events_market", table_name="drop_events")

    op.create_index(
        "ix_drop_events_user_facing_opened_at",
        "drop_events",
        ["user_facing_opened_at"],
        unique=False,
    )
    op.create_index(
        "ix_drop_events_push_sent_user_facing_opened_at",
        "drop_events",
        ["user_facing_opened_at"],
        unique=False,
        postgresql_where=sa.text("push_sent_at IS NOT NULL"),
    )
    op.execute(
        sa.text(
            "CREATE INDEX ix_drop_events_market_user_facing_opened_at "
            "ON drop_events (market, user_facing_opened_at DESC)"
        )
    )
    op.create_index(
        "ix_drop_events_bucket_id_user_facing_opened_at",
        "drop_events",
        ["bucket_id", "user_facing_opened_at"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index(
        "ix_drop_events_bucket_id_user_facing_opened_at",
        table_name="drop_events",
    )
    op.execute(sa.text("DROP INDEX IF EXISTS ix_drop_events_market_user_facing_opened_at"))
    op.drop_index(
        "ix_drop_events_push_sent_user_facing_opened_at",
        table_name="drop_events",
        postgresql_where=sa.text("push_sent_at IS NOT NULL"),
    )
    op.drop_index("ix_drop_events_user_facing_opened_at", table_name="drop_events")

    op.create_index("ix_drop_events_market", "drop_events", ["market"], unique=False)
    op.create_index("ix_drop_events_opened_at", "drop_events", ["opened_at"], unique=False)
