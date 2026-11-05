#!/bin/bash
# Builds a universal release Amnesia.app bundle at .build/Amnesia.app.
set -euo pipefail

cd "$(dirname "$0")/.."

build_flags=(-c release --arch arm64 --arch x86_64)
swift build "${build_flags[@]}" --product Amnesia
binary_dir=$(swift build "${build_flags[@]}" --show-bin-path)

app=.build/Amnesia.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary_dir/Amnesia" "$app/Contents/MacOS/Amnesia"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"

# SwiftPM records the deployment target as the SDK version, which makes macOS
# run the app in compatibility mode with the old design. Record the real SDK so
# it gets the current system appearance.
minimum_system=$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' Resources/Info.plist)
vtool -set-build-version macos "$minimum_system" "$(xcrun --show-sdk-version)" -replace \
    -output "$app/Contents/MacOS/Amnesia" "$app/Contents/MacOS/Amnesia" 2>/dev/null

# Ad-hoc signature: enough to run locally, not notarized for distribution.
codesign --force --sign - "$app"

echo "Built $app"
