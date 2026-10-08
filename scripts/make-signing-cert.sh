#!/bin/bash
# Creates a self-signed "Shortkeys Dev" code-signing identity in the login keychain.
# A stable identity keeps the Accessibility permission across rebuilds.
set -euo pipefail

NAME="Shortkeys Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -p codesigning | grep -q "\"$NAME\""; then
    echo "\"$NAME\" already exists."
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.cnf" <<CNF
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
CNF

# Use the system LibreSSL: its PKCS#12 output is what `security import` expects.
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -config "$TMP/cert.cnf" -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
/usr/bin/openssl pkcs12 -export -name "$NAME" -passout pass:shortkeys \
    -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -out "$TMP/identity.p12"

security import "$TMP/identity.p12" -k "$KEYCHAIN" -P shortkeys -T /usr/bin/codesign

# Let codesign use the key without a prompt (otherwise signing can fail with
# errSecInternalComponent). Asks for your Mac login password.
echo "Allowing codesign to use the key; enter your Mac login password:"
security set-key-partition-list -S apple-tool:,apple: -s "$KEYCHAIN" >/dev/null

echo "Created \"$NAME\". Now run ./build.sh"
