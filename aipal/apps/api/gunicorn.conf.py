"""Gunicorn WSGI / ASGI server configuration for AiPal API backend.

SQLite Concurrency Notice:
-------------------------
SQLite in WAL (Write-Ahead Logging) mode permits concurrent readers alongside a single active writer process.
Because SQLite enforces a single-writer lock at the database level:
- Running too many worker processes (e.g. 10+) causes excessive write lock contention under load,
  leading to `sqlite3.OperationalError: database is locked`.
- Therefore, we configure a modest worker count of 2 to 4 workers (e.g., multiprocessing.cpu_count() bounded between 2 and 4).
- Each Gunicorn process manages its own independent database connections per request context.
- Database connection objects are NEVER shared across worker processes or threads.
"""

import multiprocessing
import os

bind = os.getenv("GUNICORN_BIND", "0.0.0.0:8102")
backlog = 2048

cpu_cores = multiprocessing.cpu_count()
workers = int(os.getenv("GUNICORN_WORKERS", max(2, min(4, cpu_cores))))

worker_class = "uvicorn.workers.UvicornWorker"
worker_connections = 1000
timeout = 60
keepalive = 5

accesslog = "-"
errorlog = "-"
loglevel = os.getenv("LOG_LEVEL", "info")


def on_starting(server):
    print(
        f"[Gunicorn] Starting AiPal API on {bind} with {workers} uvicorn worker(s). "
        "SQLite WAL concurrency mode active."
    )
