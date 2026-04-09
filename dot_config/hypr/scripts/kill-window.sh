#!/usr/bin/env bash

set -u

notify() {
  notify-send \
    -a "Hyprland" \
    -h string:x-canonical-private-synchronous:hypr-kill-window \
    "$@"
}

socket2="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr/${HYPRLAND_INSTANCE_SIGNATURE:-}/.socket2.sock"
event_file="$(mktemp)"
listener_pid=""

cleanup() {
  if [[ -n "$listener_pid" ]]; then
    kill "$listener_pid" >/dev/null 2>&1 || true
    wait "$listener_pid" 2>/dev/null || true
  fi

  rm -f "$event_file"
}

trap cleanup EXIT

notify "Kill window" "Select the window to close"

if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" && -S "$socket2" ]] && command -v python3 >/dev/null 2>&1; then
  timeout 30s python3 - "$socket2" >"$event_file" <<'PY' &
import socket
import sys

sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock.connect(sys.argv[1])

buffer = ""

while True:
    chunk = sock.recv(4096)
    if not chunk:
        break

    buffer += chunk.decode("utf-8", errors="replace")

    while "\n" in buffer:
        line, buffer = buffer.split("\n", 1)
        if line.startswith("closewindow>>"):
            print(line.split(">>", 1)[1])
            sys.exit(0)

sys.exit(1)
PY
  listener_pid=$!

  # Give the event listener a moment to connect before entering kill mode.
  sleep 0.1
fi

output="$(hyprctl kill 2>&1)"
status=$?

output="$(
  printf '%s\n' "$output" | sed '/^[[:space:]]*$/d'
)"

if [[ $status -ne 0 ]]; then
  if [[ -n "$output" ]]; then
    notify "Kill failed" "$output"
  else
    notify "Kill failed" "Could not enter kill mode"
  fi
  exit 1
fi

if [[ -n "$listener_pid" ]]; then
  wait "$listener_pid"
fi

if [[ -s "$event_file" ]]; then
  notify "Window killed" "Selected window was closed"
elif [[ -n "$output" && "$output" != "ok" ]]; then
  notify "Kill failed" "$output"
else
  notify "Kill failed" "No window was killed"
fi
