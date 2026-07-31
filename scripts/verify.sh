#!/usr/bin/env bash
# formatting, analysis and tests across every package — the same checks CI runs
set -euo pipefail

cd "$(dirname "$0")/.."

PACKAGES=(muto_ui muto_feature muto_app)

for package in "${PACKAGES[@]}"; do
  echo "==> $package"
  (
    cd "$package"
    flutter pub get >/dev/null
    dart format --output=none --set-exit-if-changed lib test
    flutter analyze --no-pub
    if compgen -G "test/**/*_test.dart" >/dev/null || compgen -G "test/*_test.dart" >/dev/null; then
      flutter test --no-pub --reporter=compact
    else
      echo "no tests yet"
    fi
  )
done

echo "==> all packages passed"
