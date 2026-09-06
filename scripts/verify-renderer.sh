#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
verification_dir="$(mktemp -d "${TMPDIR:-/tmp}/serein-renderer.XXXXXX")"
trap 'rm -rf "$verification_dir"' EXIT

swiftc \
  "$project_root/Sources/TimetableWallpaper/Models.swift" \
  "$project_root/Sources/TimetableWallpaper/WallpaperRenderer.swift" \
  "$project_root/scripts/verify-renderer.swift" \
  -o "$verification_dir/verify-renderer"
"$verification_dir/verify-renderer" "$@"
