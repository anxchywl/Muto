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
| [INFRASTRUCTURE.md](./INFRASTRUCTURE.md) | Toolchain, running, checks, builds, environments, CI, and deployment operations |
| [API.md](./API.md) | Implemented endpoints and the mapping from Flutter repositories to the backend API |
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
  dependencies: createRemoteDependencies(baseUri: apiBaseUri),
  config: MutoConfig.remote(baseUri: apiBaseUri),
  onSessionExpired: authController.refresh,
)
```

Remote configuration requires HTTPS by default. The standalone debug host
opts into insecure HTTP only for local development.

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
2. **Dependencies.** A `MutoDependencies` assembled by
   `createSampleDependencies()` or `createRemoteDependencies()`.
3. **A config.** `MutoBackend` records which data source the build was
   assembled with, and must match the dependency set passed beside it.
4. **`onSessionExpired`.** Called once per token when a call comes back
   unauthorized, however many calls failed. The host refreshes and passes a new
   token, which rebuilds the scope so nothing from the previous session
   survives. Being offline is a different outcome and never asks the host to
   re-authenticate.

Before a real host can mount this: marketplace endpoints behind every repository interface,
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

## Where the backend attaches

Nine interfaces in `domain/repositories/`: listings, sellers, favorites,
reports, report operations, images, sessions, and two local stores — drafts
and search history.
Sample and HTTP implementations satisfy them. The independent FastAPI service
resolves external identities to stable internal users and implements the
listing, favorites, seller, report and image contracts with PostgreSQL persistence.
This includes server-authoritative lifecycle rules, keyset pagination,
idempotent writes, optimistic concurrency, report and upload rate limiting,
operator-only report intake and private staged image storage.

Two of them are local by nature. Drafts and recent searches are the student's
own text on their own device, and neither would move to a server if one
appeared.

`MutoConfig.backend` records which was chosen, at the one place the feature is
constructed rather than inferred deeper in the tree.

The Flutter HTTP implementation lives in `data/remote`, satisfies the same
interfaces, and changes nothing above it. The wire mapping is in
[API.md](./API.md).

## Security boundaries

The backend now re-enforces listing ownership, verification, expected versions,
status transitions, visibility, favorites, seller privacy, idempotent writes,
self-report restrictions, report rate limiting, image ownership, image content
validation and reference redemption without trusting identity or metadata from
the client.

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

Five taps on Browse switch between separate user and operator development
sessions; five more switch back. The callback exists only behind the debug
gate, recreates the account scope, and never supplies an `is_admin` claim.
Remote mode uses two distinct configured tokens and the backend resolves the
operator role. Release builds cannot open this path.

The sample placeholder tokens are not credentials. Remote development tokens
must be random secrets supplied outside source control because the development
backend treats them as bearer credentials.

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

The remote client has a ten-second request timeout and no automatic retry.
Every mutation carrying side-effect risk supplies an idempotency key. A late
unauthorized response is applied only if it belongs to the current token, and
authenticated image cache keys carry a non-secret session namespace so private
bytes cannot be reused after an account switch. Superseded controller results
are discarded, but the current `package:http` boundary does not actively abort
an already-sent request. The backend's host
authentication resolver intentionally
rejects every production token because the issuer, audience, signature and
verification claims are undecided. The S3 adapter, release scripts and CI
deployment job are implemented but remain externally unverified until storage,
DNS, server access and GitHub environment secrets exist. Dependencies are
scanned by advisory in CI.

### Threat model

| Threat | Control | Remaining boundary |
|---|---|---|
| Forged ownership or verification | Request bodies contain neither; both come from the authenticated principal | Production host token validation is not yet implemented |
| IDOR and identifier enumeration | UUID resources still pass through owner and visibility checks; hidden, removed and suspended-seller content has deliberate responses | General browse throttling remains an edge-proxy responsibility |
| Replayed or duplicate mutations | User-and-operation-scoped idempotency records, request fingerprints and PostgreSQL advisory locks | Expired records are removed by scheduled maintenance |
| Stale edits | Every listing write requires an expected version and conflicting writes return `409` | The client must reload before retrying a conflict |
| Malicious or oversized uploads | Bounded streaming reads, signature decoding, pixel limits, animation rejection, metadata-stripping re-encoding, per-account slot limits and server-generated S3 keys | Bucket policy and credentials must be provisioned externally |
| Hidden or deleted content leakage | Shared listing visibility rules apply to feeds, sellers, favorites, detail and controlled image reads | Cleanup is hourly; bucket lifecycle is the fallback for staged objects |
| Account switching and expired tokens | Scope recreation, generation checks, stale-`401` suppression and per-session private image cache keys | The future host owns token refresh and replacement |
| Malformed cursors | Signed opaque cursors are schema-checked and bound to account, filters and ordering | Cursor-secret rotation needs a deployment policy |
| Report rate-limit bypass | Stable internal-account scope and serialized PostgreSQL checks | No general-purpose distributed limiter is added without demonstrated need |
| Forged operator state | Operator access comes from the token resolver and every operations endpoint rechecks it | Final host role mapping awaits Jas Wallet auth design |
| Log or response leakage | API access logs are off, proxy logs omit request headers, errors are structured, and responses omit stack traces, SQL, tokens and private paths | Alert delivery needs an external webhook |

To report a vulnerability, open a private security advisory through the
repository's Security tab rather than a public issue.

## Testing strategy

Flutter uses `flutter_test` with hand-written fakes. Backend tests use pytest;
database integration tests run against PostgreSQL rather than a mock.

| Suite | Proves |
|---|---|
| `domain/` | Every ordered status pair, money and kind invariants, text, contact, search and report validation |
| `data/` | Wire decoding, endpoint mapping, failure mapping, account isolation, ownership, versions, idempotency, pagination, image rules, rate limiting |
| `application/` | Account switching mid-flight, expiry, freshness, conflicts, debouncing, optimistic writes |
| `presentation/` | Every screen in three languages, both themes, and screen-reader labels |
| `boundaries/` | The layer rules above, by scanning imports |

The tests that matter most assert that something is *absent*: contact details
missing from a feed response, sold listings missing from browse, a reserve
action missing from a sold listing, a report action missing from your own.

Not done, and not claimed: golden tests, integration tests on a Flutter device,
or an automated end-to-end Flutter run against a live backend.
