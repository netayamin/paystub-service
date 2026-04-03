"""Opportunity detection: poll runs, per-venue bucket state, scored events.

revision = '055'
revises = '054'
"""

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = "055"
down_revision = "054"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "opportunity_poll_runs",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("bucket_id", sa.String(length=64), nullable=False),
        sa.Column("polled_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("success", sa.Boolean(), server_default="true", nullable=False),
        sa.Column("http_status", sa.Integer(), nullable=True),
        sa.Column("latency_ms", sa.Integer(), nullable=True),
        sa.Column("coverage_score", sa.Float(), server_default="0", nullable=False),
        sa.Column("venue_hit_count", sa.Integer(), server_default="0", nullable=False),
        sa.Column("error_count", sa.Integer(), server_default="0", nullable=False),
        sa.Column("error_code", sa.String(length=64), nullable=True),
        sa.Column("provider", sa.String(length=32), server_default="resy", nullable=False),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_opportunity_poll_runs_bucket_id", "opportunity_poll_runs", ["bucket_id"], unique=False)
    op.create_index("ix_opportunity_poll_runs_polled_at", "opportunity_poll_runs", ["polled_at"], unique=False)

    op.create_table(
        "venue_bucket_states",
        sa.Column("bucket_id", sa.String(length=64), nullable=False),
        sa.Column("venue_id", sa.String(length=64), nullable=False),
        sa.Column("current_state", sa.String(length=16), nullable=False),
        sa.Column("previous_state", sa.String(length=16), nullable=True),
        sa.Column("consecutive_bookable_polls", sa.Integer(), server_default="0", nullable=False),
        sa.Column("consecutive_unbookable_polls", sa.Integer(), server_default="0", nullable=False),
        sa.Column("consecutive_absent_polls", sa.Integer(), server_default="0", nullable=False),
        sa.Column("last_seen_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("last_bookable_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("last_unbookable_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("first_seen_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=True),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("venue_name_snapshot", sa.String(length=512), nullable=True),
        sa.PrimaryKeyConstraint("bucket_id", "venue_id"),
    )

    op.create_table(
        "opportunity_events",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("bucket_id", sa.String(length=64), nullable=False),
        sa.Column("venue_id", sa.String(length=64), nullable=False),
        sa.Column("poll_run_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("event_type", sa.String(length=32), nullable=False),
        sa.Column("detected_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.Column("opportunity_score", sa.Float(), nullable=True),
        sa.Column("scarcity_score", sa.Float(), nullable=True),
        sa.Column("venue_score", sa.Float(), nullable=True),
        sa.Column("timing_score", sa.Float(), nullable=True),
        sa.Column("ttl_score", sa.Float(), nullable=True),
        sa.Column("confidence_score", sa.Float(), nullable=True),
        sa.Column("freshness_score", sa.Float(), nullable=True),
        sa.Column("reason_codes_json", sa.Text(), nullable=True),
        sa.Column("notified", sa.Boolean(), server_default="false", nullable=False),
        sa.Column("venue_name", sa.String(length=512), nullable=True),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_opportunity_events_bucket_id", "opportunity_events", ["bucket_id"], unique=False)
    op.create_index("ix_opportunity_events_venue_id", "opportunity_events", ["venue_id"], unique=False)
    op.create_index("ix_opportunity_events_poll_run_id", "opportunity_events", ["poll_run_id"], unique=False)
    op.create_index("ix_opportunity_events_event_type", "opportunity_events", ["event_type"], unique=False)
    op.create_index("ix_opportunity_events_detected_at", "opportunity_events", ["detected_at"], unique=False)


def downgrade() -> None:
    op.drop_index("ix_opportunity_events_detected_at", table_name="opportunity_events")
    op.drop_index("ix_opportunity_events_event_type", table_name="opportunity_events")
    op.drop_index("ix_opportunity_events_poll_run_id", table_name="opportunity_events")
    op.drop_index("ix_opportunity_events_venue_id", table_name="opportunity_events")
    op.drop_index("ix_opportunity_events_bucket_id", table_name="opportunity_events")
    op.drop_table("opportunity_events")
    op.drop_table("venue_bucket_states")
    op.drop_index("ix_opportunity_poll_runs_polled_at", table_name="opportunity_poll_runs")
    op.drop_index("ix_opportunity_poll_runs_bucket_id", table_name="opportunity_poll_runs")
    op.drop_table("opportunity_poll_runs")
