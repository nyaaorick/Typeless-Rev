#!/usr/bin/env bash
# Build, then run the unit tests and the headless librime self-test.
# SPEECH=1 also runs the speech self-test (downloads the en-US and zh-CN speech models on first run).
# POLISH=1 also runs the polish-model self-test (needs scripts/prepare-model.sh to have been run).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$("$ROOT/scripts/build.sh" | tail -1)"
ARCH="${ARCHS:-$(uname -m)}"
LOG="$ROOT/build/unit-tests.log"

echo "==> unit tests"
cd "$ROOT"
if xcodebuild test -project Typeless-Rev.xcodeproj -scheme TypelessRev \
  -destination "platform=macOS,arch=${ARCH%% *}" -derivedDataPath build/DerivedData \
  ARCHS="$ARCH" ONLY_ACTIVE_ARCH=NO >"$LOG" 2>&1; then
  grep -E 'Executed [0-9]+ tests' "$LOG" | tail -1
else
  tail -40 "$LOG" >&2
  echo "error: unit tests failed; full log: $LOG" >&2
  exit 1
fi

echo "==> librime self-test"
"$APP/Contents/MacOS/Typeless-Rev" --selftest

echo "==> menu bar and HUD self-test"
"$APP/Contents/MacOS/Typeless-Rev" --selftest-ui

if [[ "${POLISH:-0}" == 1 ]]; then
  echo "==> polish self-test"
  "$APP/Contents/MacOS/Typeless-Rev" --selftest-polish
fi

if [[ "${SPEECH:-0}" == 1 ]]; then
  echo "==> speech self-test"
  "$APP/Contents/MacOS/Typeless-Rev" --selftest-speech
fi
