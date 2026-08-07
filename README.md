# Muto

Muto is a marketplace for verified Nazarbayev University students. Someone
lists a thing they no longer need; someone else finds it and gets in touch. The
exchange itself happens between the two people, off the app.

It is built as an **embeddable Flutter feature**, developed against a
standalone host in this repository and intended to be mounted inside the Jas
Wallet application later.

> **There is no backend.** Everything runs on bundled sample data through mock
> repositories, and the app shows a permanent `Sample data` banner while it
> does. Nothing here has ever run against a server.

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
messaging, and any moderation queue, verdict or appeal. The rules behind all of
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

Requires Flutter 3.38.5 / Dart 3.10.4, and Android or iOS tooling. No web, no
desktop.

```bash
cp .env.example .env
cd muto_app && flutter run --dart-define-from-file=../.env
```

```bash
./scripts/verify.sh
```

That second command is the whole gate — formatting, analysis with
`--fatal-infos`, every test, and a line-coverage floor of 70% — and it is
exactly what CI runs. Toolchain, builds, CI and everything else operational is
in [docs/INFRASTRUCTURE.md](docs/INFRASTRUCTURE.md).

## Environment variables

One, and it only ever weakens a debug build:

| Variable | Default | Meaning |
|---|---|---|
| `ENABLE_DEV_ACCESS` | `true` | Lets the standalone host open the marketplace with a placeholder session |

It is a Dart define, never read from the process environment at runtime. It
cannot switch anything on in a release build: the gate is
`kDebugMode && ENABLE_DEV_ACCESS`, the host refuses to open without it, and a
test asserts that. See [.env.example](.env.example).

No credential, token or key exists anywhere in this repository, and none is
needed to run it.

## Limits worth knowing

- **Mocked.** Listing reads and writes, status changes, seller profiles, search
  suggestions, reports, pagination, version conflicts, idempotent publishes and
  photo rules are all simulated in memory. Full list in
  [docs/PRODUCT.md](docs/PRODUCT.md).
- **Deferred.** No network call, no account system, no durability beyond the
  unfinished draft and recent searches, and no backend behind the repository
  interfaces.
- **Security.** Every rule the mocks enforce is enforced on the client, which
  makes it a specification and not a control until a server enforces it again.
  Boundaries and how to report a vulnerability are in
  [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md#security-boundaries).
- **Deployment.** There is none. CI builds a debug and a release artifact to
  prove they compile and that development access cannot be enabled in a release
  build; neither is signed, uploaded or distributed, and there is no
  environment to roll back to.
- **Jas Wallet.** Not integrated. The host contract exists and has never been
  exercised against a real host.

## Licence

There is no licence file, so default copyright applies: all rights reserved.
The source is readable; nobody is granted the right to use, copy or
redistribute it.
