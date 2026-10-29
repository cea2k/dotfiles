# dotfiles

Personal environment managed with [chezmoi](https://www.chezmoi.io/): dotfiles, system packages, runtimes and secrets. Goal: a new machine is usable in minutes with a single command.

## How it works

| Concern | Mechanism |
|---|---|
| Config files | chezmoi source files (`dot_*`, `private_dot_config/...`) |
| Per-machine differences | `role` chosen at `chezmoi init`: `laptop`, `server`, `test` |
| System packages, COPR, repos, Flatpak | `.chezmoidata/packages.yaml` + `run_onchange_` scripts |
| Runtimes (node, pnpm...) | mise, global config in `~/.config/mise/config.toml` |
| Env-var secrets | Bitwarden item `dotfiles-env`, read through `rbw` at apply time |
| Secret files | age-encrypted files in this repo (`encrypted_*`) |
| SSH keys | Bitwarden desktop SSH agent. Keys are never stored here. |

### Roles

| Role | Machine | Desktop configs | Bitwarden secrets | Packages |
|---|---|---|---|---|
| `laptop` | Yoga Pro 7, Fedora | yes | yes | dnf + COPR + Flatpak + mise |
| `test` | old HP, Fedora | yes | no | dnf + COPR + Flatpak + mise |
| `server` | Hostinger VPS, Ubuntu | no | no | apt (user tools only) |

The role is asked once and stored in `~/.config/chezmoi/chezmoi.toml`. To change it, edit that file or run `chezmoi init --prompt`.

### Repo layout

```
.chezmoi.toml.tmpl            # prompts (role, git identity), age + hook config
.install-prereqs.sh           # hook: installs rbw/age before templates render
.chezmoiignore                # what each role skips
.chezmoidata/packages.yaml    # all packages, single source of truth
.chezmoiscripts/              # run_once_ / run_onchange_ install scripts
dot_zshrc.tmpl
dot_gitconfig.tmpl
dot_local/bin/executable_dotfiles-drift
private_dot_config/mise/config.toml
private_dot_config/zsh/private_secrets.zsh.tmpl
```

Scripts run in this order: `05` dnf baseline, `10` repos/COPR, `20` packages, then file updates, then `30` Flatpak, `40` mise, `50` default shell.

---

## One-time setup (do this once, ever)

### 1. Bitwarden: secrets item

Create a Bitwarden item named **`dotfiles-env`** (any type, a Secure Note works). Add one **custom field per environment variable**:

| Field name | Value |
|---|---|
| `GITHUB_TOKEN` | `ghp_...` |
| `NPM_TOKEN` | `...` |

Field names must be valid shell variable names. They are rendered to `~/.config/zsh/secrets.zsh` (mode 0600) and sourced by zsh.

### 2. Bitwarden: SSH agent

In the Bitwarden desktop app: Settings, enable the SSH agent. Import or generate your SSH keys inside Bitwarden. `.zshrc` points `SSH_AUTH_SOCK` at the agent socket (Flatpak and native paths are both handled).

### 3. age key (only if you need encrypted files)

```bash
mkdir -p ~/.config/chezmoi
age-keygen -o ~/.config/chezmoi/key.txt
grep AGE-SECRET-KEY ~/.config/chezmoi/key.txt
```

Store that `AGE-SECRET-KEY-...` line as the **password** of a Bitwarden login item named **`chezmoi-age-key`**. Run `chezmoi init` again afterwards so the config picks up encryption.

### 4. Import the current machine's configs

```bash
chezmoi init git@github.com:<github-user>/dotfiles.git
chezmoi diff                      # REVIEW: repo .zshrc/.gitconfig will replace yours
chezmoi merge ~/.zshrc            # carry over anything you want to keep
chezmoi add ~/.tmux.conf ~/.config/niri ~/.config/ghostty ~/.config/noctalia
chezmoi apply
chezmoi cd && git add -A && git commit -m "import current configs" && git push
```

Before the first apply, also fill in the missing COPR for noctalia in `packages.yaml`, and add any packages you already rely on.

---

## Restore a machine

`init <github-user>` clones `https://github.com/<github-user>/dotfiles.git`, so the repo must be public. If you make it private, use `init git@github.com:<github-user>/dotfiles.git` instead (needs SSH access first).

### Laptop (Fedora, full environment)

```bash
# 1. Password manager first (templates read secrets during apply)
sudo dnf install -y rbw age pinentry
rbw config set email <bitwarden-email>
rbw register        # needed on the official Bitwarden server (uses your personal API key)
rbw unlock

# 2. age key (skip if you have no encrypted files)
mkdir -p ~/.config/chezmoi
rbw get chezmoi-age-key > ~/.config/chezmoi/key.txt
chmod 600 ~/.config/chezmoi/key.txt

# 3. Everything else
sh -c "$(curl -fsLS get.chezmoi.io)" -- -b ~/.local/bin init --apply <github-user>
# answer: role = laptop
```

Then: log out and in (default shell is now zsh), open Bitwarden desktop and enable the SSH agent, and run `ssh -T git@github.com` to verify.

### Test machine (old HP, Fedora)

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- -b ~/.local/bin init --apply <github-user>
# answer: role = test
```

No secrets are rendered. Useful as a full rehearsal of the laptop restore.

### Server (Hostinger VPS, Ubuntu)

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- -b ~/.local/bin init --apply <github-user>
# answer: role = server
```

Gets shell, tmux, git and CLI tools only. It never installs or configures Docker or anything Coolify manages. There is no Bitwarden vault on the server by design. If a server needs a secret file, encrypt it with a separate server-only age key.

---

## Daily workflow

| Task | Command |
|---|---|
| Edit a managed file | `chezmoi edit ~/.zshrc` then `chezmoi apply` |
| Edited the real file directly | `chezmoi re-add` |
| Start managing a new file | `chezmoi add ~/.config/foo` |
| Add an encrypted file | `chezmoi add --encrypt ~/.config/foo/token` |
| See pending changes | `chezmoi diff` / `chezmoi status` |
| Commit and push | `chezmoi cd`, then normal git |
| Pull changes on another machine | `chezmoi update` |
| Secret changed in Bitwarden | `rbw sync && chezmoi apply` |

### Adding software

Never `dnf install` something you want to keep without recording it:

1. Add it to `.chezmoidata/packages.yaml` (`chezmoi cd`, then edit the file).
2. `chezmoi apply`. The matching script re-runs because the package list hash changed.
3. Commit.

COPR goes under `copr:`, third-party `.repo` URLs under `repos:`, Flatpak app IDs under `flatpak:`. Global runtimes go in `private_dot_config/mise/config.toml`. Project runtimes belong in each project's own `mise.toml`.

### Catching drift

```bash
dotfiles-drift
```

This reports dnf packages installed by hand that aren't in `packages.yaml` (ignoring the baseline taken on first apply), declared packages that are missing, undeclared Flatpaks, and unrecorded config changes. Run it weekly. This is the habit that keeps the repo from dying.

---

## Testing changes safely

```bash
chezmoi diff                       # what apply would change
chezmoi apply --dry-run --verbose  # also shows scripts
chezmoi execute-template < .chezmoiscripts/run_onchange_before_20-fedora-packages.sh.tmpl
```

A full bootstrap test in a throwaway Fedora container:

```bash
podman run --rm -it fedora:44 bash -c '
  dnf install -y curl git sudo && useradd -m -G wheel t && echo "t ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers &&
  su - t -c "sh -c \"\$(curl -fsLS get.chezmoi.io)\" -- -b ~/.local/bin init --apply <github-user>"'
# answer: role = test
```

## Troubleshooting

| Symptom | Fix |
|---|---|
| Apply hangs or fails on `secrets.zsh` | `rbw unlock`, or `rbw sync` if the item was just created |
| A script did not re-run after editing it | Only content changes trigger `run_onchange_`. Use `chezmoi state delete-bucket --bucket=entryState` to force all of them. |
| `run_once_` script needs to run again | `chezmoi state delete-bucket --bucket=scriptState` |
| COPR enable fails | Check the COPR name and that it builds for this Fedora release |
| Wrong role on a machine | Edit `~/.config/chezmoi/chezmoi.toml`, then `chezmoi apply` |

## Not managed here (on purpose)

- Coolify, Docker and app deployments on the VPS
- Project repositories and their `.env` files
- Browser profiles and app data under `~/.var/app`
- `/etc` beyond package repositories
