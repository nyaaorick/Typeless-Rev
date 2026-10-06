#!/usr/bin/env bash
# Build an installer package for people who will not build from source. Prints the .pkg path as
# the last line of output.
#
#   scripts/package.sh                      build/Typeless-Rev-<version>.pkg
#   SIGN_IDENTITY="-" scripts/package.sh    sign the app ad-hoc instead of with this Mac's identity
#
# The package itself is not signed or notarized (that needs a paid Apple Developer account), so a
# downloaded copy is stopped by Gatekeeper once; README "Install" walks the user through "Open
# Anyway". The app inside keeps whatever signature build.sh gave it, and files an installer writes
# carry no quarantine, so it runs once installed.
#
# It installs into the current user's ~/Library/Input Methods (no administrator password), refuses
# Intel Macs and anything before macOS 26 on its own (no installer-check script, which would add
# a warning of its own), quits a running copy first and registers the input source afterwards.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$("$ROOT/scripts/build.sh" | tail -1)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Contents/Info.plist")"
OUT="$ROOT/build/Typeless-Rev-$VERSION.pkg"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/root" "$WORK/scripts" "$WORK/resources"
ditto "$APP" "$WORK/root/Typeless-Rev.app"

# Installer runs these with $2 = the folder the app goes into. In the user's home domain they may
# still run as root, so anything that talks to the user's session runs as the console user.
cat >"$WORK/scripts/preinstall" <<'EOF'
#!/bin/bash
# A running copy keeps the old code loaded; macOS relaunches the new one on demand.
pkill -x Typeless-Rev 2>/dev/null || true
exit 0
EOF

cat >"$WORK/scripts/postinstall" <<'EOF'
#!/bin/bash
APP="$2/Typeless-Rev.app/Contents/MacOS/Typeless-Rev"
as_user() {
  if [[ $EUID -eq 0 ]]; then
    local user; user="$(stat -f%Su /dev/console)"
    launchctl asuser "$(id -u "$user")" sudo -u "$user" "$@"
  else
    "$@"
  fi
}
as_user "$APP" --register || true
# macOS relaunches an active input method as soon as it is killed, so the old binary can come
# back before the copy lands. Kill again now that the new one is in place.
pkill -x Typeless-Rev 2>/dev/null || true
exit 0
EOF
chmod +x "$WORK/scripts/preinstall" "$WORK/scripts/postinstall"

# Not relocatable: otherwise Installer "upgrades" any other copy with the same bundle ID it finds
# (a build folder, a Downloads copy) instead of writing to Input Methods.
pkgbuild --analyze --root "$WORK/root" "$WORK/component.plist" >/dev/null
plutil -replace 0.BundleIsRelocatable -bool NO "$WORK/component.plist"

pkgbuild \
  --root "$WORK/root" \
  --component-plist "$WORK/component.plist" \
  --install-location "/Library/Input Methods" \
  --scripts "$WORK/scripts" \
  --identifier "$BUNDLE_ID.pkg" \
  --version "$VERSION" \
  "$WORK/Typeless-Rev.pkg" >&2

cat >"$WORK/resources/conclusion.html" <<'EOF'
<!doctype html>
<html><body style="font-family: -apple-system; font-size: 13px">
<h3>Typeless-Rev is installed.</h3>
<ol>
  <li>Pick <b>Typeless-Rev</b> in the input menu in the menu bar. If it is not listed, add it in
    System Settings &gt; Keyboard &gt; Input Sources (under English), or log out and back in once.</li>
  <li>Turn off "Use the Caps Lock key to switch to and from ABC" in the same place: the Caps Lock
    key is the 中/英 key here.</li>
  <li>Open the microphone icon in the menu bar: allow the microphone and download the speech data,
    and the polish model if you want it.</li>
  <li>Hold <b>Right Option</b> and speak.</li>
</ol>
</body></html>
EOF

# The user's home domain only: ~/Library/Input Methods, no administrator password. The OS and CPU
# checks are declarative, so Installer shows no "will run a program" warning.
cat >"$WORK/distribution.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
    <title>Typeless-Rev $VERSION</title>
    <options customize="never" require-scripts="false" hostArchitectures="arm64"/>
    <domains enable_anywhere="false" enable_currentUserHome="true" enable_localSystem="false"/>
    <allowed-os-versions><os-version min="26.0"/></allowed-os-versions>
    <conclusion file="conclusion.html" mime-type="text/html"/>
    <choices-outline><line choice="default"/></choices-outline>
    <choice id="default" title="Typeless-Rev"><pkg-ref id="$BUNDLE_ID.pkg"/></choice>
    <pkg-ref id="$BUNDLE_ID.pkg" version="$VERSION" onConclusion="none">Typeless-Rev.pkg</pkg-ref>
</installer-gui-script>
EOF

productbuild \
  --distribution "$WORK/distribution.xml" \
  --resources "$WORK/resources" \
  --package-path "$WORK" \
  "$OUT" >&2

echo "$OUT"
