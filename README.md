# Lavender Dotfiles

An extremely minimal lavender themed hyprland setup with cool applications. Automated installation and management for Arch, Fedora, Gentoo, and NixOS.

## Stuff Included

### **Window Manager & Desktop**
- **Hyprland** (obv)
- **Waybar** 
- **Wofi** 
- **GDM** 
- **Hyprpaper** 
- **Hyprlock** 

### **Applications & Tools**
- **Kitty** 
- **Goonsh** (cuz.. why not)
- **Nautilus** 
- **VSCode** 
- **Spotify** 
- **Vesktop** 
- **Zen Browser** 

### **Customization & Theming**
- **Starship** 
- **Oh My Zsh** 
- **Cava** 
- **CBonsai** 

### **Utilities**
- **GPU Screen Recorder** 
- **Grimblast** 
- **Swappy** 
- **Fastfetch**

## Installation

### One-Line Installation
```bash
curl -sSL https://raw.githubusercontent.com/DriftFe/dotfiles/main/install.sh | bash
```

### Manual Installation
```bash
git clone https://github.com/DriftFe/dotfiles.git
cd dotfiles
chmod +x install.sh
./install.sh
```

## Supported Distributions

### ✅ **Fully Supported**
- **Arch Linux** (and sub-distros: Manjaro, EndeavourOS)
- **Fedora** (and sub-distros: RHEL, CentOS)
- **Gentoo**
- **NixOS**

### ❌ **Not Supported**
- Debian-based distributions (Ubuntu, Pop!_OS, Linux Mint)
  - *Use Arch, Fedora, Gentoo, or NixOS instead*

## Management Scripts

### **Install** (`install.sh`)
```bash
./install.sh
```

### **Update** (`update.sh`)
```bash
./update.sh
```

### **Uninstall** (`uninstall.sh`)
```bash
./uninstall.sh
```

## Customization

### **Wallpapers** (as of now, you have to replace the current wallpaper, because its hard-coded to only load wallpaper.jpg)
Place custom wallpapers in `~/.wallpapers/` and update

### **Keybindings**
Modify Hyprland keybindings in:
```bash
vim ~/.config/hypr/keys.conf
```

### **Shell Configuration**
Customize your shell experience:
```bash
# Edit Zsh config
vim ~/.zshrc

# Powerlevel10k prompt
p10k configure

# Starship prompt
vim ~/.config/starship.toml
```

## Prerequisites

The installer automatically handles most dependencies, but ensure you have:

- **Git** - For cloning the repository
- **Curl** - For one-line installation

### Optional for GUI Mode:
- **Zenity** (For graphical installation)
- **X11 or Wayland session** - For GUI display

## Post-Installation

1. **Reboot your system** for all changes to take effect
2. **Log in with GDM** - Hyprland will be the default session
3. **Launch applications:**
   - `Super + A` - Open Wofi launcher
   - `Super + T` - Open Kitty terminal
   - `Super + Q` - Close window
   - `Super + M` - Exit Hyprland

4. **Customize to your liking** using the configuration files

## Troubleshooting

### Common Issues
**No Permission:**
```bash
chmod +x [script].sh

**Hyprland won't start:**
```bash
# Check if session file exists
ls /usr/share/wayland-sessions/hyprland.desktop

# Manually create if missing
sudo cp /usr/share/hyprland/hyprland.desktop /usr/share/wayland-sessions/
```

**Missing packages on Arch:**
```bash
# Install yay if not present
sudo pacman -S --needed base-devel git
git clone https://aur.archlinux.org/yay.git
cd yay && makepkg -si
```

**Waybar not showing:**
```bash
# Restart waybar
pkill waybar
waybar &
```

**Dotfiles not applied:**
```bash
# Manually sync configurations
rsync -av dot_config/ ~/.config/
```

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

ty for reading, ur amazing :3
