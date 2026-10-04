#!/usr/bin/env bash
# Build and install Typeless-Rev into ~/Library/Input Methods, then register and
# enable its input source. It does not switch your current input source.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$("$ROOT/scripts/build.sh" | tail -1)"
DEST="$HOME/Library/Input Methods"

# A running copy keeps the old code loaded; macOS relaunches the new one on demand.
pkill -x Typeless-Rev 2>/dev/null || true

# An older build registered itself as a Chinese (Simplified) source. Turn that entry off while
# the installed copy still declares it; after the copy below, nothing could.
"$APP/Contents/MacOS/Typeless-Rev" --disable-legacy

mkdir -p "$DEST/Typeless-Rev.app"
rsync -a --delete "$APP/" "$DEST/Typeless-Rev.app/"
"$DEST/Typeless-Rev.app/Contents/MacOS/Typeless-Rev" --register

# macOS relaunches an active input method as soon as it is killed, so the kill above can bring
# the old binary straight back before the copy lands. Kill again now that the new one is in place.
pkill -x Typeless-Rev 2>/dev/null || true

echo
echo "Installed. Typeless-Rev starts in English; press the 中/英 key (Caps Lock) to switch to Chinese pinyin."
echo "It is listed under System Settings > Keyboard > Input Sources > English. If it is missing,"
echo "add it there, or log out and back in once."
