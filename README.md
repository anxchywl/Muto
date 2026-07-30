# Muto

A marketplace for verified Nazarbayev University students. Buy, sell, exchange,
or give away things on campus, contact the seller directly, and manage your own
listings.

Proprietary. All rights reserved. Not open source.

## Current state

There is **no backend**. The app runs entirely on sample data through mock
repositories, and every screen shows a `Sample data` indicator while it does.
Repository interfaces and the host session contract are the seams a real
backend will attach to later. Nothing here has run against a server.

What the product does and does not do is in [docs/PRODUCT.md](docs/PRODUCT.md).
How it is put together is in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Packages

```text
app_ui/        shared presentation kit (tokens, buttons, cards, sheets, theme)
muto_ui/       marketplace presentation built on those tokens
muto_feature/  the embeddable feature — domain, application, data, presentation
muto_app/      standalone Flutter host used for development
```

`muto_feature` is designed to be mounted inside a host application. `muto_app`
exists so it can be built and used on its own.

## Requirements

- Flutter 3.38.5, Dart 3.10.4
- Android or iOS target. No web, no desktop.

## Running

```bash
cd muto_app && flutter run
```

## Verifying

```bash
./scripts/verify.sh
```

Runs formatting, analysis, and tests across every package — the same checks CI
runs.
