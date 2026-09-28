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
# Bash invocation, plus the filing lexer's fork and, for a `gh api` command, the
# floor's -- see the filing gate below). PHRASE-detecting
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
# Match git commit at start of string OR after chain operators (&&, ||, ;, |)
# so chained commands like "git add && git commit" are caught. Tolerates
# env-assignment prefixes (LEFTHOOK=0 git commit), a launcher (sudo/env/…),
# and git options between `git` and `commit` (-C dir, -c k=v, --git-dir=d) —
# the same width precommit-guard.sh detects; a narrower gate here would make
# those arms unreachable on the hook path.
# Scans $COMMAND (NOT $SCAN): this gates the REAL commit, so a message body
# mentioning "git commit" still IS a commit — no false-positive class here.
# The canonical check lives in plugins/soleur/scripts/precommit-guard.sh —
# plugin is the source of truth so work/ship/one-shot can invoke the identical
# check in sessions where hooks do not fire (Soleur Cloud Mode, FR5). This
# wrapper translates the script's refusal into the hook deny envelope.
if grep -qE '(^|[|;&])[[:space:]]*([A-Za-z_][A-Za-z_0-9]*=[^[:space:]]+[[:space:]]+)*((sudo|command|nice|env|xargs)[[:space:]]+)?([A-Za-z_][A-Za-z_0-9]*=[^[:space:]]+[[:space:]]+)*git([[:space:]]+(-C[[:space:]]+[^[:space:]]+|-c[[:space:]]+[^[:space:]]+|--git-dir=[^[:space:]]+|--git-dir[[:space:]]+[^[:space:]]+|-[A-Za-z]))*[[:space:]]+commit' <<<"$COMMAND"; then
  REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
  GUARD="$REPO_ROOT/plugins/soleur/scripts/precommit-guard.sh"
  if [ -n "$REPO_ROOT" ] && [ -x "$GUARD" ]; then
    HOOK_CWD=$(jq -r '.cwd // empty' <<<"$INPUT" 2>/dev/null || echo "")
    if ! bash "$GUARD" --cwd "$HOOK_CWD" "$COMMAND" >/dev/null 2>&1; then
      emit_incident "guardrails-block-commit-on-main" "deny" "Never allow agents to work directly on default branch" "$COMMAND"
      jq -n '{
        hookSpecificOutput: {
          hookEventName: "PreToolUse",        permissionDecision: "deny",
          permissionDecisionReason: "BLOCKED: Committing directly to main/master is not allowed. Create a feature branch first."
        }
      }'
      exit 0
    fi
  else
    # Plugin script unreachable — fall back to the inline check so the hook
    # never silently loses the guard when the plugin tree moves.
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
#  2. But "a real conflict always writes all three markers" is FALSE. The
#     commonest botched resolution deletes the opener and the `=======` and
#     leaves the trailing `>>>>>>> other` behind, which a two-type rule passes.
#     So a lone TERMINATOR keeps its own arm. The asymmetry is measured, not
#     assumed: on origin/main `^>{7}( |$)` appears in ZERO files while `^<{7}( |$)`
#     and `^={7,}$` both have large prose classes (fenced examples, setext
#     underlines, ASCII rules), so only the terminator is free of false positives.
#
#     A PATH-CONDITIONAL ARM USED TO LIVE HERE and was retired with the thing it
#     served (#8377 / ADR-235). A custom merge driver that exits non-zero makes git
#     write no markers at all -- it marks the path `UU` and leaves ours-content in
#     place, so the file reads as cleanly merged -- and the kb-index driver wrote a
#     lone sentinel into knowledge-base/INDEX.md expressly so this guard would fire.
#     That driver is gone and INDEX.md is an untracked cache, so the sentinel can no
#     longer be produced OR staged. .claude/hooks/guardrails.test.sh pins its absence
#     rather than its behaviour: re-adding any path-conditional arm reddens a passing
#     assertion, which is the signal the next reader of this awk should have to
#     override deliberately.
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
# shape. `--no-color` and `--no-ext-diff` are both load-bearing, for DIFFERENT
# mechanisms: `color.diff=always` wraps every line in ANSI so `^\+` never matches,
# while a `diff.external` replaces the patch body wholesale (no `+` lines at all).
# Either way the guard silently allows a full triple. `--src-prefix=a/ --dst-prefix=b/`
# and `--no-relative` are load-bearing the same way (#8263): the awk keys on the
# `+++ b/` header, and a user's `diff.mnemonicprefix`/`diff.noprefix` rewrites it
# (`+++ i/…`, `+++ …`) while `diff.relative` from a subdirectory drops INDEX.md
# from the diff. Each disarmed the kb-index sentinel arm, and the missed header
# also skipped the per-file reset, so counting went global and over-fired.
# `-c core.quotePath=false` closes the same over-fire on DEFAULT config, with no
# user setting involved: quotePath defaults to TRUE, so a non-ASCII filename is
# emitted as `+++ "b/caf\303\251.md"`, which `^\+\+\+ b/` does not match. Measured:
# a `<<<<<<< HEAD` line in one file plus a `=======` line in an unrelated
# accented-filename file made the counting go global and DENIED a clean commit.
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
    CONFLICT_GIT=(git -c core.quotePath=false -C "$CONFLICT_MARKERS_DIR")
  else
    CONFLICT_GIT=(git -c core.quotePath=false)
  fi
  if ! "${CONFLICT_GIT[@]}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    IN_REPO=0
  else
    IN_REPO=1
  fi
  STAGED_DIFF=""
  DIFF_RC=0
  if [ "$IN_REPO" -eq 1 ]; then
    # `if` (not `; DIFF_RC=$?`): under `set -e` a failed `git diff --cached`
    # aborts before the read -- which is exactly the failure the could-not-verify
    # arm below exists to report.
    if STAGED_DIFF=$("${CONFLICT_GIT[@]}" diff --cached --no-color --no-ext-diff \
      --src-prefix=a/ --dst-prefix=b/ --no-relative 2>/dev/null); then
      DIFF_RC=0
    else
      DIFF_RC=$?
    fi
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
    /^\+\+\+ (a|b|c|i|o|w)\// { lt = 0; eq = 0; next }
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
        permissionDecisionReason: "BLOCKED: Staged content contains an unresolved conflict — a file with two or more marker types, or a lone trailing `>>>>>>>`. Resolve all conflicts before committing."
      }
    }'
    exit 0
  fi
fi

# guardrails:require-milestone — Block gh issue create without --milestone
# guardrails:require-filing-justification — a filing must name who it is for.
#
# DETECTION (#9089, ADR-256) is the UNION of two detectors:
#
#   (a) lib/filing-shape.pl — a shell lexer. It finds every `gh issue create|new`
#       and every `gh api <issues collection>` POST bash would EXECUTE: inside
#       $(…), backticks, <(…), `bash|sh|zsh|dash|ksh -c` and `eval` strings,
#       unquoted-heredoc bodies, pipeline stages, groups, `if`/`for` bodies and
#       after any launcher (gh at any argv position). It emits one NUL-framed
#       record per filing carrying that filing's OWN exits (repo, milestone,
#       labels, body, body file), parsed with gh's value-taking flag tables, so
#       another command on the same line can no longer supply them. The
#       predicate it applies is bound to filingShape() in
#       apps/web-platform/server/inngest/cron-bash-allowlist-hook.mjs by the
#       shared corpus lib/filing-shape-corpus.json. Debug a false deny with
#       `perl .claude/hooks/lib/filing-shape.pl --trace <<<'<command>'`.
#
#   (b) THE FLOOR — main's detectors over $SCAN (commit bodies/heredocs and
#       quoted spans blanked, #5192): the CLASS 1 grep for `gh issue create`
#       and _api_pl for a `gh api …/issues` POST. They stay so nothing this
#       change does, and no way it fails, lets through a filing main denied
#       (PR7). Each reports a COUNT per shape; a shape whose floor count is
#       above the lexer's is a floor-only hit and denies. ADR-256 records when
#       the floor may go (three consecutive clean --differential runs).
#
# CLASS 4 of the filing surface: `gh api .../issues -X POST` creates an issue
# without the word `create` anywhere. This repo has a DOCUMENTED instance of an
# agent routing around a block that way (see the 2026-06-11 posttooluse-hooks
# learning, which records a filing made via `gh api` after
# guardrails:require-milestone denied the `gh issue create` form). The
# MILESTONE arm stays scoped to `gh issue create` -- `gh api` takes no
# --milestone flag, so requiring one there would deny every legitimate API
# filing. Only the issues COLLECTION creates an issue; a POST to
# `issues/<N>/labels`, `/comments` or `/assignees` edits an existing one.
#
# WHEN THE LEXER FAILS (no perl, exit 2 = the agent's own unbalanced quoting,
# exit 3 = a bound tripped, a truncated or malformed stream). ADR-256 is a
# scoped exception to ADR-157's "a hook that cannot parse its input asks …
# never denies": the exception covers only filing-shaped commands.
#
#   | condition                                        | decision                          |
#   |--------------------------------------------------|-----------------------------------|
#   | floor count > lexer count (any cause)            | deny (TOK_MSG when the cause is   |
#   |                                                  | exit2, else the parse message)    |
#   | exit2 and the filing indicator matches           | deny with TOK_MSG                 |
#   | any other failure and the indicator matches      | ask (allow under                  |
#   |                                                  | SOLEUR_DISABLE_HOOK_INPUT_ASK=1)  |
#   | the indicator does not match                     | allow (main's non-filing verdict) |
#
# The indicator runs in `grep -E` on the raw command with `\`-newline
# continuations joined -- never bash `[[ =~ ]]`, which is quadratic on a miss
# (36 KB took 3.3 s, measured). One incident code carries the cause as an enum
# and no payload (ADR-157 telemetry clause).
_FS_PL="${BASH_SOURCE[0]%/*}/lib/filing-shape.pl"
_FS_TOK_MSG="BLOCKED: the command could not be tokenized (unbalanced quoting); write the body to a file and pass --body-file"

_fg_deny() {
  local rid="$1" note="$2" reason="$3"
  emit_incident "$rid" "deny" "$note" "$COMMAND"
  jq -n --arg r "$reason" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse", permissionDecision: "deny",
      permissionDecisionReason: $r
    }
  }'
  exit 0
}

# THE FLOOR, counted. CLASS 1 is anchored on `^`/`&&`/`||`/`;` over $SCAN.
_fl_create=0; _fl_api=0
if grep -qE '(^|&&|\|\||;)\s*gh\s+issue\s+create' <<<"$SCAN"; then
  _fl_create="$(grep -oE '(^|&&|\|\||;)\s*gh\s+issue\s+create' <<<"$SCAN" | wc -l)" || _fl_create=1
  _fl_create=$((_fl_create + 0))
fi
if grep -qE 'gh\s+api\b' <<<"$SCAN"; then
  # _api_pl (the CLASS 4 floor): joins `\`-newline continuations, neutralises
  # escaped separators, drops redirect operators (`2>&1`, `&>`, `>&2`, `<&0`,
  # `>|` -- their `&`/`|` is not a separator), splits on `;&|`/newline only at
  # nesting depth 0, and counts the segments holding BOTH an issues-collection
  # endpoint and a POST signal. LINEAR: `gh\s+api\b` is found once per segment
  # and the endpoint is checked per whitespace token from its first `repos/`,
  # because the old `gh\s+api\b.*\brepos/\S+/issues` took 8.6 s on a 70 KB
  # padded input -- which outruns the non-blocking hook timeout on its own.
  _api_pl='
    s/\\\n/ /g;
    s/\\[;&|()]/_/g;
    s/>\|/> /g;
    s/(?<!\S)\d+(?=&>|[<>]&)//g;
    s/(?:&>>?|[<>]&)[\d-]*/ /g;
    my ($d, $bt, $cur, @seg) = (0, 0, "");
    for my $c (split //) {
      if ($c eq "`") { $bt = !$bt; $cur .= $c; next }
      if (!$bt) {
        if ($c eq "(") { $d++ }
        elsif ($c eq ")") { $d-- if $d > 0 }
        elsif ($d == 0 && $c =~ /[;&|\n]/) { push @seg, $cur; $cur = ""; next }
      }
      $cur .= $c;
    }
    push @seg, $cur;
    my ($hits, $input) = (0, 0);
    for my $s (@seg) {
      next unless $s =~ /gh\s+api\b/g;
      my $rest = substr($s, pos($s));
      my $ep = 0;
      for my $t (split /\s+/, $rest) {
        next unless $t =~ m{\brepos/}g;
        if (substr($t, pos($t)) =~ m{\S/issues(?:/?(?:[?#()<>`\\]|$)|[\$\}])}) { $ep = 1; last }
      }
      next unless $ep;
      next unless $s =~ /(?:-X|--method)[\s=]*POST\b|--input(?:[\s=]|$)|-[fF][\s=]*title=|--(?:raw-)?field[\s=]+title=/;
      $hits++;
      $input = 1 if $s =~ /--input(?:[\s=]|$)/;
    }
    print "$hits $input";'
  _api_rc=0
  _api_out="$(printf '%s' "$SCAN" | perl -0777 -ne "$_api_pl" 2>/dev/null)" || _api_rc=$?
  if [[ "$_api_rc" == 0 && "$_api_out" =~ ^([0-9]+)\ [01]$ ]]; then
    _fl_api="${BASH_REMATCH[1]}"
  elif grep -qE 'gh\s+api\b.*\brepos/[^[:space:]]+/issues' <<<"$SCAN" \
       && grep -qE '(-X|--method)[[:space:]=]*POST|--input|-[fF][[:space:]=]*title=|--(raw-)?field[[:space:]=]+title=' <<<"$SCAN"; then
    # perl unavailable or broken: a whole-command match that over-gates
    # sub-resource POSTs rather than letting a create through.
    _fl_api=1
  fi
fi

# THE LEXER. Records are read BY COUNT (never by searching for a sentinel)
# with a `read -d ''` loop -- `$(…)` and `mapfile` would drop the NUL framing
# or the exit code -- and the producer's status rides in as a final RC record,
# captured with `|| _fs_rc=$?`: the substitution inherits `set -e`, so a bare
# `; printf … "$?"` never runs when perl exits non-zero and every refusal
# would read as a truncated stream.
_fs_items=(); _fs_cause=""
if command -v perl >/dev/null 2>&1 && [[ -r "$_FS_PL" ]]; then
  while IFS= read -r -d '' _fs_x; do _fs_items+=("$_fs_x"); done \
    < <(_fs_rc=0; printf '%s' "$COMMAND" | perl "$_FS_PL" 2>/dev/null || _fs_rc=$?; printf 'RC\0%s\0' "$_fs_rc")
else
  _fs_cause="noperl"
fi
_fs_n=${#_fs_items[@]}
_fr_off=(); _fr_nf=(); _fr_shape=(); _fr_ctx=()
_lex_create=0; _lex_api=0
if [[ -z "$_fs_cause" ]]; then
  if (( _fs_n < 2 )) || [[ "${_fs_items[$((_fs_n - 2))]}" != "RC" ]]; then
    _fs_cause="trunc"
  elif [[ "${_fs_items[$((_fs_n - 1))]}" != "0" ]]; then
    case "${_fs_items[$((_fs_n - 1))]}" in
      2) _fs_cause="exit2" ;;
      3) _fs_cause="crash"
         if (( _fs_n >= 4 )) && [[ "${_fs_items[$((_fs_n - 4))]}" == "E" ]]; then
           case "${_fs_items[$((_fs_n - 3))]}" in
             depth|budget|alarm) _fs_cause="${_fs_items[$((_fs_n - 3))]}" ;;
           esac
         fi ;;
      *) _fs_cause="crash" ;;
    esac
  else
    _fi=0; _fs_ok=0
    while (( _fi < _fs_n - 2 )); do
      if [[ "${_fs_items[$_fi]}" == "F" ]] && (( _fi + 3 < _fs_n - 2 )) \
         && [[ "${_fs_items[$((_fi + 3))]}" =~ ^[0-9]+$ ]] \
         && (( _fi + 4 + ${_fs_items[$((_fi + 3))]} <= _fs_n - 2 )); then
        _fr_shape+=("${_fs_items[$((_fi + 1))]}")
        _fr_ctx+=("${_fs_items[$((_fi + 2))]}")
        _fr_nf+=("${_fs_items[$((_fi + 3))]}")
        _fr_off+=("$((_fi + 4))")
        case "${_fs_items[$((_fi + 1))]}" in
          create) _lex_create=$((_lex_create + 1)) ;;
          api)    _lex_api=$((_lex_api + 1)) ;;
        esac
        _fi=$((_fi + 4 + ${_fs_items[$((_fi + 3))]}))
      elif [[ "${_fs_items[$_fi]}" == "OK" ]] && (( _fi == _fs_n - 3 )); then
        _fs_ok=1; _fi=$((_fi + 1))
      else
        break
      fi
    done
    [[ "$_fs_ok" == 1 ]] || _fs_cause="trunc"
  fi
fi
if [[ -n "$_fs_cause" ]]; then
  _lex_create=0; _lex_api=0; _fr_shape=()
fi

# Floor-only: main's detectors saw more filings of a shape than the lexer did.
_fs_floor_only=0
(( _fl_create > _lex_create || _fl_api > _lex_api )) && _fs_floor_only=1

if [[ -n "$_fs_cause" || "$_fs_floor_only" == 1 ]]; then
  _fs_c="${_fs_cause:-floor-only}"
  _fs_ind=0
  if [[ "$_fs_floor_only" == 0 ]]; then
    grep -qE '\bgh\b.*(issue[^A-Za-z0-9_]+(create|new)|issues)' <<<"${COMMAND//$'\\\n'/}" && _fs_ind=1
  fi
  if [[ "$_fs_floor_only" == 1 || "$_fs_c" == "exit2" && "$_fs_ind" == 1 ]]; then
    emit_incident "guardrails-filing-lexer-failure" "deny" "cause=$_fs_c" ""
    if [[ "$_fs_c" == "exit2" ]]; then
      _fg_deny "wg-defer-only-after-inline-triage" "filing command could not be tokenized (unbalanced quoting)" "$_FS_TOK_MSG"
    fi
    _fg_deny "wg-defer-only-after-inline-triage" "filing gate could not parse the command" \
      "BLOCKED: the filing gate could not parse this command (${_fs_c}); run the filing as a plain top-level command with an absolute --body-file path."
  fi
  if [[ "$_fs_ind" == 1 ]]; then
    if [[ "${SOLEUR_DISABLE_HOOK_INPUT_ASK:-}" == "1" ]]; then
      emit_incident "guardrails-filing-lexer-failure" "warn" "cause=$_fs_c (ask suppressed)" ""
    else
      emit_incident "guardrails-filing-lexer-failure" "warn" "cause=$_fs_c" ""
      jq -n --arg c "$_fs_c" '{
        hookSpecificOutput: {
          hookEventName: "PreToolUse", permissionDecision: "ask",
          permissionDecisionReason: ("COULD NOT VERIFY: the filing gate could not parse this command (" + $c + "), so it cannot tell whether it files a GitHub issue. Approve only if it does not file an issue. Debug with: perl .claude/hooks/lib/filing-shape.pl --trace <<< \"<command>\". Set SOLEUR_DISABLE_HOOK_INPUT_ASK=1 to suppress this prompt.")
        }
      }'
      exit 0
    fi
  fi
fi

# One filing, gated on its OWN fields. Returns on a pass; denies and exits
# otherwise. Record r's fields are _fs_items[_fr_off[r] .. +_fr_nf[r]).
_gate_one_filing() {
  local r="$1"
  local shape="${_fr_shape[$r]}" ctx="${_fr_ctx[$r]}" off="${_fr_off[$r]}" nf="${_fr_nf[$r]}"
  local head="" repo="" has_repo=0 milestone=0 bodyfile="" has_bf=0 body="" has_body=0 bodyvar=0 varcorpus="" input=0
  local -a labels=()
  local k f
  for (( k = off; k < off + nf; k++ )); do
    f="${_fs_items[$k]}"
    case "$f" in
      head=*)      head="${f#head=}" ;;
      repo=*)      repo="${f#repo=}"; has_repo=1 ;;
      milestone=1) milestone=1 ;;
      label=*)     labels+=("${f#label=}") ;;
      bodyfile=*)  bodyfile="${f#bodyfile=}"; has_bf=1 ;;
      body=*)      body="${f#body=}"; has_body=1 ;;
      bodyvar=1)   bodyvar=1 ;;
      varcorpus=*) varcorpus="${f#varcorpus=}" ;;
      input=1)     input=1 ;;
    esac
  done

  # WHERE the filing runs, and where its exit therefore has to go (PR8).
  local where hint=""
  case "$ctx" in
    subst)    where='inside $(…)' ;;
    backtick) where='inside backticks' ;;
    shell-c)  where='inside a bash -c string' ;;
    eval)     where='inside an eval-ed string' ;;
    heredoc)  where='inside an unquoted heredoc body' ;;
    *)        where='at top level' ;;
  esac
  [[ "$ctx" == backtick || "$ctx" == heredoc ]] && \
    hint=" If that text is prose rather than a command, quote it: bash executes backticks and \$(…) in an unquoted heredoc."
  local sfx=" Refused filing: \`${head}\` ${where}; add the exit inside that same command, on the gh invocation itself.${hint}"

  # Exempt issue creation targeting an EXTERNAL repo (--repo owner/name where
  # owner is not our org). The backlog-hygiene rule applies only to OUR
  # issues; external/vendor repos have their own milestone sets. The repo is
  # THIS filing's last -R/--repo (gh keeps the last), normalized by the lexer
  # (scheme and host stripped, owner lowercased). A value holding `$` or a
  # backtick is never external: its owner is unknowable here.
  local our=0 ext=0
  if [[ "$has_repo" == 1 ]]; then
    case "$repo" in
      *'$'*|*'`'*) our=1 ;;
      jikig-ai/*)  our=1 ;;
      */*)         ext=1 ;;
    esac
  fi
  [[ "$our" == 1 || "$ext" == 0 ]] || return 0

  if [[ "$shape" == "create" && "$milestone" == 0 ]]; then
    _fg_deny "guardrails-require-milestone" "gh issue create must include --milestone" \
      "BLOCKED: gh issue create must include --milestone. Default to 'Post-MVP / Later' for operational issues. Read knowledge-base/product/roadmap.md for feature issues.${sfx}"
  fi

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
  # THREE EXITS ON THIS SURFACE, ONE GATE, AND DELIBERATELY NO FOURTH
  # NARRATABLE ONE. Exit 1 is free and always available, so a purpose-named
  # bypass marker would buy nothing an honest `--label meta/machinery` does
  # not, while reproducing the reflexive-override pathology ADR-155 documents
  # (net-issue-flow has been overridden 98 times). The cron substrate's mirror
  # (cron-bash-allowlist-hook.mjs) carries one more, exit 0, keyed on a file
  # the agent cannot read — not narratable, so not reproducible here (ADR-216
  # addendum, #8076).
  local pass=0

  # The taxonomy is shared with the backfill classifier so the two cannot
  # drift. Unreadable => FAIL TOWARD GATING: a gate that silently stops
  # matching is indistinguishable from a gate that passed, which is the exact
  # empty-telemetry-is-not-absence class this PR exists to remove.
  local tax="${BASH_SOURCE[0]%/*}/lib/user-surface-taxonomy.txt" re=""
  if [[ -r "$tax" ]]; then
    re="$(grep -vE '^[[:space:]]*(#|$)' "$tax" | paste -sd'|' - || true)"
  fi
  if [[ -z "$re" ]]; then
    _fg_deny "wg-defer-only-after-inline-triage" "user-surface taxonomy unreadable at ${tax}" \
      "BLOCKED: the user-surface taxonomy could not be read at ${tax}. Failing toward gating rather than allowing an unchecked filing."
  fi

  # --input sends the request body from a file or stdin, and gh then moves
  # every -f/-F field to the QUERY STRING -- so a `labels[]=meta/machinery` or
  # a body line passed as a field never reaches the new issue, and this gate
  # cannot read the JSON. Refuse with the recovery rather than crediting an
  # exit the filing does not actually carry.
  if [[ "$input" == 1 ]]; then
    _fg_deny "wg-defer-only-after-inline-triage" "gh api issue create via --input cannot be verified" \
      "BLOCKED: this gh api filing uses --input, so this gate cannot read its body or labels, and gh sends any -f/-F field to the query string instead of the issue. Drop --input and pass every field with -f: -f title=... -f body=... and, for a finding about Soleur own verification machinery, -f labels[]=meta/machinery. The body must then carry the justification (a User-Impact: + Fix-Size: pair, or a Mandated-By: line).${sfx}"
  fi

  # EXIT 1 — the machinery ledger. A finding about Soleur own guards, gates,
  # ledgers or probes does not need a user-visible consequence, because by
  # construction it has none. Free, always available, honest.
  # It reads THIS filing's label fields: `--label`/`-l` on the create form,
  # `-f 'labels[]=…'` on the api form (the lexer credits `labels[]=` only on
  # api field values). Merely NAMING the flag inside a quoted --body is prose,
  # not a flag -- the escape corpus that found that (2026-09-10-every-escape…)
  # is why this is a field, never a grep of the command. `--label` is a cobra
  # StringSlice, so `--label meta/machinery,type/bug` is ordinary gh syntax:
  # split on commas and anchor each element between commas, so
  # `foo/meta/machinery` still does not match.
  local l
  for l in "${labels[@]+"${labels[@]}"}"; do
    case ",${l}," in *,meta/machinery,*) pass=1 ;; esac
  done

  # THE BODY CORPUS. Read `--body-file` when present, because that is the form
  # this repo PRESCRIBES (`review/SKILL.md`: "Use `gh issue create --body-file
  # <path>` -- never `--body \"$VAR\"`"). Declared-but-unreadable FAILS TOWARD
  # GATING and names the path -- but ONLY WHEN THE BODY IS NEEDED: exit 1 is
  # decided from the labels alone, and the heredoc that WRITES the file is often
  # in the same Bash call, so it does not exist yet when this hook runs (FR7).
  # Otherwise the corpus is THIS filing's last literal body (gh keeps the last).
  # A body built from an expansion (`--body "$BODY"`) reads the variable corpus
  # -- this command's heredoc bodies and literal assignment values -- never the
  # whole command line, which another command's arguments could satisfy.
  local corpus=""
  if [[ "$has_bf" == 1 ]]; then
    if [[ "$bodyfile" != "-" && -r "$bodyfile" ]]; then
      corpus="$(cat -- "$bodyfile" 2>/dev/null || true)"
    elif [[ "$pass" == 0 ]]; then
      local rel=""
      [[ "$bodyfile" != /* && "$bodyfile" != "-" ]] && \
        rel=" Pass an absolute path: a relative path resolves against the hook's working directory, not yours."
      _fg_deny "wg-defer-only-after-inline-triage" "--body-file unreadable at ${bodyfile}" \
        "BLOCKED: --body-file names ${bodyfile}, which this gate cannot read, so the filing justification cannot be verified. Write the body file first (a separate step), then run gh issue create. Reading from stdin (-F -) is not supported here for the same reason.${rel}${sfx}"
    fi
  elif [[ "$has_body" == 1 ]]; then
    corpus="$body"
    [[ "$bodyvar" == 1 ]] && corpus="${varcorpus}"$'\n'"${body}"
  fi

  # EXIT 3 — a rule MANDATES this filing. Same closed, human-gated vocabulary
  # ADR-155 established, which is what makes the mandating gate and this
  # restricting gate ONE gate rather than two that disagree. This hook does not
  # re-derive the tagged set -- that is net-issue-flow.sh job, from the
  # merge-base corpus. The leading class is [^A-Za-z0-9_-], NOT [[:space:]]: an
  # inline body starts the value with the field. KNOWN RESIDUAL: net-issue-flow
  # anchors the claim whole-line over the issue BODY, so a mid-sentence claim
  # passes here and is refused there; the refusal text below says so.
  if [[ "$pass" == 0 ]] \
     && grep -qE '(^|[^A-Za-z0-9_-])Mandated-By:[[:space:]]*(hr|wg)-[a-z0-9-]+' <<<"$corpus"; then
    pass=1
  fi

  # EXIT 2 — a NAMED user-visible consequence AND a MEASURED fix size.
  local ui="" n="" m="" fs_count
  if [[ "$pass" == 0 ]]; then
    [[ "$corpus" =~ User-Impact:[[:space:]]*([^$'\n']+) ]] && ui="${BASH_REMATCH[1]}"
    # EXACTLY ONE Fix-Size, or the filing is malformed: with two, whichever the
    # regex binds first is the author's choice, which is not a measurement.
    fs_count="$(grep -cE 'Fix-Size:[[:space:]]*[0-9]+[[:space:]]*lines?[[:space:]]*/[[:space:]]*[0-9]+[[:space:]]*files?' <<<"$corpus" || true)"
    if [[ "$fs_count" == "1" ]] \
       && [[ "$corpus" =~ Fix-Size:[[:space:]]*([0-9]+)[[:space:]]*lines?[[:space:]]*/[[:space:]]*([0-9]+)[[:space:]]*files? ]]; then
      n="${BASH_REMATCH[1]}"; m="${BASH_REMATCH[2]}"
    fi
    if [[ -n "$ui" ]] && grep -qiE -- "\\b(${re})\\b" <<<"$ui" \
       && [[ -n "$n" && -n "$m" ]]; then
      # Inside the inline threshold => REFUSE: the size is not an adjective,
      # so it cannot be talked past.
      if (( n <= 100 && m <= 4 )); then
        local lw="lines" fw="files"
        [[ "$n" == 1 ]] && lw="line"
        [[ "$m" == 1 ]] && fw="file"
        _fg_deny "wg-defer-only-after-inline-triage" "fix-size ${n} lines / ${m} files is inside the inline threshold" \
          "BLOCKED: Fix-Size: ${n} ${lw} / ${m} ${fw} is INSIDE the inline threshold (<=100 lines AND <=4 files, per ADR-131 which records it moving from <=30/<=2 to <=100/<=4). Fix it inline in this PR instead of filing. If the blocker is AUTHORITY rather than size -- an operator-only credential or a production decision -- say so with a Mandated-By: <rule-id> line, which is a different exit."
      fi
      pass=1
    fi
  fi

  # DERIVABLE-INPUTS is a DENY PREDICATE, not a third field: making the CLAIM
  # itself the trigger, and requiring a concrete SOURCE CLASS rather than free
  # text, is strictly stronger than a field any token satisfies.
  if [[ "$pass" == 1 ]] \
     && grep -qiE 'would have to choose|we lack|lack the numbers|no numbers|unknown values|do not have the numbers|lacking the numbers' <<<"$corpus"; then
    if ! grep -qiE 'Inputs-Derived:[[:space:]]*.*(workflow run|ci run|run [0-9]|log|telemetry|marker|measurement|probe|prior pr|pr [0-9]|dashboard|query)' <<<"$corpus"; then
      _fg_deny "wg-defer-only-after-inline-triage" "claims a missing-numbers blocker with no derivable-inputs source" \
        "BLOCKED: this body claims the blocker is that the numbers are unknown. Before that becomes a filing, try to DERIVE them: add an Inputs-Derived: line naming a concrete source -- a workflow run, a log query, a telemetry marker, a measurement, or a prior PR. Measured precedent: a deferral blocked on choosing 19 timeout values was resolved in ~2 minutes from ten existing main runs."
    fi
  fi

  if [[ "$pass" == 0 ]]; then
    local x1="--label meta/machinery"
    [[ "$shape" == "api" ]] && x1="-f labels[]=meta/machinery (the gh api spelling)"
    _fg_deny "wg-defer-only-after-inline-triage" "gh issue create names no user-visible consequence" \
      "BLOCKED: this filing names no user-visible consequence. Take ONE of three exits. (1) It is a finding about Soleur own verification machinery -- add ${x1}. That ledger is excluded from the operator digest and from user-facing drains, and is the honest home for a guard/gate/ledger/probe finding. (2) It affects something a user receives -- add two lines to the body: \`User-Impact: <named route, page, component, CLI command, email or document>\` and \`Fix-Size: <N> lines / <M> files\` measured, not estimated. (3) A rule mandates the filing -- add \`Mandated-By: <rule-id>\` ON ITS OWN LINE in the body (the merge-boundary gate anchors it whole-line, so a claim written mid-sentence or in the title passes here and is refused there). \"The guard is imperfect\" is exit 1, not exit 2.${sfx}"
  fi
  return 0
}

for (( _fr = 0; _fr < ${#_fr_shape[@]}; _fr++ )); do
  _gate_one_filing "$_fr"
done

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
