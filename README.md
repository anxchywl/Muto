# Muto

A marketplace for verified Nazarbayev University students. Buy, sell, exchange
or give away things on campus, contact the seller directly, and manage your own
listings.

Proprietary. All rights reserved. Not open source.

## Current state

There is **no backend**. The app runs entirely on sample data through mock
repositories, and shows a `Sample data` banner while it does. Nothing here has
run against a server.

What is simulated and what is not is set out in
[docs/PRODUCT.md](docs/PRODUCT.md). How the pieces fit together, and where a
real backend would attach, is in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Packages

```text
app_ui/        design tokens and shared widgets, vendored from the Events project
muto_ui/       marketplace widgets built from those tokens
muto_feature/  the embeddable feature — domain, application, data, presentation
muto_app/      standalone host used for development
```

`muto_feature` is built to be mounted inside a host application. `muto_app`
exists so it can be run on its own.

## Requirements

- Flutter 3.38.5, Dart 3.10.4
- Android or iOS. No web, no desktop.

## Running

```bash
cd muto_app && flutter run
```

English, Kazakh and Russian follow the device language. Light and dark follow
the system theme.

## Verifying

```bash
./scripts/verify.sh
```

Formatting, analysis, tests and the coverage floor across every package — the
same checks CI runs.

## Maintenance

```bash
./scripts/gen_sample_images.sh
```

Regenerates the placeholder images used by the sample listings. They are flat
generated shapes, never photographs.
