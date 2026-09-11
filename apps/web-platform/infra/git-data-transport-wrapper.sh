#!/usr/bin/env bash
#
# git-data in-band TRANSPORT forced-command wrapper — epic #5274 Phase 3, Sub-PR 3.D
# / ADR-068 §6.
#
# THE forced command on the transport key (cloud-init-git-data.yml), and THE confinement of
# that key: the git account's login shell is /bin/sh (#8043 — sshd runs `command=` as
# `<login shell> -c`, and git-shell refuses that form with rc=128, measured), so nothing
# but the authorized_keys `command=` map and this allowlist stands between a client and a
# shell. It replaced the raw `git-shell -c "$SSH_ORIGINAL_COMMAND"` form, which resolved the
# repo-path argument WITHOUT a canonicalization fence (a crafted
# `git-upload-pack '/mnt/git-data-luks/../../etc/...'` reached paths outside the bare-repo
# root). It applies the SAME store-mounted + canonicalize-under-root guards that
# git-data-provision.sh / git-data-remove.sh apply, then execs the real server verb.
#
# Contract: read SSH_ORIGINAL_COMMAND; ALLOW only the two git server verbs
#   git-upload-pack '<path>'   (clone / fetch / ls-remote — read)
#   git-receive-pack '<path>'  (push — write, gated further by the pre-receive fence)
# in either the hyphen (`git-upload-pack`) or space (`git upload-pack`) form. REJECT
# every other command (interactive shell, `git gc`, `rm`, chained `;`/`&&`, …) with
# a clear remote: error + exit 1. Extract the single quoted path arg, reject dot-path
# traversal, `readlink -f` it, and refuse unless it canonicalizes to a DIRECT
# `<root>/<id>.git` child of the bare-repo root (mirrors git-data-remove.sh's exact-
# child assertion). Runs as the `git` user; sshd forwards client environment only for
# names matched by AcceptEnv, and Ubuntu's stock sshd_config ships `AcceptEnv LANG LC_*`
# (#8043 F10 — not "empty", as this comment once said), which cannot match
# GIT_DATA_REPO_ROOT, so REPO_ROOT is always the server default in production.
set -euo pipefail

# Overridable ONLY for tests (unreachable from a client: `AcceptEnv LANG LC_*` cannot
# match this name — identical posture to git-data-provision.sh / git-data-remove.sh).
REPO_ROOT="${GIT_DATA_REPO_ROOT:-/mnt/git-data/repositories}"
# (#8043 review) The MOUNT the store lives on and the ROOT-OWNED hook directory — the same
# two seams provision/remove carry, defaulted identically (git-data-bootstrap.sh is the
# writer of record for both literals; the ownership suite pins the defaults agree).
MOUNT_ROOT="${GIT_DATA_MOUNT_ROOT:-/mnt/git-data}"
HOOKS_DIR="${GIT_DATA_HOOKS_DIR:-/mnt/git-data/hooks}"

reject() {
  echo "remote: git-data transport: $1" >&2
  exit 1
}

cmd="${SSH_ORIGINAL_COMMAND:-}"
[ -n "$cmd" ] || reject "interactive shell / empty command denied (transport is git-upload-pack/git-receive-pack only)"

# --- Allowlist the verb and strip its prefix (hyphen AND space forms) ---------
case "$cmd" in
  "git-upload-pack "*)  verb="git-upload-pack";  rest="${cmd#git-upload-pack }" ;;
  "git upload-pack "*)  verb="git-upload-pack";  rest="${cmd#git upload-pack }" ;;
  "git-receive-pack "*) verb="git-receive-pack"; rest="${cmd#git-receive-pack }" ;;
  "git receive-pack "*) verb="git-receive-pack"; rest="${cmd#git receive-pack }" ;;
  *) reject "command not allowed: only git-upload-pack / git-receive-pack permitted, got '$cmd'" ;;
esac

# --- Unquote the single path argument -----------------------------------------
# git single-quotes the repo path (e.g. git-upload-pack 'repositories/ws.git'). Strip
# exactly one surrounding pair of single quotes; anything else (a second arg, an
# unbalanced quote, a `;`) leaves stray tokens that the traversal/charset guards
# below reject.
path="$rest"
case "$path" in
  "'"*"'") path="${path#\'}"; path="${path%\'}" ;;
esac
[ -n "$path" ] || reject "empty repo path"

# --- Fail-closed traversal + shell-metachar guard (before any readlink) --------
case "$path" in
  *..*)                 reject "repo path contains dot-dot traversal: '$path'" ;;
  *"'"*)                reject "repo path contains a stray quote (multi-arg / injection): '$path'" ;;
  *';'* | *'&'* | *'|'* | *'`'* | *'$'* | *' '*)
    reject "repo path contains shell metacharacters: '$path'" ;;
esac

# --- (#8043 review) REFUSE UNLESS THE STORE IS MOUNTED AND THE ROOT IS ON IT — the same
#     guard provision/remove carry (git-data-remove.sh states the full rationale; this is the
#     third forced command and the one that WRITES user source on every push, so it cannot be
#     the one without it). mountpoint(1) is resolved from PATH and its absence fails closed;
#     `stat -c %m` names the mount the root sits on, which must be the store's own. ---
command -v mountpoint >/dev/null 2>&1 || reject "cannot verify the store is mounted: mountpoint(1) not on PATH (fail-closed)"
mountpoint -q "$MOUNT_ROOT" || reject "git-data store is not mounted at $MOUNT_ROOT — refusing transport on an unmounted store (fail-closed)"

# --- Canonicalize under the bare-repo root (CWE-22, same guard as provision/remove) --
root_real="$(readlink -f "$REPO_ROOT" 2>/dev/null || echo "")"
[ -d "$root_real" ] || reject "repo root $REPO_ROOT is not present"
[ "$(stat -c %m "$root_real")" = "$(readlink -f "$MOUNT_ROOT")" ] || reject "repo root $root_real is not on the store mounted at $MOUNT_ROOT (fail-closed)"
repo_real="$(readlink -f "$path" 2>/dev/null || echo "")"
[ -n "$repo_real" ] || reject "repo path does not resolve: '$path'"
# readlink -f canonicalizes a non-existent leaf too, so require the repo to actually
# exist — it is always provisioned (git-data-provision.sh) before the first transport.
[ -e "$repo_real" ] || reject "repo does not exist (provision it first): '$path'"

# Must be a DIRECT <root>/<id>.git child — exactly the shape provision/remove create
# (defense-in-depth beyond the prefix check: blocks a symlink or nested path that
# resolves under the root but is not a real per-workspace bare repo).
case "$repo_real" in
  "$root_real"/*.git) : ;;
  *) reject "resolved path escapes the bare-repo root or is not a <id>.git repo: '$repo_real'" ;;
esac
child="${repo_real#"$root_real"/}"
case "$child" in
  */*) reject "repo path is not a direct child of the root (nested): '$repo_real'" ;;
esac

# --- Test-only dry-run hook (unreachable from a client: `AcceptEnv LANG LC_*` cannot
#     match GIT_DATA_TRANSPORT_EXEC_DRYRUN — identical posture to GIT_DATA_REPO_ROOT).
#     Lets the drift test assert the ACCEPT path
#     without spinning a real git-upload-pack handshake. NO security impact: it only
#     replaces the final exec with an echo of the validated, canonicalized command. -
# --- (#8043 review) THE FENCE IS PINNED ON THE COMMAND LINE. Repo-local config is
#     git-writable (the repo is git:git), and a repo-local `core.hooksPath` outranks the
#     system value the bootstrap sets — so with code execution as `git`, one workspace could
#     point its own hooks at a git-writable dir and receive pushes unfenced without ever
#     touching the root-owned pre-receive (measured: `core.hooksPath=/nonexistent` → push
#     accepted, no hook run). `git -c` is the one config scope nothing under the repo can
#     override, so the verb is exec'd through it. Applied to both verbs for uniformity. ---
if [ "${GIT_DATA_TRANSPORT_EXEC_DRYRUN:-0}" = "1" ]; then
  echo "DRYRUN-EXEC git -c core.hooksPath=${HOOKS_DIR} ${verb#git-} ${repo_real}"
  exit 0
fi

# --- Exec the real server verb against the CANONICALIZED path -----------------
exec git -c "core.hooksPath=${HOOKS_DIR}" "${verb#git-}" "$repo_real"
