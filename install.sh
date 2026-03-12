#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

# ╔═══════════════════════════════════════════════════════════════╗
# ║                 Dotfiles Installer for Arch Linux             ║
# ╚═══════════════════════════════════════════════════════════════╝

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

REPO_URL="https://github.com/DriftFe/dotfiles.git"
WORK_DIR=""
TMP_DIR=""

# Colors
C_RESET='\033[0m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[1;33m'
C_RED='\033[0;31m'
C_CYAN='\033[0;36m'
C_PURPLE='\033[0;35m'

log() { echo -e "${C_PURPLE}[+]${C_RESET} $*"; }
success() { echo -e "${C_GREEN}[✓]${C_RESET} $*"; }
warn() { echo -e "${C_YELLOW}[!]${C_RESET} $*" >&2; }
err() { echo -e "${C_RED}[✗]${C_RESET} $*" >&2; exit 1; }
info() { echo -e "${C_CYAN}[i]${C_RESET} $*"; }

cleanup() {
  if [[ -n "$WORK_DIR" && -d "$WORK_DIR" ]]; then
    rm -rf "$WORK_DIR"
  fi

  if [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]]; then
    rm -rf "$TMP_DIR"
  fi
}

trap cleanup EXIT

if [[ $EUID -eq 0 ]]; then
  err "Do not run this installer as root. Run it as your normal user."
fi

# Ensure Arch
if ! command -v pacman >/dev/null 2>&1; then
  err "This installer supports Arch Linux only."
fi

SRC_DOTCONFIG="$script_dir/dot_config"
DEST_CONFIG="$HOME/.config"

if [[ ! -d "$SRC_DOTCONFIG" ]]; then
  warn "dot_config directory not found next to install.sh."

  if ! command -v git >/dev/null 2>&1; then
    info "Installing git (required to fetch dotfiles)"
    sudo pacman -S --needed --noconfirm git
  fi

  WORK_DIR="$(mktemp -d)"
  info "Cloning dotfiles repository to temporary directory"
  git clone --depth=1 "$REPO_URL" "$WORK_DIR/repo"

  SRC_DOTCONFIG="$WORK_DIR/repo/dot_config"
  [[ -d "$SRC_DOTCONFIG" ]] || err "dot_config directory not found in cloned repository."
fi

mkdir -p "$DEST_CONFIG"

# Ensure rsync
if ! command -v rsync >/dev/null 2>&1; then
  info "Installing rsync"
  sudo pacman -S --needed --noconfirm rsync
fi

log "Copying dotfiles..."
rsync -avh --mkpath "$SRC_DOTCONFIG"/ "$DEST_CONFIG"/

# Packages
PACMAN_PACKAGES=(
  git zsh rsync curl
  kitty
  hyprland hyprpaper waybar wofi
  mako
  wl-clipboard cliphist
  brightnessctl
  nautilus
  nm-applet
  pavucontrol blueman
  bluez bluez-utils
  libnotify
  touchegg
  xsettingsd
  noto-fonts ttf-inter ttf-roboto
  ttf-nerd-fonts-symbols ttf-font-awesome
  xdg-desktop-portal-hyprland
  xdg-user-dirs
  polkit-gnome
  grim slurp
)

AUR_PACKAGES=(
  waypaper
  gpu-screen-recorder
  nerd-fonts-jetbrains-mono
)

log "Updating system..."
sudo pacman -Syu --noconfirm

log "Installing pacman packages..."
sudo pacman -S --needed --noconfirm "${PACMAN_PACKAGES[@]}"

# Install yay
if ! command -v yay >/dev/null 2>&1; then
  log "Installing yay..."

  sudo pacman -S --needed --noconfirm base-devel git

  TMP_DIR="$(mktemp -d)"

  git clone https://aur.archlinux.org/yay.git "$TMP_DIR/yay"

  (
    cd "$TMP_DIR/yay"
    makepkg -si --noconfirm
  )

fi

log "Installing AUR packages..."
yay -S --needed --noconfirm --answerclean All --answerdiff None "${AUR_PACKAGES[@]}"

# Enable services
if command -v systemctl >/dev/null 2>&1; then

  log "Enabling services..."

  if systemctl list-unit-files | grep -q NetworkManager.service; then
    sudo systemctl enable --now NetworkManager
  fi

  if systemctl list-unit-files | grep -q bluetooth.service; then
    sudo systemctl enable --now bluetooth
  fi

  if systemctl list-unit-files | grep -q touchegg.service; then
    sudo systemctl enable --now touchegg
  fi

  systemctl --user enable --now xsettingsd.service || true
fi

# Waybar script permissions
SCRIPT_DIRS=(
  "$DEST_CONFIG/waybar/scripts"
  "$DEST_CONFIG/hypr/scripts"
)

for dir in "${SCRIPT_DIRS[@]}"; do
  if [[ -d "$dir" ]]; then
    info "Setting executable permissions in $dir"
    find "$dir" -type f -name "*.sh" -exec chmod +x {} +
  fi
done

# GNOME dark preference
if command -v gsettings >/dev/null 2>&1; then
  log "Applying dark theme"
  gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' || true
  gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita-dark' || true
fi

# Zsh setup
log "Configuring Zsh environment"

if command -v zsh >/dev/null 2>&1; then
  if [[ "$SHELL" != "$(command -v zsh)" ]]; then
    chsh -s "$(command -v zsh)" "$USER" || warn "Could not change default shell"
  fi
fi

# Install Oh My Zsh
if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
  info "Installing Oh My Zsh"
  RUNZSH=no KEEP_ZSHRC=yes sh -c \
  "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

# Powerlevel10k
if pacman -Si zsh-theme-powerlevel10k &>/dev/null; then
  sudo pacman -S --needed --noconfirm zsh-theme-powerlevel10k
else
  if [[ ! -d "$HOME/.oh-my-zsh/custom/themes/powerlevel10k" ]]; then
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git \
    "$HOME/.oh-my-zsh/custom/themes/powerlevel10k"
  fi
fi

# Zsh plugins
mkdir -p "$HOME/.oh-my-zsh/custom/plugins"
