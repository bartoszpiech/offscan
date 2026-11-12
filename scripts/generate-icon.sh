#!/usr/bin/env bash
# Renders the Offscan app icon from code (Tools/AppIconGenerator, CoreGraphics only) into the
# asset catalog: light, dark and tinted 1024×1024 PNGs, plus a 180×180 preview for reviewers.
set -euo pipefail
cd "$(dirname "$0")/.."

ICONSET=FlatlyApp/Resources/Assets.xcassets/AppIcon.appiconset
PREVIEW=Tools/AppIconGenerator/preview.png

swift run -c release --package-path Tools/AppIconGenerator AppIconGenerator "$ICONSET" "$PREVIEW"
echo "✓ App icon written to $ICONSET (preview: $PREVIEW)"
