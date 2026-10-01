#!/usr/bin/env bash

# ============================================================================

set -Eeuo pipefail
IFS=$'\n\t'

# ----------------------------------------------------------------------------
# Paths
# ----------------------------------------------------------------------------

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$SCRIPT_DIR"

DOTCONFIG="$REPO_ROOT/dot_config"
HOME_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
LOCAL_BIN="$HOME/.local/bin"
LOCAL_SHARE="$HOME/.local/share"
ZSHRC="$HOME/.zshrc"

REPO_URL="https://github.com/DriftFe/dotfiles.git"

FORCE_CONFIG_OVERRIDES="${FORCE_CONFIG_OVERRIDES:-0}"
PRESERVE_EXISTING_CONFIGS="${PRESERVE_EXISTING_CONFIGS:-0}"
SKIP_AUR="${SKIP_AUR:-0}"
SKIP_ZSH="${SKIP_ZSH:-0}"
SKIP_SERVICES="${SKIP_SERVICES:-0}"

TMP_DIR=""

# ----------------------------------------------------------------------------
# Colors
# ----------------------------------------------------------------------------

RESET='\033[0m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
PINK='\033[1;95m'

# ----------------------------------------------------------------------------
# State
# ----------------------------------------------------------------------------

PACMAN_FAILED=()
AUR_FAILED=()

CPU_PACKAGES=()
GPU_PACKAGES=()

CPU_LABEL="Unknown"
GPU_LABEL="Unknown"

# ----------------------------------------------------------------------------
# Output
# ----------------------------------------------------------------------------

banner() {
    printf '%b\n' "$PINK"
    cat <<'EOF'
┌──────────────────────────────────────────────┐
│          DriftFe / Lavender Setup            │
│       Arch Linux + Hyprland workstation      │
└──────────────────────────────────────────────┘
EOF
    printf '%b\n' "$RESET"
}

section() {
    printf '\n%b==>%b %b%s%b\n' "$CYAN" "$RESET" "$PINK" "$*" "$RESET"
}

log() {
    printf '%b[+]%b %s\n' "$PURPLE" "$RESET" "$*"
}

info() {
    printf '%b[i]%b %s\n' "$CYAN" "$RESET" "$*"
}

success() {
    printf '%b[✓]%b %s\n' "$GREEN" "$RESET" "$*"
}

warn() {
    printf '%b[!]%b %s\n' "$YELLOW" "$RESET" "$*" >&2
}

die() {
    printf '%b[✗]%b %s\n' "$RED" "$RESET" "$*" >&2
    exit 1
}

# ----------------------------------------------------------------------------
# Cleanup
# ----------------------------------------------------------------------------

cleanup() {
    if [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]]; then
        rm -rf -- "$TMP_DIR"
    fi
}

trap cleanup EXIT

# ----------------------------------------------------------------------------
# Error reporting
# ----------------------------------------------------------------------------

on_error() {
    local exit_code=$?
    local line="${BASH_LINENO[0]:-unknown}"
    local command="${BASH_COMMAND:-unknown}"

    printf '\n%b[✗] Installer failed%b\n' "$RED" "$RESET" >&2
    printf '    line: %s\n' "$line" >&2
    printf '    command: %s\n' "$command" >&2
    printf '    exit code: %s\n' "$exit_code" >&2

    exit "$exit_code"
}

trap on_error ERR

# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------

have() {
    command -v "$1" >/dev/null 2>&1
}

require_command() {
    have "$1" || die "Required command not found: $1"
}

config_override_enabled() {
    [[ "$FORCE_CONFIG_OVERRIDES" == "1" ]]
}

preserve_existing_enabled() {
    [[ "$PRESERVE_EXISTING_CONFIGS" == "1" &&
       "$FORCE_CONFIG_OVERRIDES" != "1" ]]
}

# ----------------------------------------------------------------------------
# Root / OS checks
# ----------------------------------------------------------------------------

check_environment() {
    section "Environment checks"

    [[ "$EUID" -ne 0 ]] ||
        die "Do not run this installer as root. Run it as your normal user."

    have pacman ||
        die "This installer supports Arch Linux only."

    [[ -d /etc/pacman.d ]] ||
        die "This does not look like a normal Arch Linux installation."

    if [[ "${XDG_CURRENT_DESKTOP:-}" == "" ]]; then
        info "No desktop session detected. Continuing."
    fi

    if [[ ! -d "$DOTCONFIG" ]]; then
        warn "Repository dot_config directory was not found."

        require_command git

        TMP_DIR="$(mktemp -d)"

        log "Cloning the latest dotfiles repository..."

        git clone \
            --depth=1 \
            "$REPO_URL" \
            "$TMP_DIR/dotfiles"

        REPO_ROOT="$TMP_DIR/dotfiles"
        DOTCONFIG="$REPO_ROOT/dot_config"

        [[ -d "$DOTCONFIG" ]] ||
            die "Cloned repository does not contain dot_config/."
    fi

    success "Environment looks valid."
}

# ----------------------------------------------------------------------------
# Pacman
# ----------------------------------------------------------------------------

enable_multilib() {
    local pacman_conf="/etc/pacman.conf"

    if awk '
        /^\[multilib\]$/ { found=1 }
        END { exit(found ? 0 : 1) }
    ' "$pacman_conf"; then
        return 0
    fi

    warn "multilib is not enabled."
    info "Some 32-bit applications may therefore lack 32-bit libraries."

    read -r -p "Enable multilib now? [Y/n] " answer

    case "${answer:-Y}" in
        [Yy]|[Yy][Ee][Ss])
            local tmp
            tmp="$(mktemp)"

            awk '
                BEGIN { done=0 }

                /^[[:space:]]*#[[:space:]]*\[multilib\][[:space:]]*$/ {
                    print "[multilib]"
                    done=1
                    next
                }

                /^[[:space:]]*#[[:space:]]*Include[[:space:]]*=[[:space:]]*\/etc\/pacman.d\/mirrorlist[[:space:]]*$/ && done {
                    print "Include = /etc/pacman.d/mirrorlist"
                    next
                }

                { print }

                END {
                    if (!done) {
                        print ""
                        print "[multilib]"
                        print "Include = /etc/pacman.d/mirrorlist"
                    }
                }
            ' "$pacman_conf" > "$tmp"

            # pacman.conf is root-owned, so only this write is elevated.
            sudo install -m 644 "$tmp" "$pacman_conf"
            rm -f "$tmp"

            success "Enabled multilib."
            ;;
        *)
            info "Leaving multilib disabled."
            ;;
    esac
}

configure_pacman() {
    local pacman_conf="/etc/pacman.conf"
    local tmp

    tmp="$(mktemp)"

    awk '
        /^\[options\]$/ {
            in_options=1
            print
            next
        }

        /^\[/ && in_options {
            if (!color_seen) {
                print "Color"
            }

            if (!candy_seen) {
                print "ILoveCandy"
            }

            in_options=0
        }

        in_options && /^[[:space:]]*#[[:space:]]*Color[[:space:]]*$/ {
            print "Color"
            color_seen=1
            next
        }

        in_options && /^[[:space:]]*Color[[:space:]]*$/ {
            color_seen=1
        }

        in_options && /^[[:space:]]*ILoveCandy[[:space:]]*$/ {
            candy_seen=1
        }

        { print }

        END {
            if (in_options) {
                if (!color_seen) {
                    print "Color"
                }

                if (!candy_seen) {
                    print "ILoveCandy"
                }
            }
        }
    ' "$pacman_conf" > "$tmp"

    # pacman.conf is root-owned, so only this write is elevated.
    sudo install -m 644 "$tmp" "$pacman_conf"
    rm -f "$tmp"

    success "Configured pacman."
}

update_system() {
    section "System update"

    configure_pacman

    log "Synchronizing package databases and upgrading the system..."

    sudo pacman -Syu --noconfirm

    success "System is up to date."
}

# ----------------------------------------------------------------------------
# Hardware detection
# ----------------------------------------------------------------------------

detect_cpu() {
    section "Hardware detection"

    local cpu_vendor
    cpu_vendor="$(awk -F: '/^vendor_id/ {gsub(/ /, "", $2); print $2; exit}' /proc/cpuinfo)"

    case "$cpu_vendor" in
        GenuineIntel)
            CPU_LABEL="Intel"
            CPU_PACKAGES=(intel-ucode)
            ;;
        AuthenticAMD)
            CPU_LABEL="AMD"
            CPU_PACKAGES=(amd-ucode)
            ;;
        *)
            CPU_LABEL="Unknown"
            CPU_PACKAGES=()
            ;;
    esac

    success "CPU: $CPU_LABEL"

    if (( ${#CPU_PACKAGES[@]} )); then
        info "Microcode package: ${CPU_PACKAGES[*]}"
    fi
}

detect_gpu() {
    local gpu_info=""

    if have lspci; then
        gpu_info="$(lspci -nn 2>/dev/null | grep -Ei \
            'VGA compatible controller|3D controller|Display controller' || true)"
    fi

    if [[ -z "$gpu_info" ]]; then
        GPU_LABEL="Unknown"
        warn "Could not identify the GPU with lspci."
        return
    fi

    if grep -qi 'NVIDIA' <<< "$gpu_info"; then
        GPU_LABEL="NVIDIA"
        GPU_PACKAGES=(
            mesa
            vulkan-icd-loader
            vulkan-tools
            libva-utils
        )

    elif grep -qi 'AMD\|ATI' <<< "$gpu_info"; then
        GPU_LABEL="AMD"
        GPU_PACKAGES=(
            mesa
            vulkan-radeon
            vulkan-icd-loader
            vulkan-tools
            libva-utils
        )

    elif grep -qi 'Intel' <<< "$gpu_info"; then
        GPU_LABEL="Intel"
        GPU_PACKAGES=(
            mesa
            intel-media-driver
            vulkan-intel
            vulkan-icd-loader
            vulkan-tools
            libva-utils
        )

    else
        GPU_LABEL="Unknown"
        GPU_PACKAGES=(
            mesa
            vulkan-icd-loader
            vulkan-tools
        )
    fi

    success "GPU: $GPU_LABEL"

    while IFS= read -r line; do
        info "$line"
    done <<< "$gpu_info"
}

# ----------------------------------------------------------------------------
# Package lists
# ----------------------------------------------------------------------------

build_package_lists() {
    PACMAN_PACKAGES=(
        # Core tools
        git
        jq
        neovim
        python
        python-pip
        zsh
        rsync
        curl
        wget
        unzip
        base-devel

        # Desktop / Hyprland
        hyprland
        hyprlock
        waybar
        wofi
        mako
        libnotify

        # Terminal
        kitty

        # Wallpaper
        awww

        # Wayland utilities
        wl-clipboard
        cliphist
        brightnessctl
        grim
        slurp

        # File manager / media
        dolphin
        mpv
        imv

        # XDG / KDE integration
        archlinux-xdg-menu
        kio
        kservice
        shared-mime-info
        xdg-user-dirs

        # Networking
        networkmanager
        network-manager-applet

        # Audio
        pipewire
        pipewire-alsa
        pipewire-pulse
        wireplumber
        pavucontrol

        # Bluetooth
        bluez
        bluez-utils
        blueman

        # Login / GNOME integration
        gdm
        gnome-session
        gnome-shell
        gnome-desktop-4
        gsettings-desktop-schemas
        gsettings-system-schemas
        mutter

        # Desktop helpers
        gnome-keyring
        polkit-gnome
        udisks2
        playerctl
        xsettingsd
        qt5ct
        touchegg

        # Visualizer
        cava

        # Fonts
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
        ttf-jetbrains-mono-nerd
        ttf-meslo-nerd
        ttf-dejavu
        ttf-liberation
        ttf-nerd-fonts-symbols
        ttf-font-awesome
        gnu-free-fonts

        # Portals
        xdg-desktop-portal
        xdg-desktop-portal-hyprland

        # Development / CLI
        ripgrep
        fd

        # Screenshot editing
        swappy
    )

    AUR_PACKAGES=(
        wlogout
        waypaper
        youtubemusic
        vesktop-bin
        zen-browser-bin
        gpu-screen-recorder
        grimblast-git
        bibata-cursor-theme
        adw-gtk3
        cbonsai
    )
}

# ----------------------------------------------------------------------------
# Package installation
# ----------------------------------------------------------------------------

install_required_packages() {
    section "Installing official packages"

    local missing=()
    local pkg

    for pkg in "${PACMAN_PACKAGES[@]}"; do
        if ! pacman -Si "$pkg" >/dev/null 2>&1; then
            warn "Official repository package not found: $pkg"
            missing+=("$pkg")
        fi
    done

    if (( ${#missing[@]} )); then
        printf '\n'
        warn "The following packages are unavailable in your enabled repositories:"
        printf '  %s\n' "${missing[@]}"
        die "Package list contains unavailable official packages."
    fi

    sudo pacman -S --needed --noconfirm \
        "${PACMAN_PACKAGES[@]}" \
        "${CPU_PACKAGES[@]}" \
        "${GPU_PACKAGES[@]}"

    success "Official packages installed."
}

install_yay() {
    if have yay; then
        success "yay is already installed."
        return
    fi

    section "Installing yay"

    have git || die "git is required to build yay."
    have makepkg || die "makepkg is required to build yay."

    TMP_DIR="$(mktemp -d)"

    git clone \
        --depth=1 \
        https://aur.archlinux.org/yay.git \
        "$TMP_DIR/yay"

    (
        cd "$TMP_DIR/yay"
        makepkg -si --noconfirm
    )

    have yay ||
        die "yay installation failed."

    success "yay installed."
}

install_aur_packages() {
    (( SKIP_AUR == 0 )) ||
        return 0

    section "Installing AUR packages"

    install_yay

    local pkg

    for pkg in "${AUR_PACKAGES[@]}"; do
        info "Installing AUR package: $pkg"

        if yay -S \
            --needed \
            --noconfirm \
            --answerclean None \
            --answerdiff None \
            "$pkg"; then

            success "Installed $pkg"
        else
            warn "AUR package failed: $pkg"
            AUR_FAILED+=("$pkg")
        fi
    done
}

# ----------------------------------------------------------------------------
# Config validation
# ----------------------------------------------------------------------------

validate_source_configs() {
    section "Validating dotfiles"

    [[ -d "$DOTCONFIG" ]] ||
        die "Missing dot_config directory."

    if [[ -f "$DOTCONFIG/waybar/config" ]]; then
        if have python3; then
            python3 -m json.tool \
                "$DOTCONFIG/waybar/config" \
                >/dev/null ||
                die "Invalid Waybar JSON."
        fi
    fi

    if [[ -f "$DOTCONFIG/waybar/style.css" ]]; then
        grep -Eq \
            '(^|[[:space:]])window#waybar[[:space:]]*\{' \
            "$DOTCONFIG/waybar/style.css" ||
            warn "Waybar stylesheet does not contain the expected window#waybar selector."
    fi

    while IFS= read -r -d '' file; do
        bash -n "$file" ||
            die "Shell syntax error: $file"
    done < <(
        find "$DOTCONFIG" \
            -type f \
            -name '*.sh' \
            -print0
    )

    while IFS= read -r -d '' file; do
        if have python3; then
            python3 -m py_compile "$file" ||
                die "Python syntax error: $file"
        fi
    done < <(
        find "$DOTCONFIG" \
            -type f \
            -name '*.py' \
            -print0
    )

    if grep -R -nE \
        '^[[:space:]]*pseudotile[[:space:]]*=' \
        "$DOTCONFIG/hypr" \
        >/dev/null 2>&1; then

        die "Obsolete Hyprland pseudotile setting detected."
    fi

    success "Source configuration passed syntax checks."
}

# ----------------------------------------------------------------------------
# Safe configuration installation
# ----------------------------------------------------------------------------

copy_file() {
    local src="$1"
    local dst="$2"
    local mode="${3:-644}"
    local label="${4:-file}"

    [[ -f "$src" ]] || return 0

    mkdir -p "$(dirname "$dst")"

    if preserve_existing_enabled && [[ -e "$dst" ]]; then
        info "Preserving existing $label"
        return 0
    fi

    if [[ -f "$dst" ]] && cmp -s "$src" "$dst"; then
        info "$label already current"
        return 0
    fi

    install -m "$mode" "$src" "$dst"

    success "Installed $label"
}

sync_dotfiles() {
    section "Installing dotfiles"

    mkdir -p "$HOME_CONFIG"

    local args=(
        -a
        --checksum
        --mkpath
        --exclude '/.zshrc'
        --exclude '/local_bin/'
        --exclude '/local_share/'
        --exclude '/kde-color-schemes/'
    )

    if preserve_existing_enabled; then
        args+=(--ignore-existing)
    fi

    rsync \
        "${args[@]}" \
        "$DOTCONFIG/" \
        "$HOME_CONFIG/"

    success "Configuration synchronized."
}

install_special_files() {
    copy_file \
        "$DOTCONFIG/.zshrc" \
        "$ZSHRC" \
        644 \
        "Zsh configuration"

    copy_file \
        "$DOTCONFIG/mimeapps.list" \
        "$HOME_CONFIG/mimeapps.list" \
        644 \
        "MIME defaults"

    # Local binaries
    if [[ -d "$DOTCONFIG/local_bin" ]]; then
        mkdir -p "$LOCAL_BIN"

        local args=(
            -a
            --checksum
            --mkpath
        )

        if preserve_existing_enabled; then
            args+=(--ignore-existing)
        fi

        rsync \
            "${args[@]}" \
            "$DOTCONFIG/local_bin/" \
            "$LOCAL_BIN/"

        find "$LOCAL_BIN" \
            -maxdepth 1 \
            -type f \
            -exec chmod +x {} +

        success "Installed local helper scripts."
    fi

    # Local desktop files
    if [[ -d "$DOTCONFIG/local_share/applications" ]]; then
        mkdir -p "$LOCAL_SHARE/applications"

        local args=(
            -a
            --checksum
            --mkpath
        )

        if preserve_existing_enabled; then
            args+=(--ignore-existing)
        fi

        rsync \
            "${args[@]}" \
            "$DOTCONFIG/local_share/applications/" \
            "$LOCAL_SHARE/applications/"

        success "Installed local desktop entries."
    fi

    # KDE color schemes
    if [[ -d "$DOTCONFIG/kde-color-schemes" ]]; then
        mkdir -p "$LOCAL_SHARE/color-schemes"

        local args=(
            -a
            --checksum
            --mkpath
        )

        if preserve_existing_enabled; then
            args+=(--ignore-existing)
        fi

        rsync \
            "${args[@]}" \
            "$DOTCONFIG/kde-color-schemes/" \
            "$LOCAL_SHARE/color-schemes/"

        success "Installed KDE color schemes."
    fi
}

# ----------------------------------------------------------------------------
# User path normalization
# ----------------------------------------------------------------------------

normalize_paths() {
    section "Normalizing user paths"

    local dolphinrc="$HOME_CONFIG/dolphinrc"
    local bookmarks="$HOME_CONFIG/gtk-3.0/bookmarks"

    if [[ -f "$dolphinrc" ]]; then
        sed -i \
            -E \
            "s|^HomeUrl=file:///home/[^/[:space:]]*|HomeUrl=file://$HOME|" \
            "$dolphinrc" || true
    fi

    if [[ -f "$bookmarks" ]]; then
        sed -i \
            -E \
            "s|file:///home/[^/]*/|file://$HOME/|g" \
            "$bookmarks" || true
    fi
}

# ----------------------------------------------------------------------------
# Font configuration
# ----------------------------------------------------------------------------

install_font_config() {
    section "Configuring fonts"

    local dir="$HOME_CONFIG/fontconfig/conf.d"
    local file="$dir/75-driftfe-fallbacks.conf"

    mkdir -p "$dir"

    cat > "$file" <<'EOF'
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

    fc-cache -f >/dev/null 2>&1 || true

    success "Font fallback configuration installed."
}

# ----------------------------------------------------------------------------
# GTK defaults
# ----------------------------------------------------------------------------

install_gtk_defaults() {
    section "Configuring GTK"

    local gtk3="$HOME_CONFIG/gtk-3.0/settings.ini"
    local gtk4="$HOME_CONFIG/gtk-4.0/settings.ini"

    mkdir -p \
        "$(dirname "$gtk3")" \
        "$(dirname "$gtk4")"

    local tmp
    tmp="$(mktemp)"

    cat > "$tmp" <<'EOF'
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

    if config_override_enabled || [[ ! -f "$gtk3" ]]; then
        install -m 644 "$tmp" "$gtk3"
    fi

    if config_override_enabled || [[ ! -f "$gtk4" ]]; then
        install -m 644 "$tmp" "$gtk4"
    fi

    rm -f "$tmp"

    success "GTK defaults configured."
}

# ----------------------------------------------------------------------------
# KDE / Dolphin integration
# ----------------------------------------------------------------------------

configure_kde() {
    section "Configuring KDE integration"

    local kiorc="$HOME_CONFIG/kiorc"

    touch "$kiorc"

    if grep -q '^\[General\]' "$kiorc"; then
        if grep -q '^TerminalApplication=' "$kiorc"; then
            sed -i \
                's|^TerminalApplication=.*|TerminalApplication=kitty|' \
                "$kiorc"
        else
            sed -i \
                '/^\[General\]/a TerminalApplication=kitty' \
                "$kiorc"
        fi

        if grep -q '^TerminalService=' "$kiorc"; then
            sed -i \
                's|^TerminalService=.*|TerminalService=kitty.desktop|' \
                "$kiorc"
        else
            sed -i \
                '/^\[General\]/a TerminalService=kitty.desktop' \
                "$kiorc"
        fi
    else
        cat >> "$kiorc" <<'EOF'

[General]
TerminalApplication=kitty
TerminalService=kitty.desktop
EOF
    fi

    if have xdg-mime; then
        xdg-mime default org.kde.dolphin.desktop inode/directory || true
    fi

    if have update-mime-database; then
        sudo update-mime-database /usr/share/mime >/dev/null 2>&1 || true
    fi

    if have kbuildsycoca6; then
        kbuildsycoca6 --noincremental >/dev/null 2>&1 || true
    fi

    success "KDE/Dolphin integration configured."
}

# ----------------------------------------------------------------------------
# Bluetooth
# ----------------------------------------------------------------------------

configure_bluetooth() {
    section "Configuring Bluetooth"

    local conf="/etc/bluetooth/main.conf"

    [[ -f "$conf" ]] || {
        warn "Bluetooth configuration file not found."
        return
    }

    local tmp
    tmp="$(mktemp)"

    awk '
        BEGIN { changed=0 }

        /^[[:space:]]*#?[[:space:]]*AutoEnable[[:space:]]*=/ {
            print "AutoEnable=true"
            changed=1
            next
        }

        { print }

        END {
            if (!changed) {
                print ""
                print "[Policy]"
                print "AutoEnable=true"
            }
        }
    ' "$conf" > "$tmp"

    sudo install -m 644 "$tmp" "$conf"
    rm -f "$tmp"

    success "Bluetooth AutoEnable configured."
}

# ----------------------------------------------------------------------------
# Services
# ----------------------------------------------------------------------------

enable_system_service() {
    local unit="$1"

    if systemctl list-unit-files "$unit" >/dev/null 2>&1; then
        sudo systemctl unmask "$unit" >/dev/null 2>&1 || true
        sudo systemctl enable "$unit"
        success "Enabled $unit"
    else
        warn "System service not found: $unit"
    fi
}

disable_conflicting_display_managers() {
    local dm

    for dm in sddm lightdm; do
        if systemctl list-unit-files "${dm}.service" \
            >/dev/null 2>&1; then

            if systemctl is-enabled "${dm}.service" \
                >/dev/null 2>&1; then

                sudo systemctl disable "${dm}.service"
                success "Disabled ${dm}.service"
            fi
        fi
    done
}

configure_gdm() {
    section "Configuring GDM"

    disable_conflicting_display_managers
    enable_system_service NetworkManager.service
    enable_system_service bluetooth.service
    enable_system_service gdm.service

    if systemctl list-unit-files graphical.target \
        >/dev/null 2>&1; then

        sudo systemctl set-default graphical.target
    fi

    success "GDM configured."
}

configure_touchegg() {
    if systemctl list-unit-files touchegg.service \
        >/dev/null 2>&1; then

        sudo systemctl enable touchegg.service
        success "Touchégg enabled."
    else
        warn "touchegg.service not found."
    fi
}

configure_udisks() {
    if systemctl list-unit-files udisks2.service \
        >/dev/null 2>&1; then

        sudo systemctl enable udisks2.service
        success "udisks2 enabled."
    fi
}

install_polkit_agent_autostart() {
    local autostart_dir="$HOME_CONFIG/autostart"
    local desktop_file="/usr/share/applications/polkit-gnome-authentication-agent-1.desktop"

    [[ -f "$desktop_file" ]] || return 0

    mkdir -p "$autostart_dir"

    if [[ ! -f "$autostart_dir/polkit-gnome-authentication-agent-1.desktop" ||
          "$FORCE_CONFIG_OVERRIDES" == "1" ]]; then

        cp "$desktop_file" \
            "$autostart_dir/polkit-gnome-authentication-agent-1.desktop"
    fi

    success "Polkit authentication agent configured."
}

# ----------------------------------------------------------------------------
# Hyprland session
# ----------------------------------------------------------------------------

configure_hyprland_gdm_session() {
    section "Configuring Hyprland session"

    local session_dir="/usr/share/wayland-sessions"
    local session="$session_dir/hyprland.desktop"

    sudo mkdir -p "$session_dir"

    if [[ -f "$session" ]]; then
        success "Hyprland GDM session already exists."
        return
    fi

    local candidate

    for candidate in \
        /usr/share/hyprland/hyprland.desktop \
        /usr/share/wayland-sessions/hyprland.desktop
    do
        if [[ -f "$candidate" ]]; then
            sudo install -m 644 "$candidate" "$session"
            success "Installed Hyprland GDM session."
            return
        fi
    done

    warn "Could not locate a Hyprland session desktop file."
}

# ----------------------------------------------------------------------------
# PipeWire
# ----------------------------------------------------------------------------

configure_pipewire() {
    section "Configuring PipeWire"

    # PipeWire and WirePlumber are normally managed as user services.
    # Enable them so they are available immediately after login.
    systemctl --user daemon-reload >/dev/null 2>&1 || true

    for unit in \
        pipewire.service \
        pipewire-pulse.service \
        wireplumber.service
    do
        if systemctl --user list-unit-files "$unit" \
            >/dev/null 2>&1; then

            systemctl --user enable --now "$unit" || \
                warn "Could not enable $unit"
        fi
    done

    # Remove an old PulseAudio user service if one exists.
    systemctl --user disable \
        --now pulseaudio.service \
        pulseaudio.socket \
        >/dev/null 2>&1 || true

    systemctl --user mask \
        pulseaudio.service \
        pulseaudio.socket \
        >/dev/null 2>&1 || true

    success "PipeWire/WirePlumber configured."
}

# ----------------------------------------------------------------------------
# Portals
# ----------------------------------------------------------------------------

configure_portals() {
    section "Configuring desktop portals"

    systemctl --user daemon-reload >/dev/null 2>&1 || true

    for unit in \
        xdg-desktop-portal.service \
        xdg-desktop-portal-hyprland.service
    do
        if systemctl --user list-unit-files "$unit" \
            >/dev/null 2>&1; then

            # Portals may be socket/D-Bus activated. If enable is supported,
            # enable it, but do not make installation fail if activation is
            # handled automatically by the package.
            systemctl --user enable "$unit" \
                >/dev/null 2>&1 || true
        fi
    done

    success "Desktop portals configured."
}

# ----------------------------------------------------------------------------
# Zsh / Oh My Zsh / P10k
# ----------------------------------------------------------------------------

configure_zsh_theme() {
    [[ -f "$ZSHRC" ]] || return

    local desired='ZSH_THEME="powerlevel10k/powerlevel10k"'

    if grep -q '^ZSH_THEME=' "$ZSHRC"; then
        sed -i \
            's|^ZSH_THEME=.*|ZSH_THEME="powerlevel10k/powerlevel10k"|' \
            "$ZSHRC"
    else
        printf '\n%s\n' "$desired" >> "$ZSHRC"
    fi

    success "Powerlevel10k selected."
}

ensure_zsh_plugin() {
    local plugin="$1"
    local line
    local existing

    [[ -f "$ZSHRC" ]] || return

    if grep -q '^plugins=' "$ZSHRC"; then
        line="$(grep '^plugins=' "$ZSHRC" | head -n1)"
        existing="${line#plugins=}"
        existing="${existing#\(}"
        existing="${existing%\)}"

        if grep -qw "$plugin" <<< "$existing"; then
            return
        fi

        sed -i \
            "s|^plugins=.*|plugins=($existing $plugin)|" \
            "$ZSHRC"
    else
        printf 'plugins=(git %s)\n' "$plugin" >> "$ZSHRC"
    fi

    success "Enabled Zsh plugin: $plugin"
}

configure_zsh() {
    (( SKIP_ZSH == 0 )) ||
        return 0

    section "Configuring Zsh"

    have zsh || {
        warn "zsh is not installed; skipping Zsh setup."
        return
    }

    local zsh_path
    zsh_path="$(command -v zsh)"

    if [[ -f /etc/shells ]] &&
       ! grep -Fxq "$zsh_path" /etc/shells; then

        printf '%s\n' "$zsh_path" |
            sudo tee -a /etc/shells >/dev/null
    fi

    if [[ "$SHELL" != "$zsh_path" ]]; then
        chsh -s "$zsh_path" "$USER" ||
            warn "Could not change the login shell to zsh."
    fi

    if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
        log "Installing Oh My Zsh..."

        RUNZSH=no
        CHSH=no
        KEEP_ZSHRC=yes

        export RUNZSH CHSH KEEP_ZSHRC

        sh -c \
            "$(curl -fsSL \
            https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" \
            "" \
            --unattended
    fi

    local custom="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
    local p10k="$custom/themes/powerlevel10k"

    if [[ ! -d "$p10k" ]]; then
        log "Installing Powerlevel10k..."

        git clone \
            --depth=1 \
            https://github.com/romkatv/powerlevel10k.git \
            "$p10k"
    fi

    local autosuggestions="$custom/plugins/zsh-autosuggestions"

    if [[ ! -d "$autosuggestions" ]]; then
        log "Installing zsh-autosuggestions..."

        git clone \
            --depth=1 \
            https://github.com/zsh-users/zsh-autosuggestions \
            "$autosuggestions"
    fi

    configure_zsh_theme
    ensure_zsh_plugin zsh-autosuggestions

    # Remove the obsolete manual source line used by older versions
    # of this installer.
    if [[ -f "$ZSHRC" ]]; then
        sed -i \
            '\|^source ~/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh$|d' \
            "$ZSHRC"
    fi

    success "Zsh environment configured."
}

# ----------------------------------------------------------------------------
# Kitty
# ----------------------------------------------------------------------------

configure_kitty() {
    section "Configuring Kitty"

    local kitty="$HOME_CONFIG/kitty/kitty.conf"

    [[ -f "$kitty" ]] || return 0

    local zsh_path
    zsh_path="$(command -v zsh || true)"

    [[ -n "$zsh_path" ]] || return 0

    if grep -Eq '^[[:space:]]*shell[[:space:]]+' "$kitty"; then
        sed -i \
            "s|^[[:space:]]*shell[[:space:]].*|shell $zsh_path|" \
            "$kitty"
    else
        printf '\nshell %s\n' "$zsh_path" >> "$kitty"
    fi

    success "Kitty configured to launch Zsh."
}

# ----------------------------------------------------------------------------
# MIME defaults
# ----------------------------------------------------------------------------

configure_media_defaults() {
    section "Configuring media defaults"

    have xdg-mime || return 0

    if [[ -f /usr/share/applications/mpv.desktop ]]; then
        local mime

        while IFS= read -r mime; do
            [[ -n "$mime" ]] || continue
            xdg-mime default mpv.desktop "$mime" || true
        done < <(
            sed -n 's/^MimeType=//p' \
                /usr/share/applications/mpv.desktop |
            tr ';' '\n'
        )
    fi

    if [[ -f /usr/share/applications/imv.desktop ]]; then
        local mime

        while IFS= read -r mime; do
            [[ -n "$mime" ]] || continue
            xdg-mime default imv.desktop "$mime" || true
        done < <(
            sed -n 's/^MimeType=//p' \
                /usr/share/applications/imv.desktop |
            tr ';' '\n'
        )
    fi

    success "Media associations configured."
}

# ----------------------------------------------------------------------------
# GSettings
# ----------------------------------------------------------------------------

configure_gsettings() {
    section "Configuring GNOME settings"

    have gsettings || {
        warn "gsettings not available."
        return
    }

    gsettings set \
        org.gnome.desktop.interface \
        color-scheme \
        'prefer-dark' || true

    gsettings set \
        org.gnome.desktop.interface \
        gtk-theme \
        'adw-gtk3-dark' || true

    gsettings set \
        org.gnome.desktop.interface \
        icon-theme \
        'Adwaita' || true

    gsettings set \
        org.gnome.desktop.interface \
        cursor-theme \
        'Bibata-Modern-Classic' || true

    gsettings set \
        org.gnome.desktop.interface \
        cursor-size \
        24 || true

    success "GNOME settings applied."
}

# ----------------------------------------------------------------------------
# Executable permissions
# ----------------------------------------------------------------------------

fix_permissions() {
    section "Fixing script permissions"

    local dirs=(
        "$HOME_CONFIG/waybar/scripts"
        "$HOME_CONFIG/hypr/scripts"
        "$HOME_CONFIG/wofi/scripts"
        "$LOCAL_BIN"
    )

    local dir

    for dir in "${dirs[@]}"; do
        [[ -d "$dir" ]] || continue

        find "$dir" \
            -type f \
            \( -name '*.sh' -o -name '*.py' \) \
            -exec chmod +x {} +
    done

    chmod +x "$REPO_ROOT/install.sh" 2>/dev/null || true

    success "Executable permissions fixed."
}

# ----------------------------------------------------------------------------
# GSettings schemas
# ----------------------------------------------------------------------------

compile_schemas() {
    section "Rebuilding GSettings schemas"

    if have glib-compile-schemas &&
       [[ -d /usr/share/glib-2.0/schemas ]]; then

        sudo glib-compile-schemas \
            /usr/share/glib-2.0/schemas
    fi

    success "GSettings schemas rebuilt."
}

# ----------------------------------------------------------------------------
# Validation
# ----------------------------------------------------------------------------

validate_installation() {
    section "Final validation"

    local commands=(
        hyprland
        hyprlock
        waybar
        kitty
        zsh
        wofi
        mako
        wl-copy
        wl-paste
        cliphist
        brightnessctl
        grim
        slurp
        dolphin
        mpv
        imv
        bluetoothctl
        blueman-applet
        playerctl
        awww
        awww-daemon
    )

    local missing=()
    local cmd

    for cmd in "${commands[@]}"; do
        have "$cmd" || missing+=("$cmd")
    done

    if (( ${#missing[@]} )); then
        warn "Missing expected commands:"
        printf '  %s\n' "${missing[@]}"
    else
        success "Core commands are available."
    fi

    if [[ -f "$HOME_CONFIG/waybar/config" ]] &&
       have python3; then

        python3 -m json.tool \
            "$HOME_CONFIG/waybar/config" \
            >/dev/null ||
            warn "Installed Waybar config is not valid JSON."
    fi

    if have fc-match; then
        info "Monospace font:"
        fc-match monospace | head -n1 || true
    fi

    if systemctl --user is-active pipewire.service \
        >/dev/null 2>&1; then

        success "PipeWire is active."
    else
        warn "PipeWire is not currently active."
    fi

    if systemctl --user is-active wireplumber.service \
        >/dev/null 2>&1; then

        success "WirePlumber is active."
    else
        warn "WirePlumber is not currently active."
    fi

    if systemctl is-enabled gdm.service \
        >/dev/null 2>&1; then

        success "GDM is enabled."
    else
        warn "GDM is not enabled."
    fi

    if (( ${#AUR_FAILED[@]} )); then
        warn "AUR packages that failed:"
        printf '  %s\n' "${AUR_FAILED[@]}"
    fi
}

# ----------------------------------------------------------------------------
# Summary
# ----------------------------------------------------------------------------

print_summary() {
    section "Installation summary"

    printf '%bCPU%b: %s\n' "$CYAN" "$RESET" "$CPU_LABEL"
    printf '%bGPU%b: %s\n' "$CYAN" "$RESET" "$GPU_LABEL"
    printf '%bConfig%b: %s\n' "$CYAN" "$RESET" "$HOME_CONFIG"
    printf '%bShell%b: %s\n' "$CYAN" "$RESET" "${SHELL:-unknown}"

    if (( SKIP_AUR )); then
        info "AUR installation was skipped."
    fi

    if (( SKIP_ZSH )); then
        info "Zsh configuration was skipped."
    fi

    if (( SKIP_SERVICES )); then
        info "Service configuration was skipped."
    fi

    if config_override_enabled; then
        warn "FORCE_CONFIG_OVERRIDES=1 was used."
    elif preserve_existing_enabled; then
        info "Existing configuration files were preserved."
    else
        info "Existing files were updated only when repository content changed."
    fi

    echo
    success "DriftFe dotfiles installation finished."

    info "A reboot is recommended before judging the final desktop state."
}

# ----------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------

main() {
    banner

    check_environment

    require_command sudo
    require_command rsync
    require_command git

    sudo -v

    enable_multilib
    update_system

    detect_cpu
    detect_gpu

    build_package_lists
    install_required_packages

    validate_source_configs

    compile_schemas

    sync_dotfiles
    install_special_files
    normalize_paths

    install_font_config
    install_gtk_defaults
    configure_kde

    if (( SKIP_SERVICES == 0 )); then
        configure_bluetooth
        configure_gdm
        configure_hyprland_gdm_session
        configure_touchegg
        configure_udisks
        install_polkit_agent_autostart
        configure_pipewire
        configure_portals
    fi

    configure_kitty

    if (( SKIP_ZSH == 0 )); then
        configure_zsh
    fi

    configure_media_defaults
    configure_gsettings

    fix_permissions

    if (( SKIP_AUR == 0 )); then
        install_aur_packages
    fi

    validate_installation
    print_summary
}

main "$@"