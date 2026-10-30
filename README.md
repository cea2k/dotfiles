# dotfiles

Personal environment managed with [chezmoi](https://www.chezmoi.io/): config files, system packages, runtimes, fonts and secrets. A new machine is usable with one command.

## Daily use

chezmoi keeps a copy of every managed file in its repo (`~/.local/share/chezmoi`). Commands work from any directory, and paths are the real ones in your home.

### Plain files (most configs)

Edit them normally, then save the change back to the repo:

```bash
nvim ~/.tmux.conf
chezmoi re-add                 # copy your edits into the repo
```

### Templates (`.zshrc`, `.gitconfig`)

These are generated per machine, so edit the template, never the real file (`apply` would overwrite it):

```bash
chezmoi edit --apply ~/.zshrc  # alias: cze ~/.zshrc
```

`chezmoi re-add` skips templates. If you edited the real file by mistake, run `chezmoi merge ~/.zshrc`.

### Common commands

| Task | Command |
|---|---|
| Track a new file or folder | `chezmoi add ~/.config/foo` |
| Track a secret file (encrypted) | `chezmoi add --encrypt ~/.config/foo/token` |
| Home vs repo out of sync? | `chezmoi status` (short), `chezmoi diff` (full) |
| Uncommitted repo changes? | `chezmoi git -- status` |
| Commit and push | `chezmoi git -- add -A`, then `chezmoi git -- commit -m "msg"`, then `chezmoi git -- push` |
| Get changes from GitHub | `chezmoi update` (git pull, then apply) |
| Write repo state to home | `chezmoi apply` (local only, no git) |
| Stop tracking a file | `chezmoi forget ~/.config/foo` (the file itself stays) |
| Secret changed in Bitwarden | `rbw sync && chezmoi apply` |

`chezmoi status` compares repo and home, not git. Empty output only means they match, not that everything is pushed.

### Adding software

Don't `dnf install` something you want to keep without recording it:

1. `chezmoi cd`, edit `.chezmoidata/packages.yaml`, then `exit`.
2. `chezmoi apply`. The install script re-runs because the list changed.
3. Commit and push.

COPR goes under `copr:`, third-party `.repo` URLs under `repos:`, Flatpak app IDs under `flatpak:`. Global runtimes go in `~/.config/mise/config.toml`, and project runtimes in each project's `mise.toml`. Anything you would otherwise `curl` or `git clone` by hand (scripts, plugins, fonts) goes in `.chezmoiexternal.toml.tmpl`.

### Catching drift

```bash
dotfiles-drift
```

This lists dnf packages installed by hand but not in `packages.yaml` (ignoring what was installed before the first apply), declared packages that are missing, undeclared Flatpaks, and config changes not yet in the repo. Run it weekly.

---

## How it works

| Concern | Mechanism |
|---|---|
| Config files | chezmoi source files (`dot_*`, `private_dot_config/...`) |
| Per-machine differences | answers given at `chezmoi init` (role, Bitwarden) |
| System packages, COPR, repos, Flatpak | `.chezmoidata/packages.yaml` + `run_onchange_` scripts |
| Downloaded files (fzf-preview, tpm, catppuccin, fonts) | `.chezmoiexternal.toml.tmpl` |
| Tmux plugins | TPM, installed automatically when `.tmux.conf` changes |
| Runtimes (node, pnpm...) | mise |
| Env-var secrets | Bitwarden item `dotfiles-env`, read through `rbw` |
| Secret files | age-encrypted files in this repo (`encrypted_*`) |
| SSH keys | Bitwarden desktop SSH agent. Keys are never stored here. |

### Roles

| Role | Machine | Desktop configs, fonts | Bitwarden secrets | Packages |
|---|---|---|---|---|
| `laptop` | Yoga Pro 7, Fedora | yes | asked, default yes | dnf + COPR + Flatpak + mise |
| `test` | old HP, Fedora | yes | asked, default no | dnf + COPR + Flatpak + mise |
| `server` | Hostinger VPS, Ubuntu | no | never | apt (user tools only) |

Answers are stored in `~/.config/chezmoi/chezmoi.toml`. Check them with:

```bash
chezmoi execute-template 'role={{ .role }} bitwarden={{ .bitwarden }}'
```

To change one, edit the `[data]` section of that file and run `chezmoi init && chezmoi apply`. `chezmoi init` regenerates that file from `.chezmoi.toml.tmpl` and keeps existing answers; it never touches your home files. Don't hand-edit settings outside `[data]` there, as `init` overwrites them. Put them in `.chezmoi.toml.tmpl` instead.

### Repo layout

```
.chezmoi.toml.tmpl            # prompts (role, git identity, Bitwarden), age + hook config
.install-prereqs.sh           # hook: installs rbw/age before templates render
.chezmoiignore                # what each role skips
.chezmoidata/packages.yaml    # all packages, single source of truth
.chezmoiexternal.toml.tmpl    # downloaded files: fzf-preview, tpm, catppuccin, fonts
.chezmoiscripts/              # install scripts (see order below)
dot_zshrc.tmpl                # template
dot_gitconfig.tmpl            # template
dot_tmux.conf
dot_local/bin/executable_dotfiles-drift
private_dot_config/           # ghostty, niri, mise, zsh/secrets
dot_local/state/noctalia/     # noctalia settings (it keeps config in ~/.local/state)
```

On `chezmoi apply`, things run in this order:

1. `05` dnf baseline (first run only), `10` repos and COPR, `20` packages
2. Files and externals are written
3. `30` Flatpak, `40` mise runtimes, `45` tmux plugins, `50` default shell to zsh (first run only)

---

## Restore a machine

The repo is public, so `init cea2k` clones it over HTTPS with no SSH key needed.

### Laptop (Fedora, full environment)

```bash
# 1. Password manager first (templates read secrets during apply)
sudo dnf install -y rbw age pinentry
rbw config set email <bitwarden-email>
rbw register        # asks for client_id/secret from your Bitwarden personal API key
rbw unlock

# 2. age key (skip if there are no encrypted files in the repo)
mkdir -p ~/.config/chezmoi
rbw get chezmoi-age-key > ~/.config/chezmoi/key.txt
chmod 600 ~/.config/chezmoi/key.txt

# 3. Everything else
sh -c "$(curl -fsLS get.chezmoi.io)" -- -b ~/.local/bin init --apply cea2k
# answers: role = laptop, Bitwarden = yes
```

Then:

1. Log out and back in (the default shell is now zsh).
2. Open Bitwarden desktop, enable the SSH agent, and verify with `ssh -T git@github.com`.
3. Switch the repo to SSH so you can push. The restore cloned over HTTPS, which can pull but not push:
   ```bash
   chezmoi git -- remote set-url origin git@github.com:cea2k/dotfiles.git
   ```
4. Reinstall noctalia plugins from its UI if they didn't come back on their own. The list is under `[plugins]` in `~/.local/state/noctalia/settings.toml`. If the theme colors look like defaults, re-select the wallpaper once to regenerate the palette.

### Test machine (old HP, Fedora)

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- -b ~/.local/bin init --apply cea2k
# answers: role = test, Bitwarden = no
```

This is a full rehearsal of the laptop restore, without secrets. Follow steps 1, 3 and 4 from the laptop list above as needed.

### Server (Hostinger VPS, Ubuntu)

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- -b ~/.local/bin init --apply cea2k
# answer: role = server
```

The server gets shell, tmux, git and CLI tools only. It never installs or configures Docker or anything Coolify manages, and it has no Bitwarden vault by design. If it needs a secret file, encrypt it with a separate server-only age key.

---

## One-time setup (already done, kept for reference)

### Bitwarden secrets item

Only needed when Bitwarden = yes. Create a Secure Note named **`dotfiles-env`** with one **custom field per environment variable** (field name = variable name, e.g. `GITHUB_TOKEN`). Then run `rbw sync`, and check with `rbw get --raw dotfiles-env`.

The fields are rendered to `~/.config/zsh/secrets.zsh` (mode 0600), which `.zshrc` sources. This covers shell-wide tokens only; project `.env` files are not managed here.

### Bitwarden SSH agent

In Bitwarden desktop, open Settings and enable the SSH agent, then import or create your SSH keys there. `.zshrc` points `SSH_AUTH_SOCK` at the agent socket (the Flatpak and native paths are both handled).

### age key (only for encrypted files)

```bash
mkdir -p ~/.config/chezmoi
age-keygen -o ~/.config/chezmoi/key.txt
grep AGE-SECRET-KEY ~/.config/chezmoi/key.txt
```

Store that `AGE-SECRET-KEY-...` line as the password of a Bitwarden login item named **`chezmoi-age-key`**, then run `chezmoi init` so the config enables encryption.

---

## Testing changes safely

```bash
chezmoi diff                       # what apply would change
chezmoi apply --dry-run --verbose  # also shows scripts
chezmoi cat ~/.zshrc               # rendered output of a template
```

Full bootstrap in a throwaway Fedora container:

```bash
podman run --rm -it fedora:44 bash -c '
  dnf install -y curl git sudo && useradd -m -G wheel t && echo "t ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers &&
  su - t -c "sh -c \"\$(curl -fsLS get.chezmoi.io)\" -- -b ~/.local/bin init --apply cea2k"'
# answers: role = test, Bitwarden = no
```

## Troubleshooting

| Symptom | Fix |
|---|---|
| `rbw get: failed to load config` | rbw isn't set up. Configure it, or set `bitwarden = false` and run `chezmoi init` |
| `couldn't find entry for 'dotfiles-env'` | Create the item (see one-time setup), then `rbw sync` |
| Apply hangs or fails on `secrets.zsh` | `rbw unlock` |
| `{{` or `-if: command not found` when a shell starts | Template syntax ended up in the real file. Edit with `chezmoi edit`, then `chezmoi apply` |
| `config file template has changed` warning | `chezmoi init` |
| An install script did not re-run | `run_onchange_` reruns only when its content changes. Force all with `chezmoi state delete-bucket --bucket=entryState` |
| A `run_once_` script must run again | `chezmoi state delete-bucket --bucket=scriptState` |
| COPR enable fails | Check the COPR name and that it builds for this Fedora release |
| `.ssh/config` missing on a machine | It's encrypted and skipped where there's no age key. Restore `~/.config/chezmoi/key.txt` from Bitwarden (`chezmoi-age-key`), then `chezmoi init && chezmoi apply` |
| `chezmoi git -- push` asks for a username | The remote is HTTPS. Run `chezmoi git -- remote set-url origin git@github.com:cea2k/dotfiles.git` |

## Not managed here (on purpose)

- Coolify, Docker and app deployments on the VPS
- Project repositories and their `.env` files
- Browser profiles and app data under `~/.var/app`
- `/etc` beyond package repositories
