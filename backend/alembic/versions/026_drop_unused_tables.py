"""Drop all tables not needed for discovery drop feed.

Keeps only: discovery_buckets, drop_events.

Drops: paystub_insights (FK to documents), documents, tool_call_logs,
booking_attempts, venue_search_snapshots, watch_list, chat_sessions.

Revision ID: 026
Revises: 025
Create Date: (run alembic upgrade head)

"""
from typing import Sequence, Union

from alembic import op

revision: str = "026"
down_revision: Union[str, None] = "025"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.drop_table("paystub_insights")
    op.drop_table("documents")
    op.drop_table("tool_call_logs")
    op.drop_table("booking_attempts")
    op.drop_table("venue_search_snapshots")
    op.drop_table("watch_list")
    op.drop_table("chat_sessions")


def downgrade() -> None:
    # Recreate minimal table structures for rollback (no data).
    # Tables are recreated empty; full column definitions from original migrations.
    import sqlalchemy as sa
    op.create_table(
        "chat_sessions",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("session_id", sa.String(64), nullable=False),
        sa.Column("messages_json", sa.Text(), nullable=True),
        sa.Column("last_venue_search_json", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), onupdate=sa.func.now()),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_chat_sessions_session_id", "chat_sessions", ["session_id"], unique=True)
    op.create_table(
        "watch_list",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("venue_id", sa.Integer(), nullable=False),
        sa.Column("venue_name", sa.String(255), nullable=True),
        sa.Column("party_size", sa.Integer(), nullable=True),
        sa.Column("preferred_slot", sa.String(32), nullable=True),
        sa.Column("notify_only", sa.Boolean(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_watch_list_venue_id", "watch_list", ["venue_id"], unique=False)
    op.create_table(
        "venue_search_snapshots",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("criteria_key", sa.String(128), nullable=False),
        sa.Column("venue_names_json", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_venue_search_snapshots_criteria_key", "venue_search_snapshots", ["criteria_key"], unique=True)
    op.create_table(
        "booking_attempts",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("venue_name", sa.String(255), nullable=True),
        sa.Column("date_str", sa.String(10), nullable=True),
        sa.Column("party_size", sa.Integer(), nullable=True),
        sa.Column("status", sa.String(32), nullable=True),
        sa.Column("error_message", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_table(
        "tool_call_logs",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("tool_name", sa.String(64), nullable=True),
        sa.Column("arguments_json", sa.Text(), nullable=True),
        sa.Column("result_summary", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_table(
        "documents",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("filename", sa.String(), nullable=False),
        sa.Column("format", sa.String(), nullable=True),
        sa.Column("page_count", sa.Integer(), nullable=True),
        sa.Column("status", sa.String(), nullable=False, server_default="pending"),
        sa.Column("temp_path", sa.String(), nullable=True),
        sa.Column("extracted_text", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), onupdate=sa.func.now()),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_table(
        "paystub_insights",
        sa.Column("id", sa.Integer(), autoincrement=True, nullable=False),
        sa.Column("document_id", sa.Integer(), sa.ForeignKey("documents.id", ondelete="CASCADE"), nullable=False),
        sa.Column("gross_pay", sa.Float(), nullable=True),
        sa.Column("net_pay", sa.Float(), nullable=True),
        sa.Column("pay_date", sa.Date(), nullable=True),
        sa.Column("pay_period_start", sa.Date(), nullable=True),
        sa.Column("pay_period_end", sa.Date(), nullable=True),
        sa.Column("pay_frequency", sa.String(32), nullable=True),
        sa.Column("federal_tax", sa.Float(), nullable=True),
        sa.Column("state_tax", sa.Float(), nullable=True),
        sa.Column("social_security_tax", sa.Float(), nullable=True),
        sa.Column("medicare_tax", sa.Float(), nullable=True),
        sa.Column("retirement_401k_employee", sa.Float(), nullable=True),
        sa.Column("retirement_401k_employer_match", sa.Float(), nullable=True),
        sa.Column("retirement_401k_employee_ytd", sa.Float(), nullable=True),
        sa.Column("retirement_401k_employer_ytd", sa.Float(), nullable=True),
        sa.Column("hsa", sa.Float(), nullable=True),
        sa.Column("other_deductions_json", sa.Text(), nullable=True),
        sa.PrimaryKeyConstraint("id"),
    )
