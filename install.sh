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
  case "$ID" in
    arch|manjaro|endeavouros)
      DISTRO="arch"
      ;;
    fedora|rhel|centos)
      DISTRO="fedora"
      ;;
    gentoo)
      DISTRO="gentoo"
      ;;
    nixos)
      DISTRO="nixos"
      ;;
    *)
      DISTRO="$ID"
      ;;
  esac
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
    sudo pacman -S --needed --noconfirm \
      hyprland waybar kitty zsh nautilus wofi sddm fastfetch mpv htop wl-clipboard \
      swaybg unzip curl wget git gtk3 gtk4 playerctl nano vim flatpak hyprpaper \
      hyprlock noto-fonts noto-fonts-cjk noto-fonts-emoji ttf-jetbrains-mono \
      ttf-fira-code ttf-roboto font-manager
    ;;
  fedora)
    sudo dnf update -y
    sudo dnf install -y \
      hyprland waybar kitty zsh nautilus wofi sddm fastfetch mpv htop wl-clipboard \
      swaybg unzip curl wget git gtk3 gtk4 playerctl nano vim flatpak hyprpaper \
      hyprlock google-noto-sans-fonts google-noto-emoji-fonts \
      jetbrains-mono-fonts fira-code-fonts google-roboto-fonts font-manager
    ;;
  gentoo)
    sudo emerge --sync
    sudo emerge --ask \
      app-shells/zsh app-admin/rsync app-editors/vim app-editors/nano \
      app-text/wget net-misc/curl app-misc/flatpak media-video/mpv \
      app-admin/fastfetch app-admin/htop x11-terms/kitty gui-apps/wofi \
      gui-apps/waybar gui-apps/sddm gui-libs/gtk gui-libs/gtk4 \
      gui-apps/hyprpaper gui-apps/hyprlock gui-apps/swaybg \
      media-fonts/noto media-fonts/jetbrains-mono media-fonts/roboto font-manager
    ;;
  nixos)
    echo "[!] NixOS detected. Please add the following to your /etc/nixos/configuration.nix and run 'sudo nixos-rebuild switch':"
    echo 'environment.systemPackages = with pkgs; [ zsh git curl wget unzip nano vim fastfetch htop mpv kitty waybar hyprland nautilus wofi sddm wl-clipboard swaybg gtk3 gtk4 playerctl flatpak noto-fonts noto-fonts-cjk noto-fonts-emoji jetbrains-mono fira-code roboto font-manager ];'
    exit 0
    ;;
  *)
    echo "[!] Unsupported distro: $DISTRO"
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

# ─── Enable SDDM ─────────────
if command -v systemctl &>/dev/null; then
  echo "[*] Enabling SDDM..."
  sudo systemctl enable sddm || true
fi

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
    --text="All done! You may want to reboot now."
  zenity --question --text="Reboot now?"
  [ $? -eq 0 ] && reboot
else
  echo "[✓] Installation complete."
  read -p "Reboot now? (y/n): " reboot
  [[ "$reboot" =~ ^[Yy]$ ]] && reboot
fi
