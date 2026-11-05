#!/bin/bash
# Builds a release Amnesia.app bundle at .build/Amnesia.app.
set -euo pipefail

cd "$(dirname "$0")/.."

swift build -c release --product Amnesia
binary_dir=$(swift build -c release --show-bin-path)

app=.build/Amnesia.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$binary_dir/Amnesia" "$app/Contents/MacOS/Amnesia"
cp Resources/Info.plist "$app/Contents/Info.plist"

# Ad-hoc signature: enough to run locally, not notarized for distribution.
codesign --force --sign - "$app"

echo "Built $app"
