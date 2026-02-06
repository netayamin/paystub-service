"""Add tool_call_logs table for Log tab

Revision ID: 016
Revises: 015
Create Date: (run alembic upgrade head)

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "016"
down_revision: Union[str, None] = "015"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "tool_call_logs",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column("tool_name", sa.String(128), nullable=False),
        sa.Column("arguments_json", sa.Text(), nullable=True),
        sa.Column("session_id", sa.String(64), nullable=True),
    )
    op.create_index("ix_tool_call_logs_tool_name", "tool_call_logs", ["tool_name"], unique=False)
    op.create_index("ix_tool_call_logs_created_at", "tool_call_logs", ["created_at"], unique=False)
    op.create_index("ix_tool_call_logs_session_id", "tool_call_logs", ["session_id"], unique=False)


def downgrade() -> None:
    op.drop_index("ix_tool_call_logs_session_id", table_name="tool_call_logs")
    op.drop_index("ix_tool_call_logs_created_at", table_name="tool_call_logs")
    op.drop_index("ix_tool_call_logs_tool_name", table_name="tool_call_logs")
    op.drop_table("tool_call_logs")
