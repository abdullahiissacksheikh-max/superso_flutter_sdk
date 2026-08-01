#!/usr/bin/env bash
# Full pub.dev readiness check for superso_flutter_sdk.
#
# Run this locally — the environment this package was authored in had no Dart
# or Flutter toolchain, so none of these checks have been executed yet.
#
#   chmod +x verify.sh && ./verify.sh
set -euo pipefail

cd "$(dirname "$0")"

section() { printf '\n\033[1;34m▸ %s\033[0m\n' "$1"; }
fail()    { printf '\033[1;31m✗ %s\033[0m\n' "$1"; exit 1; }
pass()    { printf '\033[1;32m✓ %s\033[0m\n' "$1"; }

command -v flutter >/dev/null 2>&1 || fail "flutter not found on PATH"

section "Resolving dependencies"
flutter pub get
pass "dependencies resolved"

section "Static analysis (must report zero issues)"
flutter analyze --no-pub
pass "flutter analyze clean"

section "Formatting"
dart format --output=none --set-exit-if-changed lib test
pass "formatting clean"

section "Tests"
flutter test --no-pub
pass "tests passed"

section "Documentation coverage"
dart doc --dry-run
pass "dartdoc generated without errors"

section "Publish dry run"
flutter pub publish --dry-run
pass "package is publishable"

section "pana score (pub.dev's own scorer)"
if command -v pana >/dev/null 2>&1; then
  pana --no-warning --exit-code-threshold 0
  pass "pana clean"
else
  printf '  pana not installed — run: dart pub global activate pana\n'
fi

printf '\n\033[1;32mAll checks passed.\033[0m\n'
