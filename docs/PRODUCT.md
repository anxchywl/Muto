# Muto Product Specification

Canonical product behaviour and rules. How it is built is in
[ARCHITECTURE.md](./ARCHITECTURE.md); how it is run and shipped is in
[INFRASTRUCTURE.md](./INFRASTRUCTURE.md); the summary is in
[README.md](../README.md).

## Surfaces

- **Embeddable Flutter feature.** The marketplace itself: browse, search,
  listing detail, seller profile, favorites, the student's own listings, the
  editor, and reporting. Mounted inside a host application.
- **Standalone Flutter host.** Development only. It supplies theme, locale and
  a placeholder session so the feature can be run without a host, and a release
  build of it refuses to open at all.

The feature is not integrated with Jas Wallet. Standalone development access is
the current state, and the host contract exists but has never been exercised
against a real host.

## Identity and roles

- The host supplies a token. It is exchanged for an identity and never stored.
- The feature never decides who the student is, and never decides whether they
  are verified. Both come back from whatever resolved the session.
- There is no role in this product. A listing has an owner, and that is the
  only distinction the marketplace makes.
- Verification gates two things: publishing, and seeing a seller's contact
  details. Nothing else changes with it.
- An unauthorized response clears feature state and asks the host to
  re-authenticate exactly once per token. Being offline is a different outcome
  and never asks.

## Kinds of listing

| Kind | Price | Also asks for |
|---|---|---|
| For sale | Required, above zero | — |
| Swap | Never | What the seller wants in return |
| Free | Never | — |

A price is meaningless without a currency, so an amount is always held with
one: KZT in whole tenge, USD in cents. Nothing is converted between them, and a
price filter therefore applies inside one currency at a time.

## Listing lifecycle

```text
draft (on the device, never sent)
  └─ publish ──→ active
                   ├──→ reserved ──→ active | sold | removed
                   ├──→ sold ──────→ active (relist) | removed
                   ├──→ hidden ────→ active | removed
                   └──→ removed (final)
```

Rules:

- Only the owner moves a listing, and only along an arrow above. Anything else
  is refused rather than quietly allowed.
- Publishing accepts a client request id. Repeating it with the same draft
  returns the listing already created; reusing it with a changed draft is
  rejected.
- Every update carries the version it was read at. A stale write is refused
  with a conflict rather than overwriting a newer one.
- A photo reference is staged, owned by one account, and redeemed when the
  listing is saved. One that is never redeemed expires.
- A published listing is active for 30 days from publication. After that it is
  hidden from other students and remains visible to its owner as needing a
  relist. Relisting renews the 30-day window without changing the original
  posted date.
- Editing is possible while a listing is active, reserved or hidden. A sold
  listing cannot be edited, only relisted or removed.

## Who sees what

| Status | Owner | Another student | Opened by an old link |
|---|---|---|---|
| Active | Yes | In the feed | Opens |
| Reserved | Yes | In the feed, marked reserved | Opens |
| Sold | In their listings | Not in the feed | Opens, read only |
| Hidden | In their listings | Invisible | Not found |
| Removed | Gone | Invisible | Says it was taken down |

A sold listing stays reachable on purpose. Someone following an old link is
asking "did this go?", and answering that is more useful than an error.

## Finding things

- Search, category, type, condition and order narrow the same feed. Pagination
  is bounded and cursor-based.
- Suggestions come from the titles of listings that are actually visible. They
  carry no ids, no prices and no contact details.
- Recent searches are recorded on submit, not on keystroke, are bounded to
  eight, belong to one account, and never survive an account switch.
- A seller's page shows their listings still in circulation and a count. There
  is no reputation, no rating and no history of what they sold.

## Contact

Seller contact details appear on the listing detail screen only, and only for a
student the server considers verified. They are never in the feed, in search
results, in a seller's page, or in any other preview.

Contact details arrive as structured fields — a Telegram username, an email
address, a phone number — never as a URL. The client validates each for shape
and builds the destination itself. Nothing opens on its own: choosing a channel
shows the full destination first and waits.

## Reporting

A student may report someone else's listing, never their own. A reason is
required, and a note is required when the reason is "something else".

Reporting is one way. There is no queue, no verdict, no appeal, and nothing
that says whether anyone else reported the same listing. A retry sends nothing
twice, and a burst is refused.

An authenticated operator may read reports in a private intake surface. The
surface never exposes reporter identity and has no verdict, appeal or automated
enforcement. Operational retention and escalation are defined in
[INFRASTRUCTURE.md](./INFRASTRUCTURE.md); reporting promises receipt and review,
not a particular outcome.

## Photos

Up to six per listing, at most 5 MB each, JPEG, PNG or WebP. The file type is
decided by reading the image itself rather than trusting its name. A photo that
fails a check is refused with a reason rather than silently dropped.

## Language and money

English, Kazakh and Russian, everywhere: every screen, state, validation
message, dialog, error and screen-reader label. The reader's language comes
from the host application, and anything outside those three falls back to
English.

Prices, dates and counts are formatted for the reader's language, including
Russian's four plural forms.

## What is not built, on purpose

No payments, checkout, delivery, cart or coupons. No ratings or reviews. No
advertising or promoted listings. No in-app messaging: contact is external, and
no conversation is ever stored. No moderation queue, verdict or appeal — this
is peer to peer between students the university has already verified.

Every one of these is a decision, not a gap.

## What is simulated

Sample mode runs entirely against bundled data. Remote mode implements the
same feature behavior through the backend and is selected explicitly by the
host; it never falls back to sample records after a network or configuration
failure.

Simulated, and behaving as the real thing is specified to:

- failure injection: offline, expired session, forced conflict

Not implemented for production:

- any production account resolution; the standalone host uses a placeholder
  session and the backend's real host adapter fails closed until its token
  contract is defined
- provisioned production object storage and credentials; the private
  S3-compatible adapter and lifecycle policy are implemented

Sample-mode publications live in memory and disappear when the app restarts.
Remote-mode publications persist in PostgreSQL. Unfinished drafts and recent
searches remain device-local in both modes.
