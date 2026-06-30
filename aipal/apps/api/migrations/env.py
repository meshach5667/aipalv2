from __future__ import annotations

import asyncio
import os
import sys
from logging.config import fileConfig
from pathlib import Path

from alembic import context
from sqlalchemy import pool
from sqlalchemy.engine import Connection
from sqlalchemy.ext.asyncio import async_engine_from_config

BASE_DIR = Path(__file__).resolve().parents[1]
if str(BASE_DIR) not in sys.path:
    sys.path.insert(0, str(BASE_DIR))

from app.config import get_settings  # noqa: E402
from app.db import Base  # noqa: E402
from app import models as _models  # noqa: F401,E402

config = context.config
if config.config_file_name is not None:
    fileConfig(config.config_file_name)

settings = get_settings()
target_metadata = Base.metadata
FALLBACK_SQLITE_URL = f"sqlite+aiosqlite:///{(BASE_DIR / '.alembic-dev.db').as_posix()}"


def run_migrations_offline() -> None:
    url = settings.database_url
    context.configure(
        url=url,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
        compare_type=True,
        compare_server_default=True,
    )

    with context.begin_transaction():
        context.run_migrations()


def do_run_migrations(connection: Connection) -> None:
    context.configure(
        connection=connection,
        target_metadata=target_metadata,
        compare_type=True,
        compare_server_default=True,
    )

    with context.begin_transaction():
        context.run_migrations()


async def run_async_migrations() -> None:
    url = settings.database_url
    engine_config = {"sqlalchemy.url": url}
    connectable = async_engine_from_config(
        engine_config,
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )
    try:
        async with connectable.connect() as connection:
            await connection.run_sync(do_run_migrations)
    except Exception:
        await connectable.dispose()
        if url == FALLBACK_SQLITE_URL:
            raise
        fallback = async_engine_from_config(
            {"sqlalchemy.url": FALLBACK_SQLITE_URL},
            prefix="sqlalchemy.",
            poolclass=pool.NullPool,
        )
        async with fallback.connect() as connection:
            await connection.run_sync(do_run_migrations)
        await fallback.dispose()
        return
    await connectable.dispose()


def run_migrations_online() -> None:
    asyncio.run(run_async_migrations())


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
