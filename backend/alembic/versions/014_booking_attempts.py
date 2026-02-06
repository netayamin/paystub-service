"""Add booking_attempts table for auto-book error reporter

Revision ID: 014
Revises: 013
Create Date: (run alembic upgrade head)

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "014"
down_revision: Union[str, None] = "013"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "booking_attempts",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
        sa.Column("venue_name", sa.String(255), nullable=False),
        sa.Column("date_str", sa.String(10), nullable=False),
        sa.Column("party_size", sa.Integer(), nullable=False),
        sa.Column("status", sa.String(16), nullable=False),
        sa.Column("error_message", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    op.create_index("ix_booking_attempts_created_at", "booking_attempts", ["created_at"], unique=False)


def downgrade() -> None:
    op.drop_index("ix_booking_attempts_created_at", table_name="booking_attempts")
    op.drop_table("booking_attempts")
