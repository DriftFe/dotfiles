#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

# ╔═══════════════════════════════════════════════════════════════════════╗
# ║           Lavender Dotfiles Installer for Arch Linux                  ║
# ╚═══════════════════════════════════════════════════════════════════════╝

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SRC_DOTCONFIG="$script_dir/dot_config"

# Color codes for pretty output
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

require_arch() {
  if ! command -v pacman >/dev/null 2>&1; then
    err "This installer requires Arch Linux (pacman not found)."
  fi
}

ensure_sudo() {
  if command -v sudo >/dev/null 2>&1; then
    if ! sudo -v; then
      err "sudo authentication failed. Run this script with sufficient privileges."
    fi
    while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
  else
    if [[ $EUID -ne 0 ]]; then
      err "sudo not found. Re-run as root (or install sudo)."
    fi
  fi
}

pac() {
  if command -v sudo >/dev/null 2>&1; then sudo pacman "$@"; else pacman "$@"; fi
}

build_yay() {
  local tmpdir
  tmpdir="$(mktemp -d)"
  log "Bootstrapping yay from AUR in $tmpdir"
  pushd "$tmpdir" >/dev/null
  if git clone --depth=1 https://aur.archlinux.org/yay-bin.git >/dev/null 2>&1; then
    cd yay-bin
  else
    warn "Cloning yay-bin failed, trying yay"
    git clone --depth=1 https://aur.archlinux.org/yay.git
    cd yay
  fi
  makepkg -si --noconfirm
  popd >/dev/null
  rm -rf "$tmpdir"
  success "yay AUR helper installed"
}

ensure_yay() {
  if command -v yay >/dev/null 2>&1; then
    return
  fi
  log "Installing prerequisites for AUR builds (base-devel, git)"
  pac -S --needed --noconfirm base-devel git
  build_yay
}

install_pkg() {
  local pkg="$1"
  if pacman -Si --quiet "$pkg" >/dev/null 2>&1; then
    log "Installing (repo) $pkg"
    pac -S --needed --noconfirm "$pkg"
  else
    aur_pkgs+=("$pkg")
  fi
}

install_pkgs_auto() {
  local -a pkgs=("$@")
  local -a aur_to_install=()
  aur_pkgs=()

  echo
  log "Processing ${#pkgs[@]} packages..."

  for p in "${pkgs[@]}"; do
    install_pkg "$p"
  done

  if ((${#aur_pkgs[@]} > 0)); then
    echo
    info "AUR packages detected: ${aur_pkgs[*]}"
    ensure_yay
    log "Installing ${#aur_pkgs[@]} AUR packages..."
    yay -S --needed --noconfirm "${aur_pkgs[@]}"
  fi

  success "All packages installed successfully"
}

build_package_list() {
  local -a pkgs=()

  info "Detecting required packages from configuration..."

  # Core utilities
  pkgs+=(git curl wget)

  # Fonts (add more as needed)
  pkgs+=(ttf-jetbrains-mono ttf-jetbrains-mono-nerd ttf-font-awesome ttf-nerd-fonts-symbols ttf-nerd-fonts-symbols-mono noto-fonts noto-fonts-emoji ttf-dejavu)

  # Add more package detection logic here if needed

  declare -Ag seen=()
  packages=()
  for p in "${pkgs[@]}"; do
    if [[ -z "${seen[$p]:-}" ]]; then
      packages+=("$p")
      seen[$p]=1
    fi
  done
  success "Detected ${#packages[@]} packages to install"
}

copy_wallpapers() {
  local wp_src="$SRC_DOTCONFIG/wallpapers"
  if [[ -d "$wp_src" ]]; then
    mkdir -p "$HOME/.wallpapers"
    local count
    count=$(find "$wp_src" -type f | wc -l)
    cp -a "$wp_src/." "$HOME/.wallpapers/"
    success "Copied $count wallpapers to ~/.wallpapers"
  else
    warn "No wallpapers directory found at $wp_src; skipping."
  fi
}

copy_dotconfig() {
  echo
  log "Deploying configuration files to $HOME/.config"
  
  # Verify source directory exists
  if [[ ! -d "$SRC_DOTCONFIG" ]]; then
    err "Source directory $SRC_DOTCONFIG does not exist!"
  fi
  
  info "Source directory: $SRC_DOTCONFIG"
  info "Listing contents:"
  ls -la "$SRC_DOTCONFIG" || warn "Could not list source directory"
  
  mkdir -p "$HOME/.config"

  local -a skip=(wallpapers)
  local copied=0

  shopt -s nullglob dotglob
  for entry in "$SRC_DOTCONFIG"/*; do
    # Check if glob matched anything
    if [[ ! -e "$entry" ]]; then
      warn "No files found in $SRC_DOTCONFIG"
      break
    fi
    
    local name
    name="$(basename "$entry")"

    # Skip filtered entries
    local should_skip=0
    for s in "${skip[@]}"; do
      if [[ "$name" == "$s" ]]; then
        should_skip=1
        break
      fi
    done
    
    if [[ $should_skip -eq 1 ]]; then
      info "  ⊝ Skipping $name"
      continue
    fi

    local dest="$HOME/.config/$name"
    if [[ -d "$entry" ]]; then
      mkdir -p "$dest"
      cp -rf "$entry/." "$dest/"
      info "  ├─ $name/ → ~/.config/$name/"
      ((copied++))
    else
      cp -f "$entry" "$HOME/.config/"
      info "  ├─ $name → ~/.config/$name"
      ((copied++))
    fi
  done
  shopt -u nullglob dotglob

  # Copy files like .zshrc and starship.toml from repo root if present
  if [[ -f "$script_dir/.zshrc" ]]; then
    cp -f "$script_dir/.zshrc" "$HOME/.zshrc"
    info "  └─ .zshrc → ~/"
    ((copied++))
  fi
  if [[ -f "$script_dir/starship.toml" ]]; then
    mkdir -p "$HOME/.config"
    cp -f "$script_dir/starship.toml" "$HOME/.config/starship.toml"
    info "  └─ starship.toml → ~/.config/"
    ((copied++))
  fi
  
  if [[ $copied -eq 0 ]]; then
    warn "No files were copied! Check the source directory."
  else
    success "Deployed $copied configuration items"
  fi
}

set_hyprland_default() {
  log "Configuring GDM to use Hyprland as default session"
  local target_user="${SUDO_USER:-$USER}"
  local accountsservice_file="/var/lib/AccountsService/users/$target_user"

  if [[ ! -f "$accountsservice_file" ]]; then
    if command -v sudo >/dev/null 2>&1; then
      sudo mkdir -p "$(dirname "$accountsservice_file")"
      sudo tee "$accountsservice_file" >/dev/null <<EOF
[User]
Session=hyprland
XSession=hyprland
SystemAccount=false
EOF
    else
      mkdir -p "$(dirname "$accountsservice_file")"
      tee "$accountsservice_file" >/dev/null <<EOF
[User]
Session=hyprland
XSession=hyprland
SystemAccount=false
EOF
    fi
    success "Created AccountsService profile for $target_user"
  else
    if command -v sudo >/dev/null 2>&1; then
      sudo sed -i '/^\[User\]/a Session=hyprland\nXSession=hyprland' "$accountsservice_file" 2>/dev/null || true
      sudo sed -i 's/^Session=.*/Session=hyprland/' "$accountsservice_file" 2>/dev/null || true
      sudo sed -i 's/^XSession=.*/XSession=hyprland/' "$accountsservice_file" 2>/dev/null || true
    else
      sed -i '/^\[User\]/a Session=hyprland\nXSession=hyprland' "$accountsservice_file" 2>/dev/null || true
      sed -i 's/^Session=.*/Session=hyprland/' "$accountsservice_file" 2>/dev/null || true
      sed -i 's/^XSession=.*/XSession=hyprland/' "$accountsservice_file" 2>/dev/null || true
    fi
    success "Updated AccountsService profile"
  fi
}

enable_services() {
  if ! command -v systemctl >/dev/null 2>&1; then
    warn "systemctl not available; skipping service enablement."
    return
  fi

  log "Enabling system services"
  if command -v sudo >/dev/null 2>&1; then
    sudo systemctl enable --now gdm.service NetworkManager.service bluetooth.service upower.service 2>/dev/null || true
  else
    systemctl enable --now gdm.service NetworkManager.service bluetooth.service upower.service 2>/dev/null || true
  fi
  success "System services enabled: GDM, NetworkManager, Bluetooth, UPower"

  log "Enabling user services"
  if [[ -n "${SUDO_USER:-}" && "$EUID" -eq 0 ]]; then
    sudo -u "$SUDO_USER" systemctl --user enable --now \
      pipewire.service \
      pipewire-pulse.service \
      wireplumber.service \
      xdg-desktop-portal-hyprland.service \
      xdg-desktop-portal.service \
      touchegg.service 2>/dev/null || true
  else
    systemctl --user enable --now \
      pipewire.service \
      pipewire-pulse.service \
      wireplumber.service \
      xdg-desktop-portal-hyprland.service \
      xdg-desktop-portal.service \
      touchegg.service 2>/dev/null || true
  fi
  success "User services enabled: PipeWire, Portals, Touchegg"
}

main() {
  require_arch
  ensure_sudo

  echo
  log "Updating system packages"
  pac -Syu --noconfirm

  build_package_list
  if (((${#packages[@]} == 0))); then
    warn "No packages detected; proceeding with configuration only."
  else
    install_pkgs_auto "${packages[@]}"
  fi

  copy_dotconfig
  copy_wallpapers
  set_hyprland_default
  enable_services

  success "Dotfiles installation complete!"
}

main "$@"
