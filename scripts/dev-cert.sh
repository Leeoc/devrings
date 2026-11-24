#!/bin/bash
# Creates a self-signed "DevRings Dev" code signing certificate in the login keychain, once.
# bundle.sh signs with it, so every local build keeps the same identity and the Keychain's
# "Always Allow" for DevRings' tokens survives rebuilds. Ad hoc signatures change on every build.
set -euo pipefail

name="DevRings Dev"
if security find-certificate -c "$name" >/dev/null 2>&1; then
    echo "\"$name\" is already in your keychain."
    exit 0
fi

dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
# The system LibreSSL writes a PKCS#12 that `security import` reads; Homebrew's OpenSSL 3+ needs -legacy for that.
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -subj "/CN=$name" \
    -keyout "$dir/key.pem" -out "$dir/cert.pem" \
    -addext "keyUsage=critical,digitalSignature" -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null
/usr/bin/openssl pkcs12 -export -inkey "$dir/key.pem" -in "$dir/cert.pem" -name "$name" \
    -out "$dir/cert.p12" -passout pass:devrings
security import "$dir/cert.p12" -k "$HOME/Library/Keychains/login.keychain-db" -P devrings -T /usr/bin/codesign
echo "Added \"$name\". Rebuild with scripts/bundle.sh, then click Always Allow once when DevRings asks for its tokens."
