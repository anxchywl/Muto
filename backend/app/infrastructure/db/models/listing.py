from __future__ import annotations

from datetime import datetime
from uuid import UUID

from sqlalchemy import (
    BigInteger,
    CheckConstraint,
    Computed,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    text,
)
from sqlalchemy.dialects.postgresql import JSONB, TSVECTOR
from sqlalchemy.orm import Mapped, mapped_column

from app.infrastructure.db.base import Base, TimestampMixin, UuidPrimaryKeyMixin


class Listing(UuidPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "listings"
    __table_args__ = (
        CheckConstraint(
            "kind IN ('sale', 'exchange', 'giveaway')",
            name="kind_allowed",
        ),
        CheckConstraint(
            "condition IN ('new', 'like_new', 'good', 'worn')",
            name="condition_allowed",
        ),
        CheckConstraint(
            "category IN ('textbooks', 'electronics', 'furniture', 'clothing', "
            "'sports', 'dorm', 'tickets', 'other')",
            name="category_allowed",
        ),
        CheckConstraint(
            "status IN ('active', 'reserved', 'sold', 'hidden', 'removed')",
            name="status_allowed",
        ),
        CheckConstraint("version > 0", name="version_positive"),
        CheckConstraint(
            "(kind = 'sale' AND price_minor_units IS NOT NULL "
            "AND currency IS NOT NULL) OR "
            "(kind <> 'sale' AND price_minor_units IS NULL AND currency IS NULL)",
            name="price_matches_kind",
        ),
        CheckConstraint(
            "price_minor_units IS NULL OR price_minor_units > 0",
            name="price_positive",
        ),
        CheckConstraint(
            "(currency = 'KZT' AND price_minor_units <= 50000000) OR "
            "(currency = 'USD' AND price_minor_units <= 10000000) OR "
            "price_minor_units IS NULL",
            name="price_within_currency_limit",
        ),
        CheckConstraint(
            "char_length(title) BETWEEN 3 AND 80",
            name="title_length_allowed",
        ),
        CheckConstraint(
            "char_length(description) <= 2000",
            name="description_length_allowed",
        ),
        CheckConstraint(
            "currency IS NULL OR currency IN ('KZT', 'USD')",
            name="currency_allowed",
        ),
        CheckConstraint(
            "kind = 'exchange' OR wanted_items IS NULL",
            name="wanted_items_matches_kind",
        ),
        Index("ix_listings_owner_updated", "owner_id", text("updated_at DESC")),
        Index("ix_listings_status_created", "status", text("created_at DESC")),
        Index("ix_listings_category_status", "category", "status"),
        Index("ix_listings_kind_status", "kind", "status"),
        Index("ix_listings_condition_status", "condition", "status"),
        Index("ix_listings_search_vector", "search_vector", postgresql_using="gin"),
    )

    owner_id: Mapped[UUID] = mapped_column(
        ForeignKey("users.id", ondelete="RESTRICT"),
        nullable=False,
    )
    title: Mapped[str] = mapped_column(String(80), nullable=False)
    description: Mapped[str] = mapped_column(Text, nullable=False, default="")
    category: Mapped[str] = mapped_column(String(32), nullable=False)
    kind: Mapped[str] = mapped_column(String(32), nullable=False)
    condition: Mapped[str] = mapped_column(String(32), nullable=False)
    price_minor_units: Mapped[int | None] = mapped_column(BigInteger, nullable=True)
    currency: Mapped[str | None] = mapped_column(String(3), nullable=True)
    wanted_items: Mapped[str | None] = mapped_column(String(200), nullable=True)
    status: Mapped[str] = mapped_column(
        String(32), nullable=False, default="active", server_default="active"
    )
    version: Mapped[int] = mapped_column(
        Integer, nullable=False, default=1, server_default="1"
    )
    search_vector: Mapped[str] = mapped_column(
        TSVECTOR,
        Computed("to_tsvector('simple', title || ' ' || description)", persisted=True),
        nullable=False,
    )


class IdempotencyKey(UuidPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "idempotency_keys"
    __table_args__ = (
        Index(
            "uq_idempotency_keys_scope",
            "user_id",
            "operation",
            "key",
            unique=True,
        ),
        Index("ix_idempotency_keys_expires_at", "expires_at"),
    )

    user_id: Mapped[UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    operation: Mapped[str] = mapped_column(String(64), nullable=False)
    key: Mapped[str] = mapped_column(String(128), nullable=False)
    request_fingerprint: Mapped[str] = mapped_column(String(64), nullable=False)
    response_status: Mapped[int] = mapped_column(Integer, nullable=False)
    response_body: Mapped[dict[str, object]] = mapped_column(JSONB, nullable=False)
    expires_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False
    )
