#!/usr/bin/env bash
# Prints the code-signing identity the build should use: a name, or "-" for ad-hoc.
# Messages go to stderr, so `IDENTITY="$(scripts/sign-identity.sh)"` captures only the answer.
#
# A stable identity keeps macOS's microphone grant across rebuilds; an ad-hoc signature changes
# with every build and loses it. Order of preference:
#   1. $SIGN_IDENTITY, if set ("-" forces ad-hoc)
#   2. TypelessDev, the self-signed certificate made by scripts/setup-signing.sh
#   3. the first valid "Apple Development" certificate (a free Apple ID's Personal Team)
#   4. ad-hoc
# An identity only counts if codesign can use it without stopping to ask: the first use of a
# new key makes macOS show a Keychain dialog, and a build must not hang behind it.
set -uo pipefail

# True when codesign signs a scratch file with "$1" within 10 seconds.
usable() {
  local scratch pid dog status
  scratch="$(mktemp -d)"
  cp /usr/bin/true "$scratch/probe"
  codesign --force --sign "$1" "$scratch/probe" >/dev/null 2>&1 &
  pid=$!
  ( sleep 10; kill "$pid" 2>/dev/null ) >/dev/null 2>&1 &
  dog=$!
  wait "$pid" 2>/dev/null
  status=$?
  { kill "$dog"; wait "$dog"; } 2>/dev/null
  rm -rf "$scratch"
  return $status
}

valid_identities="$(security find-identity -v -p codesigning 2>/dev/null)"
candidates=()
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  candidates+=("$SIGN_IDENTITY")
else
  grep -q '"TypelessDev"' <<<"$valid_identities" && candidates+=("TypelessDev")
  apple="$(grep -o '"Apple Development: [^"]*"' <<<"$valid_identities" | head -1 | tr -d '"')"
  [[ -n "$apple" ]] && candidates+=("$apple")
fi

for identity in ${candidates[@]+"${candidates[@]}"}; do
  if [[ "$identity" == "-" ]] || usable "$identity"; then
    echo "$identity"
    exit 0
  fi
  echo "warning: cannot sign with \"$identity\" without a Keychain prompt; run scripts/setup-signing.sh once" >&2
done

echo "warning: signing ad-hoc; microphone permission will not survive a rebuild (scripts/setup-signing.sh fixes that)" >&2
echo "-"
