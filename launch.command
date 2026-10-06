#!/usr/bin/env bash
# Double-click to build Typeless-Rev, install it into ~/Library/Input Methods, start it, and follow
# its log. Close the window (or press Control-C) to stop following; the input method keeps running.
set -euo pipefail

cd "$(dirname "$0")"
APP="$HOME/Library/Input Methods/Typeless-Rev.app"

echo "==> building and installing (the first build takes a few minutes)"
if ! scripts/install.sh; then
  echo
  echo "Build or install failed; see above. Press Return to close."
  read -r
  exit 1
fi

# install.sh stops the old copy; macOS restarts an input method only when it is next used, so start
# it now to have the menu bar icon back at once.
sleep 1
pgrep -x Typeless-Rev >/dev/null || open "$APP"
sleep 1
if pgrep -x Typeless-Rev >/dev/null; then
  echo "==> Typeless-Rev is running. Pick it in the input menu, then hold Right Option and speak."
else
  echo "==> Installed, but it did not start; pick Typeless-Rev in the input menu to start it."
fi

echo "==> following the log (Control-C to stop)"
exec log stream --style compact --info --predicate 'subsystem == "com.nyaaorick.inputmethod.TypelessRev"'
