from __future__ import annotations

import pytest

from app.domain.errors import ConflictError, ValidationError
from app.domain.listings import (
    ALLOWED_TRANSITIONS,
    ListingKind,
    ListingStatus,
    require_transition,
    validate_listing_values,
)


def test_every_listing_transition_matches_the_product_contract() -> None:
    for current in ListingStatus:
        for target in ListingStatus:
            if target in ALLOWED_TRANSITIONS[current]:
                require_transition(current, target)
            else:
                with pytest.raises(ConflictError):
                    require_transition(current, target)


def test_sale_requires_a_bounded_price_and_currency() -> None:
    validate_listing_values(
        kind=ListingKind.sale,
        price_minor_units=1,
        currency="KZT",
        wanted_items=None,
    )
    with pytest.raises(ValidationError):
        validate_listing_values(
            kind=ListingKind.sale,
            price_minor_units=0,
            currency="KZT",
            wanted_items=None,
        )


def test_non_sale_cannot_carry_a_price() -> None:
    with pytest.raises(ValidationError):
        validate_listing_values(
            kind=ListingKind.giveaway,
            price_minor_units=100,
            currency="KZT",
            wanted_items=None,
        )


def test_wanted_items_belong_to_an_exchange() -> None:
    with pytest.raises(ValidationError):
        validate_listing_values(
            kind=ListingKind.giveaway,
            price_minor_units=None,
            currency=None,
            wanted_items="A lamp",
        )
