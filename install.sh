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

log()     { echo -e "${C_PURPLE}[+]${C_RESET} $*"; }
success() { echo -e "${C_GREEN}[✓]${C_RESET} $*"; }
warn()    { echo -e "${C_YELLOW}[!]${C_RESET} $*" >&2; }
err()     { echo -e "${C_RED}[✗]${C_RESET} $*" >&2; exit 1; }
info()    { echo -e "${C_CYAN}[i]${C_RESET} $*"; }

cleanup() {
  [[ -n "$WORK_DIR" && -d "$WORK_DIR" ]] && rm -rf "$WORK_DIR"
  [[ -n "$TMP_DIR"  && -d "$TMP_DIR"  ]] && rm -rf "$TMP_DIR"
}

trap cleanup EXIT

if [[ $EUID -eq 0 ]]; then
  err "Do not run this installer as root. Run it as your normal user."
fi

if ! command -v pacman >/dev/null 2>&1; then
  err "This installer supports Arch Linux only."
fi

# ── Dotfiles ────────────────────────────────────────────────────
SRC_DOTCONFIG="$script_dir/dot_config"
DEST_CONFIG="$HOME/.config"

if [[ ! -d "$SRC_DOTCONFIG" ]]; then
  warn "dot_config directory not found next to install.sh."

  if ! command -v git >/dev/null 2>&1; then
    info "Installing git (required to fetch dotfiles)"
    sudo pacman -S --needed --noconfirm git
  fi

  WORK_DIR="$(mktemp -d)"
  info "Cloning dotfiles repository..."
  git clone --depth=1 "$REPO_URL" "$WORK_DIR/repo"

  SRC_DOTCONFIG="$WORK_DIR/repo/dot_config"
  [[ -d "$SRC_DOTCONFIG" ]] || err "dot_config directory not found in cloned repository."
fi

mkdir -p "$DEST_CONFIG"

if ! command -v rsync >/dev/null 2>&1; then
  info "Installing rsync"
  sudo pacman -S --needed --noconfirm rsync
fi

log "Copying dotfiles..."
rsync -avh --mkpath "$SRC_DOTCONFIG"/ "$DEST_CONFIG"/

# ── Pacman packages ─────────────────────────────────────────────
PACMAN_PACKAGES=(
  # Core
  git zsh rsync curl wget

  # Terminal
  kitty

  # Hyprland (swww replaces hyprpaper)
  hyprland swww waybar wofi

  # Notifications
  mako libnotify

  # Clipboard
  wl-clipboard cliphist

  # Brightness / screen
  brightnessctl grim slurp

  # File manager
  nautilus

  # Network
  networkmanager network-manager-applet

  # Audio (PipeWire stack)
  pipewire pipewire-alsa pipewire-pulse
  wireplumber pavucontrol

  # Bluetooth
  bluez bluez-utils blueman

  # Gestures
  touchegg

  # GTK settings daemon (for dark theme in apps)
  xsettingsd

  # Fonts
  noto-fonts ttf-roboto
  ttf-jetbrains-mono
  ttf-nerd-fonts-symbols ttf-font-awesome

  # Portals & integration
  xdg-desktop-portal-hyprland xdg-user-dirs

  # Polkit
  polkit-gnome
)

# ── AUR packages ────────────────────────────────────────────────
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
)

# ── System update + pacman install ──────────────────────────────
log "Updating system..."
sudo pacman -Syu --noconfirm

log "Installing pacman packages..."
sudo pacman -S --needed --noconfirm "${PACMAN_PACKAGES[@]}"

# ── yay ─────────────────────────────────────────────────────────
if ! command -v yay >/dev/null 2>&1; then
  log "Installing yay (AUR helper)..."
  sudo pacman -S --needed --noconfirm base-devel git
  TMP_DIR="$(mktemp -d)"
  git clone https://aur.archlinux.org/yay.git "$TMP_DIR/yay"
  (cd "$TMP_DIR/yay" && makepkg -si --noconfirm)
fi

log "Installing AUR packages..."
yay -S --needed --noconfirm --answerclean All --answerdiff None "${AUR_PACKAGES[@]}"

# ── Services ────────────────────────────────────────────────────
log "Enabling system services..."

if command -v systemctl >/dev/null 2>&1; then

  # System-level
  for svc in NetworkManager bluetooth touchegg; do
    if systemctl list-unit-files | grep -q "^${svc}.service"; then
      sudo systemctl enable --now "$svc" && success "Enabled $svc"
    else
      warn "$svc.service not found, skipping"
    fi
  done

  # User-level: PipeWire
  log "Enabling PipeWire user services..."
  # Disable PulseAudio if still present
  systemctl --user disable --now pulseaudio pulseaudio.socket 2>/dev/null || true
  systemctl --user mask pulseaudio pulseaudio.socket 2>/dev/null || true

  for usvc in pipewire pipewire-pulse wireplumber; do
    if systemctl --user list-unit-files | grep -q "^${usvc}"; then
      systemctl --user enable --now "$usvc" && success "Enabled user service: $usvc"
    else
      warn "User service $usvc not found, skipping"
    fi
  done

  # xsettingsd
  systemctl --user enable --now xsettingsd.service 2>/dev/null || true

  # swww wallpaper daemon
  if command -v swww-daemon >/dev/null 2>&1; then
    swww-daemon &disown 2>/dev/null || true
    success "Started swww-daemon"
  fi

fi

# ── Script permissions ──────────────────────────────────────────
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

# Make install.sh itself executable
chmod +x "$script_dir/install.sh" 2>/dev/null || true

# ── GTK dark theme + cursor ─────────────────────────────────────
if command -v gsettings >/dev/null 2>&1; then
  log "Applying dark GTK theme and cursor..."
  gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'           || true
  gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3-dark'            || true
  gsettings set org.gnome.desktop.interface cursor-theme 'Bibata-Modern-Classic' || true
  gsettings set org.gnome.desktop.interface cursor-size 24                       || true
fi

# ── Screenshots directory ────────────────────────────────────────
mkdir -p "$HOME/Pictures/Screenshots"
success "Created ~/Pictures/Screenshots"

# ── Zsh + Oh My Zsh ─────────────────────────────────────────────
log "Configuring Zsh..."

if command -v zsh >/dev/null 2>&1; then
  if [[ "$SHELL" != "$(command -v zsh)" ]]; then
    chsh -s "$(command -v zsh)" "$USER" || warn "Could not change default shell to zsh"
  fi
fi

if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
  info "Installing Oh My Zsh..."
  RUNZSH=no KEEP_ZSHRC=yes sh -c \
    "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

# ── Powerlevel10k ───────────────────────────────────────────────
log "Installing Powerlevel10k..."

if pacman -Si zsh-theme-powerlevel10k &>/dev/null; then
  sudo pacman -S --needed --noconfirm zsh-theme-powerlevel10k
  P10K_PATH="/usr/share/zsh-theme-powerlevel10k/powerlevel10k.zsh-theme"
else
  P10K_DIR="$HOME/.oh-my-zsh/custom/themes/powerlevel10k"
  if [[ ! -d "$P10K_DIR" ]]; then
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$P10K_DIR"
  fi
  P10K_PATH="$P10K_DIR/powerlevel10k.zsh-theme"
fi

# Set p10k as theme in .zshrc if not already set
ZSHRC="$HOME/.zshrc"
if [[ -f "$ZSHRC" ]]; then
  if grep -q 'ZSH_THEME=' "$ZSHRC"; then
    sed -i 's/^ZSH_THEME=.*/ZSH_THEME="powerlevel10k\/powerlevel10k"/' "$ZSHRC"
  else
    echo 'ZSH_THEME="powerlevel10k/powerlevel10k"' >> "$ZSHRC"
  fi
fi

# ── Zsh plugins ─────────────────────────────────────────────────
log "Installing Zsh plugins..."

ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
mkdir -p "$ZSH_CUSTOM/plugins"

# zsh-autosuggestions
if [[ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]]; then
  info "Installing zsh-autosuggestions..."
  git clone https://github.com/zsh-users/zsh-autosuggestions \
    "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
fi

# zsh-syntax-highlighting
if [[ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]]; then
  info "Installing zsh-syntax-highlighting..."
  git clone https://github.com/zsh-users/zsh-syntax-highlighting \
    "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
fi

# Enable plugins in .zshrc
if [[ -f "$ZSHRC" ]]; then
  if grep -q '^plugins=' "$ZSHRC"; then
    sed -i 's/^plugins=.*/plugins=(git zsh-autosuggestions zsh-syntax-highlighting)/' "$ZSHRC"
  else
    echo 'plugins=(git zsh-autosuggestions zsh-syntax-highlighting)' >> "$ZSHRC"
  fi
fi

# ── XDG user dirs ───────────────────────────────────────────────
if command -v xdg-user-dirs-update >/dev/null 2>&1; then
  xdg-user-dirs-update
fi

# ── Done ─────────────────────────────────────────────────────────
echo ""
success "Installation complete!"
info "Please reboot for all changes (PipeWire, shell, services) to take effect."
info "After reboot, run 'p10k configure' in your terminal to set up your prompt."
