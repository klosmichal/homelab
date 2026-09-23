#!/usr/bin/env bash
# Mirror config files between this repo and the runtime locations under
# APPDATA_ROOT.
#
#   diff  — show what differs, change nothing (safe to run any time)
#   push  — repo  -> runtime  (what `just sync-config` does)
#   pull  — runtime -> repo   (what `just pull-config` does)
#
# push and pull always run the diff first and require confirmation, because
# both directions overwrite. Set CONFIRM=yes to skip the prompt (CI, scripts).
#
# Exit codes: 0 files were copied, 1 aborted or error, 2 nothing to do.
set -uo pipefail

MODE="${1:-diff}"
ROOT="${APPDATA_ROOT:-/srv/homelab}"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Only the runtime copy of AdGuardHome.yaml is root-owned 0600; everything else
# belongs to the login user. So sudo is applied per file, only where the plain
# operation would fail — otherwise a full run would prompt for a password it
# does not need. Export SUDO="" to forbid escalation entirely.
if [ -z "${SUDO+x}" ]; then
  if [ "$(id -u)" -eq 0 ]; then SUDO=""; else SUDO="sudo"; fi
fi

# Prefix for reading a path: empty when it is already readable.
read_as() { [ -r "$1" ] || printf '%s' "$SUDO"; }

# Prefix for writing a path: empty when the file (or its parent, if the file
# does not exist yet) is already writable.
write_as() {
  if [ -e "$1" ]; then
    [ -w "$1" ] || printf '%s' "$SUDO"
  else
    [ -w "$(dirname "$1")" ] || printf '%s' "$SUDO"
  fi
}

# repo path | runtime path (relative to ROOT) | direction
#   both — the repo is the source of truth; push writes it, pull snapshots it
#   pull — the app owns the file; we only ever copy it back into the repo
FILES=(
  "config/adguardhome/AdGuardHome.yaml|adguardhome/conf/AdGuardHome.yaml|both"
  "config/samba/smb.conf|samba/smb.conf|both"
  "config/qbittorrent/qBittorrent.conf|qbittorrent/config/qBittorrent/qBittorrent.conf|both"
  "config/gluetun/auth/config.toml|gluetun/auth/config.toml|both"
  "config/recyclarr/recyclarr.yml|recyclarr/config/recyclarr.yml|both"
  # Home Assistant writes automations, scenes and scripts from its own UI, so
  # those are pull-only — pushing them would overwrite what the UI saved.
  "config/homeassistant/configuration.yaml|homeassistant/config/configuration.yaml|both"
  "config/homeassistant/automations.yaml|homeassistant/config/automations.yaml|pull"
  "config/homeassistant/scenes.yaml|homeassistant/config/scenes.yaml|pull"
  "config/homeassistant/scripts.yaml|homeassistant/config/scripts.yaml|pull"
)

# Homepage is a directory of yaml/css/js; take whatever the repo holds.
for f in "$REPO"/config/homepage/*; do
  [ -f "$f" ] || continue
  FILES+=("config/homepage/$(basename "$f")|homepage/config/$(basename "$f")|both")
done

# Entries this mode acts on: push only touches `both`, pull touches everything.
applies() {
  local direction="$1"
  case "$MODE" in
    push) [ "$direction" = "both" ] ;;
    *) true ;;
  esac
}

# Prints one status line per file, plus a unified diff for anything that
# differs. Returns 0 if every file matches, 1 if any differ or are missing.
run_diff() {
  local clean=0
  local entry repo live direction repo_path live_path prefix
  for entry in "${FILES[@]}"; do
    IFS='|' read -r repo live direction <<<"$entry"
    applies "$direction" || continue
    repo_path="$REPO/$repo"
    live_path="$ROOT/$live"

    if [ ! -f "$repo_path" ]; then
      printf '  missing in repo    %s\n' "$repo"
      clean=1
      continue
    fi
    if [ ! -e "$live_path" ]; then
      printf '  missing on server  %s\n' "$live"
      clean=1
      continue
    fi

    # A failed sudo exits 1, exactly like "files differ", so confirm the file is
    # readable first — otherwise an unreadable file is reported as a difference.
    prefix="$(read_as "$live_path")"
    if [ -n "$prefix" ] && ! $prefix test -r "$live_path" 2>/dev/null; then
      printf '  UNREADABLE         %s  (needs sudo)\n' "$live"
      clean=1
      continue
    fi

    # diff: 0 identical, 1 differ, anything else means it could not be read.
    $prefix diff -q "$live_path" "$repo_path" >/dev/null 2>&1
    case $? in
      0)
        printf '  same               %s\n' "$repo"
        continue
        ;;
      1) ;;
      *)
        printf '  UNREADABLE         %s  (needs sudo)\n' "$live"
        clean=1
        continue
        ;;
    esac

    clean=1
    printf '  DIFFERS            %s%s\n' "$repo" \
      "$([ "$direction" = "pull" ] && echo '  (pull-only)')"
    $prefix diff -u --label "live: $live_path" --label "repo: $repo_path" \
      "$live_path" "$repo_path" 2>/dev/null | sed 's/^/      /'
  done
  return $clean
}

copy() {
  local entry repo live direction src dst copied=0
  for entry in "${FILES[@]}"; do
    IFS='|' read -r repo live direction <<<"$entry"
    applies "$direction" || continue

    if [ "$MODE" = "push" ]; then
      src="$REPO/$repo"; dst="$ROOT/$live"
    else
      src="$ROOT/$live"; dst="$REPO/$repo"
    fi

    [ -e "$src" ] || { printf '  skipped (no source)  %s\n' "$src"; continue; }
    $(read_as "$src") diff -q "$src" "$dst" >/dev/null 2>&1 && continue

    $(write_as "$(dirname "$dst")") mkdir -p "$(dirname "$dst")"
    # cp onto an existing file keeps that file's owner and mode.
    $(write_as "$dst") cp "$src" "$dst" || {
      printf '  FAILED to write  %s  (needs sudo?)\n' "$dst"
      return 1
    }
    printf '  copied  %s -> %s\n' "$src" "$dst"
    copied=1
  done
  [ "$copied" -eq 1 ] || return 2
  return 0
}

case "$MODE" in
  diff)
    echo "Comparing repo configs against $ROOT ..."
    if run_diff; then echo "Everything matches."; exit 0; fi
    exit 1
    ;;
  push|pull)
    if [ "$MODE" = "push" ]; then
      echo "About to overwrite the RUNTIME configs under $ROOT with the repo copies."
    else
      echo "About to overwrite the REPO configs with the runtime copies from $ROOT."
    fi
    echo
    if run_diff; then
      echo
      echo "Nothing to do — repo and runtime already match."
      exit 2
    fi
    echo
    if [ "${CONFIRM:-}" != "yes" ]; then
      if [ ! -t 0 ]; then
        echo "Not a terminal and CONFIRM=yes was not set — aborting." >&2
        exit 1
      fi
      read -r -p "Apply the changes above? [y/N] " reply
      case "$reply" in
        [yY] | [yY][eE][sS]) ;;
        *) echo "Aborted — nothing was changed."; exit 1 ;;
      esac
    fi
    copy
    exit $?
    ;;
  *)
    echo "usage: $(basename "$0") [diff|push|pull]" >&2
    exit 1
    ;;
esac
