"""Create paystub_insights table

Revision ID: 003
Revises: 002
Create Date: (run alembic upgrade head)

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "003"
down_revision: Union[str, None] = "002"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "paystub_insights",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
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
    )
    op.create_index("ix_paystub_insights_document_id", "paystub_insights", ["document_id"], unique=True)


def downgrade() -> None:
    op.drop_table("paystub_insights")
