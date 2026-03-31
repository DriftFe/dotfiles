#!/usr/bin/env bash

set -euo pipefail

LAYOUT="$HOME/.config/wlogout/layout"
STYLE="$HOME/.config/wlogout/style.css"

export XDG_SESSION_TYPE=wayland
export GDK_BACKEND=wayland

if [[ -z "${WAYLAND_DISPLAY:-}" ]] && [[ -n "${XDG_RUNTIME_DIR:-}" ]]; then
  socket="$(find "$XDG_RUNTIME_DIR" -maxdepth 1 -type s -name 'wayland-*' | head -n 1)"
  if [[ -n "${socket:-}" ]]; then
    export WAYLAND_DISPLAY="${socket##*/}"
  fi
fi

if pgrep -x wlogout >/dev/null; then
  pkill -x wlogout
  exit 0
fi

exec wlogout \
  -l "$LAYOUT" \
  -C "$STYLE" \
  -p layer-shell \
  -b 5 \
  -c 12 \
  -r 12 \
  -m 290
