#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
verification_dir="$(mktemp -d "${TMPDIR:-/tmp}/serein-spaces.XXXXXX")"
trap 'rm -rf "$verification_dir"' EXIT

swiftc \
  "$project_root/Sources/TimetableWallpaper/WallpaperSpaceStore.swift" \
  "$project_root/Sources/TimetableWallpaper/WallpaperStoreWriter.swift" \
  "$project_root/scripts/verify-spaces.swift" \
  -o "$verification_dir/verify-spaces"
"$verification_dir/verify-spaces"
