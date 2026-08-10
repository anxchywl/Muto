from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "20260813_0002"
down_revision: str | None = "20260813_0001"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "listings",
        sa.Column("owner_id", sa.Uuid(), nullable=False),
        sa.Column("title", sa.String(length=80), nullable=False),
        sa.Column("description", sa.Text(), nullable=False),
        sa.Column("category", sa.String(length=32), nullable=False),
        sa.Column("kind", sa.String(length=32), nullable=False),
        sa.Column("condition", sa.String(length=32), nullable=False),
        sa.Column("price_minor_units", sa.BigInteger(), nullable=True),
        sa.Column("currency", sa.String(length=3), nullable=True),
        sa.Column("wanted_items", sa.String(length=200), nullable=True),
        sa.Column(
            "status", sa.String(length=32), server_default="active", nullable=False
        ),
        sa.Column("version", sa.Integer(), server_default="1", nullable=False),
        sa.Column(
            "search_vector",
            postgresql.TSVECTOR(),
            sa.Computed(
                "to_tsvector('simple', title || ' ' || description)",
                persisted=True,
            ),
            nullable=False,
        ),
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
            "category IN ('textbooks', 'electronics', 'furniture', 'clothing', "
            "'sports', 'dorm', 'tickets', 'other')",
            name=op.f("ck_listings_category_allowed"),
        ),
        sa.CheckConstraint(
            "condition IN ('new', 'like_new', 'good', 'worn')",
            name=op.f("ck_listings_condition_allowed"),
        ),
        sa.CheckConstraint(
            "currency IS NULL OR currency IN ('KZT', 'USD')",
            name=op.f("ck_listings_currency_allowed"),
        ),
        sa.CheckConstraint(
            "kind IN ('sale', 'exchange', 'giveaway')",
            name=op.f("ck_listings_kind_allowed"),
        ),
        sa.CheckConstraint(
            "kind = 'exchange' OR wanted_items IS NULL",
            name=op.f("ck_listings_wanted_items_matches_kind"),
        ),
        sa.CheckConstraint(
            "(kind = 'sale' AND price_minor_units IS NOT NULL "
            "AND currency IS NOT NULL) OR (kind <> 'sale' "
            "AND price_minor_units IS NULL AND currency IS NULL)",
            name=op.f("ck_listings_price_matches_kind"),
        ),
        sa.CheckConstraint(
            "price_minor_units IS NULL OR price_minor_units > 0",
            name=op.f("ck_listings_price_positive"),
        ),
        sa.CheckConstraint(
            "status IN ('active', 'reserved', 'sold', 'hidden', 'removed')",
            name=op.f("ck_listings_status_allowed"),
        ),
        sa.CheckConstraint("version > 0", name=op.f("ck_listings_version_positive")),
        sa.ForeignKeyConstraint(
            ["owner_id"],
            ["users.id"],
            name=op.f("fk_listings_owner_id_users"),
            ondelete="RESTRICT",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_listings")),
    )
    op.create_index("ix_listings_category_status", "listings", ["category", "status"])
    op.create_index("ix_listings_condition_status", "listings", ["condition", "status"])
    op.create_index("ix_listings_kind_status", "listings", ["kind", "status"])
    op.create_index(
        "ix_listings_owner_updated",
        "listings",
        ["owner_id", sa.literal_column("updated_at DESC")],
    )
    op.create_index(
        "ix_listings_search_vector",
        "listings",
        ["search_vector"],
        postgresql_using="gin",
    )
    op.create_index(
        "ix_listings_status_created",
        "listings",
        ["status", sa.literal_column("created_at DESC")],
    )
    op.create_table(
        "idempotency_keys",
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("operation", sa.String(length=64), nullable=False),
        sa.Column("key", sa.String(length=128), nullable=False),
        sa.Column("request_fingerprint", sa.String(length=64), nullable=False),
        sa.Column("response_status", sa.Integer(), nullable=False),
        sa.Column(
            "response_body", postgresql.JSONB(astext_type=sa.Text()), nullable=False
        ),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
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
            name=op.f("fk_idempotency_keys_user_id_users"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_idempotency_keys")),
    )
    op.create_index(
        "ix_idempotency_keys_expires_at", "idempotency_keys", ["expires_at"]
    )
    op.create_index(
        "uq_idempotency_keys_scope",
        "idempotency_keys",
        ["user_id", "operation", "key"],
        unique=True,
    )


def downgrade() -> None:
    op.drop_index("uq_idempotency_keys_scope", table_name="idempotency_keys")
    op.drop_index("ix_idempotency_keys_expires_at", table_name="idempotency_keys")
    op.drop_table("idempotency_keys")
    op.drop_index("ix_listings_status_created", table_name="listings")
    op.drop_index(
        "ix_listings_search_vector", table_name="listings", postgresql_using="gin"
    )
    op.drop_index("ix_listings_owner_updated", table_name="listings")
    op.drop_index("ix_listings_kind_status", table_name="listings")
    op.drop_index("ix_listings_condition_status", table_name="listings")
    op.drop_index("ix_listings_category_status", table_name="listings")
    op.drop_table("listings")
