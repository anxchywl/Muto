from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "20260813_0004"
down_revision: str | None = "20260813_0003"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "image_uploads",
        sa.Column("owner_id", sa.Uuid(), nullable=False),
        sa.Column(
            "state", sa.String(length=32), server_default="pending", nullable=False
        ),
        sa.Column("declared_mime_type", sa.String(length=32), nullable=False),
        sa.Column("declared_byte_length", sa.BigInteger(), nullable=False),
        sa.Column("detected_mime_type", sa.String(length=32), nullable=True),
        sa.Column("byte_size", sa.BigInteger(), nullable=True),
        sa.Column("width", sa.Integer(), nullable=True),
        sa.Column("height", sa.Integer(), nullable=True),
        sa.Column("content_digest", sa.String(length=64), nullable=True),
        sa.Column("version", sa.String(length=64), nullable=True),
        sa.Column("storage_key", sa.String(length=512), nullable=True),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("finalized_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("redeemed_listing_id", sa.Uuid(), nullable=True),
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
            "declared_mime_type IN ('image/jpeg', 'image/png', 'image/webp')",
            name=op.f("ck_image_uploads_declared_mime_allowed"),
        ),
        sa.CheckConstraint(
            "declared_byte_length > 0 AND declared_byte_length <= 5242880",
            name=op.f("ck_image_uploads_declared_size_allowed"),
        ),
        sa.CheckConstraint(
            "state IN ('pending', 'expired') OR "
            "(detected_mime_type IS NOT NULL AND byte_size IS NOT NULL "
            "AND width IS NOT NULL AND height IS NOT NULL "
            "AND content_digest IS NOT NULL AND version IS NOT NULL "
            "AND storage_key IS NOT NULL)",
            name=op.f("ck_image_uploads_completed_metadata_present"),
        ),
        sa.CheckConstraint(
            "(state = 'redeemed') = (redeemed_listing_id IS NOT NULL)",
            name=op.f("ck_image_uploads_redemption_matches_state"),
        ),
        sa.CheckConstraint(
            "state IN ('pending', 'uploaded', 'finalized', 'redeemed', 'expired')",
            name=op.f("ck_image_uploads_state_allowed"),
        ),
        sa.ForeignKeyConstraint(
            ["owner_id"],
            ["users.id"],
            name=op.f("fk_image_uploads_owner_id_users"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["redeemed_listing_id"],
            ["listings.id"],
            name=op.f("fk_image_uploads_redeemed_listing_id_listings"),
            ondelete="RESTRICT",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_image_uploads")),
    )
    op.create_index(
        "ix_image_uploads_owner_created",
        "image_uploads",
        ["owner_id", "created_at"],
    )
    op.create_index(
        "ix_image_uploads_state_expires",
        "image_uploads",
        ["state", "expires_at"],
    )
    op.create_table(
        "listing_images",
        sa.Column("listing_id", sa.Uuid(), nullable=False),
        sa.Column("image_upload_id", sa.Uuid(), nullable=False),
        sa.Column("position", sa.Integer(), nullable=False),
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
            "position >= 0 AND position < 6",
            name=op.f("ck_listing_images_position_allowed"),
        ),
        sa.ForeignKeyConstraint(
            ["image_upload_id"],
            ["image_uploads.id"],
            name=op.f("fk_listing_images_image_upload_id_image_uploads"),
            ondelete="RESTRICT",
        ),
        sa.ForeignKeyConstraint(
            ["listing_id"],
            ["listings.id"],
            name=op.f("fk_listing_images_listing_id_listings"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_listing_images")),
        sa.UniqueConstraint(
            "image_upload_id",
            name="uq_listing_images_upload",
        ),
        sa.UniqueConstraint(
            "listing_id",
            "position",
            name="uq_listing_images_listing_position",
        ),
    )
    op.create_index(
        "ix_listing_images_listing_id",
        "listing_images",
        ["listing_id"],
    )


def downgrade() -> None:
    op.drop_index("ix_listing_images_listing_id", table_name="listing_images")
    op.drop_table("listing_images")
    op.drop_index("ix_image_uploads_state_expires", table_name="image_uploads")
    op.drop_index("ix_image_uploads_owner_created", table_name="image_uploads")
    op.drop_table("image_uploads")
