#!/usr/bin/env bash

set -uo pipefail

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/hypr"
STATE_FILE="$STATE_DIR/gaming-mode"

notify() {
    local title="$1"
    local body="${2:-}"

    if command -v notify-send >/dev/null 2>&1; then
        notify-send "$title" "$body"
    fi
}

json_escape() {
    local value="$1"
    value=${value//\\/\\\\}
    value=${value//\"/\\\"}
    value=${value//$'\n'/ }
    printf '%s' "$value"
}

is_enabled() {
    [[ -f "$STATE_FILE" ]] && [[ "$(cat "$STATE_FILE" 2>/dev/null)" == "on" ]]
}

status() {
    if is_enabled; then
        printf '{"text":"","tooltip":"%s","class":"on"}\n' "$(json_escape "Gaming mode: on")"
    else
        printf '{"text":"","tooltip":"%s","class":"off"}\n' "$(json_escape "Gaming mode: off")"
    fi
}

apply_gaming() {
    # `hyprctl keyword` only works with the legacy Hyprlang provider.  The
    # active config is Lua, so apply the runtime override through `eval`.
    hyprctl eval 'hl.config({
        animations = { enabled = false },
        decoration = {
            blur = { enabled = false },
            shadow = { enabled = false },
            active_opacity = 1.0,
            inactive_opacity = 1.0,
            rounding = 0,
        },
        general = { gaps_in = 0, gaps_out = 0, border_size = 1 },
    })' >/dev/null
}

apply_normal() {
    # The source of truth is hyprland.lua.  Reload it instead of duplicating
    # its defaults here, so future Lua config changes are restored correctly.
    hyprctl reload >/dev/null
}

set_mode() {
    local mode="$1"

    if ! command -v hyprctl >/dev/null 2>&1; then
        notify "Gaming mode unavailable" "hyprctl was not found."
        return 1
    fi

    if [[ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
        notify "Gaming mode unavailable" "This does not look like a Hyprland session."
        return 1
    fi

    mkdir -p "$STATE_DIR"

    if [[ "$mode" == "on" ]] && apply_gaming; then
        printf 'on\n' > "$STATE_FILE"
        notify "Gaming mode enabled" "Animations, blur, shadows, gaps, and rounding are disabled."
        return 0
    fi

    if [[ "$mode" == "off" ]] && apply_normal; then
        printf 'off\n' > "$STATE_FILE"
        notify "Gaming mode disabled" "Settings restored from hyprland.lua."
        return 0
    fi

    notify "Gaming mode failed" "Could not apply Hyprland settings."
    return 1
}

case "${1:-toggle}" in
    status)
        status
        ;;
    on)
        set_mode on
        ;;
    off)
        set_mode off
        ;;
    toggle)
        if is_enabled; then
            set_mode off
        else
            set_mode on
        fi
        ;;
    *)
        printf 'Usage: %s [toggle|on|off|status]\n' "$0" >&2
        exit 2
        ;;
esac
