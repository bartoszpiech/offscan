#!/usr/bin/env bash
# Renders the synthetic photo fixtures from code (Tools/FixtureGenerator): invented documents
# "photographed" on a desk through a pinhole camera, written as HEIC with a 26 mm EXIF focal
# length, plus TestFixtures/expected.json with the words OCR must find on each.
set -euo pipefail
cd "$(dirname "$0")/.."

swift run -c release --package-path Tools/FixtureGenerator FixtureGenerator TestFixtures
echo "✓ Fixtures written to TestFixtures"
