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

# ─── Detect Distro ─────────────────────────────
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
    debian|ubuntu|pop|linuxmint)
      echo "[✗] This installer does NOT support Debian-based distros."
      echo "Please use Arch, Fedora, Gentoo, or NixOS instead."
      exit 1
      ;;
    *)
      DISTRO="$ID"
      ;;
  esac
else
  echo "[✗] Could not detect your Linux distribution."
  exit 1
fi

# ─── Confirm Install ─────────────────────────────
if $USE_GUI; then
  zenity --question --title="Install Dotfiles" \
    --text="This will install Hyprland, dependencies, and your dotfiles. Continue?"
  [ $? -ne 0 ] && zenity --info --text="Installation cancelled." && exit 0
else
  echo "[*] This will install Hyprland, dependencies, and dotfiles."
  read -p "Are you sure? (y/n): " confirm
  [[ "$confirm" != "y" && "$confirm" != "Y" ]] && echo "Cancelled." && exit 0
fi

# ─── Install Packages ─────────────────────────────
if [ "$DISTRO" = "arch" ]; then
  sudo pacman -Syu --noconfirm hyprland kitty nautilus wofi sddm waybar hyprpaper hyprlock
  if command -v yay &>/dev/null; then
    yay -S --noconfirm cava cbonsai wofi-emoji starship touchegg \
      oh-my-zsh-git zsh-theme-powerlevel10k-git grimblast swappy \
      gpu-screen-recorder vesktop visual-studio-code-bin spotify zen-browser-bin goonsh
  fi
elif [ "$DISTRO" = "fedora" ]; then
  sudo dnf install -y hyprland kitty nautilus wofi sddm waybar hyprpaper hyprlock
elif [ "$DISTRO" = "gentoo" ]; then
  sudo emerge --ask gui-wm/hyprland x11-terms/kitty gui-apps/wofi gui-apps/sddm x11-misc/waybar
elif [ "$DISTRO" = "nixos" ]; then
  echo "[!] On NixOS, please add Hyprland and related packages to your configuration.nix"
fi

# ─── Clone and Apply Dotfiles ─────────────────────────────
echo "[*] Downloading and applying dotfiles..."
TMP_DIR=$(mktemp -d)
git clone --depth=1 "$REPO_URL" "$TMP_DIR"
mkdir -p ~/.config
rsync -av "$TMP_DIR/dot_config/" ~/.config/
cp "$TMP_DIR/dot_config/.zshrc" ~/.zshrc 2>/dev/null || true
[ -d "$TMP_DIR/dot_config/.oh-my-zsh" ] && rsync -av "$TMP_DIR/dot_config/.oh-my-zsh/" ~/.oh-my-zsh/
rm -rf "$TMP_DIR"

# ─── Enable SDDM ─────────────────────────────
echo "[*] Enabling SDDM..."
sudo systemctl enable sddm

# ─── Done ─────────────────────────────
if $USE_GUI; then
  zenity --question --title="Install Complete" \
    --text="Installation complete. Reboot now?"
  [ $? -eq 0 ] && reboot
else
  echo "[✓] Installation complete."
  read -p "Reboot now? (y/n): " reboot
  [[ "$reboot" =~ ^[Yy]$ ]] && reboot
fi
