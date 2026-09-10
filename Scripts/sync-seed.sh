#!/usr/bin/env bash
# The catalog seed is authored once and consumed in three places. Keep them in
# step rather than letting them drift.
set -euo pipefail
cd "$(dirname "$0")/.."
cp server/catalog/seed-songs.json Catalog/seed-songs.json
cp server/catalog/seed-songs.json Sources/SelahBeatCore/Resources/seed-songs.json
echo "Seed synced to app bundle and Catalog/"
