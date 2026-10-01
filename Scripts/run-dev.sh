#!/usr/bin/env bash
#
# Build and launch the Mac app in Debug.
#
#   ./Scripts/run-dev.sh            # build and run
#   ./Scripts/run-dev.sh --audio    # run the audio check instead
#
# The running app holds Sparkle.framework open, so the old copy is killed and
# removed first - otherwise the build fails with "Operation not permitted".
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ "${1:-}" == "--audio" ]]; then
  exec swift run AudioCheck
fi

pkill -9 -x SelahBeat 2>/dev/null || true
rm -rf build/dev/Build/Products/Debug/SelahBeat.app

xcodebuild -project SelahBeat.xcodeproj -scheme SelahBeat-macOS \
  -configuration Debug -derivedDataPath build/dev build \
  | grep -E "error:|warning: (unused|never)|BUILD (SUCCEEDED|FAILED)" || true

open build/dev/Build/Products/Debug/SelahBeat.app
echo "SelahBeat launched"
