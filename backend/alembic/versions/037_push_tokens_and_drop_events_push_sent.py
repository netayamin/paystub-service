"""Add push_tokens table and push_sent_at on drop_events for push notifications."""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "037"
down_revision: Union[str, None] = "036"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "push_tokens",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("device_token", sa.String(256), nullable=False, unique=True),
        sa.Column("platform", sa.String(16), nullable=False, server_default="ios"),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), onupdate=sa.func.now(), nullable=False),
    )
    op.create_index("ix_push_tokens_device_token", "push_tokens", ["device_token"], unique=True)

    op.add_column(
        "drop_events",
        sa.Column("push_sent_at", sa.DateTime(timezone=True), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("drop_events", "push_sent_at")
    op.drop_index("ix_push_tokens_device_token", table_name="push_tokens")
    op.drop_table("push_tokens")
