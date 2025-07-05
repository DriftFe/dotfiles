#!/bin/bash
set -e

echo "[*] Installing cute dotfiles >w<"

# ─── Detect Distro ─────
DISTRO="unknown"
if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO=$ID
fi
echo "[*] Detected distro: $DISTRO"

# ─── Common Packages ──────
packages_common=(
  zsh git curl wget unzip nano vim fastfetch htop mpv
  noto-fonts noto-fonts-emoji font-manager
)

# ─── Distro-Specific Installation ───────
case "$DISTRO" in
  arch)
    echo "[*] Installing for Arch Linux"
    sudo pacman -Syu --noconfirm

    pacman_pkgs=(
      hyprland waybar kitty nautilus wofi sddm wl-clipboard swaybg
      gtk3 gtk4 playerctl flatpak hyprpaper hyprlock
      ttf-jetbrains-mono ttf-fira-code ttf-roboto
    )

    aur_pkgs=(
      cava cbonsai wofi-emoji ttf-font-awesome-5 ttf-font-awesome-6
      nerd-fonts-fira-code starship touchegg waypaper oh-my-zsh-git
      zsh-theme-powerlevel10k-git gpu-screen-recorder grimblast swappy
      bibata-cursor-theme network-manager-applet zen-browser-bin spotify
      waydroid vesktop visual-studio-code-bin
    )

    sudo pacman -S --needed --noconfirm "${packages_common[@]}" "${pacman_pkgs[@]}"

    if ! command -v yay &>/dev/null; then
      echo "[*] Installing yay..."
      sudo pacman -S --needed --noconfirm base-devel
      git clone https://aur.archlinux.org/yay.git /tmp/yay
      cd /tmp/yay && makepkg -si --noconfirm && cd - && rm -rf /tmp/yay
    fi

    yay -S --needed --noconfirm "${aur_pkgs[@]}"
    sudo systemctl enable sddm
    ;;

  fedora)
    echo "[*] Installing for Fedora"
    sudo dnf update -y
    sudo dnf install -y "${packages_common[@]}" kitty waybar wl-clipboard swaybg \
      nautilus wofi sddm gtk3 gtk4 playerctl flatpak

    sudo dnf install -y jetbrains-mono-fonts fira-code-fonts google-roboto-fonts fontawesome-fonts
    sudo systemctl enable sddm
    ;;

  gentoo)
    echo "[*] Installing for Gentoo"
    sudo emerge --sync
    sudo emerge --ask "${packages_common[@]}" x11-terms/kitty x11-misc/waybar \
      gui-apps/wofi gui-apps/swaybg x11-misc/wl-clipboard gui-apps/hyprland
    sudo emerge --ask media-fonts/noto media-fonts/roboto media-fonts/jetbrains-mono
    ;;

  nixos)
    echo "[*] NixOS detected!"
    echo
    echo "❗ Please add these to your /etc/nixos/configuration.nix:"
    echo
    echo "  environment.systemPackages = with pkgs; ["
    echo "    zsh git curl wget unzip nano vim fastfetch htop mpv kitty waybar hyprland"
    echo "    nautilus wofi sddm wl-clipboard swaybg gtk3 gtk4 playerctl flatpak"
    echo "    noto-fonts noto-fonts-emoji jetbrains-mono fira-code roboto font-manager"
    echo "  ];"
    echo
    echo "  services.displayManager.sddm.enable = true;"
    echo "  programs.zsh.enable = true;"
    echo
    echo "Then run: sudo nixos-rebuild switch"
    exit 0
    ;;

  *)
    echo "[!] Unsupported distro: $DISTRO"
    exit 1
    ;;
esac

# ─── ZSH & Oh My Zsh Setup ─────────
chsh -s "$(which zsh)"

if [ ! -d "$HOME/.oh-my-zsh" ]; then
  echo "[*] Installing Oh My Zsh..."
  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

# Powerlevel10k
if [ ! -d "$ZSH_CUSTOM/themes/powerlevel10k" ]; then
  git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$ZSH_CUSTOM/themes/powerlevel10k"
fi

# ZSH Plugins
[ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ] &&
  git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"

[ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ] &&
  git clone https://github.com/zsh-users/zsh-syntax-highlighting "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"

# Starship Prompt
if ! command -v starship &>/dev/null; then
  echo "[*] Installing Starship..."
  curl -sS https://starship.rs/install.sh | sh -s -- -y
fi

# ─── Wallpaper Setup ────────
mkdir -p ~/.wallpapers
[ -f "./dot_config/wallpaper.jpg" ] && cp ./dot_config/wallpaper.jpg ~/.wallpapers/
[ -f "./dot_config/wallpaper.png" ] && cp ./dot_config/wallpaper.png ~/.wallpapers/

# ─── Dotfiles Sync ──────────────
if [ -d "./dot_config" ]; then
  echo "[*] Copying dot_config to ~/.config..."
  mkdir -p ~/.config
  rsync -av --exclude=".zshrc" --exclude=".oh-my-zsh" ./dot_config/ ~/.config/

  [ -f "./dot_config/.zshrc" ] && cp -f ./dot_config/.zshrc ~/.zshrc
  [ -d "./dot_config/.oh-my-zsh" ] && rsync -av ./dot_config/.oh-my-zsh/ ~/.oh-my-zsh/
fi

# ─── ZSHRC Cleanup ────────────────
sed -i '/\.zsh\/zsh-autosuggestions/d' ~/.zshrc || true
sed -i '/\.zsh\/zsh-syntax-highlighting/d' ~/.zshrc || true

# ZSH_THEME
if grep -q '^ZSH_THEME=' ~/.zshrc; then
  sed -i 's|^ZSH_THEME=.*|ZSH_THEME="powerlevel10k/powerlevel10k"|' ~/.zshrc
else
  echo 'ZSH_THEME="powerlevel10k/powerlevel10k"' >> ~/.zshrc
fi

# Plugins
if grep -q '^plugins=' ~/.zshrc; then
  sed -i 's|^plugins=.*|plugins=(git zsh-autosuggestions zsh-syntax-highlighting)|' ~/.zshrc
else
  echo 'plugins=(git zsh-autosuggestions zsh-syntax-highlighting)' >> ~/.zshrc
fi

echo
echo "[+] Done! You can now reboot into Hyprland >w<"
echo "[i] Check keybinds in: ~/.config/hypr/keys.conf"
