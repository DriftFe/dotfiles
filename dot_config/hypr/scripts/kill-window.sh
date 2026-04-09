#!/usr/bin/env bash

set -u

notify() {
  notify-send -a "Hyprland" "$@"
}

notify "Kill window" "Select the window to close"

output="$(hyprctl kill 2>&1)"
status=$?

output="$(
  printf '%s\n' "$output" | sed '/^[[:space:]]*$/d'
)"

if [[ $status -eq 0 ]]; then
  if [[ -n "$output" && "$output" != "ok" ]]; then
    notify "Window killed" "$output"
  else
    notify "Window killed" "Selected window was closed"
  fi
else
  if [[ -n "$output" ]]; then
    notify "Kill failed" "$output"
  else
    notify "Kill failed" "No window was closed"
  fi
fi
