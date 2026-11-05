#!/bin/bash
# Regenerates Resources/AppIcon.icns from scripts/generate-icon.swift.
set -euo pipefail

cd "$(dirname "$0")/.."

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

swift scripts/generate-icon.swift "$work/icon.png"

iconset="$work/AppIcon.iconset"
mkdir "$iconset"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$work/icon.png" --out "$iconset/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$work/icon.png" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil --convert icns "$iconset" --output Resources/AppIcon.icns
echo "Built Resources/AppIcon.icns"
