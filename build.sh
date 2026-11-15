#!/bin/zsh
# Builds Bulb.app, signs it with a fixed local identity, and with "install" copies it to /Applications and opens it.
set -euo pipefail
cd "$(dirname "$0")"

APP=Bulb
IDENTITY="Bulb Local Signing"
BUNDLE="build/$APP.app"

make_identity() {
  local dir; dir=$(mktemp -d)
  local password; password=$(openssl rand -hex 16)
  cat > "$dir/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $IDENTITY
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF
  openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$dir/cert.cnf" -keyout "$dir/key.pem" -out "$dir/cert.pem" 2>/dev/null
  openssl pkcs12 -export -legacy -inkey "$dir/key.pem" -in "$dir/cert.pem" -out "$dir/id.p12" -passout "pass:$password"
  security import "$dir/id.p12" -k ~/Library/Keychains/login.keychain-db -P "$password" -T /usr/bin/codesign
  rm -rf "$dir"
}

rm -rf build
mkdir -p "$BUNDLE/Contents/MacOS"
swiftc -O Sources/*.swift -o "$BUNDLE/Contents/MacOS/$APP" -framework AppKit -framework IOKit -framework ServiceManagement
cp Info.plist "$BUNDLE/Contents/Info.plist"

security find-identity -p codesigning | grep -q "\"$IDENTITY\"" || make_identity
codesign --force --sign "$IDENTITY" "$BUNDLE"

if [[ "${1:-}" == "install" ]]; then
  pkill -x "$APP" || true
  rm -rf "/Applications/$APP.app"
  ditto "$BUNDLE" "/Applications/$APP.app"
  open "/Applications/$APP.app"
fi
