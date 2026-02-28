"""Composite index on slot_availability (state, opened_at) for just-opened/feed queries.

Revision ID: 038
Revises: 037
Create Date: (run alembic upgrade head)

Speeds up: filter(state='open').order_by(opened_at.desc()).limit(N)
"""
from typing import Sequence, Union

from alembic import op

revision: str = "038"
down_revision: Union[str, None] = "037"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_index(
        "ix_slot_availability_state_opened_at",
        "slot_availability",
        ["state", "opened_at"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index("ix_slot_availability_state_opened_at", table_name="slot_availability")
