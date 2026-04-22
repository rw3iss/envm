#!/usr/bin/env bash
# envm installer
# One-line install:
#   curl -fsSL https://raw.githubusercontent.com/rw3iss/envm/main/scripts/install.sh | bash

set -e

REPO_URL="https://github.com/rw3iss/envm"
RAW_URL="https://raw.githubusercontent.com/rw3iss/envm/main"
INSTALL_DIR="$HOME/.envm"
ENVM_SCRIPT="$INSTALL_DIR/envm.sh"
CONFIG_FILE="$INSTALL_DIR/config"

echo "Installing envm from $REPO_URL"
echo

# Prompt for .env directory (curl|bash loses stdin; read from /dev/tty)
DEFAULT_DIR="$HOME"
if [ -r /dev/tty ]; then
    printf "Where should envm look for / create your .env file? [%s] " "$DEFAULT_DIR"
    read -r ENV_DIR </dev/tty || ENV_DIR=""
else
    ENV_DIR=""
fi
ENV_DIR="${ENV_DIR:-$DEFAULT_DIR}"
ENV_DIR="${ENV_DIR/#\~/$HOME}"

mkdir -p "$INSTALL_DIR"

# Download envm.sh from the repo
if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$RAW_URL/envm.sh" -o "$ENVM_SCRIPT"
elif command -v wget >/dev/null 2>&1; then
    wget -q "$RAW_URL/envm.sh" -O "$ENVM_SCRIPT"
else
    echo "Error: curl or wget required" >&2
    exit 1
fi

# Save config
cat > "$CONFIG_FILE" <<EOF
# envm configuration
ENVM_DIR="$ENV_DIR"
EOF

# Ensure the .env file exists at the chosen location
mkdir -p "$ENV_DIR"
[ ! -f "$ENV_DIR/.env" ] && : > "$ENV_DIR/.env"

# Pick shell rc file to update
SHELL_NAME=$(basename "${SHELL:-zsh}")
case "$SHELL_NAME" in
    zsh)  RC_FILE="$HOME/.zshrc" ;;
    bash) RC_FILE="$HOME/.bashrc" ;;
    *)    RC_FILE="$HOME/.profile" ;;
esac

# Add sourcing block (delimited so uninstall can find/remove it cleanly)
if ! grep -q "envm/envm.sh" "$RC_FILE" 2>/dev/null; then
    cat >> "$RC_FILE" <<EOF

# >>> envm >>>
source "$ENVM_SCRIPT"
# <<< envm <<<
EOF
fi

echo
echo "✓ envm installed"
echo "    Script:   $ENVM_SCRIPT"
echo "    Config:   $CONFIG_FILE"
echo "    .env:     $ENV_DIR/.env"
echo "    Shell rc: $RC_FILE"
echo
echo "Reload your shell (or open a new terminal), then try:"
echo "    envm         # list variables"
echo "    envm -h      # help"
