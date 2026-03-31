"""Add baseline calibration columns to discovery_buckets (multi-poll union before locking).

revision = '054'
revises = '053'
"""

from alembic import op
import sqlalchemy as sa


revision = "054"
down_revision = "053"
branch_labels = None
depends_on = None

# Matches default DISCOVERY_BASELINE_CALIBRATION_POLLS for backfilling already-locked baselines.
_BACKFILL_POLLS = 3


def upgrade() -> None:
    op.add_column(
        "discovery_buckets",
        sa.Column("baseline_calibration_complete", sa.Boolean(), nullable=True),
    )
    op.add_column(
        "discovery_buckets",
        sa.Column("baseline_calibration_polls", sa.Integer(), nullable=True),
    )
    # Buckets that already had a non-empty baseline behave as fully calibrated.
    op.execute(
        f"""
        UPDATE discovery_buckets
        SET baseline_calibration_complete = true,
            baseline_calibration_polls = {_BACKFILL_POLLS}
        WHERE baseline_slot_ids_json IS NOT NULL
          AND baseline_slot_ids_json NOT IN ('[]', '')
        """
    )
    op.execute(
        """
        UPDATE discovery_buckets
        SET baseline_calibration_complete = COALESCE(baseline_calibration_complete, false),
            baseline_calibration_polls = COALESCE(baseline_calibration_polls, 0)
        """
    )
    op.alter_column(
        "discovery_buckets",
        "baseline_calibration_complete",
        existing_type=sa.Boolean(),
        nullable=False,
        server_default=sa.text("false"),
    )
    op.alter_column(
        "discovery_buckets",
        "baseline_calibration_polls",
        existing_type=sa.Integer(),
        nullable=False,
        server_default=sa.text("0"),
    )


def downgrade() -> None:
    op.drop_column("discovery_buckets", "baseline_calibration_polls")
    op.drop_column("discovery_buckets", "baseline_calibration_complete")
