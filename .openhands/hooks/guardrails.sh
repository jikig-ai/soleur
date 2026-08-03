#!/usr/bin/env bash
# PreToolUse guardrail hook for terminal AND file_editor tools (OpenHands port).
# Terminal: blocks commits on main, rm -rf on worktrees, a hardened recursive-
# delete ownership proof (repo/worktree roots, $HOME, /, .git-bearing checkouts),
# --delete-branch with active worktrees, commits with conflict markers, gh issue
# create without --milestone, git stash in worktrees.
# file_editor: enforces the freeze edit-lock (edits restricted to an active
# freeze prefix). Registered on both matchers in .openhands/hooks.json.
#
# OpenHands protocol: exit 2 + JSON {"decision":"deny","reason":"..."} to block.
# Input: HookEvent JSON on stdin with tool_input.command (terminal) /
# tool_input.path (file_editor) and working_dir.
#
# Corresponding prose rules: see .claude/hooks/guardrails.sh

set -euo pipefail

INPUT=$(cat)

# deny() is HOISTED above the extractions below, which now depend on it. It
# needs jq, which the availability gate immediately below has already proven.
deny() {
  jq -n --arg reason "$1" '{"decision":"deny","reason":$reason}'
  exit 2
}

# One constant, defined once. The reason text is agent-facing and was
# previously duplicated per extraction, in two different lengths, so how much
# the agent was told depended on which extraction happened to fail first.
#
# It names an action the AGENT CAN TAKE. The earlier wording ("re-send a
# well-formed envelope") named one it cannot: the agent authors tool_input
# values, while the runtime assembles the envelope, the working_dir and the
# JSON framing. The parity suite's own fixture puts the offending byte in
# working_dir, so on that payload the old text asked the agent to fix
# something it does not produce - and guardrails.sh is registered on BOTH
# matchers, so it would deny every tool the agent has, with no way forward.
UNPARSEABLE_REASON="BLOCKED: the tool-call envelope did not parse (ADR-156/ADR-162), so this hook's guards did not run and the call is refused rather than silently permitted. The usual cause is a byte in one of your tool arguments that cannot be encoded as JSON text - most often a lone surrogate from non-UTF-8 file content. Re-send with that value base64- or hex-encoded, or with the offending bytes dropped. If none of your arguments carry such a value the envelope was malformed in transport, which you did not author; re-sending unchanged may succeed."

# --- reason-class split (ADR-162) ----------------------------------------
# jq MISSING fails OPEN, loudly. ADR-157:115 rejects fail-closed here because
# the repair for a broken PATH or a missing jq is itself a tool call that would
# also be denied — and that argument bites HARDER on this harness, which has no
# `ask`, no operator-in-the-loop escalation and no kill switch. A deny on this
# class blocks its own repair.
if ! command -v jq >/dev/null 2>&1; then
  echo "[guardrails] jq missing — envelope unparseable, guards did NOT run for this call" >&2
  # FAIL OPEN, but not unconditionally. Failing open on this class is required
  # (ADR-157 §Alternatives Considered, "Fail closed": the repair for a broken
  # PATH or a missing jq is itself a tool call a deny would also block) — but an
  # UNCONDITIONAL open turns "delete jq" into a one-call disarm of every guard
  # in this file. So before proceeding, match the RAW document against the
  # narrow set of patterns whose guards are the reason this hook exists. The
  # repair commands themselves (apt-get install jq, export PATH=..., ln -s)
  # match none of these, so the recovery path stays open. Deliberately
  # over-broad in the other direction: on a branch that only runs when the
  # parser is gone, a false deny is the correct error.
  if grep -qE 'rm[[:space:]]+-[a-zA-Z]*[rf]|git[[:space:]]+stash|--delete-branch|git[[:space:]]+commit' <<<"$INPUT"; then
    printf '{"decision":"deny","reason":"BLOCKED: jq is unavailable, so the tool-call envelope cannot be parsed and this hook'"'"'s guards did not run — and the raw envelope matches a protected pattern. Repair jq first (install it, or fix PATH), then re-send."}\n'
    exit 2
  fi
  exit 0
fi

# A document jq REJECTS is a different class and it DENIES. Until now these
# three extractions ran under `set -euo pipefail` with no failure branch, so any
# document jq rejected killed the script at this line — rc 5, no deny, no
# decision JSON, no incident row — BEFORE the ADR-156 shape check below ever
# ran. A lone surrogate in a sibling field is enough to induce it while
# .tool_input.command stays a clean `rm -rf $HOME`: OpenHands is Python,
# json.dumps re-emits \ud800, and the document is valid to its parser and
# invalid to jq. Whether that was a silent bypass or a loud abort depended
# entirely on how the runtime treats a non-0/2 exit code — an invariant this
# repo does not define, which is exactly what ADR-156 forbids depending on.
# The deny is recoverable in-band: the reason string returns to the agent,
# which can re-send a well-formed envelope.
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null) \
  || deny "$UNPARSEABLE_REASON"
HOOK_CWD=$(printf '%s' "$INPUT" | jq -r '.working_dir // ""' 2>/dev/null) \
  || deny "$UNPARSEABLE_REASON"
# OpenHands file_editor uses "path"; fall back to "file_path" for compatibility.
FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.path // .tool_input.file_path // ""' 2>/dev/null) \
  || deny "$UNPARSEABLE_REASON"

# Freeze reader — cross-tree to the shared helper. freeze-lock.sh resolves the
# freeze state file from its OWN BASH_SOURCE (three dirs up from
# .claude/hooks/lib/ = repo root), so both harnesses read the SAME state. Source
# FAIL-SOFT: a missing/broken freeze helper must never disarm the guards below.
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../../.claude/hooks/lib/freeze-lock.sh" 2>/dev/null || true

# --- ADR-156 (mirror): the HookEvent envelope is MODEL-CONTROLLED ------------
# This port never calls eval, so it is not vulnerable to the #7164 code
# execution. It is still EVADABLE by the same payload: `jq -r` renders a
# non-string field across multiple lines, which matches none of the anchored
# guards below, so an array .tool_input.command would slip every gate in this
# file while looking like an ordinary empty command.
#
# This check fires when the document PARSES and a contracted field is the wrong
# TYPE. The case where the document does NOT parse is handled ABOVE, by the
# extraction failure branches — it is no longer reachable here.
#
# An earlier revision of this comment claimed the guard was "scoped deliberately
# NARROW" so that "a transport failure keeps the pre-existing behaviour". That
# was measured false in both directions and is corrected here: a document jq
# rejected did not fall through to any pre-existing behaviour, it ABORTED the
# script at the first extraction with no decision at all; and the `unparseable`
# branch below is unreachable in practice, since it requires this shape program
# to fail on a document the three simpler extractions above already parsed.
#
# The OpenHands protocol has no `ask` (ADR-157's posture in .claude/hooks/), so
# the anomalous shape DENIES. No legitimate caller sends a non-string here, and
# a deny is recoverable where a silent bypass is not.
#
# The `.tool_input` conjunct below reads `$t == "null"`, NOT `$t == null`: jq's
# `type` returns the STRING "null", so the latter is unsatisfiable. Written that
# way, this guard denied EVERY payload with an absent or null tool_input — an
# availability failure on a harness with no `ask` and no recovery path, where
# the .claude side parses the same payloads cleanly. It also falsified the
# sentence above, since those documents parse fine and carry no wrong-typed
# field. Measured both ways before and after.
GR_ENVELOPE_SHAPE=$(printf '%s' "$INPUT" | jq -r '
  # NB the // operator is deliberately absent: in jq it is a FALSY-alternative,
  # so a JSON false would be rewritten to "" and pass the type check below
  # (measured on the .claude side before this was fixed). Only null defaults.
  if (type == "object")
     and ((.tool_input? | type) as $t | $t == "null" or $t == "object")
     and ((.tool_input.command? | if . == null then "" else . end) | type == "string")
     and ((.working_dir? | if . == null then "" else . end) | type == "string")
     and ((if (.tool_input | has("path")) and (.tool_input.path != null) then .tool_input.path else .tool_input.file_path end | if . == null then "" else . end) | type == "string")
  then "ok" else "nonstring" end' 2>/dev/null) || GR_ENVELOPE_SHAPE="unparseable"
# `internal` — the shape program itself failed (a broken program, a jq version
# change, OOM) while the simpler extractions above succeeded. This was a
# TOTALLY SILENT fail-open: the fallback assigned "unparseable" and nothing
# branched on it, so an ARRAY command disarmed every guard below with no
# stdout, no stderr and no record — measured. Fail open (same
# self-referential-repair rationale as jq_missing) but LOUDLY.
if [[ "$GR_ENVELOPE_SHAPE" != "ok" && "$GR_ENVELOPE_SHAPE" != "nonstring" ]]; then
  echo "[guardrails] envelope shape program failed ($GR_ENVELOPE_SHAPE) — guards did NOT run for this call" >&2
fi
if [[ "$GR_ENVELOPE_SHAPE" == "nonstring" ]]; then
  deny "BLOCKED: the tool-call envelope carries a non-string field (e.g. an ARRAY tool_input.command). Hook stdin is model-controlled and untrusted (ADR-156); a non-string is never coerced, because the coerced value matches no guard and would bypass every gate in this hook. Re-send the command as a string."
fi


# guardrails:freeze-edit-lock — directory-scoped edit-lock for file_editor.
# Gated on BOTH file_path present AND command empty: a terminal payload carries
# .tool_input.command and no path, so this is skipped for terminal calls and
# cannot shadow the delete guards (TR3); requiring `-z COMMAND` too is defense-
# in-depth against a future payload forwarding both fields. Fail-open when no
# active freeze or a malformed state file (OQ2 blast-radius).
if [[ -n "$FILE_PATH" && -z "$COMMAND" ]] && declare -f freeze_active_prefix >/dev/null 2>&1; then
  ALLOWED=$(freeze_active_prefix) || ALLOWED=""
  if [[ -n "$ALLOWED" ]]; then
    RESOLVED=$(realpath -m "$FILE_PATH" 2>/dev/null || echo "$FILE_PATH")
    case "$RESOLVED" in
      "$ALLOWED"|"$ALLOWED"/*) : ;;   # inside the allowed prefix — allow
      *) deny "BLOCKED: a freeze is active — edits are restricted to $ALLOWED. Target $RESOLVED is outside the allowed prefix. Edit within the prefix, or clear the freeze: bash .claude/hooks/lib/freeze-lock.sh clear" ;;
    esac
  fi
  # file_editor payloads carry no terminal command — the sentinels below do not
  # apply. Exit here so no path a terminal command reaches carries a bare exit.
  exit 0
fi

# guardrails:block-commit-on-main — Block git commit on main branch
if grep -qE '(^|&&|\|\||;)\s*git\s+commit' <<<"$COMMAND"; then
  GIT_DIR=""
  if grep -qE '^\s*cd\s+' <<<"$COMMAND"; then
    GIT_DIR=$(echo "$COMMAND" | sed -nE 's/^\s*cd\s+"?([^"&;]+)"?.*/\1/p' | xargs)
  elif grep -qoE 'git\s+-C\s+\S+' <<<"$COMMAND"; then
    GIT_DIR=$(echo "$COMMAND" | grep -oE 'git\s+-C\s+\S+' | head -1 | sed -nE 's/git\s+-C\s+(\S+)/\1/p')
  fi
  if [ -n "$GIT_DIR" ] && [ -d "$GIT_DIR" ]; then
    BRANCH=$(git -C "$GIT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  elif [ -n "$HOOK_CWD" ] && [ -d "$HOOK_CWD" ]; then
    BRANCH=$(git -C "$HOOK_CWD" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  else
    BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  fi
  if [ "$BRANCH" = "main" ] || [ "$BRANCH" = "master" ]; then
    deny "BLOCKED: Committing directly to main/master is not allowed. Create a feature branch first."
  fi
fi

# guardrails:block-rm-rf-worktrees — Block rm -rf on worktree paths
if grep -qE 'rm\s+(-[a-zA-Z]*r[a-zA-Z]*f[a-zA-Z]*|-[a-zA-Z]*f[a-zA-Z]*r[a-zA-Z]*)\s+\S*\.worktrees/' <<<"$COMMAND"; then
  deny "BLOCKED: rm -rf on worktree paths is not allowed. Use git worktree remove or worktree-manager.sh cleanup-merged instead."
fi

# guardrails:block-recursive-delete — hardened ownership proof for rm -rf.
# Runs AFTER the narrow .worktrees/ gate (kept as a fast subset). Model:
# default-allow-except-protected. DENY when an rm -rf target RESOLVES onto the
# repo root, a git worktree root (or ancestor), $HOME, /, or a .git-bearing
# checkout — catching symlink/relative-path obfuscation the literal grep misses.
# The realpath here is a DENY-DECISION resolver (strengthens the block), the
# OPPOSITE direction from the constitution.md bulk-cleanup delete-executor rule
# (which forbids realpath before removal). See .claude/hooks/guardrails.sh for
# the canonical implementation + the full SCOPE note (lexical pre-exec guard:
# covers literal/relative/symlink targets, the common protected shell refs
# ~/$HOME/${HOME}/$PWD/${PWD}, and bare/path-qualified/escaped/sudo/env/command
# `rm`; does NOT see arbitrary $VAR, aliases, xargs/find-exec, or glob-expanded
# entries). This OpenHands port detects on the raw $COMMAND (it has no
# strip_command_bodies helper), so — consistent with its sibling terminal gates
# — a commit MESSAGE documenting `rm -rf` on a feature branch can over-match; the
# tokenizer (which acts only on a real `rm`/`*/rm` token) prevents false-denies
# in the common quoted-body case.
if grep -qE '(^|[[:space:]]|&&|\|\||;|\|)[^[:space:]]*rm[[:space:]]+(-[a-zA-Z]*r[a-zA-Z]*f[a-zA-Z]*|-[a-zA-Z]*f[a-zA-Z]*r[a-zA-Z]*)' <<<"$COMMAND"; then
  _rd_cwd=""
  if grep -qE '^\s*cd\s+' <<<"$COMMAND"; then
    _rd_cwd=$(echo "$COMMAND" | sed -nE 's/^\s*cd\s+"?([^"&;]+)"?.*/\1/p' | xargs)
  elif grep -qoE 'git\s+-C\s+\S+' <<<"$COMMAND"; then
    _rd_cwd=$(echo "$COMMAND" | grep -oE 'git\s+-C\s+\S+' | head -1 | sed -nE 's/git\s+-C\s+(\S+)/\1/p')
  fi
  if [ -z "$_rd_cwd" ] || [ ! -d "$_rd_cwd" ]; then
    if [ -n "$HOOK_CWD" ] && [ -d "$HOOK_CWD" ]; then _rd_cwd="$HOOK_CWD"; else _rd_cwd="$PWD"; fi
  fi

  _protected_roots=()
  while IFS= read -r _wl; do
    [[ "$_wl" == worktree\ * ]] && _protected_roots+=("${_wl#worktree }")
  done < <(git -C "$_rd_cwd" worktree list --porcelain 2>/dev/null || true)
  [[ -n "${HOME:-}" ]] && _protected_roots+=("$HOME")

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
    # Expand the common protected shell references before realpath (see canonical
    # hook). xargs has already stripped surrounding quotes.
    # shellcheck disable=SC2088  # case PATTERNS matching the literal `~` token.
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
        if [[ "$_res" == "$_pr" || "$_pr" == "$_res"/* ]]; then _deny=1; break; fi
      done
    fi
    [[ "$_deny" == 0 && -e "$_res/.git" ]] && _deny=1
    if [[ "$_deny" == 1 ]]; then
      deny "BLOCKED: rm -rf resolves onto a protected location ($_res). Repo roots, git worktree roots, \$HOME, /, and any .git-bearing checkout are protected. Delete a specific non-protected subdirectory instead, or use git worktree remove."
    fi
  done
fi

# guardrails:block-delete-branch — Block gh pr merge --delete-branch when worktrees exist
if grep -qE 'gh\s+pr\s+merge.*--delete-branch' <<<"$COMMAND"; then
  # `|| WORKTREE_COUNT=0`: git exits 128 from a non-git cwd and `pipefail`
  # propagates it, so under `set -e` this killed the hook at rc 128 with NO
  # decision, on a CLEAN payload — the same abort class this change fixes at
  # the extractions above.
  WORKTREE_COUNT=$(git worktree list 2>/dev/null | wc -l) || WORKTREE_COUNT=0
  if [ "$WORKTREE_COUNT" -gt 1 ]; then
    deny "BLOCKED: --delete-branch with active worktrees will orphan them. Remove worktrees first, then merge."
  fi
fi

# guardrails:block-conflict-markers — Block commits with conflict markers in staged content
if grep -qE '(^|&&|\|\||;)\s*git\s+(-C\s+\S+\s+)?(commit|merge\s+--continue)' <<<"$COMMAND"; then
  CONFLICT_MARKERS_DIR=""
  if grep -qE '^\s*cd\s+' <<<"$COMMAND"; then
    CONFLICT_MARKERS_DIR=$(echo "$COMMAND" | sed -nE 's/^\s*cd\s+"?([^"&;]+)"?.*/\1/p' | xargs)
  elif grep -qoE 'git\s+-C\s+\S+' <<<"$COMMAND"; then
    CONFLICT_MARKERS_DIR=$(echo "$COMMAND" | grep -oE 'git\s+-C\s+\S+' | head -1 | sed -nE 's/git\s+-C\s+(\S+)/\1/p')
  fi
  if [ -z "$CONFLICT_MARKERS_DIR" ] || [ ! -d "$CONFLICT_MARKERS_DIR" ]; then
    if [ -n "$HOOK_CWD" ] && [ -d "$HOOK_CWD" ]; then
      CONFLICT_MARKERS_DIR="$HOOK_CWD"
    fi
  fi
  if [ -n "$CONFLICT_MARKERS_DIR" ] && [ -d "$CONFLICT_MARKERS_DIR" ]; then
    STAGED_DIFF=$(git -C "$CONFLICT_MARKERS_DIR" diff --cached 2>/dev/null || true)
  else
    STAGED_DIFF=$(git diff --cached 2>/dev/null || true)
  fi
  if grep -qE '^\+(<{7}|={7}|>{7})' <<<"$STAGED_DIFF"; then
    deny "BLOCKED: Staged content contains conflict markers (<<<<<<<, =======, or >>>>>>>). Resolve all conflicts before committing."
  fi
fi

# guardrails:require-milestone — Block gh issue create without --milestone
if grep -qE '(^|&&|\|\||;)\s*gh\s+issue\s+create' <<<"$COMMAND"; then
  if ! grep -qF -- '--milestone' <<<"$COMMAND"; then
    deny "BLOCKED: gh issue create must include --milestone. Default to 'Post-MVP / Later' for operational issues. Read knowledge-base/product/roadmap.md for feature issues."
  fi
fi

# guardrails:block-stash-in-worktrees — Block git stash in worktrees
if grep -qE '(^|&&|\|\||;)\s*git\s+stash' <<<"$COMMAND"; then
  STASH_GUARD_DIR=""
  if grep -qE '^\s*cd\s+' <<<"$COMMAND"; then
    STASH_GUARD_DIR=$(echo "$COMMAND" | sed -nE 's/^\s*cd\s+"?([^"&;]+)"?.*/\1/p' | xargs)
  elif grep -qoE 'git\s+-C\s+\S+' <<<"$COMMAND"; then
    STASH_GUARD_DIR=$(echo "$COMMAND" | grep -oE 'git\s+-C\s+\S+' | head -1 | sed -nE 's/git\s+-C\s+(\S+)/\1/p')
  fi
  if [ -z "$STASH_GUARD_DIR" ] || [ ! -d "$STASH_GUARD_DIR" ]; then
    if [ -n "$HOOK_CWD" ] && [ -d "$HOOK_CWD" ]; then
      STASH_GUARD_DIR="$HOOK_CWD"
    fi
  fi
  RESOLVE_DIR="${STASH_GUARD_DIR:-.}"
  _resolved=$(cd "$RESOLVE_DIR" 2>/dev/null && pwd)
  if grep -qF '.worktrees' <<<"$_resolved"; then
    deny "BLOCKED: git stash in worktrees is not allowed. Use git show <commit>:<path> to inspect old code, or commit WIP first."
  fi
fi

# All checks passed
exit 0
