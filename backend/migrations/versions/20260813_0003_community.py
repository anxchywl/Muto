from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "20260813_0003"
down_revision: str | None = "20260813_0002"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "favorites",
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("listing_id", sa.Uuid(), nullable=False),
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
            ["listing_id"],
            ["listings.id"],
            name=op.f("fk_favorites_listing_id_listings"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["user_id"],
            ["users.id"],
            name=op.f("fk_favorites_user_id_users"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_favorites")),
        sa.UniqueConstraint(
            "user_id",
            "listing_id",
            name="uq_favorites_user_listing",
        ),
    )
    op.create_index(
        "ix_favorites_user_created",
        "favorites",
        ["user_id", "created_at"],
    )
    op.create_table(
        "reports",
        sa.Column("reporter_id", sa.Uuid(), nullable=False),
        sa.Column("listing_id", sa.Uuid(), nullable=False),
        sa.Column("reason", sa.String(length=32), nullable=False),
        sa.Column("note", sa.Text(), nullable=True),
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
            "reason <> 'other' OR note IS NOT NULL",
            name=op.f("ck_reports_other_reason_has_note"),
        ),
        sa.CheckConstraint(
            "reason IN ('prohibited', 'misleading', 'offensive', 'other')",
            name=op.f("ck_reports_reason_allowed"),
        ),
        sa.ForeignKeyConstraint(
            ["listing_id"],
            ["listings.id"],
            name=op.f("fk_reports_listing_id_listings"),
            ondelete="RESTRICT",
        ),
        sa.ForeignKeyConstraint(
            ["reporter_id"],
            ["users.id"],
            name=op.f("fk_reports_reporter_id_users"),
            ondelete="RESTRICT",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_reports")),
        sa.UniqueConstraint(
            "reporter_id",
            "listing_id",
            name="uq_reports_reporter_listing",
        ),
    )
    op.create_index(
        "ix_reports_listing_created",
        "reports",
        ["listing_id", "created_at"],
    )
    op.create_index(
        "ix_reports_reporter_created",
        "reports",
        ["reporter_id", "created_at"],
    )


def downgrade() -> None:
    op.drop_index("ix_reports_reporter_created", table_name="reports")
    op.drop_index("ix_reports_listing_created", table_name="reports")
    op.drop_table("reports")
    op.drop_index("ix_favorites_user_created", table_name="favorites")
    op.drop_table("favorites")
