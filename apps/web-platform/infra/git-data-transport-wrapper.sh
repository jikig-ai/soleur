#!/usr/bin/env bash
#
# git-data in-band TRANSPORT forced-command wrapper — epic #5274 Phase 3, Sub-PR 3.D
# / ADR-068 §6.
#
# Replaces the raw `git-shell -c "$SSH_ORIGINAL_COMMAND"` forced command on the
# transport key (cloud-init-git-data.yml). git-shell already restricts to the
# server verbs, but it resolves the repo-path argument WITHOUT a canonicalization
# fence, so a crafted `git-upload-pack '/mnt/git-data-luks/../../etc/...'` reaches
# paths outside the bare-repo root. This wrapper adds the SAME CWE-22 canonicalize-
# under-root guard git-data-provision.sh / git-data-remove.sh apply, then execs the
# real server verb — defense-in-depth ON TOP of git-shell, not a replacement of it.
#
# Contract: read SSH_ORIGINAL_COMMAND; ALLOW only the two git server verbs
#   git-upload-pack '<path>'   (clone / fetch / ls-remote — read)
#   git-receive-pack '<path>'  (push — write, gated further by the pre-receive fence)
# in either the hyphen (`git-upload-pack`) or space (`git upload-pack`) form. REJECT
# every other command (interactive shell, `git gc`, `rm`, chained `;`/`&&`, …) with
# a clear remote: error + exit 1. Extract the single quoted path arg, reject dot-path
# traversal, `readlink -f` it, and refuse unless it canonicalizes to a DIRECT
# `<root>/<id>.git` child of the bare-repo root (mirrors git-data-remove.sh's exact-
# child assertion). Runs as the `git` user; sshd passes NO client env (AcceptEnv
# empty) so REPO_ROOT is always the server default in production.
set -euo pipefail

# Overridable ONLY for tests (sshd passes no client env — identical posture to
# git-data-provision.sh / git-data-remove.sh REPO_ROOT).
REPO_ROOT="${GIT_DATA_REPO_ROOT:-/mnt/git-data/repositories}"

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

# --- Canonicalize under the bare-repo root (CWE-22, mirrors provision/remove) --
root_real="$(readlink -f "$REPO_ROOT" 2>/dev/null || echo "")"
[ -n "$root_real" ] || reject "repo root $REPO_ROOT is not present"
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

# --- Test-only dry-run hook (sshd never passes this — AcceptEnv empty, identical
#     posture to GIT_DATA_REPO_ROOT). Lets the drift test assert the ACCEPT path
#     without spinning a real git-upload-pack handshake. NO security impact: it only
#     replaces the final exec with an echo of the validated, canonicalized command. -
if [ "${GIT_DATA_TRANSPORT_EXEC_DRYRUN:-0}" = "1" ]; then
  echo "DRYRUN-EXEC ${verb} ${repo_real}"
  exit 0
fi

# --- Exec the real server verb against the CANONICALIZED path -----------------
exec "$verb" "$repo_real"
