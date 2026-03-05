"""Add partial index on slot_availability for state='open' feed queries."""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "043"
down_revision: Union[str, None] = "042"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.execute(
        sa.text(
            "CREATE INDEX ix_slot_availability_open_opened_desc "
            "ON slot_availability (opened_at DESC) "
            "WHERE state = 'open'"
        )
    )


def downgrade() -> None:
    op.execute(sa.text("DROP INDEX IF EXISTS ix_slot_availability_open_opened_desc"))
