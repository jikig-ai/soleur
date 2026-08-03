#!/usr/bin/env bash
# PreToolUse hook: review evidence gate + auto-sync against origin/main before gh pr merge.
# OpenHands port of .claude/hooks/pre-merge-rebase.sh.
#
# OpenHands protocol: exit 2 + JSON {"decision":"deny","reason":"..."} to block.
# Exit 0 + JSON {"additionalContext":"..."} to inject context.
# Input: HookEvent JSON on stdin with tool_input.command and working_dir.
#
# Corresponding prose rules: see .claude/hooks/pre-merge-rebase.sh

set -eo pipefail

INPUT=$(cat)

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
# jq MISSING fails OPEN, loudly: ADR-157:115 rejects fail-closed because the
# repair for a broken PATH or a missing jq is itself a tool call that would also
# be denied, and that bites harder here — this harness has no `ask`, no operator
# escalation and no kill switch. A document jq REJECTS is a different class and
# DENIES via the extraction failure branches below. Before this split, any
# document jq rejected killed the script under `set -euo pipefail` with no deny,
# no decision JSON and no incident row, leaving the outcome to depend on how the
# runtime treats a non-0/2 exit code — an invariant this repo does not define.
if ! command -v jq >/dev/null 2>&1; then
  echo "[pre-merge-rebase] jq missing — envelope unparseable, guards did NOT run for this call" >&2
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

# deny() and the envelope guard are hoisted ABOVE the early-exit gates below.
# Placement is the whole point: the gates at `grep -qE ... gh pr merge` and
# `[[ ! -d "$WORK_DIR" ]]` CONSUME the very fields the guard validates, and
# `jq -r` renders a non-string across lines — so an ARRAY .tool_input.command
# spelling `gh pr merge --admin` fails the line-based grep and exits 0 before
# the guard could ever run. Measured on this branch: the guard sat below them
# and BOTH the array-command and array-working_dir payloads exited 0, i.e. it
# added nothing. Same class as the bug it exists to catch.
deny() {
  jq -n --arg reason "$1" '{"decision":"deny","reason":$reason}'
  exit 2
}
# --- ADR-156 (mirror): the HookEvent envelope is MODEL-CONTROLLED ------------
# This port never calls eval, so it is not vulnerable to the #7164 code
# execution. It is still EVADABLE by the same payload: `jq -r` renders a
# non-string field across multiple lines, which matches none of the anchored
# guards below, so an array .tool_input.command would slip every gate in this
# file while looking like an ordinary empty command.
#
# Scoped deliberately NARROW — it fires only when the document PARSES and a
# contracted field is the wrong TYPE. A transport failure keeps the pre-existing
# behaviour, so this change cannot alter what happens on a jq hiccup.
#
# The OpenHands protocol has no `ask` (ADR-157's posture in .claude/hooks/), so
# the anomalous shape DENIES. No legitimate caller sends a non-string here, and
# a deny is recoverable where a silent bypass is not. Converging the two
# harnesses on one extractor is a tracked follow-up.
PMR_ENVELOPE_SHAPE=$(printf '%s' "$INPUT" | jq -r '
  # NB the // operator is deliberately absent: in jq it is a FALSY-alternative,
  # so a JSON false would be rewritten to "" and pass the type check below
  # (measured on the .claude side before this was fixed). Only null defaults.
  if (type == "object")
     and ((.tool_input? | type) as $t | $t == "null" or $t == "object")
     and ((.tool_input.command? | if . == null then "" else . end) | type == "string")
     and ((.working_dir? | if . == null then "" else . end) | type == "string")
     and ((if (.tool_input | has("path")) and (.tool_input.path != null) then .tool_input.path else .tool_input.file_path end | if . == null then "" else . end) | type == "string")
  then "ok" else "nonstring" end' 2>/dev/null) || PMR_ENVELOPE_SHAPE="unparseable"
# `internal` — the shape program itself failed (a broken program, a jq version
# change, OOM) while the simpler extractions above succeeded. This was a
# TOTALLY SILENT fail-open: the fallback assigned "unparseable" and nothing
# branched on it, so an ARRAY command disarmed every guard below with no
# stdout, no stderr and no record — measured. Fail open (same
# self-referential-repair rationale as jq_missing) but LOUDLY.
if [[ "$PMR_ENVELOPE_SHAPE" != "ok" && "$PMR_ENVELOPE_SHAPE" != "nonstring" ]]; then
  echo "[pre-merge-rebase] envelope shape program failed ($PMR_ENVELOPE_SHAPE) — guards did NOT run for this call" >&2
fi
if [[ "$PMR_ENVELOPE_SHAPE" == "nonstring" ]]; then
  deny "BLOCKED: the tool-call envelope carries a non-string field (e.g. an ARRAY tool_input.command). Hook stdin is model-controlled and untrusted (ADR-156); a non-string is never coerced, because the coerced value matches no guard and would bypass every gate in this hook. Re-send the command as a string."
fi

CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null) \
  || deny "$UNPARSEABLE_REASON"

# Early exit: only intercept gh pr merge commands.
if ! grep -qE '(^|&&|\|\||;|\s--\s)\s*gh\s+pr\s+merge(\s|$)' <<<"$CMD"; then
  exit 0
fi

# Determine working directory from hook input.
WORK_DIR=$(printf '%s' "$INPUT" | jq -r '.working_dir // ""' 2>/dev/null) \
  || deny "$UNPARSEABLE_REASON"
if [[ -z "$WORK_DIR" ]] || [[ ! -d "$WORK_DIR" ]]; then
  exit 0
fi

if ! git -C "$WORK_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  exit 0
fi



CURRENT_BRANCH=$(git -C "$WORK_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null) || CURRENT_BRANCH=""

if [[ "$CURRENT_BRANCH" == "main" ]] || [[ "$CURRENT_BRANCH" == "master" ]]; then
  exit 0
fi

# Refresh origin/main BEFORE the gate (#6724). Both local signals are scoped
# with `origin/main..HEAD`, so a stale ref widens the range and lets commits
# already on main count as this branch's review evidence. Deliberately does not
# exit on failure: the sync below fails open on network error, and keeping that
# behaviour here would make "unplug the network" a universal gate bypass.
FETCH_OK=1
if ! git -C "$WORK_DIR" fetch origin main >/dev/null 2>&1; then
  FETCH_OK=0
fi

# pre-merge:review-evidence-gate
# Check 1 was a repo-global `grep -rl "code-review" "$WORK_DIR/todos/"` and was
# therefore structurally unfailable (#6724): todos/ lives on main, so one
# long-lived review todo satisfied the gate for every branch forever. Now scoped
# to paths touched by commits unique to this branch.
# `-G` selects commits whose DIFF touched the tag (so the BRANCH introduced it),
# and the HEAD-blob check requires it to still be there — `-G` alone matches
# removals, so a sweep deleting a completed todo would otherwise count.
REVIEW_TODOS=""
while IFS= read -r _todo; do
  [[ -n "$_todo" ]] || continue
  _todo_body=$(git -C "$WORK_DIR" show "HEAD:$_todo" 2>/dev/null || true)
  if grep -q "code-review" <<<"$_todo_body"; then
    REVIEW_TODOS="$_todo"
    break
  fi
done < <(git -C "$WORK_DIR" log origin/main..HEAD -G'code-review' \
           --name-only --format= -- todos/ 2>/dev/null | sort -u)
# Signal 2 had drifted out of sync with the .claude/hooks copy: it matched only
# the legacy "refactor: add code review findings" subject, missing the "review: "
# fix-inline convention (post-#2374) entirely. Both are now matched here, plus
# the durable `Reviewed-By-Soleur:` trailer that emit-review-trailer.sh emits —
# the only signal a zero-finding review can produce.
#
# The `review: ` arm carries an OPTIONAL conventional-commit scope: this repo
# writes `review(6178): ...`, which a bare `review: ` regex misses, reading as
# "review never ran" and blocking a merge that had in fact been reviewed
# (PR #6933). Kept byte-identical to the .claude/hooks copy — the T-S case in
# pre-merge-rebase-parity.test.sh asserts that on the full call shape.
REVIEW_COMMIT=$(git -C "$WORK_DIR" log origin/main..HEAD --oneline 2>/dev/null \
  | grep -E "^[a-f0-9]+ (refactor: add code review findings|review(\([^)]*\))?: )" || true)
if [[ -z "$REVIEW_COMMIT" ]]; then
  REVIEW_COMMIT=$(git -C "$WORK_DIR" log origin/main..HEAD \
    --format='%(trailers:key=Reviewed-By-Soleur,valueonly)' 2>/dev/null \
    | grep '[^[:space:]]' || true)
fi

REVIEW_ISSUES=""
if [[ -z "$REVIEW_TODOS" ]] && [[ -z "$REVIEW_COMMIT" ]]; then
  PR_NUMBER=$(echo "$CMD" | grep -oE 'gh\s+pr\s+merge\s+([0-9]+)' | grep -oE '[0-9]+' || true)
  if [[ -z "$PR_NUMBER" ]]; then
    PR_NUMBER=$(gh pr list --repo "$(git -C "$WORK_DIR" remote get-url origin 2>/dev/null | sed 's|.*github.com[:/]||;s|\.git$||')" \
      --head "$CURRENT_BRANCH" --state open --json number --jq '.[0].number // empty' 2>/dev/null || true)
  fi
  if [[ -n "$PR_NUMBER" ]]; then
    # Kept in lockstep with .claude/hooks/pre-merge-rebase.sh. Two load-bearing details:
    # --state all, because a review issue that was filed and then CLOSED (the fix-inline
    # default) is still evidence /review ran — open-only discards the healthy case (#6786);
    # and the literal quotes, so GitHub search treats "PR #N" as an exact phrase (otherwise
    # `#123` tokenizes loosely and matches unrelated issues — confirmed in soleur/#2186).
    REVIEW_ISSUES=$(gh issue list --label code-review --state all --search "\"PR #${PR_NUMBER}\"" \
      --limit 1 --json number --jq '.[0].number // empty' 2>/dev/null || true)
  fi
fi

# A stale origin/main makes both local signals untrustworthy in the UNSAFE
# direction (the range widens to include commits already on main, and this hook
# merges origin/main on every run), so discard them rather than warn. Signal 3
# queries the remote and is unaffected, so a fetch failure degrades to
# Signal-3-only instead of to a bypass (#6724).
if [[ "$FETCH_OK" != "1" ]]; then
  REVIEW_TODOS=""
  REVIEW_COMMIT=""
fi

if [[ -z "$REVIEW_TODOS" ]] && [[ -z "$REVIEW_COMMIT" ]] && [[ -z "$REVIEW_ISSUES" ]]; then
  deny "BLOCKED: No review evidence for commits in origin/main..HEAD. If review has NOT run: run /soleur:review. If it HAS run (or found nothing, which emits no artifacts): bash plugins/soleur/skills/review/scripts/emit-review-trailer.sh --findings <n>. Scope is this branch only — evidence already on main does not count."
fi

# Check for detached HEAD
if [[ "$CURRENT_BRANCH" == "HEAD" ]]; then
  echo "Warning: Detached HEAD state. Skipping auto-sync." >&2
  exit 0
fi

# Check for uncommitted changes
if [[ "$(git -C "$WORK_DIR" rev-parse --is-inside-work-tree 2>/dev/null)" == "true" ]]; then
  if ! git -C "$WORK_DIR" diff --quiet HEAD 2>/dev/null || \
     ! git -C "$WORK_DIR" diff --cached --quiet 2>/dev/null; then
    deny "BLOCKED: Uncommitted changes detected. Commit before merging."
  fi
fi

# The fetch happens above the review-evidence gate (#6724); its outcome is
# consumed here, preserving fail-open-on-network-error for SYNCING only.
if [[ "$FETCH_OK" != "1" ]]; then
  echo "Warning: Could not fetch origin/main (network error). Proceeding with merge." >&2
  exit 0
fi

MERGE_BASE=$(git -C "$WORK_DIR" merge-base HEAD origin/main 2>/dev/null) || true
REMOTE_MAIN=$(git -C "$WORK_DIR" rev-parse origin/main 2>/dev/null) || true

if [[ -z "$MERGE_BASE" ]] || [[ -z "$REMOTE_MAIN" ]]; then
  echo "Warning: Could not determine branch relationship with main. Proceeding with merge." >&2
  exit 0
fi

if [[ "$MERGE_BASE" == "$REMOTE_MAIN" ]]; then
  echo "[ok] Branch already up-to-date with origin/main." >&2
  exit 0
fi

# Attempt merge
if ! git -C "$WORK_DIR" merge origin/main >/dev/null 2>&1; then
  CONFLICT_FILES=$(git -C "$WORK_DIR" diff --name-only --diff-filter=U 2>/dev/null \
    | head -5 | tr '\n' ', ' | sed 's/,$//')
  git -C "$WORK_DIR" merge --abort 2>/dev/null || true
  deny "BLOCKED: Merge of origin/main failed. Conflicting files: ${CONFLICT_FILES:-unknown}. Resolve conflicts manually before merging."
fi

# Push the merged result
if ! PUSH_OUTPUT=$(git -C "$WORK_DIR" push origin HEAD 2>&1); then
  deny "BLOCKED: Merge succeeded but push failed. Push manually before merging. Error: $PUSH_OUTPUT"
fi

# Success with context
jq -n --arg branch "$CURRENT_BRANCH" \
  '{"additionalContext":("Pre-merge hook: merged origin/main into " + $branch + " and pushed. Branch is now current.")}'
exit 0
