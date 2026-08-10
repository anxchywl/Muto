from __future__ import annotations

from enum import StrEnum

from app.domain.errors import ConflictError, ValidationError


class ListingKind(StrEnum):
    sale = "sale"
    exchange = "exchange"
    giveaway = "giveaway"


class ListingCondition(StrEnum):
    new = "new"
    like_new = "like_new"
    good = "good"
    worn = "worn"


class ListingCategory(StrEnum):
    textbooks = "textbooks"
    electronics = "electronics"
    furniture = "furniture"
    clothing = "clothing"
    sports = "sports"
    dorm = "dorm"
    tickets = "tickets"
    other = "other"


class ListingStatus(StrEnum):
    active = "active"
    reserved = "reserved"
    sold = "sold"
    hidden = "hidden"
    removed = "removed"


class ListingSort(StrEnum):
    newest = "newest"
    price_ascending = "price_ascending"
    price_descending = "price_descending"


ALLOWED_TRANSITIONS = {
    ListingStatus.active: {
        ListingStatus.reserved,
        ListingStatus.sold,
        ListingStatus.hidden,
        ListingStatus.removed,
    },
    ListingStatus.reserved: {
        ListingStatus.active,
        ListingStatus.sold,
        ListingStatus.removed,
    },
    ListingStatus.sold: {ListingStatus.active, ListingStatus.removed},
    ListingStatus.hidden: {ListingStatus.active, ListingStatus.removed},
    ListingStatus.removed: set(),
}

EDITABLE_STATUSES = {
    ListingStatus.active,
    ListingStatus.reserved,
    ListingStatus.hidden,
}
PUBLIC_STATUSES = {ListingStatus.active, ListingStatus.reserved}
SUPPORTED_CURRENCIES = {"KZT": 50_000_000, "USD": 10_000_000}


def require_transition(current: ListingStatus, target: ListingStatus) -> None:
    if target not in ALLOWED_TRANSITIONS[current]:
        raise ConflictError(
            "listing_transition_invalid",
            f"A {current.value} listing cannot become {target.value}.",
        )


def validate_listing_values(
    *,
    kind: ListingKind,
    price_minor_units: int | None,
    currency: str | None,
    wanted_items: str | None,
) -> None:
    if kind == ListingKind.sale:
        if price_minor_units is None or currency is None:
            raise ValidationError(
                "listing_price_required",
                "A sale listing requires a price and currency.",
            )
        maximum = SUPPORTED_CURRENCIES.get(currency)
        if maximum is None or price_minor_units <= 0 or price_minor_units > maximum:
            raise ValidationError(
                "listing_price_invalid",
                "The listing price is outside the allowed range.",
            )
    elif price_minor_units is not None or currency is not None:
        raise ValidationError(
            "listing_price_not_allowed",
            "Only sale listings may have a price.",
        )
    if kind != ListingKind.exchange and wanted_items is not None:
        raise ValidationError(
            "listing_wanted_items_not_allowed",
            "Wanted items are only valid for exchange listings.",
        )
