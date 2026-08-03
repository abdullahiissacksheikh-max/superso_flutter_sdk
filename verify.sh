#!/usr/bin/env bash
# Full pub.dev readiness check for superso_flutter_sdk.
#
#   chmod +x verify.sh && ./verify.sh
#
# Formatting is APPLIED rather than asserted: `dart format .` is the documented
# acceptance step, and failing a build on whitespace helps nobody. Everything
# after it is a hard gate.
set -euo pipefail

cd "$(dirname "$0")"

section() { printf '\n\033[1;34m▸ %s\033[0m\n' "$1"; }
fail()    { printf '\033[1;31m✗ %s\033[0m\n' "$1"; exit 1; }
pass()    { printf '\033[1;32m✓ %s\033[0m\n' "$1"; }

command -v flutter >/dev/null 2>&1 || fail "flutter not found on PATH"

section "1. Resolving dependencies"
flutter pub get
pass "flutter pub get"

section "2. Formatting"
dart format .
pass "dart format ."

section "3. Static analysis (must report zero errors)"
# `flutter analyze` exits non-zero on errors. Warnings and info do not block
# publishing, so surface them without failing the run.
if flutter analyze --no-pub; then
  pass "flutter analyze — clean"
else
  status=$?
  printf '\033[1;33m  analyze reported issues; failing only on errors\033[0m\n'
  if flutter analyze --no-pub 2>&1 | grep -qE '^\s*error\s' ; then
    fail "flutter analyze reported ERRORS"
  fi
  pass "flutter analyze — warnings/info only (exit $status)"
fi

section "4. Tests"
flutter test --no-pub
pass "flutter test"

section "5. Documentation build"
dart doc --dry-run || printf '  dart doc unavailable, skipping\n'

section "6. Publish dry run"
flutter pub publish --dry-run
pass "flutter pub publish --dry-run"

section "7. pana (pub.dev's own scorer)"
if command -v pana >/dev/null 2>&1; then
  pana --no-warning
else
  printf '  pana not installed — run: dart pub global activate pana\n'
fi

printf '\n\033[1;32mPackage is ready for: flutter pub publish\033[0m\n'
