#!/usr/bin/env bash
set -euo pipefail

IDENTITY_NAME="${AGENT_AUTOACCEPT_LOCAL_SIGN_IDENTITY:-Agent AutoAccept Local Signing}"
KEYCHAIN_PATH="${AGENT_AUTOACCEPT_SIGN_KEYCHAIN:-$HOME/Library/Keychains/AgentAutoAcceptSigning.keychain-db}"
SUPPORT_DIR="${AGENT_AUTOACCEPT_SUPPORT_DIR:-$HOME/Library/Application Support/AgentAutoAccept}"
PASSWORD_FILE="${AGENT_AUTOACCEPT_SIGN_PASSWORD_FILE:-$SUPPORT_DIR/signing-keychain-password}"

mkdir -p "$SUPPORT_DIR"
chmod 700 "$SUPPORT_DIR"

if [[ ! -f "$PASSWORD_FILE" ]]; then
    uuidgen > "$PASSWORD_FILE"
    chmod 600 "$PASSWORD_FILE"
fi

KEYCHAIN_PASSWORD="$(cat "$PASSWORD_FILE")"

if [[ ! -f "$KEYCHAIN_PATH" ]]; then
    security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH" >/dev/null
fi

security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH" >/dev/null
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH" >/dev/null

if ! security find-identity -v -p codesigning "$KEYCHAIN_PATH" 2>/dev/null | grep -Fq "\"$IDENTITY_NAME\""; then
    TMP_DIR="$(mktemp -d)"
    trap 'rm -rf "$TMP_DIR"' EXIT

    cat > "$TMP_DIR/openssl.cnf" <<EOF
[ req ]
distinguished_name = req_distinguished_name
x509_extensions = codesign_ext
prompt = no

[ req_distinguished_name ]
CN = $IDENTITY_NAME

[ codesign_ext ]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = codeSigning
EOF

    openssl req \
        -newkey rsa:2048 \
        -nodes \
        -keyout "$TMP_DIR/key.pem" \
        -x509 \
        -days 3650 \
        -out "$TMP_DIR/cert.pem" \
        -config "$TMP_DIR/openssl.cnf" >/dev/null 2>&1

    openssl pkcs12 \
        -export \
        -legacy \
        -inkey "$TMP_DIR/key.pem" \
        -in "$TMP_DIR/cert.pem" \
        -out "$TMP_DIR/identity.p12" \
        -name "$IDENTITY_NAME" \
        -passout "pass:$KEYCHAIN_PASSWORD" >/dev/null 2>&1

    security import "$TMP_DIR/identity.p12" \
        -k "$KEYCHAIN_PATH" \
        -P "$KEYCHAIN_PASSWORD" \
        -T /usr/bin/codesign >/dev/null
fi

EXISTING_KEYCHAINS="$(security list-keychains -d user | tr -d '\"')"
if ! printf '%s\n' "$EXISTING_KEYCHAINS" | grep -Fxq "$KEYCHAIN_PATH"; then
    security list-keychains -d user -s "$KEYCHAIN_PATH" $EXISTING_KEYCHAINS >/dev/null
fi

security set-key-partition-list \
    -S apple-tool:,apple: \
    -s \
    -k "$KEYCHAIN_PASSWORD" \
    "$KEYCHAIN_PATH" >/dev/null 2>&1 || true

security find-certificate -c "$IDENTITY_NAME" "$KEYCHAIN_PATH" >/dev/null
security find-identity -v -p codesigning "$KEYCHAIN_PATH" || true
echo
echo "Local signing identity is ready: $IDENTITY_NAME"
