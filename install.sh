#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

# ╔═══════════════════════════════════════════════════════════════╗
# ║                 Dotfiles Installer for Arch Linux             ║
# ╚═══════════════════════════════════════════════════════════════╝

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

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

if ! command -v pacman >/dev/null 2>&1; then
  err "This installer is Arch Linux only (requires pacman)."
fi

SRC_DOTCONFIG="$script_dir/dot_config"
DEST_CONFIG="$HOME/.config"

if [[ ! -d "$SRC_DOTCONFIG" ]]; then
  err "Source dot_config directory not found: $SRC_DOTCONFIG"
fi

log "Copying dotfiles from $SRC_DOTCONFIG to $DEST_CONFIG ..."
mkdir -p "$DEST_CONFIG"
# Ensure rsync is present before using it
if ! command -v rsync >/dev/null 2>&1; then
  info "Installing rsync ..."
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

AUR_PACKAGES=(
  waypaper
  gpu-screen-recorder
  nerd-fonts-jetbrains-mono
)

log "Synchronizing pacman database and upgrading system ..."
sudo pacman -Syu --noconfirm

log "Installing packages with pacman ..."
sudo pacman -S --needed --noconfirm "${PACMAN_PACKAGES[@]}"

# Install yay if missing  
if ! command -v yay >/dev/null 2>&1; then
  log "Installing yay (AUR helper) ..."
  sudo pacman -S --needed --noconfirm base-devel git
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT
  git clone https://aur.archlinux.org/yay.git "$tmpdir/yay"
  (cd "$tmpdir/yay" && makepkg -si --noconfirm)
fi

log "Installing AUR packages with yay ..."
yay -S --needed --noconfirm "${AUR_PACKAGES[@]}"

# Enable and start services 
if command -v systemctl >/dev/null 2>&1; then
  log "Enabling core services ..."
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

# Ensure waybar helper scripts are executable if present  
SCRIPT_DIRS=(
  "$DEST_CONFIG/waybar/scripts"
)
for dir in "${SCRIPT_DIRS[@]}"; do
  if [[ -d "$dir" ]]; then
    info "Setting scripts executable in: $dir"
    find "$dir" -type f -name "*.sh" -print0 | xargs -0 chmod +x || true
  fi
done

# Make other common script locations executable  
if [[ -d "$DEST_CONFIG/hypr/scripts" ]]; then
  find "$DEST_CONFIG/hypr/scripts" -type f -name "*.sh" -print0 | xargs -0 chmod +x || true
fi

# Apply gtk dark preference 
if command -v gsettings >/dev/null 2>&1; then
  log "Applying GNOME dark color-scheme ..."
  gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' || true
  gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita-dark' || true
fi

# Zsh environment: Oh My Zsh, Powerlevel10k, autocorrect & plugins
log "Configuring Zsh, Oh My Zsh, Powerlevel10k, and autocorrect"
# Default shell to zsh
if [[ "$(basename "$SHELL")" != "zsh" ]] && command -v chsh >/dev/null 2>&1; then
  chsh -s /usr/bin/zsh "$USER" || warn "Failed to set zsh as default shell"
fi
# Oh My Zsh
if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
  info "Installing Oh My Zsh"
  RUNZSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" || warn "Oh My Zsh install failed"
fi
# Powerlevel10k theme: use system package if present, else clone into OMZ custom
if pacman -Si --quiet zsh-theme-powerlevel10k >/dev/null 2>&1; then
  sudo pacman -S --needed --noconfirm zsh-theme-powerlevel10k || true
else
  if [[ ! -d "$HOME/.oh-my-zsh/custom/themes/powerlevel10k" ]]; then
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$HOME/.oh-my-zsh/custom/themes/powerlevel10k" || true
  fi
fi
# Plugins
mkdir -p "$HOME/.oh-my-zsh/custom/plugins"
[[ -d "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions" ]] || git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions" || true
[[ -d "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting" ]] || git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting" || true
[[ -d "$HOME/.oh-my-zsh/custom/plugins/zsh-autocomplete" ]] || git clone --depth=1 https://github.com/marlonrichert/zsh-autocomplete "$HOME/.oh-my-zsh/custom/plugins/zsh-autocomplete" || true

# .zshrc adjustments (theme, plugins, autocorrect)
if [[ -f "$HOME/.zshrc" ]]; then
  sed -i 's/^ZSH_THEME=.*/ZSH_THEME="powerlevel10k\/powerlevel10k"/' "$HOME/.zshrc" || true
  if grep -q '^plugins=' "$HOME/.zshrc"; then
    sed -i 's/^plugins=.*/plugins=(git zsh-autosuggestions zsh-syntax-highlighting zsh-autocomplete correction)/' "$HOME/.zshrc" || true
  else
    echo 'plugins=(git zsh-autosuggestions zsh-syntax-highlighting zsh-autocomplete correction)' >> "$HOME/.zshrc"
  fi
  grep -q 'source ~/.p10k.zsh' "$HOME/.zshrc" || echo '[[ -r ~/.p10k.zsh ]] && source ~/.p10k.zsh' >> "$HOME/.zshrc"
  grep -q '^setopt[[:space:]]\+CORRECT_ALL' "$HOME/.zshrc" || echo 'setopt CORRECT_ALL' >> "$HOME/.zshrc"
else
  cat > "$HOME/.zshrc" <<'RC'
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="powerlevel10k/powerlevel10k"
plugins=(git zsh-autosuggestions zsh-syntax-highlighting zsh-autocomplete correction)
source $ZSH/oh-my-zsh.sh
[[ -r ~/.p10k.zsh ]] && source ~/.p10k.zsh
setopt CORRECT_ALL
RC
fi

success "Dotfiles installation complete on Arch Linux."
