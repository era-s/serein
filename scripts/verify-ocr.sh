#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
verification_dir="$(mktemp -d "${TMPDIR:-/tmp}/timetable-ocr.XXXXXX")"
trap 'rm -rf "$verification_dir"' EXIT
cd "$project_root"
mkdir -p artifacts
swiftc -parse-as-library \
  Sources/TimetableWallpaper/Models.swift \
  Sources/TimetableWallpaper/TimetableOCR.swift \
  scripts/verify-ocr.swift \
  -o "$verification_dir/verify-ocr"
"$verification_dir/verify-ocr" "$project_root/artifacts/ocr-fixture.png"
