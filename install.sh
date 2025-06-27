#!/bin/bash

set -e

echo "[*] Installing cute dotfiles on Arch >w< "

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
  hyprpaper
  hyprlock
  noto-fonts
  noto-fonts-cjk
  noto-fonts-emoji
  ttf-jetbrains-mono
  ttf-fira-code
  ttf-roboto
  font-manager
)

# AUR packages (installed via yay)
packages_aur=(
  cava
  neofetch
  ttf-font-awesome-5
  ttf-font-awesome-6
  nerd-fonts-fira-code
  starship
  oh-my-zsh-git
  zsh-theme-powerlevel10k-git
  gpu-screen-recorder
  grim
  satty
  bibata-cursor-theme
  network-manager-applet
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

# Install Oh My Zsh (if not already installed, but we'll copy customizations next)
if [ ! -d "$HOME/.oh-my-zsh" ]; then
  echo "[*] Installing Oh My Zsh..."
  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

# Install Starship
if ! command -v starship &> /dev/null; then
  echo "[*] Installing Starship..."
  curl -sS https://starship.rs/install.sh | sh
fi

# Setup wallpaper folder and copy wallpaper
mkdir -p ~/.wallpapers
if [ -f "./wallpaper.jpg" ]; then
  echo "[*] Copying wallpaper..."
  cp ./wallpaper.jpg ~/.wallpapers/
elif [ -f "./wallpaper.png" ]; then
  cp ./wallpaper.png ~/.wallpapers/
else
  echo "[!] No wallpaper file found in current directory."
fi

# Copy all configs from dot_config
if [ -d "./dot_config" ]; then
  echo "[*] Copying config files from dot_config to home..."
  # Copy everything except .zshrc and .oh-my-zsh (handled separately for clarity)
  mkdir -p ~/.config
  rsync -av --exclude=".zshrc" --exclude=".oh-my-zsh" ./dot_config/ ~/.config/
  # Copy .zshrc if present
  if [ -f "./dot_config/.zshrc" ]; then
    cp ./dot_config/.zshrc ~/
  fi
  # Copy .oh-my-zsh if present
  if [ -d "./dot_config/.oh-my-zsh" ]; then
    mkdir -p ~/.oh-my-zsh
    rsync -av ./dot_config/.oh-my-zsh/ ~/.oh-my-zsh/
  fi
fi

echo "[+] All done!!! You can now reboot into your Hyprland setup, for keybinds, refer to ~/.config/hypr/keys.conf :3"
