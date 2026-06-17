#!/usr/bin/env bash
# infra-config-install.sh — pinned root-run escalation helper for the
# /hooks/infra-config webhook handler (#4827, Ref #4804).
#
# WHY THIS EXISTS: infra-config-apply.sh runs as User=deploy (webhook.service).
# Its 11 managed files live in root:root 0755 destination directories
# (/usr/local/bin, /etc/systemd/system, /etc/webhook). The deploy user cannot
# mktemp inside those dirs — EACCES — so the handler could never land a single
# file (the #4827 bug: every push wrote 0 files). systemd ReadWritePaths elevates
# the mount namespace to read-write but does NOT override DAC ownership.
#
# THE FIX: the handler base64-decodes each payload, then invokes THIS helper via a
# wildcard-free sudoers grant
# (Cmnd_Alias INFRA_CONFIG_INSTALL = /usr/local/bin/infra-config-install). sudo
# permits the bare command with ANY arguments — so the SECURITY BOUNDARY is here,
# not in sudoers: the helper hardcodes the 7 allowlisted destinations and refuses
# anything else. Because the helper runs as root it has no EACCES problem in the
# dest dirs: it mktemps in the destination directory itself and does a
# same-filesystem atomic rename.
#
# PAYLOAD IS READ FROM STDIN, NOT A FILE PATH (#4827 security review, P1 fix).
# An earlier design passed a staged file path as $1; because the staging dir
# (/var/lock) is deploy-writable, a deploy user invoking `sudo infra-config-install`
# directly could swap that path to a symlink → /etc/shadow (etc.) in the window
# between the helper's owner/symlink check and its `cp`, and root would copy a
# root-only file into a world-readable 0755 dest (confidentiality break / privesc).
# Reading the payload from STDIN removes the on-disk attacker-controlled source
# entirely: the redirect (`< file`) is opened by the DEPLOY user before sudo
# elevates, so a deploy user can only ever feed bytes they could already read —
# `sudo infra-config-install <dest> <mode> <owner> < /etc/shadow` fails at open as
# deploy. There is no path to swap, so no TOCTOU.
#
# CONTRACT (exit codes consumed by infra-config-apply.sh's per-file accounting):
#   0 = installed
#   1 = install failure (mktemp/write/chmod/chown/mv)
#   2 = usage error (wrong arg count)
#   3 = rejected (dest not in allowlist, or mode/owner mismatch) → install_rejected
#
# PRIVILEGE-ESCALATION HARDENING (#4827 security review):
#  - The sudoers grant `deploy ALL=(root) NOPASSWD: /usr/local/bin/infra-config-install`
#    lets the deploy user invoke this helper DIRECTLY with arbitrary args — not
#    only through the handler. So mode + owner are NOT trusted from the caller:
#    they are derived from an authoritative per-dest table below, and the helper
#    REJECTS any call whose supplied mode/owner disagrees. This blocks a deploy
#    user from passing mode=4755 to setuid a root-owned binary or owner=deploy to
#    seize one.
#  - /etc/sudoers.d/* is deliberately NOT in this table. The grant-definition file
#    is the one file whose content-write is an unbounded escalation (a deploy user
#    could install `NOPASSWD: ALL`); visudo only checks syntax, not policy, so the
#    helper cannot safely validate it. It is managed root-only (the SSH
#    handler-bootstrap bridge + cloud-init write_files), never via this helper.
set -euo pipefail

readonly LOG_TAG="infra-config-install"

# Authoritative dest → "mode owner" table. MUST stay in lockstep with FILE_MAP in
# infra-config-apply.sh (minus the sudoers entry, which is root-managed). A dest
# absent here is rejected (rc=3). mode/owner come from HERE, not the caller.
declare -rA DEST_SPEC=(
  ["/usr/local/bin/ci-deploy.sh"]="755 root:root"
  ["/usr/local/bin/ci-deploy-wrapper.sh"]="755 root:root"
  ["/etc/systemd/system/webhook.service"]="644 root:root"
  ["/usr/local/bin/cat-deploy-state.sh"]="755 root:root"
  ["/usr/local/bin/canary-bundle-claim-check.sh"]="755 root:root"
  ["/etc/webhook/hooks.json"]="640 root:deploy"
  ["/usr/local/bin/cat-infra-config-state.sh"]="755 root:root"
  ["/usr/local/bin/inngest-enumerate-reminders.sh"]="755 root:root"
  ["/usr/local/bin/inngest-rearm-reminders.sh"]="755 root:root"
  ["/usr/local/bin/inngest-wiped-volume-verify.sh"]="755 root:root"
  ["/usr/local/bin/cat-inngest-verify-state.sh"]="755 root:root"
  ["/usr/local/bin/inngest-inventory.sh"]="755 root:root"
)

# TEST_DESTDIR redirects writes to a sandbox and skips chown (no root needed),
# exactly as infra-config-apply.sh does. Empty in prod.
DESTDIR="${TEST_DESTDIR:-}"

usage() {
  echo "usage: infra-config-install <canonical-dest> <mode> <owner> < payload" >&2
  exit 2
}

[[ "$#" -eq 3 ]] || usage
dest_canonical="$1"
caller_mode="$2"
caller_owner="$3"

reject() {
  local reason="$1"
  logger -t "$LOG_TAG" "REJECTED: dest=$dest_canonical reason=$reason" 2>/dev/null || true
  echo "ERROR: install rejected ($reason) for $dest_canonical" >&2
  exit 3
}

# --- Allowlist + authoritative mode/owner (canonical dest, before sandbox prefix) ---
spec="${DEST_SPEC[$dest_canonical]:-}"
[[ -n "$spec" ]] || reject "dest_not_allowlisted"
read -r mode owner <<< "$spec"

# Reject any caller whose requested mode/owner disagrees with the authoritative
# table — a deploy user trying to escalate (setuid/chown) is refused, and a
# handler/FILE_MAP drift is surfaced loudly rather than silently overridden.
[[ "$caller_mode" == "$mode" ]] || reject "mode_mismatch:caller=$caller_mode:expected=$mode"
[[ "$caller_owner" == "$owner" ]] || reject "owner_mismatch:caller=$caller_owner:expected=$owner"

# --- Resolve the real write target (sandbox prefix in test mode) ---
dest="${DESTDIR}${dest_canonical}"
dest_dir="$(dirname "$dest")"

# Refuse to write through a symlinked destination (would clobber an unrelated path).
[[ -L "$dest" ]] && reject "dest_symlink"

# --- Atomic install: mktemp IN the dest dir (root can write it), then rename ---
# Same-filesystem rename → atomic. The payload comes from STDIN (see header) so
# there is no caller-controlled source path to symlink-swap.
install_fail() {
  local reason="$1"
  logger -t "$LOG_TAG" "FAILED: dest=$dest_canonical reason=$reason" 2>/dev/null || true
  echo "ERROR: install failed ($reason) for $dest_canonical" >&2
  exit 1
}

tmp="$(mktemp "${dest_dir}/tmp.infra-config-install.XXXXXX" 2>/dev/null)" || install_fail "mktemp"
trap 'rm -f "$tmp"' EXIT

cat > "$tmp" || install_fail "write"
chmod "$mode" "$tmp" || install_fail "chmod"
# chown only works as root; skip in sandbox/test mode (mirrors the handler).
if [[ -z "$DESTDIR" ]]; then
  chown "$owner" "$tmp" || install_fail "chown"
fi
mv -f "$tmp" "$dest" || install_fail "mv"

logger -t "$LOG_TAG" "installed: $dest_canonical mode=$mode owner=$owner" 2>/dev/null || true
exit 0
