from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "20260813_0001"
down_revision: str | None = None
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "users",
        sa.Column("display_name", sa.String(length=255), nullable=True),
        sa.Column(
            "is_verified",
            sa.Boolean(),
            server_default=sa.text("false"),
            nullable=False,
        ),
        sa.Column(
            "account_status",
            sa.String(length=32),
            server_default="active",
            nullable=False,
        ),
        sa.Column("telegram_username", sa.String(length=64), nullable=True),
        sa.Column("email", sa.String(length=320), nullable=True),
        sa.Column("phone", sa.String(length=32), nullable=True),
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.CheckConstraint(
            "account_status IN ('active', 'suspended')",
            name=op.f("ck_users_account_status_allowed"),
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_users")),
    )
    op.create_index(
        "ix_users_account_status",
        "users",
        ["account_status"],
        unique=False,
    )
    op.create_table(
        "user_identities",
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("provider_issuer", sa.String(length=255), nullable=False),
        sa.Column("provider_subject", sa.String(length=255), nullable=False),
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["users.id"],
            name=op.f("fk_user_identities_user_id_users"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_user_identities")),
        sa.UniqueConstraint(
            "provider_issuer",
            "provider_subject",
            name="uq_user_identities_provider_subject",
        ),
    )
    op.create_index(
        "ix_user_identities_user_id",
        "user_identities",
        ["user_id"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index("ix_user_identities_user_id", table_name="user_identities")
    op.drop_table("user_identities")
    op.drop_index("ix_users_account_status", table_name="users")
    op.drop_table("users")
