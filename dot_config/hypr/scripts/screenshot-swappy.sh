#!/usr/bin/env bash
set -euo pipefail

mode="${1:-area-save}"
screens_dir="$HOME/Pictures/Screenshots"
mkdir -p "$screens_dir"

timestamp="$(date +%Y%m%d_%H%M%S)"
out_file="$screens_dir/${timestamp}.png"
source_file=""
edit_file=""
auto_copy_succeeded="false"
area_timeout="20s"

cleanup() {
  if [[ -n "$source_file" && -f "$source_file" ]]; then
    rm -f "$source_file"
  fi
  if [[ -n "$edit_file" && -f "$edit_file" ]]; then
    rm -f "$edit_file"
  fi
}
trap cleanup EXIT

copy_image() {
  local image_path="$1"
  wl-copy --type image/png < "$image_path"
}

try_auto_copy() {
  local image_path="$1"

  [[ -s "$image_path" ]] || return 0

  if copy_image "$image_path"; then
    auto_copy_succeeded="true"
    notify-send "Screenshot copied" "Image copied to clipboard"
  fi
}

fallback_copy_if_needed() {
  local image_path="$1"
  local label="$2"

  [[ "$auto_copy_succeeded" == "true" ]] && return 0
  [[ -s "$image_path" ]] || return 0

  if copy_image "$image_path"; then
    auto_copy_succeeded="true"
    notify-send "Screenshot copied" "$label copied to clipboard (fallback)"
  fi
}

capture_to_file() {
  local target_path="$1"
  local capture_mode="$2"

  if [[ "$capture_mode" == "area" ]]; then
    capture_area > "$target_path"
  else
    capture_screen > "$target_path"
  fi
}

capture_area() {
  if ! timeout --kill-after=2s "$area_timeout" grimblast --freeze save area -; then
    pkill -u "$USER" -x slurp 2>/dev/null || true
    pkill -u "$USER" -x grimblast 2>/dev/null || true
    notify-send "Screenshot cancelled" "Area selection timed out or was interrupted"
    return 1
  fi
}

capture_screen() {
  grimblast save screen -
}

case "$mode" in
  clip)
    source_file="$(mktemp --suffix=.png /tmp/swappy-source-XXXXXX)"
    edit_file="$(mktemp --suffix=.png /tmp/swappy-edit-XXXXXX)"
    capture_to_file "$source_file" area
    try_auto_copy "$source_file"
    swappy -f "$source_file" -o "$edit_file"
    fallback_copy_if_needed "$edit_file" "Edited screenshot"
    ;;
  area-save)
    source_file="$(mktemp --suffix=.png /tmp/swappy-source-XXXXXX)"
    capture_to_file "$source_file" area
    try_auto_copy "$source_file"
    swappy -f "$source_file" -o "$out_file"
    fallback_copy_if_needed "$out_file" "$(basename "$out_file")"
    ;;
  screen-save)
    source_file="$(mktemp --suffix=.png /tmp/swappy-source-XXXXXX)"
    capture_to_file "$source_file" screen
    try_auto_copy "$source_file"
    swappy -f "$source_file" -o "$out_file"
    fallback_copy_if_needed "$out_file" "$(basename "$out_file")"
    ;;
  *)
    notify-send "Screenshot failed" "Unknown mode: $mode"
    exit 2
    ;;
esac
