#!/usr/bin/env bash
# Builds and runs the FlatlyCore test suite (Swift Testing) on macOS.
#
# Works with full Xcode *and* with Command Line Tools only. With CLT the Swift Testing macro
# plugin is not auto-loaded and the test runner must be arm64 (not arm64e) or Vision's neural
# networks fail with an "Espresso" error; both workarounds are applied here.
#
# Usage: scripts/test-core.sh [extra swift test args, e.g. --filter OCRPipelineTests]
set -euo pipefail
cd "$(dirname "$0")/../FlatlyCore"

TOOLCHAIN="$(dirname "$(dirname "$(xcrun --find swift)")")"
PLUGIN="$TOOLCHAIN/lib/swift/host/plugins/testing/libTestingMacros.dylib"
EXTRA=()
if [[ -f "$PLUGIN" && "$TOOLCHAIN" == *CommandLineTools* ]]; then
  EXTRA+=(-Xswiftc -load-plugin-library -Xswiftc "$PLUGIN")
fi

if [[ "$(uname -m)" == "arm64" ]]; then
  exec arch -arm64 swift test ${EXTRA[@]+"${EXTRA[@]}"} "$@"
else
  exec swift test ${EXTRA[@]+"${EXTRA[@]}"} "$@"
fi
