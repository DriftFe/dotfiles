#!/usr/bin/env bash

set -e

# --- Functions ---
msg() { echo -e "\e[32m[INFO]\e[0m $*"; }
warn() { echo -e "\e[33m[WARN]\e[0m $*"; }
err()  { echo -e "\e[31m[ERROR]\e[0m $*" >&2; exit 1; }

# --- Variables ---
DOTFILES_REPO="https://github.com/DriftFe/dotfiles"
TMP_DIR="/tmp/dotfiles-setup"
CURSOR_DIR="$HOME/.icons"
HYPR_CONF="$HOME/.config/hypr/hyprland.conf"

# --- Detect package manager ---
if command -v pacman &>/dev/null; then
    PKG="pacman -S --noconfirm"
elif command -v apt &>/dev/null; then
    PKG="apt install -y"
elif command -v dnf &>/dev/null; then
    PKG="dnf install -y"
else
    err "No supported package manager found (pacman, apt, or dnf)."
fi

# --- Start ---
msg "Starting dotfiles installation..."

# --- Install essentials ---
msg "Installing required packages..."
sudo $PKG git wget curl unzip

# --- Clone dotfiles ---
if [ -d "$TMP_DIR" ]; then
    rm -rf "$TMP_DIR"
fi
git clone --depth=1 "$DOTFILES_REPO" "$TMP_DIR"
msg "Dotfiles cloned successfully."

# --- Copy configs ---
mkdir -p "$HOME/.config"
cp -rT "$TMP_DIR/.config" "$HOME/.config"
msg "Configs applied to ~/.config."

# --- Install cliphist ---
msg "Installing cliphist..."
if ! command -v cliphist &>/dev/null; then
    sudo $PKG cliphist || warn "cliphist not found in default repos."
else
    msg "cliphist already installed, skipping."
fi

# --- Install Bibata Classic Dark cursor ---
msg "Installing Bibata Classic Dark cursor..."
mkdir -p "$CURSOR_DIR"
if [ ! -d "$CURSOR_DIR/Bibata-Classic-Dark" ]; then
    wget -qO /tmp/Bibata.tar.gz https://github.com/ful1e5/Bibata_Cursor/releases/download/v2.0.0/Bibata-Classic-Dark.tar.gz
    tar -xzf /tmp/Bibata.tar.gz -C "$CURSOR_DIR"
    msg "Bibata Classic Dark cursor installed."
else
    msg "Bibata Classic Dark already installed, skipping."
fi

# --- Set cursor theme ---
if command -v gsettings &>/dev/null; then
    gsettings set org.gnome.desktop.interface cursor-theme "Bibata-Classic-Dark" 2>/dev/null || true
fi
msg "Bibata Classic Dark cursor set as default."

# --- Configure Hyprland ---
if command -v hyprctl &>/dev/null; then
    msg "Configuring Hyprland cursor environment..."
    mkdir -p "$(dirname "$HYPR_CONF")"
    if ! grep -q "XCURSOR_THEME" "$HYPR_CONF" 2>/dev/null; then
        {
            echo ""
            echo "# --- Cursor settings ---"
            echo "env:XCURSOR_THEME,Bibata-Classic-Dark"
            echo "env:XCURSOR_SIZE,24"
        } >> "$HYPR_CONF"
        msg "Added Bibata cursor settings to Hyprland config."
    else
        msg "Hyprland cursor settings already present, skipping."
    fi
fi

# --- Cleanup ---
rm -rf "$TMP_DIR" /tmp/Bibata.tar.gz 2>/dev/null || true
msg "Temporary files cleaned."

# --- Done ---
msg "✅ Setup complete. You may need to log out and back in for cursor changes to apply."
