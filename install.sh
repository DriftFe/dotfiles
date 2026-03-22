#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

REPO_URL="https://github.com/DriftFe/dotfiles.git"
WORK_DIR=""
TMP_DIR=""

C_RESET='\033[0m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[1;33m'
C_RED='\033[0;31m'
C_CYAN='\033[0;36m'
C_PURPLE='\033[0;35m'

log()     { echo -e "${C_PURPLE}[+]${C_RESET} $*"; }
success() { echo -e "${C_GREEN}[✓]${C_RESET} $*"; }
warn()    { echo -e "${C_YELLOW}[!]${C_RESET} $*" >&2; }
err()     { echo -e "${C_RED}[✗]${C_RESET} $*" >&2; exit 1; }
info()    { echo -e "${C_CYAN}[i]${C_RESET} $*"; }

cleanup() {
  [[ -n "$WORK_DIR" && -d "$WORK_DIR" ]] && rm -rf "$WORK_DIR"
  [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]] && rm -rf "$TMP_DIR"
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

ensure_line_in_file() {
  local file="$1"
  local line="$2"

  touch "$file"
  grep -Fqx "$line" "$file" || printf '%s\n' "$line" >> "$file"
}

enable_system_service() {
  local unit="$1"

  if systemctl list-unit-files --type=service | awk '{print $1}' | grep -Fxq "$unit"; then
    sudo systemctl enable --now "$unit"
    success "Enabled $unit"
  else
    warn "$unit not found, skipping"
  fi
}

enable_user_service() {
  local unit="$1"

  if ! systemctl --user list-unit-files >/dev/null 2>&1; then
    warn "User systemd instance is unavailable; skipping $unit"
    return 0
  fi

  if systemctl --user list-unit-files | awk '{print $1}' | grep -Fxq "$unit"; then
    systemctl --user enable --now "$unit"
    success "Enabled user service: $unit"
  else
    warn "User service $unit not found, skipping"
  fi
}

trap cleanup EXIT

if [[ $EUID -eq 0 ]]; then
  err "Do not run this installer as root. Run it as your normal user."
fi

have_cmd pacman || err "This installer supports Arch Linux only."

log "Refreshing sudo credentials..."
sudo -v

SRC_DOTCONFIG="$script_dir/dot_config"
DEST_CONFIG="$HOME/.config"
ZSHRC="$HOME/.zshrc"

if [[ ! -d "$SRC_DOTCONFIG" ]]; then
  warn "dot_config directory not found next to install.sh."

  if ! have_cmd git; then
    info "Installing git so the repository can be fetched"
    sudo pacman -S --needed --noconfirm git
  fi

  WORK_DIR="$(mktemp -d)"
  info "Cloning dotfiles repository..."
  git clone --depth=1 "$REPO_URL" "$WORK_DIR/repo"

  SRC_DOTCONFIG="$WORK_DIR/repo/dot_config"
  [[ -d "$SRC_DOTCONFIG" ]] || err "dot_config directory not found in cloned repository."
fi

PACMAN_PACKAGES=(
  git
  zsh
  rsync
  curl
  wget
  unzip
  base-devel
  kitty
  mpv
  hyprland
  swww
  waybar
  wofi
  mako
  libnotify
  wl-clipboard
  cliphist
  brightnessctl
  grim
  slurp
  nautilus
  networkmanager
  network-manager-applet
  pipewire
  pipewire-alsa
  pipewire-pulse
  wireplumber
  pavucontrol
  bluez
  bluez-utils
  blueman
  touchegg
  xsettingsd
  qt5ct
  gnome-keyring
  udisks2
  playerctl
  cava
  noto-fonts
  noto-fonts-emoji
  ttf-roboto
  ttf-jetbrains-mono
  ttf-nerd-fonts-symbols
  ttf-font-awesome
  xdg-desktop-portal
  xdg-desktop-portal-hyprland
  xdg-user-dirs
  polkit-gnome
)

AUR_PACKAGES=(
  waypaper
  vesktop-bin
  zen-browser-bin
  gpu-screen-recorder
  nerd-fonts-jetbrains-mono
  grimblast-git
  swappy
  bibata-cursor-theme
  hyprpicker
  adw-gtk3
  cbonsai
)

log "Updating system..."
sudo pacman -Syu --noconfirm

log "Installing pacman packages..."
sudo pacman -S --needed --noconfirm "${PACMAN_PACKAGES[@]}"

mkdir -p "$DEST_CONFIG"

log "Copying dotfiles into $DEST_CONFIG..."
rsync -avh --mkpath "$SRC_DOTCONFIG"/ "$DEST_CONFIG"/

if ! have_cmd yay; then
  log "Installing yay (AUR helper)..."
  TMP_DIR="$(mktemp -d)"
  git clone https://aur.archlinux.org/yay.git "$TMP_DIR/yay"
  (
    cd "$TMP_DIR/yay"
    makepkg -si --noconfirm
  )
fi

if (( ${#AUR_PACKAGES[@]} > 0 )); then
  log "Installing AUR packages..."
  yay -S --needed --noconfirm --answerclean All --answerdiff None "${AUR_PACKAGES[@]}"
fi

log "Enabling system services..."
enable_system_service "NetworkManager.service"
enable_system_service "bluetooth.service"
enable_system_service "touchegg.service"

log "Enabling user services..."
systemctl --user disable --now pulseaudio.service pulseaudio.socket 2>/dev/null || true
systemctl --user mask pulseaudio.service pulseaudio.socket 2>/dev/null || true
enable_user_service "pipewire.service"
enable_user_service "pipewire-pulse.service"
enable_user_service "wireplumber.service"
enable_user_service "xsettingsd.service"

log "Setting executable permissions on scripts..."
SCRIPT_DIRS=(
  "$DEST_CONFIG/waybar/scripts"
  "$DEST_CONFIG/hypr/scripts"
  "$DEST_CONFIG/wofi/scripts"
  "$script_dir"
)

for dir in "${SCRIPT_DIRS[@]}"; do
  if [[ -d "$dir" ]]; then
    info "chmod +x on *.sh in $dir"
    find "$dir" -type f -name "*.sh" -exec chmod +x {} +
  fi
done

chmod +x "$script_dir/install.sh" 2>/dev/null || true

if have_cmd gsettings; then
  log "Applying GTK theme and cursor defaults..."
  gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' || true
  gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3-dark' || true
  gsettings set org.gnome.desktop.interface icon-theme 'Adwaita' || true
  gsettings set org.gnome.desktop.interface cursor-theme 'Bibata-Modern-Classic' || true
  gsettings set org.gnome.desktop.interface cursor-size 24 || true
fi

mkdir -p "$HOME/Pictures/Screenshots"
success "Ensured ~/Pictures/Screenshots exists"

log "Configuring Zsh..."
if have_cmd zsh && [[ "$SHELL" != "$(command -v zsh)" ]]; then
  chsh -s "$(command -v zsh)" "$USER" || warn "Could not change default shell to zsh"
fi

if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
  info "Installing Oh My Zsh..."
  RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c \
    "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" \
    --unattended
fi

log "Installing Powerlevel10k..."
if pacman -Si zsh-theme-powerlevel10k >/dev/null 2>&1; then
  sudo pacman -S --needed --noconfirm zsh-theme-powerlevel10k
else
  P10K_DIR="$HOME/.oh-my-zsh/custom/themes/powerlevel10k"
  if [[ ! -d "$P10K_DIR" ]]; then
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$P10K_DIR"
  fi
fi

if [[ -f "$ZSHRC" ]]; then
  if grep -q '^ZSH_THEME=' "$ZSHRC"; then
    sed -i 's|^ZSH_THEME=.*|ZSH_THEME="powerlevel10k/powerlevel10k"|' "$ZSHRC"
  else
    ensure_line_in_file "$ZSHRC" 'ZSH_THEME="powerlevel10k/powerlevel10k"'
  fi
fi

log "Installing Zsh plugins..."
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
mkdir -p "$ZSH_CUSTOM/plugins"

if [[ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]]; then
  info "Installing zsh-autosuggestions..."
  git clone https://github.com/zsh-users/zsh-autosuggestions \
    "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
fi

if [[ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]]; then
  info "Installing zsh-syntax-highlighting..."
  git clone https://github.com/zsh-users/zsh-syntax-highlighting \
    "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
fi

if [[ -f "$ZSHRC" ]]; then
  if grep -q '^plugins=' "$ZSHRC"; then
    sed -i 's/^plugins=.*/plugins=(git zsh-autosuggestions zsh-syntax-highlighting)/' "$ZSHRC"
  else
    ensure_line_in_file "$ZSHRC" 'plugins=(git zsh-autosuggestions zsh-syntax-highlighting)'
  fi
fi

if have_cmd xdg-user-dirs-update; then
  xdg-user-dirs-update
fi

log "Validating core commands used by the dotfiles..."
missing_commands=()
for cmd in hyprland waybar wofi mako wl-copy wl-paste cliphist blueman-applet bluetoothctl \
  udisksctl playerctl hyprpicker grimblast swappy swww-daemon; do
  have_cmd "$cmd" || missing_commands+=("$cmd")
done

if (( ${#missing_commands[@]} > 0 )); then
  warn "Some expected commands are still missing: ${missing_commands[*]}"
else
  success "Core dotfile dependencies look good"
fi

echo ""
success "Installation complete!"
info "Reboot or log out and back in so shell, services, and desktop changes fully apply."
info "After reboot, run 'p10k configure' once to finish your prompt setup."
