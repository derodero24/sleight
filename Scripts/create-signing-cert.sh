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
# Launch Services requires one for CGEventTap with Input Monitoring.
set -euo pipefail

NAME="${SIGNING_CERT_NAME:-Sleight Development}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning | grep -q "$NAME"; then
    echo "already have a '$NAME' identity; nothing to do"
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/openssl.cnf" <<'CONF'
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no

[dn]
CN = PLACEHOLDER

[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CONF
sed -i '' "s/PLACEHOLDER/$NAME/" "$WORK/openssl.cnf"

openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
    -config "$WORK/openssl.cnf" \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>/dev/null

# A throwaway password rather than an empty one: the Security framework rejects
# empty-password PKCS#12 files. It only has to survive the next two lines.
PASS="$(openssl rand -hex 16)"

openssl pkcs12 -export -legacy \
    -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -out "$WORK/identity.p12" -passout "pass:$PASS" 2>/dev/null

# -T lets codesign use the key without a prompt each time. macOS may still ask
# once, on the first signature; Always Allow makes it stop.
security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$PASS" \
    -T /usr/bin/codesign -T /usr/bin/security >/dev/null

echo "created '$NAME' in the login keychain"
security find-identity -v -p codesigning | grep "$NAME" || true
cat <<EOF

Build with it:

    SIGN_ID="$NAME" ./Scripts/install.sh

macOS may ask once whether codesign can use the key. Choose Always Allow.
Accessibility permission then survives rebuilds, so install.sh stops resetting it.
EOF
