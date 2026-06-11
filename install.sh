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
PRESERVE_EXISTING_CONFIGS="${PRESERVE_EXISTING_CONFIGS:-0}"

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

preserve_existing_configs_enabled() {
  [[ "$PRESERVE_EXISTING_CONFIGS" == "1" && "$FORCE_CONFIG_OVERRIDES" != "1" ]]
}

install_file_if_changed() {
  local source_file="$1"
  local dest_file="$2"
  local mode="$3"
  local label="$4"

  [[ -f "$source_file" ]] || return 0
  mkdir -p "$(dirname -- "$dest_file")"

  if preserve_existing_configs_enabled && [[ -e "$dest_file" ]]; then
    info "Keeping existing $label"
    return 0
  fi

  if [[ -f "$dest_file" ]] && cmp -s "$source_file" "$dest_file"; then
    info "$label is already current"
    return 0
  fi

  install -m "$mode" "$source_file" "$dest_file"
  success "Updated $label"
}

install_generated_file_if_changed() {
  local source_file="$1"
  local dest_file="$2"
  local mode="$3"
  local label="$4"

  install_file_if_changed "$source_file" "$dest_file" "$mode" "$label"
  rm -f "$source_file"
}

gsettings_value_is() {
  local schema="$1"
  local key="$2"
  local expected="$3"
  local current=""

  current="$(gsettings get "$schema" "$key" 2>/dev/null || true)"
  [[ "$current" == "$expected" ]]
}

validate_json_file() {
  local file="$1"

  [[ -f "$file" ]] || err "Missing required config file: $file"

  if have_cmd python3; then
    python3 -m json.tool "$file" >/dev/null || err "Invalid JSON: $file"
  else
    warn "python3 not found; skipping JSON validation for $file"
  fi
}

validate_css_file() {
  local file="$1"
  local first_nonempty=""

  [[ -f "$file" ]] || err "Missing required CSS file: $file"

  first_nonempty="$(sed -n '/[^[:space:]]/ { s/^[[:space:]]*//; p; q; }' "$file")"
  if [[ "$first_nonempty" == \{* || "$first_nonempty" == \[* ]]; then
    err "$file looks like JSON, not CSS"
  fi

  grep -Eq '(^|[[:space:]])window#waybar[[:space:]]*\{' "$file" || \
    err "$file does not look like a Waybar stylesheet"
}

validate_shell_scripts() {
  local file

  while IFS= read -r -d '' file; do
    bash -n "$file" || err "Shell syntax check failed: $file"
  done < <(find "$SRC_DOTCONFIG" -type f -name "*.sh" -print0)
}

validate_python_scripts() {
  local file

  if ! have_cmd python3; then
    warn "python3 not found; skipping Python syntax validation"
    return 0
  fi

  while IFS= read -r -d '' file; do
    python3 -m py_compile "$file" || err "Python syntax check failed: $file"
  done < <(find "$SRC_DOTCONFIG" -type f -name "*.py" -print0)
}

validate_referenced_config_files() {
  if ! have_cmd python3; then
    warn "python3 not found; skipping referenced script validation"
    return 0
  fi

  python3 - "$SRC_DOTCONFIG" <<'PY'
import json
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
missing = []

def check_config_path(source, label, command):
    if not isinstance(command, str):
        return

    for match in re.finditer(r'~/(?:\.config)/([^"\'\s,;&|]+)', command):
        rel = match.group(1)
        target = root / rel
        if not target.exists():
            missing.append(f"{source}: {label} references missing ~/.config/{rel}")

waybar_config = root / "waybar/config"
if waybar_config.exists():
    with waybar_config.open(encoding="utf-8") as f:
        config = json.load(f)

    for section in ("modules-left", "modules-center", "modules-right"):
        for module in config.get(section, []):
            if module.startswith("custom/") and module not in config:
                missing.append(f"waybar/config: {section} lists {module}, but no module config exists")

    for module, values in config.items():
        if not isinstance(values, dict):
            continue

        for key in ("exec", "on-click", "on-scroll-up", "on-scroll-down"):
            check_config_path("waybar/config", f"{module}.{key}", values.get(key))

hypr_files = list((root / "hypr").glob("*.conf"))
keys_file = root / "hypr/keys.conf"
if keys_file.exists():
    hypr_files.append(keys_file)

for hypr_file in hypr_files:
    text = hypr_file.read_text(encoding="utf-8")
    for line_number, line in enumerate(text.splitlines(), 1):
        check_config_path(str(hypr_file.relative_to(root)), f"line {line_number}", line)

if missing:
    for item in missing:
        print(item, file=sys.stderr)
    sys.exit(1)
PY
  local status=$?
  (( status == 0 )) || err "One or more configs reference missing files"
}

validate_source_dotfiles() {
  section "Config validation"
  log "Checking source dotfiles before copying..."

  validate_json_file "$SRC_DOTCONFIG/waybar/config"
  validate_css_file "$SRC_DOTCONFIG/waybar/style.css"
  validate_shell_scripts
  validate_python_scripts
  validate_referenced_config_files

  if grep -R -nE '^[[:space:]]*pseudotile[[:space:]]*=' "$SRC_DOTCONFIG/hypr" >/dev/null 2>&1; then
    grep -R -nE '^[[:space:]]*pseudotile[[:space:]]*=' "$SRC_DOTCONFIG/hypr" >&2 || true
    err "Found obsolete Hyprland pseudotile config"
  fi

  success "Source dotfiles passed basic validation"
}

sync_dotfiles() {
  local rsync_args=(
    -avh
    --checksum
    --mkpath
    --exclude '/.zshrc'
    --exclude '/local_bin/'
    --exclude '/local_share/'
    --exclude '/kde-color-schemes/'
  )

  if preserve_existing_configs_enabled; then
    rsync_args+=(--ignore-existing)
  fi

  if rsync "${rsync_args[@]}" "$SRC_DOTCONFIG"/ "$DEST_CONFIG"/; then
    success "Synced changed dotfiles into $DEST_CONFIG"
  else
    err "Dotfile sync failed"
  fi
}

install_zshrc() {
  local source_file="$SRC_DOTCONFIG/.zshrc"

  [[ -f "$source_file" ]] || return 0

  install_file_if_changed "$source_file" "$ZSHRC" 644 "Zsh config"
}

install_mimeapps_defaults() {
  local source_file="$SRC_DOTCONFIG/mimeapps.list"
  local dest_file="$DEST_CONFIG/mimeapps.list"

  [[ -f "$source_file" ]] || return 0

  install_file_if_changed "$source_file" "$dest_file" 644 "default application associations"
}

install_local_bin_files() {
  local src_dir="$SRC_DOTCONFIG/local_bin"
  local dest_dir="$HOME/.local/bin"
  local rsync_args=(-avh --checksum --mkpath)

  [[ -d "$src_dir" ]] || return 0

  preserve_existing_configs_enabled && rsync_args+=(--ignore-existing)

  mkdir -p "$dest_dir"
  rsync "${rsync_args[@]}" "$src_dir"/ "$dest_dir"/
  find "$dest_dir" -maxdepth 1 -type f -exec chmod +x {} +
  success "Synced local helper commands"
}

install_local_applications() {
  local src_dir="$SRC_DOTCONFIG/local_share/applications"
  local dest_dir="$HOME/.local/share/applications"
  local dolphin_desktop="$dest_dir/org.kde.dolphin.desktop"
  local dolphin_exec="Exec=$HOME/.local/bin/dolphin-themed %u"
  local rsync_args=(-avh --checksum --mkpath)

  [[ -d "$src_dir" ]] || return 0

  preserve_existing_configs_enabled && rsync_args+=(--ignore-existing)

  mkdir -p "$dest_dir"
  rsync "${rsync_args[@]}" "$src_dir"/ "$dest_dir"/

  if [[ -f "$dolphin_desktop" ]]; then
    if ! grep -Fxq "$dolphin_exec" "$dolphin_desktop"; then
      sed -i "s|^Exec=.*|$dolphin_exec|" "$dolphin_desktop"
      success "Updated Dolphin desktop entry"
    fi
  fi

  success "Synced local desktop entry overrides"
}

normalize_user_config_paths() {
  local dolphinrc="$DEST_CONFIG/dolphinrc"
  local bookmarks="$DEST_CONFIG/private_gtk-3.0/bookmarks"

  if [[ -f "$dolphinrc" ]]; then
    if grep -Eq '^HomeUrl=file:///home/[^/[:space:]]*' "$dolphinrc"; then
      sed -i "s|^HomeUrl=file:///home/[^/[:space:]]*|HomeUrl=file://$HOME|" "$dolphinrc"
      success "Normalized Dolphin home path"
    fi
  fi

  if [[ -f "$bookmarks" ]]; then
    if grep -Eq 'file:///home/[^/]*/' "$bookmarks"; then
      sed -i "s|file:///home/[^/]*/|file://$HOME/|g" "$bookmarks"
      success "Normalized GTK bookmark paths"
    fi
  fi
}

enable_system_service() {
  local unit="$1"

  if systemctl list-unit-files "$unit" --type=service --no-legend 2>/dev/null | awk '{print $1}' | grep -Fxq "$unit"; then
    sudo systemctl unmask "$unit" >/dev/null 2>&1 || true
    sudo systemctl enable "$unit"
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
      printf '[User]\nSession=%s\nXSession=%s\nSessionType=wayland\n' "$session" "$session" > "$tmp_file"
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
  local tmp_file=""

  mkdir -p "$gtk3_dir" "$gtk4_dir"

  tmp_file="$(mktemp)"
  cat > "$tmp_file" <<'EOF'
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
  install_generated_file_if_changed "$tmp_file" "$gtk3_file" 644 "GTK 3 dark theme defaults"

  tmp_file="$(mktemp)"
  cat > "$tmp_file" <<'EOF'
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
  install_generated_file_if_changed "$tmp_file" "$gtk4_file" 644 "GTK 4 dark theme defaults"
}

install_kde_theme_files() {
  local data_dir="$HOME/.local/share"
  local source_dir="$SRC_DOTCONFIG/kde-color-schemes"
  local rsync_args=(-avh --checksum --mkpath)

  if [[ -d "$source_dir" ]]; then
    preserve_existing_configs_enabled && rsync_args+=(--ignore-existing)
    mkdir -p "$data_dir/color-schemes"
    rsync "${rsync_args[@]}" "$source_dir"/ "$data_dir/color-schemes"/
    success "Synced KDE color schemes"
  fi

  install_file_if_changed "$SRC_DOTCONFIG/kdeglobals" "$DEST_CONFIG/kdeglobals" 644 "KDE global theme defaults"
  install_file_if_changed "$SRC_DOTCONFIG/dolphin.qss" "$DEST_CONFIG/dolphin.qss" 644 "Dolphin stylesheet"
}

install_kio_defaults() {
  local kiorc_file="$DEST_CONFIG/kiorc"

  mkdir -p "$DEST_CONFIG"
  touch "$kiorc_file"

  if grep -q '^\[General\]' "$kiorc_file"; then
    if grep -q '^TerminalApplication=' "$kiorc_file"; then
      grep -Fxq 'TerminalApplication=kitty' "$kiorc_file" || \
        sed -i 's|^TerminalApplication=.*|TerminalApplication=kitty|' "$kiorc_file"
    else
      sed -i '/^\[General\]/a TerminalApplication=kitty' "$kiorc_file"
    fi

    if grep -q '^TerminalService=' "$kiorc_file"; then
      grep -Fxq 'TerminalService=kitty.desktop' "$kiorc_file" || \
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
  local mpv_desktop="/usr/share/applications/mpv.desktop"
  local imv_desktop="/usr/share/applications/imv.desktop"
  local mimes=()
  local mime

  log "Setting media file defaults to mpv and imv..."

  if [[ -f "$mpv_desktop" ]]; then
    IFS=';' read -r -a mimes <<< "$(grep -m1 '^MimeType=' "$mpv_desktop" | cut -d= -f2-)"
    for mime in "${mimes[@]}"; do
      [[ -n "$mime" ]] && xdg-mime default mpv.desktop "$mime" || true
    done
  else
    warn "mpv.desktop not found; video defaults may not be registered"
  fi

  if [[ -f "$imv_desktop" ]]; then
    IFS=';' read -r -a mimes <<< "$(grep -m1 '^MimeType=' "$imv_desktop" | cut -d= -f2-)"
    for mime in "${mimes[@]}"; do
      [[ -n "$mime" ]] && xdg-mime default imv.desktop "$mime" || true
    done
  else
    warn "imv.desktop not found; image defaults may not be registered"
  fi
}

rebuild_kde_service_cache() {
  rm -f "$HOME"/.cache/ksycoca6_* 2>/dev/null || true

  if have_cmd update-mime-database; then
    sudo update-mime-database /usr/share/mime || warn "Could not update shared MIME database"
  fi

  if have_cmd kbuildsycoca6; then
    XDG_MENU_PREFIX=arch- kbuildsycoca6 --noincremental || warn "Could not rebuild KDE service cache"
  fi
}

configure_kde_application_menu() {
  local arch_menu="/etc/xdg/menus/arch-applications.menu"
  local fallback_menu="/etc/xdg/menus/applications.menu"

  if [[ -e "$arch_menu" && ! -e "$fallback_menu" ]]; then
    sudo ln -sf "$arch_menu" "$fallback_menu"
    success "Linked KDE fallback applications menu to Arch's XDG menu"
  elif [[ -e "$fallback_menu" ]]; then
    success "KDE fallback applications menu is present"
  else
    warn "$arch_menu is missing; install archlinux-xdg-menu if Dolphin cannot remember file associations"
  fi
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

cleanup_legacy_zsh_autosuggestions_source() {
  [[ -f "$ZSHRC" ]] || return 0

  if grep -Fxq 'source ~/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh' "$ZSHRC"; then
    sed -i '\|^source ~/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh$|d' "$ZSHRC"
    success "Removed legacy zsh-autosuggestions source line from $ZSHRC"
  fi
}

ensure_login_shell_is_allowed() {
  local shell_path="$1"

  [[ -n "$shell_path" ]] || return 0
  [[ -f /etc/shells ]] || return 0

  if ! grep -Fxq "$shell_path" /etc/shells; then
    printf '%s\n' "$shell_path" | sudo tee -a /etc/shells >/dev/null
    success "Added $shell_path to /etc/shells"
  fi
}

configure_kitty_shell() {
  local kitty_conf="$DEST_CONFIG/kitty/kitty.conf"
  local zsh_path=""

  [[ -f "$kitty_conf" ]] || return 0
  zsh_path="$(command -v zsh 2>/dev/null || true)"
  [[ -n "$zsh_path" ]] || return 0

  if grep -Fxq "shell $zsh_path" "$kitty_conf"; then
    info "Kitty shell is already zsh"
    return 0
  fi

  if grep -Eq '^[#[:space:]]*shell[[:space:]]+' "$kitty_conf"; then
    sed -i "s|^[#[:space:]]*shell[[:space:]].*|shell $zsh_path|" "$kitty_conf"
  else
    printf '\nshell %s\n' "$zsh_path" >> "$kitty_conf"
  fi

  success "Configured Kitty to launch zsh"
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
  local tmp_file=""

  mkdir -p "$fontconfig_dir"

  tmp_file="$(mktemp)"
  cat > "$tmp_file" <<'EOF'
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

  install_generated_file_if_changed "$tmp_file" "$fontconfig_file" 644 "font fallback config"
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
  jq
  python
  zsh
  adw-gtk-theme
  gnome-themes-extra
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
  archlinux-xdg-menu
  kio
  kservice
  shared-mime-info
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

validate_source_dotfiles

log "Copying dotfiles into $DEST_CONFIG..."
sync_dotfiles
install_zshrc
normalize_user_config_paths
install_mimeapps_defaults
install_local_bin_files
install_local_applications
configure_kitty_shell

log "Installing font fallback preferences..."
install_font_fallback_config
install_gtk_defaults
install_kde_theme_files
install_kio_defaults
configure_kde_application_menu

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
configure_bluetooth_defaults
disable_system_service_if_enabled "sddm.service"
disable_system_service_if_enabled "lightdm.service"
enable_system_service "NetworkManager.service"
enable_system_service "bluetooth.service"
enable_system_service "gdm.service"
enable_system_service "touchegg.service"
enable_system_service "udisks2.service"
set_system_default_target "graphical.target"
install_hyprland_session_for_gdm
set_default_gdm_session "hyprland"

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
  section "Theme defaults"
  log "Applying dark GTK theme and cursor defaults..."
  gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' || true
  gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3-dark' || true
  gsettings set org.gnome.desktop.interface icon-theme 'Adwaita' || true
  gsettings set org.gnome.desktop.interface cursor-theme 'Bibata-Modern-Classic' || true
  gsettings set org.gnome.desktop.interface cursor-size 24 || true
fi

mkdir -p "$HOME/Pictures/Screenshots"
success "Ensured ~/Pictures/Screenshots exists"

section "Zsh setup"
log "Configuring Zsh..."
if have_cmd zsh && [[ "$SHELL" != "$(command -v zsh)" ]]; then
  ensure_login_shell_is_allowed "$(command -v zsh)"
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
  cleanup_legacy_zsh_autosuggestions_source
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
rebuild_kde_service_cache

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
elif preserve_existing_configs_enabled; then
  info "Preserved existing config files because PRESERVE_EXISTING_CONFIGS=1 was set."
else
  info "Update mode synced files whose content changed and skipped files already current."
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
