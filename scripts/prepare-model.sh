#!/usr/bin/env bash
# Download and install the polish model (pinned revision) without the ~0.67 GB vision
# encoder, where the app looks for it. This is the menu's "Download" without the menu.
#
#   scripts/prepare-model.sh
#
# Installs to ~/Library/Application Support/Typeless-Rev/Models/polish
# (override with TYPELESS_REV_MODEL_DIR).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$("$ROOT/scripts/build.sh" | tail -1)"
exec "$APP/Contents/MacOS/Typeless-Rev" --install-model
