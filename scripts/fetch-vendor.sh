#!/usr/bin/env bash
# Fetch the pinned third-party inputs into vendor/ (gitignored). Idempotent.
#   vendor/librime/dist   prebuilt librime (universal), headers, rime_deployer
#   vendor/rime-data-src/ Rime schemas/dictionaries (prelude, essay, luna-pinyin, stroke)
#   vendor/opencc/        OpenCC conversion data taken from the Homebrew bottle
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR="$ROOT/vendor"
LIBRIME_TAG="1.17.0"
LIBRIME_ASSET="rime-33e7814-macOS-universal.tar.bz2"

# repo -> pinned commit
RIME_DATA_REPOS=(
  "rime-prelude 082425e"
  "rime-essay 054920d"
  "rime-luna-pinyin 56b934b"
  "rime-stroke 1e8fff9"
)

mkdir -p "$VENDOR"

if [[ ! -f "$VENDOR/librime/dist/lib/librime.1.dylib" ]]; then
  echo "==> librime $LIBRIME_TAG"
  tmp="$(mktemp -d)"
  gh release download "$LIBRIME_TAG" --repo rime/librime -p "$LIBRIME_ASSET" -D "$tmp"
  mkdir -p "$VENDOR/librime"
  tar -xjf "$tmp/$LIBRIME_ASSET" -C "$VENDOR/librime"
  rm -rf "$tmp"
fi

for entry in "${RIME_DATA_REPOS[@]}"; do
  read -r repo commit <<<"$entry"
  dest="$VENDOR/rime-data-src/$repo"
  if [[ ! -d "$dest/.git" ]]; then
    echo "==> $repo @ $commit"
    mkdir -p "$VENDOR/rime-data-src"
    git clone -q "https://github.com/rime/$repo.git" "$dest"
  fi
  git -C "$dest" checkout -q "$commit"
done

if [[ ! -f "$VENDOR/opencc/t2s.json" ]]; then
  echo "==> OpenCC data (Homebrew bottle, not installed)"
  brew fetch --quiet opencc >/dev/null
  bottle="$(brew --cache opencc)"
  tmp="$(mktemp -d)"
  tar -xzf "$bottle" -C "$tmp" --include='*/share/opencc/*'
  mkdir -p "$VENDOR/opencc"
  cp "$tmp"/opencc/*/share/opencc/*.json "$tmp"/opencc/*/share/opencc/*.ocd2 "$VENDOR/opencc/"
  rm -rf "$tmp"
fi

echo "vendor ready: $(grep -m1 '^librime ' "$VENDOR/librime/version-info.txt") (release $LIBRIME_TAG)"
