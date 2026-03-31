#!/usr/bin/env bash

set -euo pipefail

LAYOUT="$HOME/.config/wlogout/layout"
STYLE="$HOME/.config/wlogout/style.css"

if pgrep -x wlogout >/dev/null; then
  pkill -x wlogout
  exit 0
fi

exec wlogout \
  --layout "$LAYOUT" \
  --css "$STYLE" \
  --protocol layer-shell \
  --buttons-per-row 5 \
  --column-spacing 24 \
  --row-spacing 24 \
  --margin 0
