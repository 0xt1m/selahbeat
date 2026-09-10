#!/usr/bin/env bash
#
# Adds the Sparkle auto-updater to the macOS target.
#
# It ships disabled because resolving a remote SwiftPM package needs network
# access that a sandboxed/headless shell may not have — with it enabled, an
# unresolvable package hangs `xcodebuild` at "Resolve Package Graph" with no
# error. Run this once from a normal terminal on your own machine.
#
# The Swift code already handles both states: SparkleUpdaterController is
# guarded by `#if canImport(Sparkle)`, so the app builds and runs either way.
# Without Sparkle you still get the in-app "new version available" banner via
# the GitHub Releases API; with it you get one-click download-and-install.
set -euo pipefail
cd "$(dirname "$0")/.."

if grep -q "sparkle-project/Sparkle" project.yml; then
  echo "Sparkle is already enabled in project.yml"
else
  python3 - <<'PY'
p = 'project.yml'
s = open(p).read()
s = s.replace("""packages:
""", """packages:
  Sparkle:
    url: https://github.com/sparkle-project/Sparkle
    from: "2.6.0"
""", 1)
s = s.replace("""    dependencies:
      - package: SelahBeatCore
        product: SelahBeatUI
      - package: Sparkle""", """    dependencies:
      - package: SelahBeatCore
        product: SelahBeatUI
      - package: Sparkle""")
# Attach Sparkle to the macOS target only.
s = s.replace("""  SelahBeat-iOS:""", """  SelahBeat-iOS:""")
marker = """    dependencies:
      - package: SelahBeatCore
        product: SelahBeatUI
      - package: Sparkle
        product: Sparkle"""
if marker not in s:
    s = s.replace("""      - package: SelahBeatCore
        product: SelahBeatUI

  SelahBeat-iOS:""", """      - package: SelahBeatCore
        product: SelahBeatUI
      - package: Sparkle
        product: Sparkle

  SelahBeat-iOS:""", 1)
open(p, 'w').write(s)
PY
  echo "Added Sparkle to project.yml (macOS target only)"
fi

xcodegen generate
echo
echo "Now resolve the package once (this needs network access):"
echo "  xcodebuild -resolvePackageDependencies -project SelahBeat.xcodeproj -scheme SelahBeat-macOS"
echo
echo "Then set SUPublicEDKey in Apps/macOS/Info.plist to your Sparkle public key."
echo "Generate the keypair with Sparkle's bin/generate_keys and BACK UP the private key —"
echo "losing it means no installed copy can ever update again."
