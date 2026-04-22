# envm — environment variable manager
# Source this file in your shell rc to define the `envm` function.
# https://github.com/rw3iss/envm

envm() {
    # Resolve .env location: $ENVM_DIR env var > config file > $HOME
    local _envm_config="$HOME/.envm/config"
    local _envm_dir
    if [ -n "${ENVM_DIR:-}" ]; then
        _envm_dir="$ENVM_DIR"
    elif [ -f "$_envm_config" ]; then
        _envm_dir=$(grep '^ENVM_DIR=' "$_envm_config" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'")
    fi
    _envm_dir="${_envm_dir:-$HOME}"
    _envm_dir="${_envm_dir/#\~/$HOME}"
    local _envm_file="$_envm_dir/.env"

    # Colors
    local R=$'\033[0m' C_KEY=$'\033[1;37m' C_VAL=$'\033[38;5;114m'
    local C_OLD=$'\033[38;5;208m' C_DIM=$'\033[2m' C_ERR=$'\033[31m'

    # Ensure .env exists for any read/write operation
    if [ ! -f "$_envm_file" ]; then
        mkdir -p "$_envm_dir" 2>/dev/null
        : > "$_envm_file"
    fi

    # --- Internal helpers ---
    _envm_get() { grep -E "^export $1=" "$_envm_file" 2>/dev/null | sed "s/^export $1=//"; }
    _envm_set() {
        if grep -qE "^export $1=" "$_envm_file" 2>/dev/null; then
            sed -i "s|^export ${1}=.*|export ${1}=${2}|" "$_envm_file"
        else
            echo "export ${1}=${2}" >> "$_envm_file"
        fi
    }

    # --- uninstall ---
    if [ "$1" = "uninstall" ]; then
        printf "Uninstall envm? This removes the command but leaves your .env file intact. [y/N] "
        read -r _confirm
        if [[ ! "$_confirm" =~ ^[Yy]$ ]]; then
            echo "Cancelled."
            return 0
        fi
        # Remove source blocks from shell rc files
        for _rc in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.profile"; do
            [ -f "$_rc" ] && sed -i '/# >>> envm >>>/,/# <<< envm <<</d' "$_rc"
        done
        # Remove install dir (safe: user's .env lives outside this)
        rm -rf "$HOME/.envm"
        unset -f envm 2>/dev/null
        echo "envm uninstalled."
        echo "Reinstall or suggest changes: https://github.com/rw3iss/envm"
        return 0
    fi

    # --- help ---
    if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
        cat <<EOF
envm — environment variable manager

Usage:
  envm                    list all variables
  envm KEY                show value of KEY
  envm KEY VALUE          set KEY=VALUE (prompts if already exists)
  envm -d KEY             delete KEY (prompts)
  envm uninstall          uninstall envm completely
  envm -h                 show this help

Current .env file: $_envm_file
Override at runtime:  ENVM_DIR=/some/path envm ...
Permanent override:   edit $_envm_config

https://github.com/rw3iss/envm
EOF
        return 0
    fi

    # --- no args: list all ---
    if [ $# -eq 0 ]; then
        printf "${C_DIM}%s${R}\n\n" "$_envm_file"
        grep -E '^export [A-Za-z_]' "$_envm_file" 2>/dev/null | while IFS= read -r _line; do
            local _key _val
            _key=$(echo "$_line" | sed 's/^export //; s/=.*//')
            _val=$(echo "$_line" | sed "s/^export ${_key}=//")
            printf "  ${C_KEY}%-35s${R}${C_VAL}%s${R}\n" "$_key" "$_val"
        done
        echo ""
        return 0
    fi

    # --- delete ---
    if [ "$1" = "-d" ]; then
        [ -z "$2" ] && { echo "Usage: envm -d KEY"; return 1; }
        local _existing
        _existing=$(_envm_get "$2")
        [ -z "$_existing" ] && { printf "${C_ERR}Not found: %s${R}\n" "$2"; return 1; }
        printf "Delete ${C_KEY}%s${R}=${C_OLD}%s${R}\n" "$2" "$_existing"
        printf "Confirm? [y/N] "; read -r _confirm
        if [[ "$_confirm" =~ ^[Yy]$ ]]; then
            sed -i "/^export $2=/d" "$_envm_file"
            unset "$2"
            echo "Deleted: $2"
        else
            echo "Cancelled."
        fi
        return 0
    fi

    # --- one arg: show value ---
    if [ $# -eq 1 ]; then
        local _val
        _val=$(_envm_get "$1")
        if [ -n "$_val" ]; then
            printf "${C_KEY}%s${R}=${C_VAL}%s${R}\n" "$1" "$_val"
        else
            printf "${C_ERR}Not found: %s${R}\n" "$1"
            return 1
        fi
        return 0
    fi

    # --- two args: set value ---
    local _key=$1 _val=$2
    local _existing
    _existing=$(_envm_get "$_key")
    if [ -n "$_existing" ]; then
        printf "Current: ${C_KEY}%s${R}=${C_OLD}%s${R}\n" "$_key" "$_existing"
        printf "Replace with '%s'? [y/N] " "$_val"; read -r _confirm
        [[ ! "$_confirm" =~ ^[Yy]$ ]] && { echo "Cancelled."; return 0; }
    fi
    _envm_set "$_key" "$_val"
    # shellcheck disable=SC1090
    source "$_envm_file"
    local _action
    _action=$([ -n "$_existing" ] && echo "Updated" || echo "Added")
    printf "${_action}: ${C_KEY}%s${R}=${C_VAL}%s${R}\n" "$_key" "$_val"
}
