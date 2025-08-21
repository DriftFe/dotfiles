# ─── Clone and Apply Dotfiles ─────────────────────────────
echo "[*] Downloading Lavender Dotfiles..."
TMP_DIR=$(mktemp -d)

if ! git clone --depth=1 "$REPO_URL" "$TMP_DIR"; then
    show_message "$SCRIPT_NAME" "Failed to clone repository. Check your internet connection." "error"
    cleanup_and_exit 1
fi

if [ ! -d "$TMP_DIR/dot_config" ]; then
    show_message "$SCRIPT_NAME" "Repository structure is unexpected. 'dot_config' directory not found." "error"
    cleanup_and_exit 1
fi

echo "[*] Applying Lavender Dotfiles..."
mkdir -p ~/.config

# Apply configs
if ! rsync -av "$TMP_DIR/dot_config/" ~/.config/; then
    show_message "$SCRIPT_NAME" "Failed to copy configuration files." "error"
    cleanup_and_exit 1
fi

# Copy wallpapers if present
if [ -d "$TMP_DIR/wallpapers" ]; then
    echo "[*] Copying wallpapers..."
    mkdir -p ~/.wallpapers
    rsync -av "$TMP_DIR/wallpapers/" ~/.wallpapers/
fi
