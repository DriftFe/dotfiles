#!/usr/bin/env bash
set -euo pipefail

# --- UI helpers ---
msg()  { echo -e "\e[32m[INFO]\e[0m  $*"; }
warn() { echo -e "\e[33m[WARN]\e[0m  $*"; }
err()  { echo -e "\e[31m[ERROR]\e[0m $*" >&2; exit 1; }

# --- Pre-flight: ensure Arch ---
command -v pacman >/dev/null 2>&1 || err "This script supports only Arch-based systems (pacman not found)."

# --- Vars ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_REPO="https://github.com/DriftFe/dotfiles"
TMP_DIR="$(mktemp -d -t dotfiles-setup-XXXXXX)"
CURSOR_DIR="$HOME/.icons"
HYPR_CONF="$HOME/.config/hypr/hyprland.conf"
HYPRPAPER_CONF="$HOME/.config/hypr/hyprpaper.conf"
WOFI_STYLE="$HOME/.config/wofi/style.css"
# Default wallpaper directory preference order
WALL_DIRS=(
  "$HOME/.config/wallpapers"
  "$HOME/wallpapers"
  "$HOME/.wallpapers"
  "$HOME/Pictures/Wallpapers"
  "$HOME/Pictures"
)
HYPRCURSOR_NAME="Bibata-Modern-Classic"
HYPRCURSOR_SIZE="24"

# --- Ensure base tooling ---
msg "Updating system and installing base tools..."
sudo pacman -Syu --noconfirm || warn "System update had issues."
sudo pacman -S --needed --noconfirm git wget curl unzip rsync base-devel || err "Failed to install base tools."

# --- AUR helper detection/installation (yay preferred) ---
AUR_HELPER=""
if command -v yay &>/dev/null; then
  AUR_HELPER="yay"
  msg "Found yay AUR helper"
elif command -v paru &>/dev/null; then
  AUR_HELPER="paru"
  msg "Found paru AUR helper"
else
  msg "No AUR helper found. Installing yay..."
  WORKDIR="$(mktemp -d)"
  pushd "$WORKDIR" >/dev/null
  git clone https://aur.archlinux.org/yay.git || err "Failed to clone yay repository"
  pushd yay >/dev/null
  makepkg -si --noconfirm || err "Failed to build/install yay"
  popd >/dev/null
  popd >/dev/null
  rm -rf "$WORKDIR"
  AUR_HELPER="yay"
  msg "Successfully installed yay"
fi

# --- Package sets ---
# Split into smaller batches for better error tracking
CORE_PKGS=(
  gdm
  hyprland
  hyprpaper
  kitty
  waybar
  wofi
  mako
)

HYPR_UTILS=(
  hyprland-qtutils
  hyprlock
  cliphist
  wl-clipboard
  brightnessctl
  jq
  playerctl
  libnotify
)

AUDIO_VIDEO=(
  pipewire
  wireplumber
  xorg-xwayland
  pavucontrol
)

PORTAL_PKGS=(
  xdg-desktop-portal-hyprland
  xdg-desktop-portal-gtk
)

NETWORK_PKGS=(
  networkmanager
  network-manager-applet
)

BLUETOOTH_PKGS=(
  bluez
  bluez-utils
  blueman
)

GNOME_UTILS=(
  nautilus
  polkit-gnome
  gnome-keyring
)

SCREENSHOT_PKGS=(
  grim
  slurp
  swappy
)

FUN_PKGS=(
  cbonsai
  cava
  kdenlive
)

FONT_PKGS=(
  noto-fonts
  noto-fonts-emoji
  ttf-font-awesome
)

QT_PKGS=(
  qt5ct
  qt6ct
  qt5-wayland
  qt6-wayland
)

MISC_PKGS=(
  bibata-cursor-theme
  touchegg
  xdg-user-dirs
  zsh
  starship
)

AUR_PKGS=(
  waypaper
  grimblast-git
  vesktop
  zen-browser-bin
  wofi-emoji
  gpu-screen-recorder
  spotify
)

AUR_FONTS=(
  ttf-nerd-fonts-symbols
  ttf-nerd-fonts-symbols-mono
  ttf-jetbrains-mono-nerd
)

# --- Install function with retry ---
install_packages() {
  local pkg_manager="$1"
  shift
  local packages=("$@")
  
  msg "Installing with $pkg_manager: ${packages[*]}"
  
  if [[ "$pkg_manager" == "pacman" ]]; then
    sudo pacman -S --needed --noconfirm "${packages[@]}" || return 1
  else
    "$pkg_manager" -S --needed --noconfirm "${packages[@]}" || return 1
  fi
  return 0
}

# --- Install core packages (critical - fail if any issue) ---
msg "Installing CORE packages (GDM, Hyprland, Waybar, Kitty, etc.)..."
install_packages pacman "${CORE_PKGS[@]}" || err "CRITICAL: Failed to install core packages!"

# Verify core packages
for pkg in "${CORE_PKGS[@]}"; do
  if ! pacman -Qi "$pkg" &>/dev/null; then
    err "CRITICAL: Package '$pkg' failed to install!"
  fi
done
msg "✓ Core packages verified successfully"

# --- Install additional package groups (best effort) ---
msg "Installing Hyprland utilities..."
install_packages pacman "${HYPR_UTILS[@]}" || warn "Some Hyprland utilities failed to install"

msg "Installing audio/video packages..."
install_packages pacman "${AUDIO_VIDEO[@]}" || warn "Some audio/video packages failed to install"

msg "Installing portal packages..."
install_packages pacman "${PORTAL_PKGS[@]}" || warn "Some portal packages failed to install"

msg "Installing network packages..."
install_packages pacman "${NETWORK_PKGS[@]}" || warn "Some network packages failed to install"

msg "Installing bluetooth packages..."
install_packages pacman "${BLUETOOTH_PKGS[@]}" || warn "Some bluetooth packages failed to install"

msg "Installing GNOME utilities..."
install_packages pacman "${GNOME_UTILS[@]}" || warn "Some GNOME utilities failed to install"

msg "Installing screenshot tools..."
install_packages pacman "${SCREENSHOT_PKGS[@]}" || warn "Some screenshot tools failed to install"

msg "Installing fun packages (cava, cbonsai, kdenlive)..."
install_packages pacman "${FUN_PKGS[@]}" || warn "Some fun packages failed to install"

msg "Installing fonts..."
install_packages pacman "${FONT_PKGS[@]}" || warn "Some fonts failed to install"

msg "Installing Qt packages..."
install_packages pacman "${QT_PKGS[@]}" || warn "Some Qt packages failed to install"

msg "Installing miscellaneous packages..."
install_packages pacman "${MISC_PKGS[@]}" || warn "Some miscellaneous packages failed to install"

# --- JetBrains Mono font (best effort) ---
msg "Installing JetBrains Mono font..."
if ! sudo pacman -S --needed --noconfirm ttf-jetbrains-mono; then
  msg "Trying JetBrains Mono from AUR..."
  "$AUR_HELPER" -S --needed --noconfirm ttf-jetbrains-mono-nerd || warn "Failed to install JetBrains Mono font"
fi

# --- AUR packages (best effort) ---
msg "Installing AUR packages..."
for pkg in "${AUR_PKGS[@]}"; do
  msg "Installing $pkg from AUR..."
  "$AUR_HELPER" -S --needed --noconfirm "$pkg" || warn "Failed to install $pkg from AUR"
done

msg "Installing AUR fonts..."
for pkg in "${AUR_FONTS[@]}"; do
  msg "Installing $pkg from AUR..."
  "$AUR_HELPER" -S --needed --noconfirm "$pkg" || warn "Failed to install $pkg from AUR"
done

# VS Code and Waydroid (best effort)
msg "Installing VS Code..."
if ! sudo pacman -S --needed --noconfirm code; then
  msg "Trying VS Code from AUR..."
  "$AUR_HELPER" -S --needed --noconfirm visual-studio-code-bin || warn "Failed to install VS Code"
fi

msg "Installing Waydroid..."
if ! sudo pacman -S --needed --noconfirm waydroid; then
  msg "Trying Waydroid from AUR..."
  "$AUR_HELPER" -S --needed --noconfirm waydroid || warn "Failed to install Waydroid"
fi

# --- Enable essential services ---
msg "Enabling and starting essential system services..."
sudo systemctl enable NetworkManager.service || warn "Failed to enable NetworkManager"
sudo systemctl start NetworkManager.service || warn "Failed to start NetworkManager"
sudo systemctl enable bluetooth.service || warn "Failed to enable bluetooth"
sudo systemctl start bluetooth.service || warn "Failed to start bluetooth"

# Enable user services that should run in the user session
msg "Enabling user services..."
systemctl --user enable pipewire.service || warn "Failed to enable pipewire"
systemctl --user enable pipewire-pulse.service || warn "Failed to enable pipewire-pulse"
systemctl --user enable wireplumber.service || warn "Failed to enable wireplumber"

# --- GDM configuration and Hyprland as default ---
msg "Configuring GDM and setting Hyprland as default session..."

# Ensure GDM is installed
if ! pacman -Qi gdm &>/dev/null; then
  err "GDM is not installed! Cannot proceed with display manager setup."
fi

# Find Hyprland session file
SESSION_FILE=""
POSSIBLE_SESSIONS=(
  "/usr/share/wayland-sessions/hyprland.desktop"
  "/usr/share/xsessions/hyprland.desktop"
)

for session in "${POSSIBLE_SESSIONS[@]}"; do
  if [[ -f "$session" ]]; then
    SESSION_FILE="$session"
    break
  fi
done

if [[ -z "$SESSION_FILE" ]]; then
  # Search for any hyprland session
  SESSION_FILE="$(find /usr/share/{wayland-sessions,xsessions} -type f -iname '*hyprland*.desktop' 2>/dev/null | head -n1 || true)"
fi

if [[ -z "$SESSION_FILE" ]]; then
  warn "No Hyprland session file found! GDM may not show Hyprland option."
else
  SESSION_NAME="$(basename "$SESSION_FILE" .desktop)"
  msg "Found Hyprland session: $SESSION_NAME at $SESSION_FILE"
  
  # Configure GDM custom.conf
  GDM_CONF="/etc/gdm/custom.conf"
  sudo mkdir -p /etc/gdm
  
  if [[ ! -f "$GDM_CONF" ]]; then
    msg "Creating $GDM_CONF..."
    echo "[daemon]" | sudo tee "$GDM_CONF" >/dev/null
  fi
  
  # Ensure [daemon] section exists
  if ! grep -q '^\[daemon\]' "$GDM_CONF"; then
    echo -e "\n[daemon]" | sudo tee -a "$GDM_CONF" >/dev/null
  fi
  
  # Set WaylandEnable=true
  if grep -q '^[[:space:]]*#\?[[:space:]]*WaylandEnable=' "$GDM_CONF"; then
    sudo sed -i 's/^[[:space:]]*#\?[[:space:]]*WaylandEnable=.*/WaylandEnable=true/' "$GDM_CONF"
  else
    sudo sed -i '/^\[daemon\]/a WaylandEnable=true' "$GDM_CONF"
  fi
  
  # Set DefaultSession
  if grep -q '^[[:space:]]*#\?[[:space:]]*DefaultSession=' "$GDM_CONF"; then
    sudo sed -i "s/^[[:space:]]*#\?[[:space:]]*DefaultSession=.*/DefaultSession=${SESSION_NAME}/" "$GDM_CONF"
  else
    sudo sed -i "/^\[daemon\]/a DefaultSession=${SESSION_NAME}" "$GDM_CONF"
  fi
  
  msg "GDM configured with DefaultSession=${SESSION_NAME}"
  
  # Configure AccountsService for user
  ACCOUNTS_DIR="/var/lib/AccountsService/users"
  sudo mkdir -p "$ACCOUNTS_DIR"
  USER_ACCOUNT="$ACCOUNTS_DIR/$USER"
  
  if [[ ! -f "$USER_ACCOUNT" ]]; then
    echo -e "[User]\nSession=${SESSION_NAME}\nXSession=${SESSION_NAME}\nSystemAccount=false" | sudo tee "$USER_ACCOUNT" >/dev/null
  else
    # Update existing file
    if ! grep -q '^\[User\]' "$USER_ACCOUNT"; then
      echo -e "\n[User]" | sudo tee -a "$USER_ACCOUNT" >/dev/null
    fi
    if grep -q '^Session=' "$USER_ACCOUNT"; then
      sudo sed -i "s/^Session=.*/Session=${SESSION_NAME}/" "$USER_ACCOUNT"
    else
      sudo sed -i "/^\[User\]/a Session=${SESSION_NAME}" "$USER_ACCOUNT"
    fi
    if grep -q '^XSession=' "$USER_ACCOUNT"; then
      sudo sed -i "s/^XSession=.*/XSession=${SESSION_NAME}/" "$USER_ACCOUNT"
    else
      sudo sed -i "/^\[User\]/a XSession=${SESSION_NAME}" "$USER_ACCOUNT"
    fi
  fi
  
  msg "AccountsService configured for user $USER"
fi

# Enable and start GDM
msg "Enabling and starting GDM service..."
sudo systemctl enable gdm.service || warn "Failed to enable GDM"
sudo systemctl start gdm.service 2>/dev/null || msg "GDM will start on next boot (not starting now to avoid session conflicts)"

# Check for conflicting display managers
OTHER_DMS=(lightdm sddm lxdm)
for dm in "${OTHER_DMS[@]}"; do
  if systemctl is-enabled "${dm}.service" &>/dev/null; then
    warn "Disabling conflicting display manager: ${dm}"
    sudo systemctl disable "${dm}.service" || true
    sudo systemctl stop "${dm}.service" 2>/dev/null || true
  fi
done

# --- Prepare user directories ---
msg "Creating user directories..."
xdg-user-dirs-update 2>/dev/null || true
mkdir -p "$HOME/Pictures/Screenshots" "$HOME/Videos" "$HOME/Downloads" || true

# --- Fetch and sync dotfiles ---
msg "Fetching dotfiles from $DOTFILES_REPO..."
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

if git clone --depth=1 "$DOTFILES_REPO" "$TMP_DIR"; then
  msg "Successfully cloned dotfiles repository"
  
  # Sync dot_* directories
  msg "Syncing dot_* directories..."
  shopt -s nullglob
  for src_dir in "$TMP_DIR"/dot_*; do
    if [[ -d "$src_dir" ]]; then
      base="$(basename "$src_dir")"
      target="$HOME/.${base#dot_}"
      msg "Syncing $base -> $target"
      mkdir -p "$target"
      rsync -av --exclude='.git' "$src_dir/" "$target/" || err "Failed to sync $base"
    fi
  done
  shopt -u nullglob
  
  # Sync .config if present
  if [[ -d "$TMP_DIR/.config" ]]; then
    msg "Syncing .config directory..."
    mkdir -p "$HOME/.config"
    rsync -av --exclude='.git' "$TMP_DIR/.config/" "$HOME/.config/" || err "Failed to sync .config"
  fi
  
  # Sync wallpapers - try multiple possible locations
  WALLPAPER_SYNCED=false
  for wall_src in "$TMP_DIR/wallpapers" "$TMP_DIR/.wallpapers" "$TMP_DIR/dot_wallpapers" "$TMP_DIR/.config/wallpapers"; do
    if [[ -d "$wall_src" ]]; then
      msg "Found wallpapers in $wall_src, syncing to ~/.config/wallpapers..."
      mkdir -p "$HOME/.config/wallpapers"
      rsync -av "$wall_src/" "$HOME/.config/wallpapers/" || err "Failed to sync wallpapers"
      WALLPAPER_SYNCED=true
      break
    fi
  done
  
  if [[ "$WALLPAPER_SYNCED" == "false" ]]; then
    err "No wallpapers directory found in repository - required for setup"
  else
    msg "✓ Wallpapers synced successfully"
  fi
else
  err "Failed to clone dotfiles repository - cannot continue"
fi

# --- Copy local configs and wallpapers from script directory ---
msg "Copying local files from script directory..."

# Copy .zshrc if present
if [[ -f "$SCRIPT_DIR/.zshrc" ]]; then
  msg "Copying .zshrc from script directory..."
  cp -f "$SCRIPT_DIR/.zshrc" "$HOME/.zshrc"
fi

# Copy starship.toml if present
if [[ -f "$SCRIPT_DIR/starship.toml" ]]; then
  msg "Copying starship.toml from script directory..."
  mkdir -p "$HOME/.config"
  cp -f "$SCRIPT_DIR/starship.toml" "$HOME/.config/starship.toml"
fi

# Copy wallpapers from script directory (dot_config/wallpapers -> ~/.wallpapers)
if [[ -d "$SCRIPT_DIR/dot_config/wallpapers" ]]; then
  msg "Copying wallpapers from $SCRIPT_DIR/dot_config/wallpapers to ~/.wallpapers..."
  mkdir -p "$HOME/.wallpapers"
  rsync -av "$SCRIPT_DIR/dot_config/wallpapers/" "$HOME/.wallpapers/" || warn "Failed to copy wallpapers from script directory"
  msg "✓ Wallpapers copied to ~/.wallpapers"
else
  warn "No wallpapers found in $SCRIPT_DIR/dot_config/wallpapers"
fi

# Copy any other dot_config contents to ~/.config
if [[ -d "$SCRIPT_DIR/dot_config" ]]; then
  msg "Copying dot_config contents to ~/.config..."
  mkdir -p "$HOME/.config"
  rsync -av --exclude='wallpapers' "$SCRIPT_DIR/dot_config/" "$HOME/.config/" || warn "Failed to copy dot_config"
fi

# --- Make scripts executable ---
if [[ -d "$HOME/.config/waybar/scripts" ]]; then
  msg "Making Waybar scripts executable..."
  find "$HOME/.config/waybar/scripts" -type f \( -name "*.sh" -o -name "*.py" \) -exec chmod +x {} +
fi

if [[ -d "$HOME/.config/hypr/scripts" ]]; then
  msg "Making Hypr scripts executable..."
  find "$HOME/.config/hypr/scripts" -type f \( -name "*.sh" -o -name "*.py" \) -exec chmod +x {} +
fi

# --- Configure hyprpaper with actual wallpaper ---
msg "Configuring hyprpaper..."
mkdir -p "$(dirname "$HYPRPAPER_CONF")"

# Find first wallpaper
WP_PATH=""
for wall_dir in "${WALL_DIRS[@]}"; do
  if [[ -d "$wall_dir" ]]; then
    WP_PATH="$(find "$wall_dir" -maxdepth 1 -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \) -print -quit 2>/dev/null || true)"
    if [[ -n "$WP_PATH" ]]; then
      msg "Found wallpaper: $WP_PATH"
      break
    fi
  fi
done

if [[ -z "$WP_PATH" ]]; then
  warn "No wallpapers found! Creating placeholder config."
  WP_PATH="$HOME/.config/wallpapers/default.png"
fi

# Write hyprpaper config
cat > "$HYPRPAPER_CONF" <<EOF
splash = false
ipc = on

preload = ${WP_PATH}
wallpaper = ,${WP_PATH}
EOF

msg "✓ hyprpaper configured with wallpaper: $WP_PATH"

# --- Configure wofi fonts ---
if [[ -f "$WOFI_STYLE" ]]; then
  msg "Configuring wofi to use JetBrains Mono Nerd Font..."
  sed -i 's/font-family:.*$/font-family: "JetBrainsMono Nerd Font", "JetBrains Mono", monospace;/' "$WOFI_STYLE" || true
fi

# --- Cursor theme setup ---
msg "Setting up Bibata cursor theme..."
mkdir -p "$CURSOR_DIR"

# Install from AUR if needed
if [[ ! -d "$CURSOR_DIR/$HYPRCURSOR_NAME" ]] && [[ ! -d "/usr/share/icons/$HYPRCURSOR_NAME" ]]; then
  "$AUR_HELPER" -S --needed --noconfirm bibata-cursor-theme-bin || warn "Failed to install Bibata cursor theme"
fi

# GTK cursor settings
for gtk_ver in gtk-3.0 gtk-4.0; do
  gtk_dir="$HOME/.config/$gtk_ver"
  mkdir -p "$gtk_dir"
  settings_ini="$gtk_dir/settings.ini"
  
  if [[ ! -f "$settings_ini" ]]; then
    echo "[Settings]" > "$settings_ini"
  fi
  
  if grep -q '^gtk-cursor-theme-name=' "$settings_ini"; then
    sed -i "s/^gtk-cursor-theme-name=.*/gtk-cursor-theme-name=$HYPRCURSOR_NAME/" "$settings_ini"
  else
    echo "gtk-cursor-theme-name=$HYPRCURSOR_NAME" >> "$settings_ini"
  fi
  
  if grep -q '^gtk-cursor-theme-size=' "$settings_ini"; then
    sed -i "s/^gtk-cursor-theme-size=.*/gtk-cursor-theme-size=$HYPRCURSOR_SIZE/" "$settings_ini"
  else
    echo "gtk-cursor-theme-size=$HYPRCURSOR_SIZE" >> "$settings_ini"
  fi
done

# Hyprland cursor environment variables
mkdir -p "$(dirname "$HYPR_CONF")"
if [[ ! -f "$HYPR_CONF" ]]; then
  touch "$HYPR_CONF"
fi

append_env_if_missing() {
  local env_var="$1"
  local env_line="$2"
  if ! grep -q "^env = $env_var," "$HYPR_CONF"; then
    echo "$env_line" >> "$HYPR_CONF"
  fi
}

append_env_if_missing "HYPRCURSOR_THEME" "env = HYPRCURSOR_THEME,$HYPRCURSOR_NAME"
append_env_if_missing "HYPRCURSOR_SIZE" "env = HYPRCURSOR_SIZE,$HYPRCURSOR_SIZE"
append_env_if_missing "XCURSOR_THEME" "env = XCURSOR_THEME,$HYPRCURSOR_NAME"
append_env_if_missing "XCURSOR_SIZE" "env = XCURSOR_SIZE,$HYPRCURSOR_SIZE"

# gsettings for GNOME apps
if command -v gsettings &>/dev/null; then
  gsettings set org.gnome.desktop.interface cursor-theme "$HYPRCURSOR_NAME" 2>/dev/null || true
  gsettings set org.gnome.desktop.interface cursor-size "$HYPRCURSOR_SIZE" 2>/dev/null || true
fi

msg "✓ Cursor theme configured"

# --- Polkit agent setup ---
msg "Setting up polkit authentication agent..."
POLKIT_AUTOSTART="$HOME/.config/autostart/polkit-gnome-authentication-agent-1.desktop"
mkdir -p "$HOME/.config/autostart"
cat > "$POLKIT_AUTOSTART" <<'EOF'
[Desktop Entry]
Type=Application
Name=Polkit GNOME Authentication Agent
Comment=GNOME Polkit authentication agent
Exec=/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1
Terminal=false
Categories=System;
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF
chmod +x "$POLKIT_AUTOSTART"
msg "✓ Polkit agent will autostart"

# --- Create Hyprland autostart for essential services ---
msg "Creating Hyprland autostart configuration..."
HYPR_AUTOSTART="$HOME/.config/hypr/autostart.conf"

# Backup existing autostart if present
if [[ -f "$HYPR_AUTOSTART" ]]; then
  cp "$HYPR_AUTOSTART" "$HYPR_AUTOSTART.backup.$(date +%s)"
fi

# Create autostart config with all essential services
cat > "$HYPR_AUTOSTART" <<'EOF'
# Hyprland Autostart Configuration
# Essential services and applications that start with Hyprland

# Wallpaper daemon
exec-once = hyprpaper

# Notification daemon
exec-once = mako

# Status bar
exec-once = waybar

# Polkit authentication agent
exec-once = /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1

# Clipboard manager
exec-once = wl-paste --type text --watch cliphist store
exec-once = wl-paste --type image --watch cliphist store

# Network manager applet
exec-once = nm-applet --indicator

# Bluetooth manager
exec-once = blueman-applet

# Idle management and screen locking (if hyprlock is installed)
exec-once = hypridle

# XDG portals
exec-once = dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP

# GNOME keyring
exec-once = gnome-keyring-daemon --start --components=secrets

# Touchegg (touchpad gestures)
exec-once = touchegg

# Audio server (if not started by systemd)
exec-once = pipewire
exec-once = wireplumber
EOF

# Source autostart in main Hyprland config if not already present
if ! grep -q "source.*autostart.conf" "$HYPR_CONF" 2>/dev/null; then
  echo -e "\n# Autostart services\nsource = ~/.config/hypr/autostart.conf" >> "$HYPR_CONF"
  msg "✓ Autostart configuration linked to hyprland.conf"
fi

msg "✓ Hyprland autostart configured (hyprpaper, mako, waybar, etc.)"

# --- Zsh setup ---
msg "Setting up Zsh, Oh My Zsh, and plugins..."

# Install Oh My Zsh
if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
  msg "Installing Oh My Zsh..."
  RUNZSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" || \
    git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git "$HOME/.oh-my-zsh" || \
    warn "Failed to install Oh My Zsh"
fi

# Install Powerlevel10k
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
mkdir -p "$ZSH_CUSTOM/themes"
if [[ ! -d "$ZSH_CUSTOM/themes/powerlevel10k" ]]; then
  msg "Installing Powerlevel10k theme..."
  git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$ZSH_CUSTOM/themes/powerlevel10k" || \
    warn "Failed to install Powerlevel10k"
fi

# Install zsh-autosuggestions
mkdir -p "$HOME/.zsh"
if [[ ! -d "$HOME/.zsh/zsh-autosuggestions" ]]; then
  msg "Installing zsh-autosuggestions..."
  git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions "$HOME/.zsh/zsh-autosuggestions" || \
    warn "Failed to install zsh-autosuggestions"
fi

# Set zsh as default shell
if command -v zsh &>/dev/null; then
  ZSH_PATH="$(command -v zsh)"
  CURRENT_SHELL="$(getent passwd "$USER" | cut -d: -f7)"
  if [[ "$CURRENT_SHELL" != "$ZSH_PATH" ]]; then
    msg "Setting zsh as default shell..."
    chsh -s "$ZSH_PATH" "$USER" || warn "Failed to set zsh as default shell. Run manually: chsh -s $ZSH_PATH"
  fi
fi

# --- Cleanup ---
msg "Cleaning up temporary files..."
rm -rf "$TMP_DIR" || true

# --- Final summary ---
echo ""
echo "=============================================="
msg "✓ Installation complete!"
echo "=============================================="
echo ""
msg "Installed and verified:"
echo "  • Core: GDM, Hyprland, Waybar, Kitty, Wofi, Hyprpaper, Mako"
echo "  • Tools: Cava, Screenshot tools, Audio/Video stack"
echo "  • Services enabled: GDM, NetworkManager, Bluetooth, Pipewire"
echo "  • Hyprland autostart: hyprpaper, waybar, mako, polkit, clipboard"
echo "  • Configured: GDM with Hyprland as default session"
echo "  • Synced: Dotfiles and wallpapers"
echo "  • Theme: Bibata cursor theme"
echo "  • Shell: Zsh with Oh My Zsh and Powerlevel10k"
echo ""
msg "Services status:"
systemctl is-enabled gdm.service && echo "  ✓ GDM enabled" || echo "  ✗ GDM not enabled"
systemctl is-enabled NetworkManager.service && echo "  ✓ NetworkManager enabled" || echo "  ✗ NetworkManager not enabled"
systemctl is-enabled bluetooth.service && echo "  ✓ Bluetooth enabled" || echo "  ✗ Bluetooth not enabled"
systemctl --user is-enabled pipewire.service 2>/dev/null && echo "  ✓ Pipewire enabled" || echo "  ✗ Pipewire not enabled"
echo ""
msg "Next steps:"
echo "  1. Reboot your system: sudo reboot"
echo "  2. At GDM login, Hyprland should be auto-selected"
echo "  3. Log in - all services will start automatically!"
echo "  4. Hyprpaper, Waybar, Mako will launch on Hyprland startup"
echo ""
warn "If Hyprland doesn't appear, check: ls /usr/share/wayland-sessions/"
echo "=============================================="
