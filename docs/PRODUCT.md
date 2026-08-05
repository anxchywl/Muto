# Product

What Muto does, what it deliberately does not do, and what is currently
simulated. How it is built is in [ARCHITECTURE.md](ARCHITECTURE.md).

## What it is

A marketplace for verified Nazarbayev University students. Someone lists a
thing they no longer need; someone else finds it and gets in touch. The
exchange itself happens between the two people, off the app.

## What a student can do

- Browse listings, search them, and narrow them by category, type, condition
  and order
- Open a listing and see its photos, price, condition and description
- Save listings and come back to them
- Contact a seller through Telegram, email or phone
- Publish something for sale, for swap, or to give away
- Manage their own listings: edit, reserve, mark sold, hide, relist, remove

## What it does not do, on purpose

No payments, checkout, delivery, cart, or coupons. No ratings or reviews. No
advertising or promoted listings. No in-app messaging: contact is external, and
no conversation is ever stored. No moderation queue — this is peer to peer
between students the university has already verified.

Every one of these is a decision, not a gap.

## Kinds of listing

| Kind | Price | Also asks for |
|---|---|---|
| For sale | Required, above zero | — |
| Swap | Never | What the seller wants in return |
| Free | Never | — |

A price is meaningless without a currency, so an amount is always held with
one: KZT in whole tenge, USD in cents. Nothing is converted between them, and
a price filter therefore applies inside one currency at a time.

## Lifecycle

```text
draft (on the device, never sent)
  └─ publish ──→ active
                   ├──→ reserved ──→ active | sold | removed
                   ├──→ sold ──────→ active (relist) | removed
                   ├──→ hidden ────→ active | removed
                   └──→ removed (final)
```

Only the owner moves a listing, and only along an arrow above. Anything else is
refused rather than quietly allowed.

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

Editing is possible while a listing is active, reserved or hidden. A sold
listing cannot be edited, only relisted or removed.

## Contact

Seller contact details appear on the listing detail screen only, and only for a
student the server considers verified. They are never in the feed, in search
results, or in any preview.

Nothing opens on its own. Choosing a channel shows the full destination first
and waits for the student to agree.

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

## What is simulated

**There is no server.** Everything runs against sample data bundled with the
app, and a `Sample data` banner says so on every screen. It cannot be
dismissed.

Simulated, and behaving as the real thing is specified to:

- listing reads, writes and status changes, including who is allowed to make
  them
- pagination, page by page, with an opaque cursor
- rejecting a write whose version is out of date
- returning the same listing when a publish is retried with the same token
- refusing a photo that breaks the rules
- staging a photo and redeeming it when the listing is saved
- failure injection: offline, expired session, forced conflict

Not simulated, and not present at all:

- any network call
- any account system; the standalone host uses a placeholder session and no
  credentials exist anywhere in this repository
- durability. Published listings live in memory and are gone when the app
  restarts. Saved listings and the unfinished draft are the only things kept on
  the device.

Nothing in this repository has run against a real server.
