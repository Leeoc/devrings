#!/bin/bash
# Builds a release zip from a tag: scripts/release.sh v1.2.0 → build/DevRings-1.2.0.zip
# Signed ad hoc: DevRings doesn't use Apple's Developer ID or notarisation. The Homebrew cask clears the
# quarantine flag after install; a manual download needs the same (see the README).
set -euo pipefail
cd "$(dirname "$0")/.."

tag=${1:?usage: scripts/release.sh v1.2.0}
version=${tag#v}
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Tag must look like v1.2.0, got $tag" >&2; exit 1; }

VERSION=$version SIGN_IDENTITY=- scripts/bundle.sh >/dev/null
zip=build/DevRings-$version.zip
rm -f "$zip"
ditto -c -k --keepParent build/DevRings.app "$zip"
echo "$zip"
shasum -a 256 "$zip" | cut -d' ' -f1
