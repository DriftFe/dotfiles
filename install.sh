#!/bin/bash

set -e

echo "[*] Installing cute dotfiles on Arch >w< "

# Update system
sudo pacman -Syu --noconfirm

# Essential packages from official repos
packages_pacman=(
  hyprland waybar kitty zsh nautilus wofi sddm fastfetch mpv htop wl-clipboard
  swaybg unzip curl wget git gtk3 gtk4 playerctl nano vim flatpak hyprpaper
  hyprlock noto-fonts noto-fonts-cjk noto-fonts-emoji ttf-jetbrains-mono
  ttf-fira-code ttf-roboto font-manager
)

# AUR packages to install with yay
packages_aur=(
  cava cbonsai wofi-emoji neofetch ttf-font-awesome-5 ttf-font-awesome-6
  nerd-fonts-fira-code starship touchegg waypaper oh-my-zsh-git
  zsh-theme-powerlevel10k-git gpu-screen-recorder grimblast swappy
  bibata-cursor-theme network-manager-applet zen-browser-bin spotify
  waydroid vesktop visual-studio-code-bin
)

echo "[*] Installing pacman packages..."
sudo pacman -S --needed --noconfirm "${packages_pacman[@]}"

# Install yay if missing
if ! command -v yay &>/dev/null; then
  echo "[*] Installing yay..."
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

# Set zsh as default shell
chsh -s "$(which zsh)"

# Install Oh My Zsh
if [ ! -d "$HOME/.oh-my-zsh" ]; then
  echo "[*] Installing Oh My Zsh..."
  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

# Clone Powerlevel10k theme
if [ ! -d "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k" ]; then
  echo "[*] Cloning Powerlevel10k..."
  git clone --depth=1 https://github.com/romkatv/powerlevel10k.git \
    "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
fi

# Clone zsh-autosuggestions
if [ ! -d "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions" ]; then
  echo "[*] Cloning zsh-autosuggestions..."
  git clone https://github.com/zsh-users/zsh-autosuggestions \
    "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions"
fi

# Clone zsh-syntax-highlighting
if [ ! -d "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting" ]; then
  echo "[*] Cloning zsh-syntax-highlighting..."
  git clone https://github.com/zsh-users/zsh-syntax-highlighting \
    "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting"
fi

# Install Starship prompt if not already present
if ! command -v starship &>/dev/null; then
  echo "[*] Installing Starship..."
  curl -sS https://starship.rs/install.sh | sh
fi

# Setup wallpaper
mkdir -p ~/.wallpapers
if [ -f "./dot_config/wallpaper.jpg" ]; then
  echo "[*] Copying wallpaper.jpg..."
  cp ./dot_config/wallpaper.jpg ~/.wallpapers/
elif [ -f "./dot_config/wallpaper.png" ]; then
  echo "[*] Copying wallpaper.png..."
  cp ./dot_config/wallpaper.png ~/.wallpapers/
else
  echo "[!] No wallpaper found in dot_config."
fi

# Copy dotfiles
if [ -d "./dot_config" ]; then
  echo "[*] Copying dot_config to ~/.config..."
  mkdir -p ~/.config
  rsync -av --exclude=".zshrc" --exclude=".oh-my-zsh" ./dot_config/ ~/.config/

  # Replace .zshrc
  if [ -f "./dot_config/.zshrc" ]; then
    echo "[*] Installing custom .zshrc..."
    cp -f ./dot_config/.zshrc ~/.zshrc
  fi

  # Copy any custom oh-my-zsh setup
  if [ -d "./dot_config/.oh-my-zsh" ]; then
    echo "[*] Copying Oh My Zsh custom content..."
    mkdir -p ~/.oh-my-zsh
    rsync -av ./dot_config/.oh-my-zsh/ ~/.oh-my-zsh/
  fi
fi

# Fix broken manual source lines (just in case)
sed -i '/\.zsh\/zsh-autosuggestions/d' ~/.zshrc
sed -i '/\.zsh\/zsh-syntax-highlighting/d' ~/.zshrc

# Ensure Powerlevel10k theme is set
if grep -q '^ZSH_THEME=' ~/.zshrc; then
  sed -i 's|^ZSH_THEME=.*|ZSH_THEME="powerlevel10k/powerlevel10k"|' ~/.zshrc
else
  echo 'ZSH_THEME="powerlevel10k/powerlevel10k"' >> ~/.zshrc
fi

# Enable Oh My Zsh plugins
if grep -q '^plugins=' ~/.zshrc; then
  sed -i 's|^plugins=.*|plugins=(git zsh-autosuggestions zsh-syntax-highlighting)|' ~/.zshrc
else
  echo 'plugins=(git zsh-autosuggestions zsh-syntax-highlighting)' >> ~/.zshrc
fi

echo "[+] Done! You can now reboot into Hyprland. >w<"
echo "[i] Check keybinds in: ~/.config/hypr/keys.conf"
