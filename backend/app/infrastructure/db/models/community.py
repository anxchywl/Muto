from __future__ import annotations

from datetime import datetime
from uuid import UUID

from sqlalchemy import (
    BigInteger,
    CheckConstraint,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column

from app.infrastructure.db.base import Base, TimestampMixin, UuidPrimaryKeyMixin


class Favorite(UuidPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "favorites"
    __table_args__ = (
        UniqueConstraint(
            "user_id",
            "listing_id",
            name="uq_favorites_user_listing",
        ),
        Index("ix_favorites_user_created", "user_id", "created_at"),
    )

    user_id: Mapped[UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    listing_id: Mapped[UUID] = mapped_column(
        ForeignKey("listings.id", ondelete="CASCADE"), nullable=False
    )


class Report(UuidPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "reports"
    __table_args__ = (
        UniqueConstraint(
            "reporter_id",
            "listing_id",
            name="uq_reports_reporter_listing",
        ),
        CheckConstraint(
            "reason IN ('prohibited', 'misleading', 'offensive', 'other')",
            name="reason_allowed",
        ),
        CheckConstraint(
            "reason <> 'other' OR note IS NOT NULL",
            name="other_reason_has_note",
        ),
        CheckConstraint(
            "note IS NULL OR char_length(note) <= 500",
            name="note_length_allowed",
        ),
        Index("ix_reports_listing_created", "listing_id", "created_at"),
        Index("ix_reports_reporter_created", "reporter_id", "created_at"),
    )

    reporter_id: Mapped[UUID] = mapped_column(
        ForeignKey("users.id", ondelete="RESTRICT"), nullable=False
    )
    listing_id: Mapped[UUID] = mapped_column(
        ForeignKey("listings.id", ondelete="RESTRICT"), nullable=False
    )
    reason: Mapped[str] = mapped_column(String(32), nullable=False)
    note: Mapped[str | None] = mapped_column(Text, nullable=True)


class ImageUpload(UuidPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "image_uploads"
    __table_args__ = (
        CheckConstraint(
            "state IN ('pending', 'uploaded', 'finalized', 'redeemed', 'expired')",
            name="state_allowed",
        ),
        CheckConstraint(
            "declared_byte_length > 0 AND declared_byte_length <= 5242880",
            name="declared_size_allowed",
        ),
        CheckConstraint(
            "declared_mime_type IN ('image/jpeg', 'image/png', 'image/webp')",
            name="declared_mime_allowed",
        ),
        CheckConstraint(
            "detected_mime_type IS NULL OR "
            "detected_mime_type IN ('image/jpeg', 'image/png', 'image/webp')",
            name="detected_mime_allowed",
        ),
        CheckConstraint(
            "byte_size IS NULL OR (byte_size > 0 AND byte_size <= 5242880)",
            name="byte_size_allowed",
        ),
        CheckConstraint(
            "width IS NULL OR height IS NULL OR "
            "(width >= 200 AND height >= 200 AND width::bigint * height <= 50000000)",
            name="dimensions_allowed",
        ),
        CheckConstraint(
            "state IN ('pending', 'expired') OR "
            "(detected_mime_type IS NOT NULL AND byte_size IS NOT NULL "
            "AND width IS NOT NULL AND height IS NOT NULL "
            "AND content_digest IS NOT NULL AND version IS NOT NULL "
            "AND storage_key IS NOT NULL)",
            name="completed_metadata_present",
        ),
        CheckConstraint(
            "(state = 'redeemed') = (redeemed_listing_id IS NOT NULL)",
            name="redemption_matches_state",
        ),
        Index("ix_image_uploads_owner_created", "owner_id", "created_at"),
        Index("ix_image_uploads_state_expires", "state", "expires_at"),
    )

    owner_id: Mapped[UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    state: Mapped[str] = mapped_column(
        String(32), nullable=False, default="pending", server_default="pending"
    )
    declared_mime_type: Mapped[str] = mapped_column(String(32), nullable=False)
    declared_byte_length: Mapped[int] = mapped_column(BigInteger, nullable=False)
    detected_mime_type: Mapped[str | None] = mapped_column(String(32), nullable=True)
    byte_size: Mapped[int | None] = mapped_column(BigInteger, nullable=True)
    width: Mapped[int | None] = mapped_column(Integer, nullable=True)
    height: Mapped[int | None] = mapped_column(Integer, nullable=True)
    content_digest: Mapped[str | None] = mapped_column(String(64), nullable=True)
    version: Mapped[str | None] = mapped_column(String(64), nullable=True)
    storage_key: Mapped[str | None] = mapped_column(String(512), nullable=True)
    expires_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False
    )
    finalized_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    redeemed_listing_id: Mapped[UUID | None] = mapped_column(
        ForeignKey("listings.id", ondelete="RESTRICT"), nullable=True
    )


class ListingImage(UuidPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "listing_images"
    __table_args__ = (
        UniqueConstraint(
            "listing_id",
            "position",
            name="uq_listing_images_listing_position",
        ),
        UniqueConstraint(
            "image_upload_id",
            name="uq_listing_images_upload",
        ),
        CheckConstraint("position >= 0 AND position < 6", name="position_allowed"),
        Index("ix_listing_images_listing_id", "listing_id"),
    )

    listing_id: Mapped[UUID] = mapped_column(
        ForeignKey("listings.id", ondelete="CASCADE"), nullable=False
    )
    image_upload_id: Mapped[UUID] = mapped_column(
        ForeignKey("image_uploads.id", ondelete="RESTRICT"), nullable=False
    )
    position: Mapped[int] = mapped_column(Integer, nullable=False)
