#!/usr/bin/env bash
# One command to get from a fresh clone to a runnable project.
set -euo pipefail
cd "$(dirname "$0")/.."

command -v xcodegen >/dev/null || brew install xcodegen
xcodegen generate

echo
echo "Generated SelahBeat.xcodeproj"
echo "  swift test                       # core + render-scheduler tests"
echo "  open SelahBeat.xcodeproj         # then run the SelahBeat-macOS scheme"
