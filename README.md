# Muto

Muto is a small marketplace for verified Nazarbayev University students. People
list things they no longer need, and interested students contact the owner
outside the app.

The marketplace is an embeddable Flutter feature. This repository also contains
a standalone host for development.

> Remote mode is the default. The current development deployment uses
> `https://muto.anxchywl.dev` with temporary development authentication and
> synthetic marketplace records. Production authentication and signing are not
> included.

## Features

- Browse listings, search them with suggestions and recent searches, and narrow
  them by category, type, condition and order
- Open a listing and see its photos, price, condition and description
- Open a seller and see what else they have listed
- Save listings and come back to them
- Contact a seller through Telegram, email or phone, outside the app
- Publish something for sale, for swap, or to give away
- Manage their own listings: edit, reserve, mark sold, hide, relist, remove
- Report someone else's listing

Payments, checkout, delivery, ratings, reviews, advertising, promoted listings,
and in-app messaging are not part of the project. Reports have a private,
read-only operator intake; the app does not make moderation decisions. See
[docs/PRODUCT.md](docs/PRODUCT.md) for the complete product rules.

## Project structure

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

Inside `muto_feature`, the layers are `domain`, `application`, `data`, and
`presentation`. The dependency rules are enforced by tests. See
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Development

You need Flutter 3.38.5 (Dart 3.10.4), Python 3.12, `uv`, Docker, and Android
or iOS tooling. Web and desktop are not supported.

```bash
cp .env.example .env
cd muto_app && flutter run --dart-define-from-file=../.env
```

```bash
./scripts/verify.sh
```

To run the backend and PostgreSQL:

```bash
docker compose -f docker/docker-compose.yml up --build
curl http://127.0.0.1:8000/health/ready
```

The example configuration already selects remote mode. Populate the local
PostgreSQL database with the idempotent seed command in
[docs/INFRASTRUCTURE.md](docs/INFRASTRUCTURE.md), then run the same
`flutter run` command. The app never falls back to bundled records if
configuration or a request fails.

Run the complete local quality gate with `./scripts/verify.sh`. It covers
formatting, linting, type analysis, security checks, tests, and coverage.
More detail is in [docs/INFRASTRUCTURE.md](docs/INFRASTRUCTURE.md).

## Configuration

Flutter uses five compile-time values:

| Variable | Default | Meaning |
|---|---|---|
| `ENABLE_DEV_ACCESS` | `true` | Lets the standalone host open the marketplace with a placeholder session |
| `MUTO_BACKEND` | `remote` | Selects `remote` dependencies; `sample` remains available for tests |
| `MUTO_API_BASE_URL` | local API | Required by the host in remote mode |
| `MUTO_ACCESS_TOKEN` | synthetic local token | Development student token, passed unchanged to the session repository |
| `MUTO_ADMIN_ACCESS_TOKEN` | synthetic local token | Distinct development operator token |

The standalone host refuses to open in release mode unless it is integrated
with a real host. See [.env.example](.env.example).

In a debug build, five taps on the Browse tab switch to the server-resolved
operator account and five more switch back. The switch recreates the feature
scope, so caches and authenticated image state cannot cross accounts. It is
unavailable in release builds and neither token is an authorization claim by
itself: the backend resolves the account and role.

The same example file documents backend runtime settings. Local authentication
accepts only the explicitly configured synthetic development tokens. The live
development deployment uses the same adapter temporarily; it must be replaced
with the host authentication adapter before production use.

## Status and limitations

- The standalone host uses the FastAPI service and PostgreSQL by default.
- In-memory sample repositories remain only as test fixtures; they are not the
  host's normal data source.
- The live development backend currently contains synthetic listings and uses
  temporary development authentication.
- The current downloadable artifact is the prerelease
  [v0.1.2-dev APK](https://github.com/anxchywl/Muto/releases/tag/v0.1.2-dev).
- Production host authentication, real signing, and app-store distribution are
  not finished.

## Documentation

- [Product rules](docs/PRODUCT.md)
- [Architecture and security boundaries](docs/ARCHITECTURE.md)
- [API contract](docs/API.md)
- [Infrastructure and deployment](docs/INFRASTRUCTURE.md)

## License

Muto is licensed under the [MIT License](LICENSE).
