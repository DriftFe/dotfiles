#!/usr/bin/env bash

set -euo pipefail

# ────────────────────────────────
# Globals
# ────────────────────────────────
DOTFILES_REPO="https://github.com/DriftFe/dotfiles"
TMP_DIR="$(mktemp -d)"
BACKUP_DIR="$HOME/.dotfiles_backup_$(date +%Y%m%d_%H%M%S)"

WAYPAPER_CFG="$HOME/.config/waypaper/config.json"
HYPAPER_CONF="$HOME/.config/hyprpaper/hyprpaper.conf"
HYPR_CONF="$HOME/.config/hypr/hyprland.conf"

# ────────────────────────────────
# Utils
# ────────────────────────────────
msg() { echo -e "\e[1;32m[*]\e[0m $*"; }
warn() { echo -e "\e[1;33m[!]\e[0m $*"; }
err() { echo -e "\e[1;31m[✗]\e[0m $*" >&2; }

# ────────────────────────────────
# Checks
# ────────────────────────────────
msg "Checking requirements..."
command -v git >/dev/null || { err "git missing"; exit 1; }
command -v rsync >/dev/null || { err "rsync missing"; exit 1; }

# ────────────────────────────────
# Detect distro
# ────────────────────────────────
if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO=$ID
else
    DISTRO="unknown"
fi

msg "Detected distro: $DISTRO"

# ────────────────────────────────
# Install packages
# ────────────────────────────────
msg "Installing dependencies..."

case "$DISTRO" in
    arch|endeavouros|manjaro|cachyos)
        sudo pacman -Syu --needed --noconfirm \
            hyprland waybar wofi kitty \
            hyprpaper hyprlock gdm nautilus
        ;;
    fedora)
        sudo dnf install -y \
            hyprland waybar wofi kitty \
            hyprpaper hyprlock gdm nautilus
        ;;
    void)
        sudo xbps-install -Sy \
            hyprland waybar wofi kitty \
            hyprpaper hyprlock gdm nautilus
        ;;
    opensuse*|tumbleweed)
        sudo zypper install -y \
            hyprland waybar wofi kitty \
            hyprpaper hyprlock gdm nautilus
        ;;
    nixos)
        warn "On NixOS, add these packages manually via configuration.nix"
        ;;
    *)
        warn "Unsupported distro, please install dependencies manually."
        ;;
esac

# ────────────────────────────────
# Backup old configs
# ────────────────────────────────
msg "Backing up old configs..."
mkdir -p "$BACKUP_DIR"
for item in .zshrc .config/hypr .config/waybar .config/kitty .config/wofi; do
    if [ -e "$HOME/$item" ]; then
        rsync -a "$HOME/$item" "$BACKUP_DIR/"
        rm -rf "$HOME/$item"
    fi
done

# ────────────────────────────────
# Clone dotfiles
# ────────────────────────────────
msg "Cloning dotfiles..."
git clone --depth=1 "$DOTFILES_REPO" "$TMP_DIR"

# Apply dotfiles
msg "Applying dotfiles..."
rsync -av "$TMP_DIR/dot_config/" "$HOME/.config/"

# Ensure scripts are executable
chmod -R +x "$HOME/.config/hypr/scripts" 2>/dev/null || true

# Setup zsh
[ -f "$TMP_DIR/.zshrc" ] && cp "$TMP_DIR/.zshrc" "$HOME/"

# ────────────────────────────────
# Wallpapers
# ────────────────────────────────
if [ -d "$TMP_DIR/dot_config/wallpapers" ]; then
    msg "Copying wallpapers..."
    mkdir -p "$HOME/.wallpapers"
    rsync -av "$TMP_DIR/dot_config/wallpapers/" "$HOME/.wallpapers/"
else
    warn "No wallpapers found in dotfiles."
fi

# ────────────────────────────────
# Force dark theme
# ────────────────────────────────
msg "Applying dark theme..."
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' 2>/dev/null || true
gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita-dark' 2>/dev/null || true

# ────────────────────────────────
# GTK theme setup
# ────────────────────────────────
msg "Configuring GTK theme..."
mkdir -p ~/.config/gtk-3.0 ~/.config/gtk-4.0

cat > ~/.config/gtk-3.0/settings.ini <<EOF
[Settings]
gtk-application-prefer-dark-theme=1
gtk-theme-name=Adwaita-dark
gtk-icon-theme-name=Papirus-Dark
gtk-font-name=JetBrainsMono Nerd Font 11
gtk-cursor-theme-name=Bibata-Modern-Classic
EOF

cp ~/.config/gtk-3.0/settings.ini ~/.config/gtk-4.0/

# ────────────────────────────────
# Hyprpaper config sync
# ────────────────────────────────
msg "Setting up hyprpaper config..."

if [ -f "$WAYPAPER_CFG" ]; then
    WP_FILE=$(grep -oP '"wallpaper":\s*"\K[^"]+' "$WAYPAPER_CFG" | head -n1 || true)
    if [ -n "$WP_FILE" ]; then
        msg "Found wallpaper in Waypaper: $WP_FILE"
        mkdir -p "$(dirname "$HYPAPER_CONF")"
        cat > "$HYPAPER_CONF" <<EOF
# Auto-generated by Lavender installer
preload = $WP_FILE
wallpaper = ,$WP_FILE
splash = true
EOF
    else
        warn "No wallpaper entry found in Waypaper config."
    fi
else
    warn "Waypaper config not found, skipping hyprpaper sync."
fi

# ────────────────────────────────
# Auto-start hyprpaper in Hyprland
# ────────────────────────────────
if [ -f "$HYPR_CONF" ]; then
    if ! grep -q "exec-once.*hyprpaper" "$HYPR_CONF"; then
        msg "Adding hyprpaper to Hyprland autostart..."
        echo -e "\n# Auto-start hyprpaper\nexec-once = hyprpaper &" >> "$HYPR_CONF"
    else
        msg "Hyprpaper already in autostart, skipping..."
    fi
else
    warn "Hyprland config not found, cannot auto-add hyprpaper."
fi

# ────────────────────────────────
# Enable GDM + Hyprland session
# ────────────────────────────────
if command -v systemctl >/dev/null; then
    sudo systemctl enable gdm || true
    sudo systemctl set-default graphical.target || true
fi

# Create Hyprland session file if missing
if [ ! -f /usr/share/wayland-sessions/hyprland.desktop ]; then
    sudo tee /usr/share/wayland-sessions/hyprland.desktop >/dev/null <<EOF
[Desktop Entry]
Name=Hyprland
Comment=An independent tiling Wayland compositor
Exec=Hyprland
Type=Application
EOF
fi

# ────────────────────────────────
# Finish
# ────────────────────────────────
msg "Cleaning up..."
rm -rf "$TMP_DIR"

msg "Installation complete! 🎉"
echo "Backups saved in: $BACKUP_DIR"
echo "You can reboot now to start Hyprland."
