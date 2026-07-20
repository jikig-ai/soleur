#!/usr/bin/env bash
# PreToolUse hook: review evidence gate + auto-sync against origin/main before gh pr merge.
#
# pre-merge:review-evidence-gate — blocks gh pr merge when no review evidence exists on the branch.
# Review evidence is detected via three signals (any one suffices):
# (1) todos/ files tagged "code-review" (legacy, pre-#1329)
# (2) a commit matching "refactor: add code review findings" (legacy, pre-#1329)
# (3) GitHub issues with "code-review" label referencing the branch's PR (current, post-#1329)
# No escape hatch — run /review before merging.
#
# Auto-sync: merges origin/main into the feature branch to ensure it is current before merge.
# Note: filename says "rebase" for historical reasons; strategy is merge (not rebase).
#
# Corresponding prose rules:
#   constitution.md "Before creating a PR or merging, merge latest origin/main into the feature branch"
#   pre-merge:review-evidence-gate — blocks gh pr merge without review evidence (self-documented in this script)
#
# Error handling: fail-open on infrastructure errors (network, non-git context),
# fail-closed on logical errors (conflicts, dirty tree, push failure, missing review evidence).

set -eo pipefail
# -u (nounset) omitted: hook failure paths must return JSON, not crash silently.

# shellcheck source=lib/incidents.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/incidents.sh"

# shellcheck source=lib/session-state.sh
# headless_or_stderr routes warns to a log file under $GIT_COMMON_DIR/
# soleur-session-state/logs/$PPID.log when stderr is not a TTY and
# CLAUDECODE is set (running under `claude --bg`). Otherwise echoes to
# stderr as before. Tolerate missing helper for legacy worktrees.
_SS_LIB="$(dirname "${BASH_SOURCE[0]}")/lib/session-state.sh"
if [[ -f "$_SS_LIB" ]]; then
  # shellcheck source=/dev/null
  source "$_SS_LIB"
else
  headless_or_stderr() { echo "[$1] $2" >&2; }
fi
export SOLEUR_HOOK_NAME="pre-merge-rebase"

INPUT=$(cat)
# `|| true`: under `set -eo pipefail`, jq exits 5 on malformed/empty stdin and
# would otherwise abort the script before the fail-open guards below — breaking
# the header's "fail-open on infrastructure errors" invariant. Degrade to "" so
# a malformed payload yields no merge-detection and a clean exit 0 (#4600).
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // ""' || true)

# Strip commit-message bodies before merge-detection so a commit whose message
# documents "gh pr merge" (e.g. `git commit -m "do not hand-roll gh pr merge"`)
# is not mistaken for a merge (#4600). perl -0777 slurps the whole (possibly
# multi-line) command; the /gs substitutions blank, in order:
#   1. heredoc bodies — `<<[-]['"]?DELIM['"]? … \nDELIM` (covers `git commit
#      -F - <<EOF … EOF`). Only the body between the opening line and the
#      closing delimiter is blanked; the markers and anything AFTER the closing
#      delimiter (where a real chained `gh pr merge` could live) are preserved.
#   2. double- and single-quoted spans (escape-aware) — covers `-m "…"` and the
#      `-m "$(cat <<EOF … EOF)"` shape where the heredoc sits inside the quote.
# Both leave the command structure OUTSIDE quotes/heredocs intact, where a real
# chained `gh pr merge` lives. Sibling precedent: follow-through-directive-
# gate.sh:72 ("sed -E can't do non-greedy across newlines" — same
# multiline-quoted-body class). On strip-tool failure, fall back to the raw
# $CMD so we fail TOWARD firing (over-detect), never toward a silent
# merge-bypass.
# The perl one-liner that used to live inline here is now the shared
# strip_command_bodies helper in lib/incidents.sh (#5192) — same canonical
# regex, one tested copy consumed by every phrase-detecting gate.
SCAN=$(strip_command_bodies "$CMD")

# Early exit: only intercept gh pr merge commands.
# Word boundary (\s|$) prevents false positives on hypothetical merge-* subcommands.
# Chain operator pattern from guardrails.sh catches chained commands.
# Runs against $SCAN (quote-stripped), not $CMD, per the #4600 fix above.
if ! echo "$SCAN" | grep -qE '(^|&&|\|\||;|\s--\s)\s*gh\s+pr\s+merge(\s|$)'; then
  exit 0
fi
# Note: the `\s--\s` alternative catches the with_lock wrapped form
# (`bash session-state.sh with_lock merge-main 600 -- gh pr merge ...`)
# so the wrapped form does NOT bypass the review-evidence gate, the
# uncommitted-changes check, or the origin/main auto-sync.

# Determine working directory from hook input (.cwd is authoritative).
# `|| true` for the same fail-open reason as the CMD read above (#4600).
WORK_DIR=$(echo "$INPUT" | jq -r '.cwd // ""' || true)
if [[ -z "$WORK_DIR" ]] || [[ ! -d "$WORK_DIR" ]]; then
  exit 0
fi

# Verify we are in a git repository
if ! git -C "$WORK_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  exit 0
fi

# Resolve current branch for main/master skip and detached HEAD handling
CURRENT_BRANCH=$(git -C "$WORK_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null)

# Skip if already on main/master -- no local review evidence to check,
# and nothing to sync (the agent is merging a PR *into* main, not from it)
if [[ "$CURRENT_BRANCH" == "main" ]] || [[ "$CURRENT_BRANCH" == "master" ]]; then
  exit 0
fi

# Refresh origin/main BEFORE the review-evidence gate (#6724).
#
# Both local signals below are scoped with `origin/main..HEAD`, so they are only
# as accurate as the locally-cached origin/main ref. A stale ref silently widens
# that range and lets commits already on main count as this branch's own review
# evidence — which re-opens the vacuity the scoping exists to close. This hook
# in particular merges origin/main in and pushes, so on a second merge attempt
# the cached ref is guaranteed to be behind unless it is refreshed here.
#
# This deliberately does NOT exit on failure. The sync logic further down fails
# open on a network error, which is correct for syncing; but if the fetch kept
# that behaviour at this position, any network failure would return 0 BEFORE the
# gate ran, turning "unplug the network" into a universal gate bypass. The
# outcome is recorded and acted on after the gate instead.
FETCH_OK=1
if ! git -C "$WORK_DIR" fetch origin main >/dev/null 2>&1; then
  FETCH_OK=0
fi

# pre-merge:review-evidence-gate — Review evidence gate.
# Block gh pr merge when no review evidence exists on the branch.
# Signals 1-2 are local; Signal 3 requires network (gh API).
# Fires before detached HEAD exit because gh pr merge operates on a PR number,
# not the local checkout state -- review evidence is still visible in detached HEAD.

# Check 1 (legacy): todo files tagged "code-review" INTRODUCED BY THIS BRANCH.
#
# This was `grep -rl "code-review" "$WORK_DIR/todos/"` — a repo-global grep, and
# therefore structurally unfailable (#6724). todos/ is a tracked directory that
# lives on main, so a single long-lived review todo anywhere in it satisfied the
# gate for EVERY branch, forever, including branches where review never ran. The
# gate could not deny anything for as long as that file existed.
#
# `-G'code-review'` selects commits whose DIFF adds or removes a line matching
# the pattern, so this asks "did THIS BRANCH introduce review evidence?".
#
# The obvious formulation — list the paths the branch touched, then grep those
# paths — is still vacuous, just more narrowly. `git log --name-only` yields
# paths, and grep then reads whatever those paths contain IN THE CURRENT
# CHECKOUT. So a branch that merely TOUCHES a pre-existing main-side todo (a
# `resolve-todo-parallel` sweep, marking one done, a reformat) lists that path,
# grep matches the `code-review` tag that came from main, and the gate passes
# with no review having run. Matching on the diff instead of on the working
# tree closes that; it is the same class of residual the repo-global grep had.
# `-G` alone is still not enough: it matches lines ADDED **or REMOVED**, so a
# sweep that merely deletes a completed review todo (`git rm todos/...`) would
# count as evidence. So each candidate path must ALSO still carry the tag in
# HEAD's blob — evidence that was introduced and is still there.
REVIEW_TODOS=""
while IFS= read -r _todo; do
  [[ -n "$_todo" ]] || continue
  if git -C "$WORK_DIR" show "HEAD:$_todo" 2>/dev/null | grep -q "code-review"; then
    REVIEW_TODOS="$_todo"
    break
  fi
done < <(git -C "$WORK_DIR" log origin/main..HEAD -G'code-review' \
           --name-only --format= -- todos/ 2>/dev/null | sort -u)

# Check 2: review commit, or the machine-emitted review trailer.
#
# The `Reviewed-By-Soleur:` trailer is the durable signal, emitted by
# plugins/soleur/skills/review/scripts/emit-review-trailer.sh. It exists because
# a zero-finding review legitimately produces no artifacts and no commit, so the
# message-pattern signals below cannot fire for it — the gate would deny exactly
# the branches that were clean (#6724).
#
# The two message patterns are retained as legacy fallbacks for branches
# reviewed before the trailer existed: "refactor: add code review findings" and
# the "review: <summary> (P<N>)" fix-inline convention from
# rf-review-finding-default-fix-inline (post-#2374).
REVIEW_COMMIT=$(git -C "$WORK_DIR" log origin/main..HEAD --oneline 2>/dev/null \
  | grep -E "^[a-f0-9]+ (refactor: add code review findings|review: )" || true)
if [[ -z "$REVIEW_COMMIT" ]]; then
  REVIEW_COMMIT=$(git -C "$WORK_DIR" log origin/main..HEAD \
    --format='%(trailers:key=Reviewed-By-Soleur,valueonly)' 2>/dev/null \
    | grep '[^[:space:]]' || true)
fi

# Check 3 (current): GitHub issues with "code-review" label referencing this PR.
# Coupled to review-todo-structure.md issue body template ("**Source:** PR #<number>").
# Fail open if gh is unavailable or network fails (Signal 3 is additive, not required).
REVIEW_ISSUES=""
if [[ -z "$REVIEW_TODOS" ]] && [[ -z "$REVIEW_COMMIT" ]]; then
  # Only run the network check if local signals found nothing
  # Reads $CMD (not $SCAN) intentionally: by here the command IS a real merge
  # (passed the SCAN filter), and the PR-number arg lives outside quotes, so
  # the #4600 quote-strip is unnecessary for the extraction.
  PR_NUMBER=$(echo "$CMD" | grep -oE 'gh\s+pr\s+merge\s+([0-9]+)' | grep -oE '[0-9]+' || true)
  if [[ -z "$PR_NUMBER" ]]; then
    # No PR number in command args -- fall back to branch-based lookup
    PR_NUMBER=$(gh pr list --repo "$(git -C "$WORK_DIR" remote get-url origin 2>/dev/null | sed 's|.*github.com[:/]||;s|\.git$||')" \
      --head "$CURRENT_BRANCH" --state open --json number --jq '.[0].number // empty' 2>/dev/null || true)
  fi
  if [[ -n "$PR_NUMBER" ]]; then
    # Wrap the phrase in literal quotes so GitHub search treats "PR #N" as an
    # exact phrase (otherwise `#123` tokenizes loosely and matches unrelated
    # issues that happen to reference the PR prefix — confirmed in soleur/#2186
    # session when search "PR #123" returned issues that never mentioned 123).
    REVIEW_ISSUES=$(gh issue list --label code-review --state all --search "\"PR #${PR_NUMBER}\"" \
      --limit 1 --json number --jq '.[0].number // empty' 2>/dev/null || true)
  fi
fi

# A stale origin/main makes BOTH local signals untrustworthy in the UNSAFE
# direction, so they are discarded rather than merely warned about (#6724).
#
# Hoisting the fetch above the gate stopped a network failure from
# short-circuiting the gate, but recording FETCH_OK without acting on it left a
# verified bypass: with origin/main stale, `origin/main..HEAD` widens to include
# commits already on main, and this hook MERGES origin/main on every successful
# run — so after one pass a branch inherits main's whole `review:` history.
# Measured: a branch with zero review evidence of its own PASSES the gate in
# that state. This PR makes it strictly worse, because emit-review-trailer.sh
# guarantees main's history is dense with `review:` subjects and trailers.
#
# Signal 3 is unaffected (it queries the remote by PR number, not the local
# range), so a fetch failure degrades to Signal-3-only rather than to a bypass.
if [[ "$FETCH_OK" != "1" ]]; then
  REVIEW_TODOS=""
  REVIEW_COMMIT=""
fi

if [[ -z "$REVIEW_TODOS" ]] && [[ -z "$REVIEW_COMMIT" ]] && [[ -z "$REVIEW_ISSUES" ]]; then
  emit_incident "rf-never-skip-qa-review-before-merging" deny \
    "Never skip QA/review before merging. Full pipeline:" "$CMD"
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: "BLOCKED: No review evidence for commits in origin/main..HEAD. If review has NOT run: run /soleur:review. If it HAS run (or found nothing, which emits no artifacts): bash plugins/soleur/skills/review/scripts/emit-review-trailer.sh --findings <n>. Signals checked: todos/ tagged code-review introduced by this branch, a review: commit or Reviewed-By-Soleur: trailer, a code-review-labelled issue citing this PR. Note the scope is this branch only — evidence already on main does not count."
    }
  }'
  exit 0
fi

# Check for detached HEAD -- auto-sync needs a branch to push
if [[ "$CURRENT_BRANCH" == "HEAD" ]]; then
  headless_or_stderr warn "Detached HEAD state. Skipping auto-sync."
  exit 0
fi

# Check for uncommitted changes (tracked files only -- untracked files
# cannot conflict with merge and should not block it).
# Skip if not inside a work tree (bare repo context): git diff --quiet HEAD
# returns 128 and git diff --cached --quiet returns 1 (empty index vs HEAD),
# both false positives. Fail open in bare repo setups (#1386).
if [[ "$(git -C "$WORK_DIR" rev-parse --is-inside-work-tree 2>/dev/null)" == "true" ]]; then
  if ! git -C "$WORK_DIR" diff --quiet HEAD 2>/dev/null || \
     ! git -C "$WORK_DIR" diff --cached --quiet 2>/dev/null; then
    emit_incident "hr-when-a-command-exits-non-zero-or-prints" deny \
      "When a command exits non-zero or prints a warning" "$CMD"
    jq -n '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: "BLOCKED: Uncommitted changes detected. Commit before merging."
      }
    }'
    exit 0
  fi
fi

# The fetch itself now happens above the review-evidence gate (#6724) so that a
# network failure cannot short-circuit the gate. Its outcome is consumed here,
# preserving the original fail-open-on-network-error behaviour for SYNCING only.
if [[ "$FETCH_OK" != "1" ]]; then
  headless_or_stderr warn "Could not fetch origin/main (network error). Proceeding with merge."
  exit 0
fi

# Check if sync is needed by comparing merge-base with origin/main tip
MERGE_BASE=$(git -C "$WORK_DIR" merge-base HEAD origin/main 2>/dev/null) || true
REMOTE_MAIN=$(git -C "$WORK_DIR" rev-parse origin/main 2>/dev/null) || true

if [[ -z "$MERGE_BASE" ]] || [[ -z "$REMOTE_MAIN" ]]; then
  # Could not determine relationship -- fail open
  headless_or_stderr warn "Could not determine branch relationship with main. Proceeding with merge."
  exit 0
fi

if [[ "$MERGE_BASE" == "$REMOTE_MAIN" ]]; then
  # Already up-to-date, no sync needed
  headless_or_stderr info "Branch already up-to-date with origin/main."
  exit 0
fi

# Serialize against concurrent main-sync attempts (sibling sessions
# pre-flighting `gh pr merge --auto` from a different worktree). Lock name
# is `rebase-main` per plan §Implementation Phases for the hook surface,
# even though the strategy here is `git merge` (see top-of-file comment on
# the historical filename).
acquire_lock rebase-main 60 || headless_or_stderr warn "rebase-main lock contended; proceeding without serialization"
# Release on any exit path below (merge failure, push failure, success).
trap 'release_lock rebase-main 2>/dev/null || true' EXIT

# Attempt merge
if ! git -C "$WORK_DIR" merge origin/main >/dev/null 2>&1; then
  # Merge failed -- capture conflicts BEFORE aborting (abort clears conflict state)
  CONFLICT_FILES=$(git -C "$WORK_DIR" diff --name-only --diff-filter=U 2>/dev/null \
    | head -5 | tr '\n' ', ' | sed 's/,$//')
  git -C "$WORK_DIR" merge --abort 2>/dev/null || true
  emit_incident "hr-when-a-command-exits-non-zero-or-prints" deny \
    "When a command exits non-zero or prints a warning" "$CMD"
  jq -n --arg files "${CONFLICT_FILES:-unknown}" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: ("BLOCKED: Merge of origin/main failed. Conflicting files: " + $files + ". Resolve conflicts manually before merging.")
    }
  }'
  exit 0
fi

# Merge succeeded -- push to update the remote branch.
# Regular push (not force-push) since merge does not rewrite history.
if ! PUSH_OUTPUT=$(git -C "$WORK_DIR" push origin HEAD 2>&1); then
  emit_incident "hr-when-a-command-exits-non-zero-or-prints" deny \
    "When a command exits non-zero or prints a warning" "$CMD"
  jq -n --arg output "$PUSH_OUTPUT" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: ("BLOCKED: Merge succeeded but push failed. Push manually before merging. Error: " + $output)
    }
  }'
  exit 0
fi

# Return success with context so the agent knows what happened
jq -n --arg branch "$CURRENT_BRANCH" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    additionalContext: ("Pre-merge hook: merged origin/main into " + $branch + " and pushed. Branch is now current.")
  }
}'
exit 0
