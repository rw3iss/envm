# envm — multi-namespace environment variable manager

A zero-dependency shell function for managing **multiple `.env` files** as distinct namespaces — load, unload, list, edit, and resolve conflicts between them, with changes taking effect **live in your current shell**.

- One file, no binaries, no daemons
- Works in `bash` and `zsh`
- Changes apply to the current shell immediately
- Safe unload: only unsets vars that still match their loaded value (won't clobber manual overrides)
- Conflict detection across namespaces with table + per-key resolution
- Namespaces auto-load in every new shell

## Install

One-line install:

```bash
curl -fsSL https://raw.githubusercontent.com/rw3iss/envm/main/scripts/install.sh | bash
```

You'll be prompted for which directory should hold your default `.env` file (default: `~`).

The installer:
1. Downloads `envm.sh` to `~/.envm/envm.sh`
2. Writes your chosen default dir to `~/.envm/config`
3. Adds a `source` line to your shell rc (`~/.zshrc`, `~/.bashrc`, or `~/.profile`)
4. Creates an empty default `.env` if one doesn't exist

Reload your shell, then run `envm`.

## Concepts

- **Namespace** — a named group of env vars backed by one `.env` file. The default namespace is called `default` and maps to `$ENVM_DIR/.env` (or `~/.env` if unset).
- **Loaded** — a namespace whose vars are currently exported into your shell. The loaded list (persisted at `~/.envm/loaded`) is auto-sourced in every new shell.
- **Snapshot** — a copy of each loaded namespace's `.env` taken at load time, stored at `~/.envm/snapshots/<id>.env`. Used for safe unload.

## Commands

```
envm                       list all vars, grouped by namespace
envm -e                    list loaded namespaces
envm -e <id>               list vars in a namespace
envm KEY                   show value from default namespace
envm KEY VALUE             set KEY=VALUE in default namespace
envm -e <id> KEY [VALUE]   show/set in a specific namespace
envm -d KEY                delete KEY from default namespace
envm -d -e <id> KEY        delete KEY from a specific namespace
envm load <file>           load a .env file as a new namespace
envm load <file> --as <id> load with an explicit namespace id
envm unload                unload the default namespace
envm unload -e <id>        unload a specific namespace
envm -f <query>            search keys for <query> across all loaded namespaces
envm -f <query> -e <id>    search keys in a specific namespace
envm -f <query> -v         search values instead of keys (works with -e too)
envm -h                    show help
envm uninstall             uninstall envm
```

## Examples

### Default namespace

```bash
$ envm
[default] /home/user/.env

  GH_TOKEN                   ghp_xxxxxxxxxxxxxxxxxxxxx
  OLLAMA_API_BASE            http://127.0.0.1:11434

$ envm FOO bar
Added in default: FOO=bar

$ envm FOO
FOO=bar

$ envm -d FOO
Delete from default: FOO=bar
Confirm? [y/N] y
Deleted from default: FOO
```

### Loading additional namespaces

```bash
$ envm load ~/projects/staging/.env
Loaded staging from /home/user/projects/staging/.env

$ envm -e
Loaded environments:

  default        /home/user/.env                      (12 vars)
  staging        /home/user/projects/staging/.env     (5 vars)

$ envm -e staging
[staging] /home/user/projects/staging/.env

  DB_HOST                    staging.db.internal
  API_KEY                    xyz789
```

### Searching

Case-insensitive substring match across currently-loaded namespaces. By default it searches **keys**; add `-v` to search **values** instead. Combine with `-e <id>` to scope to one namespace.

```bash
# Find every key containing "token" across all namespaces
$ envm -f token
Searching keys for 'token'

[default] /home/user/.env
  GH_TOKEN                           ghp_xxxxxxxxxxxxxxxxxxxx
  K6_CLOUD_TOKEN                     glc_xxxxxxxxxxxxxxxxxxxx

2 match(es).

# Find values containing "/usr" (e.g., anything pointing at system paths)
$ envm -f /usr -v
Searching values for '/usr'

[default] /home/user/.env
  JAVA_HOME                          /usr/share
  CMAKE_CXX_COMPILER                 /usr/bin/g++

2 match(es).

# Search within a specific namespace only
$ envm -f DB -e staging
```

### Writing to a specific namespace

```bash
$ envm -e staging DB_POOL_SIZE 20
Added in staging: DB_POOL_SIZE=20
```

### Conflict resolution on load

When loading a .env whose keys are already set by another namespace:

```bash
$ envm load ~/projects/prod/.env

Conflicts detected loading 'prod':

  KEY             CURRENT (source)                NEW (prod)
  -------         ----------------                ---
  DB_HOST         staging.db.internal (staging)   prod.db.internal
  API_KEY         xyz789 (staging)                pk_live_abc

  [1] Keep all current values
  [2] Use all new values from prod
  [p] Prompt per-variable
  [c] Cancel load
Choice [p]: p

DB_HOST:
  [1] keep current: staging.db.internal
  [2] use new:      prod.db.internal
Choice [1]: 2

API_KEY:
  [1] keep current: xyz789
  [2] use new:      pk_live_abc
Choice [1]: 1

Loaded prod from /home/user/projects/prod/.env
```

### Safe unload with restore

Unloading walks each variable in the namespace's snapshot and does the right thing based on the current shell value:

| Situation | Action |
|-----------|--------|
| current value ≠ snapshot value | **Skip** — you (or another namespace) overwrote it; don't touch |
| current = snapshot, and another loaded namespace has this key | **Restore** — use the value from the most recently-loaded remaining namespace that has it |
| current = snapshot, and no other namespace has it | **Unset** |

Example stacking behavior:

```
envm load ~/proj-a/.env     # A: KEY=a
envm load ~/proj-b/.env     # B: KEY=b   (shell now has KEY=b)
envm unload -e proj-b       # → restored from A, KEY=a again
envm unload                 # → default had no KEY, so unset
```

Transcript:

```bash
$ envm unload -e staging
Unload staging (/home/user/projects/staging/.env)?
Restores each variable from the most recent remaining namespace that had it,
or unsets if none. Values you overwrote manually are skipped. [y/N] y
Unloaded staging: 2 unset, 3 restored, 1 skipped (overwritten)
```

The order of restore lookup comes directly from `~/.envm/loaded` — later entries are newer, and we walk bottom-up when searching for a previous owner.

### Unknown namespace

```bash
$ envm -e nonexistent
Namespace not loaded: nonexistent

Loaded namespaces:
  default
  staging
```

## Where are things stored?

| Path | Purpose |
|------|---------|
| `~/.envm/config` | Default `ENVM_DIR` setting |
| `~/.envm/loaded` | TSV of currently-registered namespaces (`id\tpath`) |
| `~/.envm/snapshots/<id>.env` | Copy of each namespace's .env at load time |
| `$ENVM_DIR/.env` | The default namespace's actual .env file |

## Config

Three ways to set where the default `.env` lives — listed in override order (first wins):

| Method | Scope | How |
|--------|-------|-----|
| `ENVM_DIR` env var | Per-call / per-session | `ENVM_DIR=/tmp envm ...` |
| `~/.envm/config` | Persistent | Edit `ENVM_DIR="..."` |
| Installer prompt | Initial setup | Answer at install time |

## Uninstall

```bash
envm uninstall
```

- Removes the source block from your shell rc (`~/.zshrc`, `~/.bashrc`, or `~/.profile`)
- Deletes `~/.envm/` (including the loaded list and all snapshots)
- Unsets the `envm` function in the current shell

**Your actual `.env` files are left intact** — those are your data, owned by you.

## Manual / development install

```bash
git clone git@github.com:rw3iss/envm.git ~/Sites/tools/envm
echo 'source ~/Sites/tools/envm/envm.sh' >> ~/.zshrc
```

## License

MIT
