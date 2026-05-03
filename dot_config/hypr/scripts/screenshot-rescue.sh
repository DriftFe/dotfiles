#!/usr/bin/env bash
set -euo pipefail

killed="false"

for process_name in slurp grimblast hyprpicker; do
  if pkill -u "$USER" -x "$process_name" 2>/dev/null; then
    killed="true"
  fi
done

if [[ "$killed" == "true" ]]; then
  notify-send "Screenshot cancelled" "Area selection helpers were stopped"
fi
