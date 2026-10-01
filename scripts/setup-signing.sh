#!/usr/bin/env bash
# One-time setup of a stable code-signing identity named TypelessDev (a self-signed
# certificate in your login keychain), so builds keep their microphone permission.
#
# Run it yourself in a terminal: it needs you at the keyboard twice. macOS asks for your login
# password to trust the certificate, and this script asks for it once more to let codesign use
# the key without a dialog on every build. The password is read silently, handed to `security`
# and never written anywhere. Safe to run again; it skips what is already done.
#
#   scripts/setup-signing.sh [name]      default name: TypelessDev
set -euo pipefail

NAME="${1:-TypelessDev}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

# 1. The certificate: self-signed, valid ten years, for code signing only.
if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
  echo "certificate \"$NAME\" already exists"
else
  cat >"$scratch/openssl.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
CNF
  # macOS's own LibreSSL writes a PKCS#12 file that `security import` accepts.
  /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$scratch/openssl.cnf" \
    -keyout "$scratch/key.pem" -out "$scratch/cert.pem" 2>/dev/null
  /usr/bin/openssl pkcs12 -export -inkey "$scratch/key.pem" -in "$scratch/cert.pem" -name "$NAME" \
    -out "$scratch/id.p12" -passout pass:import
  security import "$scratch/id.p12" -k "$KEYCHAIN" -P import -T /usr/bin/codesign >/dev/null
  echo "created certificate \"$NAME\""
fi

# 2. Trust it for code signing (macOS shows its password dialog).
if security find-identity -v -p codesigning | grep -q "\"$NAME\""; then
  echo "\"$NAME\" is already trusted for code signing"
else
  security find-certificate -c "$NAME" -p "$KEYCHAIN" >"$scratch/trust.pem"
  echo "macOS will now ask for your password to trust the certificate..."
  security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$scratch/trust.pem"
fi

# 3. Let codesign use the key without a dialog.
read -r -s -p "Login keychain password (used once, not stored): " password
echo
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -l "$NAME" -k "$password" "$KEYCHAIN" >/dev/null
unset password

# 4. Prove it: sign a scratch file and show the requirement the permission grant is tied to.
cp /usr/bin/true "$scratch/probe"
codesign --force --sign "$NAME" "$scratch/probe"
echo
codesign -dr - "$scratch/probe" 2>&1 | grep designated
echo
echo "Done. scripts/build.sh and scripts/install.sh now sign with \"$NAME\"."
