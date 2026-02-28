"""Create drop_events table if missing (e.g. DB was at head but table was dropped)."""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "041"
down_revision: Union[str, None] = "040"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Create drop_events only if it doesn't exist (current schema matches model after 037)
    conn = op.get_bind()
    result = conn.execute(sa.text(
        "SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'drop_events'"
    ))
    if result.fetchone() is not None:
        return
    op.create_table(
        "drop_events",
        sa.Column("id", sa.Integer(), autoincrement=True, primary_key=True),
        sa.Column("bucket_id", sa.String(20), nullable=False),
        sa.Column("slot_id", sa.String(64), nullable=False),
        sa.Column("opened_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("venue_id", sa.String(64), nullable=True),
        sa.Column("venue_name", sa.String(256), nullable=True),
        sa.Column("payload_json", sa.Text(), nullable=True),
        sa.Column("dedupe_key", sa.String(128), nullable=False),
        sa.Column("closed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("drop_duration_seconds", sa.Integer(), nullable=True),
        sa.Column("time_bucket", sa.String(16), nullable=True),
        sa.Column("slot_date", sa.String(10), nullable=True),
        sa.Column("slot_time", sa.String(32), nullable=True),
        sa.Column("provider", sa.String(32), nullable=True, server_default="resy"),
        sa.Column("neighborhood", sa.String(128), nullable=True),
        sa.Column("price_range", sa.String(32), nullable=True),
        sa.Column("push_sent_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index("ix_drop_events_bucket_id", "drop_events", ["bucket_id"])
    op.create_index("ix_drop_events_slot_id", "drop_events", ["slot_id"])
    op.create_index("ix_drop_events_opened_at", "drop_events", ["opened_at"])
    op.create_unique_constraint("uq_drop_events_dedupe_key", "drop_events", ["dedupe_key"])


def downgrade() -> None:
    op.drop_table("drop_events")
