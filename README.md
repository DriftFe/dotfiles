# Lavender Dotfiles

A soft lavender Hyprland setup for Arch Linux with a glassy look, a custom Wofi launcher, and a bunch of actually useful daily apps and scripts >~<

## Included

### Window Manager & Desktop
- Hyprland
- Waybar
- Wofi
- GDM
- awww
- Hyprlock
- Mako

### Applications & Tools
- Kitty
- Dolphin
- VS Code
- Spotify
- Vesktop
- Zen Browser
- Kdenlive

### Shell & Visuals
- Zsh
- Oh My Zsh
- Starship
- Cava
- CBonsai

### Utilities
- Cliphist
- Grimblast
- Swappy
- Hyprpicker
- Fastfetch
- Waypaper
- Touchegg

## Features

- Lavender/pink Hyprland styling
- Custom Spotlight-ish Wofi app launcher
- Clipboard history picker on `Super + V`
- Emoji picker on `Super + .`
- USB popup actions through Wofi
- Screenshot workflow with Grimblast + Swappy
- Scratchpad / special workspace support
- Animated borders and blur because flat desktops are boring >:(

## Installation

### One-Line Install

If you trust me a little too much:

```bash
curl -sSL https://raw.githubusercontent.com/DriftFe/dotfiles/main/install.sh | bash
```

### Manual Install

If you want to look at what is happening first, which is fair >_<

```bash
git clone https://github.com/DriftFe/dotfiles.git
cd dotfiles
chmod +x install.sh
./install.sh
```

## Management

### Install Script

```bash
./install.sh
```

## Keybinds

### Core

- `Super + A` - Open app launcher
- `Super + T` - Open Kitty
- `Super + E` - Open Dolphin
- `Super + B` - Open Zen Browser
- `Super + C` - Open VS Code
- `Super + D` - Open Vesktop
- `Super + Ctrl + S` - Open Spotify
- `Super + L` - Lock screen
- `Super + M` - Exit Hyprland

### Window Management

- `Super + Q` - Close active window
- `Super + Shift + Q` - Kill selected window
- `Super + W` - Toggle floating
- `Super + J` - Toggle split layout
- `Super + Arrow Keys` - Move focus
- `Alt + Arrow Keys` - Move windows

### Utilities

- `Super + V` - Clipboard history
- `Super + .` - Emoji picker
- `Alt + S` - Area screenshot to clipboard, then edit
- `Ctrl + Alt + S` - Area screenshot to file
- `Print` - Fullscreen screenshot to file
- `Alt + W` - Random wallpaper

## Customization

### Hyprland

Tweak Hyprland settings and keybinds here:

```bash
vim ~/.config/hypr/hyprland.conf
vim ~/.config/hypr/keys.conf
```

### Wofi

Customize launcher styling:

```bash
vim ~/.config/wofi/style.css
```

### Shell

```bash
vim ~/.zshrc
vim ~/.config/starship.toml
```

### Wallpapers

Wallpaper restore is currently tied to the existing setup through Waypaper, so if you want your own look you will probably want to swap that around a bit.

## Prerequisites

The installer should handle most of it, but having these ready helps:

- Git
- Curl
- base-devel

## Post-Install

1. Reboot the system.
2. Log in through GDM.
3. Launch Hyprland.
4. Press `Super + A` and make sure the launcher opens like it should.
5. Mess with `~/.config/hypr/keys.conf` and `~/.config/wofi/style.css` until it feels like yours >:3

## Troubleshooting

### Hyprland Won't Start

```bash
ls /usr/share/wayland-sessions/hyprland.desktop
sudo cp /usr/share/hyprland/hyprland.desktop /usr/share/wayland-sessions/
```

### Waybar Not Showing

```bash
pkill waybar
waybar &
```

### Scripts Not Executing

```bash
chmod +x ~/.config/hypr/scripts/*.sh
chmod +x ~/.config/hypr/scripts/*.py
```

### Dotfiles Not Applying

```bash
rsync -av dot_config/ ~/.config/
```

ty for reading, hope u like the setup <3
