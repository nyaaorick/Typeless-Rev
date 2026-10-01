#!/usr/bin/env bash
# Embed librime and the Rime data set into the built app bundle. Runs as the
# post-build phase of the Xcode target and is safe to run again by hand.
#
#   Contents/Frameworks/librime.1.dylib        engine
#   Contents/Frameworks/rime-plugins/*.dylib   lua, octagram, predict
#   Contents/SharedSupport/rime/               schemas, dictionaries, OpenCC data
#   Contents/SharedSupport/rime/build/         dictionaries compiled at build time
#   Contents/SharedSupport/user-seed/          files copied to the user data dir on first run
#
# Usage: bundle-rime.sh /path/to/Typeless-Rev.app
set -euo pipefail

APP="${1:?usage: bundle-rime.sh <app bundle>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIBRIME="$ROOT/vendor/librime/dist"
SRC="$ROOT/vendor/rime-data-src"
# SIGN_IDENTITY (set by scripts/build.sh) wins over Xcode's own ad-hoc setting.
IDENTITY="${SIGN_IDENTITY:-${EXPANDED_CODE_SIGN_IDENTITY:--}}"

FRAMEWORKS="$APP/Contents/Frameworks"
SUPPORT="$APP/Contents/SharedSupport"
RIME_DATA="$SUPPORT/rime"

if [[ ! -f "$LIBRIME/lib/librime.1.dylib" || ! -d "$SRC/rime-prelude" ]]; then
  echo "error: vendor/ is incomplete; run scripts/fetch-vendor.sh" >&2
  exit 1
fi

sign() {
  codesign --force --sign "$IDENTITY" --timestamp=none "$@"
}

# Start from a clean slate so stale files never ship. Stray coverage dumps
# (*.profraw) dropped into the bundle by tools run from inside it would break signing.
rm -rf "$FRAMEWORKS" "$SUPPORT"
find "$APP" -name '*.profraw' -delete
mkdir -p "$FRAMEWORKS/rime-plugins" "$RIME_DATA/opencc" "$SUPPORT/user-seed"

# --- engine ------------------------------------------------------------------
cp -L "$LIBRIME/lib/librime.1.dylib" "$FRAMEWORKS/"
for plugin in "$LIBRIME"/lib/rime-plugins/*.dylib; do
  cp -L "$plugin" "$FRAMEWORKS/rime-plugins/"
  # Plugins link @rpath/librime.1.dylib; let them find it one directory up.
  install_name_tool -add_rpath "@loader_path/.." "$FRAMEWORKS/rime-plugins/$(basename "$plugin")"
done

# --- data --------------------------------------------------------------------
cp "$SRC"/rime-prelude/{default,key_bindings,punctuation,symbols}.yaml "$RIME_DATA/"
cp "$SRC/rime-essay/essay.txt" "$RIME_DATA/"
# The pinyin dictionary is luna_pinyin's; the schema on top of it is our own (Data/rime).
cp "$SRC/rime-luna-pinyin/luna_pinyin.dict.yaml" "$RIME_DATA/"
cp "$SRC/rime-luna-pinyin/pinyin.yaml" "$RIME_DATA/"
cp "$ROOT/Data/rime/typeless_pinyin.schema.yaml" "$RIME_DATA/"
# Simplified conversion for typeless_pinyin (opencc_config: t2s.json). The config is
# our own: the Homebrew one targets OpenCC 1.2+, newer than the copy inside librime 1.17.
cp "$ROOT"/vendor/opencc/{TSPhrases.ocd2,TSCharacters.ocd2} "$RIME_DATA/opencc/"
cp "$ROOT/Data/opencc/t2s.json" "$RIME_DATA/opencc/"
cp "$ROOT"/Data/user-seed/* "$SUPPORT/user-seed/"

# --- prebuilt dictionaries ---------------------------------------------------
# Compiling the pinyin dictionary takes a while; do it here so the first launch
# only has to deploy the (tiny) user config.
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
cp "$ROOT"/Data/user-seed/* "$scratch/"
DYLD_LIBRARY_PATH="$LIBRIME/lib" "$LIBRIME/bin/rime_deployer" \
  --build "$scratch" "$RIME_DATA" "$RIME_DATA/build" >"$scratch/deployer.log" 2>&1 || {
  cat "$scratch/deployer.log" >&2
  echo "error: rime_deployer --build failed" >&2
  exit 1
}

# --- signing -----------------------------------------------------------------
# Nested code first, then the app itself. Xcode skips its own CodeSign step on
# incremental builds, so the seal over the files written above has to come from here.
sign "$FRAMEWORKS"/rime-plugins/*.dylib
sign "$FRAMEWORKS/librime.1.dylib"
sign "$APP"

# --- checks ------------------------------------------------------------------
# Every dependency must resolve inside the bundle or the system.
bad=0
for lib in "$FRAMEWORKS/librime.1.dylib" "$FRAMEWORKS"/rime-plugins/*.dylib; do
  while read -r dep; do
    case "$dep" in
      /usr/lib/* | /System/* | @rpath/* | @loader_path/* | @executable_path/*) ;;
      *) echo "error: $(basename "$lib") links $dep" >&2; bad=1 ;;
    esac
  done < <(otool -L "$lib" | grep -E '^[[:space:]]' | awk '{print $1}')
done
for expected in default.yaml typeless_pinyin.schema.yaml luna_pinyin.table.bin typeless_pinyin.prism.bin; do
  [[ -f "$RIME_DATA/build/$expected" ]] || { echo "error: prebuilt $expected is missing" >&2; bad=1; }
done
# OpenCC fails with a misleading "config not found" when a referenced dictionary is missing.
for config in "$RIME_DATA"/opencc/*.json; do
  for dict in $(grep -o '"file": *"[^"]*"' "$config" | sed 's/.*: *"\(.*\)"/\1/'); do
    [[ -f "$RIME_DATA/opencc/$dict" ]] || { echo "error: $(basename "$config") needs opencc/$dict" >&2; bad=1; }
  done
done
codesign --verify --deep --strict "$APP" 2>&1 || { echo "error: bundle signature does not verify" >&2; bad=1; }
[[ $bad -eq 0 ]] || exit 1

echo "signed with: $IDENTITY"; echo "bundled librime $(basename "$(readlink "$LIBRIME/lib/librime.dylib" 2>/dev/null || echo librime)") + Rime data into $(basename "$APP")"
