#!/usr/bin/env bash
# Sync current Waypaper wallpapers into Hyprpaper config

WAYPAPER_CFG="$HOME/.config/waypaper/config.json"
HYPAPER_CONF="$HOME/.config/hyprpaper/hyprpaper.conf"

mkdir -p "$(dirname "$HYPAPER_CONF")"

if [ ! -f "$WAYPAPER_CFG" ]; then
    echo "[!] Waypaper config not found at $WAYPAPER_CFG"
    exit 1
fi

# Extract wallpapers (Waypaper stores them as JSON values)
WALLPAPERS=$(grep -oP '"wallpaper":\s*\{[^}]+\}' "$WAYPAPER_CFG" || true)

if [ -n "$WALLPAPERS" ]; then
    # ────────────────────────────────
    # Case 1: per-monitor wallpapers
    # ────────────────────────────────
    > "$HYPAPER_CONF"
    echo "# Auto-generated from Waypaper" >> "$HYPAPER_CONF"
    echo "splash = true" >> "$HYPAPER_CONF"

    # Extract monitor→wallpaper pairs
    echo "$WALLPAPERS" | grep -oP '"[^"]+":\s*"[^"]+"' | while read -r line; do
        MONITOR=$(echo "$line" | cut -d: -f1 | tr -d '" ')
        FILE=$(echo "$line" | cut -d: -f2- | tr -d '" ')
        echo "preload = $FILE" >> "$HYPAPER_CONF"
        echo "wallpaper = $MONITOR,$FILE" >> "$HYPAPER_CONF"
    done
else
    # ────────────────────────────────
    # Case 2: single wallpaper (global)
    # ────────────────────────────────
    WP_FILE=$(grep -oP '"wallpaper":\s*"\K[^"]+' "$WAYPAPER_CFG" | head -n1 || true)
    if [ -n "$WP_FILE" ]; then
        cat > "$HYPAPER_CONF" <<EOF
# Auto-generated from Waypaper
preload = $WP_FILE
wallpaper = ,$WP_FILE
splash = true
EOF
    fi
fi

# Restart hyprpaper to apply changes
pkill hyprpaper 2>/dev/null
sleep 0.2
hyprpaper &
