#!/bin/bash
set -e

# ─── Zenity Environment Check ─────────────────────────────
USE_GUI=false

# Check if zenity is available and we're in a GUI session
if command -v zenity &>/dev/null && { [ "$DISPLAY" ] || [ "$WAYLAND_DISPLAY" ]; }; then
  USE_GUI=true
else
  echo "[*] No GUI detected or Zenity not installed. Falling back to terminal mode."
fi

# ─── Welcome ─────────────────────────────
if $USE_GUI; then
  zenity --info --width=300 --title="Cute Dotfiles Installer >w<" \
    --text="Welcome to the multi-distro dotfiles installer!"
else
  echo "Cute Dotfiles Installer >w<"
  echo "Welcome to the multi-distro dotfiles installer!"
  read -p "Press Enter to continue..."
fi

# ─── Detect Distro ───────────────────────
DISTRO="unknown"
if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO=$ID
fi

if $USE_GUI; then
  zenity --info --title="Distro Detected!" --text="You're running: $DISTRO"
else
  echo "[*] Detected distro: $DISTRO"
fi

# ─── Confirm Install ─────────────────────
if $USE_GUI; then
  zenity --question --title="Confirm Install" \
    --text="Install dotfiles and Hyprland setup on $DISTRO?"
  [ $? -ne 0 ] && zenity --info --text="Installation cancelled." && exit 0
else
  read -p "Install dotfiles and Hyprland setup on $DISTRO? (y/n): " confirm
  [[ "$confirm" != "y" && "$confirm" != "Y" ]] && echo "Cancelled." && exit 0
fi

# ─── Begin Install ───────────────────────
echo "[*] Starting installation..."

packages_common=(
  zsh git curl wget unzip nano vim fastfetch htop mpv
  noto-fonts noto-fonts-emoji font-manager sddm
)

case "$DISTRO" in
  arch)
    sudo pacman -Syu --noconfirm
    pacman_pkgs=(
      hyprland waybar kitty nautilus wofi wl-clipboard swaybg
      gtk3 gtk4 playerctl flatpak hyprpaper hyprlock
      ttf-jetbrains-mono ttf-fira-code ttf-roboto
    )
    aur_pkgs=(
      cava cbonsai wofi-emoji ttf-font-awesome-5 ttf-font-awesome-6
      nerd-fonts-fira-code starship touchegg oh-my-zsh-git
      zsh-theme-powerlevel10k-git gpu-screen-recorder grimblast swappy
      network-manager-applet zen-browser-bin spotify vesktop visual-studio-code-bin goonsh
    )

    sudo pacman -S --needed --noconfirm "${packages_common[@]}" "${pacman_pkgs[@]}"
    if ! command -v yay &>/dev/null; then
      echo "[*] Installing yay..."
      sudo pacman -S --needed --noconfirm base-devel
      git clone https://aur.archlinux.org/yay.git /tmp/yay
      cd /tmp/yay && makepkg -si --noconfirm && cd - && rm -rf /tmp/yay
    fi

    failed_pkgs=()
    for pkg in "${aur_pkgs[@]}"; do
      echo "[*] Installing AUR package: $pkg"
      if ! yay -S --needed --noconfirm "$pkg"; then
        echo "[!] Failed to install $pkg. Will retry later."
        failed_pkgs+=("$pkg")
      fi
    done

    # Reattempt loop
    if [ ${#failed_pkgs[@]} -gt 0 ]; then
      echo "[*] Reattempting failed AUR installs..."
      for pkg in "${failed_pkgs[@]}"; do
        echo "[*] Retrying $pkg..."
        yay -S --needed --noconfirm "$pkg" || echo "[x] $pkg still failed. Skipping."
      done
    fi

    sudo systemctl enable sddm
    ;;

  fedora)
    sudo dnf update -y
    sudo dnf install -y "${packages_common[@]}" kitty waybar wl-clipboard swaybg \
      nautilus wofi gtk3 gtk4 playerctl flatpak
    sudo dnf install -y jetbrains-mono-fonts fira-code-fonts google-roboto-fonts fontawesome-fonts
    sudo systemctl enable sddm
    ;;

  gentoo)
    sudo emerge --sync
    sudo emerge --ask "${packages_common[@]}" x11-terms/kitty x11-misc/waybar \
      gui-apps/wofi gui-apps/swaybg x11-misc/wl-clipboard gui-apps/hyprland
    sudo emerge --ask media-fonts/noto media-fonts/roboto media-fonts/jetbrains-mono
    ;;

  nixos)
    echo "[!] NixOS detected. Please update /etc/nixos/configuration.nix with:

  environment.systemPackages = with pkgs; [
    zsh git curl wget unzip nano vim fastfetch htop mpv kitty waybar hyprland
    nautilus wofi sddm wl-clipboard swaybg gtk3 gtk4 playerctl flatpak
    noto-fonts noto-fonts-emoji jetbrains-mono fira-code roboto font-manager
  ];

services.xserver.displayManager.sddm.enable = true;

Then run: sudo nixos-rebuild switch"
    exit 0
    ;;

  *)
    echo "[!] Unsupported distro: $DISTRO"
    exit 1
    ;;
esac

# ─── Shell Setup ─────────────────────────
echo "[*] Setting up ZSH and themes..."
chsh -s "$(which zsh)"

if [ ! -d "$HOME/.oh-my-zsh" ]; then
  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
[ ! -d "$ZSH_CUSTOM/themes/powerlevel10k" ] && \
  git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$ZSH_CUSTOM/themes/powerlevel10k"
[ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ] && \
  git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
[ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ] && \
  git clone https://github.com/zsh-users/zsh-syntax-highlighting "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"

if ! command -v starship &>/dev/null; then
  curl -sS https://starship.rs/install.sh | sh -s -- -y
fi

# ─── Wallpapers & Dotfiles ───────────────
echo "[*] Copying dotfiles and wallpapers..."
mkdir -p ~/.wallpapers
[ -f "./dot_config/wallpaper.jpg" ] && cp ./dot_config/wallpaper.jpg ~/.wallpapers/
[ -f "./dot_config/wallpaper.png" ] && cp ./dot_config/wallpaper.png ~/.wallpapers/

if [ -d "./dot_config" ]; then
  mkdir -p ~/.config
  rsync -av ./dot_config/ ~/.config/
  [ -f "./dot_config/.zshrc" ] && cp -f ./dot_config/.zshrc ~/.zshrc
  [ -d "./dot_config/.oh-my-zsh" ] && rsync -av ./dot_config/.oh-my-zsh/ ~/.oh-my-zsh/
fi

# ─── Final zshrc Tweaks ─────────────────
sed -i '/\.zsh\/zsh-autosuggestions/d' ~/.zshrc || true
sed -i '/\.zsh\/zsh-syntax-highlighting/d' ~/.zshrc || true

grep -q '^ZSH_THEME=' ~/.zshrc && \
  sed -i 's|^ZSH_THEME=.*|ZSH_THEME="powerlevel10k/powerlevel10k"|' ~/.zshrc || \
  echo 'ZSH_THEME="powerlevel10k/powerlevel10k"' >> ~/.zshrc

grep -q '^plugins=' ~/.zshrc && \
  sed -i 's|^plugins=.*|plugins=(git zsh-autosuggestions zsh-syntax-highlighting)|' ~/.zshrc || \
  echo 'plugins=(git zsh-autosuggestions zsh-syntax-highlighting)' >> ~/.zshrc

# ─── Finish ──────────────────────────────
echo "[✓] Installation complete!"
if $USE_GUI; then
  zenity --question --title="Reboot?" \
    --text="Installation complete!\n\nDo you want to reboot now?"
  [ $? -eq 0 ] && reboot
else
  read -p "Reboot now? (y/n): " reboot_now
  [[ "$reboot_now" =~ ^[Yy]$ ]] && reboot
fi
