# Muto Infrastructure

Setting the repository up, running it, the checks that must pass, and what
happens automatically. Product rules are in [PRODUCT.md](./PRODUCT.md); the
structure it all rests on is in [ARCHITECTURE.md](./ARCHITECTURE.md); the code
conventions are in [../AGENTS.md](../AGENTS.md).

## Toolchain

| Tool | Version |
|---|---|
| Flutter | 3.38.5 stable |
| Dart | 3.10.4 (ships with that Flutter) |
| Java | 17, for Android builds |
| Python | 3.12, for the backend |
| uv | Python dependency and environment management |
| PostgreSQL | 16 |
| Docker | Local and deployment orchestration |

Targets are Android and iOS. Web and desktop are not supported and are not
tested.

## First run

```bash
cp .env.example .env
cd muto_app && flutter run --dart-define-from-file=../.env
```

`flutter run` resolves the three sibling packages through path dependencies, so
there is nothing to publish or link by hand. Dropping
`--dart-define-from-file` is fine — the defaults are the same as the example
file — but keeping it is the habit that matters once more defines exist.

The app opens against the configured backend, in the device's language if that
is English, Kazakh or Russian, and follows the system theme.

The backend runs separately:

```bash
docker compose -f docker/docker-compose.yml up --build
curl http://127.0.0.1:8000/health/live
curl http://127.0.0.1:8000/health/ready
```

Compose applies migrations before starting the API. PostgreSQL is bound to
`127.0.0.1:54321` and the API to `127.0.0.1:8000`. A private named volume holds
normalized development images; no host directory or public file server is
exposed.

Populate three idempotent synthetic listings after the service is ready:

```bash
docker compose -f docker/docker-compose.yml exec backend .venv/bin/python -m app.commands.seed
```

The command is blocked in production and contains no contact details,
credentials, photographs or real student records.

The example Flutter configuration already selects remote mode. Set
`MUTO_API_BASE_URL=http://127.0.0.1:8000`, `MUTO_ACCESS_TOKEN` to the same
synthetic value as `DEVELOPMENT_AUTH_TOKEN`, and `MUTO_ADMIN_ACCESS_TOKEN` to
the same value as `DEVELOPMENT_ADMIN_AUTH_TOKEN`, then restart `flutter run`. An
Android emulator reaches the host through `http://10.0.2.2:8000`; a physical
Android device needs a reachable development-machine address. Android permits
cleartext traffic only in debug builds. iOS needs a local HTTPS endpoint because
no broad App Transport Security exception is included. Production mode requires
HTTPS and a real host auth adapter.

## Checks

```bash
./scripts/verify.sh
```

That is the database-independent local gate: backend formatting, linting,
typing, Bandit and unit tests, followed by Flutter formatting, analysis, tests
and the existing 70% feature coverage floor. Run it before pushing.

Backend checks alone:

```bash
cd backend
uv sync --frozen --extra dev
uv run --frozen ruff format --check app migrations tests
uv run --frozen ruff check app migrations tests
uv run --frozen mypy app
uv run --frozen bandit -q -r app
uv run --frozen pytest tests/unit
```

Migration and PostgreSQL integration checks:

```bash
cd backend
uv run --frozen alembic -c alembic.ini upgrade head
uv run --frozen alembic -c alembic.ini check
TEST_DATABASE_URL="$DATABASE_URL" uv run --frozen pytest tests --cov=app
```

The complete backend suite uses PostgreSQL and enforces the 80% backend
coverage floor. Unit-only coverage is not used as a substitute for exercising
database behavior.

Individually, from inside a package directory:

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze --no-pub --fatal-infos
flutter test --no-pub
```

Coverage, which only `muto_feature` is measured on:

```bash
cd muto_feature && flutter test --coverage
./scripts/coverage_floor.sh muto_feature/coverage/lcov.info 70
```

Generated localizations are excluded from the floor: they come from the ARB
files, and testing them would measure the generator.

## Builds

```bash
cd muto_app
flutter build apk --debug
flutter build apk --release --dart-define=ENABLE_DEV_ACCESS=false
```

The local release build is unsigned and is only a compilation check. A tagged
development release explicitly enables the standalone placeholder session with
`ALLOW_STANDALONE_DEV_ACCESS=true`; it is not an app-store release. The
separate release workflow attaches its APK to a GitHub Release.

## Working on the feature

**Adding user-facing text.** Add the key to all three ARB files under
`muto_feature/lib/src/l10n/arb/`, English first, then run:

```bash
cd muto_feature && flutter gen-l10n
```

Generated output is not committed. A string that exists in only one language is
a build failure waiting to happen, and no literal user-facing text may appear
outside the ARB files.

**Adding a repository.** Define the interface in `domain/repositories/`,
implement it under `data/`, and wire it in `MutoScope`. Nothing above `data/`
may name an implementation, and a boundary test fails the build if it does.

**Regenerating sample images.**

```bash
./scripts/gen_sample_images.sh
```

They are flat generated shapes, never photographs, and never a real person's
belongings.

**Simulating failure.** `MockFaults` can force offline, an expired session, or
a version conflict on the next write. Latency is real by default so loading
states are visible; tests use `MockLatency.none()`.

## Environment variables

[../.env.example](../.env.example) documents Flutter's explicit backend, API
and token selection alongside backend runtime configuration. `.env` is ignored
and must never be committed. Missing remote API configuration fails startup;
remote requests never fall back to bundled sample data.

Production defaults are fail-closed: host authentication rejects tokens until
an adapter exists, API documentation is disabled, CORS has no allowed origin,
development authentication is rejected when `APP_ENV=production`, and the
local filesystem adapter is rejected in production. Production Compose also
requires explicit S3 credentials and an HTTPS endpoint.

Unredeemed uploads expire after 60 minutes by default. Local cleanup can be run
manually:

```bash
cd backend
uv run --frozen python -m app.commands.cleanup_images
uv run --frozen python -m app.commands.reconcile_storage
uv run --frozen python -m app.commands.cleanup_records
```

The first command processes a bounded batch with row locking, deletes private
bytes and marks the upload expired. Reconciliation deletes storage objects that
have had no database reference for 24 hours, covering partial write failures.
The final command removes expired idempotency records, expired upload metadata
after 30 days, and reports after 365 days by default. Production Compose runs
all three hourly. The bucket lifecycle independently
expires `staged/` objects after two days, covering a database/storage partial
failure. Redeemed images remain until a listing is removed or drops the image;
that release makes the object immediately eligible for cleanup.

## Continuous integration

The CI workflow, [`../.github/workflows/ci.yml`](../.github/workflows/ci.yml), runs
on pushes to `main` and on pull requests. It runs the same commands as above, so
a green `verify.sh` locally means a green `quality` job. It reads the repository
and nothing more, cancels superseded runs on a branch, and caches the Flutter
SDK, the pub cache and Gradle.

| Job | Fails when |
|---|---|
| `backend-quality` | Backend formatting, linting, typing, Bandit or unit tests fail |
| `backend-integration` | A migration, schema drift check, real PostgreSQL test or the 80% backend coverage floor fails |
| `quality` | Anything is unformatted, any analyzer note appears, a test fails, or coverage drops below the floor |
| `debug-build` | The app does not compile for a device |
| `release-guard` | The release build fails, or development access could be enabled in one |
| `secrets` | `gitleaks` finds a credential pattern anywhere in the history |
| `dependencies` | `osv-scanner` finds a known advisory in the committed lockfile |
| `deployment-validation` | Shell scripts, production Compose or production images are invalid |

Validation jobs need no secret, which keeps pull requests from forks safe. The
`deploy` job runs only for a tested default-branch push, uses the protected `temporary`
environment, and skips when its three SSH secrets are absent.

The CI workflow is the repository's required quality gate. Release builds are
separate: pushing a tag matching `v*.*.*` runs
[`../.github/workflows/release.yml`](../.github/workflows/release.yml) and
publishes an unsigned APK to a GitHub Release.

## Deployment

`docker/docker-compose.production.yml` runs PostgreSQL, the API, private S3-backed
maintenance, daily database backups, Caddy TLS routing and a readiness monitor.
Copy either `deploy/temporary.env.example` for the current debug-only remote
environment or `deploy/production.env.example` after real host authentication
exists. Store the result as `.env.production`, owned by `deploy` with mode 600.

Required external inputs are:

- a DNS name whose A/AAAA record reaches the server on ports 80 and 443
- a private S3-compatible media bucket and scoped object credentials
- a separate backup bucket, scoped credentials and an age recipient for
  encrypted offsite backups in production
- an optional alert webhook; without it failures remain visible only in logs
- `SSH_HOST`, `SSH_USER` and `SSH_PRIVATE_KEY` secrets in the GitHub
  `temporary` environment

Configure and verify the image bucket from the backup image:

```bash
docker compose --env-file .env.production -f docker/docker-compose.production.yml \
  run --rm -e IMAGE_LIFECYCLE_FILE=/usr/local/share/muto/image-lifecycle.json \
  backup /usr/local/bin/configure-storage.sh
```

The check fails if the bucket ACL grants public or broad authenticated-user
access, then installs the staged-object lifecycle. The application never gives
clients object credentials or direct object keys; controlled image delivery
continues through the authenticated API.

Deploy from the server repository with:

```bash
DEPLOY_REF=$(git rev-parse HEAD) deploy/deploy.sh
```

Preflight checks secrets and secure storage configuration. Deployment builds an
immutable commit-tagged backend image, starts PostgreSQL, creates and validates
a custom-format backup, runs the forward migration as a one-off job, starts the
new application, checks public readiness and verifies backup freshness. If the
application fails, it restores the previous image. Migrations must remain
backward-compatible because automatic database downgrade is intentionally not
attempted during rollback.

`deploy/restore.sh` verifies a selected dump, requires typing `restore`, takes a
fresh backup, restores in one transaction, reapplies migrations and restarts
the API. A restore test must be run in staging before treating backups as
operationally proven.

Reports are visible only to the server-resolved operator role, without reporter
identity. Operators review the intake at least daily. Prohibited or safety
reports are escalated immediately through the institution's approved security
channel; other reports are reviewed within two business days. Reports expire
after 365 days unless institutional policy requires a different configured
period. There is no verdict, appeal or automated enforcement workflow.

The manual `Live backend validation` workflow runs the synthetic authentication,
role isolation, private upload, redemption, controlled download and cleanup
journey on Android and iOS. It requires `MUTO_STAGING_API_URL`,
`MUTO_STAGING_USER_TOKEN` and `MUTO_STAGING_ADMIN_TOKEN` repository secrets.

Still deferred: host token validation, real signing and host distribution,
a final privacy review, a remotely observed green workflow, staging restore
evidence, and live-device poor-network testing. The repository contains the
procedures; it does not claim those external checks have happened.
