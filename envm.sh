# envm — multi-namespace environment variable manager
# Source this file in your shell rc to define the `envm` function.
# https://github.com/rw3iss/envm

# Ensure core GNU utilities (grep, sed, awk, cut, tr) are reachable even if
# the user's PATH has been mangled or the shell's command hash is stale.
case ":$PATH:" in *:/usr/bin:*) ;; *) PATH="/usr/bin:$PATH" ;; esac
case ":$PATH:" in *:/bin:*)     ;; *) PATH="/bin:$PATH"     ;; esac
export PATH

# ---------- Setup (called on every invocation) ----------
_envm_setup() {
    # Rebuild command hash table in case it's stale from a previous shell state
    if [ -n "$ZSH_VERSION" ]; then
        rehash 2>/dev/null
    else
        hash -r 2>/dev/null
    fi
    # Pure-shell config parse (no grep/head/cut/tr) so bootstrap works even if
    # coreutils aren't reachable on startup.
    local config="$HOME/.envm/config"
    local dir=""
    if [ -n "${ENVM_DIR:-}" ]; then
        dir="$ENVM_DIR"
    elif [ -f "$config" ]; then
        local _l
        while IFS= read -r _l; do
            case "$_l" in
                'ENVM_DIR='*)
                    dir="${_l#ENVM_DIR=}"
                    dir="${dir#\"}"; dir="${dir%\"}"
                    dir="${dir#\'}"; dir="${dir%\'}"
                    break
                    ;;
            esac
        done < "$config"
    fi
    _ENVM_DIR="${dir:-$HOME}"
    _ENVM_DIR="${_ENVM_DIR/#\~/$HOME}"
    _ENVM_FILE="$_ENVM_DIR/.env"
    _ENVM_STATE="$HOME/.envm"
    _ENVM_LOADED="$_ENVM_STATE/loaded"
    _ENVM_SNAPSHOTS="$_ENVM_STATE/snapshots"
    # Only try to create dirs if mkdir is reachable (usually pre-existing anyway)
    if [ ! -d "$_ENVM_STATE" ] || [ ! -d "$_ENVM_SNAPSHOTS" ]; then
        command -v mkdir >/dev/null 2>&1 && mkdir -p "$_ENVM_STATE" "$_ENVM_SNAPSHOTS" 2>/dev/null
    fi
    [ ! -f "$_ENVM_LOADED" ] && : > "$_ENVM_LOADED" 2>/dev/null

    # Colors
    R=$'\033[0m'
    C_KEY=$'\033[1;37m'
    C_VAL=$'\033[38;5;114m'
    C_OLD=$'\033[38;5;208m'
    C_NEW=$'\033[38;5;42m'
    C_DIM=$'\033[2m'
    C_ERR=$'\033[31m'
    C_NS=$'\033[1;34m'
}

# ---------- Namespace registry helpers (pure-shell — no coreutils needed) ----------
# These run in the bootstrap path, so they must not depend on grep/awk/sed/mv/rm
# in case the user's PATH is temporarily missing /usr/bin on shell start.
_envm_ns_exists() {
    [ -f "$_ENVM_LOADED" ] || return 1
    local _l
    while IFS= read -r _l; do
        [ "${_l%%	*}" = "$1" ] && return 0
    done < "$_ENVM_LOADED"
    return 1
}
_envm_ns_path() {
    [ -f "$_ENVM_LOADED" ] || return
    local _l
    while IFS= read -r _l; do
        if [ "${_l%%	*}" = "$1" ]; then
            printf '%s\n' "${_l#*	}"
            return
        fi
    done < "$_ENVM_LOADED"
}
_envm_ns_ids() {
    [ -f "$_ENVM_LOADED" ] || return
    local _l
    while IFS= read -r _l; do
        [ -z "$_l" ] && continue
        printf '%s\n' "${_l%%	*}"
    done < "$_ENVM_LOADED"
}
_envm_ns_add() {
    _envm_ns_remove "$1"
    printf '%s\t%s\n' "$1" "$2" >> "$_ENVM_LOADED"
}
_envm_ns_remove() {
    [ -f "$_ENVM_LOADED" ] || return
    local _l _content=""
    while IFS= read -r _l; do
        [ -z "$_l" ] && continue
        [ "${_l%%	*}" = "$1" ] && continue
        _content="${_content}${_l}
"
    done < "$_ENVM_LOADED"
    printf '%s' "$_content" > "$_ENVM_LOADED"
}

_envm_infer_id() {
    local path="$1"
    local abs
    abs=$(cd "$(dirname "$path")" 2>/dev/null && pwd)/$(basename "$path")
    # If this is the default ENVM_DIR/.env, always use "default"
    if [ "$abs" = "$_ENVM_FILE" ]; then
        echo "default"; return
    fi
    local base
    base=$(basename "$path")
    if [ "$base" = ".env" ]; then
        basename "$(cd "$(dirname "$path")" 2>/dev/null && pwd)"
    else
        echo "${base%.env}"
    fi
}

# Pure-shell file copy (no cp needed on bootstrap path)
_envm_snapshot_save() {
    [ -f "$2" ] || return
    local _l
    : > "$_ENVM_SNAPSHOTS/$1.env"
    while IFS= read -r _l || [ -n "$_l" ]; do
        printf '%s\n' "$_l" >> "$_ENVM_SNAPSHOTS/$1.env"
    done < "$2"
}
_envm_snapshot_file() { printf '%s\n' "$_ENVM_SNAPSHOTS/$1.env"; }

# ---------- File parsing ----------
# Output lines of KEY=VALUE (strips the "export " prefix).
_envm_parse() {
    grep -E '^export [A-Za-z_][A-Za-z0-9_]*=' "$1" 2>/dev/null | sed 's/^export //'
}
_envm_file_get() {
    grep -E "^export $1=" "$2" 2>/dev/null | head -1 | sed "s/^export $1=//"
}
_envm_k() { echo "$1" | sed 's/=.*//'; }
_envm_v() { local l="$1"; local k; k=$(_envm_k "$l"); echo "${l#${k}=}"; }

# Portable "get current shell value" / "check if set"
_envm_cur()    { eval "printf '%s' \"\${$1-}\""; }
_envm_is_set() { eval "[ -n \"\${$1+x}\" ]"; }

# Apply KEY=VALUE to current shell
_envm_export() { export "$1=$2"; }

# ---------- List operations ----------
_envm_list_all() {
    if [ ! -s "$_ENVM_LOADED" ]; then
        printf "${C_DIM}No environments loaded.${R}\n"
        return
    fi
    while IFS=$'\t' read -r id path; do
        [ -z "$id" ] && continue
        printf "${C_NS}[%s]${R} ${C_DIM}%s${R}\n" "$id" "$path"
        if [ -f "$path" ]; then
            while IFS= read -r line; do
                local k v
                k=$(_envm_k "$line"); v=$(_envm_v "$line")
                printf "  ${C_KEY}%-35s${R}${C_VAL}%s${R}\n" "$k" "$v"
            done < <(_envm_parse "$path")
        else
            printf "  ${C_ERR}(file missing)${R}\n"
        fi
        echo ""
    done < "$_ENVM_LOADED"
}

_envm_list_namespaces() {
    printf "${C_DIM}Loaded environments:${R}\n\n"
    if [ ! -s "$_ENVM_LOADED" ]; then
        echo "  (none)"
        return
    fi
    while IFS=$'\t' read -r id path; do
        [ -z "$id" ] && continue
        local count=0
        [ -f "$path" ] && count=$(_envm_parse "$path" | wc -l | tr -d ' ')
        printf "  ${C_NS}%-15s${R} ${C_DIM}%s${R}  (%s vars)\n" "$id" "$path" "$count"
    done < "$_ENVM_LOADED"
    echo ""
}

_envm_list_ns_vars() {
    local id="$1"
    if ! _envm_ns_exists "$id"; then
        _envm_err_unknown_ns "$id"; return 1
    fi
    local path
    path=$(_envm_ns_path "$id")
    printf "${C_NS}[%s]${R} ${C_DIM}%s${R}\n\n" "$id" "$path"
    if [ -f "$path" ]; then
        while IFS= read -r line; do
            local k v
            k=$(_envm_k "$line"); v=$(_envm_v "$line")
            printf "  ${C_KEY}%-35s${R}${C_VAL}%s${R}\n" "$k" "$v"
        done < <(_envm_parse "$path")
    fi
    echo ""
}

_envm_err_unknown_ns() {
    printf "${C_ERR}Namespace not loaded: %s${R}\n\n" "$1"
    echo "Loaded namespaces:"
    _envm_ns_ids | while read -r i; do echo "  $i"; done
}

# ---------- Conflict detection & load ----------
# Emits tab-separated lines: KEY\tCURRENT_VALUE\tSOURCE_NS\tNEW_VALUE
_envm_detect_conflicts() {
    local new_file="$1" new_id="$2"
    local line key new_val cur_val src_ns snap snap_val id
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        key=$(_envm_k "$line"); new_val=$(_envm_v "$line")
        _envm_is_set "$key" || continue
        cur_val=$(_envm_cur "$key")
        [ "$cur_val" = "$new_val" ] && continue
        src_ns="shell"
        while IFS= read -r id; do
            [ -z "$id" ] || [ "$id" = "$new_id" ] && continue
            snap=$(_envm_snapshot_file "$id")
            [ -f "$snap" ] || continue
            snap_val=$(_envm_file_get "$key" "$snap")
            if [ "$snap_val" = "$cur_val" ]; then src_ns="$id"; break; fi
        done < <(_envm_ns_ids)
        printf "%s\t%s\t%s\t%s\n" "$key" "$cur_val" "$src_ns" "$new_val"
    done < <(_envm_parse "$new_file")
}

_envm_load() {
    local path="" id=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --as) id="$2"; shift 2 ;;
            -*)   printf "${C_ERR}Unknown flag: %s${R}\n" "$1"; return 1 ;;
            *)    [ -z "$path" ] && path="$1" || { echo "Extra arg: $1"; return 1; }; shift ;;
        esac
    done
    [ -z "$path" ] && { echo "Usage: envm load <path> [--as <id>]"; return 1; }
    [ -f "$path" ] || { printf "${C_ERR}File not found: %s${R}\n" "$path"; return 1; }

    path=$(cd "$(dirname "$path")" 2>/dev/null && pwd)/$(basename "$path")
    [ -z "$id" ] && id=$(_envm_infer_id "$path")

    if _envm_ns_exists "$id"; then
        printf "Namespace ${C_NS}%s${R} already loaded. Reload? [y/N] " "$id"
        read -r _c; [[ ! "$_c" =~ ^[Yy]$ ]] && { echo "Cancelled."; return 0; }
    fi

    local conflicts
    conflicts=$(_envm_detect_conflicts "$path" "$id")
    local resolution="new"

    if [ -n "$conflicts" ]; then
        echo ""
        printf "${C_DIM}Conflicts detected loading '${C_NS}%s${C_DIM}':${R}\n\n" "$id"
        printf "  ${C_KEY}%-20s${R}  ${C_OLD}%-34s${R}  ${C_NEW}%s${R}\n" "KEY" "CURRENT (source)" "NEW ($id)"
        printf "  ${C_DIM}%-20s  %-34s  %s${R}\n" "-------" "----------------" "---"
        while IFS=$'\t' read -r k cv src nv; do
            local cd="$cv (${src})"
            printf "  ${C_KEY}%-20s${R}  ${C_OLD}%-34s${R}  ${C_NEW}%s${R}\n" "$k" "$cd" "$nv"
        done <<< "$conflicts"
        echo ""
        echo "  [1] Keep all current values"
        echo "  [2] Use all new values from $id"
        echo "  [p] Prompt per-variable"
        echo "  [c] Cancel load"
        printf "Choice [p]: "
        read -r ch
        case "$ch" in
            1)       resolution="current" ;;
            2)       resolution="new" ;;
            c|C)     echo "Cancelled."; return 0 ;;
            p|P|"")  resolution="prompt" ;;
        esac
    fi

    # Apply
    local line key val conf cur
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        key=$(_envm_k "$line"); val=$(_envm_v "$line")
        conf=""
        [ -n "$conflicts" ] && conf=$(echo "$conflicts" | awk -F'\t' -v k="$key" '$1==k {print; exit}')

        if [ -n "$conf" ]; then
            case "$resolution" in
                current) : ;;
                new)     _envm_export "$key" "$val" ;;
                prompt)
                    cur=$(echo "$conf" | cut -f2)
                    printf "\n${C_KEY}%s${R}:\n  [1] keep current: ${C_OLD}%s${R}\n  [2] use new:      ${C_NEW}%s${R}\nChoice [1]: " "$key" "$cur" "$val"
                    read -r pc
                    [[ "$pc" = "2" ]] && _envm_export "$key" "$val"
                    ;;
            esac
        else
            _envm_export "$key" "$val"
        fi
    done < <(_envm_parse "$path")

    _envm_snapshot_save "$id" "$path"
    _envm_ns_add "$id" "$path"
    printf "\n${C_NEW}Loaded${R} ${C_NS}%s${R} from %s\n" "$id" "$path"
}

# ---------- Unload ----------
# For each var in the unloading namespace's snapshot:
#   - current value != snapshot value  → skip (overwritten, don't touch)
#   - current value == snapshot value, and another loaded namespace has this
#     key in its snapshot → restore that value (walk loaded list in reverse,
#     excluding self; first match wins)
#   - current value == snapshot value, and nothing else has it → unset
_envm_unload() {
    local id="${1:-default}"
    if ! _envm_ns_exists "$id"; then
        _envm_err_unknown_ns "$id"; return 1
    fi
    local path snap
    path=$(_envm_ns_path "$id")
    snap=$(_envm_snapshot_file "$id")

    printf "Unload ${C_NS}%s${R} (%s)?\n" "$id" "$path"
    printf "Restores each variable from the most recent remaining namespace that had it,\nor unsets if none. Values you overwrote manually are skipped. [y/N] "
    read -r c; [[ ! "$c" =~ ^[Yy]$ ]] && { echo "Cancelled."; return 0; }

    local unset_n=0 skip_n=0 restore_n=0 line key val cur
    if [ -f "$snap" ]; then
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            key=$(_envm_k "$line"); val=$(_envm_v "$line")
            _envm_is_set "$key" || continue
            cur=$(_envm_cur "$key")
            if [ "$cur" != "$val" ]; then
                skip_n=$((skip_n+1))
                continue
            fi
            # Current value is ours — look for a previous owner to restore from.
            # Walk loaded list in reverse (awk for portability), excluding self.
            local restored=false prev_id prev_path prev_snap prev_val
            while IFS=$'\t' read -r prev_id prev_path; do
                [ -z "$prev_id" ] || [ "$prev_id" = "$id" ] && continue
                prev_snap=$(_envm_snapshot_file "$prev_id")
                [ -f "$prev_snap" ] || continue
                prev_val=$(_envm_file_get "$key" "$prev_snap")
                if [ -n "$prev_val" ]; then
                    _envm_export "$key" "$prev_val"
                    restored=true
                    break
                fi
            done < <(awk '{a[NR]=$0} END{for(i=NR;i>0;i--) print a[i]}' "$_ENVM_LOADED")
            if $restored; then
                restore_n=$((restore_n+1))
            else
                unset "$key"
                unset_n=$((unset_n+1))
            fi
        done < <(_envm_parse "$snap")
    fi
    _envm_ns_remove "$id"
    rm -f "$snap"
    printf "Unloaded ${C_NS}%s${R}: %d unset" "$id" "$unset_n"
    [ "$restore_n" -gt 0 ] && printf ", %d restored" "$restore_n"
    [ "$skip_n"    -gt 0 ] && printf ", %d skipped (overwritten)" "$skip_n"
    echo ""
}

# ---------- Individual key operations ----------
_envm_show() {
    local key="$1" ns="$2"
    if [ -n "$ns" ]; then
        _envm_ns_exists "$ns" || { _envm_err_unknown_ns "$ns"; return 1; }
        local path val
        path=$(_envm_ns_path "$ns")
        val=$(_envm_file_get "$key" "$path")
        if [ -n "$val" ]; then
            printf "${C_NS}[%s]${R} ${C_KEY}%s${R}=${C_VAL}%s${R}\n" "$ns" "$key" "$val"
        else
            printf "${C_ERR}Not found in %s: %s${R}\n" "$ns" "$key"; return 1
        fi
    else
        local val
        val=$(_envm_file_get "$key" "$_ENVM_FILE")
        if [ -n "$val" ]; then
            printf "${C_KEY}%s${R}=${C_VAL}%s${R}\n" "$key" "$val"
        else
            printf "${C_ERR}Not found: %s${R}\n" "$key"; return 1
        fi
    fi
}

_envm_set() {
    local key="$1" val="$2" ns="$3"
    local path resolved_ns
    if [ -n "$ns" ]; then
        _envm_ns_exists "$ns" || { _envm_err_unknown_ns "$ns"; return 1; }
        path=$(_envm_ns_path "$ns"); resolved_ns="$ns"
    else
        path="$_ENVM_FILE"
        [ ! -f "$path" ] && { mkdir -p "$(dirname "$path")"; : > "$path"; }
        resolved_ns="default"
        _envm_ns_exists "$resolved_ns" || _envm_ns_add "$resolved_ns" "$path"
    fi

    local existing
    existing=$(_envm_file_get "$key" "$path")
    if [ -n "$existing" ]; then
        printf "Current in ${C_NS}%s${R}: ${C_KEY}%s${R}=${C_OLD}%s${R}\n" "$resolved_ns" "$key" "$existing"
        printf "Replace with '%s'? [y/N] " "$val"
        read -r c; [[ ! "$c" =~ ^[Yy]$ ]] && { echo "Cancelled."; return 0; }
        sed -i "s|^export ${key}=.*|export ${key}=${val}|" "$path"
    else
        echo "export ${key}=${val}" >> "$path"
    fi
    _envm_snapshot_save "$resolved_ns" "$path"
    _envm_export "$key" "$val"
    local action="Added"
    [ -n "$existing" ] && action="Updated"
    printf "${action} in ${C_NS}%s${R}: ${C_KEY}%s${R}=${C_VAL}%s${R}\n" "$resolved_ns" "$key" "$val"
}

_envm_delete() {
    local key="$1" ns="$2"
    local path resolved_ns
    if [ -n "$ns" ]; then
        _envm_ns_exists "$ns" || { _envm_err_unknown_ns "$ns"; return 1; }
        path=$(_envm_ns_path "$ns"); resolved_ns="$ns"
    else
        path="$_ENVM_FILE"; resolved_ns="default"
    fi
    local existing
    existing=$(_envm_file_get "$key" "$path")
    if [ -z "$existing" ]; then
        printf "${C_ERR}Not found in %s: %s${R}\n" "$resolved_ns" "$key"; return 1
    fi
    printf "Delete from ${C_NS}%s${R}: ${C_KEY}%s${R}=${C_OLD}%s${R}\n" "$resolved_ns" "$key" "$existing"
    printf "Confirm? [y/N] "
    read -r c
    if [[ "$c" =~ ^[Yy]$ ]]; then
        sed -i "/^export $key=/d" "$path"
        _envm_snapshot_save "$resolved_ns" "$path"
        unset "$key"
        printf "Deleted from %s: %s\n" "$resolved_ns" "$key"
    else
        echo "Cancelled."
    fi
}

# ---------- Help / Uninstall ----------
_envm_help() {
    cat <<EOF
envm — multi-namespace environment variable manager

  envm                       list all vars, grouped by namespace
  envm -e                    list loaded namespaces
  envm -e <id>               list vars in a namespace
  envm KEY                   show value from default namespace
  envm KEY VALUE             set KEY=VALUE in default namespace
  envm -e <id> KEY [VALUE]   show/set in a specific namespace
  envm -d KEY                delete KEY from default namespace
  envm -d -e <id> KEY        delete KEY from a specific namespace
  envm load <path>           load a .env file as a new namespace
  envm load <path> --as <id> load with an explicit namespace id
  envm unload                unload the default namespace
  envm unload -e <id>        unload a specific namespace
  envm -h                    show this help
  envm uninstall             uninstall envm

Default .env:   $_ENVM_FILE
State dir:      $_ENVM_STATE
Override dir:   ENVM_DIR=/some/path envm ...

https://github.com/rw3iss/envm
EOF
}

_envm_uninstall() {
    printf "Uninstall envm? This removes the command and state; your .env files stay intact. [y/N] "
    read -r c; [[ ! "$c" =~ ^[Yy]$ ]] && { echo "Cancelled."; return 0; }
    for rc in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.profile"; do
        [ -f "$rc" ] && sed -i '/# >>> envm >>>/,/# <<< envm <<</d' "$rc"
    done
    rm -rf "$HOME/.envm"
    unset -f envm 2>/dev/null
    echo "envm uninstalled."
    echo "Reinstall or suggest changes: https://github.com/rw3iss/envm"
}

# ---------- Main dispatcher ----------
envm() {
    _envm_setup

    # Bare `envm -e` -> list namespaces
    if [ "$1" = "-e" ] && [ $# -eq 1 ]; then
        _envm_list_namespaces; return
    fi

    # Extract -e <id> (anywhere in the arg list)
    local _ns="" _args=()
    while [ $# -gt 0 ]; do
        if [ "$1" = "-e" ] && [ $# -ge 2 ] && [ "${2:0:1}" != "-" ]; then
            _ns="$2"; shift 2
        else
            _args+=("$1"); shift
        fi
    done
    if [ "${#_args[@]}" -gt 0 ]; then set -- "${_args[@]}"; else set --; fi

    case "$1" in
        uninstall) _envm_uninstall ;;
        -h|--help) _envm_help ;;
        load)      shift; _envm_load "$@" ;;
        unload)    _envm_unload "$_ns" ;;
        -d)        [ -z "$2" ] && { echo "Usage: envm -d KEY [-e <id>]"; return 1; }
                   _envm_delete "$2" "$_ns" ;;
        "")        if [ -n "$_ns" ]; then _envm_list_ns_vars "$_ns"
                   else _envm_list_all; fi ;;
        *)         if [ $# -eq 1 ]; then _envm_show "$1" "$_ns"
                   else _envm_set "$1" "$2" "$_ns"; fi ;;
    esac
}

# ---------- Auto-source registered namespaces on shell start ----------
_envm_bootstrap() {
    _envm_setup
    # Register default namespace if loaded file is empty and .env exists
    if [ ! -s "$_ENVM_LOADED" ] && [ -f "$_ENVM_FILE" ]; then
        _envm_ns_add "default" "$_ENVM_FILE"
        _envm_snapshot_save "default" "$_ENVM_FILE"
    fi
    # Source each registered namespace's file
    if [ -s "$_ENVM_LOADED" ]; then
        local id path
        while IFS=$'\t' read -r id path; do
            [ -z "$id" ] && continue
            # shellcheck disable=SC1090
            [ -f "$path" ] && . "$path" 2>/dev/null
        done < "$_ENVM_LOADED"
    fi
    # Prune orphan snapshots — skip silently if rm isn't reachable
    if command -v rm >/dev/null 2>&1 && [ -d "$_ENVM_SNAPSHOTS" ]; then
        local snap snap_id
        for snap in "$_ENVM_SNAPSHOTS"/*.env; do
            [ -f "$snap" ] || continue
            snap_id="${snap##*/}"       # pure-shell basename
            snap_id="${snap_id%.env}"   # strip .env suffix
            _envm_ns_exists "$snap_id" || rm -f "$snap" 2>/dev/null
        done
    fi
}
_envm_bootstrap
