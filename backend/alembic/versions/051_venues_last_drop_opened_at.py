"""venues.last_drop_opened_at — denormalized max drop time so drop_events can stay tiny.

Follow status and similar features read last drop from venues, not from scanning drop_events.
Backfill from existing drop_events (one aggregate UPDATE).
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "051"
down_revision: Union[str, None] = "050"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "venues",
        sa.Column("last_drop_opened_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index(
        "ix_venues_last_drop_opened_at",
        "venues",
        ["last_drop_opened_at"],
        unique=False,
        postgresql_where=sa.text("last_drop_opened_at IS NOT NULL"),
    )
    conn = op.get_bind()
    conn.execute(
        sa.text("""
        UPDATE venues AS v
        SET last_drop_opened_at = s.mx
        FROM (
            SELECT venue_id, MAX(user_facing_opened_at) AS mx
            FROM drop_events
            WHERE venue_id IS NOT NULL
            GROUP BY venue_id
        ) AS s
        WHERE v.venue_id = s.venue_id
        """)
    )


def downgrade() -> None:
    op.drop_index("ix_venues_last_drop_opened_at", table_name="venues")
    op.drop_column("venues", "last_drop_opened_at")
