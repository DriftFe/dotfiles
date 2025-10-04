#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

# ╔═══════════════════════════════════════════════════════════════╗
# ║           Lavender Dotfiles >~< Installer                     ║
# ║        Automated Hyprland Setup for Arch Linux                ║
# ╚═══════════════════════════════════════════════════════════════╝

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SRC_DOTCONFIG="$script_dir/dot_config"

# Color codes for pretty output
C_RESET='\033[0m'
C_PURPLE='\033[0;35m'
C_PINK='\033[1;35m'
C_CYAN='\033[0;36m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[1;33m'
C_RED='\033[0;31m'
C_BLUE='\033[0;34m'

log() { echo -e "${C_PURPLE}[+]${C_RESET} $*"; }
success() { echo -e "${C_GREEN}[✓]${C_RESET} $*"; }
warn() { echo -e "${C_YELLOW}[!]${C_RESET} $*" >&2; }
err() { echo -e "${C_RED}[✗]${C_RESET} $*" >&2; exit 1; }
info() { echo -e "${C_CYAN}[i]${C_RESET} $*"; }

print_banner() {
  echo -e "${C_PINK}"
  cat << "EOF"
    ╦  ┌─┐┬  ┬┌─┐┌┐┌┌┬┐┌─┐┬─┐  ╔╦╗┌─┐┌┬┐┌─┐┬┬  ┌─┐┌─┐
    ║  ├─┤└┐┌┘├┤ │││ ││├┤ ├┬┘   ║║│ │ │ ├┤ ││  ├┤ └─┐
    ╩═╝┴ ┴ └┘ └─┘┘└┘─┴┘└─┘┴└─  ═╩╝└─┘ ┴ └  ┴┴─┘└─┘└─┘
                    >~< Installer v2.0
EOF
  echo -e "${C_RESET}"
}

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
    # Keep sudo alive
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

  # Essential Hyprland ecosystem
  pkgs+=(
    hyprland
    hyprlock
    hyprpaper
    kitty
    gdm
    waybar
    mako
    wofi
    waypaper
  )

  # Screenshot and screen capture
  pkgs+=(
    grim
    slurp
    grimblast
    satty
    wl-clipboard
    cliphist
  )

  # Shell environment
  [[ -d "$SRC_DOTCONFIG/zsh" ]] && pkgs+=(zsh zsh-completions fzf)
  [[ -f "$script_dir/starship.toml" ]] && pkgs+=(starship)

  # Application configs
  local -a direct=(cava fastfetch vesktop simple-update-notifier)
  for d in "${direct[@]}"; do
    [[ -d "$SRC_DOTCONFIG/$d" ]] && pkgs+=("$d")
  done

  # GTK theming
  [[ -d "$SRC_DOTCONFIG/gtk-4.0" || -d "$SRC_DOTCONFIG/private_gtk-3.0" ]] && pkgs+=(gtk3 gtk4)

  # System utilities and dependencies
  pkgs+=(
    # Brightness and audio
    brightnessctl
    pavucontrol
    playerctl
    pamixer
    
    # Audio server
    pipewire pipewire-pulse pipewire-alsa pipewire-jack wireplumber
    
    # Bluetooth
    bluez bluez-utils blueman
    
    # Network
    networkmanager network-manager-applet
    
    # Power management
    upower
    acpi
    
    # Notifications
    libnotify
    dunst
    
    # File managers
    nautilus
    thunar
    
    # Qt theming
    qt5ct qt5-wayland qt6-wayland
    kvantum kvantum-qt5
    
    # Cursors and fonts
    bibata-cursor-theme
    ttf-jetbrains-mono
    ttf-jetbrains-mono-nerd
    ttf-font-awesome
    ttf-nerd-fonts-symbols
    ttf-nerd-fonts-symbols-mono
    noto-fonts
    noto-fonts-emoji
    ttf-dejavu
    
    # XDG portals
    xdg-desktop-portal-hyprland
    xdg-desktop-portal-gtk
    xdg-utils
    
    # Wayland essentials
    xorg-xwayland
    wayland-protocols
    
    # Input and gestures
    touchegg
    
    # Screen recording
    gpu-screen-recorder
    
    # Authentication
    polkit-gnome
    
    # GTK theme tools
    nwg-look
    
    # System monitors
    btop
    
    # Media
    mpv
    imv
  )

  # Deduplicate
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

copy_dotconfig() {
  echo
  log "Deploying configuration files to $HOME/.config"
  mkdir -p "$HOME/.config"

  local -a skip=(wallpapers)
  local copied=0

  shopt -s nullglob dotglob
  for entry in "$SRC_DOTCONFIG"/*; do
    local name
    name="$(basename "$entry")"

    # Skip filtered entries
    for s in "${skip[@]}"; do
      if [[ "$name" == "$s" ]]; then
        continue 2
      fi
    done

    local dest="$HOME/.config/$name"
    if [[ -d "$entry" ]]; then
      mkdir -p "$dest"
      cp -a "$entry/." "$dest/"
      info "  ├─ $name/"
      ((copied++))
    else
      cp -a "$entry" "$HOME/.config/"
      info "  ├─ $name"
      ((copied++))
    fi
  done
  shopt -u nullglob dotglob

  # Special files
  if [[ -f "$script_dir/starship.toml" ]]; then
    cp -a "$script_dir/starship.toml" "$HOME/.config/starship.toml"
    info "  ├─ starship.toml"
    ((copied++))
  fi

  if [[ -f "$script_dir/.zshrc" ]]; then
    cp -a "$script_dir/.zshrc" "$HOME/.zshrc"
    info "  └─ .zshrc → ~/"
    ((copied++))
  fi
  
  success "Deployed $copied configuration items"
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

chmod_scripts() {
  echo
  log "Setting executable permissions on scripts"
  local target_user="${SUDO_USER:-$USER}"
  local script_count=0
  
  if [[ -d "$HOME/.config" ]]; then
    while IFS= read -r -d '' script; do
      chmod +x "$script"
      ((script_count++))
    done < <(find "$HOME/.config" -type f \( -name "*.sh" -o -name "*.bash" -o -name "*.zsh" \) -print0 2>/dev/null)
  fi
  
  # Waybar scripts
  if [[ -d "$HOME/.config/waybar/scripts" ]]; then
    find "$HOME/.config/waybar/scripts" -type f -exec chmod +x {} \; 2>/dev/null || true
  fi
  
  # Hypr scripts
  if [[ -d "$HOME/.config/hypr/scripts" ]]; then
    find "$HOME/.config/hypr/scripts" -type f -exec chmod +x {} \; 2>/dev/null || true
  fi

  # Fix ownership if running with sudo
  if [[ -n "${SUDO_USER:-}" && "$EUID" -eq 0 ]]; then
    chown -R "$target_user:$target_user" "$HOME/.config" 2>/dev/null || true
  fi
  
  success "Made $script_count scripts executable"
}

setup_oh_my_zsh() {
  echo
  log "Setting up Oh My Zsh and Powerlevel10k"
  local target_user="${SUDO_USER:-$USER}"
  local user_home
  
  # Determine the actual user's home directory
  if [[ -n "${SUDO_USER:-}" ]]; then
    user_home=$(eval echo ~"$SUDO_USER")
  else
    user_home="$HOME"
  fi
  
  # Install Oh My Zsh
  if [[ ! -d "$user_home/.oh-my-zsh" ]]; then
    log "Installing Oh My Zsh..."
    if [[ -n "${SUDO_USER:-}" && "$EUID" -eq 0 ]]; then
      sudo -u "$target_user" sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    else
      sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    fi
    success "Oh My Zsh installed"
  else
    info "Oh My Zsh already installed, skipping..."
  fi
  
  # Install Powerlevel10k theme
  if [[ ! -d "$user_home/.oh-my-zsh/custom/themes/powerlevel10k" ]]; then
    log "Installing Powerlevel10k theme..."
    if [[ -n "${SUDO_USER:-}" && "$EUID" -eq 0 ]]; then
      sudo -u "$target_user" git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$user_home/.oh-my-zsh/custom/themes/powerlevel10k"
    else
      git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$user_home/.oh-my-zsh/custom/themes/powerlevel10k"
    fi
    success "Powerlevel10k installed"
  else
    info "Powerlevel10k already installed, skipping..."
  fi
  
  # Install popular Oh My Zsh plugins
  log "Installing Oh My Zsh plugins..."
  
  # zsh-autosuggestions
  if [[ ! -d "$user_home/.oh-my-zsh/custom/plugins/zsh-autosuggestions" ]]; then
    if [[ -n "${SUDO_USER:-}" && "$EUID" -eq 0 ]]; then
      sudo -u "$target_user" git clone https://github.com/zsh-users/zsh-autosuggestions "$user_home/.oh-my-zsh/custom/plugins/zsh-autosuggestions"
    else
      git clone https://github.com/zsh-users/zsh-autosuggestions "$user_home/.oh-my-zsh/custom/plugins/zsh-autosuggestions"
    fi
  fi
  
  # zsh-syntax-highlighting
  if [[ ! -d "$user_home/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting" ]]; then
    if [[ -n "${SUDO_USER:-}" && "$EUID" -eq 0 ]]; then
      sudo -u "$target_user" git clone https://github.com/zsh-users/zsh-syntax-highlighting "$user_home/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting"
    else
      git clone https://github.com/zsh-users/zsh-syntax-highlighting "$user_home/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting"
    fi
  fi
  
  # zsh-completions
  if [[ ! -d "$user_home/.oh-my-zsh/custom/plugins/zsh-completions" ]]; then
    if [[ -n "${SUDO_USER:-}" && "$EUID" -eq 0 ]]; then
      sudo -u "$target_user" git clone https://github.com/zsh-users/zsh-completions "$user_home/.oh-my-zsh/custom/plugins/zsh-completions"
    else
      git clone https://github.com/zsh-users/zsh-completions "$user_home/.oh-my-zsh/custom/plugins/zsh-completions"
    fi
  fi
  
  success "Oh My Zsh plugins installed (autosuggestions, syntax-highlighting, completions)"
  
  # Set zsh as default shell
  if [[ "$SHELL" != "$(which zsh)" ]]; then
    log "Setting zsh as default shell for $target_user"
    if command -v sudo >/dev/null 2>&1; then
      sudo chsh -s "$(which zsh)" "$target_user" 2>/dev/null || warn "Could not change default shell. Run 'chsh -s \$(which zsh)' manually."
    else
      chsh -s "$(which zsh)" "$target_user" 2>/dev/null || warn "Could not change default shell. Run 'chsh -s \$(which zsh)' manually."
    fi
    success "Default shell set to zsh"
  fi
  
  # Fix ownership
  if [[ -n "${SUDO_USER:-}" && "$EUID" -eq 0 ]]; then
    chown -R "$target_user:$target_user" "$user_home/.oh-my-zsh" 2>/dev/null || true
    chown "$target_user:$target_user" "$user_home/.zshrc" 2>/dev/null || true
  fi
}

ensure_user_in_group() {
  local grp="$1"
  local target_user="${SUDO_USER:-$USER}"
  if ! getent group "$grp" >/dev/null; then
    warn "Group $grp does not exist; skipping."
    return
  fi
  if id -nG "$target_user" | grep -qw "$grp"; then
    return
  fi
  log "Adding user $target_user to group $grp"
  if command -v sudo >/dev/null 2>&1; then
    sudo gpasswd -a "$target_user" "$grp" >/dev/null || true
  else
    gpasswd -a "$target_user" "$grp" >/dev/null || true
  fi
}

userctl() {
  local target_user="${SUDO_USER:-$USER}"
  if [[ -n "${SUDO_USER:-}" && "$EUID" -eq 0 ]]; then
    sudo -u "$target_user" systemctl --user "$@"
  else
    systemctl --user "$@"
  fi
}

set_hyprland_default() {
  echo
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

  echo
  log "Enabling system services"
  if command -v sudo >/dev/null 2>&1; then
    sudo systemctl enable --now gdm.service NetworkManager.service bluetooth.service upower.service 2>/dev/null || true
  else
    systemctl enable --now gdm.service NetworkManager.service bluetooth.service upower.service 2>/dev/null || true
  fi
  success "System services enabled: GDM, NetworkManager, Bluetooth, UPower"

  log "Enabling user services"
  userctl enable --now \
    pipewire.service \
    pipewire-pulse.service \
    wireplumber.service \
    xdg-desktop-portal-hyprland.service \
    xdg-desktop-portal.service \
    touchegg.service 2>/dev/null || true
  success "User services enabled: PipeWire, Portals, Touchegg"
}

setup_directories() {
  echo
  log "Creating user directories"
  mkdir -p "$HOME/Videos" "$HOME/Pictures/Screenshots" "$HOME/Documents" "$HOME/Downloads"
  success "User directories created"
}

print_completion() {
  local target_user="${SUDO_USER:-$USER}"
  
  echo
  echo -e "${C_PINK}╔═══════════════════════════════════════════════════════════════╗${C_RESET}"
  echo -e "${C_PINK}║${C_RESET}  ✨ ${C_PURPLE}Lavender Dotfiles Installation Complete!${C_RESET} ✨              ${C_PINK}║${C_RESET}"
  echo -e "${C_PINK}╚═══════════════════════════════════════════════════════════════╝${C_RESET}"
  echo
  echo -e "${C_CYAN}━━━ 🔄 Next Steps ━━━${C_RESET}"
  echo
  echo -e "${C_GREEN}1.${C_RESET} ${C_YELLOW}RESTART YOUR SYSTEM${C_RESET}"
  echo -e "   ${C_BLUE}└─${C_RESET} GDM will automatically start with Hyprland as default"
  echo
  echo -e "${C_GREEN}2.${C_RESET} ${C_YELLOW}Check Keybindings${C_RESET}"
  echo -e "   ${C_BLUE}├─${C_RESET} Click the ⌨️  keyboard icon in waybar (top bar)"
  echo -e "   ${C_BLUE}└─${C_RESET} Or press ${C_PURPLE}SUPER + /${C_RESET} to view all keybinds"
  echo
  echo -e "${C_CYAN}━━━ ⌨️  Essential Keybinds ━━━${C_RESET}"
  echo
  echo -e "   ${C_PURPLE}SUPER + Return${C_RESET}    → Open terminal (Kitty)"
  echo -e "   ${C_PURPLE}SUPER + R${C_RESET}         → App launcher (Wofi)"
  echo -e "   ${C_PURPLE}SUPER + E${C_RESET}         → File manager (Nautilus)"
  echo -e "   ${C_PURPLE}SUPER + Q${C_RESET}         → Close window"
  echo -e "   ${C_PURPLE}SUPER + M${C_RESET}         → Exit Hyprland"
  echo -e "   ${C_PURPLE}SUPER + L${C_RESET}         → Lock screen (Hyprlock)"
  echo -e "   ${C_PURPLE}SUPER + F${C_RESET}         → Toggle fullscreen"
  echo -e "   ${C_PURPLE}SUPER + V${C_RESET}         → Toggle floating"
  echo -e "   ${C_PURPLE}SUPER + 1-9${C_RESET}       → Switch workspace"
  echo
  echo -e "${C_CYAN}━━━ 📸 Screenshots ━━━${C_RESET}"
  echo
  echo -e "   ${C_PURPLE}Print Screen${C_RESET}      → Full screen → Satty editor"
  echo -e "   ${C_PURPLE}SUPER + S${C_RESET}         → Area selection → Satty editor"
  echo -e "   ${C_PURPLE}SHIFT + Print${C_RESET}     → Area selection → Clipboard"
  echo
  echo -e "${C_CYAN}━━━ 🎨 Customization ━━━${C_RESET}"
  echo
  echo -e "   ${C_GREEN}Wallpapers:${C_RESET}   ${C_PURPLE}waypaper${C_RESET} or browse ${C_BLUE}~/.wallpapers/${C_RESET}"
  echo -e "   ${C_GREEN}GTK Themes:${C_RESET}   ${C_PURPLE}nwg-look${C_RESET}"
  echo -e "   ${C_GREEN}Qt Themes:${C_RESET}    ${C_PURPLE}qt5ct${C_RESET} or ${C_PURPLE}kvantummanager${C_RESET}"
  echo -e "   ${C_GREEN}Waybar:${C_RESET}       ${C_BLUE}~/.config/waybar/config${C_RESET}"
  echo -e "   ${C_GREEN}Hyprland:${C_RESET}     ${C_BLUE}~/.config/hypr/hyprland.conf${C_RESET}"
  echo
  echo -e "${C_CYAN}━━━ 🔧 Useful Commands ━━━${C_RESET}"
  echo
  echo -e "   ${C_PURPLE}hyprctl reload${C_RESET}                  → Reload Hyprland config"
  echo -e "   ${C_PURPLE}killall waybar && waybar &${C_RESET}      → Restart waybar"
  echo -e "   ${C_PURPLE}brightnessctl set 50%${C_RESET}           → Set brightness to 50%"
  echo -e "   ${C_PURPLE}pactl set-sink-volume @DEFAULT@ +5%${C_RESET} → Increase volume"
  echo
  echo -e "${C_CYAN}━━━ 💡 Tips ━━━${C_RESET}"
  echo
  echo -e "   • Hold ${C_PURPLE}SUPER${C_RESET} and drag windows to move them"
  echo -e "   • Hold ${C_PURPLE}SUPER + Right-click${C_RESET} to resize windows"
  echo -e "   • Use ${C_PURPLE}SUPER + Mouse Wheel${C_RESET} to switch workspaces"
  echo -e "   • Installed as user: ${C_GREEN}$target_user${C_RESET}"
  echo
  echo -e "${C_PINK}╔═══════════════════════════════════════════════════════════════╗${C_RESET}"
  echo -e "${C_PINK}║${C_RESET}          💜 Enjoy your beautiful Lavender setup! >~<         ${C_PINK}║${C_RESET}"
  echo -e "${C_PINK}╚═══════════════════════════════════════════════════════════════╝${C_RESET}"
  echo
}

main() {
  print_banner
  
  require_arch
  ensure_sudo

  echo
  log "Updating system packages"
  pac -Syu --noconfirm

  log "Ensuring base development tools"
  pac -S --needed --noconfirm base-devel git

  build_package_list
  if ((${#packages[@]} == 0)); then
    warn "No packages detected; proceeding with configuration only."
  else
    install_pkgs_auto "${packages[@]}"
  fi

  setup_directories
  
  log "Configuring user groups"
  ensure_user_in_group video
  ensure_user_in_group input

  enable_services
  copy_dotconfig
  copy_wallpapers
  chmod_scripts
  set_hyprland_default

  print_completion
}

main "$@"
