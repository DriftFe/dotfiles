#!/usr/bin/env bash

set -euo pipefail

# --- Functions ---
msg()  { echo -e "\e[32m[INFO]\e[0m  $*"; }
warn() { echo -e "\e[33m[WARN]\e[0m  $*"; }
err()  { echo -e "\e[31m[ERROR]\e[0m $*" >&2; exit 1; }

# --- Variables ---
DOTFILES_REPO="https://github.com/DriftFe/dotfiles"
TMP_DIR="$(mktemp -d -t dotfiles-setup-XXXXXX)"
CURSOR_DIR="$HOME/.icons"
HYPR_CONF="$HOME/.config/hypr/hyprland.conf"
HYPRCURSOR_NAME="Bibata-Modern-Classic"
HYPRCURSOR_SIZE="24"

# --- Detect package manager ---
PKG_MGR=""
INSTALL_CMD=""
if command -v pacman &>/dev/null; then
  PKG_MGR="pacman"
  INSTALL_CMD="pacman -S --noconfirm"
elif command -v apt &>/dev/null; then
  PKG_MGR="apt"
  INSTALL_CMD="apt install -y"
elif command -v dnf &>/dev/null; then
  PKG_MGR="dnf"
  INSTALL_CMD="dnf install -y"
else
  err "No supported package manager found (pacman, apt, or dnf)."
fi

# Helper: install a package best-effort
install_pkg() {
  local pkg="$1"
  if [[ -z "$pkg" ]]; then return 0; fi
  msg "Installing package: $pkg"
  if ! sudo $INSTALL_CMD "$pkg"; then
    warn "Failed to install '$pkg'. Continuing."
  fi
}

# Helper: ensure a command exists by installing an appropriate package
ensure_cmd() {
  local cmd="$1"; shift
  local pkg="${1:-}"; shift || true

  if command -v "$cmd" &>/dev/null; then
    msg "'$cmd' already present."
    return 0
  fi

  # Choose default package name if not provided
  if [[ -z "$pkg" ]]; then
    pkg="$cmd"
  fi
  install_pkg "$pkg"
}

# Helper: sync/copy preserving attributes (merge, not delete)
sync_path() {
  local src="$1"
  local dst="$2"
  mkdir -p "$dst"
  if command -v rsync &>/dev/null; then
    rsync -a --info=NAME,STATS --exclude='.git' "$src" "$dst"
  else
    cp -a "$src" "$dst"
  fi
}

# --- Start ---
msg "Starting dotfiles installation..."

# --- Essentials ---
msg "Installing required base packages..."
case "$PKG_MGR" in
  pacman)
    sudo pacman -S --noconfirm git wget curl unzip rsync || warn "Some base packages failed to install."
    ;;
  apt|dnf)
    sudo $INSTALL_CMD git wget curl unzip rsync || warn "Some base packages failed to install."
    ;;
esac

# --- Clone dotfiles ---
msg "Fetching dotfiles..."
if [[ -d "$TMP_DIR" ]]; then rm -rf "$TMP_DIR"; fi
mkdir -p "$TMP_DIR"
if ! git clone --depth=1 "$DOTFILES_REPO" "$TMP_DIR"; then
  err "Failed to clone $DOTFILES_REPO"
fi
msg "Dotfiles cloned successfully to $TMP_DIR."

# --- Copy dot_* directories/files and wallpapers ---
msg "Syncing dot_* content and wallpapers..."
mkdir -p "$HOME/.config" "$HOME/.wallpapers"

# Map dot_* -> hidden paths in $HOME (e.g., dot_config -> ~/.config)
shopt -s nullglob
mapped_any=false
for SRC in "$TMP_DIR"/dot_*; do
  [[ -e "$SRC" ]] || continue
  mapped_any=true
  base="$(basename "$SRC")"
  target="$HOME/.${base#dot_}"
  if [[ -d "$SRC" ]]; then
    sync_path "$SRC/." "$target/"
  else
    mkdir -p "$(dirname "$target")"
    if command -v rsync &>/dev/null; then
      rsync -a "$SRC" "$target"
    else
      cp -a "$SRC" "$target"
    fi
  fi
done
shopt -u nullglob

# Fallback: if repo provides .config, merge it
if [[ -d "$TMP_DIR/.config" ]]; then
  sync_path "$TMP_DIR/.config/." "$HOME/.config/"
fi

# Wallpapers: copy from either wallpapers or .wallpapers to ~/.wallpapers
if [[ -d "$TMP_DIR/wallpapers" ]]; then
  sync_path "$TMP_DIR/wallpapers/." "$HOME/.wallpapers/"
elif [[ -d "$TMP_DIR/.wallpapers" ]]; then
  sync_path "$TMP_DIR/.wallpapers/." "$HOME/.wallpapers/"
fi

# Update hyprpaper config paths to current $HOME if a wallpaper exists
HP_CONF="$HOME/.config/hypr/hyprpaper.conf"
if [[ -f "$HP_CONF" && -d "$HOME/.wallpapers" ]]; then
  wp_file="$(find "$HOME/.wallpapers" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.png' \) | head -n1)"
  if [[ -n "$wp_file" ]]; then
    sed -i "s|^preload = .*|preload = $wp_file|; s|^wallpaper = ,.*|wallpaper = ,$wp_file|" "$HP_CONF" || true
  fi
fi
msg "Files synced."

# --- Install tools referenced by your config ---
msg "Ensuring tools referenced by Hyprland config are installed..."
case "$PKG_MGR" in
  pacman)
    # Package names for Arch-based
    ensure_cmd hyprctl hyprland
    ensure_cmd kitty kitty
    ensure_cmd wl-copy wl-clipboard
    ensure_cmd wl-paste wl-clipboard
    ensure_cmd waybar waybar
    ensure_cmd hyprpaper hyprpaper
    ensure_cmd wofi wofi
    ensure_cmd mako mako
    ensure_cmd waypaper waypaper
    ensure_cmd touchegg touchegg
    ensure_cmd nm-applet network-manager-applet
    ensure_cmd cliphist cliphist
    ;;
  apt)
    # Debian/Ubuntu family (best-effort; some may be unavailable on certain releases)
    ensure_cmd hyprctl hyprland || true
    ensure_cmd kitty kitty
    ensure_cmd wl-copy wl-clipboard
    ensure_cmd wl-paste wl-clipboard
    ensure_cmd waybar waybar
    ensure_cmd hyprpaper hyprpaper || true
    ensure_cmd wofi wofi
    ensure_cmd mako mako
    ensure_cmd waypaper waypaper || true
    ensure_cmd touchegg touchegg
    ensure_cmd nm-applet network-manager-gnome
    ensure_cmd cliphist cliphist || true
    ;;
  dnf)
    # Fedora family (best-effort; hyprland may require COPR)
    ensure_cmd hyprctl hyprland || true
    ensure_cmd kitty kitty
    ensure_cmd wl-copy wl-clipboard
    ensure_cmd wl-paste wl-clipboard
    ensure_cmd waybar waybar
    ensure_cmd hyprpaper hyprpaper || true
    ensure_cmd wofi wofi
    ensure_cmd mako mako
    ensure_cmd waypaper waypaper || true
    ensure_cmd touchegg touchegg
    ensure_cmd nm-applet NetworkManager-gnome
    ensure_cmd cliphist cliphist || true
    ;;
esac

# --- Install Bibata Modern Classic cursor (matches your config) ---
msg "Installing cursor theme: $HYPRCURSOR_NAME ..."
mkdir -p "$CURSOR_DIR"
if [[ ! -d "$CURSOR_DIR/$HYPRCURSOR_NAME" ]]; then
  TMP_CUR="/tmp/${HYPRCURSOR_NAME}.tar.gz"
  if wget -qO "$TMP_CUR" "https://github.com/ful1e5/Bibata_Cursor/releases/download/v2.0.0/${HYPRCURSOR_NAME}.tar.gz"; then
    tar -xzf "$TMP_CUR" -C "$CURSOR_DIR"
    msg "Cursor '$HYPRCURSOR_NAME' installed under $CURSOR_DIR."
  else
    warn "Failed to download ${HYPRCURSOR_NAME}. Consider installing via your package manager."
  fi
else
  msg "Cursor '$HYPRCURSOR_NAME' already present, skipping."
fi

# --- Set cursor theme at the desktop level (best-effort) ---
if command -v gsettings &>/dev/null; then
  gsettings set org.gnome.desktop.interface cursor-theme "$HYPRCURSOR_NAME" 2>/dev/null || true
  gsettings set org.gnome.desktop.interface cursor-size "$HYPRCURSOR_SIZE" 2>/dev/null || true
fi
msg "Cursor theme configured for desktop (if supported)."

# --- Configure Hyprland environment (only append if missing) ---
if command -v hyprctl &>/dev/null; then
  msg "Verifying Hyprland cursor env in $HYPR_CONF ..."
  mkdir -p "$(dirname "$HYPR_CONF")"
  touch "$HYPR_CONF"

  if ! grep -q "^env[[:space:]]*=[[:space:]]*HYPRCURSOR_THEME," "$HYPR_CONF" 2>/dev/null; then
    {
      echo ""
      echo "# --- Cursor settings (managed by install-hypr-dotfiles.sh) ---"
      echo "env = HYPRCURSOR_THEME,$HYPRCURSOR_NAME"
    } >> "$HYPR_CONF"
    msg "Added HYPRCURSOR_THEME to Hyprland config."
  fi

  if ! grep -q "^env[[:space:]]*=[[:space:]]*HYPRCURSOR_SIZE," "$HYPR_CONF" 2>/dev/null; then
    echo "env = HYPRCURSOR_SIZE,$HYPRCURSOR_SIZE" >> "$HYPR_CONF"
    msg "Added HYPRCURSOR_SIZE to Hyprland config."
  fi

  if ! grep -q "^env[[:space:]]*=[[:space:]]*XCURSOR_THEME," "$HYPR_CONF" 2>/dev/null; then
    echo "env = XCURSOR_THEME,$HYPRCURSOR_NAME" >> "$HYPR_CONF"
    msg "Added XCURSOR_THEME to Hyprland config."
  fi

  if ! grep -q "^env[[:space:]]*=[[:space:]]*XCURSOR_SIZE," "$HYPR_CONF" 2>/dev/null; then
    echo "env = XCURSOR_SIZE,$HYPRCURSOR_SIZE" >> "$HYPR_CONF"
    msg "Added XCURSOR_SIZE to Hyprland config."
  fi
fi

# --- Cleanup ---
rm -rf "$TMP_DIR" "/tmp/${HYPRCURSOR_NAME}.tar.gz" 2>/dev/null || true
msg "Temporary files cleaned."

# --- Done ---
msg "✅ Setup complete. Log out/in or restart the compositor for cursor changes to fully apply."
