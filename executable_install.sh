#!/bin/bash

set -e

echo "[*] Installing Hyprland setup on Arch..."

# Update system
sudo pacman -Syu --noconfirm

# Essential packages
packages=(
  hyprland
  waybar
  kitty
  zsh
  wofi
  sddm
  fastfetch
  mpv
  neofetch
  cava
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
)

echo "[*] Installing packages..."
sudo pacman -S --needed --noconfirm "${packages[@]}"

# Enable SDDM
sudo systemctl enable sddm

# Set default shell to zsh
chsh -s "$(which zsh)"

echo "[+] All done. You can now reboot into your Hyprland setup!"
