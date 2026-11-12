#!/usr/bin/env bash
# Screenshots of every main screen, taken by FlatlyUITests/ScreenshotTests on an iPhone simulator
# with the DEBUG demo library (FLATLY_DEMO_DATA=1). Needs Xcode (not just the Command Line Tools)
# and XcodeGen. Used by the "screenshots" job in .github/workflows/ios-build.yml; works the same
# on a Mac with Xcode.
#
#   scripts/ui-screenshots.sh build   generate the project if missing, boot a simulator, build for testing
#   scripts/ui-screenshots.sh shoot   run ScreenshotTests once per variant and export the PNGs
#   scripts/ui-screenshots.sh smoke   run the FlatlyUITests smoke tests once
#   scripts/ui-screenshots.sh all     build + shoot (the default)
#
# A variant is <lang>-<appearance>: the language reaches the tests as FLATLY_SCREENSHOT_LANG
# (xcodebuild forwards TEST_RUNNER_FLATLY_SCREENSHOT_LANG), the appearance is set on the simulator.
#
# Environment:
#   VARIANTS        default "en-light en-dark pl-light"
#   OUT_DIR         default build/screenshots: png/<lang>-<appearance>-<NN-screen>.png, failures/
#                   (screenshots XCTest took of failing tests), results/*.xcresult, logs/
#   DERIVED_DATA    default build/DerivedData
#   SIMULATOR_UDID  default: newest iOS runtime, preferring the newest "iPhone NN Pro"
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${OUT_DIR:-build/screenshots}"
DERIVED="${DERIVED_DATA:-build/DerivedData}"
VARIANTS="${VARIANTS:-en-light en-dark pl-light}"
FLOW_TESTS="${FLOW_TESTS:-test17LibrarySelectAndMerge test19LibraryBulkDelete test06bFilterApplyToAll test21EditorLargeText test13bDocumentMoreMenu test20StartupError test20bStartupErrorLargeText test15bCameraScannedPages test15cCameraFinishFromPagesSheet}"
SCHEME=FlatlyUITests
UDID_FILE="$OUT/simulator-udid"
mkdir -p "$OUT/logs"

# Prints "<udid>\t<name>\t<runtime>" of the simulator to use.
pick_simulator() {
  xcrun simctl list devices available -j | python3 -c '
import json, re, sys
data = json.load(sys.stdin)
best = None
for runtime, devices in data.get("devices", {}).items():
    m = re.search(r"iOS-(\d+)-(\d+)", runtime)
    if not m:
        continue
    version = (int(m.group(1)), int(m.group(2)))
    for device in devices:
        name = device.get("name", "")
        if not name.startswith("iPhone") or not device.get("isAvailable", True):
            continue
        pro = re.fullmatch(r"iPhone (\d+) Pro", name)
        kind = 2 if pro else (1 if re.fullmatch(r"iPhone (\d+)", name) else 0)
        rank = (version, kind, int(pro.group(1)) if pro else 0)
        if best is None or rank > best[0]:
            best = (rank, device["udid"], name, runtime)
if best is None:
    sys.exit("No available iPhone simulator found (xcrun simctl list devices available).")
print(f"{best[1]}\t{best[2]}\t{best[3]}")
'
}

simulator_udid() {
  if [[ -n "${SIMULATOR_UDID:-}" ]]; then
    echo "$SIMULATOR_UDID"
  elif [[ -s "$UDID_FILE" ]]; then
    cat "$UDID_FILE"
  else
    local picked
    picked="$(pick_simulator)"
    echo "Simulator: $(echo "$picked" | cut -f2) ($(echo "$picked" | cut -f3))" >&2
    echo "$picked" | cut -f1 | tee "$UDID_FILE"
  fi
}

boot_simulator() {
  local udid=$1
  xcrun simctl boot "$udid" 2>/dev/null || true
  xcrun simctl bootstatus "$udid" -b >/dev/null
  # A tidy status bar: 9:41, full signal and battery.
  xcrun simctl status_bar "$udid" override --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100 || true
}

# run_logged <log file> <egrep filter> <command…>: runs the command with its full output in the log,
# streams the lines matching the filter, and returns the command's exit status.
run_logged() {
  local log=$1 filter=$2
  shift 2
  set +e
  "$@" 2>&1 | tee "$log" | grep --line-buffered -E "$filter"
  local status=${PIPESTATUS[0]}
  set -e
  return "$status"
}

# Sets UDID (booting the simulator) and the xcodebuild arguments shared by every action.
UDID=""
XCODEBUILD_ARGS=()
TEST_FLAGS=()
prepare() {
  UDID="$(simulator_udid)"
  boot_simulator "$UDID"
  XCODEBUILD_ARGS=(-project Flatly.xcodeproj -scheme "$SCHEME" -destination "id=$UDID" -derivedDataPath "$DERIVED")
  TEST_FLAGS=(-parallel-testing-enabled NO -test-timeouts-enabled YES -default-test-execution-time-allowance 120)
  # Skip the slow diagnostics collection after a failure when this Xcode can turn it off.
  if xcodebuild -help 2>&1 | grep -q -- "-collect-test-diagnostics"; then
    TEST_FLAGS+=(-collect-test-diagnostics never)
  fi
}

build() {
  [[ -d Flatly.xcodeproj ]] || scripts/generate-project.sh
  prepare
  run_logged "$OUT/logs/build.log" "error:|warning: .*FlatlyApp|\*\* .* \*\*" \
    xcodebuild build-for-testing "${XCODEBUILD_ARGS[@]}" COMPILER_INDEX_STORE_ENABLE=NO \
    || { echo "::error::build-for-testing failed (see $OUT/logs/build.log)"; grep -E "error:" "$OUT/logs/build.log" | sort -u | head -40; exit 1; }
}

# Exports the attachments of a result bundle and copies the screenshots to png/<prefix>-<name>.png
# (and screenshots of failures to failures/). Prints how many screenshots were exported.
export_screenshots() {
  local result=$1 prefix=$2
  local raw="$OUT/attachments/$prefix"
  rm -rf "$raw" && mkdir -p "$raw" "$OUT/png" "$OUT/failures"
  xcrun xcresulttool export attachments --path "$result" --output-path "$raw" >/dev/null
  python3 - "$raw" "$OUT" "$prefix" <<'PY'
import json, pathlib, re, shutil, sys

raw, out, prefix = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), sys.argv[3]
manifest_path = raw / "manifest.json"
if not manifest_path.exists():
    sys.exit(f"{manifest_path} is missing")
manifest = json.loads(manifest_path.read_text())

def attachments(node, test=""):
    """Yields (test identifier, attachment dict) for every exported attachment in the manifest."""
    if isinstance(node, list):
        for item in node:
            yield from attachments(item, test)
    elif isinstance(node, dict):
        test = node.get("testIdentifier", test)
        if "exportedFileName" in node:
            yield test, node
        for value in node.values():
            if isinstance(value, (list, dict)):
                yield from attachments(value, test)

screen = re.compile(r"^(\d{2}-[a-z0-9]+(?:-[a-z0-9]+)*)")
count = failures = 0
for test, attachment in attachments(manifest):
    source = raw / attachment["exportedFileName"]
    if not source.exists():
        continue
    name = attachment.get("suggestedHumanReadableName") or attachment.get("name") or source.name
    match = screen.match(name)
    if match:
        shutil.copyfile(source, out / "png" / f"{prefix}-{match.group(1)}{source.suffix or '.png'}")
        count += 1
    elif attachment.get("isAssociatedWithFailure") and source.suffix.lower() in (".png", ".jpg", ".jpeg", ".heic"):
        failures += 1
        test_name = re.sub(r"[^A-Za-z0-9]+", "-", test.split("/")[-1]).strip("-") or "test"
        shutil.copyfile(source, out / "failures" / f"{prefix}-{test_name}-{failures}{source.suffix}")
print(f"{prefix}: {count} screenshots" + (f", {failures} failure screenshots" if failures else ""))
if count == 0:
    print(json.dumps(manifest, indent=1)[:4000])
PY
}

shoot() {
  local failed=()
  prepare
  rm -rf "$OUT/png" "$OUT/failures"
  mkdir -p "$OUT/results"
  for variant in $VARIANTS; do
    local lang=${variant%%-*} appearance=${variant#*-}
    local result="$OUT/results/$variant.xcresult"
    echo "▸ $variant"
    xcrun simctl ui "$UDID" appearance "$appearance"
    rm -rf "$result"
    export TEST_RUNNER_FLATLY_SCREENSHOT_LANG="$lang"
    # Flow tests (select/merge, bulk delete and Recently Deleted, Apply to All, large text, menus,
    # startup error, the camera's Scanned Pages sheet and Finish from it) run in the first variant
    # only; the others shoot the main screens, which keeps the job short.
    local skip=()
    if [[ "$variant" != "${VARIANTS%% *}" ]]; then
      for t in $FLOW_TESTS; do skip+=(-skip-testing:FlatlyUITests/ScreenshotTests/$t); done
    fi
    run_logged "$OUT/logs/$variant.log" "Test Case .* (passed|failed)|error:|\*\* .* \*\*" \
      xcodebuild test-without-building "${XCODEBUILD_ARGS[@]}" "${TEST_FLAGS[@]}" \
      -only-testing:FlatlyUITests/ScreenshotTests ${skip[@]+"${skip[@]}"} -resultBundlePath "$result" \
      || failed+=("$variant")
    if [[ -d "$result" ]]; then export_screenshots "$result" "$variant"; else failed+=("$variant (no result bundle)"); fi
  done
  unset TEST_RUNNER_FLATLY_SCREENSHOT_LANG
  xcrun simctl ui "$UDID" appearance light
  local count
  count=$(find "$OUT/png" -name '*.png' 2>/dev/null | wc -l | tr -d ' ')
  echo "✓ $count screenshots in $OUT/png"
  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    {
      echo "### Screenshots ($count)"
      echo
      find "$OUT/png" -name '*.png' -exec basename {} \; | sort | sed 's/^/- /'
      if ((${#failed[@]})); then echo; echo "Failed variants: ${failed[*]}"; fi
    } >> "$GITHUB_STEP_SUMMARY"
  fi
  if ((${#failed[@]})); then
    echo "::error::Screenshot tests failed for: ${failed[*]}"
    return 1
  fi
}

smoke() {
  local result="$OUT/results/smoke.xcresult"
  prepare
  xcrun simctl ui "$UDID" appearance light
  mkdir -p "$OUT/results"
  rm -rf "$result"
  run_logged "$OUT/logs/smoke.log" "Test Case .* (passed|failed)|error:|\*\* .* \*\*" \
    xcodebuild test-without-building "${XCODEBUILD_ARGS[@]}" "${TEST_FLAGS[@]}" \
    -only-testing:FlatlyUITests/FlatlyUITests -resultBundlePath "$result"
}

case "${1:-all}" in
  build) build ;;
  shoot) shoot ;;
  smoke) smoke ;;
  all) build && shoot ;;
  *) echo "usage: $0 [build|shoot|smoke|all]" >&2; exit 2 ;;
esac
