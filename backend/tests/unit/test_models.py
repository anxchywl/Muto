from __future__ import annotations

from sqlalchemy import CheckConstraint, UniqueConstraint

from app.infrastructure.db.models import (
    Favorite,
    ImageUpload,
    Listing,
    ListingImage,
    Report,
    User,
    UserIdentity,
)


def test_user_account_status_is_constrained() -> None:
    constraints = {
        constraint.name
        for constraint in User.__table__.constraints
        if isinstance(constraint, CheckConstraint)
    }
    assert "ck_users_account_status_allowed" in constraints
    assert User.__table__.c.email.unique is not True


def test_external_identity_is_unique_by_issuer_and_subject() -> None:
    constraints = {
        constraint.name
        for constraint in UserIdentity.__table__.constraints
        if isinstance(constraint, UniqueConstraint)
    }
    assert "uq_user_identities_provider_subject" in constraints
    foreign_key = next(iter(UserIdentity.__table__.c.user_id.foreign_keys))
    assert foreign_key.ondelete == "CASCADE"


def test_favorites_are_unique_per_account_and_listing() -> None:
    constraints = {
        constraint.name
        for constraint in Favorite.__table__.constraints
        if isinstance(constraint, UniqueConstraint)
    }
    assert "uq_favorites_user_listing" in constraints


def test_reports_are_unique_without_exposing_other_reporters() -> None:
    constraints = {
        constraint.name
        for constraint in Report.__table__.constraints
        if isinstance(constraint, UniqueConstraint)
    }
    assert "uq_reports_reporter_listing" in constraints


def test_listing_images_have_stable_positions_and_single_redemption() -> None:
    constraints = {
        constraint.name
        for constraint in ListingImage.__table__.constraints
        if isinstance(constraint, UniqueConstraint)
    }
    assert "uq_listing_images_listing_position" in constraints
    assert "uq_listing_images_upload" in constraints
    owner_key = next(iter(ImageUpload.__table__.c.owner_id.foreign_keys))
    assert owner_key.ondelete == "CASCADE"


def test_persisted_content_bounds_are_database_constraints() -> None:
    listing_constraints = {
        constraint.name
        for constraint in Listing.__table__.constraints
        if isinstance(constraint, CheckConstraint)
    }
    report_constraints = {
        constraint.name
        for constraint in Report.__table__.constraints
        if isinstance(constraint, CheckConstraint)
    }
    image_constraints = {
        constraint.name
        for constraint in ImageUpload.__table__.constraints
        if isinstance(constraint, CheckConstraint)
    }
    assert "ck_listings_price_within_currency_limit" in listing_constraints
    assert "ck_listings_description_length_allowed" in listing_constraints
    assert "ck_reports_note_length_allowed" in report_constraints
    assert "ck_image_uploads_dimensions_allowed" in image_constraints
