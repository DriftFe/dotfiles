#!/usr/bin/env bash

# Arch-only dotfiles installer for Hyprland
# - Installs required repo and AUR packages (via yay/paru; bootstraps yay if missing)
# - Syncs dotfiles + wallpapers from the repo
# - Ensures hyprpaper and wofi font config
# - Sets Bibata cursor theme system-wide (GTK + Hypr env)

set -euo pipefail

# --- UI helpers ---
msg()  { echo -e "\e[32m[INFO]\e[0m  $*"; }
warn() { echo -e "\e[33m[WARN]\e[0m  $*"; }
err()  { echo -e "\e[31m[ERROR]\e[0m $*" >&2; exit 1; }

# --- Pre-flight: ensure Arch ---
command -v pacman >/dev/null 2>&1 || err "This script supports only Arch-based systems (pacman not found)."

# --- Vars ---
DOTFILES_REPO="https://github.com/DriftFe/dotfiles"
TMP_DIR="$(mktemp -d -t dotfiles-setup-XXXXXX)"
CURSOR_DIR="$HOME/.icons"
HYPR_CONF="$HOME/.config/hypr/hyprland.conf"
HYPRPAPER_CONF="$HOME/.config/hyprpaper/hyprpaper.conf"
WOFI_STYLE="$HOME/.config/wofi/style.css"
WALL_DIR="$HOME/.wallpapers"
HYPRCURSOR_NAME="Bibata-Modern-Classic"
HYPRCURSOR_SIZE="24"

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
# Core repo packages
PAC_PKGS=(
  hyprland hyprpaper hyprland-qtutils
  waybar wofi mako kitty gdm
  cliphist wl-clipboard network-manager-applet touchegg
  rsync wget curl unzip
  noto-fonts noto-fonts-emoji ttf-font-awesome
  bibata-cursor-theme
)

# Try to install Nerd font + JetBrains packages from repo first, otherwise AUR
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

# Additional AUR packages
AUR_PKGS=(
  waypaper
  ttf-nerd-fonts-symbols ttf-nerd-fonts-symbols-mono
)
msg "Installing AUR packages..."
"$AUR_HELPER" -S --needed --noconfirm "${AUR_PKGS[@]}" || warn "Some AUR packages failed."

# --- Fetch dotfiles ---
msg "Fetching dotfiles from $DOTFILES_REPO ..."
rm -rf "$TMP_DIR" && mkdir -p "$TMP_DIR"
if ! git clone --depth=1 "$DOTFILES_REPO" "$TMP_DIR"; then
  err "Failed to clone $DOTFILES_REPO"
fi

# --- Sync dot_* and optional .config ---
msg "Syncing dot_* content and wallpapers..."
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

# --- Cleanup ---
rm -rf "$TMP_DIR" || true

msg "Done. Reboot or restart Hyprland for all changes to take full effect."
