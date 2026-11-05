#!/bin/bash
# Builds the app and zips it for a GitHub release at .build/Amnesia-<version>.zip.
set -euo pipefail

cd "$(dirname "$0")/.."

scripts/build-app.sh

version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
archive=".build/Amnesia-$version.zip"

# ditto keeps the bundle's structure and signature, which plain zip can break.
rm -f "$archive"
ditto -c -k --keepParent .build/Amnesia.app "$archive"

echo "Built $archive"
shasum -a 256 "$archive"
