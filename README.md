# envm — environment variable manager

A tiny zero-dependency shell function for listing, reading, adding, updating, and deleting environment variables in a single `.env` file — with changes taking effect **live in your current shell**.

- One file, no binaries, no daemons
- Works in `bash` and `zsh`
- Changes apply to the current shell immediately (no need to re-source)
- Delete and unset in one step
- Colored, aligned output

## Install

One-line install:

```bash
curl -fsSL https://raw.githubusercontent.com/rw3iss/envm/main/scripts/install.sh | bash
```

You'll be prompted for which directory should hold your `.env` file (default: `~`).

The installer:

1. Downloads `envm.sh` to `~/.envm/envm.sh`
2. Writes a config to `~/.envm/config` with your chosen directory
3. Creates an empty `.env` in that directory if one doesn't exist
4. Adds a `source` line to your shell rc (`~/.zshrc`, `~/.bashrc`, or `~/.profile`)

Then reload your shell (or open a new terminal) and run `envm`.

## Usage

```
envm                    list all variables
envm KEY                show value of KEY
envm KEY VALUE          set KEY=VALUE (prompts to confirm if exists)
envm -d KEY             delete KEY (prompts)
envm uninstall          uninstall envm completely
envm -h                 show help
```

### Examples

```bash
# List all vars
$ envm
/home/user/.env

  GH_TOKEN                            ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
  OLLAMA_API_BASE                     http://127.0.0.1:11434
  JAVA_HOME                           /usr/share

# Read one
$ envm GH_TOKEN
GH_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx

# Add a new var — live in current shell immediately
$ envm MY_API_KEY abc123
Added: MY_API_KEY=abc123
$ echo $MY_API_KEY
abc123

# Update an existing var
$ envm GH_TOKEN ghp_newtoken
Current: GH_TOKEN=ghp_oldtoken
Replace with 'ghp_newtoken'? [y/N] y
Updated: GH_TOKEN=ghp_newtoken

# Delete
$ envm -d MY_API_KEY
Delete MY_API_KEY=abc123
Confirm? [y/N] y
Deleted: MY_API_KEY
```

## Where does it store variables?

By default, `~/.env`. You can change this three ways:

| Method | Scope | How |
|--------|-------|-----|
| Installer prompt | Persistent | Answer the prompt at install time |
| Config file | Persistent | Edit `ENVM_DIR=...` in `~/.envm/config` |
| Env var | Per-session / per-call | `ENVM_DIR=/some/path envm ...` |

Env var override wins over the config file.

## Uninstall

```bash
envm uninstall
```

This:

- Removes the source block from your shell rc (`~/.zshrc`, `~/.bashrc`, `~/.profile`)
- Deletes `~/.envm/`
- Unsets the `envm` function in the current shell

**Your `.env` file is left intact** — that's your data.

## How it works

- The `envm` function is defined in `envm.sh` and sourced into your shell rc
- Runs **in your current shell context** (not a subprocess), so `export` and `unset` take effect immediately
- All reads use `grep` on the `.env` file directly
- All writes use `sed -i` for in-place editing
- After every write, the `.env` is `source`d automatically

## Manual / development install

```bash
git clone git@github.com:rw3iss/envm.git ~/Sites/tools/envm
echo 'source ~/Sites/tools/envm/envm.sh' >> ~/.zshrc
```

## License

MIT
