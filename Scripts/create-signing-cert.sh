#!/bin/bash
# Creates a self-signed code signing certificate and puts it in the login keychain.
#
# Why bother: an ad-hoc signature's designated requirement is the cdhash, which
# changes on every build, so Accessibility permission has to be re-granted every
# time. Signing with a certificate makes the requirement this instead:
#
#     designated => identifier "dev.sleight.Sleight" and certificate leaf = H"..."
#
# The certificate does not change between builds, so the permission sticks.
#
# This is for development. Distribution needs a Developer ID from Apple, since
# so that Gatekeeper accepts the app on someone else's Mac.
set -euo pipefail

NAME="${SIGNING_CERT_NAME:-Sleight Development}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

# Without -v. A self-signed leaf has no trust settings, so it never appears in
# the "valid identities" list even though codesign signs with it happily. With -v
# the guard never matched, and a second run imported a second identity with the
# same name - which makes `codesign --sign` ambiguous and breaks the build.
if security find-identity -p codesigning | grep -qF "$NAME"; then
    echo "already have a '$NAME' identity; nothing to do"
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/openssl.cnf" <<CONF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no

[dn]
CN = $NAME

[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CONF

openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
    -config "$WORK/openssl.cnf" \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>/dev/null

# A throwaway password rather than an empty one: the Security framework rejects
# empty-password PKCS#12 files. It only has to survive the next two lines.
PASS="$(openssl rand -hex 16)"

# -legacy exists only in OpenSSL 3.x. macOS ships LibreSSL, which rejects the
# flag outright and already defaults to the encoding Apple's Security framework
# needs, so asking for it there made the script fail on any Mac without Homebrew
# OpenSSL - silently, because the error was being discarded.
LEGACY=""
if openssl version | grep -q "^OpenSSL 3"; then
    LEGACY="-legacy"
fi

PASS="$PASS" openssl pkcs12 -export $LEGACY \
    -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -out "$WORK/identity.p12" -passout env:PASS

# -T lets codesign use the key without a prompt each time. macOS may still ask
# once, on the first signature; Always Allow makes it stop.
security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$PASS" \
    -T /usr/bin/codesign -T /usr/bin/security >/dev/null

if ! security find-identity -p codesigning | grep -qF "$NAME"; then
    echo "import reported success but no '$NAME' identity is present" >&2
    exit 1
fi
echo "created '$NAME' in the login keychain"
security find-identity -p codesigning | grep -F "$NAME"
cat <<EOF

Build with it:

    SIGN_ID="$NAME" ./Scripts/install.sh

macOS may ask once whether codesign can use the key. Choose Always Allow.
Accessibility permission then survives rebuilds, so install.sh stops resetting it.
EOF
