"""Venue profile cache: image, neighborhood, resy URL, market."""

from alembic import op
import sqlalchemy as sa


revision = "047"
down_revision = "046"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("venues", sa.Column("image_url", sa.String(length=512), nullable=True))
    op.add_column("venues", sa.Column("neighborhood", sa.String(length=128), nullable=True))
    op.add_column("venues", sa.Column("resy_url", sa.String(length=512), nullable=True))
    op.add_column("venues", sa.Column("market", sa.String(length=32), nullable=True))


def downgrade() -> None:
    op.drop_column("venues", "market")
    op.drop_column("venues", "resy_url")
    op.drop_column("venues", "neighborhood")
    op.drop_column("venues", "image_url")
