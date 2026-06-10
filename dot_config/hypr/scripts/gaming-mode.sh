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

apply_keyword() {
    local key="$1"
    local value="$2"

    hyprctl keyword "$key" "$value" >/dev/null
}

apply_gaming() {
    apply_keyword animations:enabled false
    apply_keyword decoration:blur:enabled false
    apply_keyword decoration:shadow:enabled false
    apply_keyword decoration:active_opacity 1.0
    apply_keyword decoration:inactive_opacity 1.0
    apply_keyword decoration:rounding 0
    apply_keyword general:gaps_in 0
    apply_keyword general:gaps_out 0
    apply_keyword general:border_size 1
}

apply_normal() {
    apply_keyword animations:enabled "yes, please :)"
    apply_keyword decoration:blur:enabled true
    apply_keyword decoration:shadow:enabled true
    apply_keyword decoration:active_opacity 0.9
    apply_keyword decoration:inactive_opacity 0.8
    apply_keyword decoration:rounding 10
    apply_keyword general:gaps_in 5
    apply_keyword general:gaps_out 10
    apply_keyword general:border_size 2
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

    if [[ "$mode" == "on" ]]; then
        if apply_gaming; then
            printf 'on\n' > "$STATE_FILE"
            notify "Gaming mode enabled" "Hyprland effects are disabled."
            return 0
        fi
    else
        if apply_normal; then
            printf 'off\n' > "$STATE_FILE"
            notify "Gaming mode disabled" "Hyprland effects are restored."
            return 0
        fi
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
