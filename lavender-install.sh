#!/usr/bin/env bash
set -euo pipefail
if ! command -v pacman >/dev/null 2>&1; then
  echo "This installer is Arch Linux only (requires pacman)." >&2
  exit 1
fi

SRC_DOTCONFIG="${1:-$(pwd)/dot_config}"
DEST_CONFIG="$HOME/.config"

if [[ ! -d "$SRC_DOTCONFIG" ]]; then
  echo "Source dot_config directory not found: $SRC_DOTCONFIG" >&2
  exit 1
fi

echo "Copying dotfiles from $SRC_DOTCONFIG to $DEST_CONFIG ..."
mkdir -p "$DEST_CONFIG"
# Ensure rsync is present before using it
if ! command -v rsync >/dev/null 2>&1; then
  echo "Installing rsync ..."
  sudo pacman -S --needed --noconfirm rsync
fi
rsync -avh --delete --mkpath "$SRC_DOTCONFIG"/ "$DEST_CONFIG"/

# Packages
PACMAN_PACKAGES=(
  git zsh rsync
  kitty
  hyprland hyprpaper waybar wofi
  mako
  wl-clipboard cliphist
  brightnessctl
  nautilus
  pavucontrol blueman network-manager-applet
  libnotify
  touchegg
  xsettingsd
  noto-fonts ttf-inter ttf-roboto ttf-nerd-fonts-symbols ttf-font-awesome
)

# AUR packages
AUR_PACKAGES=(
  waypaper
  gpu-screen-recorder
  nerd-fonts-jetbrains-mono
)

echo "Synchronizing pacman database and upgrading system ..."
sudo pacman -Syu --noconfirm

echo "Installing packages with pacman ..."
sudo pacman -S --needed --noconfirm "${PACMAN_PACKAGES[@]}"

# Install yay if missing
if ! command -v yay >/dev/null 2>&1; then
  echo "Installing yay (AUR helper) ..."
  sudo pacman -S --needed --noconfirm base-devel git
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT
  git clone https://aur.archlinux.org/yay.git "$tmpdir/yay"
  (cd "$tmpdir/yay" && makepkg -si --noconfirm)
fi

echo "Installing AUR packages with yay ..."
yay -S --needed --noconfirm "${AUR_PACKAGES[@]}"

# Enable and start services
if command -v systemctl >/dev/null 2>&1; then
  echo "Enabling core services ..."
  # System services
  if systemctl list-unit-files | grep -q '^NetworkManager.service'; then
    sudo systemctl enable --now NetworkManager || true
  fi
  if systemctl list-unit-files | grep -q '^bluetooth.service'; then
    sudo systemctl enable --now bluetooth || true
  fi
  # User services
  systemctl --user enable --now touchegg.service || true
  systemctl --user enable --now xsettingsd.service || true
  # PipeWire (if applicable)
  systemctl --user enable --now pipewire.service pipewire-pulse.service wireplumber.service || true
fi

# Ensure Waybar helper scripts are executable if present
SCRIPT_DIRS=(
  "$DEST_CONFIG/waybar/scripts"
)
for dir in "${SCRIPT_DIRS[@]}"; do
  if [[ -d "$dir" ]]; then
    echo "Setting scripts executable in: $dir"
    find "$dir" -type f -name "*.sh" -print0 | xargs -0 chmod +x || true
  fi
done

# Make other common script locations executable
if [[ -d "$DEST_CONFIG/hypr/scripts" ]]; then
  find "$DEST_CONFIG/hypr/scripts" -type f -name "*.sh" -print0 | xargs -0 chmod +x || true
fi

# Apply gtk dark preference
if command -v gsettings >/dev/null 2>&1; then
  echo "Applying GNOME dark color-scheme ..."
  gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' || true
  gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita-dark' || true
fi

echo "\nOptional environment variables (add to your compositor/session if desired):"
echo "  export GTK_THEME=Adwaita:dark"
echo "  export GTK_APPLICATION_PREFER_DARK_THEME=1"
echo "\nInstall complete on Arch Linux (pacman + AUR)."