"""One-time retention cleanup for drop_events (unbounded growth fix).

Application code now (1) deletes all drop_events for a slot when it closes, and
(2) prunes by user_facing_opened_at for *all* rows older than DROP_EVENTS_RETENTION_DAYS,
not only push_sent rows. This migration removes historical backlog.

Downgrade is a no-op (deleted rows cannot be restored).
"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "050"
down_revision: Union[str, None] = "049"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

# One-time backlog trim: slightly longer than minimum daily retention (7d) so we do not
# fight operators who rely on the first week of history before env tuning.
_RETAIN_INTERVAL = "14 days"


def upgrade() -> None:
    conn = op.get_bind()
    # Batched deletes to avoid one huge transaction on very large tables.
    batch = 25_000
    total = 0
    while True:
        result = conn.execute(
            sa.text(
                f"""
                DELETE FROM drop_events
                WHERE id IN (
                    SELECT id FROM drop_events
                    WHERE user_facing_opened_at
                        < (CURRENT_TIMESTAMP AT TIME ZONE 'UTC') - INTERVAL '{_RETAIN_INTERVAL}'
                    LIMIT :lim
                )
                """
            ),
            {"lim": batch},
        )
        n = result.rowcount or 0
        total += n
        if n < batch:
            break
    print(f"050_drop_events_bulk_retention_cleanup: deleted {total} rows (user_facing_opened_at older than {_RETAIN_INTERVAL})")


def downgrade() -> None:
    pass
