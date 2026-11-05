#!/bin/bash
# Builds the app and zips it for a GitHub release at .build/Amnesia-<version>.zip.
set -euo pipefail

cd "$(dirname "$0")/.."

scripts/build-app.sh

# Below SDK 26 macOS runs the app in compatibility mode, without Liquid Glass.
minimum_sdk=26
for arch in arm64 x86_64; do
    sdk=$(vtool -arch "$arch" -show-build .build/Amnesia.app/Contents/MacOS/Amnesia | awk '$1 == "sdk" {print $2}')
    if [ "${sdk%%.*}" -lt "$minimum_sdk" ]; then
        echo "error: $arch was built with SDK $sdk, but needs $minimum_sdk or later" >&2
        exit 1
    fi
done

version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
archive=".build/Amnesia-$version.zip"

# ditto keeps the bundle's structure and signature, which plain zip can break.
rm -f "$archive"
ditto -c -k --keepParent .build/Amnesia.app "$archive"

echo "Built $archive"
shasum -a 256 "$archive"
