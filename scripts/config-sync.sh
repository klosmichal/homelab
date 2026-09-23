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

# The runtime copy of AdGuardHome.yaml is root-owned 0600, so reading or
# writing it needs root. cp onto an existing file keeps that file's owner and
# mode, so this never changes ownership of the others. Export SUDO="" to skip
# it entirely (already root, or a tree you own).
if [ -z "${SUDO+x}" ]; then
  if [ "$(id -u)" -eq 0 ]; then SUDO=""; else SUDO="sudo"; fi
fi

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
  local entry repo live direction repo_path live_path
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
    if ! $SUDO test -f "$live_path"; then
      if [ -e "$live_path" ]; then
        printf '  UNREADABLE         %s  (needs sudo)\n' "$live"
      else
        printf '  missing on server  %s\n' "$live"
      fi
      clean=1
      continue
    fi
    if $SUDO diff -q "$live_path" "$repo_path" >/dev/null 2>&1; then
      printf '  same               %s\n' "$repo"
      continue
    fi

    clean=1
    printf '  DIFFERS            %s%s\n' "$repo" \
      "$([ "$direction" = "pull" ] && echo '  (pull-only)')"
    $SUDO diff -u --label "live: $live_path" --label "repo: $repo_path" \
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

    $SUDO test -f "$src" || { printf 'skipped (no source)  %s\n' "$src"; continue; }
    if $SUDO diff -q "$src" "$dst" >/dev/null 2>&1; then continue; fi

    $SUDO mkdir -p "$(dirname "$dst")"
    $SUDO cp "$src" "$dst" || return 1
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
