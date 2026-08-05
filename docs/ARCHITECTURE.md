# Architecture

How Muto is put together. What it does is in [PRODUCT.md](PRODUCT.md); the
rules for changing it are in [../AGENTS.md](../AGENTS.md).

## Packages

```text
app_ui/        design tokens, buttons, cards, sheets, icons, light and dark theme
muto_ui/       marketplace widgets built from those tokens
muto_feature/  the marketplace itself: domain, application, data, presentation
muto_app/      standalone host: MaterialApp, theme, locale, lifecycle
```

Dependencies point one way, `muto_app → muto_feature → muto_ui → app_ui`, and
that is enforced by each package's pubspec rather than by convention.

`app_ui` is vendored from the Events project so both products look and behave
alike. `muto_ui` holds what only a marketplace needs. Every widget in both
takes text that is already translated and already formatted: deciding what
something means belongs to the feature, deciding how it looks belongs to the
kit.

## Layers

`muto_feature/lib/src` is split four ways, and a test in `test/boundaries`
fails the build if the split is crossed.

| Layer | Holds | May not |
|---|---|---|
| `domain/` | Entities, value objects, the status machine, validation, repository interfaces | Import Flutter, http or storage |
| `application/` | Controllers, cache, account isolation | Depend on a concrete repository |
| `data/` | Repository implementations, sample data, local storage | — |
| `presentation/` | Screens, widgets, formatting | Import `data/` |

Wiring happens once, in `MutoScope`. It is the only place that knows both a
controller and an implementation.

## Host contract

The feature is built to be mounted inside another application.

```dart
MutoFeature(
  session: MutoHostSession(accessToken: token),
  dependencies: dependencies,
  config: const MutoConfig.sample(),
  onSessionExpired: host.refreshSession,
)
```

The host owns authentication, theme, locale and lifecycle. The feature owns its
navigation, its strings and its state, and never creates a `MaterialApp`.

The token is exchanged for an identity and never stored. The feature does not
inspect it, does not refresh it, and does not decide who the student is or
whether they are verified — all of that comes back from whatever resolved the
session. There is no role in this contract: a listing has an owner, and that is
the only distinction the marketplace makes.

When a call comes back unauthorized, the feature clears its state and calls
`onSessionExpired` exactly once per token, however many calls failed. Being
offline is a different outcome and never asks the host to re-authenticate.

## State

Flutter's own primitives only: `ChangeNotifier`, `ValueListenableBuilder`,
`setState`. No state-management package.

Controllers are owned by `MutoScope`, an `InheritedWidget` created per mount,
not by globals. A new token rebuilds the scope, so state from one session
cannot structurally survive into the next.

```text
MutoScope
├── SessionController        identity, expiry, one report per token
├── ListingFeedController    browse, favorites and my listings, one each
├── FavoritesController      the saved set, optimistic and reversible
├── ListingEditorController  draft, validation, photos, idempotency
└── ListingCache             the one copy of every listing
```

Browse, favorites and my listings are the same paginated list with different
loaders, so they share one controller class and one view.

## Account isolation

Three mechanisms, because one is not enough:

1. **Scope lifetime.** A new session builds a new scope; the old controllers
   are disposed.
2. **Generation counter.** A load captures it at the start and refuses to write
   its result if it moved. This is what discards a request that was already in
   flight when the account changed.
3. **Namespaced storage.** Persisted keys carry the schema version and the
   account: `muto_v1_{userId}_{name}`. A layout change discards old entries
   instead of misreading them.

Anything belonging to one student — favorites, drafts, their own listings — is
scoped and never survives a switch.

## Caching

One listing exists once, in `ListingCache`, and every feed refers to it by id,
so a status change updates the feed, the detail screen and the saved list at
the same moment.

Feeds are stale-while-revalidate: a fresh feed short-circuits, so a screen can
ask to load on every build. Past ten minutes, data that cannot be refreshed
says so rather than pretending to be current. A failed refresh keeps what is on
screen instead of blanking it.

Pagination uses an opaque cursor. The client never builds one, stops if the
same cursor comes back twice, and collapses an id that appears on two pages.

## Images

`ImageLocator` resolves a reference to one of a closed set of places — bundled,
remote, or in memory for a photo staged but not yet saved — or to nothing at
all. Returning nothing is what lets a widget show a real failure state instead
of a broken box.

Uploads are two-phase: a photo is staged and gets a reference, and the
reference is redeemed when the listing is saved. One that is never redeemed
expires rather than leaving an orphan.

The client checks size, dimensions and format before anything leaves the
device, reading the leading bytes rather than trusting a file name. These
checks are a courtesy and a first line of defence, never a control: whatever
accepts an upload has to make the same decisions again and re-encode the
result.

## Localization

ARB files and Flutter's own generator, because Russian needs four plural
categories and a map of strings cannot express that.

The feature installs its own delegate over whatever the host provides, so it
works inside a host that has never heard of it. The language comes from the
host's ambient locale; anything outside English, Kazakh and Russian falls back
to English.

No user-facing text exists outside the ARB files.

## Security boundaries

| Boundary | Enforced by | What the client does |
|---|---|---|
| Identity | The session response | Never persists the token, never infers identity |
| Verification | The server | Gates publishing and contact, never claims it |
| Ownership | The authority that accepts writes | Hides affordances; handles refusal gracefully |
| Status changes | The same authority | Offers only what the transition map allows |
| Photo content | Re-encoded on acceptance | Pre-checks by magic bytes, size, dimensions |
| Outbound links | The client | Builds every URL itself from validated fields |
| Text rendering | The client | Plain text only; strips bidi overrides and controls |

Two are worth stating plainly.

**No URL is ever accepted from data.** Contact details arrive as structured
fields — a Telegram username, an email, a phone number. Each is validated for
shape, and the client then constructs `https://t.me/…`, `mailto:` or `tel:`
itself. A field that fails validation produces no channel at all, so there is
nothing for a crafted listing to point at. Nothing opens without a dialog
naming the destination.

**Listing text is never rich.** It renders as plain text with no
linkification, after control characters and bidirectional overrides are
stripped — those let a crafted title display as something other than what it
contains.

Development access is double-gated: `kDebugMode && ENABLE_DEV_ACCESS`. A
release build cannot switch it on however the define is set, and a test proves
it. Because the app runs on sample data, no credential exists in this
repository to leak.

## Testing

`flutter_test` only, with hand-written fakes. Roughly 250 tests.

| Suite | Covers |
|---|---|
| `domain/` | Every ordered status pair, money and kind invariants, text and contact validation |
| `data/` | Tolerant decoding, ownership, versions, idempotency, pagination, image rules |
| `application/` | Account switching mid-flight, expiry, freshness, conflicts, optimistic writes |
| `presentation/` | Every screen in three languages, both themes, and screen-reader labels |
| `boundaries/` | The layer rules above |

Tests that matter most are the ones that assert a thing is *absent*: contact
details missing from a feed response, sold listings missing from browse, a
reserve action missing from a sold listing.

Not done, and not claimed: golden tests, and any test against a real server.

## Verification and CI

`./scripts/verify.sh` runs exactly what CI runs — formatting, analysis with
`--fatal-infos`, tests, and a line-coverage floor of 70% measured over
hand-written code.

CI has three jobs: quality, a release build proving development access cannot
be enabled in one, and a secret scan over full history. There is no deployment
job, because there is nothing to deploy.

## Where a backend attaches

Five interfaces in `domain/repositories/`: listings, favorites, images,
sessions, and drafts. The sample implementations satisfy them today; an HTTP
implementation would satisfy the same ones, and nothing above `data/` would
change.

`MutoConfig.backend` records which was chosen, and the sample-data banner is
derived from it rather than set by hand, so it cannot drift from the truth.
