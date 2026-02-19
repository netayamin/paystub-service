"""User notifications: persisted read state and metadata for scale and customization.

Best-practice layout:
- recipient_id: who receives (e.g. 'default' or client session/device id; later user_id when you add auth).
- type: notification kind ('new_drop', etc.) for future filtering and preferences.
- read_at: NULL = unread; set when user marks as read (persisted across devices).
- metadata: JSONB for type-specific payload (name, date_str, resy_url, slots, ...) without schema churn.
Index supports: "my recent notifications", "my unread count", and filtering by type later.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import JSONB

revision: str = "033"
down_revision: Union[str, None] = "032"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "user_notifications",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("recipient_id", sa.String(64), nullable=False),
        sa.Column("type", sa.String(32), nullable=False, server_default="new_drop"),
        sa.Column("read_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("metadata", JSONB, nullable=False, server_default="{}"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_user_notifications_recipient_read_created",
        "user_notifications",
        ["recipient_id", "read_at", "created_at"],
        unique=False,
        postgresql_ops={"created_at": "DESC"},
    )
    op.create_index("ix_user_notifications_recipient_id", "user_notifications", ["recipient_id"], unique=False)
    op.create_index("ix_user_notifications_type", "user_notifications", ["type"], unique=False)


def downgrade() -> None:
    op.drop_index("ix_user_notifications_type", table_name="user_notifications")
    op.drop_index("ix_user_notifications_recipient_id", table_name="user_notifications")
    op.drop_index("ix_user_notifications_recipient_read_created", table_name="user_notifications")
    op.drop_table("user_notifications")
