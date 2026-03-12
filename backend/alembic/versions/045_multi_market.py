"""Multi-market support: resize bucket_id columns, add market column to discovery tables.

- bucket_id String(20) → String(40) in discovery_buckets, slot_availability, drop_events,
  availability_state.  New format: {market}_{date}_{timeslot} e.g. "nyc_2026-03-11_21:00".
- Add market String(32) column (nullable) + index to each of those tables.
- Backfill market='nyc' for all existing rows (old bucket IDs are NYC data).
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "045"
down_revision: Union[str, None] = "044"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # 1. Resize bucket_id from String(20) → String(40) everywhere
    op.alter_column("discovery_buckets", "bucket_id",
                     existing_type=sa.String(20), type_=sa.String(40), nullable=False)
    op.alter_column("slot_availability", "bucket_id",
                     existing_type=sa.String(20), type_=sa.String(40), nullable=False)
    op.alter_column("drop_events", "bucket_id",
                     existing_type=sa.String(20), type_=sa.String(40), nullable=False)
    op.alter_column("availability_state", "bucket_id",
                     existing_type=sa.String(20), type_=sa.String(40), nullable=False)

    # 2. Add market column to each table
    op.add_column("discovery_buckets",
                  sa.Column("market", sa.String(32), nullable=True))
    op.add_column("slot_availability",
                  sa.Column("market", sa.String(32), nullable=True))
    op.add_column("drop_events",
                  sa.Column("market", sa.String(32), nullable=True))
    op.add_column("availability_state",
                  sa.Column("market", sa.String(32), nullable=True))

    # 3. Backfill existing rows (all pre-migration data is NYC)
    op.execute("UPDATE discovery_buckets  SET market = 'nyc' WHERE market IS NULL")
    op.execute("UPDATE slot_availability  SET market = 'nyc' WHERE market IS NULL")
    op.execute("UPDATE drop_events        SET market = 'nyc' WHERE market IS NULL")
    op.execute("UPDATE availability_state SET market = 'nyc' WHERE market IS NULL")

    # 4. Add indexes for fast per-market queries
    op.create_index("ix_discovery_buckets_market",  "discovery_buckets",  ["market"])
    op.create_index("ix_slot_availability_market",  "slot_availability",  ["market"])
    op.create_index("ix_drop_events_market",        "drop_events",        ["market"])
    op.create_index("ix_availability_state_market", "availability_state", ["market"])


def downgrade() -> None:
    op.drop_index("ix_availability_state_market", table_name="availability_state")
    op.drop_index("ix_drop_events_market",        table_name="drop_events")
    op.drop_index("ix_slot_availability_market",  table_name="slot_availability")
    op.drop_index("ix_discovery_buckets_market",  table_name="discovery_buckets")

    op.drop_column("availability_state", "market")
    op.drop_column("drop_events",        "market")
    op.drop_column("slot_availability",  "market")
    op.drop_column("discovery_buckets",  "market")

    op.alter_column("availability_state", "bucket_id",
                     existing_type=sa.String(40), type_=sa.String(20), nullable=False)
    op.alter_column("drop_events", "bucket_id",
                     existing_type=sa.String(40), type_=sa.String(20), nullable=False)
    op.alter_column("slot_availability", "bucket_id",
                     existing_type=sa.String(40), type_=sa.String(20), nullable=False)
    op.alter_column("discovery_buckets", "bucket_id",
                     existing_type=sa.String(40), type_=sa.String(20), nullable=False)
