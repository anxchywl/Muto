# Agents

Rules for anyone — human or model — writing code in this repository.

**Sources of truth:**

- Product behaviour and what is simulated: `docs/PRODUCT.md`
- Technical structure and boundaries: `docs/ARCHITECTURE.md`
- This file: coding rules (mandatory)

---

## Packages

```text
app_ui/        shared presentation kit, vendored from the Events project
muto_ui/       marketplace presentation built on app_ui tokens
muto_feature/  the embeddable feature: domain, application, data, presentation
muto_app/      standalone Flutter host: MaterialApp, theme, locale, lifecycle
```

`app_ui` is a copy of the kit the Events project uses. Prefer leaving it alone.
Change it only when the fix belongs there rather than here — an accessibility
gap, a bug affecting every consumer — and then keep it generic, match the
surrounding style, and add nothing marketplace-specific.

Dependency direction is one way:

```text
muto_app -> muto_feature -> muto_ui -> app_ui
```

Never import in the other direction. Never add a dependency to `muto_ui` that is
not presentational.

---

## General

- Write all code, comments, documentation, and commit messages in English.
- Keep changes minimal — only touch what the task requires.
- Do not add features, abstractions, or error handling that was not asked for.
- Do not create new files unless editing an existing one is not possible.
- Do not leave debug prints, temporary variables, or commented-out code.
- Never use emoji anywhere: UI, copy, source, comments, tests, docs, or commits.

## Comments

Write a comment only when the **why** is non-obvious — a hidden constraint, a
workaround, or something that would surprise a reader.

Rules:

- All comments lowercase, no punctuation at the end.
- One line maximum.
- Explain intent, never implementation.

```dart
// bad
// this method loads the listings from the repository

// good
// host may not register our delegate, so the feature scopes its own
```

## Code style

- Follow the existing patterns in the file you are editing.
- Prefer early returns over deep nesting.
- Keep functions small — one responsibility each.
- Do not catch broadly; catch the specific failure you can handle.
- Do not shadow builtins.
- No `TextStyle()`, raw `Color`, or raw spacing numbers in feature code — use
  `AppTextStyles`, `AppColors`, `AppSpacing`.
- No literal user-facing text. Every string comes from the localizations.

## Layers

`muto_feature/lib/src` is split and the split is enforced by tests:

- `domain/` — pure Dart. No Flutter import, no networking, no storage.
- `application/` — controllers and cache. Depends on domain interfaces only.
- `data/` — repository implementations. The only layer that knows wire shapes.
- `presentation/` — screens and widgets. Never imports `data/`.

## Naming

- `lower_snake_case.dart` file names, `UpperCamelCase` types.
- Short but descriptive — `ListingsController`, not `Mgr` or `ListingDataHandler`.
- A file mirrors what it holds.

## Tests

- `flutter_test` only. Hand-written fakes, no mocking package.
- Every icon-only control asserts a non-empty semantics label.
- A new domain rule lands with the test that proves it.

## Commits

- Conventional prefix, lowercase, imperative: `feat:`, `fix:`, `docs:`,
  `chore:`, `style:`, `refactor:`, `test:`.
- Optional scope: `fix(editor): keep draft on validation failure`.
- No period at the end. No issue numbers unless asked. No trailers.

## What not to do

- Do not put marketplace concepts into `app_ui/` or `muto_ui/`.
- Do not refactor code unrelated to the current task.
- Do not add logging unless asked.
- Do not write docstrings — type hints and good names are enough.
- Do not describe simulated behaviour as if a backend exists.
