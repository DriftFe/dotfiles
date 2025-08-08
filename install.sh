#!/bin/bash
set -e

REPO_URL="https://github.com/DriftFe/dotfiles"

# ─── Zenity Environment Check ─────────────────────────────
USE_GUI=false

if command -v zenity &>/dev/null && { [ "$DISPLAY" ] || [ "$WAYLAND_DISPLAY" ]; }; then
  USE_GUI=true
else
  echo "[*] No GUI detected or Zenity not installed. Falling back to terminal mode."
fi

# ─── Normalize DISTRO ─────────────────────────────
if [ -f /etc/os-release ]; then
  . /etc/os-release
  if [[ "$ID_LIKE" =~ arch ]]; then
    DISTRO="arch"
  elif [[ "$ID_LIKE" =~ fedora|rhel|centos ]]; then
    DISTRO="fedora"
  elif [[ "$ID_LIKE" =~ gentoo ]]; then
    DISTRO="gentoo"
  elif [[ "$ID_LIKE" =~ nixos ]]; then
    DISTRO="nixos"
  else
    case "$ID" in
      arch|manjaro|endeavouros|arco|garuda)
        DISTRO="arch";;
      fedora|rhel|centos|rocky|almalinux)
        DISTRO="fedora";;
      gentoo)
        DISTRO="gentoo";;
      nixos)
        DISTRO="nixos";;
      *)
        DISTRO="unknown";;
    esac
  fi
else
  DISTRO="unknown"
fi

# ─── Confirm Install ─────────────────────
if $USE_GUI; then
  zenity --question --title="Install Dotfiles" \
    --text="This will install all configs and packages for $DISTRO. Continue?"
  [ $? -ne 0 ] && zenity --info --text="Installation cancelled." && exit 0
else
  echo "[*] This will install dotfiles and packages for $DISTRO."
  read -p "Continue? (y/n): " confirm
  [[ "$confirm" != "y" && "$confirm" != "Y" ]] && echo "Cancelled." && exit 0
fi

# ─── Package Installation ─────────────────────────────
echo "[*] Installing base packages..."

case "$DISTRO" in
  arch)
    sudo pacman -Syu --noconfirm

    pacman_pkgs=(
      hyprland waybar kitty nautilus wofi wl-clipboard swaybg
      gtk3 gtk4 playerctl flatpak hyprpaper hyprlock pavucontrol gdm
      ttf-jetbrains-mono ttf-fira-code ttf-roboto
    )

    aur_pkgs=(
      cava cbonsai wofi-emoji ttf-font-awesome-5 ttf-font-awesome-6
      nerd-fonts-fira-code starship touchegg waypaper oh-my-zsh-git
      zsh-theme-powerlevel10k-git gpu-screen-recorder grimblast swappy
      bibata-cursor-theme network-manager-applet zen-browser-bin spotify
      waydroid vesktop visual-studio-code-bin goonsh
    )

    sudo pacman -S --needed --noconfirm "${pacman_pkgs[@]}"

    if ! command -v yay &>/dev/null; then
      echo "[*] Installing yay..."
      sudo pacman -S --needed --noconfirm base-devel
      git clone https://aur.archlinux.org/yay.git /tmp/yay
      cd /tmp/yay && makepkg -si --noconfirm && cd - && rm -rf /tmp/yay
    fi

    yay -S --needed --noconfirm "${aur_pkgs[@]}"
    ;;

  fedora)
    sudo dnf update -y
    sudo dnf install -y zsh git curl wget unzip nano vim fastfetch htop mpv kitty waybar wl-clipboard swaybg \
      nautilus wofi gtk3 gtk4 playerctl flatpak gdm \
      jetbrains-mono-fonts fira-code-fonts google-roboto-fonts fontawesome-fonts
    ;;

  gentoo)
    sudo emerge --sync
    sudo emerge --ask zsh git curl wget unzip nano vim fastfetch htop mpv x11-terms/kitty x11-misc/waybar \
      gui-apps/wofi gui-apps/swaybg x11-misc/wl-clipboard gui-apps/hyprland media-fonts/noto media-fonts/roboto media-fonts/jetbrains-mono gdm
    ;;

  nixos)
    echo "[!] NixOS detected. Please update your configuration.nix manually."
    $USE_GUI && zenity --info --title="NixOS Detected" --text="Update /etc/nixos/configuration.nix to include your packages."
    exit 0
    ;;

  *)
    echo "[!] Unsupported distro: $DISTRO"
    $USE_GUI && zenity --error --text="Unsupported distro: $DISTRO"
    exit 1
    ;;
esac

# ─── Clone Repo If Needed ─────────────
TMP_DIR=$(mktemp -d)
echo "[*] Cloning dotfiles from $REPO_URL..."
git clone --depth=1 "$REPO_URL" "$TMP_DIR"

# ─── Apply Dotfiles ─────────────────────
echo "[*] Copying configs..."
mkdir -p ~/.config
rsync -av --exclude=".zshrc" --exclude=".oh-my-zsh" "$TMP_DIR/dot_config/" ~/.config/
[ -f "$TMP_DIR/dot_config/.zshrc" ] && cp -f "$TMP_DIR/dot_config/.zshrc" ~/.zshrc
[ -d "$TMP_DIR/dot_config/.oh-my-zsh" ] && rsync -av "$TMP_DIR/dot_config/.oh-my-zsh/" ~/.oh-my-zsh/

# ─── Setup GDM Auto-Login to Hyprland ─────────────
echo "[*] Setting up GDM for Hyprland auto-login..."

# Create session file
sudo tee /usr/share/wayland-sessions/hyprland.desktop > /dev/null <<'EOF'
[Desktop Entry]
Name=Hyprland
Comment=Dynamic tiling Wayland compositor
Exec=/usr/bin/Hyprland
Type=Application
EOF

# Enable GDM
sudo systemctl enable gdm

# Configure auto-login
sudo mkdir -p /var/lib/AccountsService/users
sudo tee /var/lib/AccountsService/users/$USER > /dev/null <<EOF
[User]
XSession=hyprland
EOF

sudo sed -i "/^\[daemon\]/,/^\[/ s/^#*AutomaticLoginEnable=.*/AutomaticLoginEnable=True/" /etc/gdm/custom.conf || echo -e "[daemon]\nAutomaticLoginEnable=True" | sudo tee -a /etc/gdm/custom.conf
sudo sed -i "/^\[daemon\]/,/^\[/ s/^#*AutomaticLogin=.*/AutomaticLogin=$USER/" /etc/gdm/custom.conf || echo "AutomaticLogin=$USER" | sudo tee -a /etc/gdm/custom.conf

# ─── Final zshrc Tweaks ────────────
sed -i '/\.zsh\/zsh-autosuggestions/d' ~/.zshrc || true
sed -i '/\.zsh\/zsh-syntax-highlighting/d' ~/.zshrc || true

grep -q '^ZSH_THEME=' ~/.zshrc && \
  sed -i 's|^ZSH_THEME=.*|ZSH_THEME="powerlevel10k/powerlevel10k"|' ~/.zshrc || \
  echo 'ZSH_THEME="powerlevel10k/powerlevel10k"' >> ~/.zshrc

grep -q '^plugins=' ~/.zshrc && \
  sed -i 's|^plugins=.*|plugins=(git zsh-autosuggestions zsh-syntax-highlighting)|' ~/.zshrc || \
  echo 'plugins=(git zsh-autosuggestions zsh-syntax-highlighting)' >> ~/.zshrc

# ─── Finish ─────────────
rm -rf "$TMP_DIR"

if $USE_GUI; then
  zenity --info --title="Installation Complete" \
    --text="All done! Your system will boot directly into Hyprland via GDM."
  zenity --question --text="Reboot now?"
  [ $? -eq 0 ] && reboot
else
  echo "[✓] Installation complete. Your system will boot directly into Hyprland via GDM."
  read -p "Reboot now? (y/n): " reboot
  [[ "$reboot" =~ ^[Yy]$ ]] && reboot
fi
