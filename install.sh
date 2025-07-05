#!/bin/bash
set -e

# ─── Ensure Zenity Is Installed :3 ──────────────
if ! command -v zenity &>/dev/null; then
  echo "[!] Zenity not found. Installing it now..."
  . /etc/os-release
  case "$ID" in
    arch) sudo pacman -S --noconfirm zenity ;;
    fedora) sudo dnf install -y zenity ;;
    gentoo) sudo emerge --ask zenity ;;
    debian|ubuntu) sudo apt install -y zenity ;;
    *) echo "[!] Can't auto-install zenity on this distro"; exit 1 ;;
  esac
fi

# ─── Welcome ──────────────────
zenity --info --width=300 --height=100 \
  --title="Cute Dotfiles Installer >w<" \
  --text="Welcome to the multi-distro dotfiles installer!\n\nClick OK to continue."

# ─── Detect Distro ───────────────
DISTRO="unknown"
if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO=$ID
fi

zenity --info --title="Distro Detected!" \
  --text="You're running: $DISTRO"

# ─── Confirm Install ────────────
zenity --question --width=300 --title="Confirm Install" \
  --text="Do you want to install dotfiles and Hyprland setup on your $DISTRO system?"

if [ $? -ne 0 ]; then
  zenity --info --text="Installation cancelled." && exit 0
fi

# ─── Begin Install with Progress ──────────
(
echo "5"; echo "# Preparing..."

# Common packages
packages_common=(
  zsh git curl wget unzip nano vim fastfetch htop mpv
  noto-fonts noto-fonts-emoji font-manager
)

echo "10"; echo "# Installing system packages..."

case "$DISTRO" in
  arch)
    sudo pacman -Syu --noconfirm

    pacman_pkgs=(
      hyprland waybar kitty nautilus wofi sddm wl-clipboard swaybg
      gtk3 gtk4 playerctl flatpak hyprpaper hyprlock
      ttf-jetbrains-mono ttf-fira-code ttf-roboto
    )

    aur_pkgs=(
      cava cbonsai wofi-emoji ttf-font-awesome-5 ttf-font-awesome-6
      nerd-fonts-fira-code starship touchegg waypaper oh-my-zsh-git
      zsh-theme-powerlevel10k-git gpu-screen-recorder grimblast swappy
      bibata-cursor-theme network-manager-applet zen-browser-bin spotify
      waydroid vesktop visual-studio-code-bin
    )

    sudo pacman -S --needed --noconfirm "${packages_common[@]}" "${pacman_pkgs[@]}"

    if ! command -v yay &>/dev/null; then
      echo "[*] Installing yay..."
      sudo pacman -S --needed --noconfirm base-devel
      git clone https://aur.archlinux.org/yay.git /tmp/yay
      cd /tmp/yay && makepkg -si --noconfirm && cd - && rm -rf /tmp/yay
    fi

    yay -S --needed --noconfirm "${aur_pkgs[@]}"
    sudo systemctl enable sddm
    ;;

  fedora)
    sudo dnf update -y
    sudo dnf install -y "${packages_common[@]}" kitty waybar wl-clipboard swaybg \
      nautilus wofi sddm gtk3 gtk4 playerctl flatpak
    sudo dnf install -y jetbrains-mono-fonts fira-code-fonts google-roboto-fonts fontawesome-fonts
    sudo systemctl enable sddm
    ;;

  gentoo)
    sudo emerge --sync
    sudo emerge --ask "${packages_common[@]}" x11-terms/kitty x11-misc/waybar \
      gui-apps/wofi gui-apps/swaybg x11-misc/wl-clipboard gui-apps/hyprland
    sudo emerge --ask media-fonts/noto media-fonts/roboto media-fonts/jetbrains-mono
    ;;

  nixos)
    echo "100"; echo "# NixOS detected. Skipping runtime install..."
    zenity --info --title="NixOS Detected" \
      --text="❗ Please edit /etc/nixos/configuration.nix and add the following:\n\n\
environment.systemPackages = with pkgs; [\n  zsh git curl wget unzip nano vim fastfetch htop mpv kitty waybar hyprland\n\
nautilus wofi sddm wl-clipboard swaybg gtk3 gtk4 playerctl flatpak\n\
noto-fonts noto-fonts-emoji jetbrains-mono fira-code roboto font-manager\n];\n\
\nThen run: sudo nixos-rebuild switch"
    exit 0
    ;;

  *)
    zenity --error --text="Unsupported distro: $DISTRO"
    exit 1
    ;;
esac

echo "50"; echo "# Setting up ZSH and themes..."

# ─── Shell Setup ───────────
chsh -s "$(which zsh)"

if [ ! -d "$HOME/.oh-my-zsh" ]; then
  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

[ ! -d "$ZSH_CUSTOM/themes/powerlevel10k" ] &&
  git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$ZSH_CUSTOM/themes/powerlevel10k"

[ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ] &&
  git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"

[ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ] &&
  git clone https://github.com/zsh-users/zsh-syntax-highlighting "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"

if ! command -v starship &>/dev/null; then
  curl -sS https://starship.rs/install.sh | sh -s -- -y
fi

echo "80"; echo "# Copying wallpapers and dotfiles..."

# ─── Wallpaper Setup ────────────
mkdir -p ~/.wallpapers
[ -f "./dot_config/wallpaper.jpg" ] && cp ./dot_config/wallpaper.jpg ~/.wallpapers/
[ -f "./dot_config/wallpaper.png" ] && cp ./dot_config/wallpaper.png ~/.wallpapers/

# ─── Dotfiles ────────────
if [ -d "./dot_config" ]; then
  mkdir -p ~/.config
  rsync -av --exclude=".zshrc" --exclude=".oh-my-zsh" ./dot_config/ ~/.config/
  [ -f "./dot_config/.zshrc" ] && cp -f ./dot_config/.zshrc ~/.zshrc
  [ -d "./dot_config/.oh-my-zsh" ] && rsync -av ./dot_config/.oh-my-zsh/ ~/.oh-my-zsh/
fi

# ─── Final zshrc Tweaks ────────────
sed -i '/\.zsh\/zsh-autosuggestions/d' ~/.zshrc || true
sed -i '/\.zsh\/zsh-syntax-highlighting/d' ~/.zshrc || true

grep -q '^ZSH_THEME=' ~/.zshrc && \
  sed -i 's|^ZSH_THEME=.*|ZSH_THEME="powerlevel10k/powerlevel10k"|' ~/.zshrc || \
  echo 'ZSH_THEME="powerlevel10k/powerlevel10k"' >> ~/.zshrc

grep -q '^plugins=' ~/.zshrc && \
  sed -i 's|^plugins=.*|plugins=(git zsh-autosuggestions zsh-syntax-highlighting)|' ~/.zshrc || \
  echo 'plugins=(git zsh-autosuggestions zsh-syntax-highlighting)' >> ~/.zshrc

echo "100"; echo "# Done!"
) | zenity --progress \
  --title="Installing Dotfiles..." \
  --text="Starting install..." \
  --percentage=0 \
  --auto-close

# ─── Reboot Prompt ────────
zenity --question --width=300 --title="Reboot?" \
  --text="Installation complete!\n\nDo you want to reboot now?"

[ $? -eq 0 ] && reboot
