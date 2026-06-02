#!/usr/bin/env bash
# infra-config-install.sh — pinned root-run escalation helper for the
# /hooks/infra-config webhook handler (#4827, Ref #4804).
#
# WHY THIS EXISTS: infra-config-apply.sh runs as User=deploy (webhook.service).
# Its 8 managed files live in root:root 0755 destination directories
# (/usr/local/bin, /etc/systemd/system, /etc/webhook, /etc/sudoers.d). The deploy
# user cannot mktemp inside those dirs — EACCES — so the handler could never land
# a single file (the #4827 bug: every push wrote 0 files). systemd ReadWritePaths
# elevates the mount namespace to read-write but does NOT override DAC ownership.
#
# THE FIX: the handler stages each decoded payload in a deploy-writable dir, then
# invokes THIS helper via a wildcard-free sudoers grant
# (Cmnd_Alias INFRA_CONFIG_INSTALL = /usr/local/bin/infra-config-install). sudo
# permits the bare command with ANY arguments — so the SECURITY BOUNDARY is here,
# not in sudoers: the helper hardcodes the 8 allowlisted destinations and refuses
# anything else, and refuses TOCTOU-attackable staged sources (symlink / wrong
# owner). Mirrors the inngest-bootstrap precedent (ci-deploy.sh:683-788): fixed
# pinned path, dest pinned by an in-image allowlist, symlink/owner guards.
#
# Because the helper runs as root it has no EACCES problem in the dest dirs: it
# mktemps in the destination directory itself and does a same-filesystem atomic
# rename, so atomicity holds regardless of which filesystem the staging dir is on.
#
# CONTRACT (exit codes consumed by infra-config-apply.sh's per-file accounting):
#   0 = installed
#   1 = install failure (mktemp/cp/chmod/chown/mv)
#   2 = usage error (wrong arg count)
#   3 = rejected (dest not in allowlist, or TOCTOU guard tripped) → install_rejected
set -euo pipefail

readonly LOG_TAG="infra-config-install"

# Canonical destinations the helper is permitted to write. MUST stay in lockstep
# with FILE_MAP in infra-config-apply.sh — a dest absent here is rejected (rc=3).
readonly ALLOWED_DESTS=(
  "/usr/local/bin/ci-deploy.sh"
  "/usr/local/bin/ci-deploy-wrapper.sh"
  "/etc/systemd/system/webhook.service"
  "/usr/local/bin/cat-deploy-state.sh"
  "/usr/local/bin/canary-bundle-claim-check.sh"
  "/etc/sudoers.d/deploy-inngest-bootstrap"
  "/etc/webhook/hooks.json"
  "/usr/local/bin/cat-infra-config-state.sh"
)

# TEST_DESTDIR redirects writes to a sandbox and skips chown (no root needed),
# exactly as infra-config-apply.sh does. Empty in prod.
DESTDIR="${TEST_DESTDIR:-}"

usage() {
  echo "usage: infra-config-install <staged-src> <canonical-dest> <mode> <owner>" >&2
  exit 2
}

[[ "$#" -eq 4 ]] || usage
src="$1"
dest_canonical="$2"
mode="$3"
owner="$4"

reject() {
  local reason="$1"
  logger -t "$LOG_TAG" "REJECTED: dest=$dest_canonical reason=$reason" 2>/dev/null || true
  echo "ERROR: install rejected ($reason) for $dest_canonical" >&2
  exit 3
}

# --- Allowlist check (canonical dest, before any sandbox prefix) ---
allowed=0
for d in "${ALLOWED_DESTS[@]}"; do
  if [[ "$dest_canonical" == "$d" ]]; then
    allowed=1
    break
  fi
done
[[ "$allowed" -eq 1 ]] || reject "dest_not_allowlisted"

# --- TOCTOU guards on the staged source (the one attacker-influenceable input) ---
# Refuse a symlinked source: the deploy user could repoint it after the handler
# staged it, tricking root into copying arbitrary file content.
[[ -L "$src" ]] && reject "src_symlink"
[[ -f "$src" ]] || reject "src_missing"

# The staged source must be owned by the invoking (deploy) user. Under sudo,
# SUDO_USER is the real caller; outside sudo (sandbox tests), fall back to the
# current user so the guard still validates ownership.
expected_owner="${SUDO_USER:-$(id -un)}"
actual_owner="$(stat -c '%U' "$src" 2>/dev/null || echo '?')"
[[ "$actual_owner" == "$expected_owner" ]] || reject "src_owner_mismatch:$actual_owner"

# --- Resolve the real write target (sandbox prefix in test mode) ---
dest="${DESTDIR}${dest_canonical}"
dest_dir="$(dirname "$dest")"

# Refuse to write through a symlinked destination (would clobber an unrelated path).
[[ -L "$dest" ]] && reject "dest_symlink"

# --- Atomic install: mktemp IN the dest dir (root can write it), then rename ---
# Same-filesystem rename → atomic regardless of where the staging dir lives.
install_fail() {
  local reason="$1"
  logger -t "$LOG_TAG" "FAILED: dest=$dest_canonical reason=$reason" 2>/dev/null || true
  echo "ERROR: install failed ($reason) for $dest_canonical" >&2
  exit 1
}

tmp="$(mktemp "${dest_dir}/tmp.infra-config-install.XXXXXX" 2>/dev/null)" || install_fail "mktemp"
trap 'rm -f "$tmp"' EXIT

cp "$src" "$tmp" || install_fail "cp"
chmod "$mode" "$tmp" || install_fail "chmod"
# chown only works as root; skip in sandbox/test mode (mirrors the handler).
if [[ -z "$DESTDIR" ]]; then
  chown "$owner" "$tmp" || install_fail "chown"
fi
mv -f "$tmp" "$dest" || install_fail "mv"

logger -t "$LOG_TAG" "installed: $dest_canonical mode=$mode owner=$owner" 2>/dev/null || true
exit 0
