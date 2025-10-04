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
HYPRPAPER_CONF="$HOME/.config/hyprpaper/hyprpaper.conf"
WOFI_STYLE="$HOME/.config/wofi/style.css"
WALL_DIR="$HOME/.wallpapers"
HYPRCURSOR_NAME="Bibata-Modern-Classic"
HYPRCURSOR_SIZE="24"
GDM_DEFAULT_SESSION="hyprland"

# --- Ensure base tooling ---
sudo pacman -Syu --needed --noconfirm git wget curl unzip rsync base-devel || warn "Base tools installation had issues."

# --- AUR helper detection/installation (yay preferred) ---
AUR_HELPER=""
if command -v yay &>/dev/null; then
  AUR_HELPER="yay"
elif command -v paru &>/dev/null; then
  AUR_HELPER="paru"
else
  msg "No AUR helper found. Bootstrapping yay (non-root build)."
  WORKDIR="$(mktemp -d)"
  pushd "$WORKDIR" >/dev/null
  git clone https://aur.archlinux.org/yay.git
  pushd yay >/dev/null
  makepkg -si --noconfirm
  popd >/dev/null
  popd >/dev/null
  rm -rf "$WORKDIR"
  AUR_HELPER="yay"
fi

# --- Install packages ---
# Core + inferred repo packages (keep this list to reliable repo packages)
PAC_PKGS=(
  # Display manager and base Hyprland stack
  gdm hyprland hyprpaper hyprland-qtutils hyprlock
  waybar wofi mako kitty
  # Clipboard & utilities
  cliphist wl-clipboard brightnessctl jq playerctl libnotify
  # Audio/portals
  pipewire wireplumber xorg-xwayland pavucontrol
  xdg-desktop-portal-hyprland xdg-desktop-portal-gtk
  # Networking
  networkmanager network-manager-applet
  # Bluetooth
  bluez bluez-utils blueman
  # File manager and DE bits
  nautilus polkit-gnome gnome-keyring
  # Touch gestures
  touchegg
  # Multimedia / screenshots
  grim slurp swappy
  # Fun/CLI
  cava
  # Media creation
  kdenlive
  # Fonts and cursors
  noto-fonts noto-fonts-emoji ttf-font-awesome
  bibata-cursor-theme
  # Qt theming
  qt5ct qt6ct qt5-wayland qt6-wayland
  # Misc
  rsync wget curl unzip xdg-user-dirs zsh starship
)

# AUR packages inferred from configs (best-effort)
AUR_PKGS=(
  waypaper
  cbonsai
  grimblast-git
  vesktop
  zen-browser-bin
  wofi-emoji
  gpu-screen-recorder
  spotify
  # Symbols
  ttf-nerd-fonts-symbols ttf-nerd-fonts-symbols-mono
)

# Prefer repo for JetBrains fonts, then fall back to AUR
REPO_OR_AUR=(ttf-jetbrains-mono-nerd ttf-jetbrains-mono)

msg "Installing core pacman packages..."
sudo pacman -S --needed --noconfirm "${PAC_PKGS[@]}" || warn "Some pacman packages failed."

# Try repo first for fonts, fall back to AUR
for pkg in "${REPO_OR_AUR[@]}"; do
  if ! sudo pacman -S --needed --noconfirm "$pkg"; then
    msg "Falling back to AUR for $pkg ..."
    "$AUR_HELPER" -S --needed --noconfirm "$pkg" || warn "Failed to install $pkg via AUR."
  fi
done

# Install AUR packages (best-effort; continue on errors)
msg "Installing AUR packages..."
"$AUR_HELPER" -S --needed --noconfirm "${AUR_PKGS[@]}" || warn "Some AUR packages failed."

# Try alternate AUR names for zen-browser if needed
if ! command -v zen-browser &>/dev/null; then
  "$AUR_HELPER" -S --needed --noconfirm zen-browser-bin || true
fi

# Optional apps referenced in keybinds — install robustly
# VS Code (code): repo first, then AUR visual-studio-code-bin
if ! command -v code &>/dev/null; then
  sudo pacman -S --needed --noconfirm code || "$AUR_HELPER" -S --needed --noconfirm visual-studio-code-bin || warn "Failed to install VS Code"
fi
# Waydroid: repo first (if present), then AUR
if ! command -v waydroid &>/dev/null; then
  sudo pacman -S --needed --noconfirm waydroid || "$AUR_HELPER" -S --needed --noconfirm waydroid || warn "Failed to install waydroid"
fi
# Powder (best-effort AUR; may not exist for all arches)
if ! command -v powder &>/dev/null; then
  "$AUR_HELPER" -S --needed --noconfirm powder || warn "Package 'powder' not available; skip"
fi

# --- Enable essential services ---
msg "Enabling essential system services ..."
sudo systemctl enable NetworkManager.service || warn "Failed to enable NetworkManager.service"
sudo systemctl enable bluetooth.service || warn "Failed to enable bluetooth.service"

# --- GDM: install and set Hyprland as default session ---
msg "Configuring GDM and setting default session to $GDM_DEFAULT_SESSION ..."
if sudo pacman -Qi gdm >/dev/null 2>&1; then
  if [[ -f "/usr/share/wayland-sessions/${GDM_DEFAULT_SESSION}.desktop" ]]; then
    # Ensure /etc/gdm/custom.conf exists and has [daemon]
    if [[ ! -f /etc/gdm/custom.conf ]]; then
      sudo install -D -m 644 /dev/null /etc/gdm/custom.conf
      echo "[daemon]" | sudo tee -a /etc/gdm/custom.conf >/dev/null
    fi
    if ! grep -q '^\s*\[daemon\]' /etc/gdm/custom.conf; then
      echo -e "\n[daemon]" | sudo tee -a /etc/gdm/custom.conf >/dev/null
    fi
    # WaylandEnable=true
    if grep -q '^\s*#\?\s*WaylandEnable=' /etc/gdm/custom.conf; then
      sudo sed -i -E 's/^\s*#?\s*WaylandEnable\s*=.*/WaylandEnable=true/' /etc/gdm/custom.conf
    else
      sudo sed -i '/^\s*\[daemon\]/a WaylandEnable=true' /etc/gdm/custom.conf
    fi
    # DefaultSession=hyprland
    if grep -q '^\s*#\?\s*DefaultSession=' /etc/gdm/custom.conf; then
      sudo sed -i -E "s/^\s*#?\s*DefaultSession\s*=.*/DefaultSession=${GDM_DEFAULT_SESSION}/" /etc/gdm/custom.conf
    else
      sudo sed -i "/^\s*\[daemon\]/a DefaultSession=${GDM_DEFAULT_SESSION}" /etc/gdm/custom.conf
    fi
    # AccountsService: prefer Hyprland for this user
    sudo mkdir -p /var/lib/AccountsService/users
    if [[ ! -f "/var/lib/AccountsService/users/$USER" ]]; then
      echo -e "[User]\nXSession=${GDM_DEFAULT_SESSION}" | sudo tee "/var/lib/AccountsService/users/$USER" >/dev/null
    else
      if grep -q '^XSession=' "/var/lib/AccountsService/users/$USER"; then
        sudo sed -i -E "s/^XSession=.*/XSession=${GDM_DEFAULT_SESSION}/" "/var/lib/AccountsService/users/$USER"
      else
        echo "XSession=${GDM_DEFAULT_SESSION}" | sudo tee -a "/var/lib/AccountsService/users/$USER" >/dev/null
      fi
    fi
    # Enable GDM
    sudo systemctl enable gdm.service || warn "Failed to enable gdm.service"
    # Warn if other DMs are enabled
    OTHER_DM="$(systemctl list-unit-files | awk '/^(lightdm|sddm|lxdm)\.service/ && $2=="enabled"{print $1}' || true)"
    if [[ -n "${OTHER_DM:-}" ]]; then
      warn "Other display manager(s) enabled: ${OTHER_DM}. They may conflict with GDM."
    fi
  else
    warn "Hyprland wayland session file not found at /usr/share/wayland-sessions/${GDM_DEFAULT_SESSION}.desktop"
  fi
else
  warn "GDM not installed; skipping GDM configuration."
fi

# --- Prepare user dirs ---
xdg-user-dirs-update 2>/dev/null || true
mkdir -p "$HOME/Pictures/Screenshots" "$HOME/Videos" || true

# --- Fetch dotfiles ---
msg "Fetching dotfiles from $DOTFILES_REPO ..."
rm -rf "$TMP_DIR" && mkdir -p "$TMP_DIR"
if ! git clone --depth=1 "$DOTFILES_REPO" "$TMP_DIR"; then
  warn "Failed to clone $DOTFILES_REPO, continuing without remote dotfiles."
fi

# --- Sync dot_* and optional .config from repo (best-effort) ---
if [[ -d "$TMP_DIR" && -n "$(ls -A "$TMP_DIR" 2>/dev/null || true)" ]]; then
  msg "Syncing dot_* content and wallpapers from repo..."
  mkdir -p "$HOME/.config" "$WALL_DIR"
  shopt -s nullglob
  for SRC in "$TMP_DIR"/dot_*; do
    base="$(basename "$SRC")"
    target="$HOME/.${base#dot_}"
    mkdir -p "$target"
    rsync -a --info=NAME,STATS --exclude='.git' "$SRC/." "$target/"
  done
  shopt -u nullglob

  if [[ -d "$TMP_DIR/.config" ]]; then
    rsync -a --info=NAME,STATS --exclude='.git' "$TMP_DIR/.config/." "$HOME/.config/"
  fi

  if [[ -d "$TMP_DIR/wallpapers" ]]; then
    rsync -a --info=NAME,STATS "$TMP_DIR/wallpapers/." "$WALL_DIR/"
  elif [[ -d "$TMP_DIR/.wallpapers" ]]; then
    rsync -a --info=NAME,STATS "$TMP_DIR/.wallpapers/." "$WALL_DIR/"
  fi
fi

# --- Also copy local zsh and starship configs from script directory if present ---
if [[ -f "$SCRIPT_DIR/.zshrc" ]]; then
  msg "Copying .zshrc from $SCRIPT_DIR to $HOME ..."
  cp -f "$SCRIPT_DIR/.zshrc" "$HOME/.zshrc"
fi
if [[ -f "$SCRIPT_DIR/starship.toml" ]]; then
  msg "Copying starship.toml from $SCRIPT_DIR to ~/.config ..."
  mkdir -p "$HOME/.config"
  cp -f "$SCRIPT_DIR/starship.toml" "$HOME/.config/starship.toml"
fi

# --- Ensure scripts executable ---
if [[ -d "$HOME/.config/waybar/scripts" ]]; then
  find "$HOME/.config/waybar/scripts" -type f -name "*.sh" -exec chmod +x {} +
fi

# --- hyprpaper configuration (use ~/. path as requested) ---
mkdir -p "$(dirname "$HYPRPAPER_CONF")"
DEFAULT_WP="$WALL_DIR/wallpaper.png"
# Pick a first image if default not present
if [[ ! -f "$DEFAULT_WP" ]]; then
  CANDIDATE="$(find "$WALL_DIR" -maxdepth 1 -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \) | head -n1 || true)"
  if [[ -n "${CANDIDATE:-}" ]]; then
    DEFAULT_WP="$CANDIDATE"
  fi
fi
# Always write with tilde path expansion literal
TILDE_WP="~/.wallpapers/$(basename "$DEFAULT_WP" 2>/dev/null || echo wallpaper.png)"
cat > "$HYPRPAPER_CONF" <<EOF
splash = false
preload = $TILDE_WP
wallpaper = ,$TILDE_WP
EOF

# --- wofi: force JetBrains Mono Nerd as primary font ---
if [[ -f "$WOFI_STYLE" ]]; then
  # Replace any font-family line with our preferred stack
  sed -i 's/^\([[:space:]]*font-family:.*\)$/  font-family: "JetBrainsMono Nerd Font", "JetBrains Mono", monospace, "Font Awesome 6 Free";/' "$WOFI_STYLE" || true
fi

# --- Cursor theme installation and configuration ---
mkdir -p "$CURSOR_DIR"
# If the repo package failed, try AUR bibata-cursor-theme-bin
if [[ ! -d "$CURSOR_DIR/$HYPRCURSOR_NAME" && ! -d "/usr/share/icons/$HYPRCURSOR_NAME" ]]; then
  "$AUR_HELPER" -S --needed --noconfirm bibata-cursor-theme-bin || true
fi

# GTK settings (best-effort)
for gtkdir in "$HOME/.config/gtk-3.0" "$HOME/.config/gtk-4.0"; do
  mkdir -p "$gtkdir"
  ini="$gtkdir/settings.ini"
  touch "$ini"
  if grep -q '^gtk-cursor-theme-name=' "$ini"; then
    sed -i "s/^gtk-cursor-theme-name=.*/gtk-cursor-theme-name=$HYPRCURSOR_NAME/" "$ini"
  else
    echo "gtk-cursor-theme-name=$HYPRCURSOR_NAME" >> "$ini"
  fi
  if grep -q '^gtk-cursor-size=' "$ini"; then
    sed -i "s/^gtk-cursor-size=.*/gtk-cursor-size=$HYPRCURSOR_SIZE/" "$ini"
  else
    echo "gtk-cursor-size=$HYPRCURSOR_SIZE" >> "$ini"
  fi
done

# Hyprland env ensures cursor usage
mkdir -p "$(dirname "$HYPR_CONF")" && touch "$HYPR_CONF"
append_if_missing() {
  local key="$1"; shift
  local line="$1"
  grep -q "^$key" "$HYPR_CONF" || echo "$line" >> "$HYPR_CONF"
}
append_if_missing 'env[[:space:]]*= HYPRCURSOR_THEME,' "env = HYPRCURSOR_THEME,$HYPRCURSOR_NAME"
append_if_missing 'env[[:space:]]*= HYPRCURSOR_SIZE,'  "env = HYPRCURSOR_SIZE,$HYPRCURSOR_SIZE"
append_if_missing 'env[[:space:]]*= XCURSOR_THEME,'     "env = XCURSOR_THEME,$HYPRCURSOR_NAME"
append_if_missing 'env[[:space:]]*= XCURSOR_SIZE,'      "env = XCURSOR_SIZE,$HYPRCURSOR_SIZE"

# GNOME (if present) for completeness
if command -v gsettings &>/dev/null; then
  gsettings set org.gnome.desktop.interface cursor-theme "$HYPRCURSOR_NAME" 2>/dev/null || true
  gsettings set org.gnome.desktop.interface cursor-size "$HYPRCURSOR_SIZE" 2>/dev/null || true
fi

# --- Zsh, Oh-my-zsh, P10k, Autosuggestions bootstrap ---
msg "Setting up Zsh, Oh My Zsh, Powerlevel10k, and zsh-autosuggestions ..."
if ! command -v zsh &>/dev/null; then
  warn "zsh not found after install; check pacman logs."
fi
# Oh My Zsh
if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
  git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git "$HOME/.oh-my-zsh" || warn "Failed to clone Oh My Zsh"
fi
# P10k theme under OMZ custom
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
mkdir -p "$ZSH_CUSTOM/themes"
if [[ ! -d "$ZSH_CUSTOM/themes/powerlevel10k" ]]; then
  git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$ZSH_CUSTOM/themes/powerlevel10k" || warn "Failed to clone Powerlevel10k"
fi
# zsh-autosuggestions in ~/.zsh as referenced by your .zshrc
mkdir -p "$HOME/.zsh"
if [[ ! -d "$HOME/.zsh/zsh-autosuggestions" ]]; then
  git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions "$HOME/.zsh/zsh-autosuggestions" || warn "Failed to clone zsh-autosuggestions"
fi
# Make zsh default shell (best effort)
if command -v zsh &>/dev/null; then
  if [[ "$(getent passwd "$USER" | cut -d: -f7)" != "$(command -v zsh)" ]]; then
    chsh -s "$(command -v zsh)" "$USER" || warn "Unable to set zsh as default shell (you can run: chsh -s \"$(command -v zsh)\")"
  fi
fi

# --- Cleanup ---
rm -rf "$TMP_DIR" || true

msg "Done. Reboot to reach the GDM login screen and auto-start Hyprland."
msg "Services enabled (ensure started after reboot): NetworkManager, Bluetooth, GDM."
