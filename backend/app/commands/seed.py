from __future__ import annotations

import asyncio
from uuid import NAMESPACE_URL, uuid5

from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import AppEnvironment, get_settings
from app.infrastructure.db import Database
from app.infrastructure.db.models import Listing, User, UserIdentity

SELLER_ID = uuid5(NAMESPACE_URL, "https://muto.local/synthetic/seller")
LISTING_IDS = [
    uuid5(NAMESPACE_URL, f"https://muto.local/synthetic/listing/{index}")
    for index in range(1, 4)
]


async def seed_synthetic_data(session: AsyncSession) -> int:
    await session.execute(
        insert(User)
        .values(
            id=SELLER_ID,
            display_name="Sample Seller",
            is_verified=True,
            account_status="active",
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
    listings = [
        {
            "id": LISTING_IDS[0],
            "owner_id": SELLER_ID,
            "title": "Linear algebra textbook",
            "description": "Synthetic local development listing",
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
            "description": "Synthetic local development listing",
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
            "description": "Synthetic local development listing",
            "category": "sports",
            "kind": "exchange",
            "condition": "worn",
            "price_minor_units": None,
            "currency": None,
            "wanted_items": "A synthetic board game",
        },
    ]
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
