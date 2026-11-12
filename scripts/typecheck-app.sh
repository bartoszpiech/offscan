#!/usr/bin/env bash
# Type-checks FlatlyApp (and FlatlyUITests) against the Mac Catalyst SDK — the closest thing to an
# iOS build available without Xcode. Catches type errors, missing symbols, Swift 6 concurrency
# violations and availability mistakes in the SwiftUI/UIKit code.
#
# SwiftData's @Model macro plugin is not in the Command Line Tools toolchain, so
# FlatlyApp/Persistence/*.swift is swapped for Tools/Typecheck/PersistenceStubs.swift (same API).
#
# With Xcode installed you can also just build the FlatlyApp scheme instead.
set -euo pipefail
cd "$(dirname "$0")/.."

SDK_DIR=/Library/Developer/CommandLineTools/SDKs
if xcode-select -p 2>/dev/null | grep -q "Xcode.app"; then
  SDK_DIR="$(xcode-select -p)/Platforms/MacOSX.platform/Developer/SDKs"
fi
# Prefer the 26.x SDK: in the 27 SDK SwiftUI's @State became a macro whose plugin CLT lacks.
SDK=""
for cand in "$SDK_DIR"/MacOSX26.5.sdk "$SDK_DIR"/MacOSX26.sdk "$SDK_DIR"/MacOSX.sdk; do
  if [[ -d "$cand" ]]; then SDK="$cand"; break; fi
done
[[ -n "$SDK" ]] || { echo "No macOS SDK found in $SDK_DIR" >&2; exit 1; }

TOOLCHAIN="$(dirname "$(dirname "$(xcrun --find swift)")")"
PLUGINS="$TOOLCHAIN/lib/swift/host/plugins"
TARGET=arm64-apple-ios17.0-macabi
BUILD=.build/typecheck
mkdir -p "$BUILD"

COMMON=(
  -swift-version 6
  -target "$TARGET"
  -sdk "$SDK"
  -F "$SDK/System/iOSSupport/System/Library/Frameworks"
  -I "$SDK/System/iOSSupport/usr/lib/swift"
  -strict-concurrency=complete
  -parse-as-library
  -D DEBUG
)
for p in "$PLUGINS"/libObservationMacros.dylib "$PLUGINS"/libSwiftMacros.dylib; do
  [[ -f "$p" ]] && COMMON+=(-Xfrontend -load-plugin-library -Xfrontend "$p")
done

echo "▸ Emitting FlatlyCore module for $TARGET"
CORE_SOURCES=$(find FlatlyCore/Sources/FlatlyCore -name '*.swift' | sort)
# shellcheck disable=SC2086
xcrun swiftc "${COMMON[@]}" -module-name FlatlyCore -emit-module -emit-module-path "$BUILD/FlatlyCore.swiftmodule" $CORE_SOURCES

echo "▸ Type-checking FlatlyApp"
APP_SOURCES=$(find FlatlyApp -name '*.swift' -not -path 'FlatlyApp/Persistence/*' | sort)
# shellcheck disable=SC2086
xcrun swiftc "${COMMON[@]}" -I "$BUILD" -module-name FlatlyApp -typecheck $APP_SOURCES Tools/Typecheck/PersistenceStubs.swift

if ls FlatlyUITests/*.swift >/dev/null 2>&1; then
  echo "▸ Parsing FlatlyUITests (XCTest is not shipped with Command Line Tools; syntax check only)"
  xcrun swiftc -swift-version 6 -parse FlatlyUITests/*.swift
fi
echo "✓ Type-check passed"
