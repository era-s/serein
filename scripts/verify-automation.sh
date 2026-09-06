#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
verification_dir="$(mktemp -d "${TMPDIR:-/tmp}/serein-automation.XXXXXX")"
trap 'rm -rf "$verification_dir"' EXIT

swiftc \
  "$project_root/Sources/TimetableWallpaper/Models.swift" \
  "$project_root/Sources/TimetableWallpaper/CalendarModels.swift" \
  "$project_root/Sources/TimetableWallpaper/CalendarEventConverter.swift" \
  "$project_root/Sources/TimetableWallpaper/AutomationModels.swift" \
  "$project_root/Sources/TimetableWallpaper/SavedStudio.swift" \
  "$project_root/Sources/TimetableWallpaper/WallpaperAutomation.swift" \
  "$project_root/scripts/verify-automation.swift" \
  -o "$verification_dir/verify-automation"
"$verification_dir/verify-automation"
