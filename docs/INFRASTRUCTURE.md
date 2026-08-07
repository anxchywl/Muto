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
| Python | 3, used by the coverage script |

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

The app opens on sample data, in the device's language if that is English,
Kazakh or Russian, and follows the system theme.

## Checks

```bash
./scripts/verify.sh
```

That is the whole gate, and it is what CI runs: formatting, analysis with
`--fatal-infos`, every test in every package, and a coverage floor of 70%
measured over hand-written code. Run it before pushing.

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

The release build is a check rather than a deliverable. It is unsigned, it is
not distributed, and its point is to prove the app compiles in release and that
the standalone host refuses to open without development access.

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

One variable, documented in [../.env.example](../.env.example) and in the
README. `.env` is ignored by git and must never be committed.

Flutter reads defines at compile time. There is no runtime environment
lookup anywhere in this repository, and no configuration file is read from
disk at startup.

## Continuous integration

One workflow, [`../.github/workflows/ci.yml`](../.github/workflows/ci.yml), on
pushes to `main` and on pull requests. It runs the same commands as above, so a
green `verify.sh` locally means a green `quality` job. It reads the repository
and nothing more, cancels superseded runs on a branch, and caches the Flutter
SDK, the pub cache and Gradle.

| Job | Fails when |
|---|---|
| `quality` | Anything is unformatted, any analyzer note appears, a test fails, or coverage drops below the floor |
| `debug-build` | The app does not compile for a device |
| `release-guard` | The release build fails, or development access could be enabled in one |
| `secrets` | `gitleaks` finds a credential pattern anywhere in the history |
| `dependencies` | `osv-scanner` finds a known advisory in the committed lockfile |

No job needs a secret, which is what makes running on pull requests from forks
safe. Any job that later needs one must not run on untrusted pull requests.

**The workflow has never executed** — this repository has no remote, so there
is no run to point at. Every job has been reproduced locally, but treat CI as
unproven until a run goes green.

### What is deliberately absent

There is no deployment, release, Docker, database or backend job, because none
of those things exist: no server, no store listing, no signing key, nothing
versioned or distributed from here. The release build is a compile check, not
an artifact anyone installs.

If a backend or a distribution channel is added, deployment belongs in a
separate workflow — gated on a protected environment with explicit approval, an
immutable release identifier, a health check, a smoke test and a written
rollback. None of that exists, and nothing here should be read as if it did.
