from __future__ import annotations

from uuid import UUID

from sqlalchemy import (
    Boolean,
    CheckConstraint,
    ForeignKey,
    Index,
    String,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.infrastructure.db.base import Base, TimestampMixin, UuidPrimaryKeyMixin


class User(UuidPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "users"
    __table_args__ = (
        CheckConstraint(
            "account_status IN ('active', 'suspended')",
            name="account_status_allowed",
        ),
        Index("ix_users_account_status", "account_status"),
    )

    display_name: Mapped[str | None] = mapped_column(String(255), nullable=True)
    is_verified: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
        default=False,
        server_default="false",
    )
    account_status: Mapped[str] = mapped_column(
        String(32),
        nullable=False,
        default="active",
        server_default="active",
    )
    telegram_username: Mapped[str | None] = mapped_column(String(64), nullable=True)
    email: Mapped[str | None] = mapped_column(String(320), nullable=True)
    phone: Mapped[str | None] = mapped_column(String(32), nullable=True)

    identities: Mapped[list[UserIdentity]] = relationship(
        back_populates="user",
        cascade="all, delete-orphan",
        passive_deletes=True,
    )


class UserIdentity(UuidPrimaryKeyMixin, TimestampMixin, Base):
    __tablename__ = "user_identities"
    __table_args__ = (
        UniqueConstraint(
            "provider_issuer",
            "provider_subject",
            name="uq_user_identities_provider_subject",
        ),
        Index("ix_user_identities_user_id", "user_id"),
    )

    user_id: Mapped[UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    provider_issuer: Mapped[str] = mapped_column(String(255), nullable=False)
    provider_subject: Mapped[str] = mapped_column(String(255), nullable=False)

    user: Mapped[User] = relationship(back_populates="identities")
