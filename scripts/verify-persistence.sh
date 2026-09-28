#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
verification_dir="$(mktemp -d "${TMPDIR:-/tmp}/serein-persistence.XXXXXX")"
trap 'rm -rf "$verification_dir"' EXIT

swiftc -module-cache-path "$verification_dir/module-cache" \
  "$project_root/Sources/TimetableWallpaper/Models.swift" \
  "$project_root/Sources/TimetableWallpaper/CalendarVisibility.swift" \
  "$project_root/Sources/TimetableWallpaper/AutomationModels.swift" \
  "$project_root/Sources/TimetableWallpaper/SavedStudio.swift" \
  "$project_root/Sources/TimetableWallpaper/StudioPersistence.swift" \
  "$project_root/scripts/verify-persistence.swift" \
  -o "$verification_dir/verify-persistence"
"$verification_dir/verify-persistence"
