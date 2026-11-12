#!/usr/bin/env bash
# Generates Flatly.xcodeproj from project.yml with XcodeGen.
# Override the bundle identifier with:  BUNDLE_ID_PREFIX=com.yourcompany.flatly scripts/generate-project.sh
set -euo pipefail
cd "$(dirname "$0")/.."
export BUNDLE_ID_PREFIX="${BUNDLE_ID_PREFIX:-com.example.flatly}"
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen not found. Install with: brew install xcodegen" >&2
  exit 1
fi
xcodegen generate --spec project.yml
echo "Generated Flatly.xcodeproj (bundle id: $BUNDLE_ID_PREFIX)"
