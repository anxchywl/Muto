# Muto

Muto is a marketplace for verified Nazarbayev University students. Someone
lists a thing they no longer need; someone else finds it and gets in touch. The
exchange itself happens between the two people, off the app.

It is built as an **embeddable Flutter feature**, developed against a
standalone host in this repository and intended to be mounted inside the Jas
Wallet application later.

> **Sample mode remains the default.** The Flutter feature also has an explicit
> remote mode backed by the service in this repository. Production host
> authentication is still deliberately unconfigured. Private S3-compatible
> image storage and deployment automation are implemented, but need external
> credentials and a hostname before they can be exercised.

## What a student can do

- Browse listings, search them with suggestions and recent searches, and narrow
  them by category, type, condition and order
- Open a listing and see its photos, price, condition and description
- Open a seller and see what else they have listed
- Save listings and come back to them
- Contact a seller through Telegram, email or phone, outside the app
- Publish something for sale, for swap, or to give away
- Manage their own listings: edit, reserve, mark sold, hide, relist, remove
- Report someone else's listing

Deliberately absent, as decisions rather than gaps: payments, checkout,
delivery, cart, ratings, reviews, advertising, promoted listings, in-app
messaging, and any moderation verdict or appeal. Operators have a private,
read-only report intake; it does not decide outcomes. The rules behind all of
it are in [docs/PRODUCT.md](docs/PRODUCT.md).

## System map

```text
muto_app  →  muto_feature  →  muto_ui  →  app_ui
  host        the feature      widgets     tokens
```

| Package | Holds |
|---|---|
| `app_ui` | Design tokens and generic widgets, vendored from the Events project |
| `muto_ui` | Marketplace widgets built from those tokens, presentation only |
| `muto_feature` | The feature itself: domain, application, data, presentation |
| `muto_app` | Standalone development host: `MaterialApp`, theme, locale, lifecycle |

Inside `muto_feature` the layers are `domain / application / data /
presentation`, and a test fails the build if one imports another it should not.
The reasoning, the host contract and the security boundaries are in
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Local development

Requires Flutter 3.38.5 / Dart 3.10.4, Python 3.12, `uv`, Docker, and Android
or iOS tooling. No Flutter web or desktop target is supported.

```bash
cp .env.example .env
cd muto_app && flutter run --dart-define-from-file=../.env
```

```bash
./scripts/verify.sh
```

To run the backend and PostgreSQL:

```bash
docker compose up --build
curl http://127.0.0.1:8000/health/ready
```

To run the standalone Flutter host against that service, change
`MUTO_BACKEND=remote` in `.env`, keep the synthetic local token from the
example, and run the same `flutter run` command. Remote mode never falls back
to sample data if configuration or a request fails.

The verification script is the local quality gate for backend and Flutter:
formatting, linting, type analysis, security checks, tests, and coverage.
Toolchain, migrations, builds and CI are in
[docs/INFRASTRUCTURE.md](docs/INFRASTRUCTURE.md).

## Environment variables

Flutter uses five compile-time values:

| Variable | Default | Meaning |
|---|---|---|
| `ENABLE_DEV_ACCESS` | `true` | Lets the standalone host open the marketplace with a placeholder session |
| `MUTO_BACKEND` | `sample` | Selects `sample` or `remote` dependencies explicitly |
| `MUTO_API_BASE_URL` | local API | Required by the host in remote mode |
| `MUTO_ACCESS_TOKEN` | synthetic local token | Development student token, passed unchanged to the session repository |
| `MUTO_ADMIN_ACCESS_TOKEN` | synthetic local token | Distinct development operator token |

It cannot switch anything on in a release build: the gate is
`kDebugMode && ENABLE_DEV_ACCESS`, the host refuses to open without it, and a
test asserts that. See [.env.example](.env.example).

In a debug build, five taps on the Browse tab switch to the server-resolved
operator account and five more switch back. The switch recreates the feature
scope, so caches and authenticated image state cannot cross accounts. It is
unavailable in release builds and neither token is an authorization claim by
itself: the backend resolves the account and role.

The same example file documents backend runtime settings. Local authentication
accepts only the explicitly configured synthetic development token and the
backend refuses to start with that adapter in production. The future host token
format is not yet defined, so production authentication deliberately rejects
every token.

## Limits worth knowing

- **Two Flutter modes.** Sample mode simulates the complete product in memory.
  Remote mode maps the same repository interfaces to the versioned API with
  timeouts, structured failure mapping, idempotency and expected versions.
- **Backend scope.** Identity, listings, favorites, seller profiles, reports,
  operator report intake and staged images are implemented. Development uses
  private local storage; deployment uses a private S3-compatible bucket and
  controlled authenticated delivery through the API.
- **Security.** The backend enforces identity and marketplace rules. The
  Flutter client derives no identity fields, does not retry automatically, and
  isolates session state and authenticated image caches across account changes.
  Boundaries and how to report a vulnerability are in
  [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md#security-boundaries).
- **Deployment.** Production Compose, TLS routing, preflight checks, verified
  backups, retention cleanup, readiness monitoring, application rollback and a
  main-branch deployment job are present. They remain unverified remotely until
  the server, DNS, object storage and GitHub environment secrets are supplied.
  Flutter artifacts are still unsigned and undistributed.
- **Jas Wallet.** Not integrated. Its token contract is still unresolved, and
  the host contract has never been exercised against a real host.

## Licence

There is no licence file, so default copyright applies: all rights reserved.
The source is readable; nobody is granted the right to use, copy or
redistribute it.
