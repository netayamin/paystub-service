import os
from logging.config import fileConfig

from dotenv import load_dotenv
from sqlalchemy import engine_from_config
from sqlalchemy import pool
from alembic import context

from app.config import settings
from app.db.base import Base
from app.db.tables import ALL_TABLE_NAMES
from app.models.discovery_bucket import DiscoveryBucket  # noqa: F401
from app.models.drop_event import DropEvent  # noqa: F401
from app.models.feed_cache import FeedCache  # noqa: F401
from app.models.market_metrics import MarketMetrics  # noqa: F401
from app.models.venue import Venue  # noqa: F401
from app.models.venue_metrics import VenueMetrics  # noqa: F401
from app.models.venue_rolling_metrics import VenueRollingMetrics  # noqa: F401

load_dotenv()

# Ensure we only have current tables (no dropped tables as models).
_registered = set(Base.metadata.tables)
_expected = set(ALL_TABLE_NAMES)
assert _registered == _expected, (
    f"Model tables {_registered} must match app.db.tables.ALL_TABLE_NAMES {_expected}. "
    "Do not add models for dropped tables."
)

config = context.config
if config.config_file_name is not None:
    fileConfig(config.config_file_name)

target_metadata = Base.metadata
config.set_main_option("sqlalchemy.url", settings.database_url)


def run_migrations_offline() -> None:
    url = config.get_main_option("sqlalchemy.url")
    context.configure(
        url=url,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
    )
    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    connectable = engine_from_config(
        config.get_section(config.config_ini_section, {}),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )
    with connectable.connect() as connection:
        context.configure(
            connection=connection,
            target_metadata=target_metadata,
        )
        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
