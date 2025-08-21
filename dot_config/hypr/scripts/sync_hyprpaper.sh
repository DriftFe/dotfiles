#!/usr/bin/env bash
# Sync Waypaper wallpaper into Hyprpaper using hyprctl

WAYPAPER_INI="$HOME/.config/waypaper/config.ini"

if [ ! -f "$WAYPAPER_INI" ]; then
    echo "[!] Waypaper INI config not found at $WAYPAPER_INI"
    exit 1
fi

# Extract wallpaper path
WP_FILE=$(grep -E '^wallpaper *= *' "$WAYPAPER_INI" | sed -E 's/^wallpaper *= *//')
WP_FILE=$(eval echo "$WP_FILE")

if [ ! -f "$WP_FILE" ]; then
    echo "[!] Wallpaper file not found: $WP_FILE"
    exit 1
fi

# Get first monitor name
MONITOR=$(hyprctl monitors -j | jq -r '.[0].name')

# Apply wallpaper directly
hyprctl hyprpaper preload "$WP_FILE"
hyprctl hyprpaper wallpaper "$MONITOR,$WP_FILE"
