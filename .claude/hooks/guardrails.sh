#!/usr/bin/env bash
# PreToolUse guardrail hook for Bash AND Write|Edit commands.
# Bash: blocks commits on main, rm -rf on worktrees, a hardened recursive-delete
# ownership proof (repo/worktree roots, $HOME, /, .git-bearing checkouts),
# --delete-branch with active worktrees, commits with conflict markers in staged
# content, gh issue create without --milestone, git stash in worktrees.
# Write|Edit: enforces the freeze edit-lock (edits restricted to an active
# freeze prefix). Registered on both matchers in .claude/settings.json.
# NOTE: When adding or modifying guards, update the corresponding prose rule comments below.
#
# Corresponding prose rules:
#   guardrails:block-commit-on-main — constitution.md "Never allow agents to work directly on the default branch"
#   guardrails:block-rm-rf-worktrees — constitution.md "Never rm -rf on the current directory, a worktree path, or the repo root"
#   guardrails:block-recursive-delete — constitution.md "Never rm -rf a target that resolves onto a repo/worktree root (or an ancestor of either), $HOME, /, or a .git-bearing checkout"
#   guardrails:freeze-edit-lock — constitution.md "When a freeze is active, deny Write/Edit outside the allowed path prefix"
#   guardrails:block-delete-branch — constitution.md "Never use --delete-branch with gh pr merge"
#   guardrails:block-conflict-markers — constitution.md "grep staged content for conflict markers"
#   guardrails:require-milestone — constitution.md "GitHub Actions workflows and shell scripts that create issues must include --milestone"
#   guardrails:require-filing-justification — AGENTS.md wg-defer-only-after-inline-triage "a filing must name a user-visible consequence, a measured fix size, or the machinery ledger"
#   guardrails:block-stash-in-worktrees — AGENTS.md "Never git stash in worktrees"

set -euo pipefail

# shellcheck source=lib/incidents.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/incidents.sh"
# shellcheck source=lib/freeze-lock.sh
# Provides freeze_active_prefix (reader) for the freeze edit-lock branch below.
# Sourced (not run): its CLI-dispatch guard is BASH_SOURCE[0]==$0, which is
# false here, so no verb runs on source. FAIL-SOFT (|| true): freeze is an
# OPTIONAL feature — a missing/broken freeze helper must NEVER disarm the
# critical delete/commit/stash guards below (which do not depend on it). The
# freeze branch itself is additionally gated on `declare -f freeze_active_prefix`.
source "$(dirname "${BASH_SOURCE[0]}")/lib/freeze-lock.sh" 2>/dev/null || true

# shellcheck source=lib/hook-input.sh
# FAIL-HARD (no `|| true`): a fail-soft source leaves hook_parse_input
# undefined, the hook dies at the call under `set -e`, prints nothing, exits
# non-zero, and the tool proceeds — defect 2 of #7164, reintroduced one line
# above where every test points.
source "$(dirname "${BASH_SOURCE[0]}")/lib/hook-input.sh"

# The source above is fail-hard, but 12 of the 20 hooks run `set -uo pipefail`
# WITHOUT -e. There a missing helper makes hook_parse_input return 127, `!`
# inverts that to true, the response functions are 127 too, and the hook reaches
# `exit 0` — a clean pass-through with no row and no prompt, which is defect 2
# reintroduced by a broken deploy. Assert it explicitly instead of relying on -e.
if ! declare -f hook_parse_input >/dev/null 2>&1; then
  printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"SAFETY: .claude/hooks/lib/hook-input.sh is missing or unreadable, so PreToolUse guards did NOT run for this call. This is a broken deploy, not a transient fault \u2014 reinstall the hooks before continuing."}}'
  echo "[guardrails] hook-input helper missing — guards did NOT run for this call" >&2
  exit 0
fi

INPUT=$(cat)
# Single jq fork, and NO shell evaluation of hook input. The previous comment
# here claimed `@sh` made `eval` safe. That held only for a STRING: `@sh`
# quotes each element of an ARRAY as a separate word, so an array
# .tool_input.command produced an assignment followed by a COMMAND, which eval
# ran (#7164). FILE_PATH is extracted here too so the freeze edit-lock branch
# (Write/Edit) shares the same single fork.
# Parse hook stdin WITHOUT shell evaluation (ADR-156: stdin is
# model-controlled and untrusted). A non-string field is surfaced, never
# coerced — coercion closes the RCE and leaves the guards evaded (#7164).
# ADR-157: a hook that cannot fully parse its input asks. The exit lives
# HERE, at the call site, not inside the library.
if ! hook_parse_input "$INPUT"; then
  hook_input_report "guardrails"
  hook_input_should_ask && { hook_input_emit_ask "guardrails"; exit 0; }
  exit 0
fi
COMMAND="$HOOK_CMD"
TOOL_NAME="$HOOK_TOOL_NAME"
FILE_PATH="$HOOK_FILE_PATH"
# Belt-and-braces against set -u: a partial eval (jq succeeded on one
# field, failed on another) could leave a variable undefined.
: "${COMMAND:=}"
: "${TOOL_NAME:=}"
: "${FILE_PATH:=}"

# guardrails:freeze-edit-lock — directory-scoped edit-lock for file-editing
# tools (Write/Edit/MultiEdit/NotebookEdit — registered on all four in
# .claude/settings.json). Placed ABOVE the Bash sentinels and gated on BOTH
# `file_path present` AND `command empty`: a Bash payload carries
# .tool_input.command and NO file_path, so this branch is skipped for Bash calls
# and CANNOT shadow the delete guards (TR3). Requiring `-z COMMAND` too is
# defense-in-depth — even if a future harness forwarded an extra file_path field
# on a Bash payload, the non-empty COMMAND keeps this branch skipped so the Bash
# sentinels still run. Fail-open: no active freeze (or a malformed state file)
# => freeze_active_prefix echoes nothing => edit allowed (OQ2 blast-radius).
if [[ -n "$FILE_PATH" && -z "$COMMAND" ]] && declare -f freeze_active_prefix >/dev/null 2>&1; then
  ALLOWED=$(freeze_active_prefix) || ALLOWED=""
  if [[ -n "$ALLOWED" ]]; then
    RESOLVED=$(realpath -m "$FILE_PATH" 2>/dev/null || echo "$FILE_PATH")
    case "$RESOLVED" in
      "$ALLOWED"|"$ALLOWED"/*) : ;;   # inside the allowed prefix — allow
      *)
        emit_incident "guardrails-freeze-edit-lock" "deny" "Edit outside the active freeze prefix" "$FILE_PATH"
        jq -n --arg p "$RESOLVED" --arg a "$ALLOWED" '{
          hookSpecificOutput: {
            hookEventName: "PreToolUse",            permissionDecision: "deny",
            permissionDecisionReason: ("BLOCKED: a freeze is active — edits are restricted to " + $a + ". Target " + $p + " is outside the allowed prefix. Edit within the prefix, or clear the freeze: bash .claude/hooks/lib/freeze-lock.sh clear")
          }
        }'
        exit 0
        ;;
    esac
  fi
  # Write/Edit payloads do not carry a Bash command — the sentinels below
  # (all keyed on $COMMAND) do not apply. Exit here so no Bash-reachable path
  # ever hits a bare `exit 0` that could shadow the delete guard (TR3).
  exit 0
fi

# Derive a quote/heredoc-stripped view of the command ONCE (one perl fork per
# Bash invocation, alongside the existing jq + grep overhead). PHRASE-detecting
# gates (require-milestone, block-stash) scan $SCAN so a commit whose MESSAGE
# documents `gh issue create` / `git stash` is not mistaken for the real
# command (#5192). Gates that fire on `git commit` itself keep scanning
# $COMMAND — a commit that mentions "git commit" in its body still IS a commit.
SCAN=$(strip_command_bodies "$COMMAND")

# Bypass preflight — records (does NOT block) when a known bypass flag is used.
# Scope: --no-verify, -c core.hooksPath=…, HUSKY=0, --no-gpg-sign,
# -c commit.gpgsign=false, LEFTHOOK=0. See detect_bypass in lib/incidents.sh.
_bypass_rid=$(detect_bypass "$TOOL_NAME" "$COMMAND")
if [[ -n "$_bypass_rid" ]]; then
  emit_incident "$_bypass_rid" "bypass" "${COMMAND:0:50}" "$COMMAND"
fi

# guardrails:block-commit-on-main — Block git commit on main branch
# Match git commit at start of string OR after chain operators (&&, ||, ;)
# so chained commands like "git add && git commit" are caught.
# Scans $COMMAND (NOT $SCAN): this gates the REAL commit, so a message body
# mentioning "git commit" still IS a commit — no false-positive class here.
if grep -qE '(^|&&|\|\||;)\s*git\s+commit' <<<"$COMMAND"; then
  # Resolve the branch from the command's working directory, not the hook's CWD.
  # resolve_command_cwd (lib/incidents.sh) covers: "cd /worktree && ...",
  # "git -C /worktree commit", and hook-input .cwd. Falls through to the
  # hook's own CWD if none resolve.
  GIT_DIR=$(resolve_command_cwd "$COMMAND" "$INPUT")
  if [ -n "$GIT_DIR" ] && [ -d "$GIT_DIR" ]; then
    BRANCH=$(git -C "$GIT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  else
    BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  fi
  if [ "$BRANCH" = "main" ] || [ "$BRANCH" = "master" ]; then
    emit_incident "guardrails-block-commit-on-main" "deny" "Never allow agents to work directly on default branch" "$COMMAND"
    jq -n '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",        permissionDecision: "deny",
        permissionDecisionReason: "BLOCKED: Committing directly to main/master is not allowed. Create a feature branch first."
      }
    }'
    exit 0
  fi
fi

# guardrails:block-rm-rf-worktrees — Block rm -rf on worktree paths
# Match rm with recursive-force flags followed by a worktree path as an argument.
# Uses a single pattern to avoid false positives when .worktrees/ appears in
# unrelated text (e.g., inside a gh issue comment body or heredoc).
if grep -qE 'rm\s+(-[a-zA-Z]*r[a-zA-Z]*f[a-zA-Z]*|-[a-zA-Z]*f[a-zA-Z]*r[a-zA-Z]*)\s+\S*\.worktrees/' <<<"$COMMAND"; then
  emit_incident "guardrails-block-rm-rf-worktrees" "deny" "Never rm -rf on a worktree path" "$COMMAND"
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",      permissionDecision: "deny",
      permissionDecisionReason: "BLOCKED: rm -rf on worktree paths is not allowed. Use git worktree remove or worktree-manager.sh cleanup-merged instead."
    }
  }'
  exit 0
fi

# guardrails:block-recursive-delete — hardened ownership proof for rm -rf.
# Runs AFTER the narrow .worktrees/ gate above (kept as a fast, regression-
# covered subset). Model: default-allow-except-protected — every non-protected
# recursive delete (rm -rf build/, node_modules, /tmp/x) passes through; the
# hardening only ADDS deny cases for a protected class that a literal-substring
# grep misses: a symlink- or relative-path-obfuscated target that RESOLVES onto
# the repo root, a git worktree root (or an ancestor of either), $HOME, /, or a
# .git-bearing checkout.
#
# The realpath here is a DENY-DECISION resolver (resolving symlinks makes the
# guard STRONGER — it catches `rm -rf ./link` → repo root). This is the OPPOSITE
# direction from the constitution.md "bulk-cleanup helper ... never call realpath
# before deciding to remove" rule, which forbids realpath in a delete-EXECUTOR
# (resolving before removal weakens it, CWE-59). Different code paths; do not
# conflate them.
#
# SCOPE (this is a lexical PRE-EXEC guard, not a shell — like no-memory-write.sh
# it exists to stop ACCIDENTAL destructive deletes onto protected paths, not to
# defeat determined evasion). It sees the command string BEFORE the shell applies
# expansion / alias / PATH / glob. It covers: literal absolute + relative +
# symlinked targets; the common protected shell refs `~`, `$HOME`, `${HOME}`,
# `$PWD`, `${PWD}` (expanded below); and `rm` invoked bare, path-qualified
# (`/bin/rm`), backslash-escaped (`\rm`), or behind `sudo`/`env`/`command`.
# It CANNOT see: arbitrary `$VAR`/`$(cmd)` targets, aliases, `xargs rm` /
# `find … -exec rm`, or the entries a glob (`rm -rf *`, `rm -rf ./*`) will expand
# to (git-recoverable; `/` and `.git` survive default globbing). Multi-`cd`
# chains resolve relative targets against only the FIRST `cd` (shared
# resolve_command_cwd limitation). Detection runs against $SCAN (heredoc/quoted
# commit-message bodies blanked) so a commit whose MESSAGE documents `rm -rf`
# does not false-deny, while a real chained `rm` after the body is preserved and
# tokenized from the raw $COMMAND (so a quoted path ARGUMENT is still checked).
if grep -qE '(^|[[:space:]]|&&|\|\||;|\|)[^[:space:]]*rm[[:space:]]+(-[a-zA-Z]*r[a-zA-Z]*f[a-zA-Z]*|-[a-zA-Z]*f[a-zA-Z]*r[a-zA-Z]*)' <<<"$SCAN"; then
  # Resolve the command's working directory so relative targets resolve the same
  # way the shell would (cd <dir> && ..., git -C <dir>, hook .cwd, else $PWD).
  # `|| _rd_cwd=""` is belt-and-braces: resolve_command_cwd returns 0 today, but
  # a future edit ending it in a non-zero command must not abort the hook mid-
  # guard under set -e (which would silently skip the delete guard).
  _rd_cwd=$(resolve_command_cwd "$COMMAND" "$INPUT") || _rd_cwd=""
  [[ -n "$_rd_cwd" && -d "$_rd_cwd" ]] || _rd_cwd="$PWD"

  # Enumerate protected roots. git worktree list yields the main checkout + all
  # worktree roots; best-effort (git may not resolve from a non-repo cwd). $HOME
  # is always protected.
  _protected_roots=()
  while IFS= read -r _wl; do
    [[ "$_wl" == worktree\ * ]] && _protected_roots+=("${_wl#worktree }")
  done < <(git -C "$_rd_cwd" worktree list --porcelain 2>/dev/null || true)
  [[ -n "${HOME:-}" ]] && _protected_roots+=("$HOME")

  # Quote-aware tokenization (xargs -n1 honors shell quoting; chain operators
  # &&/||/;/| survive as their own tokens). Walk rm invocations, collecting
  # non-flag args as delete targets and resetting at each chain boundary. Tokens
  # are taken from the raw $COMMAND so a quoted path argument is preserved
  # (detection above used $SCAN only to gate on a real, non-message `rm`).
  _rd_toks=()
  mapfile -t _rd_toks < <(printf '%s\n' "$COMMAND" | xargs -n1 2>/dev/null) || true
  _in_rm=0
  _targets=()
  _ti=0
  while (( _ti < ${#_rd_toks[@]} )); do
    _t="${_rd_toks[$_ti]}"
    _ti=$((_ti + 1))
    _t="${_t#\\}"   # normalize a backslash-escaped `\rm` → `rm`
    case "$_t" in
      rm|*/rm)           _in_rm=1; continue ;;   # bare, /bin/rm, ./rm, \rm
      "&&"|"||"|";"|"|") _in_rm=0; continue ;;
    esac
    [[ "$_in_rm" == 1 && "$_t" != -* ]] && _targets+=("$_t")
  done

  _tj=0
  while (( _tj < ${#_targets[@]} )); do
    _tg="${_targets[$_tj]}"
    _tj=$((_tj + 1))
    # Expand the common protected shell references BEFORE realpath — a lexical
    # guard sees these literal tokens, but the shell expands them at exec onto a
    # protected target (3 review agents flagged the $HOME/~/$PWD bypass). xargs
    # has already stripped surrounding quotes, so `"$HOME"` arrives as `$HOME`.
    # shellcheck disable=SC2088  # these are case PATTERNS matching the literal
    # `~` token the guard received, NOT a path we expand — the RHS expands it.
    case "$_tg" in
      "~")          _tg="${HOME:-}" ;;
      "~/"*)        _tg="${HOME:-}/${_tg#\~/}" ;;
      '$HOME'|'${HOME}') _tg="${HOME:-}" ;;
      '$HOME/'*)    _tg="${HOME:-}/${_tg#\$HOME/}" ;;
      '${HOME}/'*)  _tg="${HOME:-}/${_tg#'${HOME}'/}" ;;
      '$PWD'|'${PWD}')   _tg="$_rd_cwd" ;;
      '$PWD/'*)     _tg="$_rd_cwd/${_tg#\$PWD/}" ;;
      '${PWD}/'*)   _tg="$_rd_cwd/${_tg#'${PWD}'/}" ;;
    esac
    _res=$( (cd "$_rd_cwd" 2>/dev/null && realpath -m "$_tg" 2>/dev/null) || echo "" )
    # Fail-closed: an unresolvable target still gets checked in its raw form.
    [[ -z "$_res" ]] && _res="$_tg"
    _deny=0
    [[ "$_res" == "/" ]] && _deny=1
    [[ "$_deny" == 0 && -n "${HOME:-}" && "$_res" == "$HOME" ]] && _deny=1
    if [[ "$_deny" == 0 ]]; then
      _pi=0
      while (( _pi < ${#_protected_roots[@]} )); do
        _pr="${_protected_roots[$_pi]}"
        _pi=$((_pi + 1))
        [[ -z "$_pr" ]] && continue
        # Deny when the target IS a protected root OR an ancestor of one
        # (rm -rf of a parent dir destroys the checkout under it).
        if [[ "$_res" == "$_pr" || "$_pr" == "$_res"/* ]]; then _deny=1; break; fi
      done
    fi
    # A .git entry at the target root means it is a repository checkout.
    [[ "$_deny" == 0 && -e "$_res/.git" ]] && _deny=1
    if [[ "$_deny" == 1 ]]; then
      emit_incident "guardrails-block-recursive-delete" "deny" "Never rm -rf a protected root or checkout" "$COMMAND"
      jq -n --arg t "$_res" '{
        hookSpecificOutput: {
          hookEventName: "PreToolUse",          permissionDecision: "deny",
          permissionDecisionReason: ("BLOCKED: rm -rf resolves onto a protected location (" + $t + "). Repo roots, git worktree roots, $HOME, /, and any .git-bearing checkout are protected. Delete a specific non-protected subdirectory instead, or use git worktree remove.")
        }
      }'
      exit 0
    fi
  done
fi

# guardrails:block-delete-branch — Block gh pr merge --delete-branch when worktrees exist
# scans $SCAN (commit bodies/heredocs stripped — see lib/incidents.sh) so a
# commit message documenting `gh pr merge --delete-branch` is not mistaken for
# one (#5192 sweep — same phrase-class FP as require-milestone).
if grep -qE 'gh\s+pr\s+merge.*--delete-branch' <<<"$SCAN"; then
  WORKTREE_COUNT=$(git worktree list 2>/dev/null | wc -l)
  if [ "$WORKTREE_COUNT" -gt 1 ]; then
    emit_incident "guardrails-block-delete-branch" "deny" "Never use --delete-branch with gh pr merge" "$COMMAND"
    jq -n '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",        permissionDecision: "deny",
        permissionDecisionReason: "BLOCKED: --delete-branch with active worktrees will orphan them. Remove worktrees first, then merge."
      }
    }'
    exit 0
  fi
fi

# guardrails:block-conflict-markers — Block commits with conflict markers in staged content
# Matches git commit and git merge --continue (which internally commits).
# Allows optional -C <path> between git and commit/merge.
# Checks only added lines (^\+) to avoid blocking removal of markers.
# CWD resolution mirrors guardrails:block-commit-on-main via resolve_command_cwd.
# Scans $COMMAND (NOT $SCAN): gates the REAL commit / merge --continue.
#
# COUNTED PER FILE, with a repo-specific single-marker arm. Three facts drive this:
#
#  1. A single `^\+(<{7}|={7}|>{7})` line cannot tell an unresolved conflict from
#     PROSE THAT QUOTES ONE. `origin/main` carries a plan documenting the kb-index
#     merge driver whose fenced example is a lone `<<<<<<< kb-index: …` sentinel,
#     which made `git merge origin/main` uncommittable through this hook repo-wide
#     -- no override, and `--no-verify` does not reach a PreToolUse hook.
#
#  2. But "a real conflict always writes all three markers" is FALSE HERE. When a
#     merge driver exits non-zero git writes NO markers at all: it marks the path
#     `UU` and leaves ours-content in place, so the file reads as cleanly merged.
#     `scripts/merge-kb-index.sh` therefore writes its OWN lone `<<<<<<< kb-index:`
#     sentinel EXPRESSLY so this guard fires (see its header, and
#     merge-pr/SKILL.md). Requiring two types would silently disarm the only
#     mechanism that makes a failed INDEX.md merge visible -- discarding the other
#     side's index rows on commit. So that sentinel keeps a single-marker arm,
#     scoped to the file it can legitimately appear in.
#
#  3. Counting must be PER FILE. A global count lets two unrelated prose files
#     (one quoting `<<<<<<<`, one with a lone `=======`) satisfy a two-type rule
#     between them, and conversely says nothing about the types being in the same
#     region.
#
# `=` is anchored `^\+={7}\r?$` (exactly seven, alone, CRLF-tolerant; the `\+` is
# load-bearing -- it is what limits the gate to ADDED lines so removing markers is
# never blocked). Unanchored
# `={7}` also matched Markdown setext heading underlines and `=======` ASCII rules.
# `<`/`>` require space-or-EOL after the seventh character, which is git's own
# shape. `--no-color --no-ext-diff` is load-bearing: with `color.diff=always` or a
# `diff.external` configured, the diff arrives ANSI-wrapped, `^\+` never matches,
# and the guard silently allows a full triple.
if grep -qE '(^|&&|\|\||;)\s*git\s+(-C\s+\S+\s+)?(commit|(merge|rebase|cherry-pick|revert)\s+--continue)' <<<"$COMMAND"; then
  CONFLICT_MARKERS_DIR=$(resolve_command_cwd "$COMMAND" "$INPUT")
  # FAIL LOUD, not open. `2>/dev/null || true` made an errored `git diff` (an
  # index.lock race, a fork failure under memory pressure, a corrupt index)
  # indistinguishable from clean content -- the guard then silently allowed a
  # real conflict. Capture the status and ASK rather than allow.
  # NOT-A-REPO is not an anomaly: there is no staged content to guard, so the
  # gate simply does not apply. Only a diff that fails INSIDE a repository is
  # unexplained. Conflating the two fired `ask` on every non-git working
  # directory and short-circuited the gates below it -- caught by this file's
  # own pre-existing AC4 fixture, whose command chains `gh issue create` after a
  # `git commit` heredoc and expects the require-milestone gate to still run.
  if [ -n "$CONFLICT_MARKERS_DIR" ] && [ -d "$CONFLICT_MARKERS_DIR" ]; then
    CONFLICT_GIT=(git -C "$CONFLICT_MARKERS_DIR")
  else
    CONFLICT_GIT=(git)
  fi
  if ! "${CONFLICT_GIT[@]}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    IN_REPO=0
  else
    IN_REPO=1
  fi
  STAGED_DIFF=""
  DIFF_RC=0
  if [ "$IN_REPO" -eq 1 ]; then
    STAGED_DIFF=$("${CONFLICT_GIT[@]}" diff --cached --no-color --no-ext-diff 2>/dev/null); DIFF_RC=$?
  fi
  if [ "$IN_REPO" -eq 1 ] && [ "$DIFF_RC" -ne 0 ]; then
    emit_incident "guardrails-block-conflict-markers" "warn" "git diff --cached failed; cannot verify" "$COMMAND"
    jq -n '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",        permissionDecision: "ask",
        permissionDecisionReason: "COULD NOT VERIFY: `git diff --cached` failed, so staged content could not be checked for conflict markers. This is not a clean result — confirm the index is healthy before committing."
      }
    }'
    exit 0
  fi
  # A lone `>>>>>>>` denies on its own; the other arms need two types.
  # ASYMMETRIC ON PURPOSE, and the asymmetry is measured, not assumed. On
  # origin/main: `^>{7}( |$)` appears in ZERO files, `^<{7}( |$)` in exactly one
  # (the merge-driver plan that motivated this fix), and `^={7,}$` in seven
  # (setext underlines and ASCII rules). So a stray terminator has no
  # false-positive class here, while the other two do. That matters because the
  # commonest botched resolution deletes the opener and the `=======` and leaves
  # the trailing `>>>>>>> other` behind -- a two-type rule alone would pass it,
  # and in the .md files that dominate this repo nothing else would catch it.
  CONFLICT_HIT=$(awk '
    /^\+\+\+ b\// { path = substr($0, 7); lt = 0; eq = 0; next }
    /^\+<<<<<<< kb-index:/ {
      if (path == "knowledge-base/INDEX.md") { print "hit"; exit }
    }
    /^\+>>>>>>>( |$)/ { print "hit"; exit }
    /^\+<<<<<<<( |$)/ { lt = 1 }
    /^\+=======\r?$/  { eq = 1 }
    { if (lt + eq >= 2) { print "hit"; exit } }
  ' <<<"$STAGED_DIFF")
  if [ -n "$CONFLICT_HIT" ]; then
    emit_incident "guardrails-block-conflict-markers" "deny" "Resolve conflicts before committing" "$COMMAND"
    jq -n '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",        permissionDecision: "deny",
        permissionDecisionReason: "BLOCKED: Staged content contains an unresolved conflict — a file with two or more marker types, or the kb-index merge-driver sentinel in knowledge-base/INDEX.md. Resolve all conflicts before committing."
      }
    }'
    exit 0
  fi
fi

# guardrails:require-milestone — Block gh issue create without --milestone
# scans $SCAN (commit bodies/heredocs stripped — see lib/incidents.sh) so a
# commit message documenting `gh issue create` is not mistaken for one (#5192).
# The --repo/--milestone flag checks below intentionally read $COMMAND: on a
# real create those flags live OUTSIDE quotes and survive the strip, and on a
# commit-body FP this `if` never fires so they are never reached.
# CLASS 4 of the filing surface: `gh api .../issues -X POST` creates an issue
# without the word `create` anywhere. This repo has a DOCUMENTED instance of an
# agent routing around a block that way (see the 2026-06-11 posttooluse-hooks
# learning, which records a filing made via `gh api` after
# guardrails:require-milestone denied the `gh issue create` form). A blocking
# gate trains that route faster than an advisory one did, so the trigger covers
# both shapes. The MILESTONE arm below stays scoped to `gh issue create` --
# `gh api` takes no --milestone flag, so requiring one there would deny every
# legitimate API filing.
_gh_create=0; _gh_api_issue=0
grep -qE '(^|&&|\|\||;)\s*gh\s+issue\s+create' <<<"$SCAN" && _gh_create=1
grep -qE 'gh\s+api\b[^|]*\brepos/[^[:space:]]+/issues\b' <<<"$SCAN" \
  && grep -qE '(-X|--method)[[:space:]]+POST|-f[[:space:]]+title=|--field[[:space:]]+title=' <<<"$SCAN" \
  && _gh_api_issue=1
if [[ "$_gh_create" == 1 || "$_gh_api_issue" == 1 ]]; then
  # Exempt issue creation targeting an EXTERNAL repo (--repo owner/name where
  # owner is not our org). The constitution backlog-hygiene rule applies only to
  # OUR issues; external/vendor repos (e.g. upstream bug reports) have their own
  # milestone sets and forcing --milestone would fail against them.
  # Quote-aware tokenization: `xargs -n1` honors shell quoting, so a `--repo`
  # substring embedded in a quoted --title/--body value is NOT mistaken for a
  # real flag (it stays inside one token), and a quoted `--repo "jikig-ai/soleur"`
  # is recognized correctly. Only a standalone --repo/-R/--repo=/-R= token counts.
  # Fail toward GATING: if xargs errors (unbalanced quotes → empty tokens) or no
  # external target is found, the milestone gate stays on. If our own repo appears
  # in ANY --repo/-R flag, the gate stays on regardless of other tokens.
  _repo_toks=(); _our_repo=0; _ext_repo=0
  mapfile -t _repo_toks < <(printf '%s\n' "$COMMAND" | xargs -n1 2>/dev/null) || true
  _ri=0
  while (( _ri < ${#_repo_toks[@]} )); do
    _rt="${_repo_toks[$_ri]}"; _rv=""
    case "$_rt" in
      --repo|-R) _rv="${_repo_toks[$((_ri + 1))]:-}" ;;
      --repo=*)  _rv="${_rt#--repo=}" ;;
      -R=*)      _rv="${_rt#-R=}" ;;
    esac
    case "$_rv" in
      jikig-ai/*) _our_repo=1 ;;
      */*)        _ext_repo=1 ;;
    esac
    _ri=$((_ri + 1))
  done
  # Gate only when no external target was named AND our own repo wasn't named
  # (our repo appearing anywhere wins, so an external token can't ungate it).
  if [[ "$_gh_create" == 1 ]] \
     && [[ "$_our_repo" == 1 || "$_ext_repo" == 0 ]] && ! grep -qF -- '--milestone' <<<"$COMMAND"; then
    emit_incident "guardrails-require-milestone" "deny" "gh issue create must include --milestone" "$COMMAND"
    jq -n '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",        permissionDecision: "deny",
        permissionDecisionReason: "BLOCKED: gh issue create must include --milestone. Default to '\''Post-MVP / Later'\'' for operational issues. Read knowledge-base/product/roadmap.md for feature issues."
      }
    }'
    exit 0
  fi

  # guardrails:require-filing-justification — a filing must name who it is for.
  #
  # Corresponding prose rule: wg-defer-only-after-inline-triage.
  # The full triple test lives HERE, not in the rule body, per
  # cq-agents-md-tier-gate: a rule that becomes [hook-enforced:] keeps its id,
  # its tag and a one-line pointer, and the enforcing artifact carries the prose.
  #
  #   (1) INLINE-FIRST. Measure the fix. If it lands as <=100 changed lines AND
  #       <=4 files, fix it inline -- do not file. The threshold is NOT invented
  #       here: ADR-131 records it moving from <=30 lines/<=2 files to <=100/<=4
  #       "with instrumentation", and ship-net-issue-flow-gate.sh quotes the same
  #       pair as "the cost-of-filing auto-flip" in its remediation text. A
  #       refusal naming a threshold nobody can trace is how the override reflex
  #       gets trained, so the citation is part of the gate.
  #       This is a SIZE test. If the blocker is AUTHORITY (an operator-only
  #       credential, a production decision) inline does not apply however small
  #       the diff would be -- such a filing takes the Mandated-By: exit.
  #   (2) CONCRETE TRIGGER. An observable signal saying "do this now": a date, a
  #       metric, a user report. If there is none, document it in place.
  #   (3) PLAUSIBLE IN ~6 MONTHS. Will that trigger fire within six months at
  #       current scale? If not, document it in place.
  #
  # WHY AT THE FILING SITE AND NOT THE MERGE BOUNDARY. net-issue-flow is per-PR
  # net-ZERO: perfectly enforced it holds the backlog at its CURRENT size
  # forever. Measured 2026-09-10 the repo ran ~2 filed per 1 closed every week
  # without exception, 1,455 open. Only a check at the moment of filing moves the
  # rate. See knowledge-base/project/learnings/workflow-patterns/
  # 2026-05-29-net-issue-flow-gate-at-filing-site-not-just-ship.md, where the
  # ship-side surfacing was bypassed precisely because filings happen in /work.
  #
  # THREE EXITS, ONE GATE, AND DELIBERATELY NO FOURTH. Exit 1 is free and always
  # available, so a purpose-named bypass marker would buy nothing an honest
  # `--label meta/machinery` does not, while reproducing the reflexive-override
  # pathology ADR-155 documents (net-issue-flow has been overridden 98 times).
  if [[ "$_our_repo" == 1 || "$_ext_repo" == 0 ]]; then
    _fj_pass=0

    # The taxonomy is shared with the backfill classifier so the two cannot
    # drift. Unreadable => FAIL TOWARD GATING: a gate that silently stops
    # matching is indistinguishable from a gate that passed, which is the exact
    # empty-telemetry-is-not-absence class this PR exists to remove.
    _fj_tax="${BASH_SOURCE[0]%/*}/lib/user-surface-taxonomy.txt"
    _fj_re=""
    if [[ -r "$_fj_tax" ]]; then
      _fj_re="$(grep -vE '^[[:space:]]*(#|$)' "$_fj_tax" | paste -sd'|' - || true)"
    fi
    if [[ -z "$_fj_re" ]]; then
      emit_incident "wg-defer-only-after-inline-triage" "deny" \
        "user-surface taxonomy unreadable at ${_fj_tax}" "$COMMAND"
      jq -n --arg p "$_fj_tax" '{
        hookSpecificOutput: {
          hookEventName: "PreToolUse", permissionDecision: "deny",
          permissionDecisionReason: ("BLOCKED: the user-surface taxonomy could not be read at " + $p + ". Failing toward gating rather than allowing an unchecked filing.")
        }
      }'
      exit 0
    fi

    # EXIT 1 — the machinery ledger. A finding about Soleur own guards, gates,
    # ledgers or probes does not need a user-visible consequence, because by
    # construction it has none. Free, always available, honest.
    #
    # READ A REAL FLAG TOKEN, NOT $COMMAND PROSE. An earlier form grepped the
    # whole command for `--label[= ]meta/machinery`, which is satisfied by the
    # string appearing inside a quoted --body -- so merely MENTIONING the flag
    # in prose opened the free exit. That is the bare-token class
    # (cq-assert-anchor-not-bare-token) inside the gate built to enforce it, and
    # no mutation of the guard can surface it because the guard was working
    # exactly as written; it took an escape corpus. Reuse the quote-aware
    # `_repo_toks` tokenizer already computed above: `xargs -n1` honours shell
    # quoting, so a --label inside a quoted value stays inside ONE token and is
    # never mistaken for a flag.
    #
    # TWO SYNTAXES, ONE EXIT. `--label` is the `gh issue create` spelling; the
    # `gh api` POST form the trigger above also covers has no --label flag at
    # all and spells the same thing `-f 'labels[]=meta/machinery'`. Reading only
    # the first made exit 1 UNREACHABLE for every api-form filing -- measured:
    # `gh api .../issues -X POST -f 'labels[]=meta/machinery'` was denied, so an
    # honest machinery filing on that route had no exit but 2 or 3, which pushes
    # a machinery finding onto the product ledger. That is the same consequence
    # as the --body-file gap, one syntax over.
    #
    # COMMA-JOINED VALUES COUNT. `--label` is a cobra StringSlice, so
    # `--label meta/machinery,type/bug` is ordinary, documented gh syntax.
    # Exact-equality against the whole value denied it -- and the refusal told
    # the filer to add the very flag they had just passed. Split on commas and
    # anchor each element between commas, so `foo/meta/machinery` still does not
    # match (the anchor requires a comma, not a slash, before the element).
    _fj_li=0
    while (( _fj_li < ${#_repo_toks[@]} )); do
      _fj_t="${_repo_toks[$_fj_li]}"; _fj_v=""
      case "$_fj_t" in
        --label|-l) _fj_v="${_repo_toks[$((_fj_li + 1))]:-}" ;;
        --label=*)  _fj_v="${_fj_t#--label=}" ;;
        -l=*)       _fj_v="${_fj_t#-l=}" ;;
        # gh api field flags: -f/--field (and the raw variants) carry
        # `labels[]=<one label>`. gh sends one field per label, so there is no
        # comma form here, but running it through the same anchor is harmless.
        -f|--field|--raw-field)
          _fj_fv="${_repo_toks[$((_fj_li + 1))]:-}"
          [[ "$_fj_fv" == labels\[\]=* ]] && _fj_v="${_fj_fv#labels[]=}" ;;
        labels\[\]=*) _fj_v="${_fj_t#labels[]=}" ;;
      esac
      case ",${_fj_v}," in *,meta/machinery,*) _fj_pass=1 ;; esac
      _fj_li=$((_fj_li + 1))
    done

    # THE BODY CORPUS. Read `--body-file` when present, because that is the form
    # this repo PRESCRIBES (`review/SKILL.md`: "Use `gh issue create --body-file
    # <path>` -- never `--body \"$VAR\"`", and work/SKILL.md's operator-step gate
    # says the same). Reading only $COMMAND made exits 2 and 3 structurally
    # unreachable for the prescribed shape: every correctly-formed user-facing
    # filing was denied unless it took exit 1, which would have pushed real
    # product issues onto the machinery ledger and corrupted the very separation
    # this gate exists to create. The guard must accept the command shape the
    # guard itself prescribes.
    #
    # Declared-but-unreadable FAILS TOWARD GATING and names the path: we cannot
    # verify a justification we cannot read, and a silent pass here would make
    # the gate trivially bypassable by pointing at a nonexistent file.
    # The corpus is the BODY VALUE, whichever way it is supplied -- not the raw
    # command line. Anchoring whole-line against $COMMAND can never match an
    # inline --body, because the whole invocation is one physical line; the
    # tokenizer gives us the value with its quoting resolved and its embedded
    # newlines intact, which is what both gates actually reason about.
    _fj_body="$COMMAND"
    _fj_bf=""
    _fj_bi=0
    while (( _fj_bi < ${#_repo_toks[@]} )); do
      _fj_bt="${_repo_toks[$_fj_bi]}"
      case "$_fj_bt" in
        --body-file|-F) _fj_bf="${_repo_toks[$((_fj_bi + 1))]:-}" ;;
        --body-file=*)  _fj_bf="${_fj_bt#--body-file=}" ;;
      esac
      _fj_bi=$((_fj_bi + 1))
    done
    if [[ -n "$_fj_bf" ]]; then
      if [[ "$_fj_bf" != "-" && -r "$_fj_bf" ]]; then
        _fj_body="$(cat -- "$_fj_bf" 2>/dev/null || true)"
      else
        emit_incident "wg-defer-only-after-inline-triage" "deny" \
          "--body-file unreadable at ${_fj_bf}" "$COMMAND"
        jq -n --arg f "$_fj_bf" '{
          hookSpecificOutput: {
            hookEventName: "PreToolUse", permissionDecision: "deny",
            permissionDecisionReason: ("BLOCKED: --body-file names " + $f + ", which this gate cannot read, so the filing justification cannot be verified. Write the body file first (a separate step), then run gh issue create. Reading from stdin (-F -) is not supported here for the same reason.")
          }
        }'
        exit 0
      fi
    fi

    # EXIT 3 — a rule MANDATES this filing. Same closed, human-gated vocabulary
    # ADR-155 established, which is what makes the mandating gate and this
    # restricting gate ONE gate rather than two that disagree. This hook does not
    # re-derive the tagged set -- that is net-issue-flow.sh job, from the
    # merge-base corpus. It accepts a well-formed claim and lets the merge
    # boundary adjudicate it. Two gates, one vocabulary, no second pin.
    if [[ "$_fj_pass" == 0 ]] \
       && grep -qE '(^|[^A-Za-z0-9_-])Mandated-By:[[:space:]]*(hr|wg)-[a-z0-9-]+' <<<"$_fj_body"; then
      # The leading class is [^A-Za-z0-9_-], NOT [[:space:]]: in a real command the
      # field sits immediately after `--body "`, so a whitespace-or-start anchor
      # never fires on the shape that actually reaches this hook.
      #
      # KNOWN RESIDUAL, stated rather than papered over: the two gates share a
      # vocabulary but not a GRAMMAR. net-issue-flow.sh anchors the same claim
      # whole-line (`^[ \t\r]*[Mm]andated-[Bb]y:[ \t\r]*[A-Za-z0-9-]+[ \t\r]*$`)
      # over the issue BODY. A claim written mid-sentence, or in the --title,
      # previously passed HERE and was rejected THERE as "no Mandated-By claim" --
      # a remediation loop where the agent satisfies one gate and is refused by
      # the other with no message explaining the difference. That is the
      # `Tracks:` vs `Tracks #N` shape net-issue-flow.sh already documents as
      # measured. A whole-line anchor HERE is not the fix: this hook's corpus for
      # an inline `--body` is the one-line $COMMAND (xargs cannot preserve a
      # multi-line body value), so `^...$` would be unmatchable and would deny
      # three legitimate shapes -- measured, it broke exit 2, the 100/5 boundary
      # and the Inputs-Derived case. The actionable half is the REMEDIATION TEXT,
      # which now tells the filer the claim must be on its own line, so the loop
      # resolves on the first refusal instead of silently at merge.
      _fj_pass=1
    fi

    # EXIT 2 — a NAMED user-visible consequence AND a MEASURED fix size.
    _fj_ui=""
    _fj_n=""; _fj_m=""
    if [[ "$_fj_pass" == 0 ]]; then
      [[ "$_fj_body" =~ User-Impact:[[:space:]]*([^$'\n']+) ]] && _fj_ui="${BASH_REMATCH[1]}"
      # EXACTLY ONE Fix-Size, or the filing is malformed. bash `=~` binds the
      # FIRST match, so with two Fix-Size lines the author chooses which one the
      # gate reads: a large size first and the honest small size second evaded
      # the inline-threshold refusal entirely, while small-first correctly
      # denied -- which is precisely why it survived every fixture. Rather than
      # picking a side (last-wins is equally arbitrary and equally gameable),
      # refuse the ambiguity: one measured size, or none.
      _fj_fs_count="$(grep -cE 'Fix-Size:[[:space:]]*[0-9]+[[:space:]]*lines?[[:space:]]*/[[:space:]]*[0-9]+[[:space:]]*files?' <<<"$_fj_body" || true)"
      if [[ "$_fj_fs_count" == "1" ]] \
         && [[ "$_fj_body" =~ Fix-Size:[[:space:]]*([0-9]+)[[:space:]]*lines?[[:space:]]*/[[:space:]]*([0-9]+)[[:space:]]*files? ]]; then
        _fj_n="${BASH_REMATCH[1]}"; _fj_m="${BASH_REMATCH[2]}"
      fi
      if [[ -n "$_fj_ui" ]] && grep -qiE -- "\\b(${_fj_re})\\b" <<<"$_fj_ui" \
         && [[ -n "$_fj_n" && -n "$_fj_m" ]]; then
        # Inside the inline threshold => REFUSE. This is the check that catches
        # the 19-lines-in-1-file deferral: the size is not an adjective, so it
        # cannot be talked past.
        if (( _fj_n <= 100 && _fj_m <= 4 )); then
          emit_incident "wg-defer-only-after-inline-triage" "deny" \
            "fix-size ${_fj_n} lines / ${_fj_m} files is inside the inline threshold" "$COMMAND"
          jq -n --arg n "$_fj_n" --arg m "$_fj_m" '{
            hookSpecificOutput: {
              hookEventName: "PreToolUse", permissionDecision: "deny",
              permissionDecisionReason: ("BLOCKED: Fix-Size: " + $n + (if $n == "1" then " line" else " lines" end) + " / " + $m + (if $m == "1" then " file" else " files" end) + " is INSIDE the inline threshold (<=100 lines AND <=4 files, per ADR-131 which records it moving from <=30/<=2 to <=100/<=4). Fix it inline in this PR instead of filing. If the blocker is AUTHORITY rather than size -- an operator-only credential or a production decision -- say so with a Mandated-By: <rule-id> line, which is a different exit.")
            }
          }'
          exit 0
        fi
        _fj_pass=1
      fi
    fi

    # DERIVABLE-INPUTS is a DENY PREDICATE, not a third field. A free-text field
    # that any single token satisfies enforces nothing -- the agent that wrote
    # "we lack the numbers" would proceed by appending a word. Making the CLAIM
    # itself the trigger, and requiring a concrete SOURCE CLASS rather than free
    # text, is strictly stronger while removing a field from the contract.
    if [[ "$_fj_pass" == 1 ]] \
       && grep -qiE 'would have to choose|we lack|lack the numbers|no numbers|unknown values|do not have the numbers|lacking the numbers' <<<"$_fj_body"; then
      if ! grep -qiE 'Inputs-Derived:[[:space:]]*.*(workflow run|ci run|run [0-9]|log|telemetry|marker|measurement|probe|prior pr|pr [0-9]|dashboard|query)' <<<"$_fj_body"; then
        emit_incident "wg-defer-only-after-inline-triage" "deny" \
          "claims a missing-numbers blocker with no derivable-inputs source" "$COMMAND"
        jq -n '{
          hookSpecificOutput: {
            hookEventName: "PreToolUse", permissionDecision: "deny",
            permissionDecisionReason: "BLOCKED: this body claims the blocker is that the numbers are unknown. Before that becomes a filing, try to DERIVE them: add an Inputs-Derived: line naming a concrete source -- a workflow run, a log query, a telemetry marker, a measurement, or a prior PR. Measured precedent: a deferral blocked on choosing 19 timeout values was resolved in ~2 minutes from ten existing main runs."
          }
        }'
        exit 0
      fi
    fi

    if [[ "$_fj_pass" == 0 ]]; then
      emit_incident "wg-defer-only-after-inline-triage" "deny" \
        "gh issue create names no user-visible consequence" "$COMMAND"
      jq -n '{
        hookSpecificOutput: {
          hookEventName: "PreToolUse", permissionDecision: "deny",
          permissionDecisionReason: "BLOCKED: this filing names no user-visible consequence. Take ONE of three exits. (1) It is a finding about Soleur own verification machinery -- add --label meta/machinery. That ledger is excluded from the operator digest and from user-facing drains, and is the honest home for a guard/gate/ledger/probe finding. (2) It affects something a user receives -- add two lines to the body: `User-Impact: <named route, page, component, CLI command, email or document>` and `Fix-Size: <N> lines / <M> files` measured, not estimated. (3) A rule mandates the filing -- add `Mandated-By: <rule-id>` ON ITS OWN LINE in the body (the merge-boundary gate anchors it whole-line, so a claim written mid-sentence or in the title passes here and is refused there). \"The guard is imperfect\" is exit 1, not exit 2."
        }
      }'
      exit 0
    fi
  fi
fi

# guardrails:block-stash-in-worktrees — Block git stash unconditionally
# Unconditional: CWD detection is unreliable in subagent contexts where the shell
# CWD is a worktree but no explicit "cd" prefix appears in the command. Blocking
# git stash everywhere is safe — AGENTS.md requires "commit WIP first" and there
# is no legitimate automated use case for git stash in this repo.
# scans $SCAN (commit bodies/heredocs stripped — see lib/incidents.sh) so a
# commit message documenting "never git stash" is not mistaken for one (#5192).
if grep -qE '(^|&&|\|\||;)\s*git\s+stash' <<<"$SCAN"; then
  emit_incident "hr-never-git-stash-in-worktrees" "deny" "Never git stash in worktrees" "$COMMAND"
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",      permissionDecision: "deny",
      permissionDecisionReason: "BLOCKED: git stash is not allowed. Use git show <commit>:<path> to inspect old code, or commit WIP first."
    }
  }'
  exit 0
fi

# All checks passed
exit 0
