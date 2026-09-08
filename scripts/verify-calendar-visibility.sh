#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
verification_dir="$(mktemp -d "${TMPDIR:-/tmp}/serein-visibility.XXXXXX")"
trap 'rm -rf "$verification_dir"' EXIT

swiftc \
  "$project_root/Sources/TimetableWallpaper/Models.swift" \
  "$project_root/Sources/TimetableWallpaper/CalendarModels.swift" \
  "$project_root/Sources/TimetableWallpaper/CalendarEventConverter.swift" \
  "$project_root/Sources/TimetableWallpaper/CalendarVisibility.swift" \
  "$project_root/Sources/TimetableWallpaper/AutomationModels.swift" \
  "$project_root/Sources/TimetableWallpaper/SavedStudio.swift" \
  "$project_root/Sources/TimetableWallpaper/WeekdayHeaderDates.swift" \
  "$project_root/Sources/TimetableWallpaper/WallpaperAutomation.swift" \
  "$project_root/scripts/verify-calendar-visibility.swift" \
  -o "$verification_dir/verify-calendar-visibility"
"$verification_dir/verify-calendar-visibility"
