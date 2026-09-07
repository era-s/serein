#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
swift build -c release
binary_dir="$(swift build -c release --show-bin-path)"
app_dir="$project_dir/dist/Serein.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary_dir/TimetableWallpaper" "$app_dir/Contents/MacOS/Serein"
cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Serein</string>
<key>CFBundleIdentifier</key><string>studio.serein.wallpaper</string>
<key>CFBundleName</key><string>Serein</string>
<key>CFBundleDisplayName</key><string>Serein</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.3.2</string>
<key>CFBundleVersion</key><string>6</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSCalendarsFullAccessUsageDescription</key><string>선택한 캘린더의 주간 일정을 읽어 배경화면으로 만듭니다. Serein은 원본 일정을 추가, 수정 또는 삭제하지 않습니다.</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
swift scripts/make-icon.swift "$app_dir/Contents/Resources"
python3 scripts/sign-app.py "$app_dir"
printf 'Built: %s\n' "$app_dir"
