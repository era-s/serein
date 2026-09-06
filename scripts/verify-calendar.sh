#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
verification_dir="$(mktemp -d "${TMPDIR:-/tmp}/serein-calendar.XXXXXX")"
trap 'rm -rf "$verification_dir"' EXIT

swiftc \
  "$project_root/Sources/TimetableWallpaper/Models.swift" \
  "$project_root/Sources/TimetableWallpaper/CalendarModels.swift" \
  "$project_root/Sources/TimetableWallpaper/CalendarEventConverter.swift" \
  "$project_root/Sources/TimetableWallpaper/SystemCalendarService.swift" \
  "$project_root/Sources/TimetableWallpaper/CalendarImportModel.swift" \
  "$project_root/scripts/verify-calendar.swift" \
  -o "$verification_dir/verify-calendar"
"$verification_dir/verify-calendar"
