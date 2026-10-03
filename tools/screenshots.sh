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
  # Right after a reinstall the simulator sometimes doesn't know the app yet ("unknown to
  # FrontBoard"), so give the launch a few tries.
  for attempt in 1 2 3 4; do
    if SIMCTL_CHILD_FAIRYLAND_DEBUG="$flags" xcrun simctl launch "$SIM" "$BUNDLE" >/dev/null; then break; fi
    if [ "$attempt" = 4 ]; then echo "✗ couldn't launch for $name" >&2; exit 1; fi
    echo "  launch failed, retrying ($attempt)…"
    sleep 3
  done
  # Startup can take a long while on a CI simulator, and how long varies from run to run. The
  # white launch screen makes a tiny PNG (~70 KB) and anything the game draws a far bigger one,
  # so wait for the first real frame, then give the scene its own seconds to settle.
  start=$SECONDS
  sleep 3
  while :; do
    xcrun simctl io "$SIM" screenshot --type=png "$OUT/$name.png" >/dev/null 2>&1 || true
    size=$(stat -f%z "$OUT/$name.png" 2>/dev/null || echo 0)
    [ "$size" -gt 300000 ] && break
    if [ $((SECONDS - start)) -gt 150 ]; then echo "  still on the launch screen after 150 s"; break; fi
    sleep 3
  done
  echo "::notice::$name: first frame after $((SECONDS - start)) s"
  sleep "${wait:-8}"
  xcrun simctl io "$SIM" screenshot --type=png "$OUT/$name.png"
  # The simulator stays in portrait, so a landscape-locked app comes out sideways; turn it upright.
  if [[ ",$flags," == *",landscape,"* ]]; then sips -r 270 "$OUT/$name.png" >/dev/null; fi
done
