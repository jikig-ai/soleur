#!/usr/bin/env bash
# Workspace git-repo readiness probe WITH forensic capture (#6184 follow-up).
#
# soleur:go's Step 0.0 readiness gate previously ran
#   git rev-parse --is-bare-repository 2>/dev/null || true; git rev-parse --is-inside-work-tree 2>/dev/null || true
# and DISCARDED git's stderr. When git rejected the repo (a masked/corrupt config,
# a broken .git, an in-flight clone) the gate fired its "workspace isn't ready"
# message with NO record of WHY — the exact blind spot that forced a manual
# `git rev-parse` + `findmnt` round-trip to diagnose the #6184 config.worktree case.
#
# This script decides readiness identically (prints `SOLEUR_GIT_REPO_READY=true`
# iff git considers the CWD a work tree or bare repo) AND, on the NOT-ready path,
# emits a single-line `SOLEUR_GIT_REPO_DIAG` forensic to stdout. The server-side
# PostToolUse(Bash) telemetry hook (git-lock-marker-telemetry.ts) mirrors that line
# to Better Stack + Sentry, so the next readiness-gate failure is self-diagnosable
# without asking the operator to paste terminal output.
#
# Output contract (go.md keys on these):
#   ready   → prints `SOLEUR_GIT_REPO_READY=true`,  exit 0
#   not     → prints `SOLEUR_GIT_REPO_READY=false` + a `SOLEUR_GIT_REPO_DIAG …` line, exit 0
# Always exit 0: this is a diagnostic, never a hard failure that aborts the gate.
#
# Privacy: emits only git's own error text + filesystem type/mount metadata — no repo
# contents. The stderr is sanitized to one line and length-bounded before emission.

set -uo pipefail

# ftype <path> — classify an inode for the forensic (mirrors worktree-manager.sh's
# SOLEUR_GIT_LOCK_DIAG vocabulary so the two are greppable together).
ftype() {
  local p="$1"
  if [[ ! -e "$p" && ! -L "$p" ]]; then echo "absent"; return; fi
  if [[ -L "$p" ]]; then echo "symlink"; return; fi
  if [[ -c "$p" ]]; then echo "chardevice"; return; fi
  if [[ -b "$p" ]]; then echo "blockdevice"; return; fi
  if [[ -d "$p" ]]; then echo "dir"; return; fi
  if [[ -p "$p" ]]; then echo "fifo"; return; fi
  if [[ -f "$p" ]]; then echo "regular"; return; fi
  echo "other"
}

# sanitize <text> — collapse to a single line and bound length; strip the wrapping
# so a hostile/huge stderr cannot bloat the mirrored log line.
sanitize() {
  printf '%s' "$1" | tr '\n\r\t' '   ' | sed 's/  */ /g' | cut -c1-400
}

# Readiness = git recognizes the CWD as a work tree OR a bare repo. Capture stderr.
wt_err="$(git rev-parse --is-inside-work-tree 2>&1 >/dev/null)"; wt_rc=$?
wt_out="$(git rev-parse --is-inside-work-tree 2>/dev/null)"
bare_out="$(git rev-parse --is-bare-repository 2>/dev/null)"

if [[ "$wt_out" == "true" || "$bare_out" == "true" ]]; then
  echo "SOLEUR_GIT_REPO_READY=true"
  exit 0
fi

# NOT ready — capture the forensic. `git config --list` re-run separately: a config
# PARSE failure (e.g. an unreadable/masked config, an unknown extension under
# repositoryformatversion=1) is the discriminator between "no repo yet" (clone
# in-flight) and "repo present but git rejects it".
cfg_err="$(git config --list 2>&1 >/dev/null)"; cfg_rc=$?

git_dir_type="$(ftype ".git")"
cw_type="$(ftype ".git/config.worktree")"
cl_type="$(ftype ".git/config.lock")"

# Prefer the config-parse error when git rejected the repo (more specific than the
# generic rev-parse "not a git repository"); fall back to the rev-parse stderr.
err_text="$cfg_err"
[[ -z "$err_text" ]] && err_text="$wt_err"

echo "SOLEUR_GIT_REPO_READY=false"
echo "SOLEUR_GIT_REPO_DIAG ready=false git_dir=${git_dir_type} config_worktree=${cw_type} config_lock=${cl_type} rev_parse_rc=${wt_rc} config_parse_rc=${cfg_rc} err=\"$(sanitize "$err_text")\""
exit 0
