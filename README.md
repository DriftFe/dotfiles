# lavender dotfiles ♡
omg hi!! this is my soft lavender hyprland setup for arch linux >~< it's got a glassy look, a custom wofi launcher, and a bunch of actually useful daily apps and scripts that i use!! hope u like it as much as i do hehe

![Preview](https://www.dropbox.com/scl/fi/vd78noq20sxr20193b7li/image.webp?rlkey=x0lm1eaa3b7y74n3mlpqa64b5&st=b74g2c35&raw=1)

## what's inside ♡
### window manager & desktop stuff
- Hyprland
- Waybar
- Wofi
- GDM
- awww
- Hyprlock
- Mako
### apps i actually use
- Kitty
- Dolphin
- VS Code
- Spotify
- Vesktop
- Zen Browser
- Kdenlive
### shell & pretty visuals
- Zsh
- Oh My Zsh
- Starship
- Cava
- CBonsai
### little utilities n things
- Cliphist
- Grimblast
- Swappy
- Hyprpicker
- Fastfetch
- Waypaper
- Touchegg

## features ♡
- lavender/pink hyprland styling because purple is the only correct color
- custom spotlight-ish wofi app launcher that looks super cute
- clipboard history picker on `Super + V`
- emoji picker on `Super + .` (very important)
- usb popup actions through wofi!!
- screenshot workflow with grimblast + swappy
- scratchpad / special workspace support
- animated borders and blur because flat desktops make me sad >:(

## installation ♡
### one-line install
if u trust me (plz trust me):
```bash
curl -sSL https://raw.githubusercontent.com/DriftFe/dotfiles/main/install.sh | bash
```
### manual install
if u wanna see what's going on first, which is totally valid and smart of u >_<
```bash
git clone https://github.com/DriftFe/dotfiles.git
cd dotfiles
chmod +x install.sh
./install.sh
```

## keybinds ♡
### the important ones
- `Super + A` - open app launcher
- `Super + T` - open kitty
- `Super + E` - open dolphin
- `Super + B` - open zen browser
- `Super + C` - open vs code
- `Super + D` - open vesktop
- `Super + Ctrl + S` - open spotify (essential)
- `Super + L` - lock screen
- `Super + M` - exit hyprland (nooo)
### window stuff
- `Super + Q` - close active window
- `Super + Shift + Q` - kill selected window (the aggressive version)
- `Super + W` - toggle floating
- `Super + J` - toggle split layout
- `Super + Arrow Keys` - move focus
- `Alt + Arrow Keys` - move windows
### utilities n things
- `Super + V` - clipboard history
- `Super + .` - emoji picker ♡
- `Alt + S` - area screenshot to clipboard, then edit
- `Ctrl + Alt + S` - area screenshot to file
- `Print` - fullscreen screenshot to file
- `Alt + W` - random wallpaper

## customization ♡
### hyprland
tweak settings and keybinds here!!
```bash
vim ~/.config/hypr/hyprland.conf
vim ~/.config/hypr/keys.conf
```
### wofi
make the launcher even cuter:
```bash
vim ~/.config/wofi/style.css
```
### shell
```bash
vim ~/.zshrc
vim ~/.config/starship.toml
```
### wallpapers
wallpaper restore is tied to waypaper rn so if u wanna use ur own wallpapers u'll probably wanna mess with that a little!! shouldn't be too hard tho

## prerequisites ♡
the installer handles most of it but just in case:
- Git
- Curl
- base-devel

## post-install ♡
1. reboot!!
2. log in through GDM
3. launch hyprland
4. press `Super + A` and make sure the launcher opens >_<
5. dig through `~/.config/hypr/keys.conf` and `~/.config/wofi/style.css` until it feels like urs :3

## troubleshooting ♡
### hyprland won't start
ugh okay try this:
```bash
ls /usr/share/wayland-sessions/hyprland.desktop
sudo cp /usr/share/hyprland/hyprland.desktop /usr/share/wayland-sessions/
```
### waybar not showing
```bash
pkill waybar
waybar &
```
### scripts not executing
oh u probably just need to chmod them!!
```bash
chmod +x ~/.config/hypr/scripts/*.sh
chmod +x ~/.config/hypr/scripts/*.py
```
### dotfiles not applying
```bash
rsync -av dot_config/ ~/.config/
```

---
ty so much for checking this out, I hope u love it as much as I do!! feel free to make it ur own >~< ♡
