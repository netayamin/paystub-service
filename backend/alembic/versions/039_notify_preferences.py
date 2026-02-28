"""Add notify_preferences: user add (include) / remove (exclude) from default hotlist.

Notify list = (hotlist ∪ included) − excluded. One row per (recipient_id, venue_name_normalized).
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "039"
down_revision: Union[str, None] = "038"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "notify_preferences",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("recipient_id", sa.String(64), nullable=False, index=True),
        sa.Column("venue_name_normalized", sa.String(256), nullable=False),
        sa.Column("preference", sa.String(16), nullable=False, server_default="include"),
        sa.UniqueConstraint("recipient_id", "venue_name_normalized", name="uq_notify_preferences_recipient_venue"),
    )
    op.create_index(
        "ix_notify_preferences_recipient_preference",
        "notify_preferences",
        ["recipient_id", "preference"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index("ix_notify_preferences_recipient_preference", table_name="notify_preferences")
    op.drop_table("notify_preferences")
