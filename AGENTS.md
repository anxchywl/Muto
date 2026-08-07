# Agents

Rules for anyone writing code in this repository, human or model. They are not
suggestions: a change that breaks one is wrong even if it works.

**Sources of truth:**

- Product behaviour and what is simulated: `docs/PRODUCT.md`
- Structure, boundaries and security: `docs/ARCHITECTURE.md`
- Setup, checks, builds and CI: `docs/INFRASTRUCTURE.md`
- This file: coding rules

## Packages

```text
app_ui/        shared presentation kit, vendored from the Events project
muto_ui/       marketplace presentation built on app_ui tokens
muto_feature/  the embeddable feature: domain, application, data, presentation
muto_app/      standalone Flutter host: MaterialApp, theme, locale, lifecycle
```

Dependencies point one way: `muto_app → muto_feature → muto_ui → app_ui`. Never
the other way, and never a non-presentational dependency in `muto_ui`.

`app_ui` is a copy of the kit the Events project uses. Prefer leaving it alone.
Change it only when the fix belongs there rather than here — an accessibility
gap, a bug affecting every consumer — and then keep it generic and add nothing
marketplace-specific.

## Layers

`muto_feature/lib/src` is split four ways and a test enforces the split:

- `domain/` — pure Dart. No Flutter import, no networking, no storage.
- `application/` — controllers and cache. Depends on domain interfaces only.
- `data/` — repository implementations. The only layer that knows wire shapes.
- `presentation/` — screens and widgets. Never imports `data/`.

Business logic does not live in widgets. A widget that decides what something
means is a controller in the wrong place.

## General

- Write all code, comments, documentation and commit messages in English.
- Keep changes minimal — only touch what the task requires.
- Do not add features, abstractions, dependencies or error handling that was
  not asked for.
- Do not create a new file when editing an existing one would do.
- Do not leave debug prints, temporary variables or commented-out code.
- Never use emoji anywhere: UI, copy, source, comments, tests, docs or commits.

## Code style

- Follow the existing patterns in the file you are editing.
- Prefer early returns over deep nesting; keep functions small.
- Do not catch broadly; catch the specific failure you can handle, and never
  swallow one silently.
- No `TextStyle()`, raw `Color` or raw spacing numbers in feature code — use
  `AppTextStyles`, `AppColors`, `AppSpacing`.
- No literal user-facing text. Every string comes from the localizations, in
  all three languages.
- `lower_snake_case.dart` files, `UpperCamelCase` types. Short but descriptive:
  `ListingsController`, not `Mgr` or `ListingDataHandler`.

## Comments

Write a comment only when the **why** is non-obvious — a hidden constraint, a
workaround, or something that would surprise a reader. All lowercase, no
punctuation at the end, one line, intent rather than implementation. No
docstrings: types and good names are enough.

```dart
// bad
// this method loads the listings from the repository

// good
// host may not register our delegate, so the feature scopes its own
```

## Tests

- `flutter_test` only. Hand-written fakes, no mocking package.
- A new domain rule lands with the test that proves it.
- Every icon-only control asserts a non-empty semantics label.
- Prefer a test that asserts something is *absent* where absence is the point.
- Keep coverage above the floor, but never write a test to move a number.

## Commits

Conventional prefix, lowercase, imperative: `feat:`, `fix:`, `docs:`, `chore:`,
`style:`, `refactor:`, `test:`. Optional scope, as in
`fix(editor): keep draft on validation failure`. No period at the end, no issue
numbers unless asked, no trailers.

## What not to do

- Do not put marketplace concepts into `app_ui/` or `muto_ui/`.
- Do not refactor code unrelated to the current task.
- Do not add logging unless asked.
- Do not describe simulated behaviour as if a backend exists.
- Do not commit a secret, real student data, a photograph, a local path or
  build output.
