"""Add image_url to slot_availability for feed venue images."""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "044"
down_revision: Union[str, None] = "043"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("slot_availability", sa.Column("image_url", sa.String(512), nullable=True))


def downgrade() -> None:
    op.drop_column("slot_availability", "image_url")
