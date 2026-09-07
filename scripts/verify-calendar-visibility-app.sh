#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
verification_dir="$(mktemp -d "${TMPDIR:-/tmp}/serein-visibility-app.XXXXXX")"
studio_file="$HOME/Library/Application Support/Serein/studio.json"
temporary_user_dir="$(getconf DARWIN_USER_TEMP_DIR)"
demo_file="${temporary_user_dir%/}/serein-automation-demo.png"
demo_existed=false
if [[ -L "$demo_file" || ( -e "$demo_file" && ! -f "$demo_file" ) ]]; then
  printf 'Refusing to overwrite a non-regular demo output file.\n' >&2
  rm -rf "$verification_dir"
  exit 1
fi
if [[ -f "$demo_file" ]]; then
  cp -p "$demo_file" "$verification_dir/original-demo.png"
  demo_existed=true
fi

studio_hash() {
  if [[ -f "$studio_file" ]]; then
    shasum -a 256 "$studio_file" | awk '{print $1}'
  else
    printf 'absent\n'
  fi
}

studio_before="$(studio_hash)"
cleanup() {
  local result=$?
  trap - EXIT
  local studio_after
  studio_after="$(studio_hash)"
  if [[ "$studio_before" != "$studio_after" ]]; then
    printf 'FAIL: The personal studio.json changed during verification.\n' >&2
    result=1
  elif [[ "$result" == 0 ]]; then
    printf 'Verified personal studio.json SHA-256 is unchanged.\n'
  fi
  if [[ "$demo_existed" == true ]]; then
    cp -p "$verification_dir/original-demo.png" "$demo_file"
  else
    rm -f "$demo_file"
  fi
  rm -rf "$verification_dir"
  exit "$result"
}
trap cleanup EXIT

source_files=()
for source in "$project_root"/Sources/TimetableWallpaper/*.swift; do
  # Keep every real app component, replacing only its native scene entry point.
  if [[ "$(basename "$source")" != "WallpaperApp.swift" ]]; then
    source_files+=("$source")
  fi
done

swiftc -parse-as-library "${source_files[@]}" \
  "$project_root/scripts/verify-calendar-visibility-app.swift" \
  -o "$verification_dir/verify-calendar-visibility-app"
SEREIN_VERIFICATION_TEMP_DIR="$temporary_user_dir" TZ="Asia/Seoul" \
  "$verification_dir/verify-calendar-visibility-app" --automation-demo
