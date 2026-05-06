#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$script_dir"

REPO_URL="https://github.com/DriftFe/dotfiles.git"
WORK_DIR=""
TMP_DIR=""
FAILED_PACMAN_PACKAGES=()
FAILED_AUR_PACKAGES=()
CPU_PACKAGES=()
GPU_PACKAGES=()
FORCE_CONFIG_OVERRIDES="${FORCE_CONFIG_OVERRIDES:-0}"

C_RESET='\033[0m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[1;33m'
C_RED='\033[0;31m'
C_CYAN='\033[0;36m'
C_PURPLE='\033[0;35m'
C_PINK='\033[1;95m'

print_banner() {
  echo -e "${C_PINK}"
  cat <<'EOF'
┌──────────────────────────────────────────────┐
│          Lavender Dotfiles Installer         │
│        soft setup, slightly dramatic >~<     │
└──────────────────────────────────────────────┘
EOF
  echo -e "${C_RESET}"
}

section() {
  echo ""
  echo -e "${C_CYAN}==>${C_RESET} ${C_PINK}$*${C_RESET}"
}

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

config_overrides_enabled() {
  [[ "$FORCE_CONFIG_OVERRIDES" == "1" ]]
}

gsettings_value_is() {
  local schema="$1"
  local key="$2"
  local expected="$3"
  local current=""

  current="$(gsettings get "$schema" "$key" 2>/dev/null || true)"
  [[ "$current" == "$expected" ]]
}

sync_dotfiles() {
  if config_overrides_enabled; then
    rsync -avh --mkpath "$SRC_DOTCONFIG"/ "$DEST_CONFIG"/
  else
    rsync -avh --mkpath --ignore-existing "$SRC_DOTCONFIG"/ "$DEST_CONFIG"/
  fi
}

install_mimeapps_defaults() {
  local source_file="$SRC_DOTCONFIG/mimeapps.list"
  local dest_file="$DEST_CONFIG/mimeapps.list"

  [[ -f "$source_file" ]] || return 0

  mkdir -p "$DEST_CONFIG"
  install -m644 "$source_file" "$dest_file"
  success "Installed default application associations"
}

install_local_bin_files() {
  local src_dir="$REPO_ROOT/local_bin"
  local dest_dir="$HOME/.local/bin"

  [[ -d "$src_dir" ]] || return 0

  mkdir -p "$dest_dir"
  rsync -avh --mkpath "$src_dir"/ "$dest_dir"/
  find "$dest_dir" -maxdepth 1 -type f -exec chmod +x {} +
  success "Installed local helper commands"
}

install_local_applications() {
  local src_dir="$REPO_ROOT/local_share/applications"
  local dest_dir="$HOME/.local/share/applications"
  local dolphin_desktop="$dest_dir/org.kde.dolphin.desktop"

  [[ -d "$src_dir" ]] || return 0

  mkdir -p "$dest_dir"
  rsync -avh --mkpath "$src_dir"/ "$dest_dir"/

  if [[ -f "$dolphin_desktop" ]]; then
    sed -i "s|^Exec=.*|Exec=$HOME/.local/bin/dolphin-themed %u|" "$dolphin_desktop"
  fi

  success "Installed local desktop entry overrides"
}

enable_system_service() {
  local unit="$1"

  if systemctl list-unit-files --type=service | awk '{print $1}' | grep -Fxq "$unit"; then
    sudo systemctl unmask "$unit" >/dev/null 2>&1 || true
    sudo systemctl enable --now "$unit"
    success "Enabled $unit"
  else
    warn "$unit not found, skipping"
  fi
}

disable_system_service_if_enabled() {
  local unit="$1"

  if systemctl list-unit-files --type=service | awk '{print $1}' | grep -Fxq "$unit"; then
    if systemctl is-enabled "$unit" >/dev/null 2>&1; then
      sudo systemctl disable "$unit"
      success "Disabled $unit"
    fi
  fi
}

set_default_gdm_session() {
  local session="$1"
  local dmrc="$HOME/.dmrc"
  local tmp_file=""

  if [[ ! -f "$dmrc" ]] || config_overrides_enabled; then
    printf '[Desktop]\nSession=%s\n' "$session" > "$dmrc"
    chmod 644 "$dmrc"
    success "Set $session as the default desktop session in $dmrc"
  else
    info "Keeping existing $dmrc unchanged"
  fi

  if [[ -d /var/lib/AccountsService ]] || have_cmd accounts-daemon; then
    if [[ ! -f "/var/lib/AccountsService/users/$USER" ]] || config_overrides_enabled; then
      tmp_file="$(mktemp)"
      printf '[User]\nSession=%s\nSessionType=wayland\n' "$session" > "$tmp_file"
      sudo install -d -m755 /var/lib/AccountsService/users
      sudo install -m644 "$tmp_file" "/var/lib/AccountsService/users/$USER"
      rm -f "$tmp_file"
      success "Configured AccountsService to default to $session for $USER"
    else
      info "Keeping existing AccountsService session config for $USER"
    fi
  else
    warn "AccountsService not detected; wrote $dmrc only"
  fi
}

set_system_default_target() {
  local target="$1"

  if systemctl list-unit-files --type=target | awk '{print $1}' | grep -Fxq "$target"; then
    sudo systemctl set-default "$target"
    success "Set default systemd target to $target"
  else
    warn "$target not found, skipping"
  fi
}

install_hyprland_session_for_gdm() {
  local session_dir="/usr/share/wayland-sessions"
  local session_file="$session_dir/hyprland.desktop"
  local source_candidates=(
    "/usr/share/hyprland/hyprland.desktop"
    "/usr/share/wayland-sessions/hyprland.desktop"
  )
  local candidate

  if [[ -f "$session_file" ]]; then
    success "Hyprland GDM session entry is present"
    return 0
  fi

  for candidate in "${source_candidates[@]}"; do
    if [[ -f "$candidate" ]]; then
      sudo install -d -m755 "$session_dir"
      sudo install -m644 "$candidate" "$session_file"
      success "Installed Hyprland session entry for GDM"
      return 0
    fi
  done

  warn "Hyprland session entry was not found; GDM may not list Hyprland until the desktop file is installed"
}

configure_bluetooth_defaults() {
  local bluetooth_conf="/etc/bluetooth/main.conf"
  local tmp_file=""

  [[ -f "$bluetooth_conf" ]] || return 0

  tmp_file="$(mktemp)"
  awk '
    BEGIN { updated=0 }
    /^[[:space:]]*#?[[:space:]]*AutoEnable[[:space:]]*=/ {
      print "AutoEnable=true"
      updated=1
      next
    }
    { print }
    END {
      if (!updated) {
        print "AutoEnable=true"
      }
    }
  ' "$bluetooth_conf" > "$tmp_file"
  sudo install -m644 "$tmp_file" "$bluetooth_conf"
  rm -f "$tmp_file"
  success "Configured Bluetooth to power adapters on at startup"
}

install_gtk_defaults() {
  local gtk3_dir="$DEST_CONFIG/gtk-3.0"
  local gtk4_dir="$DEST_CONFIG/gtk-4.0"
  local gtk3_file="$gtk3_dir/settings.ini"
  local gtk4_file="$gtk4_dir/settings.ini"

  mkdir -p "$gtk3_dir" "$gtk4_dir"

  cat > "$gtk3_file" <<'EOF'
[Settings]
gtk-theme-name=adw-gtk3-dark
gtk-application-prefer-dark-theme=true
gtk-cursor-theme-name=Bibata-Modern-Classic
gtk-cursor-theme-size=24
gtk-font-name=Noto Sans, 10
gtk-icon-theme-name=Adwaita
gtk-decoration-layout=icon:minimize,maximize,close
gtk-enable-animations=true
gtk-primary-button-warps-slider=true
EOF
  success "Installed GTK 3 dark theme defaults"

  cat > "$gtk4_file" <<'EOF'
[Settings]
gtk-theme-name=adw-gtk3-dark
gtk-application-prefer-dark-theme=true
gtk-cursor-theme-name=Bibata-Modern-Classic
gtk-cursor-theme-size=24
gtk-font-name=Noto Sans, 10
gtk-icon-theme-name=Adwaita
gtk-decoration-layout=icon:minimize,maximize,close
gtk-enable-animations=true
gtk-primary-button-warps-slider=true
EOF
  success "Installed GTK 4 dark theme defaults"
}

install_kde_color_scheme() {
  local scheme_dir="$HOME/.local/share/color-schemes"
  local scheme_file="$scheme_dir/KittyLavender.colors"
  local source_file="$REPO_ROOT/kde-color-schemes/KittyLavender.colors"

  if [[ ! -f "$source_file" ]]; then
    warn "KittyLavender KDE color scheme source not found, skipping"
    return 0
  fi

  mkdir -p "$scheme_dir"
  install -m644 "$source_file" "$scheme_file"
  success "Installed KittyLavender KDE color scheme"
}

install_kio_defaults() {
  local kiorc_file="$DEST_CONFIG/kiorc"

  mkdir -p "$DEST_CONFIG"
  touch "$kiorc_file"

  if grep -q '^\[General\]' "$kiorc_file"; then
    if grep -q '^TerminalApplication=' "$kiorc_file"; then
      sed -i 's|^TerminalApplication=.*|TerminalApplication=kitty|' "$kiorc_file"
    else
      sed -i '/^\[General\]/a TerminalApplication=kitty' "$kiorc_file"
    fi

    if grep -q '^TerminalService=' "$kiorc_file"; then
      sed -i 's|^TerminalService=.*|TerminalService=kitty.desktop|' "$kiorc_file"
    else
      sed -i '/^\[General\]/a TerminalService=kitty.desktop' "$kiorc_file"
    fi
  else
    cat >> "$kiorc_file" <<'EOF'

[General]
TerminalApplication=kitty
TerminalService=kitty.desktop
EOF
  fi

  success "Configured KDE apps to use Kitty as the terminal"
}

set_media_mime_defaults() {
  local video_mimes=(
    video/mp4
    video/x-matroska
    video/webm
    video/x-msvideo
    video/quicktime
    video/mpeg
    video/x-ms-wmv
    video/x-flv
    video/ogg
    video/3gpp
    video/mp2t
    video/x-m4v
    application/ogg
  )
  local image_mimes=(
    image/png
    image/jpeg
    image/gif
    image/webp
    image/bmp
    image/tiff
    image/svg+xml
    image/avif
    image/heif
    image/heic
  )
  local mime

  log "Setting media file defaults to mpv and imv..."
  for mime in "${video_mimes[@]}"; do
    xdg-mime default mpv.desktop "$mime" || true
  done
  for mime in "${image_mimes[@]}"; do
    xdg-mime default imv.desktop "$mime" || true
  done
}

configure_zsh_theme() {
  local desired_theme='ZSH_THEME="powerlevel10k/powerlevel10k"'

  [[ -f "$ZSHRC" ]] || return 0

  if grep -q '^ZSH_THEME=' "$ZSHRC"; then
    if config_overrides_enabled || grep -Eq '^ZSH_THEME="?(robbyrussell|random)"?$' "$ZSHRC"; then
      sed -i 's|^ZSH_THEME=.*|'"$desired_theme"'|' "$ZSHRC"
      success "Configured Powerlevel10k as the active Oh My Zsh theme"
    else
      info "Keeping existing ZSH_THEME in $ZSHRC"
    fi
  else
    ensure_line_in_file "$ZSHRC" "$desired_theme"
    success "Added Powerlevel10k theme to $ZSHRC"
  fi
}

ensure_zsh_plugin_enabled() {
  local plugin="$1"
  local plugins_line=""
  local plugin_list=()
  local item=""

  [[ -f "$ZSHRC" ]] || return 0

  if grep -q '^plugins=' "$ZSHRC"; then
    plugins_line="$(grep '^plugins=' "$ZSHRC" | head -n1)"
    plugins_line="${plugins_line#plugins=}"
    plugins_line="${plugins_line#\(}"
    plugins_line="${plugins_line%\)}"

    read -r -a plugin_list <<< "$plugins_line"

    for item in "${plugin_list[@]}"; do
      if [[ "$item" == "$plugin" ]]; then
        info "Keeping existing plugins= line in $ZSHRC"
        return 0
      fi
    done

    plugin_list+=("$plugin")
    sed -i "s|^plugins=.*|plugins=(${plugin_list[*]})|" "$ZSHRC"
    success "Enabled $plugin in $ZSHRC"
  else
    ensure_line_in_file "$ZSHRC" "plugins=(git $plugin)"
    success "Added plugins=(git $plugin) to $ZSHRC"
  fi
}

configure_pacman_options() {
  local tmp_file=""

  tmp_file="$(mktemp)"
  awk '
    /^\[options\]$/ {
      in_options=1
      print
      next
    }

    /^\[/ && in_options {
      if (!candy_seen && !candy_added) {
        print "ILoveCandy"
        candy_added=1
      }
      in_options=0
    }

    in_options && /^[[:space:]]*#Color[[:space:]]*$/ {
      $0="Color"
    }

    in_options && /^[[:space:]]*ILoveCandy[[:space:]]*$/ {
      candy_seen=1
    }

    {
      print
      if (in_options && /^[[:space:]]*Color[[:space:]]*$/ && !candy_seen && !candy_added) {
        print "ILoveCandy"
        candy_added=1
      }
    }

    END {
      if (in_options && !candy_seen && !candy_added) {
        print "ILoveCandy"
      }
    }
  ' /etc/pacman.conf > "$tmp_file"

  sudo install -m644 "$tmp_file" /etc/pacman.conf
  rm -f "$tmp_file"
  success "Enabled Pacman color output and ILoveCandy"
}

multilib_enabled() {
  awk '
    /^\[multilib\]$/ { in_multilib=1; next }
    /^\[/ { in_multilib=0 }
    in_multilib && /^[[:space:]]*Include[[:space:]]*=/ { found=1 }
    END { exit(found ? 0 : 1) }
  ' /etc/pacman.conf
}

prompt_cpu_driver_packages() {
  CPU_PACKAGES=()
  CPU_DRIVER_LABEL="No extra CPU microcode packages"

  if [[ ! -t 0 || ! -t 1 ]]; then
    info "Non-interactive session detected; skipping CPU driver selection."
    return 0
  fi

  echo ""
  info "Choose the CPU support packages you want:"
  echo "  1) AMD"
  echo "  2) Intel"
  echo "  3) Virtual machine / generic"
  echo "  4) Skip extra CPU packages"

  while true; do
    read -r -p "Enter your choice [1-4]: " cpu_choice

    case "$cpu_choice" in
      1)
        CPU_DRIVER_LABEL="AMD"
        CPU_PACKAGES=(
          amd-ucode
        )
        break
        ;;
      2)
        CPU_DRIVER_LABEL="Intel"
        CPU_PACKAGES=(
          intel-ucode
        )
        break
        ;;
      3)
        CPU_DRIVER_LABEL="Virtual machine / generic"
        CPU_PACKAGES=()
        break
        ;;
      4)
        break
        ;;
      *)
        warn "Invalid selection. Please choose a number from 1 to 4."
        ;;
    esac
  done

  if (( ${#CPU_PACKAGES[@]} > 0 )); then
    success "Selected CPU package set: $CPU_DRIVER_LABEL"
    info "CPU packages: ${CPU_PACKAGES[*]}"
  else
    info "Skipping extra CPU packages."
  fi
}

prompt_gpu_driver_packages() {
  GPU_PACKAGES=()
  GPU_DRIVER_LABEL="No extra GPU driver packages"
  local include_multilib=0

  if multilib_enabled; then
    include_multilib=1
  else
    info "multilib is not enabled; skipping 32-bit graphics packages."
  fi

  if [[ ! -t 0 || ! -t 1 ]]; then
    info "Non-interactive session detected; skipping GPU driver selection."
    return 0
  fi

  echo ""
  info "Choose the graphics driver stack you want:"
  echo "  1) AMD"
  echo "  2) Intel"
  echo "  3) NVIDIA"
  echo "  4) Virtual machine / software rendering"
  echo "  5) Skip extra GPU drivers"

  while true; do
    read -r -p "Enter your choice [1-5]: " gpu_choice

    case "$gpu_choice" in
      1)
        GPU_DRIVER_LABEL="AMD"
        GPU_PACKAGES=(
          mesa
          libvdpau
          libvdpau-va-gl
          libva-utils
          vulkan-icd-loader
          vulkan-radeon
          vdpauinfo
          vulkan-tools
        )
        if (( include_multilib )); then
          GPU_PACKAGES+=(
            lib32-mesa
            lib32-vulkan-icd-loader
            lib32-vulkan-radeon
          )
        fi
        break
        ;;
      2)
        GPU_DRIVER_LABEL="Intel"
        GPU_PACKAGES=(
          intel-media-driver
          libvdpau
          libva-utils
          mesa
          vulkan-icd-loader
          vulkan-intel
          vdpauinfo
          vulkan-tools
        )
        if (( include_multilib )); then
          GPU_PACKAGES+=(
            lib32-mesa
            lib32-vulkan-icd-loader
            lib32-vulkan-intel
          )
        fi
        break
        ;;
      3)
        GPU_DRIVER_LABEL="NVIDIA"
        GPU_PACKAGES=(
          libva-nvidia-driver
          libva-utils
          libvdpau
          nvidia-open
          nvidia-utils
          nvidia-settings
          vdpauinfo
          vulkan-icd-loader
          vulkan-tools
        )
        if (( include_multilib )); then
          GPU_PACKAGES+=(
            lib32-vulkan-icd-loader
            lib32-nvidia-utils
          )
        fi
        break
        ;;
      4)
        GPU_DRIVER_LABEL="Virtual machine / software rendering"
        GPU_PACKAGES=(
          libvdpau
          libvdpau-va-gl
          libva-utils
          mesa
          vulkan-icd-loader
          vulkan-swrast
          vdpauinfo
          vulkan-tools
        )
        if (( include_multilib )); then
          GPU_PACKAGES+=(
            lib32-mesa
            lib32-vulkan-icd-loader
            lib32-vulkan-swrast
          )
        fi
        break
        ;;
      5)
        break
        ;;
      *)
        warn "Invalid selection. Please choose a number from 1 to 5."
        ;;
    esac
  done

  if (( ${#GPU_PACKAGES[@]} > 0 )); then
    success "Selected GPU driver set: $GPU_DRIVER_LABEL"
    info "GPU packages: ${GPU_PACKAGES[*]}"
  else
    info "Skipping extra GPU driver packages."
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

install_font_fallback_config() {
  local fontconfig_dir="$DEST_CONFIG/fontconfig/conf.d"
  local fontconfig_file="$fontconfig_dir/75-font-fallbacks.conf"

  mkdir -p "$fontconfig_dir"

  if [[ -f "$fontconfig_file" ]] && ! config_overrides_enabled; then
    info "Keeping existing font fallback config at $fontconfig_file"
    return 0
  fi

  cat > "$fontconfig_file" <<'EOF'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<fontconfig>
  <alias>
    <family>sans-serif</family>
    <prefer>
      <family>Noto Sans</family>
      <family>Noto Sans CJK SC</family>
      <family>Noto Sans CJK TC</family>
      <family>Noto Sans CJK JP</family>
      <family>Noto Sans CJK KR</family>
      <family>Noto Sans Arabic</family>
      <family>Noto Sans Hebrew</family>
      <family>Noto Sans Devanagari</family>
      <family>Noto Sans Thai</family>
      <family>Noto Color Emoji</family>
      <family>WenQuanYi Zen Hei</family>
      <family>DejaVu Sans</family>
      <family>Liberation Sans</family>
    </prefer>
  </alias>

  <alias>
    <family>serif</family>
    <prefer>
      <family>Noto Serif</family>
      <family>Noto Serif CJK SC</family>
      <family>Noto Serif CJK TC</family>
      <family>Noto Serif CJK JP</family>
      <family>Noto Serif CJK KR</family>
      <family>Noto Naskh Arabic</family>
      <family>Noto Serif Hebrew</family>
      <family>Noto Serif Devanagari</family>
      <family>Noto Color Emoji</family>
      <family>Jigmo</family>
      <family>IPAexMincho</family>
      <family>DejaVu Serif</family>
      <family>Liberation Serif</family>
    </prefer>
  </alias>

  <alias>
    <family>monospace</family>
    <prefer>
      <family>JetBrainsMono Nerd Font</family>
      <family>JetBrains Mono</family>
      <family>Noto Sans Mono</family>
      <family>Noto Sans Mono CJK SC</family>
      <family>Noto Sans Mono CJK TC</family>
      <family>Noto Sans Mono CJK JP</family>
      <family>Noto Sans Mono CJK KR</family>
      <family>Noto Sans Devanagari</family>
      <family>Noto Sans Arabic</family>
      <family>Noto Sans Hebrew</family>
      <family>Noto Sans Thai</family>
      <family>Symbols Nerd Font Mono</family>
      <family>Noto Color Emoji</family>
      <family>DejaVu Sans Mono</family>
      <family>Liberation Mono</family>
    </prefer>
  </alias>
</fontconfig>
EOF

  success "Installed font fallback config at $fontconfig_file"
}

install_pacman_packages() {
  local pkg

  for pkg in "$@"; do
    [[ -n "$pkg" ]] || continue

    info "Installing pacman package: $pkg"
    if sudo pacman -S --needed --noconfirm "$pkg"; then
      success "Installed pacman package: $pkg"
    else
      warn "Failed to install pacman package: $pkg"
      FAILED_PACMAN_PACKAGES+=("$pkg")
    fi
  done
}

install_aur_packages() {
  local pkg

  for pkg in "$@"; do
    [[ -n "$pkg" ]] || continue

    info "Installing AUR package: $pkg"
    if yay -S --needed --noconfirm --answerclean All --answerdiff None "$pkg"; then
      success "Installed AUR package: $pkg"
    else
      warn "Failed to install AUR package: $pkg"
      FAILED_AUR_PACKAGES+=("$pkg")
    fi
  done
}

print_package_failure_summary() {
  if (( ${#FAILED_PACMAN_PACKAGES[@]} == 0 && ${#FAILED_AUR_PACKAGES[@]} == 0 )); then
    success "All requested packages installed successfully"
    return 0
  fi

  warn "Some packages failed to install"

  if (( ${#FAILED_PACMAN_PACKAGES[@]} > 0 )); then
    warn "Pacman failures: ${FAILED_PACMAN_PACKAGES[*]}"
  fi

  if (( ${#FAILED_AUR_PACKAGES[@]} > 0 )); then
    warn "AUR failures: ${FAILED_AUR_PACKAGES[*]}"
  fi
}

trap cleanup EXIT

print_banner

if [[ $EUID -eq 0 ]]; then
  err "Do not run this installer as root. Run it as your normal user."
fi

have_cmd pacman || err "This installer supports Arch Linux only."

section "Getting ready"
log "Refreshing sudo credentials..."
sudo -v

SRC_DOTCONFIG="$script_dir/dot_config"
DEST_CONFIG="$HOME/.config"
ZSHRC="$HOME/.zshrc"

if [[ ! -d "$SRC_DOTCONFIG" ]]; then
  warn "dot_config directory not found next to install.sh."

  if ! have_cmd git; then
    info "Installing git so the repository can be fetched"
    install_pacman_packages git
    have_cmd git || err "git is required to clone the dotfiles repository."
  fi

  WORK_DIR="$(mktemp -d)"
  info "Cloning dotfiles repository..."
  git clone --depth=1 "$REPO_URL" "$WORK_DIR/repo"

  REPO_ROOT="$WORK_DIR/repo"
  SRC_DOTCONFIG="$REPO_ROOT/dot_config"
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
  hyprland
  awww
  hyprlock
  waybar
  wofi
  mako
  libnotify
  wl-clipboard
  cliphist
  brightnessctl
  grim
  slurp
  dolphin
  mpv
  imv
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
  gdm
  gnome-session
  gnome-shell
  gnome-desktop-4
  gsettings-desktop-schemas
  gsettings-system-schemas
  mutter
  touchegg
  xsettingsd
  qt5ct
  gnome-keyring
  udisks2
  playerctl
  cava
  fontconfig
  noto-fonts
  noto-fonts-cjk
  noto-fonts-emoji
  noto-fonts-extra
  ttf-indic-otf
  otf-ipaexfont
  ttf-jigmo
  wqy-zenhei
  wqy-microhei
  ttf-roboto
  ttf-jetbrains-mono
  ttf-dejavu
  ttf-liberation
  ttf-nerd-fonts-symbols
  ttf-font-awesome
  gnu-free-fonts
  xdg-desktop-portal
  xdg-desktop-portal-hyprland
  xdg-user-dirs
  polkit-gnome
)

AUR_PACKAGES=(
  wlogout
  waypaper
  vesktop-bin
  zen-browser-bin
  ttf-meslo-nerd-font-powerlevel10k
  gpu-screen-recorder
  nerd-fonts-jetbrains-mono
  grimblast-git
  swappy
  bibata-cursor-theme
  hyprpicker
  adw-gtk3
  cbonsai
)

section "System update"
log "Configuring pacman options..."
configure_pacman_options
log "Updating system..."
sudo pacman -Syu --noconfirm

section "Hardware setup"
prompt_cpu_driver_packages
prompt_gpu_driver_packages

section "Pacman packages"
log "Installing pacman packages..."
install_pacman_packages "${PACMAN_PACKAGES[@]}" "${CPU_PACKAGES[@]}" "${GPU_PACKAGES[@]}"

section "Schemas and configs"
log "Rebuilding GSettings schemas..."
sudo glib-compile-schemas /usr/share/glib-2.0/schemas

mkdir -p "$DEST_CONFIG"

log "Copying dotfiles into $DEST_CONFIG..."
sync_dotfiles
install_mimeapps_defaults
install_local_bin_files
install_local_applications

log "Installing font fallback preferences..."
install_font_fallback_config
install_gtk_defaults
install_kde_color_scheme
install_kio_defaults

if ! have_cmd yay; then
  section "AUR helper"
  log "Installing yay..."
  TMP_DIR="$(mktemp -d)"
  git clone https://aur.archlinux.org/yay.git "$TMP_DIR/yay"
  (
    cd "$TMP_DIR/yay"
    makepkg -si --noconfirm
  )
fi

if (( ${#AUR_PACKAGES[@]} > 0 )); then
  section "AUR packages"
  log "Installing AUR packages..."
  install_aur_packages "${AUR_PACKAGES[@]}"
fi

section "System services"
log "Enabling system services..."
enable_system_service "NetworkManager.service"
enable_system_service "bluetooth.service"
enable_system_service "gdm.service"
enable_system_service "touchegg.service"
enable_system_service "udisks2.service"
set_system_default_target "graphical.target"
disable_system_service_if_enabled "sddm.service"
disable_system_service_if_enabled "lightdm.service"
install_hyprland_session_for_gdm
set_default_gdm_session "hyprland"
configure_bluetooth_defaults

log "Creating swww compatibility symlinks for Waypaper..."
sudo ln -sf /usr/bin/awww /usr/bin/swww
sudo ln -sf /usr/bin/awww-daemon /usr/bin/swww-daemon
success "Waypaper compatibility symlinks are in place"

section "User services"
log "Enabling user services..."
systemctl --user disable --now pulseaudio.service pulseaudio.socket 2>/dev/null || true
systemctl --user mask pulseaudio.service pulseaudio.socket 2>/dev/null || true
enable_user_service "pipewire.service"
enable_user_service "pipewire-pulse.service"
enable_user_service "wireplumber.service"
enable_user_service "xsettingsd.service"
enable_user_service "gnome-keyring-daemon.service"
enable_user_service "xdg-desktop-portal.service"
enable_user_service "xdg-desktop-portal-hyprland.service"
print_package_failure_summary

section "Permissions"
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
    info "chmod +x on *.py in $dir"
    find "$dir" -type f -name "*.py" -exec chmod +x {} +
  fi
done

chmod +x "$script_dir/install.sh" 2>/dev/null || true

if have_cmd gsettings; then
  if config_overrides_enabled || \
    gsettings_value_is org.gnome.desktop.interface color-scheme "'default'" || \
    gsettings_value_is org.gnome.desktop.interface gtk-theme "'Adwaita'" || \
    gsettings_value_is org.gnome.desktop.interface icon-theme "'Adwaita'" || \
    gsettings_value_is org.gnome.desktop.interface cursor-theme "'Adwaita'"; then
    section "Theme defaults"
    log "Applying GTK theme and cursor defaults..."
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' || true
    gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3-dark' || true
    gsettings set org.gnome.desktop.interface icon-theme 'Adwaita' || true
    gsettings set org.gnome.desktop.interface cursor-theme 'Bibata-Modern-Classic' || true
    gsettings set org.gnome.desktop.interface cursor-size 24 || true
  else
    info "Keeping existing GTK theme and cursor settings"
  fi
fi

mkdir -p "$HOME/Pictures/Screenshots"
success "Ensured ~/Pictures/Screenshots exists"

section "Zsh setup"
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
P10K_DIR="$HOME/.oh-my-zsh/custom/themes/powerlevel10k"
if [[ ! -d "$P10K_DIR" ]]; then
  git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$P10K_DIR"
fi

if [[ -f "$ZSHRC" ]]; then
  configure_zsh_theme
fi

log "Installing Zsh plugins..."
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
mkdir -p "$ZSH_CUSTOM/plugins"

if [[ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]]; then
  info "Installing zsh-autosuggestions..."
  git clone https://github.com/zsh-users/zsh-autosuggestions \
    "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
fi

if [[ -f "$ZSHRC" ]]; then
  ensure_zsh_plugin_enabled "zsh-autosuggestions"
fi

section "Desktop defaults"
if have_cmd xdg-mime; then
  set_media_mime_defaults

  if config_overrides_enabled; then
    log "Setting Dolphin as the default file manager..."
    xdg-mime default org.kde.dolphin.desktop inode/directory || true
    xdg-mime default org.kde.dolphin.desktop application/x-gnome-saved-search || true
  else
    info "Keeping existing default file manager associations"
  fi
fi

if have_cmd xdg-user-dirs-update; then
  xdg-user-dirs-update
fi

if have_cmd fc-cache; then
  log "Rebuilding font cache..."
  fc-cache -f
fi

section "Validation"
log "Validating core commands used by the dotfiles..."
missing_commands=()
for cmd in hyprland waybar wlogout wofi mako wl-copy wl-paste cliphist blueman-applet bluetoothctl \
  udisksctl playerctl hyprpicker grimblast swappy awww-daemon dolphin hyprlock mpv imv; do
  have_cmd "$cmd" || missing_commands+=("$cmd")
done

if (( ${#missing_commands[@]} > 0 )); then
  warn "Some expected commands are still missing: ${missing_commands[*]}"
else
  success "Core dotfile dependencies look good"
fi

if [[ ! -x /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 ]]; then
  warn "polkit-gnome authentication agent is missing; some Bluetooth or privilege dialogs may not appear in Hyprland"
fi

echo ""
success "Installation complete!"
if config_overrides_enabled; then
  info "Applied config overrides because FORCE_CONFIG_OVERRIDES=1 was set."
else
  info "Safe update mode kept existing config files and defaults in place."
fi
if (( ${#CPU_PACKAGES[@]} > 0 )); then
  info "CPU package choice: ${CPU_DRIVER_LABEL:-custom}"
fi
if (( ${#GPU_PACKAGES[@]} > 0 )); then
  info "GPU package choice: ${GPU_DRIVER_LABEL:-custom}"
fi
info "Reboot or log out and back in so shell, services, and desktop changes fully apply."
if [[ -t 0 && -t 1 ]] && have_cmd zsh; then
  info "Launching an interactive zsh so Powerlevel10k can finish setup..."
  zsh -ic 'source ~/.zshrc' || true
else
  info "Open a new zsh session or run 'source ~/.zshrc' to launch the Powerlevel10k wizard."
fi
