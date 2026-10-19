#!/usr/bin/env bash
# bare-root-cwd-guard.sh — PLUGIN-level SessionStart arm for the row-3 bare-repo-root
# misanchor (#10392). Same basename as .claude/hooks/bare-root-cwd-guard.sh on purpose:
# the dual-home naming convention lets the tree disambiguate the two arms (CTO ruling
# 2026-10-20). The repo arm reaches only this repo's sessions; THIS arm ships in the
# plugin payload and so reaches every other repository on a machine that installs it.
#
# Contract: always exits 0. On detection it emits exactly one SessionStart envelope
#   {"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext": …}}
# whose additionalContext carries one `SOLEUR_BARE_ROOT_CWD source=plugin-session-start`
# marker line followed by a bounded [bare-root-cwd] redirect block. Every other path —
# no jq, no .cwd, non-bare cwd, deduped repo — prints NOTHING: a SessionStart hook that
# cannot emit valid JSON must emit nothing.
#
# cwd resolution: the envelope's `.cwd` first (jq-gated; some harnesses omit it), then
# DEVIN_PROJECT_DIR → CLAUDE_PROJECT_DIR → $PWD.
#
# Detection is the SAME three-term config-FILE predicate as the repo arm, the
# bare-head-self-heal copy, and the copy inlined in
# plugins/soleur/skills/git-worktree/scripts/git-repo-readiness-diag.sh —
# plugins/soleur/test/git-repo-readiness-diag.test.sh D5 pins the three-way parity:
#   1. `root` is a repo ROOT in the ADR-099 row-3 layout: `<root>/.git` is a real
#      directory (not a file or symlink — a `gitdir:` redirect, a linked worktree, and
#      a symlinked .git all fail here), `core.bare` reads `true` from its config FILE
#      (never `--is-bare-repository`: ADR-173 records that a masked config reports true
#      for any normal clone — the exact false-positive #10392 forbids), and
#   2. `--absolute-git-dir` resolves to exactly that directory.
# A `git init --bare` repo (mirror, server repo) fails term 1 — its git dir IS the
# root, there is no `<root>/.git` — so a genuinely bare customer repo never gets a
# misapplied redirect (P2). A session in a real worktree exits earlier on
# `--show-toplevel`, which also keeps a bare-root SUBDIRECTORY silent: that narrowing
# is deliberate (go.md's --is-bare-repository routing guard is the in-bare-subdir
# backstop).
#
# Dedup (CTO ruling 2026-10-20): when the target repo already carries its own arm —
# BOTH a `SOLEUR_BARE_ROOT_CWD` marker under `.claude/hooks/*.sh` AND a settings/devin
# registry referencing `session-rules-loader.sh` — the repo arm reports the session and
# this arm stays silent. A vendored-but-unwired tree hits term 1 only, so this arm still
# fires there; over-suppression is the worse failure direction.
#
# Redirect text is topology-generic (`git worktree add`) — a customer repo does not
# carry this repo's .worktrees/ machinery. A soleur `worktree-manager.sh` hint line is
# appended ONLY when the plugin-side script exists.
#
# No `set -e`, by design: every step is an explicit `|| exit 0`.
set -uo pipefail

# jq gates everything: it parses the incoming envelope AND emits the outgoing one, so
# without it the only correct behavior is silence.
command -v jq >/dev/null 2>&1 || exit 0

# An inherited git-location variable overrides `cd` and `git -C` alike, and would aim
# every probe below at a different repository than the one named (same unset list as
# the repo arm and the readiness-diag copy — the parity suite pins the GIT_DIR arm).
unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
  GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE

# Shared context sanitizer (#10395): the emitted path enters agent context, so the
# strip runs through the lib when it is readable. Plugin-side copy lives under
# scripts/lib/ (the plugin ships only plugins/soleur/**); the repo-side copy lives at
# .claude/hooks/lib/ and is byte-equal (context-sanitize.test.sh pins `cmp`).
_plugin_hooks_dir=$(cd -P "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P) || exit 0
_ctx_lib="$_plugin_hooks_dir/../scripts/lib/context-sanitize.sh"
# shellcheck source=/dev/null
[[ -r "$_ctx_lib" ]] && . "$_ctx_lib"
unset _ctx_lib _plugin_hooks_dir
if ! declare -F soleur_ctx_sanitize >/dev/null 2>&1; then
  # Fallback — identical byte contract to the lib (C0 + DEL + NEL/LS/PS) so an
  # unreadable lib degrades to the same strip, never to zero protection. Octal
  # \177 for DEL: tr does not interpret \xHH. $'…' ANSI-C quoting is REQUIRED on
  # the sed patterns: BSD sed does not interpret bare '\xHH' and would silently
  # strip nothing.
  soleur_ctx_sanitize() {
    LC_ALL=C tr -d '\000-\037\177' \
      | LC_ALL=C sed -e $'s/\xc2\x85//g' -e $'s/\xe2\x80\xa8//g' -e $'s/\xe2\x80\xa9//g'
  }
fi

input=$(cat 2>/dev/null || true)
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)
if [[ -z "$cwd" ]]; then
  cwd="${DEVIN_PROJECT_DIR:-${CLAUDE_PROJECT_DIR:-$PWD}}"
fi
[[ -n "$cwd" ]] || exit 0
cd -- "$cwd" 2>/dev/null || exit 0
root=$(pwd -P) || exit 0

# A worktree answers --show-toplevel; only a bare shape falls through to the
# predicate. This is a worktree test, never a bareness test (Sharp Edges).
[[ -n "$(git rev-parse --show-toplevel 2>/dev/null)" ]] && exit 0

# Three-term ADR-099 row-3 predicate — fourth inline copy, parity-pinned.
[[ -d "$root/.git" && ! -L "$root/.git" ]] || exit 0
[[ "$(git config --file "$root/.git/config" --type=bool --get core.bare 2>/dev/null)" == "true" ]] || exit 0
git_dir=$(git rev-parse --absolute-git-dir 2>/dev/null) || exit 0
[[ "$git_dir" == "$root/.git" ]] || exit 0

# Dedup: the repo's own arm reports when it is BOTH present and wired. `grep -l` on
# the glob is the bounded, read-only probe; an unmatched glob or an absent registry
# file simply fails the term and this arm still fires.
if grep -lF 'SOLEUR_BARE_ROOT_CWD' "$root"/.claude/hooks/*.sh >/dev/null 2>&1 \
  && { grep -qs 'session-rules-loader\.sh' "$root/.claude/settings.json" 2>/dev/null \
    || grep -qs 'session-rules-loader\.sh' "$root/.devin/config.json" 2>/dev/null; }; then
  exit 0
fi

# Sanitize the path for context: envelope-supplied, so strip control characters
# (incl. DEL, NEL, and the U+2028/U+2029 line-break class — #10395) and cap it.
safe_root=$(printf '%s' "$root" | soleur_ctx_sanitize | cut -c1-200)

block="SOLEUR_BARE_ROOT_CWD source=plugin-session-start
[bare-root-cwd] ${safe_root} is a bare repository root with a synced overlay of HEAD, not a worktree.
[bare-root-cwd] Route file-touching work through a linked worktree:
[bare-root-cwd]   git worktree add <path> <branch>
[bare-root-cwd] then cd into the new worktree path before editing.
[bare-root-cwd] A .env at this root is NOT project configuration — do not read it as one."

# Soleur-hint line — gated on the plugin-side script existing on this machine
# (CTO ruling: the manager ships in the plugin payload, but the text is only
# emitted where it can actually run).
if [[ -n "${CLAUDE_PLUGIN_ROOT:-}" \
  && -f "${CLAUDE_PLUGIN_ROOT}/skills/git-worktree/scripts/worktree-manager.sh" ]]; then
  safe_wm=$(printf '%s' "${CLAUDE_PLUGIN_ROOT}/skills/git-worktree/scripts/worktree-manager.sh" \
    | soleur_ctx_sanitize | cut -c1-300)
  block+=$'\n'"[bare-root-cwd] Soleur worktree manager present: bash \"${safe_wm}\" --yes create <name>"
fi

jq -n --arg ctx "$block" \
  '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$ctx}}' 2>/dev/null \
  || exit 0
exit 0
