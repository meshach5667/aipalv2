"""Add user knowledge gap consent.

Revision ID: 20260723_0018_user_knowledge_gap_consent
Revises: 20260715_0017_phase5_memory_index
"""

from alembic import op
import sqlalchemy as sa


revision = "20260723_0018_user_knowledge_gap_consent"
down_revision = "20260715_0017_phase5_memory_index"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "users",
        sa.Column(
            "knowledge_gap_data_consent",
            sa.Boolean(),
            nullable=False,
            server_default=sa.false(),
        ),
    )


def downgrade() -> None:
    op.drop_column("users", "knowledge_gap_data_consent")
