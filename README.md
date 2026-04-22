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
envm load <path>           load a .env file as a new namespace
envm load <path> --as <id> load with an explicit namespace id
envm unload                unload the default namespace
envm unload -e <id>        unload a specific namespace
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

### Safe unload

Unloading only unsets variables whose current shell value still matches what was loaded — if you (or another namespace) overwrote a value, it's skipped:

```bash
$ envm unload -e staging
Unload staging (/home/user/projects/staging/.env)?
Unsets each variable from this namespace only if its current value still matches
what was loaded (overwritten values are skipped). [y/N] y
Unloaded staging: 3 unset (2 skipped — overwritten)
```

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
