#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_PATH="${POCKET_WORLD_DERIVED_DATA:-${PROJECT_ROOT}/.build}"
SIMULATOR_UDID="${POCKET_WORLD_SIMULATOR_UDID:-}"

if [[ -z "$SIMULATOR_UDID" ]]; then
  SIMULATOR_UDID="$(xcrun simctl list devices available --json | python3 -c '
import json, sys
devices = [device for runtime, group in json.load(sys.stdin)["devices"].items()
           if ".iOS-" in runtime for device in group
           if device.get("isAvailable") and device["name"].startswith("iPhone")]
chosen = next((device for device in devices if device["state"] == "Booted"),
              devices[0] if devices else None)
if chosen is None:
    sys.exit("No iPhone simulator is installed. Add an iOS runtime and iPhone in Xcode, then retry.")
print(chosen["udid"])
')"
fi

# The shared Xcode project is committed; running the app needs no Ruby gems.
xcodebuild \
  -project "$PROJECT_ROOT/PocketWorld.xcodeproj" \
  -scheme PocketWorld \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination "id=$SIMULATOR_UDID" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGN_IDENTITY=- \
  build

APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug-iphonesimulator/PocketWorld.app"
xcrun simctl bootstatus "$SIMULATOR_UDID" -b
xcrun simctl install "$SIMULATOR_UDID" "$APP_PATH"
open -a Simulator --args -CurrentDeviceUDID "$SIMULATOR_UDID"
xcrun simctl launch --terminate-running-process "$SIMULATOR_UDID" com.pocketworld.demo
