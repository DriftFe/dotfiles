Zainy :3
driftfe
Online

Jennie⋆.˚Role icon, 𐔌՞ ₊˚⊹Bebos₊˚⊹﹒Ꜣ — 13:57
,av @Smit
MARDO SUDHAR JAO 😡
APP
 — 13:57

Jennie⋆.˚
smitthesexyonee's avatar

Jennie⋆.˚Role icon, 𐔌՞ ₊˚⊹Bebos₊˚⊹﹒Ꜣ — 13:57
:Rega_rotulu: ew
MoguMogu~ [GI], Role icon, 𐔌՞₊˚ Shadow Warden ₊˚﹒Ꜣ — 14:01
😹
Smit — 14:01
Buddy you alright?
Zainy :3Role icon, ꒰🥄﹕ L-40 : Night Owl ⸝⸝♫ ˚ — 14:01
Eh
exoRole icon, 𐔌՞ ₊˚⊹Bebos₊˚⊹﹒Ꜣ — 14:02
Fruity
Zainy :3Role icon, ꒰🥄﹕ L-40 : Night Owl ⸝⸝♫ ˚ — 14:02
Kaun bully ho rha
exoRole icon, 𐔌՞ ₊˚⊹Bebos₊˚⊹﹒Ꜣ — 14:02
Terese bdha femboy aa gya
Jennie⋆.˚Role icon, 𐔌՞ ₊˚⊹Bebos₊˚⊹﹒Ꜣ — 14:03
Yes
Zainy :3Role icon, ꒰🥄﹕ L-40 : Night Owl ⸝⸝♫ ˚ — 14:03
WHAT
not possible
Smit — 14:05
🏃
SpideyyyyRole icon, 𐔌՞ ₊˚⊹Bebos₊˚⊹﹒Ꜣ — 14:07
Hoth rasheley
Tere hoth rasheley
Zainy :3Role icon, ꒰🥄﹕ L-40 : Night Owl ⸝⸝♫ ˚ — 14:08
got my laptop back
and that nigger formatted it
SpideyyyyRole icon, 𐔌՞ ₊˚⊹Bebos₊˚⊹﹒Ꜣ — 14:08
Yeyy
Nice
,afk padhai se maut ka khel phirse
MARDO SUDHAR JAO 😡
APP
 — 14:09
:approve: @Spideyyyy: You're now AFK with the status: padhai se maut ka khel phirse
Zainy :3Role icon, ꒰🥄﹕ L-40 : Night Owl ⸝⸝♫ ˚ — 14:09
welp, at least ive backup of some stuff
Carbon. [DUDU], Role icon, ꒰🥄﹕ L-5 : Sleepy Koala ⸝⸝♫ ˚ — 14:09
@MoguMogu~hi
 [DUDU], 
MoguMogu~ [GI], Role icon, 𐔌՞₊˚ Shadow Warden ₊˚﹒Ꜣ — 14:11
:achaji: helo
 [GI], 
Carbon. [DUDU], Role icon, ꒰🥄﹕ L-5 : Sleepy Koala ⸝⸝♫ ˚ — 14:12
wsg
blackberryshortcakeRole icon, 𐔌՞₊˚ Shadow Warden ₊˚﹒Ꜣ — 14:14
FUCK YOU ALL
TUM SAB KI MKC
Jennie⋆.˚Role icon, 𐔌՞ ₊˚⊹Bebos₊˚⊹﹒Ꜣ — 14:17
Yes fuck me
Zainy :3Role icon, ꒰🥄﹕ L-40 : Night Owl ⸝⸝♫ ˚ — 14:21
#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

# ╔═══════════════════════════════════════════════════════════════╗

message.txt
7 KB
heres the new installer for my uh
dotfiles
uh
should work
Zainy :3Role icon, ꒰🥄﹕ L-40 : Night Owl ⸝⸝♫ ˚ — 14:21
omg yes mommy
﻿
#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

# ╔═══════════════════════════════════════════════════════════════╗
# ║                 Dotfiles Installer for Arch Linux             ║
# ╚═══════════════════════════════════════════════════════════════╝

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

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

# Ensure Arch
if ! command -v pacman >/dev/null 2>&1; then
  err "This installer supports Arch Linux only."
fi

SRC_DOTCONFIG="$script_dir/dot_config"
DEST_CONFIG="$HOME/.config"

[[ -d "$SRC_DOTCONFIG" ]] || err "dot_config directory not found."

mkdir -p "$DEST_CONFIG"

# Ensure rsync
if ! command -v rsync >/dev/null; then
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
if ! command -v yay >/dev/null; then
  log "Installing yay..."

  sudo pacman -S --needed --noconfirm base-devel git

  tmpdir="$(mktemp -d)"
  cleanup() { rm -rf "$tmpdir"; }
  trap cleanup EXIT

  git clone https://aur.archlinux.org/yay.git "$tmpdir/yay"

  (
    cd "$tmpdir/yay"
    makepkg -si --noconfirm
  )
fi

log "Installing AUR packages..."
yay -S --needed --noconfirm --answerclean All --answerdiff None "${AUR_PACKAGES[@]}"

# Enable services
if command -v systemctl >/dev/null; then

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
if command -v gsettings >/dev/null; then
  log "Applying dark theme"
  gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' || true
  gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita-dark' || true
fi

# Zsh setup
log "Configuring Zsh environment"

if command -v zsh >/dev/null; then
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

clone_plugin () {
  local repo="$1"
  local dest="$2"
  [[ -d "$dest" ]] || git clone --depth=1 "$repo" "$dest"
}

clone_plugin https://github.com/zsh-users/zsh-autosuggestions \
"$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions"

clone_plugin https://github.com/zsh-users/zsh-syntax-highlighting \
"$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting"

clone_plugin https://github.com/marlonrichert/zsh-autocomplete \
"$HOME/.oh-my-zsh/custom/plugins/zsh-autocomplete"

# Configure .zshrc
if [[ -f "$HOME/.zshrc" ]]; then

  sed -i 's/^ZSH_THEME=.*/ZSH_THEME="powerlevel10k\/powerlevel10k"/' "$HOME/.zshrc" || true

  if grep -q '^plugins=' "$HOME/.zshrc"; then
    sed -i 's/^plugins=.*/plugins=(git zsh-autosuggestions zsh-autocomplete zsh-syntax-highlighting correction)/' "$HOME/.zshrc"
  else
    echo 'plugins=(git zsh-autosuggestions zsh-autocomplete zsh-syntax-highlighting correction)' >> "$HOME/.zshrc"
  fi

  grep -q 'source ~/.p10k.zsh' "$HOME/.zshrc" || \
  echo '[[ -r ~/.p10k.zsh ]] && source ~/.p10k.zsh' >> "$HOME/.zshrc"

  grep -q 'setopt CORRECT_ALL' "$HOME/.zshrc" || \
  echo 'setopt CORRECT_ALL' >> "$HOME/.zshrc"

else

cat > "$HOME/.zshrc" <<'EOF'
export ZSH="$HOME/.oh-my-zsh"

ZSH_THEME="powerlevel10k/powerlevel10k"

plugins=(
git
zsh-autosuggestions
zsh-autocomplete
zsh-syntax-highlighting
correction
)

source $ZSH/oh-my-zsh.sh

[[ -r ~/.p10k.zsh ]] && source ~/.p10k.zsh

setopt CORRECT_ALL
EOF

fi

success "Dotfiles installation completed successfully."
