#!/usr/bin/env bash

set -euo pipefail

clients_json="$(hyprctl clients -j)"

if echo "$clients_json" | jq -e '.[] | select(.class == "signal-radar")' >/dev/null; then
  address="$(echo "$clients_json" | jq -r '.[] | select(.class == "signal-radar") | .address' | head -n1)"
  if [[ -n "${address:-}" ]]; then
    hyprctl dispatch closewindow "address:${address}" >/dev/null
  fi
  exit 0
fi

python3 "$HOME/.config/hypr/scripts/signal-radar.py" >/dev/null 2>&1 &
