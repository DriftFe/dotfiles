#!/usr/bin/env bash

set -euo pipefail

STYLE="$HOME/.config/wofi/power-menu.css"

show_menu() {
  printf '%s\n' \
    "Lock" \
    "Suspend" \
    "Log Out" \
    "Restart" \
    "Power Off" \
  | wofi \
      --dmenu \
      --prompt "Power" \
      --style "$STYLE" \
      --gtk-dark \
      --hide-search \
      --insensitive \
      --lines 5 \
      --width 420 \
      --location center
}

confirm_action() {
  local prompt="$1"
  local answer

  answer="$(
    printf '%s\n' "No" "Yes" \
    | wofi \
        --dmenu \
        --prompt "$prompt" \
        --style "$STYLE" \
        --gtk-dark \
        --hide-search \
        --insensitive \
        --lines 2 \
        --width 320 \
        --location center
  )"

  [[ "$answer" == "Yes" ]]
}

choice="$(show_menu)"

if [[ -z "${choice:-}" ]]; then
  exit 0
fi

case "$choice" in
  "Lock")
    exec hyprlock
    ;;
  "Suspend")
    if confirm_action "Suspend?"; then
      hyprlock &
      sleep 0.2
      exec systemctl suspend
    fi
    ;;
  "Log Out")
    if confirm_action "Log out?"; then
      exec hyprctl dispatch exit
    fi
    ;;
  "Restart")
    if confirm_action "Restart?"; then
      exec systemctl reboot
    fi
    ;;
  "Power Off")
    if confirm_action "Power off?"; then
      exec systemctl poweroff
    fi
    ;;
esac
