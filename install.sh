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
else
    DISTRO="unknown"
fi

msg "Detected distribution: $DISTRO"

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
    
    ubuntu|debian|pop)
        sudo apt update
        sudo apt install -y software-properties-common curl wget
        sudo apt install -y \
            gdm3 nautilus fastfetch \
            zsh zsh-autosuggestions zsh-syntax-highlighting \
            cava pipewire pipewire-pulse brightnessctl playerctl \
            wl-clipboard policykit-1-gnome
        
        warn "Some packages need manual installation on Ubuntu/Debian"
        warn "You might need to compile Hyprland from source or use flatpaks"
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
    
    for app in "hyprpaper" "waybar" "mako" "polkit-gnome-authentication-agent-1"; do
        if ! grep -q "exec-once.*$app" "$HYPR_CONF"; then
            echo "exec-once = $app &" >> "$HYPR_CONF"
        fi
    done
fi

# Enable display manager
if command -v systemctl &> /dev/null; then
    msg "Enabling display manager..."
    sudo systemctl enable gdm 2>/dev/null || true
    sudo systemctl set-default graphical.target 2>/dev/null || true
fi

# Create hyprland session file
HYPRLAND_SESSION="/usr/share/wayland-sessions/hyprland.desktop"
if [ ! -f "$HYPRLAND_SESSION" ]; then
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

# Make GDM default to Hyprland instead of GNOME
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

# Done!
msg "All done!"
echo
echo "Your dotfiles have been installed successfully."
echo "Backup of your old configs: $BACKUP_DIR"
echo
echo "Just reboot and Hyprland will start automatically."
echo "No need to select it from the login screen - it's now the default."
echo
echo "Basic keybinds:"
echo "  Super + Enter  = Terminal"
echo "  Super + D      = App launcher"
echo "  Super + Q      = Close window"
echo "  Super + M      = Exit Hyprland"
echo
echo "Check ~/.config/hypr/hyprland.conf for more keybinds."
echo "Enjoy your new setup!"
