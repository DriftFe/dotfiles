#!/bin/bash

set -e

echo "[*] Installing Hyprland setup on Arch..."

# Update system
sudo pacman -Syu --noconfirm

# Essential packages (pacman)
packages_pacman=(
  hyprland
  waybar
  kitty
  zsh
  wofi
  sddm
  fastfetch
  mpv
  htop
  wl-clipboard
  swaybg
  unzip
  curl
  wget
  git
  thunar
  gtk3
  gtk4
  playerctl
  wofi-emoji
)

# AUR packages (installed via yay)
packages_aur=(
  cbonsai
  cava
  neofetch
)

echo "[*] Installing pacman packages..."
sudo pacman -S --needed --noconfirm "${packages_pacman[@]}"

# Install yay if not present
if ! command -v yay &> /dev/null; then
  echo "[*] Installing yay from AUR..."
  sudo pacman -S --needed --noconfirm git base-devel
  git clone https://aur.archlinux.org/yay.git /tmp/yay
  cd /tmp/yay
  makepkg -si --noconfirm
  cd -
  rm -rf /tmp/yay
fi

echo "[*] Installing AUR packages..."
yay -S --needed --noconfirm "${packages_aur[@]}"

# Enable SDDM
sudo systemctl enable sddm

# Set default shell to zsh
chsh -s "$(which zsh)"

# Copy config files if dot_config exists
if [ -d "./dot_config" ]; then
  echo "[*] Copying config files to ~/.config..."
  mkdir -p ~/.config
  cp -r ./dot_config/* ~/.config/
fi

echo "[+] All done. You can now reboot into your Hyprland setup!"
