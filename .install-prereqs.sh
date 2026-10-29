#!/bin/sh
# Runs before every chezmoi command (read-source-state.pre hook).
# Must be fast and idempotent: it exits immediately once tools exist.
set -eu

need=""
command -v rbw >/dev/null 2>&1 || need="$need rbw"
command -v age >/dev/null 2>&1 || need="$need age"
[ -z "$need" ] && exit 0

if command -v dnf >/dev/null 2>&1; then
  echo "[dotfiles] installing prerequisites:$need" >&2
  # shellcheck disable=SC2086
  sudo dnf install -y $need pinentry
elif command -v apt-get >/dev/null 2>&1; then
  # Servers only need age (no Bitwarden vault on servers by design)
  if ! command -v age >/dev/null 2>&1; then
    echo "[dotfiles] installing prerequisites: age" >&2
    sudo apt-get update -qq && sudo apt-get install -y age
  fi
fi
