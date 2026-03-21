"""recent_missed_drops for feed Just missed section."""

from alembic import op
import sqlalchemy as sa


revision = "046"
down_revision = "045"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "recent_missed_drops",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("venue_id", sa.String(length=64), nullable=True),
        sa.Column("venue_name", sa.String(length=256), nullable=False),
        sa.Column("image_url", sa.String(length=512), nullable=True),
        sa.Column("neighborhood", sa.String(length=128), nullable=True),
        sa.Column("market", sa.String(length=32), nullable=True),
        sa.Column("slot_time", sa.String(length=32), nullable=True),
        sa.Column("gone_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_recent_missed_drops_venue_id", "recent_missed_drops", ["venue_id"])
    op.create_index("ix_recent_missed_drops_market", "recent_missed_drops", ["market"])
    op.create_index("ix_recent_missed_drops_gone_at", "recent_missed_drops", ["gone_at"])


def downgrade() -> None:
    op.drop_index("ix_recent_missed_drops_gone_at", table_name="recent_missed_drops")
    op.drop_index("ix_recent_missed_drops_market", table_name="recent_missed_drops")
    op.drop_index("ix_recent_missed_drops_venue_id", table_name="recent_missed_drops")
    op.drop_table("recent_missed_drops")
