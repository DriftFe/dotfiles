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

# ─── Confirm Update ─────────────────────
if $USE_GUI; then
  zenity --question --title="Update Dotfiles" \
    --text="Check for dotfile updates from GitHub and apply if changed?"
  [ $? -ne 0 ] && zenity --info --text="Update cancelled." && exit 0
else
  echo "[*] Check for dotfile updates from GitHub."
  read -p "Proceed? (y/n): " confirm
  [[ "$confirm" != "y" && "$confirm" != "Y" ]] && echo "Cancelled." && exit 0
fi

TMP_DIR=$(mktemp -d)
git clone --depth=1 "$REPO_URL" "$TMP_DIR"

changes=$(diff -qr "$TMP_DIR/dot_config" "$HOME/.config" | grep -v ".git")

if [ -z "$changes" ]; then
  $USE_GUI && zenity --info --title="Dotfiles Updater" --text="✅ Dotfiles are up to date." || echo "[✓] Dotfiles are up to date."
else
  $USE_GUI && zenity --question --title="Dotfiles Updater" --text="⚠️ Changes detected. Update local config?"
  if ! $USE_GUI || [ $? -eq 0 ]; then
    rsync -av --delete "$TMP_DIR/dot_config/" "$HOME/.config/"
    [ -f "$TMP_DIR/dot_config/.zshrc" ] && cp -f "$TMP_DIR/dot_config/.zshrc" ~/.zshrc
    [ -d "$TMP_DIR/dot_config/.oh-my-zsh" ] && rsync -av "$TMP_DIR/dot_config/.oh-my-zsh/" ~/.oh-my-zsh/
    $USE_GUI && zenity --info --title="Dotfiles Updater" --text="✅ Dotfiles updated." || echo "[✓] Dotfiles updated."
  else
    $USE_GUI && zenity --info --title="Dotfiles Updater" --text="Update cancelled." || echo "[x] Update cancelled."
  fi
fi

rm -rf "$TMP_DIR"

# ─── Optional: Re-source ZSH ─────────────
if [ "$SHELL" = "$(which zsh)" ]; then
  exec zsh
else
  $USE_GUI && zenity --info --title="Shell Reminder" --text="Restart your terminal session to reload configuration." || echo "[*] Restart your shell or log out and log back in."
fi
