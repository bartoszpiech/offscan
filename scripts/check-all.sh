#!/usr/bin/env bash
# Runs every verification available on this machine.
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/test-core.sh
scripts/typecheck-app.sh
scripts/check-localization.sh
# xcodebuild only copies the privacy manifest, so a malformed plist would slip through a build.
plutil -lint FlatlyApp/Resources/PrivacyInfo.xcprivacy
scripts/generate-project.sh
echo "✓ All checks passed"
