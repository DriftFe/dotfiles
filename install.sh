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
  nautilus
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
  gtk3
  gtk4
  playerctl
  nano
  vim
  flatpak
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
  cbonsai
  wofi-emoji
  neofetch
  ttf-font-awesome-5
  ttf-font-awesome-6
  nerd-fonts-fira-code
  starship
  touchegg
  waypaper
  oh-my-zsh-git
  zsh-theme-powerlevel10k-git
  gpu-screen-recorder
  grimblast
  swappy
  bibata-cursor-theme
  network-manager-applet
  zen-browser-bin
  spotify
  waydroid
  vesktop
  visual-studio-code-bin
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

# Install Oh My Zsh (if not already installed)
if [ ! -d "$HOME/.oh-my-zsh" ]; then
  echo "[*] Installing Oh My Zsh..."
  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

# Install Powerlevel10k theme for Oh My Zsh
if [ ! -d "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k" ]; then
  echo "[*] Cloning Powerlevel10k theme for Oh My Zsh..."
  git clone --depth=1 https://github.com/romkatv/powerlevel10k.git \
    "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
fi

# Clone autosuggestions plugin
if [ ! -d "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions" ]; then
  echo "[*] Cloning zsh-autosuggestions..."
  git clone https://github.com/zsh-users/zsh-autosuggestions \
    "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions"
fi

# Clone syntax-highlighting plugin
if [ ! -d "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting" ]; then
  echo "[*] Cloning zsh-syntax-highlighting..."
  git clone https://github.com/zsh-users/zsh-syntax-highlighting \
    "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting"
fi

# Install Starship
if ! command -v starship &> /dev/null; then
  echo "[*] Installing Starship..."
  curl -sS https://starship.rs/install.sh | sh
fi

# Setup wallpaper folder and copy wallpaper
mkdir -p ~/.wallpapers
if [ -f "./dot_config/wallpaper.jpg" ]; then
  echo "[*] Copying wallpaper.jpg from dot_config..."
  cp ./dot_config/wallpaper.jpg ~/.wallpapers/
elif [ -f "./dot_config/wallpaper.png" ]; then
  echo "[*] Copying wallpaper.png from dot_config..."
  cp ./dot_config/wallpaper.png ~/.wallpapers/
else  
  echo "[!] No wallpaper.jpg or wallpaper.png found in dot_config."
fi

# Copy all configs from dot_config
if [ -d "./dot_config" ]; then
  echo "[*] Copying config files from dot_config to home..."
  mkdir -p ~/.config
  rsync -av --exclude=".zshrc" --exclude=".oh-my-zsh" ./dot_config/ ~/.config/
  if [ -f "./dot_config/.zshrc" ]; then
    echo "[*] Replacing ~/.zshrc with your custom version..."
    cp -f ./dot_config/.zshrc ~/.zshrc
  fi
  if [ -d "./dot_config/.oh-my-zsh" ]; then
    echo "[*] Copying Oh My Zsh customizations..."
    mkdir -p ~/.oh-my-zsh
    rsync -av ./dot_config/.oh-my-zsh/ ~/.oh-my-zsh/
  fi
fi

# Ensure Powerlevel10k theme is set in .zshrc
if [ -f ~/.zshrc ]; then
  if grep -q '^ZSH_THEME=' ~/.zshrc; then
    sed -i 's|^ZSH_THEME=.*|ZSH_THEME="powerlevel10k/powerlevel10k"|' ~/.zshrc
  else
    echo 'ZSH_THEME="powerlevel10k/powerlevel10k"' >> ~/.zshrc
  fi
fi

# Ensure plugins are enabled in .zshrc
if [ -f ~/.zshrc ]; then
  if grep -q '^plugins=' ~/.zshrc; then
    sed -i 's|^plugins=.*|plugins=(git zsh-autosuggestions zsh-syntax-highlighting)|' ~/.zshrc
  else
    echo 'plugins=(git zsh-autosuggestions zsh-syntax-highlighting)' >> ~/.zshrc
  fi
fi

echo "[+] All done!!! You can now reboot into your Hyprland setup. For keybinds, refer to ~/.config/hypr/keys.conf :3"
