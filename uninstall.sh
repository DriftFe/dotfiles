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
    debian|ubuntu|pop|linuxmint)
      DISTRO="debian"
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

# ─── Confirm Uninstall ─────────────────────
if $USE_GUI; then
  zenity --question --title="Uninstall Dotfiles" \
    --text="This will remove all configs and dotfiles except Hyprland itself. Continue?"
  [ $? -ne 0 ] && zenity --info --text="Uninstallation cancelled." && exit 0
else
  echo "[*] This will remove all dotfiles, configs, and installed components except Hyprland."
  read -p "Are you sure? (y/n): " confirm
  [[ "$confirm" != "y" && "$confirm" != "Y" ]] && echo "Cancelled." && exit 0
fi

# ─── Stop and disable SDDM ─────────────
echo "[*] Disabling SDDM..."
sudo systemctl disable sddm || true

# ─── Remove Dotfiles ───────────────────
echo "[*] Removing dotfiles and configs..."
rm -rf ~/.config/{waybar,kitty,wofi,sddm,vesktop,hypr,hyprpaper,cava,zsh,fastfetch} \
       ~/.wallpapers ~/.oh-my-zsh ~/.zshrc ~/.config/starship.toml

# ─── Remove AUR/optional packages ──────
echo "[*] Removing optional packages..."
if command -v yay &>/dev/null; then
  yay -Rns --noconfirm cava cbonsai wofi-emoji starship touchegg \
    oh-my-zsh-git zsh-theme-powerlevel10k-git grimblast swappy \
    gpu-screen-recorder vesktop visual-studio-code-bin spotify zen-browser-bin goonsh || true
fi

# ─── Remove from official repos ────────
if [ "$DISTRO" = "arch" ]; then
  sudo pacman -Rns --noconfirm kitty nautilus wofi sddm waybar hyprpaper hyprlock || true
elif [ "$DISTRO" = "fedora" ]; then
  sudo dnf remove -y kitty nautilus wofi sddm waybar || true
elif [ "$DISTRO" = "gentoo" ]; then
  sudo emerge --ask --depclean x11-terms/kitty gui-apps/wofi gui-apps/sddm x11-misc/waybar || true
elif [ "$DISTRO" = "debian" ]; then
  sudo apt remove -y kitty nautilus wofi sddm waybar || true
fi

# ─── Offer to Restore from GitHub ─────────────
if $USE_GUI; then
  zenity --question --title="Restore Dotfiles" \
    --text="Would you like to restore the latest dotfiles from GitHub?"
  RESTORE=$?
else
  read -p "Restore latest dotfiles from GitHub? (y/n): " restore_confirm
  [[ "$restore_confirm" =~ ^[Yy]$ ]] && RESTORE=0 || RESTORE=1
fi

if [ "$RESTORE" -eq 0 ]; then
  echo "[*] Cloning latest dotfiles..."
  TMP_RESTORE=$(mktemp -d)
  git clone --depth=1 "$REPO_URL" "$TMP_RESTORE"
  mkdir -p ~/.config
  rsync -av "$TMP_RESTORE/dot_config/" ~/.config/
  cp "$TMP_RESTORE/dot_config/.zshrc" ~/.zshrc 2>/dev/null || true
  [ -d "$TMP_RESTORE/dot_config/.oh-my-zsh" ] && rsync -av "$TMP_RESTORE/dot_config/.oh-my-zsh/" ~/.oh-my-zsh/
  rm -rf "$TMP_RESTORE"
  echo "[✓] Dotfiles restored."
fi

# ─── Cleanup Complete ─────────────────
if $USE_GUI; then
  zenity --question --title="Uninstall Complete" \
    --text="Uninstallation complete. Reboot now?"
  [ $? -eq 0 ] && reboot
else
  echo "[✓] Uninstallation complete."
  read -p "Reboot now? (y/n): " reboot
  [[ "$reboot" =~ ^[Yy]$ ]] && reboot
fi
