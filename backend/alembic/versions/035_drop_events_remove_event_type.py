"""Remove event_type from drop_events; open/closed state lives in slot_availability now."""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "035"
down_revision: Union[str, None] = "034"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.drop_index("ix_drop_events_event_type_opened_at", table_name="drop_events")
    op.drop_index("ix_drop_events_event_type", table_name="drop_events")
    op.drop_column("drop_events", "event_type")


def downgrade() -> None:
    op.add_column("drop_events", sa.Column("event_type", sa.String(20), nullable=False, server_default="NEW_DROP"))
    op.create_index("ix_drop_events_event_type", "drop_events", ["event_type"], unique=False)
    op.create_index(
        "ix_drop_events_event_type_opened_at",
        "drop_events",
        ["event_type", "opened_at"],
        unique=False,
        postgresql_ops={"opened_at": "DESC"},
    )
