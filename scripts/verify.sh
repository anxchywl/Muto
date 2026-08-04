#!/usr/bin/env bash
# formatting, analysis, tests and the coverage floor — the same checks CI runs
set -euo pipefail

cd "$(dirname "$0")/.."

PACKAGES=(muto_ui muto_feature muto_app)

for package in "${PACKAGES[@]}"; do
  echo "==> $package"
  (
    cd "$package"
    flutter pub get >/dev/null
    dart format --output=none --set-exit-if-changed lib test
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
