"""Composite index on drop_events (event_type, opened_at) for scalable new-drops queries."""
from typing import Sequence, Union

from alembic import op

revision: str = "032"
down_revision: Union[str, None] = "031"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_index(
        "ix_drop_events_event_type_opened_at",
        "drop_events",
        ["event_type", "opened_at"],
        unique=False,
        postgresql_ops={"opened_at": "DESC"},
    )


def downgrade() -> None:
    op.drop_index("ix_drop_events_event_type_opened_at", table_name="drop_events")
