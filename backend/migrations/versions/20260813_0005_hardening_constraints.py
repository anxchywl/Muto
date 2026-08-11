from __future__ import annotations

from collections.abc import Sequence

from alembic import op

revision: str = "20260813_0005"
down_revision: str | None = "20260813_0004"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_check_constraint(
        op.f("ck_listings_price_within_currency_limit"),
        "listings",
        "(currency = 'KZT' AND price_minor_units <= 50000000) OR "
        "(currency = 'USD' AND price_minor_units <= 10000000) OR "
        "price_minor_units IS NULL",
    )
    op.create_check_constraint(
        op.f("ck_listings_title_length_allowed"),
        "listings",
        "char_length(title) BETWEEN 3 AND 80",
    )
    op.create_check_constraint(
        op.f("ck_listings_description_length_allowed"),
        "listings",
        "char_length(description) <= 2000",
    )
    op.create_check_constraint(
        op.f("ck_reports_note_length_allowed"),
        "reports",
        "note IS NULL OR char_length(note) <= 500",
    )
    op.create_check_constraint(
        op.f("ck_image_uploads_detected_mime_allowed"),
        "image_uploads",
        "detected_mime_type IS NULL OR "
        "detected_mime_type IN ('image/jpeg', 'image/png', 'image/webp')",
    )
    op.create_check_constraint(
        op.f("ck_image_uploads_byte_size_allowed"),
        "image_uploads",
        "byte_size IS NULL OR (byte_size > 0 AND byte_size <= 5242880)",
    )
    op.create_check_constraint(
        op.f("ck_image_uploads_dimensions_allowed"),
        "image_uploads",
        "width IS NULL OR height IS NULL OR "
        "(width >= 200 AND height >= 200 AND width::bigint * height <= 50000000)",
    )


def downgrade() -> None:
    op.drop_constraint(
        op.f("ck_image_uploads_dimensions_allowed"),
        "image_uploads",
        type_="check",
    )
    op.drop_constraint(
        op.f("ck_image_uploads_byte_size_allowed"),
        "image_uploads",
        type_="check",
    )
    op.drop_constraint(
        op.f("ck_image_uploads_detected_mime_allowed"),
        "image_uploads",
        type_="check",
    )
    op.drop_constraint(
        op.f("ck_reports_note_length_allowed"),
        "reports",
        type_="check",
    )
    op.drop_constraint(
        op.f("ck_listings_description_length_allowed"),
        "listings",
        type_="check",
    )
    op.drop_constraint(
        op.f("ck_listings_title_length_allowed"),
        "listings",
        type_="check",
    )
    op.drop_constraint(
        op.f("ck_listings_price_within_currency_limit"),
        "listings",
        type_="check",
    )
