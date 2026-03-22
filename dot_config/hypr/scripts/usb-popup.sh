#!/usr/bin/env bash

set -euo pipefail

open_path() {
  local path="$1"

  if command -v nautilus >/dev/null 2>&1; then
    nautilus "$path" >/dev/null 2>&1 &
  elif command -v thunar >/dev/null 2>&1; then
    thunar "$path" >/dev/null 2>&1 &
  fi
}

device_label() {
  local dev="$1"
  local label model size

  label="$(lsblk -no LABEL "$dev" 2>/dev/null | head -n1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  model="$(lsblk -no MODEL "$dev" 2>/dev/null | head -n1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  size="$(lsblk -no SIZE "$dev" 2>/dev/null | head -n1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

  if [[ -n "$label" ]]; then
    printf '%s (%s)' "$label" "$size"
  elif [[ -n "$model" ]]; then
    printf '%s (%s)' "$model" "$size"
  else
    printf '%s' "$dev"
  fi
}

handle_event() {
  local action="${1:-}"
  local devname="${2:-}"
  local devtype="${3:-}"

  [[ "$action" == "add" ]] || return 0
  [[ -n "$devname" ]] || return 0
  [[ -b "$devname" ]] || return 0
  [[ "$devtype" == "partition" || "$devtype" == "disk" ]] || return 0

  local base_dev="$devname"
  local pkname trans rm hotplug fstype mountpoint title choice mounted

  pkname="$(lsblk -no PKNAME "$devname" 2>/dev/null | head -n1 | tr -d ' ')"
  if [[ -n "$pkname" ]]; then
    base_dev="/dev/$pkname"
  fi

  trans="$(lsblk -no TRAN "$base_dev" 2>/dev/null | head -n1 | tr -d ' ')"
  rm="$(lsblk -no RM "$base_dev" 2>/dev/null | head -n1 | tr -d ' ')"
  hotplug="$(lsblk -no HOTPLUG "$base_dev" 2>/dev/null | head -n1 | tr -d ' ')"

  if [[ "$trans" != "usb" && "$rm" != "1" && "$hotplug" != "1" ]]; then
    return 0
  fi

  fstype="$(lsblk -no FSTYPE "$devname" 2>/dev/null | head -n1 | tr -d ' ')"
  mountpoint="$(lsblk -no MOUNTPOINT "$devname" 2>/dev/null | head -n1)"
  title="$(device_label "$devname")"

  if [[ -z "$fstype" ]]; then
    notify-send "USB connected" "$title detected"
    return 0
  fi

  if [[ -n "$mountpoint" ]]; then
    notify-send "USB ready" "$title mounted at $mountpoint"
    choice="$(printf 'Open\nIgnore\n' | wofi --dmenu --prompt "USB: $title")"
    if [[ "$choice" == "Open" ]]; then
      open_path "$mountpoint"
    fi
    return 0
  fi

  notify-send "USB connected" "$title detected"
  choice="$(printf 'Mount and open\nMount only\nIgnore\n' | wofi --dmenu --prompt "USB: $title")"

  case "$choice" in
    "Mount and open"|"Mount only")
      if mounted="$(udisksctl mount -b "$devname" 2>/dev/null)"; then
        mountpoint="$(lsblk -no MOUNTPOINT "$devname" 2>/dev/null | head -n1)"
        notify-send "USB mounted" "${mounted}"
        if [[ "$choice" == "Mount and open" && -n "$mountpoint" ]]; then
          open_path "$mountpoint"
        fi
      else
        notify-send "USB mount failed" "Could not mount $devname"
      fi
      ;;
  esac
}

current_action=""
current_devname=""
current_devtype=""

udevadm monitor --udev --subsystem-match=block --property 2>/dev/null | while IFS= read -r line; do
  if [[ -z "$line" ]]; then
    handle_event "$current_action" "$current_devname" "$current_devtype"
    current_action=""
    current_devname=""
    current_devtype=""
    continue
  fi

  case "$line" in
    UDEV*|KERNEL*)
      continue
      ;;
    ACTION=*)
      current_action="${line#ACTION=}"
      ;;
    DEVNAME=*)
      current_devname="${line#DEVNAME=}"
      ;;
    DEVTYPE=*)
      current_devtype="${line#DEVTYPE=}"
      ;;
  esac
done
