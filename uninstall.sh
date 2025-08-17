#!/bin/bash
set -e

REPO_URL="https://github.com/DriftFe/dotfiles"
SCRIPT_NAME="Lavender Dotfiles Uninstaller"

# ─── Zenity Environment Check ─────────────────────────────
USE_GUI=false
if command -v zenity &>/dev/null && { [ -n "$DISPLAY" ] || [ -n "$WAYLAND_DISPLAY" ]; }; then
    USE_GUI=true
else
    echo "[*] No GUI detected or Zenity not installed. Falling back to terminal mode."
fi

# ─── Helper Functions ─────────────────────────────
show_message() {
    local title="$1"
    local message="$2"
    local type="${3:-info}"  # info, error, warning
    
    if $USE_GUI; then
        case "$type" in
            "error")
                zenity --error --title="$title" --text="$message"
                ;;
            "warning")
                zenity --warning --title="$title" --text="$message"
                ;;
            *)
                zenity --info --title="$title" --text="$message"
                ;;
        esac
    else
        echo "[$type] $message"
    fi
}

ask_question() {
    local message="$1"
    local title="${2:-$SCRIPT_NAME}"
    
    if $USE_GUI; then
        zenity --question --title="$title" --text="$message"
        return $?
    else
        echo "[?] $message"
        read -p "Proceed? (y/n): " confirm
        [[ "$confirm" =~ ^[Yy]$ ]] && return 0 || return 1
    fi
}

# ─── Error Handler ─────────────────────────────
cleanup_and_exit() {
    local exit_code=$1
    [ -d "$TMP_RESTORE" ] && rm -rf "$TMP_RESTORE"
    exit $exit_code
}

# Set up error handling
trap 'cleanup_and_exit 1' ERR
trap 'cleanup_and_exit 0' INT TERM

# ─── Normalize DISTRO ─────────────────────────────
if [ -f /etc/os-release ]; then
    . /etc/os-release
    case "$ID" in
        arch|manjaro|endeavouros|artix|cachyos)
            DISTRO="arch"
            ;;
        fedora|rhel|centos|rocky|almalinux)
            DISTRO="fedora"
            ;;
        gentoo|funtoo)
            DISTRO="gentoo"
            ;;
        nixos)
            DISTRO="nixos"
            ;;
        opensuse*|sles)
            DISTRO="opensuse"
            ;;
        void)
            DISTRO="void"
            ;;
        *)
            DISTRO="$ID"
            ;;
    esac
else
    DISTRO="unknown"
fi

echo "[*] Detected distribution: $DISTRO"

# ─── Confirm Uninstall ─────────────────────
if ! ask_question "This will remove all configs and dotfiles except Hyprland itself. Continue?" "Uninstall Lavender Dotfiles"; then
    show_message "$SCRIPT_NAME" "Uninstallation cancelled."
    exit 0
fi

# ─── Stop and disable SDDM ─────────────
echo "[*] Disabling SDDM..."
if systemctl is-active --quiet sddm 2>/dev/null; then
    sudo systemctl stop sddm || echo "[!] Failed to stop SDDM"
fi
if systemctl is-enabled --quiet sddm 2>/dev/null; then
    sudo systemctl disable sddm || echo "[!] Failed to disable SDDM"
fi

# ─── Remove Dotfiles ───────────────────
echo "[*] Removing Lavender Dotfiles and configs..."
rm -rf ~/.config/{waybar,kitty,wofi,sddm,vesktop,hypr,hyprpaper,cava,zsh,fastfetch} \
       ~/.wallpapers ~/.oh-my-zsh ~/.zshrc ~/.config/starship.toml 2>/dev/null || true

# Create backup list of what was removed
REMOVED_CONFIGS="waybar, kitty, wofi, sddm, vesktop, hypr, hyprpaper, cava, zsh, fastfetch, wallpapers, oh-my-zsh, zshrc, starship.toml"
echo "[*] Removed configs: $REMOVED_CONFIGS"

# ─── Remove AUR/optional packages ──────
echo "[*] Removing optional packages..."
AUR_PACKAGES="cava cbonsai wofi-emoji starship touchegg oh-my-zsh-git zsh-theme-powerlevel10k-git grimblast swappy gpu-screen-recorder vesktop visual-studio-code-bin spotify zen-browser-bin goonsh"

if [ "$DISTRO" = "arch" ] && command -v yay &>/dev/null; then
    echo "[*] Removing AUR packages with yay..."
    yay -Rns --noconfirm $AUR_PACKAGES 2>/dev/null || echo "[!] Some AUR packages may not have been installed or failed to remove"
elif [ "$DISTRO" = "arch" ] && command -v paru &>/dev/null; then
    echo "[*] Removing AUR packages with paru..."
    paru -Rns --noconfirm $AUR_PACKAGES 2>/dev/null || echo "[!] Some AUR packages may not have been installed or failed to remove"
fi

# ─── Remove from official repos ────────
OFFICIAL_PACKAGES="kitty nautilus wofi sddm waybar hyprpaper hyprlock"
echo "[*] Removing official repository packages..."

case "$DISTRO" in
    "arch")
        sudo pacman -Rns --noconfirm $OFFICIAL_PACKAGES 2>/dev/null || echo "[!] Some packages may not have been installed or failed to remove"
        ;;
    "fedora")
        sudo dnf remove -y $OFFICIAL_PACKAGES 2>/dev/null || echo "[!] Some packages may not have been installed or failed to remove"
        ;;
    "gentoo")
        echo "[*] Removing Gentoo packages..."
        sudo emerge --ask --depclean x11-terms/kitty gui-apps/wofi gui-apps/sddm x11-misc/waybar 2>/dev/null || echo "[!] Some packages may not have been installed or failed to remove"
        ;;
    "nixos")
        show_message "$SCRIPT_NAME" "On NixOS, please remove Hyprland and related configs via your configuration.nix" "warning"
        ;;
esac

# ─── Offer to Restore from GitHub ─────────────
if ask_question "Would you like to restore the latest dotfiles from GitHub?" "Restore Lavender Dotfiles"; then
    echo "[*] Cloning latest Lavender Dotfiles..."
    
    # Pre-flight check
    if ! command -v git &>/dev/null; then
        show_message "$SCRIPT_NAME" "Git is not installed. Cannot restore dotfiles." "error"
    else
        TMP_RESTORE=$(mktemp -d)
        
        if git clone --depth=1 "$REPO_URL" "$TMP_RESTORE" 2>/dev/null; then
            echo "[*] Restoring dotfiles..."
            mkdir -p ~/.config
            
            # Restore configs
            if [ -d "$TMP_RESTORE/dot_config" ]; then
                rsync -av "$TMP_RESTORE/dot_config/" ~/.config/ 2>/dev/null || echo "[!] Failed to restore some configs"
                
                # Handle special files
                [ -f "$TMP_RESTORE/dot_config/.zshrc" ] && cp "$TMP_RESTORE/dot_config/.zshrc" ~/.zshrc 2>/dev/null
                
                if [ -d "$TMP_RESTORE/dot_config/.oh-my-zsh" ]; then
                    mkdir -p ~/.oh-my-zsh
                    rsync -av "$TMP_RESTORE/dot_config/.oh-my-zsh/" ~/.oh-my-zsh/ 2>/dev/null || echo "[!] Failed to restore oh-my-zsh"
                fi
                
                echo "[✓] Lavender Dotfiles restored successfully."
            else
                show_message "$SCRIPT_NAME" "Repository structure unexpected. Could not find dot_config directory." "error"
            fi
        else
            show_message "$SCRIPT_NAME" "Failed to clone repository. Check your internet connection." "error"
        fi
        
        # Clean up
        [ -d "$TMP_RESTORE" ] && rm -rf "$TMP_RESTORE"
    fi
fi

# ─── Cleanup Complete ─────────────────
show_message "$SCRIPT_NAME" "Uninstallation complete!"

if ask_question "Reboot now to complete the process?" "Uninstall Complete"; then
    echo "[*] Rebooting system..."
    sudo reboot
else
    echo "[*] Please reboot your system to complete the uninstallation."
fi
