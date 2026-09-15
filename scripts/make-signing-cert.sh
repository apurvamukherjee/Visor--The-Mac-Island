#!/usr/bin/env bash
# One-time: create a self-signed code-signing certificate so the app keeps a
# stable identity across rebuilds.
#
# Why this exists: TCC (calendar, and every other permission) remembers a
# grant against the app's code signature. Ad-hoc signing has no stable
# identity, so macOS falls back to the binary's cdhash — which changes on
# every build — and re-asks for permission each time. A self-signed
# certificate gives every future build the same identity, so the grant sticks.
#
# This writes to your login keychain and marks the certificate trusted for
# code signing. macOS will ask for your password. Nothing leaves this machine,
# and it does not make the app distributable — it is local identity only.
set -euo pipefail

NAME="Notchy Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$NAME" >/dev/null 2>&1; then
    echo "Certificate '$NAME' already exists. Nothing to do."
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
    -subj "/CN=$NAME" \
    -addext "basicConstraints=critical,CA:false" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null

openssl pkcs12 -export -out "$WORK/cert.p12" \
    -inkey "$WORK/key.pem" -in "$WORK/cert.pem" -passout pass:

security import "$WORK/cert.p12" -k "$KEYCHAIN" -P "" -T /usr/bin/codesign
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem"

echo
echo "Created '$NAME'. Next:"
echo "  1. Set CODE_SIGN_IDENTITY in project.yml to: $NAME"
echo "  2. xcodegen generate && ./scripts/make-dmg.sh"
echo "  3. Grant calendar access once more — it sticks from then on."
