#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
benchmark_dir="$(mktemp -d "${TMPDIR:-/tmp}/serein-renderer-benchmark.XXXXXX")"
trap 'rm -rf "$benchmark_dir"' EXIT
swiftc -O "$project_dir/Sources/TimetableWallpaper/Models.swift" \
  "$project_dir/Sources/TimetableWallpaper/WallpaperRenderer.swift" \
  "$project_dir/scripts/benchmark-renderer.swift" -o "$benchmark_dir/benchmark-renderer"
"$benchmark_dir/benchmark-renderer"
