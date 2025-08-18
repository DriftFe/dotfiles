#!/bin/bash
set -e

REPO_URL="https://github.com/DriftFe/dotfiles"
SCRIPT_NAME="Lavender Dotfiles Installer"

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
    [ -d "$TMP_DIR" ] && rm -rf "$TMP_DIR"
    exit $exit_code
}

# Set up error handling
trap 'cleanup_and_exit 1' ERR
trap 'cleanup_and_exit 0' INT TERM

# ─── Pre-flight Checks ─────────────────────────────
if ! command -v git &>/dev/null; then
    show_message "$SCRIPT_NAME" "Git is not installed. Please install git first." "error"
    exit 1
fi

if ! command -v rsync &>/dev/null; then
    show_message "$SCRIPT_NAME" "rsync is not installed. Please install rsync first." "error"
    exit 1
fi

# ─── Detect Distro ─────────────────────────────
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
        debian|ubuntu|pop|linuxmint|elementary|zorin|deepin)
            show_message "$SCRIPT_NAME" "This installer does NOT support Debian-based distros.\nPlease use Arch, Fedora, Gentoo, or NixOS instead." "error"
            exit 1
            ;;
        *)
            show_message "$SCRIPT_NAME" "Unsupported distribution: $ID\nSupported: Arch, Fedora, Gentoo, NixOS, openSUSE, Void" "warning"
            if ! ask_question "Continue anyway? (Package installation may fail)"; then
                exit 1
            fi
            DISTRO="$ID"
            ;;
    esac
else
    show_message "$SCRIPT_NAME" "Could not detect your Linux distribution." "error"
    exit 1
fi

echo "[*] Detected distribution: $DISTRO"

# ─── Confirm Install ─────────────────────────────
if ! ask_question "This will install Hyprland, Dependencies, and Lavender dotfiles. Continue?" "Install Lavender Dotfiles"; then
    show_message "$SCRIPT_NAME" "Installation cancelled."
    exit 0
fi

# ─── Backup Existing Configs ─────────────────────────────
BACKUP_NEEDED=false
BACKUP_CONFIGS=()

# Check for existing configs
for config in waybar kitty wofi hypr hyprpaper; do
    if [ -d "$HOME/.config/$config" ]; then
        BACKUP_NEEDED=true
        BACKUP_CONFIGS+=("$config")
    fi
done

if [ -f "$HOME/.zshrc" ]; then
    BACKUP_NEEDED=true
    BACKUP_CONFIGS+=(".zshrc")
fi

if $BACKUP_NEEDED; then
    BACKUP_DIR="$HOME/.config_backup_$(date +%Y%m%d_%H%M%S)"
    if ask_question "Existing configs detected: ${BACKUP_CONFIGS[*]}\nCreate backup in $BACKUP_DIR?"; then
        echo "[*] Creating backup..."
        mkdir -p "$BACKUP_DIR"
        for config in "${BACKUP_CONFIGS[@]}"; do
            if [ "$config" = ".zshrc" ]; then
                [ -f "$HOME/.zshrc" ] && cp "$HOME/.zshrc" "$BACKUP_DIR/"
            else
                [ -d "$HOME/.config/$config" ] && cp -r "$HOME/.config/$config" "$BACKUP_DIR/"
            fi
        done
        echo "[*] Backup created at: $BACKUP_DIR"
    fi
fi

# ─── Install Packages ─────────────────────────────
CORE_PACKAGES="hyprland kitty nautilus wofi gdm waybar hyprpaper hyprlock"
AUR_PACKAGES="cava cbonsai wofi-emoji starship touchegg oh-my-zsh-git zsh-theme-powerlevel10k-git grimblast swappy gpu-screen-recorder vesktop visual-studio-code-bin spotify zen-browser-bin goonsh"

echo "[*] Installing core packages..."

case "$DISTRO" in
    "arch")
        echo "[*] Updating system packages..."
        sudo pacman -Syu --noconfirm
        
        echo "[*] Installing core packages: $CORE_PACKAGES"
        sudo pacman -S --needed --noconfirm $CORE_PACKAGES
        
        # Install AUR packages
        if command -v yay &>/dev/null; then
            echo "[*] Installing AUR packages with yay..."
            yay -S --needed --noconfirm $AUR_PACKAGES || echo "[!] Some AUR packages failed to install"
        elif command -v paru &>/dev/null; then
            echo "[*] Installing AUR packages with paru..."
            paru -S --needed --noconfirm $AUR_PACKAGES || echo "[!] Some AUR packages failed to install"
        else
            echo "[!] No AUR helper found. Install yay or paru for additional packages."
        fi
        ;;
    "fedora")
        echo "[*] Installing packages with dnf..."
        sudo dnf install -y $CORE_PACKAGES || echo "[!] Some packages may not be available in Fedora repos"
        ;;
    "gentoo")
        echo "[*] Installing packages with emerge..."
        sudo emerge --ask --update --deep --newuse @world
        sudo emerge --ask gui-wm/hyprland x11-terms/kitty gui-apps/wofi gnome-base/gdm x11-misc/waybar || echo "[!] Some packages may not be available"
        ;;
    "nixos")
        show_message "$SCRIPT_NAME" "On NixOS, please add Hyprland and related packages to your configuration.nix\nThen run: sudo nixos-rebuild switch" "warning"
        ;;
    "opensuse")
        echo "[*] Installing packages with zypper..."
        sudo zypper install -y $CORE_PACKAGES || echo "[!] Some packages may not be available"
        ;;
    "void")
        echo "[*] Installing packages with xbps..."
        sudo xbps-install -Sy $CORE_PACKAGES || echo "[!] Some packages may not be available"
        ;;
    *)
        show_message "$SCRIPT_NAME" "Package installation not implemented for: $DISTRO\nPlease manually install: $CORE_PACKAGES" "warning"
        ;;
esac

# ─── Clone and Apply Dotfiles ─────────────────────────────
echo "[*] Downloading Lavender Dotfiles..."
TMP_DIR=$(mktemp -d)

if ! git clone --depth=1 "$REPO_URL" "$TMP_DIR"; then
    show_message "$SCRIPT_NAME" "Failed to clone repository. Check your internet connection." "error"
    cleanup_and_exit 1
fi

if [ ! -d "$TMP_DIR/dot_config" ]; then
    show_message "$SCRIPT_NAME" "Repository structure is unexpected. 'dot_config' directory not found." "error"
    cleanup_and_exit 1
fi

echo "[*] Applying Lavender Dotfiles..."
mkdir -p ~/.config

# Apply configs
if ! rsync -av "$TMP_DIR/dot_config/" ~/.config/; then
    show_message "$SCRIPT_NAME" "Failed to copy configuration files." "error"
    cleanup_and_exit 1
fi

# Make scripts executable
echo "[*] Setting executable permissions for scripts..."
find ~/.config -name "*.sh" -type f -exec chmod +x {} \; 2>/dev/null || true
find ~/.config -name "*.py" -type f -exec chmod +x {} \; 2>/dev/null || true

# Handle common script directories that should be executable
SCRIPT_DIRS=(
    "$HOME/.config/hypr/scripts"
    "$HOME/.config/waybar/scripts" 
    "$HOME/.config/wofi/scripts"
    "$HOME/.local/bin"
)

for dir in "${SCRIPT_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        echo "[*] Making scripts in $dir executable..."
        find "$dir" -type f \( -name "*.sh" -o -name "*.py" -o -name "*.pl" -o -name "*.rb" -o -executable \) -exec chmod +x {} \; 2>/dev/null || true
    fi
done

# Handle special files
if [ -f "$TMP_DIR/dot_config/.zshrc" ]; then
    cp "$TMP_DIR/dot_config/.zshrc" ~/.zshrc || echo "[!] Failed to copy .zshrc"
fi

if [ -d "$TMP_DIR/dot_config/.oh-my-zsh" ]; then
    echo "[*] Setting up oh-my-zsh..."
    mkdir -p ~/.oh-my-zsh
    rsync -av "$TMP_DIR/dot_config/.oh-my-zsh/" ~/.oh-my-zsh/ || echo "[!] Failed to copy oh-my-zsh"
    
    # Make oh-my-zsh scripts executable
    find ~/.oh-my-zsh -name "*.sh" -type f -exec chmod +x {} \; 2>/dev/null || true
fi

# Create ~/.local/bin if it doesn't exist and add to PATH
mkdir -p ~/.local/bin
if ! echo "$PATH" | grep -q "$HOME/.local/bin"; then
    echo "[*] Adding ~/.local/bin to PATH in shell config..."
    if [ -f ~/.zshrc ]; then
        grep -q 'export PATH="$HOME/.local/bin:$PATH"' ~/.zshrc || echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
    fi
    if [ -f ~/.bashrc ]; then
        grep -q 'export PATH="$HOME/.local/bin:$PATH"' ~/.bashrc || echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
    fi
fi

echo "[✓] Dotfiles applied successfully!"

# ─── Configure Dark Theme for GTK Applications ─────────────────────────────
echo "[*] Configuring dark theme for GTK applications..."

# Set GTK theme via gsettings
echo "[*] Setting GTK theme to dark via gsettings..."
gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita-dark' 2>/dev/null || true
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' 2>/dev/null || true
gsettings set org.gnome.desktop.interface icon-theme 'Adwaita' 2>/dev/null || true

# Create GTK-3 config
echo "[*] Creating GTK-3 configuration..."
mkdir -p ~/.config/gtk-3.0
cat > ~/.config/gtk-3.0/settings.ini << EOF
[Settings]
gtk-application-prefer-dark-theme=1
gtk-theme-name=Adwaita-dark
gtk-icon-theme-name=Adwaita
gtk-font-name=JetBrains Mono 11
gtk-cursor-theme-name=Bibata-Modern-Classic
gtk-cursor-theme-size=24
gtk-toolbar-style=GTK_TOOLBAR_BOTH_HORIZ
gtk-toolbar-icon-size=GTK_ICON_SIZE_LARGE_TOOLBAR
gtk-button-images=1
gtk-menu-images=1
gtk-enable-event-sounds=1
gtk-enable-input-feedback-sounds=0
gtk-xft-antialias=1
gtk-xft-hinting=1
gtk-xft-hintstyle=hintfull
gtk-xft-rgba=rgb
EOF

# Create GTK-4 config
echo "[*] Creating GTK-4 configuration..."
mkdir -p ~/.config/gtk-4.0
cat > ~/.config/gtk-4.0/settings.ini << EOF
[Settings]
gtk-application-prefer-dark-theme=1
gtk-theme-name=Adwaita-dark
gtk-icon-theme-name=Adwaita
gtk-font-name=JetBrains Mono 11
gtk-cursor-theme-name=Bibata-Modern-Classic
gtk-cursor-theme-size=24
EOF

# Create Nautilus dark theme wrapper
echo "[*] Creating Nautilus dark theme wrapper..."
cat > ~/.local/bin/nautilus-dark << 'EOF'
#!/bin/bash
# Nautilus Dark Theme Wrapper

# Set environment variables for this session
export GTK_THEME="Adwaita-dark"
export GTK2_RC_FILES="/usr/share/themes/Adwaita-dark/gtk-2.0/gtkrc"

# Launch Nautilus with dark theme
exec /usr/bin/nautilus "$@"
EOF

chmod +x ~/.local/bin/nautilus-dark

echo "[✓] Dark theme configuration applied!"

# ─── Enable GDM & Set Hyprland as Default ─────────────────────────────
if [ "$DISTRO" != "nixos" ]; then
    echo "[*] Configuring display manager..."
    
    # Enable GDM
    if systemctl list-unit-files | grep -q "gdm.service"; then
        sudo systemctl enable gdm || echo "[!] Failed to enable GDM"
    else
        echo "[!] GDM service not found. You may need to configure your display manager manually."
    fi
    
    # Ensure Hyprland session file exists
    HYPRLAND_SESSION="/usr/share/wayland-sessions/hyprland.desktop"
    if [ ! -f "$HYPRLAND_SESSION" ]; then
        echo "[*] Creating Hyprland session file..."
        sudo mkdir -p /usr/share/wayland-sessions
        sudo tee "$HYPRLAND_SESSION" >/dev/null <<EOF
[Desktop Entry]
Name=Hyprland
Comment=A dynamic tiling Wayland compositor
Exec=Hyprland
Type=Application
DesktopNames=Hyprland
EOF
    fi
    
    # Set Hyprland as default for current user
    echo "[*] Setting Hyprland as default session..."
    sudo mkdir -p /var/lib/AccountsService/users
    echo -e "[User]\nSession=hyprland\nXSession=\nSystemAccount=false" | sudo tee "/var/lib/AccountsService/users/$USER" >/dev/null
else
    echo "[*] On NixOS, configure your display manager in configuration.nix"
fi

# Clean up
cleanup_and_exit 0

# ─── Installation Complete ─────────────────────────────
show_message "$SCRIPT_NAME" "Installation completed successfully!"

if ask_question "Installation complete. Reboot now to start using Hyprland?" "Install Complete"; then
    echo "[*] Rebooting system..."
    sudo reboot
else
    echo "[*] Please reboot your system to start using Hyprland."
    echo "[*] After reboot, select 'Hyprland' from your login screen."
fi
