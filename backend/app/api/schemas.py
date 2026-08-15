from __future__ import annotations

import re
from datetime import datetime
from typing import Annotated, Self
from uuid import UUID

from pydantic import BaseModel, Field, field_validator, model_validator

from app.domain.images import MAX_IMAGE_BYTES, MAX_LISTING_IMAGES
from app.domain.listings import (
    ListingCategory,
    ListingCondition,
    ListingKind,
    ListingSort,
    ListingStatus,
)
from app.domain.reports import ReportReason, validate_report

UNSAFE_TEXT = re.compile(
    "[\u0000-\u0008\u000b-\u000c\u000e-\u001f\u007f-\u009f"
    "\u200b-\u200f\u202a-\u202e\u2060-\u2064\u2066-\u206f\ufeff]"
)


def normalize_line(value: str) -> str:
    return " ".join(UNSAFE_TEXT.sub("", value).replace("\r", "\n").split())


def normalize_block(value: str) -> str:
    cleaned = UNSAFE_TEXT.sub("", value).replace("\r\n", "\n").replace("\r", "\n")
    lines = [" ".join(line.split()) for line in cleaned.split("\n")]
    result: list[str] = []
    for line in lines:
        if line or not result or result[-1]:
            result.append(line)
    return "\n".join(result).strip()


class IdentityResponse(BaseModel):
    user_id: UUID
    display_name: str
    is_verified: bool
    is_admin: bool


class MoneyResponse(BaseModel):
    minor_units: int
    currency: str


class ImageReference(BaseModel):
    id: UUID
    version: Annotated[str, Field(min_length=16, max_length=64)]


class ImageUploadSlotRequest(BaseModel):
    mime_type: Annotated[str, Field(min_length=1, max_length=32)]
    byte_length: Annotated[int, Field(ge=1, le=MAX_IMAGE_BYTES)]


class ImageUploadSlotResponse(BaseModel):
    upload_id: UUID
    upload_target: str
    expires_at: datetime


class ImageUploadReceipt(BaseModel):
    upload_id: UUID
    mime_type: str
    byte_size: int
    width: int
    height: int


class ListingResponse(BaseModel):
    id: UUID
    version: int
    kind: ListingKind
    status: ListingStatus
    title: str
    description: str
    condition: ListingCondition
    category: ListingCategory
    images: list[ImageReference] = Field(default_factory=list)
    seller_id: UUID
    seller_display_name: str
    created_at: datetime
    expires_at: datetime
    updated_at: datetime
    price: MoneyResponse | None = None
    wanted_items: str | None = None
    contact: dict[str, str] | None = None


class PageMeta(BaseModel):
    request_id: str
    next_cursor: str | None = None


class ListingPageResponse(BaseModel):
    data: list[ListingResponse]
    meta: PageMeta


class FavoriteIdsResponse(BaseModel):
    data: list[UUID]
    meta: PageMeta


class SellerProfileResponse(BaseModel):
    seller_id: UUID
    display_name: str
    is_verified: bool
    active_listing_count: int
    first_listed_at: datetime


class ReportRequest(BaseModel):
    listing_id: UUID
    reason: ReportReason
    note: str | None = Field(default=None, max_length=500)

    @field_validator("note", mode="before")
    @classmethod
    def clean_note(cls, value: object) -> object:
        if not isinstance(value, str):
            return value
        cleaned = normalize_block(value)
        return cleaned or None

    @model_validator(mode="after")
    def validate_reason(self) -> Self:
        validate_report(self.reason, self.note)
        return self


class OperationalReportResponse(BaseModel):
    id: UUID
    listing_id: UUID
    listing_title: str
    listing_status: ListingStatus
    reason: ReportReason
    note: str | None
    created_at: datetime


class OperationalReportPage(BaseModel):
    data: list[OperationalReportResponse]
    meta: PageMeta


class ListingDraftRequest(BaseModel):
    kind: ListingKind
    title: Annotated[str, Field(min_length=3, max_length=80)]
    description: Annotated[str, Field(max_length=2000)] = ""
    condition: ListingCondition
    category: ListingCategory
    price_minor_units: int | None = None
    currency: str | None = Field(default=None, min_length=3, max_length=3)
    wanted_items: str | None = Field(default=None, max_length=200)
    images: list[ImageReference] = Field(
        default_factory=list,
        max_length=MAX_LISTING_IMAGES,
    )

    @field_validator("title")
    @classmethod
    def clean_title(cls, value: str) -> str:
        cleaned = normalize_line(value)
        if len(cleaned) < 3:
            raise ValueError("title is too short after normalization")
        return cleaned

    @field_validator("description")
    @classmethod
    def clean_description(cls, value: str) -> str:
        return normalize_block(value)

    @field_validator("wanted_items")
    @classmethod
    def clean_wanted_items(cls, value: str | None) -> str | None:
        if value is None:
            return None
        cleaned = normalize_line(value)
        return cleaned or None

    @field_validator("currency")
    @classmethod
    def normalize_currency(cls, value: str | None) -> str | None:
        return value.upper() if value else None


class ListingStatusRequest(BaseModel):
    status: ListingStatus


class ListingQueryParams(BaseModel):
    q: str | None = Field(default=None, max_length=80)
    category: ListingCategory | None = None
    kind: ListingKind | None = None
    condition: ListingCondition | None = None
    currency: str | None = Field(default=None, min_length=3, max_length=3)
    min_minor_units: int | None = Field(default=None, ge=0)
    max_minor_units: int | None = Field(default=None, ge=0)
    sort: ListingSort = ListingSort.newest
    status: ListingStatus | None = None
    cursor: str | None = Field(default=None, max_length=1000)
    limit: int | None = Field(default=None, ge=1, le=100)

    @field_validator("q")
    @classmethod
    def clean_query(cls, value: str | None) -> str | None:
        if value is None:
            return None
        cleaned = normalize_line(value)
        return cleaned or None

    @field_validator("currency")
    @classmethod
    def clean_currency(cls, value: str | None) -> str | None:
        return value.upper() if value else None

    @model_validator(mode="after")
    def validate_ranges(self) -> Self:
        if (
            self.min_minor_units is not None or self.max_minor_units is not None
        ) and self.currency is None:
            raise ValueError("price ranges require a currency")
        if (
            self.min_minor_units is not None
            and self.max_minor_units is not None
            and self.min_minor_units > self.max_minor_units
        ):
            raise ValueError("minimum price cannot exceed maximum price")
        if self.sort != ListingSort.newest and self.currency is None:
            raise ValueError("price ordering requires a currency")
        return self
