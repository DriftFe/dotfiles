#!/usr/bin/env bash

set -euo pipefail

# Dotfiles installer script
DOTFILES_REPO="https://github.com/DriftFe/dotfiles"
TMP_DIR="$(mktemp -d)"
BACKUP_DIR="$HOME/.dotfiles_backup_$(date +%Y%m%d_%H%M%S)"

WAYPAPER_CFG="$HOME/.config/waypaper/config.json"
HYPAPER_CONF="$HOME/.config/hyprpaper/hyprpaper.conf"
HYPR_CONF="$HOME/.config/hypr/hyprland.conf"

msg() { echo -e "\e[32m[INFO]\e[0m $*"; }
warn() { echo -e "\e[33m[WARN]\e[0m $*"; }
err() { echo -e "\e[31m[ERROR]\e[0m $*" >&2; }

# Basic checks
msg "Checking for required tools..."
if ! command -v git &> /dev/null; then
    err "Git is not installed. Please install git first."
    exit 1
fi

if ! command -v rsync &> /dev/null; then
    err "Rsync is not installed. Please install rsync first."
    exit 1
fi

# Figure out what distro we're on
if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO=$ID
    VERSION_ID=${VERSION_ID:-""}
else
    DISTRO="unknown"
fi

msg "Detected distribution: $DISTRO ${VERSION_ID}"

# Helper function to check if package exists in repository
package_exists() {
    if command -v apt-cache &> /dev/null; then
        apt-cache search --names-only "^$1$" | grep -q "^$1 - " 2>/dev/null
    else
        return 1
    fi
}

# Helper function to add repositories safely
add_repo_if_not_exists() {
    local repo="$1"
    local keyring="$2"
    local key_url="$3"
    
    if ! grep -q "$repo" /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null; then
        msg "Adding repository: $repo"
        if [ -n "$key_url" ]; then
            curl -fsSL "$key_url" | sudo gpg --dearmor -o "$keyring"
        fi
        echo "$repo" | sudo tee /etc/apt/sources.list.d/$(basename "$keyring" .gpg).list
        return 0
    fi
    return 1
}

# Install packages based on distro
msg "Installing packages..."

case "$DISTRO" in
    arch|endeavouros|manjaro|cachyos)
        sudo pacman -Syu --needed --noconfirm \
            hyprland waybar wofi kitty \
            hyprpaper hyprlock hypridle \
            gdm nautilus fastfetch starship \
            zsh zsh-completions zsh-autosuggestions zsh-syntax-highlighting \
            cava mako \
            ttf-jetbrains-mono-nerd papirus-icon-theme bibata-cursor-theme \
            pipewire pipewire-pulse pipewire-alsa wireplumber \
            brightnessctl playerctl grim slurp wl-clipboard \
            polkit-gnome xdg-desktop-portal-hyprland

        # Install yay if it's not there
        if ! command -v yay &> /dev/null; then
            msg "Installing yay for AUR packages..."
            git clone https://aur.archlinux.org/yay.git /tmp/yay
            (cd /tmp/yay && makepkg -si --noconfirm)
            rm -rf /tmp/yay
        fi
        
        yay -S --needed --noconfirm waypaper hyprshot wlogout
        ;;
    
    fedora)
        # Enable RPM Fusion for extra packages
        sudo dnf install -y \
            https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
            https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
        
        sudo dnf copr enable -y solopasha/hyprland
        sudo dnf install -y \
            hyprland waybar wofi kitty hyprpaper hyprlock hypridle \
            gdm nautilus fastfetch starship \
            zsh zsh-autosuggestions zsh-syntax-highlighting \
            cava mako jetbrains-mono-fonts-all papirus-icon-theme \
            pipewire pipewire-pulseaudio wireplumber \
            brightnessctl playerctl grim slurp wl-clipboard \
            polkit-gnome xdg-desktop-portal-hyprland
        ;;
    
    void)
        sudo xbps-install -Sy \
            hyprland waybar wofi kitty hyprpaper hyprlock \
            gdm nautilus fastfetch starship \
            zsh zsh-completions zsh-autosuggestions zsh-syntax-highlighting \
            cava mako font-jetbrains-mono papirus-icon-theme \
            pipewire brightnessctl playerctl grim slurp wl-clipboard polkit-gnome
        ;;
    
    opensuse*|tumbleweed)
        sudo zypper install -y \
            hyprland waybar wofi kitty hyprpaper hyprlock \
            gdm nautilus fastfetch starship \
            zsh zsh-autosuggestions zsh-syntax-highlighting \
            cava mako jetbrains-mono-fonts papirus-icon-theme \
            pipewire pipewire-pulseaudio brightnessctl playerctl \
            grim slurp wl-clipboard polkit-gnome
        ;;
    
    nixos)
        warn "You're on NixOS - you'll need to add packages to your configuration.nix manually"
        warn "Check the script comments for the package list"
        ;;
    
    ubuntu|debian|pop|linuxmint|elementary|zorin|kali|parrot|deepin)
        msg "Setting up repositories for Debian-based system..."
        
        # Update package lists
        sudo apt update
        
        # Install basic dependencies
        sudo apt install -y software-properties-common apt-transport-https \
            ca-certificates curl wget gnupg lsb-release build-essential \
            git rsync
        
        # Detect Ubuntu/Debian version for proper repo setup
        CODENAME=$(lsb_release -cs 2>/dev/null || echo "")
        if [ -z "$CODENAME" ]; then
            # Fallback for systems without lsb_release
            CODENAME=$(grep VERSION_CODENAME /etc/os-release | cut -d'=' -f2 | tr -d '"' 2>/dev/null || echo "jammy")
        fi
        
        msg "System codename: $CODENAME"
        
        # Add repositories based on what's needed
        REPO_ADDED=false
        
        # For Hyprland - try multiple sources
        if ! package_exists hyprland; then
            msg "Adding Hyprland repository..."
            
            # Try the official Hyprland PPA first (Ubuntu/derivatives)
            if [[ "$DISTRO" == "ubuntu" || "$DISTRO" == "pop" || "$DISTRO" == "linuxmint" || "$DISTRO" == "elementary" || "$DISTRO" == "zorin" ]]; then
                if add_repo_if_not_exists \
                    "deb https://ppa.launchpadcontent.net/hyprland/hyprland/ubuntu $CODENAME main" \
                    "/usr/share/keyrings/hyprland-ppa.gpg" \
                    "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x9D6A9B4534A5D7D1A4B3BA7D2B1D3B5D0D7C1A2F"; then
                    REPO_ADDED=true
                fi
            fi
            
            # For Debian, try to build from source or use backports
            if [[ "$DISTRO" == "debian" ]]; then
                # Enable backports if available
                if ! grep -q "backports" /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null; then
                    echo "deb http://deb.debian.org/debian $CODENAME-backports main" | sudo tee /etc/apt/sources.list.d/backports.list
                    REPO_ADDED=true
                fi
            fi
        fi
        
        # Add Papirus PPA for better icon theme
        if ! package_exists papirus-icon-theme; then
            if add_repo_if_not_exists \
                "deb http://ppa.launchpad.net/papirus/papirus/ubuntu jammy main" \
                "/usr/share/keyrings/papirus-ppa.gpg" \
                "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x9461999446FAF0DF770BFC9AE58A9D36647CAE7F"; then
                REPO_ADDED=true
            fi
        fi
        
        # Update if we added repositories
        if [ "$REPO_ADDED" = true ]; then
            sudo apt update
        fi
        
        # Install available packages
        msg "Installing available packages..."
        
        # Core system packages that should be available everywhere
        sudo apt install -y \
            gdm3 nautilus file-manager \
            zsh zsh-autosuggestions zsh-syntax-highlighting zsh-common \
            pipewire pipewire-pulse pipewire-alsa wireplumber \
            policykit-1-gnome \
            fonts-jetbrains-mono \
            wl-clipboard \
            curl wget git rsync
        
        # Install packages that might be available
        PACKAGES_TO_TRY=(
            "hyprland"
            "waybar" 
            "wofi"
            "kitty"
            "hyprpaper"
            "hyprlock"
            "hypridle"
            "fastfetch"
            "neofetch"  # fallback for fastfetch
            "cava"
            "mako-notifier"
            "papirus-icon-theme"
            "brightnessctl"
            "playerctl"
            "grim"
            "slurp"
            "xdg-desktop-portal-wlr"
            "bibata-cursor-theme"
        )
        
        AVAILABLE_PACKAGES=()
        MISSING_PACKAGES=()
        
        for pkg in "${PACKAGES_TO_TRY[@]}"; do
            if package_exists "$pkg"; then
                AVAILABLE_PACKAGES+=("$pkg")
            else
                MISSING_PACKAGES+=("$pkg")
            fi
        done
        
        if [ ${#AVAILABLE_PACKAGES[@]} -gt 0 ]; then
            msg "Installing available packages: ${AVAILABLE_PACKAGES[*]}"
            sudo apt install -y "${AVAILABLE_PACKAGES[@]}" || warn "Some packages failed to install"
        fi
        
        if [ ${#MISSING_PACKAGES[@]} -gt 0 ]; then
            warn "The following packages are not available in repositories and need manual installation:"
            for pkg in "${MISSING_PACKAGES[@]}"; do
                warn "  - $pkg"
            done
        fi
        
        # Install packages from alternative sources
        msg "Installing packages from alternative sources..."
        
        # Install starship
        if ! command -v starship &> /dev/null; then
            msg "Installing starship prompt..."
            curl -sS https://starship.rs/install.sh | sh -s -- --yes
        fi
        
        # Install fastfetch if not available but neofetch is
        if ! command -v fastfetch &> /dev/null && ! package_exists fastfetch; then
            if command -v neofetch &> /dev/null; then
                msg "Fastfetch not available, neofetch will be used as fallback"
            else
                msg "Installing fastfetch from GitHub releases..."
                FASTFETCH_URL="https://github.com/fastfetch-cli/fastfetch/releases/latest/download/fastfetch-linux-amd64.deb"
                wget -O /tmp/fastfetch.deb "$FASTFETCH_URL" 2>/dev/null || warn "Failed to download fastfetch"
                if [ -f /tmp/fastfetch.deb ]; then
                    sudo dpkg -i /tmp/fastfetch.deb 2>/dev/null || sudo apt install -f -y
                    rm -f /tmp/fastfetch.deb
                fi
            fi
        fi
        
        # For missing Hyprland ecosystem packages, provide build instructions
        if ! command -v hyprland &> /dev/null; then
            warn "Hyprland not found in repositories. You have several options:"
            warn "1. Build from source: https://wiki.hyprland.org/Getting-Started/Installation/"
            warn "2. Use Flatpak: flatpak install flathub org.hyprland.Hyprland"
            warn "3. Use AppImage or other distribution methods"
        fi
        
        # Install flatpak packages as fallback for missing components
        if command -v flatpak &> /dev/null; then
            msg "Setting up Flatpak fallbacks for missing packages..."
            
            # Enable Flathub if not already enabled
            flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo 2>/dev/null || true
            
            # Install missing packages via Flatpak where available
            FLATPAK_PACKAGES=(
                "org.gnome.Nautilus"
                "com.github.zelikos.rannum"  # Alternative to some missing tools
            )
            
            for fpkg in "${FLATPAK_PACKAGES[@]}"; do
                if ! flatpak list | grep -q "$fpkg"; then
                    flatpak install -y flathub "$fpkg" 2>/dev/null || true
                fi
            done
        fi
        
        # Install additional cursor themes
        if ! package_exists bibata-cursor-theme; then
            msg "Installing Bibata cursor theme manually..."
            CURSOR_DIR="$HOME/.local/share/icons"
            mkdir -p "$CURSOR_DIR"
            BIBATA_URL="https://github.com/ful1e5/Bibata_Cursor/releases/latest/download/Bibata-Modern-Classic.tar.gz"
            wget -O /tmp/bibata.tar.gz "$BIBATA_URL" 2>/dev/null || warn "Failed to download Bibata cursor theme"
            if [ -f /tmp/bibata.tar.gz ]; then
                tar -xzf /tmp/bibata.tar.gz -C "$CURSOR_DIR/" 2>/dev/null || warn "Failed to extract cursor theme"
                rm -f /tmp/bibata.tar.gz
            fi
        fi
        
        msg "Package installation complete for Debian-based system"
        ;;
    
    *)
        warn "Unknown distribution. You'll need to install packages manually."
        warn "Check the script to see what packages are needed."
        ;;
esac

# Install starship if package manager didn't have it
if ! command -v starship &> /dev/null; then
    msg "Installing starship shell prompt..."
    curl -sS https://starship.rs/install.sh | sh -s -- --yes
fi

# Change shell to zsh if it's not already
if [ "$SHELL" != "$(which zsh)" ]; then
    msg "Changing default shell to zsh..."
    chsh -s "$(which zsh)" || warn "Couldn't change shell automatically"
fi

# Back up existing configs
msg "Backing up your current configs..."
mkdir -p "$BACKUP_DIR"

for item in .zshrc .config/hypr .config/waybar .config/kitty .config/wofi \
           .config/cava .config/fastfetch .config/mako .config/hyprpaper \
           .config/waypaper .config/yay .config/gtk-3.0 .config/gtk-4.0 \
           .config/vesktop .config/starship.toml; do
    if [ -e "$HOME/$item" ]; then
        rsync -a "$HOME/$item" "$BACKUP_DIR/"
        rm -rf "$HOME/$item"
    fi
done

# Download the dotfiles
msg "Downloading dotfiles..."
git clone --depth=1 "$DOTFILES_REPO" "$TMP_DIR"

# Copy everything over
msg "Installing configs..."

if [ -d "$TMP_DIR/dot_config" ]; then
    rsync -av "$TMP_DIR/dot_config/" "$HOME/.config/"
fi

[ -f "$TMP_DIR/.zshrc" ] && cp "$TMP_DIR/.zshrc" "$HOME/"

# Check for starship config in different locations
for starship_path in "$TMP_DIR/starship.toml" "$TMP_DIR/dot_config/starship.toml"; do
    if [ -f "$starship_path" ]; then
        cp "$starship_path" "$HOME/.config/"
        break
    fi
done

# Make scripts executable
find "$HOME/.config" -name "*.sh" -type f -exec chmod +x {} \; 2>/dev/null || true
chmod -R +x "$HOME/.config/hypr/scripts" 2>/dev/null || true

# Handle wallpapers
for wallpaper_dir in "$TMP_DIR/dot_config/wallpapers" "$TMP_DIR/wallpapers"; do
    if [ -d "$wallpaper_dir" ]; then
        msg "Setting up wallpapers..."
        mkdir -p "$HOME/.wallpapers"
        rsync -av "$wallpaper_dir/" "$HOME/.wallpapers/"
        break
    fi
done

[ ! -d "$HOME/.wallpapers" ] && mkdir -p "$HOME/.wallpapers"

# Set up GTK theming
msg "Configuring GTK theme..."
mkdir -p ~/.config/gtk-3.0 ~/.config/gtk-4.0

cat > ~/.config/gtk-3.0/settings.ini <<EOF
[Settings]
gtk-application-prefer-dark-theme=1
gtk-theme-name=Adwaita-dark
gtk-icon-theme-name=Papirus-Dark
gtk-font-name=JetBrainsMono Nerd Font 11
gtk-cursor-theme-name=Bibata-Modern-Classic
gtk-cursor-size=24
EOF

cp ~/.config/gtk-3.0/settings.ini ~/.config/gtk-4.0/

# Apply dark theme through gsettings
msg "Setting dark theme preferences..."
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' 2>/dev/null || true
gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita-dark' 2>/dev/null || true
gsettings set org.gnome.desktop.interface icon-theme 'Papirus-Dark' 2>/dev/null || true
gsettings set org.gnome.desktop.interface cursor-theme 'Bibata-Modern-Classic' 2>/dev/null || true

fc-cache -f 2>/dev/null || true

# Configure hyprpaper wallpaper
msg "Setting up wallpaper daemon..."

WALLPAPER=""
if [ -f "$WAYPAPER_CFG" ]; then
    WALLPAPER=$(grep -oP '"wallpaper":\s*"\K[^"]+' "$WAYPAPER_CFG" | head -n1 2>/dev/null || true)
fi

if [ -z "$WALLPAPER" ] && [ -d "$HOME/.wallpapers" ]; then
    WALLPAPER=$(find "$HOME/.wallpapers" -type f \( -name "*.jpg" -o -name "*.jpeg" -o -name "*.png" -o -name "*.webp" \) | head -n1 2>/dev/null || true)
fi

mkdir -p "$(dirname "$HYPAPER_CONF")"
if [ -n "$WALLPAPER" ] && [ -f "$WALLPAPER" ]; then
    msg "Using wallpaper: $(basename "$WALLPAPER")"
    cat > "$HYPAPER_CONF" <<EOF
preload = $WALLPAPER
wallpaper = ,$WALLPAPER
splash = true
ipc = on
EOF
else
    warn "No wallpaper found, creating template config"
    cat > "$HYPAPER_CONF" <<EOF
# Set your wallpaper path here
# preload = /path/to/wallpaper.jpg
# wallpaper = ,/path/to/wallpaper.jpg
splash = true
ipc = on
EOF
fi

# Add autostart entries to hyprland config
if [ -f "$HYPR_CONF" ]; then
    msg "Setting up autostart applications..."
    
    # Determine the correct notification daemon
    NOTIFY_DAEMON="mako"
    if command -v mako &> /dev/null; then
        NOTIFY_DAEMON="mako"
    elif command -v dunst &> /dev/null; then
        NOTIFY_DAEMON="dunst"
    fi
    
    # Determine the correct polkit agent
    POLKIT_AGENT="polkit-gnome-authentication-agent-1"
    if command -v /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 &> /dev/null; then
        POLKIT_AGENT="/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1"
    elif command -v /usr/libexec/polkit-gnome-authentication-agent-1 &> /dev/null; then
        POLKIT_AGENT="/usr/libexec/polkit-gnome-authentication-agent-1"
    fi
    
    for app in "hyprpaper" "waybar" "$NOTIFY_DAEMON" "$POLKIT_AGENT"; do
        if command -v "$(echo "$app" | cut -d' ' -f1)" &> /dev/null; then
            if ! grep -q "exec-once.*$app" "$HYPR_CONF"; then
                echo "exec-once = $app &" >> "$HYPR_CONF"
            fi
        fi
    done
fi

# Enable display manager
if command -v systemctl &> /dev/null; then
    msg "Enabling display manager..."
    
    # Try different display managers based on what's available
    if systemctl list-unit-files | grep -q gdm3; then
        sudo systemctl enable gdm3 2>/dev/null || true
    elif systemctl list-unit-files | grep -q gdm; then
        sudo systemctl enable gdm 2>/dev/null || true
    elif systemctl list-unit-files | grep -q lightdm; then
        sudo systemctl enable lightdm 2>/dev/null || true
        warn "Using LightDM - you may need to configure it for Wayland sessions"
    fi
    
    sudo systemctl set-default graphical.target 2>/dev/null || true
fi

# Create hyprland session file
HYPRLAND_SESSION="/usr/share/wayland-sessions/hyprland.desktop"
if command -v hyprland &> /dev/null && [ ! -f "$HYPRLAND_SESSION" ]; then
    msg "Creating Hyprland session file..."
    sudo mkdir -p "$(dirname "$HYPRLAND_SESSION")"
    sudo tee "$HYPRLAND_SESSION" >/dev/null <<EOF
[Desktop Entry]
Name=Hyprland
Comment=An independent, highly customizable, dynamic tiling Wayland compositor
Exec=Hyprland
Type=Application
DesktopNames=Hyprland
EOF
fi

# Make GDM default to Hyprland instead of GNOME (only if Hyprland is installed)
if command -v hyprland &> /dev/null; then
    msg "Setting Hyprland as default session..."

    CURRENT_USER="${USER:-$(whoami)}"
    ACCOUNTS_SERVICE_DIR="/var/lib/AccountsService/users"

    if [ -d "$ACCOUNTS_SERVICE_DIR" ]; then
        USER_ACCOUNT_FILE="$ACCOUNTS_SERVICE_DIR/$CURRENT_USER"
        
        if [ -f "$USER_ACCOUNT_FILE" ]; then
            sudo sed -i '/^Session=/d' "$USER_ACCOUNT_FILE" 2>/dev/null || true
            sudo sed -i '/^XSession=/d' "$USER_ACCOUNT_FILE" 2>/dev/null || true
            echo "Session=hyprland" | sudo tee -a "$USER_ACCOUNT_FILE" >/dev/null
        else
            sudo tee "$USER_ACCOUNT_FILE" >/dev/null <<EOF
[User]
Session=hyprland
XSession=
SystemAccount=false
EOF
        fi
    fi

    # Also set it in GDM config
    for conf_file in /etc/gdm/custom.conf /etc/gdm3/custom.conf; do
        if [ -f "$conf_file" ]; then
            msg "Updating GDM config..."
            sudo cp "$conf_file" "${conf_file}.backup.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
            
            if ! sudo grep -q "^\[daemon\]" "$conf_file"; then
                echo -e "\n[daemon]" | sudo tee -a "$conf_file" >/dev/null
            fi
            
            sudo sed -i '/^DefaultSession=/d' "$conf_file" 2>/dev/null || true
            sudo sed -i '/^\[daemon\]/a DefaultSession=hyprland.desktop' "$conf_file"
            break
        fi
    done

    # Create .dmrc for older display managers
    cat > "$HOME/.dmrc" <<EOF
[Desktop]
Session=hyprland
EOF
    chmod 644 "$HOME/.dmrc"
else
    warn "Hyprland not installed - skipping session configuration"
fi

# Enable audio services
if command -v systemctl &> /dev/null; then
    msg "Setting up audio..."
    systemctl --user enable pipewire pipewire-pulse wireplumber 2>/dev/null || true
    systemctl --user start pipewire pipewire-pulse wireplumber 2>/dev/null || true
fi

# Install oh-my-zsh if not present
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    msg "Installing Oh My Zsh..."
    RUNZSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" 2>/dev/null || true
fi

# Set up some useful zsh plugins
ZSH_PLUGINS_DIR="$HOME/.oh-my-zsh/custom/plugins"
mkdir -p "$ZSH_PLUGINS_DIR"

if [ ! -d "$ZSH_PLUGINS_DIR/fast-syntax-highlighting" ]; then
    git clone https://github.com/zdharma-continuum/fast-syntax-highlighting "$ZSH_PLUGINS_DIR/fast-syntax-highlighting" 2>/dev/null || true
fi

if [ ! -d "$ZSH_PLUGINS_DIR/zsh-autosuggestions" ] && [ ! -f "/usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh" ]; then
    git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_PLUGINS_DIR/zsh-autosuggestions" 2>/dev/null || true
fi

# Fix permissions
msg "Setting proper permissions..."
find "$HOME/.config" -type d -exec chmod 755 {} \; 2>/dev/null || true
find "$HOME/.config" -type f -exec chmod 644 {} \; 2>/dev/null || true
find "$HOME/.config" -name "*.sh" -type f -exec chmod 755 {} \; 2>/dev/null || true
[ -d "$HOME/.wallpapers" ] && chmod -R 755 "$HOME/.wallpapers" 2>/dev/null || true

# Clean up
rm -rf "$TMP_DIR"

# Final summary
msg "Installation complete!"
echo
echo "Your dotfiles have been installed successfully."
echo "Backup of your old configs: $BACKUP_DIR"
echo

if command -v hyprland &> /dev/null; then
    echo "Hyprland is installed and configured as the default session."
    echo "Just reboot and Hyprland will start automatically."
    echo
    echo "Basic keybinds:"
    echo "  Super + Enter  = Terminal"
    echo "  Super + D      = App launcher"
    echo "  Super + Q      = Close window"
    echo "  Super + M      = Exit Hyprland"
else
    warn "Hyprland was not installed. You may need to:"
    warn "1. Install it manually from source or other methods"
    warn "2. Check the installation notes above for your distribution"
    warn "3. Restart the script after installing Hyprland"
fi

echo
echo "Check ~/.config/hypr/hyprland.conf for more keybinds."
echo "Enjoy your new setup!"
