#!/bin/bash
set -e

REPO_URL="https://github.com/DriftFe/dotfiles"
SCRIPT_NAME="Lavender Dotfiles Updater"

# ─── Zenity Environment Check ─────────────────────────────
USE_GUI=false
if command -v zenity &>/dev/null && { [ -n "$DISPLAY" ] || [ -n "$WAYLAND_DISPLAY" ]; }; then
    USE_GUI=true
else
    echo "[*] No GUI detected or Zenity not installed. Falling back to terminal mode."
fi

# ─── Helper Functions ─────────────────────────────
show_message() {
    local title="$1"
    local message="$2"
    local type="${3:-info}"  # info, error, warning
    
    if $USE_GUI; then
        case "$type" in
            "error")
                zenity --error --title="$title" --text="$message"
                ;;
            "warning")
                zenity --warning --title="$title" --text="$message"
                ;;
            *)
                zenity --info --title="$title" --text="$message"
                ;;
        esac
    else
        echo "[$type] $message"
    fi
}

ask_question() {
    local message="$1"
    local title="${2:-$SCRIPT_NAME}"
    
    if $USE_GUI; then
        zenity --question --title="$title" --text="$message"
        return $?
    else
        echo "[?] $message"
        read -p "Proceed? (y/n): " confirm
        [[ "$confirm" =~ ^[Yy]$ ]] && return 0 || return 1
    fi
}

# ─── Error Handler ─────────────────────────────
cleanup_and_exit() {
    local exit_code=$1
    [ -d "$TMP_DIR" ] && rm -rf "$TMP_DIR"
    exit $exit_code
}

# Set up error handling
trap 'cleanup_and_exit 1' ERR
trap 'cleanup_and_exit 0' INT TERM

# ─── Pre-flight Checks ─────────────────────────────
if ! command -v git &>/dev/null; then
    show_message "$SCRIPT_NAME" "Git is not installed. Please install git first." "error"
    exit 1
fi

if ! command -v rsync &>/dev/null; then
    show_message "$SCRIPT_NAME" "rsync is not installed. Please install rsync first." "error"
    exit 1
fi

# ─── Confirm Update ─────────────────────────────
if ! ask_question "Check for dotfile updates from GitHub and apply if changed?"; then
    show_message "$SCRIPT_NAME" "Update cancelled."
    exit 0
fi

# ─── Clone Repository ─────────────────────────────
echo "[*] Downloading latest dotfiles..."
TMP_DIR=$(mktemp -d)

if ! git clone --depth=1 "$REPO_URL" "$TMP_DIR" 2>/dev/null; then
    show_message "$SCRIPT_NAME" "Failed to clone repository. Check your internet connection and repository URL." "error"
    cleanup_and_exit 1
fi

# ─── Check for Changes ─────────────────────────────
echo "[*] Checking for changes..."

# Create .config directory if it doesn't exist
mkdir -p "$HOME/.config"

# Check if the source directory exists
if [ ! -d "$TMP_DIR/dot_config" ]; then
    show_message "$SCRIPT_NAME" "Repository structure is unexpected. 'dot_config' directory not found." "error"
    cleanup_and_exit 1
fi

# Compare directories (exclude .git and other version control files)
changes=$(diff -qr "$TMP_DIR/dot_config" "$HOME/.config" 2>/dev/null | grep -v -E "\.(git|svn|hg)" || true)

if [ -z "$changes" ]; then
    show_message "$SCRIPT_NAME" "✅ Lavender Dotfiles are up to date."
    cleanup_and_exit 0
fi

# ─── Apply Updates ─────────────────────────────
echo "[*] Changes detected:"
echo "$changes"
echo

if ask_question "⚠️ Changes detected. Update local config?" "$SCRIPT_NAME"; then
    echo "[*] Updating dotfiles..."
    
    # Backup existing config (optional)
    BACKUP_DIR="$HOME/.config_backup_$(date +%Y%m%d_%H%M%S)"
    if ask_question "Create backup of current config in $BACKUP_DIR?"; then
        echo "[*] Creating backup..."
        cp -r "$HOME/.config" "$BACKUP_DIR" 2>/dev/null || true
        echo "[*] Backup created at: $BACKUP_DIR"
    fi
    
    # Update .config directory
    if ! rsync -av --delete "$TMP_DIR/dot_config/" "$HOME/.config/"; then
        show_message "$SCRIPT_NAME" "Failed to update .config directory" "error"
        cleanup_and_exit 1
    fi
    
    # Handle .zshrc if it exists
    if [ -f "$TMP_DIR/dot_config/.zshrc" ]; then
        echo "[*] Updating .zshrc..."
        cp -f "$TMP_DIR/dot_config/.zshrc" "$HOME/.zshrc"
    fi
    
    # Handle .oh-my-zsh if it exists
    if [ -d "$TMP_DIR/dot_config/.oh-my-zsh" ]; then
        echo "[*] Updating .oh-my-zsh..."
        mkdir -p "$HOME/.oh-my-zsh"
        rsync -av "$TMP_DIR/dot_config/.oh-my-zsh/" "$HOME/.oh-my-zsh/"
    fi
    
    show_message "$SCRIPT_NAME" "✅ Lavender Dotfiles updated successfully!"
    
    # ─── Optional: Re-source Shell ─────────────────
    current_shell=$(basename "$SHELL")
    if [ "$current_shell" = "zsh" ] && [ -f "$HOME/.zshrc" ]; then
        if ask_question "Restart zsh to apply changes now?"; then
            echo "[*] Restarting zsh..."
            cleanup_and_exit 0  # Clean up before exec
            exec zsh
        fi
    else
        show_message "$SCRIPT_NAME" "Please restart your terminal session to reload configuration."
    fi
else
    show_message "$SCRIPT_NAME" "Update cancelled."
fi

# Clean up
cleanup_and_exit 0
