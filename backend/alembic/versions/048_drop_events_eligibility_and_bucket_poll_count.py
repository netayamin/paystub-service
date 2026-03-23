"""drop_events: user-facing open time, eligibility evidence, prior snapshot flags; discovery_buckets poll count."""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "048"
down_revision: Union[str, None] = "047"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Add bucket column first (short lock) to avoid overlapping long drop_events locks with readers.
    op.add_column(
        "discovery_buckets",
        sa.Column(
            "successful_poll_count",
            sa.Integer(),
            nullable=False,
            server_default="0",
        ),
    )

    # --- drop_events: nullable columns first, then backfill, then NOT NULL + CHECK ---
    op.add_column(
        "drop_events",
        sa.Column("user_facing_opened_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.add_column(
        "drop_events",
        sa.Column("eligibility_evidence", sa.String(length=32), nullable=True),
    )
    op.add_column(
        "drop_events",
        sa.Column("prior_snapshot_included_slot", sa.Boolean(), nullable=True),
    )
    op.add_column(
        "drop_events",
        sa.Column("prior_prev_slot_count", sa.Integer(), nullable=True),
    )

    op.execute(
        sa.text(
            "UPDATE drop_events SET user_facing_opened_at = opened_at "
            "WHERE user_facing_opened_at IS NULL"
        )
    )
    op.execute(
        sa.text(
            "UPDATE drop_events SET eligibility_evidence = 'unknown' "
            "WHERE eligibility_evidence IS NULL"
        )
    )
    op.execute(
        sa.text(
            "UPDATE drop_events SET prior_snapshot_included_slot = false "
            "WHERE prior_snapshot_included_slot IS NULL"
        )
    )
    op.execute(
        sa.text(
            "UPDATE drop_events SET prior_prev_slot_count = 0 "
            "WHERE prior_prev_slot_count IS NULL"
        )
    )

    op.alter_column(
        "drop_events",
        "user_facing_opened_at",
        existing_type=sa.DateTime(timezone=True),
        nullable=False,
    )
    op.alter_column(
        "drop_events",
        "eligibility_evidence",
        existing_type=sa.String(length=32),
        nullable=False,
    )
    op.alter_column(
        "drop_events",
        "prior_snapshot_included_slot",
        existing_type=sa.Boolean(),
        nullable=False,
    )
    op.alter_column(
        "drop_events",
        "prior_prev_slot_count",
        existing_type=sa.Integer(),
        nullable=False,
    )

    op.create_check_constraint(
        "ck_drop_events_eligibility_evidence",
        "drop_events",
        "eligibility_evidence IN ("
        "'nonempty_prev_delta', 'empty_prev_delta', 'first_poll_bucket', "
        "'baseline_only', 'unknown'"
        ")",
    )

    # Legacy insert paths (e.g. buckets.py before Task 2.1) omit new columns; fill before NOT NULL/CHECK.
    op.execute(
        sa.text(
            """
CREATE OR REPLACE FUNCTION trfn_drop_events_insert_defaults() RETURNS TRIGGER AS $f$
BEGIN
  IF NEW.user_facing_opened_at IS NULL THEN
    NEW.user_facing_opened_at := NEW.opened_at;
  END IF;
  IF NEW.eligibility_evidence IS NULL THEN
    NEW.eligibility_evidence := 'unknown';
  END IF;
  IF NEW.prior_snapshot_included_slot IS NULL THEN
    NEW.prior_snapshot_included_slot := false;
  END IF;
  IF NEW.prior_prev_slot_count IS NULL THEN
    NEW.prior_prev_slot_count := 0;
  END IF;
  RETURN NEW;
END;
$f$ LANGUAGE plpgsql
"""
        )
    )
    op.execute(sa.text("DROP TRIGGER IF EXISTS tr_drop_events_insert_defaults ON drop_events"))
    op.execute(
        sa.text(
            """
CREATE TRIGGER tr_drop_events_insert_defaults
  BEFORE INSERT ON drop_events
  FOR EACH ROW
  EXECUTE FUNCTION trfn_drop_events_insert_defaults()
"""
        )
    )


def downgrade() -> None:
    op.execute(sa.text("DROP TRIGGER IF EXISTS tr_drop_events_insert_defaults ON drop_events"))
    op.execute(sa.text("DROP FUNCTION IF EXISTS trfn_drop_events_insert_defaults()"))
    op.drop_constraint(
        "ck_drop_events_eligibility_evidence",
        "drop_events",
        type_="check",
    )
    op.drop_column("discovery_buckets", "successful_poll_count")
    op.drop_column("drop_events", "prior_prev_slot_count")
    op.drop_column("drop_events", "prior_snapshot_included_slot")
    op.drop_column("drop_events", "eligibility_evidence")
    op.drop_column("drop_events", "user_facing_opened_at")
