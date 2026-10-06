#!/usr/bin/env bash
# Build Typeless-Rev.app. Prints the bundle path as the last line of output.
#
#   CONFIG=Debug scripts/build.sh      Debug build (default: Release)
#   ARCHS="arm64 x86_64" scripts/build.sh   universal build (default: this Mac's architecture)
#   SIGN_IDENTITY="Name" scripts/build.sh   sign with that identity ("-" = ad-hoc); see scripts/sign-identity.sh
# Run the build output through `grep -E 'error|warning'` to skim a failed build.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${CONFIG:-Release}"
cd "$ROOT"

"$ROOT/scripts/fetch-vendor.sh" >&2
[[ -f Resources/InputIcon.pdf ]] || swift scripts/make-icon.swift Resources/InputIcon.pdf >&2
[[ -f Resources/AppIcon.icns ]] || swift scripts/make-app-icon.swift Resources/AppIcon.icns >&2
xcodegen generate --quiet >&2

ARCHS="${ARCHS:-$(uname -m)}"

# A stable identity keeps the microphone permission across rebuilds (scripts/setup-signing.sh).
# Xcode itself signs ad-hoc (its identity setting would also apply to the SwiftPM resource
# bundles, which have no team); scripts/bundle-rime.sh, the last build phase, re-signs the app
# with SIGN_IDENTITY.
export SIGN_IDENTITY="$("$ROOT/scripts/sign-identity.sh")"
echo "signing with: $SIGN_IDENTITY" >&2

xcodebuild \
  -project Typeless-Rev.xcodeproj \
  -scheme TypelessRev \
  -configuration "$CONFIG" \
  -derivedDataPath build/DerivedData \
  -destination 'platform=macOS' \
  ARCHS="$ARCHS" ONLY_ACTIVE_ARCH=NO \
  -quiet \
  build >&2

echo "$ROOT/build/DerivedData/Build/Products/$CONFIG/Typeless-Rev.app"
