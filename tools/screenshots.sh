#!/bin/bash
# Launches the built app in a booted simulator once per scene and saves a screenshot of each.
# macOS only (needs Xcode). Used by .github/workflows/screenshots.yml; also works locally:
#
#   tools/screenshots.sh <simulator-udid> <path/to/Fairyland.app> <out-dir> [scenes-file] [only-these,names]
set -euo pipefail

SIM="$1"; APP="$2"; OUT="$3"; SCENES="${4:-tools/screenshots.txt}"; ONLY="${5:-}"
BUNDLE=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Info.plist")
mkdir -p "$OUT"

xcrun simctl install "$SIM" "$APP"
xcrun simctl status_bar "$SIM" override --time 9:41 --batteryState charged --batteryLevel 100 --cellularBars 4 || true

grep -vE '^\s*(#|$)' "$SCENES" | while IFS='|' read -r name flags wait; do
  name=$(echo "$name" | xargs); flags=$(echo "$flags" | xargs); wait=$(echo "$wait" | xargs)
  if [ -n "$ONLY" ] && [[ ",$ONLY," != *",$name,"* ]]; then continue; fi
  echo "▶ $name ($flags)"
  xcrun simctl terminate "$SIM" "$BUNDLE" 2>/dev/null || true
  # Fresh data for every scene, so the title screen never shows a leftover save.
  xcrun simctl uninstall "$SIM" "$BUNDLE" && xcrun simctl install "$SIM" "$APP"
  SIMCTL_CHILD_FAIRYLAND_DEBUG="$flags" xcrun simctl launch "$SIM" "$BUNDLE" >/dev/null
  sleep "${wait:-8}"
  xcrun simctl io "$SIM" screenshot --type=png "$OUT/$name.png"
  # The simulator stays in portrait, so a landscape-locked app comes out sideways; turn it upright.
  if [[ ",$flags," == *",landscape,"* ]]; then sips -r 270 "$OUT/$name.png" >/dev/null; fi
done
