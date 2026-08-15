# Muto API Contract

The boundary between the Flutter repository interfaces and the independent
backend service. Product meaning remains in [PRODUCT.md](./PRODUCT.md); this
document owns endpoint and wire-shape decisions.

## Current implementation

Phases 1 through 6 implement and harden the service and Flutter remote adapters
for:

| Endpoint | Authentication | Purpose |
|---|---|---|
| `GET /health/live` | No | Process liveness |
| `GET /health/ready` | No | Database readiness |
| `GET /api/v1/me` | Bearer token | Resolve the current stable marketplace identity |
| `GET /api/v1/listings` | Bearer token | Browse, search, filter and paginate visible listings |
| `GET /api/v1/listings/suggestions` | Bearer token | Complete a search prefix from visible titles |
| `GET /api/v1/listings/{listing_id}` | Bearer token | Read a visible or deliberately unavailable listing |
| `GET /api/v1/me/listings` | Bearer token | Read the current owner's non-removed listings |
| `POST /api/v1/listings` | Verified bearer token | Publish an idempotent listing |
| `PATCH /api/v1/listings/{listing_id}` | Owner bearer token | Edit with an expected version |
| `PATCH /api/v1/listings/{listing_id}/status` | Owner bearer token | Apply an idempotent lifecycle transition |
| `DELETE /api/v1/listings/{listing_id}` | Owner bearer token | Move a listing to the final removed state |
| `GET /api/v1/favorites` | Bearer token | Page through currently visible saved listings |
| `GET /api/v1/favorites/ids` | Bearer token | Read the current account's saved listing IDs |
| `PUT /api/v1/favorites/{listing_id}` | Bearer token | Save a listing idempotently |
| `DELETE /api/v1/favorites/{listing_id}` | Bearer token | Remove a saved listing safely |
| `GET /api/v1/sellers/{user_id}` | Bearer token | Read a sanitized marketplace profile |
| `GET /api/v1/sellers/{user_id}/listings` | Bearer token | Page through that seller's visible listings |
| `POST /api/v1/reports` | Bearer token | Submit an idempotent, one-way report |
| `GET /api/v1/operations/reports` | Operator bearer token | Read cursor-paginated report intake without reporter identity |
| `POST /api/v1/image-uploads` | Bearer token | Request a short-lived authenticated upload slot |
| `PUT /api/v1/image-uploads/{upload_id}/content` | Owner bearer token | Decode, validate and normalize image bytes |
| `POST /api/v1/image-uploads/{upload_id}/finalize` | Owner bearer token | Finalize idempotently and return an image reference |
| `GET /api/v1/listings/{listing_id}/images` | Bearer token | Read references under normal listing visibility rules |
| `GET /api/v1/images/{image_id}/{version}` | Bearer token | Read controlled private image bytes |

JSON endpoints return `data` and `meta.request_id`. The controlled image
endpoint returns bytes with an allow-listed content type and immutable private
caching.

## Repository mapping

| Flutter interface | Backend endpoint | Request | Response | Errors |
|---|---|---|---|---|
| `SessionRepository.resolve` | `GET /api/v1/me` | Bearer token | Identity | `401` invalid token, `403` suspended account |
| `ListingRepository.browse` | `GET /api/v1/listings` | Filters, sort, limit and cursor | Listing page without contact, including `created_at` and `expires_at` | `401`, `409` cursor/filter mismatch, `422` invalid input or cursor |
| `ListingRepository.suggestions` | `GET /api/v1/listings/suggestions` | Prefix | String list | `401`, `422` invalid prefix |
| `ListingRepository.byId` | `GET /api/v1/listings/{listing_id}` | Listing id | Detail with conditional contact | `401`, `404` absent or hidden, `410` removed |
| `ListingRepository.mine` | `GET /api/v1/me/listings` | Status, limit and cursor | Owner-visible listing page | `401`, `422` invalid input or cursor |
| `ListingRepository.create` | `POST /api/v1/listings` | Draft and `Idempotency-Key` | Active listing | `401`, `403` unverified, `409` reused key, `422` invalid draft or key |
| `ListingRepository.update` | `PATCH /api/v1/listings/{listing_id}` | Draft and `If-Match` | Updated listing | `401`, `403`, `404`, `409` stale or not editable, `410`, `422` |
| `ListingRepository.changeStatus` | `PATCH /api/v1/listings/{listing_id}/status` | Status, `If-Match` and `Idempotency-Key` | Updated listing; relisting renews `expires_at` | `401`, `403`, `404`, `409` stale, invalid transition or reused key, `410`, `422` |
| `ListingRepository.remove` | `DELETE /api/v1/listings/{listing_id}` | `If-Match` and `Idempotency-Key` | Removed listing version | `401`, `403`, `404`, `409`, `410`, `422` |
| `FavoritesRepository.page` | `GET /api/v1/favorites` | Limit and cursor | Visible favorite page without contact | `401`, `409` account/cursor mismatch, `422` invalid input or cursor |
| `FavoritesRepository.savedIds` | `GET /api/v1/favorites/ids` | None | Saved listing ids | `401` |
| `FavoritesRepository.add` | `PUT /api/v1/favorites/{listing_id}` | Listing id | Idempotent saved state | `401`, `404` absent or hidden, `410` removed, `422` invalid id |
| `FavoritesRepository.remove` | `DELETE /api/v1/favorites/{listing_id}` | Listing id | Idempotent unsaved state | `401`, `422` invalid id |
| `SellerRepository.profile` | `GET /api/v1/sellers/{user_id}` | Public user id | Sanitized profile | `401`, `404` no listing history, `422` invalid id |
| `SellerRepository.listings` | `GET /api/v1/sellers/{user_id}/listings` | Limit and cursor | Active or reserved listing page | `401`, `409` seller/cursor mismatch, `422` invalid input or cursor |
| `ReportRepository.submit` | `POST /api/v1/reports` | Listing, reason, note and `Idempotency-Key` | Non-revealing acceptance | `401`, `403` own listing, `404`, `409` reused key, `410`, `422`, `429` burst limit |
| `ReportOperationsRepository.reports` | `GET /api/v1/operations/reports` | Operator bearer token and cursor | Reports without reporter identity | `401`, `403`, `409` malformed or mismatched cursor |
| `ImageRepository.stage` | `POST /api/v1/image-uploads`, `PUT .../content`, `POST .../finalize` | MIME claim, byte count, bytes and idempotency key | Staged image reference | `401`, `403`, `409`, `410` expired, `413` oversized body, `422` invalid image, `503` storage unavailable |
| `ImageLocator` | `GET /api/v1/images/{image_id}/{version}` | Image id and content version | Controlled image bytes | `401`, `404` unavailable or unauthorized, `410` owner's expired stage |

`DraftStore` and `SearchHistoryStore` remain device-local and have no backend
endpoint.

## Common protocol

Successful JSON responses use:

```json
{
  "data": {},
  "meta": {
    "request_id": "..."
  }
}
```

Errors use:

```json
{
  "error": {
    "code": "listing_version_conflict",
    "message": "The listing changed before this update was applied.",
    "request_id": "..."
  }
}
```

Mutation retries use `Idempotency-Key`. Versioned listing writes use
`If-Match`, and successful listing responses return `ETag`. Pagination cursors
are opaque, validated, filter-bound keyset cursors rather than offsets.
Idempotency records expire after 24 hours by default; the setting is bounded to
one through seven days. An expired record is replaced if its key is used again.
Bulk cleanup of expired records remains an operational maintenance task.

Reports are limited to five accepted attempts per account in a rolling
ten-minute window by default. A retry with the same idempotency key returns its
original acceptance before rate limiting. A limited response includes
`Retry-After`; different accounts have independent limits.

Image slots accept JPEG, PNG and WebP declarations and at most 5 MB. The server
decodes the content, checks its real format and dimensions, rejects animation,
enforces a 200-pixel minimum edge and 50-million-pixel ceiling, then re-encodes
it without source metadata. Client dimensions, extensions and MIME claims are
not authority. Object keys are generated from server UUIDs.
Starting upload slots is limited per account to 30 in a rolling hour by
default, independently of the report limit.

Finalization moves normalized bytes into private versioned storage and is
idempotent. A finalized reference belongs to one account and may be redeemed by
only one listing. Listing creation or editing accepts up to six references and
redeems them in the same database transaction as the listing write. Removing a
reference revokes its controlled URL and makes it eligible for cleanup.

Every marketplace endpoint requires an authenticated principal. Identity,
ownership and verification are derived from that principal and never accepted
from a request body.

## Resolved mock ambiguities

The mock favorite repository accepts any string and discovers a missing or
hidden listing only when the feed is read. The database cannot safely preserve
dangling references, so the backend accepts a favorite only for a listing the
current account can open. Removing an absent favorite remains a safe success.

The mock keeps a saved ID after a listing leaves circulation while omitting the
listing from the favorite feed. The backend preserves that distinction: IDs
remain saved for toggle state, but only active and reserved listings appear in
the page.

The mock image repository receives client-supplied dimensions and keeps the
original bytes in memory. The backend treats those values only as client hints:
it derives dimensions from decoded content and stores a normalized copy. The
mock's one-call `stage` maps to the three authenticated upload calls above; the
Flutter remote repository hides that wire sequence behind the same domain
interface.

Production uses the S3-compatible adapter with server-generated keys and a
private bucket. Clients never receive object credentials or object keys. Image
delivery remains the authenticated `GET /api/v1/images/...` endpoint, so hidden,
removed and cross-account checks run before bytes leave storage.
