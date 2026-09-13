#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
render_dir="$(mktemp -d "${TMPDIR:-/tmp}/serein-gallery.XXXXXX")"
trap 'rm -rf "$render_dir"' EXIT
swiftc "$project_dir/Sources/TimetableWallpaper/Models.swift" \
  "$project_dir/Sources/TimetableWallpaper/WallpaperRenderer.swift" \
  "$project_dir/scripts/render-gallery.swift" -o "$render_dir/render-gallery"
"$render_dir/render-gallery" "${1:-$project_dir/docs/images}"
