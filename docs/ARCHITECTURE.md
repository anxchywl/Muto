# Muto Architecture

How Muto is put together, why it is put together that way, and what the client
can and cannot be trusted to enforce.

## Where everything is written down

Each document owns its subject once. Nothing is repeated between them, so a
fact that changes has exactly one place to change.

| File | Owns |
|---|---|
| [../README.md](../README.md) | Purpose, scope summary, setup, tests, env vars, and the limits worth knowing before reading further |
| [PRODUCT.md](./PRODUCT.md) | Product behaviour and rules: lifecycle, visibility, contact, reporting, what is simulated and what is deferred |
| This file | Package split, layers, host contract, state, account isolation, caching, images, localization, security boundaries, test strategy |
| [INFRASTRUCTURE.md](./INFRASTRUCTURE.md) | Toolchain, running, checks, builds, environment, CI, and what deployment does not exist |
| [../AGENTS.md](../AGENTS.md) | Coding rules: layers, style, comments, tests, commits |

## Why four packages

The README lists them. What matters here is why the split exists at all.

The one-way chain `muto_app → muto_feature → muto_ui → app_ui` is enforced by
each package's pubspec rather than by convention: `muto_ui` cannot reach the
feature because it does not depend on it, and there is no arrangement of
imports that would let it.

`app_ui` is vendored from the Events project so both products look and behave
alike, which is also why marketplace concepts never go into it. Every widget in
both kits takes text that is already translated and already formatted: deciding
what something means belongs to the feature, deciding how it looks belongs to
the kit.

`muto_app` is scaffolding. It exists so the feature can be run without a host
and is not part of what ships — a release build of it refuses to open at all.

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

## Mounting inside a host

The feature is built to be mounted inside another application — Jas Wallet is
the intended one.

```dart
MutoFeature(
  session: MutoHostSession(accessToken: token),
  dependencies: dependencies,
  config: const MutoConfig(backend: MutoBackend.remote),
  onSessionExpired: authController.refresh,
)
```

| Concern | Owner |
|---|---|
| Authentication, token issue and refresh | Host |
| Who the student is, and whether they are verified | Host, or whatever resolves its session |
| Theme, locale, lifecycle, top-level navigation | Host |
| Which data source the feature runs on | Host, by what it passes in |
| Marketplace navigation, screens and state | Feature |
| Marketplace strings, in three languages | Feature |

The feature never creates a `MaterialApp`, never reads a locale of its own,
never persists a token, and never asks anyone to sign in. Mount it anywhere —
a tab, a route, a nested navigator — and it keeps its own stack without
fighting the host's.

Four things the host supplies:

1. **A token.** Any non-empty string the session repository can exchange for an
   identity. The feature does not parse it, does not refresh it, and does not
   decide whether the student is verified — all of that comes back from
   whatever resolved the session. There is no role in this contract: a listing
   has an owner, and that is the only distinction the marketplace makes.
2. **Dependencies.** A `MutoDependencies` with a real implementation of every
   repository interface. Until a backend exists, `createSampleDependencies()`
   is the only implementation there is.
3. **A config.** `MutoBackend.remote` turns off the sample-data banner, so it
   must not be set while sample repositories are wired.
4. **`onSessionExpired`.** Called once per token when a call comes back
   unauthorized, however many calls failed. The host refreshes and passes a new
   token, which rebuilds the scope so nothing from the previous session
   survives. Being offline is a different outcome and never asks the host to
   re-authenticate.

Before a real host can mount this: a backend behind every repository interface,
with the server enforcing every rule the mocks enforce today
(see below); a decision on how a wallet session becomes
a Muto identity and where verification is asserted; image hosting that accepts,
re-encodes and serves photos without exposing a private reference; and theme
reconciliation — Muto is built on `app_ui` tokens vendored from the Events
project, so a host using a different kit means either adopting these tokens or
retargeting `muto_ui`. That last one is the largest unknown in the integration.

Still open: whether the wallet gives Muto a tab or a route, which decides
whether the feature keeps its own bottom bar; where reports go; and whether
analytics are expected, since the feature emits none.

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
├── MutoSearchController     recent terms and suggestions, per account
├── ListingEditorController  draft, validation, photos, idempotency
└── ListingCache             the one copy of every listing
```

Browse, favorites and my listings are the same paginated list with different
loaders, so they share one controller class and one view. A seller's page is
the same list again, but it belongs to one screen rather than to the mounting,
so the screen asks the scope for its own feed and disposes it.

Two controllers are owned by a screen rather than by the scope, because their
lifetime is a screen's: the editor, and the report sheet. Both mint their
idempotency token when they open and reuse it for every retry.

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

Anything belonging to one student — favorites, drafts, recent searches, their
own listings — is scoped and never survives a switch.

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

## Where a backend attaches

Seven interfaces in `domain/repositories/`: listings, sellers, favorites,
reports, images, sessions, and two local stores — drafts and search history.
The sample implementations satisfy them today; an HTTP implementation would
satisfy the same ones, and nothing above `data/` would change.

Two of them are local by nature. Drafts and recent searches are the student's
own text on their own device, and neither would move to a server if one
appeared.

`MutoConfig.backend` records which was chosen, and the sample-data banner is
derived from it rather than set by hand, so it cannot drift from the truth.

Two of them are local by nature: drafts and recent searches are the student's
own text on their own device, and neither would move to a server if one
appeared.

An HTTP implementation would live in `data/`, satisfy the same interfaces, and
change nothing above it. What such a client must not trust is set out under
[security boundaries](#security-boundaries).

## Security boundaries

A client with no server behind it. Every rule the mock repositories enforce —
ownership on every write, expected version on every update, allowed status
transitions, contact on a detail read only, photo type and size and dimensions,
idempotent publishes, a rate limit on reports — is enforced **on the client**.

None of that is a security control. It is a specification, written as
executable code, so the screens are built against the rules from the start. A
server has to make every one of those decisions again and trust nothing the
client sends.

| Boundary | Must be enforced by | What the client does |
|---|---|---|
| Identity | The session response | Never persists the token, never infers identity |
| Verification | The server | Gates publishing and contact, never claims it |
| Ownership | The authority that accepts writes | Hides affordances, handles refusal gracefully |
| Status changes | The same authority | Offers only what the transition map allows |
| Photo content | Re-encoded on acceptance | Pre-checks magic bytes, size and dimensions |
| Rate limiting | The server | Refuses a second submit while one is in flight |
| Outbound links | The client | Builds every URL itself from validated fields |
| Text rendering | The client | Plain text only, bidi overrides and controls stripped |

Two client-side decisions are load-bearing on their own, because no server can
make them for us.

**No URL is ever accepted from data.** Contact details arrive as structured
fields — a Telegram username, an email address, a phone number. Each is
validated for shape and the client constructs `https://t.me/…`, `mailto:` or
`tel:` itself. A field that fails validation produces no channel at all, so a
crafted listing has nothing to point at. Nothing opens without a dialog naming
the destination first.

**Listing text is never rich.** It renders as plain text with no linkification,
after control characters and bidirectional overrides are stripped — those let a
crafted title display as something other than what it contains.

### Development access

The standalone host opens the marketplace with a placeholder session, gated on
`kDebugMode && ENABLE_DEV_ACCESS`, both halves required. A release build cannot
switch it on however the define is set: the host shows a refusal screen
instead, a unit test asserts the logic, and CI builds a release artifact with
the define off.

The placeholder token is not a credential. It is a short constant string the
sample repositories accept because they accept anything non-empty, and it
authorises nothing.

### What is in the repository, and on the device

No secret, token, password, keystore or service account file — CI scans the
full history on every run. No real student data: sample listings are invented,
with contact details on reserved example domains and unroutable numbers. No
photographs: sample images are flat generated shapes.

Two things are written to ordinary preference storage, namespaced per account
as `muto_v1_{userId}_{name}`: the unfinished draft, and recent searches. Both
are the student's own text, nothing is encrypted because nothing sensitive is
stored, and neither survives an account switch. No token is ever written to
disk.

### Known limitations

Every rule above is client-side only today. There is no certificate pinning,
because there is no network layer. There is no threat model for a backend that
does not exist. Dependencies are scanned by advisory in CI; a transitive Dart
package with an open advisory can be reported but not fixed here.

To report a vulnerability, open a private security advisory through the
repository's Security tab rather than a public issue.

## Testing strategy

`flutter_test` only, with hand-written fakes and no mocking package.

| Suite | Proves |
|---|---|
| `domain/` | Every ordered status pair, money and kind invariants, text, contact, search and report validation |
| `data/` | Tolerant decoding, ownership, versions, idempotency, pagination, image rules, rate limiting |
| `application/` | Account switching mid-flight, expiry, freshness, conflicts, debouncing, optimistic writes |
| `presentation/` | Every screen in three languages, both themes, and screen-reader labels |
| `boundaries/` | The layer rules above, by scanning imports |

The tests that matter most assert that something is *absent*: contact details
missing from a feed response, sold listings missing from browse, a reserve
action missing from a sold listing, a report action missing from your own.

Not done, and not claimed: golden tests, integration tests on a device, and any
test against a real server.
