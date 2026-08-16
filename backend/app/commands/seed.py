from __future__ import annotations

import asyncio
from uuid import NAMESPACE_URL, uuid5

from sqlalchemy import select, update
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import AppEnvironment, get_settings
from app.infrastructure.db import Database
from app.infrastructure.db.models import Listing, User, UserIdentity

SELLER_ID = uuid5(NAMESPACE_URL, "https://muto.local/synthetic/seller")
SELLER_TWO_ID = uuid5(NAMESPACE_URL, "https://muto.local/synthetic/seller-two")
SELLER_THREE_ID = uuid5(NAMESPACE_URL, "https://muto.local/synthetic/seller-three")
DEFAULT_USER_ID = uuid5(NAMESPACE_URL, "https://muto.local/synthetic/default-user")
LISTING_IDS = [
    uuid5(NAMESPACE_URL, f"https://muto.local/synthetic/listing/{index}")
    for index in range(1, 4)
]


async def seed_synthetic_data(session: AsyncSession) -> int:
    existing_default_user_id = await session.scalar(
        select(UserIdentity.user_id).where(
            UserIdentity.provider_issuer == "muto-development",
            UserIdentity.provider_subject == "student-a",
        )
    )
    default_user_id = existing_default_user_id or DEFAULT_USER_ID
    await session.execute(
        insert(User)
        .values(
            [
                {
                    "id": SELLER_ID,
                    "display_name": "Marketplace Seller",
                    "is_verified": True,
                    "account_status": "active",
                },
                {
                    "id": default_user_id,
                    "display_name": "Aruzhan",
                    "is_verified": True,
                    "account_status": "active",
                },
                {
                    "id": SELLER_TWO_ID,
                    "display_name": "Madi",
                    "is_verified": True,
                    "account_status": "active",
                },
                {
                    "id": SELLER_THREE_ID,
                    "display_name": "Dias",
                    "is_verified": True,
                    "account_status": "active",
                },
            ]
        )
        .on_conflict_do_nothing(index_elements=[User.id])
    )
    await session.execute(
        insert(UserIdentity)
        .values(
            user_id=SELLER_ID,
            provider_issuer="muto-synthetic-seed",
            provider_subject="sample-seller",
        )
        .on_conflict_do_nothing(constraint="uq_user_identities_provider_subject")
    )
    for seller_id, subject in (
        (SELLER_TWO_ID, "sample-seller-two"),
        (SELLER_THREE_ID, "sample-seller-three"),
    ):
        await session.execute(
            insert(UserIdentity)
            .values(
                user_id=seller_id,
                provider_issuer="muto-synthetic-seed",
                provider_subject=subject,
            )
            .on_conflict_do_nothing(constraint="uq_user_identities_provider_subject")
        )
    await session.execute(
        insert(UserIdentity)
        .values(
            user_id=default_user_id,
            provider_issuer="muto-development",
            provider_subject="student-a",
        )
        .on_conflict_do_nothing(constraint="uq_user_identities_provider_subject")
    )
    listings = [
        {
            "id": LISTING_IDS[0],
            "owner_id": SELLER_ID,
            "title": "Linear algebra textbook",
            "description": "Clean copy with highlighted chapters, useful for exam revision.",
            "category": "textbooks",
            "kind": "sale",
            "condition": "good",
            "price_minor_units": 4500,
            "currency": "KZT",
            "wanted_items": None,
        },
        {
            "id": LISTING_IDS[1],
            "owner_id": SELLER_ID,
            "title": "Desk organizer",
            "description": "Keeps pens, cables, and a calculator tidy on a small study desk.",
            "category": "dorm",
            "kind": "giveaway",
            "condition": "like_new",
            "price_minor_units": None,
            "currency": None,
            "wanted_items": None,
        },
        {
            "id": LISTING_IDS[2],
            "owner_id": SELLER_ID,
            "title": "Badminton racket",
            "description": "Lightly used racket with a fresh grip. Looking for a board game.",
            "category": "sports",
            "kind": "exchange",
            "condition": "worn",
            "price_minor_units": None,
            "currency": None,
            "wanted_items": "A synthetic board game",
        },
        {
            "id": uuid5(NAMESPACE_URL, "https://muto.local/synthetic/listing/calculus"),
            "owner_id": default_user_id,
            "title": "Calculus workbook",
            "description": (
                "Used for MATH 161. No missing pages, with a few pencil notes."
            ),
            "category": "textbooks",
            "kind": "sale",
            "condition": "good",
            "price_minor_units": 8000,
            "currency": "KZT",
            "wanted_items": None,
        },
        {
            "id": uuid5(NAMESPACE_URL, "https://muto.local/synthetic/listing/lamp"),
            "owner_id": default_user_id,
            "title": "Настольная лампа с регулировкой яркости",
            "description": "Почти новая, работает от USB.",
            "category": "dorm",
            "kind": "sale",
            "condition": "like_new",
            "price_minor_units": 4500,
            "currency": "KZT",
            "wanted_items": None,
        },
        {
            "id": uuid5(NAMESPACE_URL, "https://muto.local/synthetic/listing/bicycle"),
            "owner_id": default_user_id,
            "title": "Велосипед горный, 26 дюймов",
            "description": "Тормоза недавно менял, зимой не использовался.",
            "category": "sports",
            "kind": "sale",
            "condition": "good",
            "price_minor_units": 95000,
            "currency": "KZT",
            "wanted_items": None,
        },
        {
            "id": uuid5(NAMESPACE_URL, "https://muto.local/synthetic/listing/guitar"),
            "owner_id": default_user_id,
            "title": "Акустическая гитара, меняю",
            "description": "Строит нормально, чехол в комплекте.",
            "category": "other",
            "kind": "exchange",
            "condition": "good",
            "price_minor_units": None,
            "currency": None,
            "wanted_items": "Микрофон или аудиоинтерфейс",
        },
        {
            "id": uuid5(NAMESPACE_URL, "https://muto.local/synthetic/listing/chair"),
            "owner_id": default_user_id,
            "title": "Free desk chair, pick up from Block 22",
            "description": "The armrest is scuffed but it rolls fine.",
            "category": "furniture",
            "kind": "giveaway",
            "condition": "worn",
            "price_minor_units": None,
            "currency": None,
            "wanted_items": None,
        },
    ]
    await session.execute(
        update(Listing)
        .where(Listing.id.in_(LISTING_IDS))
        .values(
            owner_id=SELLER_ID,
        )
    )
    await session.execute(
        update(Listing)
        .where(Listing.id == LISTING_IDS[1])
        .values(owner_id=SELLER_TWO_ID)
    )
    await session.execute(
        update(Listing)
        .where(Listing.id == LISTING_IDS[2])
        .values(owner_id=SELLER_THREE_ID)
    )
    result = await session.execute(
        insert(Listing)
        .values(listings)
        .on_conflict_do_nothing(index_elements=[Listing.id])
        .returning(Listing.id)
    )
    await session.commit()
    return len(list(result.scalars()))


async def run() -> int:
    settings = get_settings()
    if settings.environment == AppEnvironment.production:
        raise RuntimeError("synthetic seeding is disabled in production")
    database = Database(settings.database_url)
    try:
        async with database.session_maker() as session:
            return await seed_synthetic_data(session)
    finally:
        await database.close()


def main() -> None:
    created = asyncio.run(run())
    print(f"synthetic listings created: {created}")


if __name__ == "__main__":
    main()
