#!/usr/bin/env bash

set -euo pipefail

keybinds_file="$HOME/.config/hypr/keys.lua"

[[ -r "$keybinds_file" ]] || {
  notify-send "Keybinds unavailable" "Could not read $keybinds_file"
  exit 1
}

wofi --show dmenu --prompt "Keybinds" < "$keybinds_file"
