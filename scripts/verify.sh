#!/usr/bin/env bash
# formatting, analysis, tests and coverage floors — the same checks ci runs
set -euo pipefail

cd "$(dirname "$0")/.."

PACKAGES=(muto_ui muto_feature muto_app)

echo "==> backend"
(
  cd backend
  uv sync --frozen --extra dev >/dev/null
  uv run --frozen ruff format --check app migrations tests
  uv run --frozen ruff check app migrations tests
  uv run --frozen mypy app
  uv run --frozen bandit -q -r app
  uv run --frozen pytest tests/unit -q
)

for package in "${PACKAGES[@]}"; do
  echo "==> $package"
  (
    cd "$package"
    flutter pub get >/dev/null
    format_paths=(lib test)
    [ -d integration_test ] && format_paths+=(integration_test)
    dart format --output=none --set-exit-if-changed "${format_paths[@]}"
    flutter analyze --no-pub --fatal-infos

    if [ "$package" = "muto_feature" ]; then
      flutter test --no-pub --coverage --reporter=failures-only
    else
      flutter test --no-pub --reporter=failures-only
    fi
  )
done

echo "==> coverage"
./scripts/coverage_floor.sh muto_feature/coverage/lcov.info 70

echo "==> all packages passed"
