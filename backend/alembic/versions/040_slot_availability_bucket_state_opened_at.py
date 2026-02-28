"""Index slot_availability (bucket_id, state, opened_at) and venue_rolling_metrics (computed_at) for faster queries.

- still-open query: filter bucket_id IN (...), state='open', order by opened_at desc → index scan.
- just-opened already uses ix_slot_availability_state_opened_at.
- Feed enrichment: order by computed_at desc limit N → index on computed_at.
"""
from typing import Sequence, Union

from alembic import op

revision: str = "040"
down_revision: Union[str, None] = "039"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # still-open: filter by bucket_id + state, order by opened_at desc
    op.create_index(
        "ix_slot_availability_bucket_state_opened_at",
        "slot_availability",
        ["bucket_id", "state", "opened_at"],
        unique=False,
        postgresql_ops={"opened_at": "DESC"},
    )
    # feed enrichment: order by computed_at desc limit 4000
    op.create_index(
        "ix_venue_rolling_metrics_computed_at",
        "venue_rolling_metrics",
        ["computed_at"],
        unique=False,
        postgresql_ops={"computed_at": "DESC"},
    )


def downgrade() -> None:
    op.drop_index("ix_venue_rolling_metrics_computed_at", table_name="venue_rolling_metrics")
    op.drop_index("ix_slot_availability_bucket_state_opened_at", table_name="slot_availability")
