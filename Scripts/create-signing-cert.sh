#!/bin/bash
# Create a local self-signed code signing certificate
# This certificate works for Full Disk Access on local builds

set -e

CERT_NAME="Pickle Cider Development"
KEYCHAIN="login.keychain-db"

echo "Creating local code signing certificate: $CERT_NAME"
echo ""

# Check if certificate already exists
EXISTING=$(security find-identity -v -p codesigning 2>/dev/null | grep "$CERT_NAME" || true)
if [ -n "$EXISTING" ]; then
    echo "Certificate already exists:"
    echo "$EXISTING"
    exit 0
fi

# Create a certificate signing request config
TEMP_DIR=$(mktemp -d)
CONFIG_FILE="$TEMP_DIR/cert.conf"
KEY_FILE="$TEMP_DIR/key.pem"
CERT_FILE="$TEMP_DIR/cert.pem"
P12_FILE="$TEMP_DIR/cert.p12"

cat > "$CONFIG_FILE" << 'EOF'
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_req
prompt = no

[req_distinguished_name]
CN = Pickle Cider Development
O = Local Development

[v3_req]
keyUsage = critical, digitalSignature
extendedKeyUsage = codeSigning
basicConstraints = CA:FALSE
EOF

echo "Generating certificate..."

# Generate private key and self-signed certificate
openssl req -x509 -newkey rsa:2048 -keyout "$KEY_FILE" -out "$CERT_FILE" \
    -days 3650 -nodes -config "$CONFIG_FILE" 2>/dev/null

# Create PKCS12 file (needed for keychain import)
# Use -legacy flag for compatibility with newer OpenSSL versions
TEMP_PASS="temppass123"
openssl pkcs12 -export -legacy -out "$P12_FILE" -inkey "$KEY_FILE" -in "$CERT_FILE" \
    -passout pass:"$TEMP_PASS" -name "$CERT_NAME" 2>/dev/null || \
openssl pkcs12 -export -out "$P12_FILE" -inkey "$KEY_FILE" -in "$CERT_FILE" \
    -passout pass:"$TEMP_PASS" -name "$CERT_NAME" 2>/dev/null

# Import into keychain
echo "Importing into keychain (you may be prompted for your password)..."
security import "$P12_FILE" -k "$KEYCHAIN" -P "$TEMP_PASS" -T /usr/bin/codesign -T /usr/bin/security -A

# Set trust for code signing
echo "Setting certificate trust (requires authentication)..."
security add-trusted-cert -d -r trustRoot -k "$KEYCHAIN" "$CERT_FILE" 2>/dev/null || true

# Allow codesign to use the key without prompting
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "" "$KEYCHAIN" 2>/dev/null || true

# Cleanup
rm -rf "$TEMP_DIR"

echo ""
echo "Verifying certificate..."
security find-identity -v -p codesigning 2>/dev/null | grep "$CERT_NAME" || {
    echo ""
    echo "Certificate created but may need manual trust setup."
    echo ""
    echo "Open Keychain Access → login → My Certificates"
    echo "Double-click '$CERT_NAME' → Trust → Code Signing: Always Trust"
}

echo ""
echo "Done! You can now run: ./Scripts/build-all.sh"
