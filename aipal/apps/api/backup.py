"""SQLite Hot Backup script for AiPal API backend.

Uses SQLite's online backup API (or subprocess sqlite3 CLI backup command) to create
atomic, hot backups of the live WAL database without blocking read or write queries.
Includes automated retention pruning (retains latest N backups).
"""

from __future__ import annotations

import argparse
import glob
import logging
import os
import sqlite3
import subprocess
from datetime import datetime, timezone

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger("backup")


def backup_database(
    db_path: str,
    backup_dir: str,
    retention_count: int = 24,
    use_cli: bool = False,
) -> str:
    """Executes a hot online backup of the SQLite database.

    Args:
        db_path: Absolute path to live SQLite database.
        backup_dir: Directory where backup files will be saved.
        retention_count: Number of recent backup files to keep.
        use_cli: If True, uses `sqlite3 <db> ".backup <dest>"` CLI. Otherwise uses Python sqlite3 backup API.

    Returns:
        Path to generated backup file.
    """
    if not os.path.exists(db_path):
        raise FileNotFoundError(f"Database file not found at: {db_path}")

    os.makedirs(backup_dir, exist_ok=True)
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    backup_filename = f"backup_{timestamp}.db"
    backup_filepath = os.path.join(backup_dir, backup_filename)

    logger.info(f"Starting online hot backup of {db_path}...")

    if use_cli:
        cmd = ["sqlite3", db_path, f".backup '{backup_filepath}'"]
        logger.info(f"Executing CLI backup: {' '.join(cmd)}")
        res = subprocess.run(cmd, capture_output=True, text=True)
        if res.returncode != 0:
            raise RuntimeError(f"sqlite3 CLI backup failed: {res.stderr}")
    else:
        src_conn = sqlite3.connect(db_path, timeout=15.0)
        dst_conn = sqlite3.connect(backup_filepath)
        try:
            with dst_conn:
                src_conn.backup(dst_conn, pages=100, sleep=0.01)
            logger.info("Online backup API transfer complete.")
        finally:
            dst_conn.close()
            src_conn.close()

    logger.info(f"Backup saved successfully to: {backup_filepath}")
    prune_old_backups(backup_dir, retention_count)
    return backup_filepath


def prune_old_backups(backup_dir: str, retention_count: int) -> None:
    """Removes old backup files exceeding retention_count."""
    pattern = os.path.join(backup_dir, "backup_*.db")
    backups = sorted(glob.glob(pattern))

    if len(backups) > retention_count:
        to_delete = backups[:-retention_count]
        for filepath in to_delete:
            try:
                os.remove(filepath)
                logger.info(f"Pruned old backup: {os.path.basename(filepath)}")
            except OSError as e:
                logger.warning(f"Failed to delete old backup {filepath}: {e}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="SQLite Online Hot Backup for AiPal API")
    parser.add_argument(
        "--db",
        default=os.getenv("DATABASE_PATH", "instance/app.db"),
        help="Path to SQLite database file",
    )
    parser.add_argument(
        "--out",
        default="instance/backups",
        help="Output directory for backup files",
    )
    parser.add_argument(
        "--retain",
        type=int,
        default=24,
        help="Number of backup files to retain (default: 24)",
    )
    parser.add_argument(
        "--cli",
        action="store_true",
        help="Use sqlite3 CLI tool instead of Python backup API",
    )
    args = parser.parse_args()

    backup_database(
        db_path=os.path.abspath(args.db),
        backup_dir=os.path.abspath(args.out),
        retention_count=args.retain,
        use_cli=args.cli,
    )
