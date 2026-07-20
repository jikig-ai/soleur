#!/usr/bin/env bash
# PreToolUse hook: block `gh pr merge` when a branch commit body OR the PR body
# contains a PROSE-EMBEDDED GitHub auto-close keyword + #N (e.g. "the sweeper
# closes #5887", "I'll close #5955 after the pipeline") that would auto-close an
# issue you did not intend to close on merge.
#
# Source rule: knowledge-base/project/learnings/2026-06-29-auto-closes-meta-content-
#   in-commit-body-trips-github-autoclose-on-hand-rolled-merge.md
#   + 2026-07-03-chain-of-latent-defects-clearing-a-wedge-exposes-a-cascade.md
#   (auto-close-prose hit TWICE via hand-rolled `gh pr merge`).
#
# Why this hook exists (the gap it closes): `/ship` Phase 6 runs
# `plugins/soleur/skills/ship/scripts/auto-close-scan.sh` at PR-creation time, but
# a HAND-ROLLED / auto `gh pr merge` (bypassing /ship) has no equivalent check.
# This hook makes the guard merge-path-independent, mirroring how
# pre-merge-rebase.sh already intercepts `gh pr merge`.
#
# Two independent checks, in this order:
#
#   1. follow-through label gate — denies a close of ANY form (standalone or
#      prose-embedded) when the target issue carries `follow-through`. Closing
#      such a tracker makes the daily sweeper skip it (it evaluates only OPEN
#      issues), so the soak verification it exists to enforce never runs.
#   2. prose-embedded arm — denies a close-keyword that appears AFTER prose on
#      its line, for any issue, labelled or not. An intentional `Closes #N` on
#      its own line (the conventional form /ship PRs use) is ALLOWED, so normal
#      fix-PRs that mean to close their issue merge unimpeded.
#
# Escape hatches — each disarms exactly one check:
#   SOLEUR_ACK_AUTOCLOSE=1            everything (checked above corpus construction)
#   SOLEUR_ACK_FOLLOWTHROUGH_CLOSE=1  the label gate only; prose arm stays armed
#
# Where this sits among the four follow-through / auto-close surfaces:
#
#   /ship Phase 6                     pre-creation, `gh pr create`   blocking, prose arm
#   pr-auto-close-scanner.yml         CI, on PR events               OBSERVATIONAL only
#   ship-soak-followthrough-gate.sh   PreToolUse, ready/merge --auto denies when a tracker
#                                                                    is MISSING enrollment
#   this hook                         PreToolUse, plain `gh pr merge` denies when an issue
#                                                                    HAS `follow-through`
#
# The last two have INVERSE semantics and can both fire on one `--auto` merge, so
# their deny messages name themselves and their distinct override envs.
#
# Best-effort, NOT a boundary. It only sees merges this harness intercepts.
# Known bypasses: merging from `main` (the branch guard exits first), the GitHub
# web UI, an admin merge, a CI-queued `--auto` merge that GitHub completes
# minutes-to-hours later (the body and labels can both change in that window),
# and the OpenHands harness, which has `pre-merge-rebase.sh` but no auto-close
# counterpart. `main` carries no branch protection, so no server-side required
# check backstops any of these today. The durable reversal layer is
# `follow-through-closure-guard.yml` (`on: issues.closed`), which is
# path-independent by construction.
#
# Fail-open: any infrastructure error (bad payload, missing git, scan failure)
# exits 0 (allow). A hook must never wedge a merge on its own bug — but every
# skipped arm prints one stderr line naming itself. Silence is how the PR-body
# arm stayed dead for 17 days while its test suite reported 8/8 passed.
set -uo pipefail

_LIB_DIR="$(dirname "${BASH_SOURCE[0]}")/lib"
# strip_command_bodies (blank quoted/heredoc bodies so a commit MESSAGE that
# documents "gh pr merge" is not mis-detected as a merge — same #4600/#5192
# canonical helper pre-merge-rebase.sh uses).
if [[ -f "$_LIB_DIR/incidents.sh" ]]; then
  # shellcheck source=/dev/null
  source "$_LIB_DIR/incidents.sh"
else
  strip_command_bodies() { cat; }
fi
export SOLEUR_HOOK_NAME="pre-merge-auto-close-scan"

INPUT=$(cat)
# `|| true`: jq exits non-zero on malformed/empty stdin under pipefail; degrade
# to "" (no detection → clean allow) rather than aborting.
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // ""' || true)
SCAN=$(printf '%s' "$CMD" | strip_command_bodies || printf '%s' "$CMD")

# Only intercept `gh pr merge` (incl. the `… -- gh pr merge` wrapped form).
if ! echo "$SCAN" | grep -qE '(^|&&|\|\||;|\s--\s)\s*gh\s+pr\s+merge(\s|$)'; then
  exit 0
fi

WORK_DIR=$(echo "$INPUT" | jq -r '.cwd // ""' || true)
[[ -n "$WORK_DIR" && -d "$WORK_DIR" ]] || exit 0
git -C "$WORK_DIR" rev-parse --git-dir >/dev/null 2>&1 || exit 0

BRANCH=$(git -C "$WORK_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
[[ -n "$BRANCH" && "$BRANCH" != "main" && "$BRANCH" != "master" && "$BRANCH" != "HEAD" ]] || exit 0

# Ack escape hatch: SOLEUR_ACK_AUTOCLOSE=1 means the operator has confirmed the
# embedded close is intentional (rare — a prose sentence that really should
# close). Mirrors the ack-env pattern used by sibling gates.
[[ "${SOLEUR_ACK_AUTOCLOSE:-}" == "1" ]] && exit 0

# Build the scan corpus: the branch commit bodies (feed the squash commit) AND
# the PR body (the other squash-message source, repo-config-dependent). Both are
# best-effort; a failure to read either must not block the merge.
SCAN_FILE=$(mktemp 2>/dev/null) || exit 0
GH_ERR=$(mktemp 2>/dev/null) || exit 0
trap 'rm -f "$SCAN_FILE" "$GH_ERR"' EXIT

# A skipped arm is ANNOUNCED. The decision still fails open — a hook must never
# wedge a merge on its own bug — but failing open in SILENCE is exactly how the
# PR-body arm stayed dead for 17 days at 8/8 green. One terse line per arm, not
# a banner: a notice the operator learns to ignore is how the next one hides.
notice() { printf 'pre-merge-auto-close-scan: %s\n' "$1" >&2; }

# ONE shared deadline across BOTH gh arms, not an independent `timeout 8` each —
# those are additive, and gh really does hang past 20s on blackholed packets (it
# fails fast, ~0.1s, only on DNS failure).
GH_DEADLINE=$(( SECONDS + 8 ))
gh_budget() { local r=$(( GH_DEADLINE - SECONDS )); (( r > 0 )) || r=1; printf '%s' "$r"; }

if ! git -C "$WORK_DIR" log origin/main..HEAD --format=%B 2>/dev/null >>"$SCAN_FILE"; then
  notice "scanned WITHOUT branch commit bodies (git log origin/main..HEAD failed)"
fi
COMMIT_LINES=$(wc -l < "$SCAN_FILE" 2>/dev/null | tr -d '[:space:]')
[[ "$COMMIT_LINES" =~ ^[0-9]+$ ]] || COMMIT_LINES=0

# PR body, bounded so a slow/absent network never stalls the merge. No --repo:
# gh resolves the repository from the working directory's remote, which also
# handles SSH-alias remotes, insteadOf rewrites, GH_REPO and gh-resolved.
# Hand-building the slug is what made this arm dead code — the sed kept the
# trailing `.git` on SSH remotes, gh answered `Could not resolve to a
# Repository`, and `|| true` swallowed it (#6775 D1).
if ! (cd "$WORK_DIR" && timeout "$(gh_budget)" gh pr view "$BRANCH" --json body --jq '.body') \
     >>"$SCAN_FILE" 2>"$GH_ERR"; then
  # gh exits non-zero BOTH when no PR exists for the branch — a normal pre-PR
  # state — and when it cannot reach GitHub. Only the latter is worth a line;
  # announcing the former would cry wolf on every pre-PR merge attempt.
  if ! grep -qiE 'no (open )?pull requests? found|no pull requests found' "$GH_ERR"; then
    notice "scanned WITHOUT the PR body (gh pr view failed) — commit bodies only"
  fi
fi
[[ -s "$SCAN_FILE" ]] || exit 0

# Reuse the canonical scanner (single-sources GitHub's keyword set + locale pin),
# then keep only PROSE-EMBEDDED matches: lines whose close-keyword is NOT the
# start-of-line directive (a standalone `Closes #N` / `- Fixes #N` is intentional).
# Resolve from the repo toplevel, not the payload cwd: a `gh pr merge` issued
# from a subdirectory would otherwise miss the scanner and exit 0 in silence.
REPO_TOP=$(git -C "$WORK_DIR" rev-parse --show-toplevel 2>/dev/null || echo "$WORK_DIR")
SCANNER="$REPO_TOP/plugins/soleur/skills/ship/scripts/auto-close-scan.sh"
if [[ ! -f "$SCANNER" ]]; then
  notice "SKIPPED — scanner not found at $SCANNER"
  exit 0
fi

# Run the canonical scanner ONCE and derive BOTH arms from its output. The two
# arms have different populations, and the ordering here is load-bearing:
#
#   prose arm  — a close keyword that is NOT the start-of-line directive.
#   label arm  — every issue this corpus would actually close, standalone or not.
#
# The label arm's entire target population is the STANDALONE `Closes #N`, which
# by construction yields an EMPTY prose arm. So a label gate appended after the
# prose arm's `[[ -n "$EMBEDDED" ]] || exit 0` early exit can never fire on any
# input it exists for — while still passing every test, because tests exercise
# the deny path directly. That is the same shape as the defect this hook is
# being repaired for. Exit only when BOTH arms are empty.
RAW=$(bash "$SCANNER" "$SCAN_FILE" 2>/dev/null || true)
[[ -n "$RAW" ]] || exit 0

DIRECTIVE='^[0-9]+:[[:space:]]*([-*>][[:space:]]*)*(close[sd]?|fix(es|ed)?|resolve[sd]?)[[:space:]]+(#[0-9]+|GH-[0-9]+)'
EMBEDDED=$(printf '%s\n' "$RAW" | grep -viE "$DIRECTIVE" || true)

# Extraction contract. The scanner emits `<line-number>:<matched-text>`, so:
#   (a) strip the `^N:` prefix FIRST, or a line number is read as an issue
#       number (`12:` yields issue 12);
#   (b) pair each number with ITS OWN preceding keyword — a bare `#N` scrape
#       denies over an issue the PR explicitly declined to close
#       (`Refs #6617, closes #6295` must not implicate #6617);
#   (c) match globally per line, since a line-leading directive launders every
#       later close on that line past the prose filter.
# Surface attribution uses the line number against the commit-arm line count,
# so the deny can tell the operator WHICH body to scrub — the whole point of
# #6775 was that the keyword had to be removed in two places.
REFERENCED=$(printf '%s\n' "$RAW" | while IFS= read -r line; do
  [[ -n "$line" ]] || continue
  num="${line%%:*}"; text="${line#*:}"
  surface="the commit message"
  [[ "$num" =~ ^[0-9]+$ ]] && (( num > COMMIT_LINES )) && surface="the PR body"
  printf '%s\n' "$text" \
    | grep -oiE '(close[sd]?|fix(es|ed)?|resolve[sd]?)[[:space:]]+(#|GH-)[0-9]+' \
    | grep -oE '[0-9]+$' \
    | while IFS= read -r n; do printf '%s\t%s\n' "$n" "$surface"; done
done | sort -u -k1,1)

[[ -n "$EMBEDDED" || -n "$REFERENCED" ]] || exit 0

emit_deny() {
  jq -n --arg r "$1" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

# --- follow-through label gate ------------------------------------------------
# A standalone `Closes #N` is allowed BY DESIGN — it is the form every ordinary
# fix-PR uses. But when #N carries `follow-through`, closing it at merge makes
# the daily sweeper skip the tracker (it evaluates only OPEN issues), so the soak
# verification the tracker existed to enforce never runs and nobody is told.
#
# The hatch is SCOPED, deliberately not the broad SOLEUR_ACK_AUTOCLOSE: that one
# is checked above corpus construction and would disarm the prose arm too.
if [[ -n "$REFERENCED" && "${SOLEUR_ACK_FOLLOWTHROUGH_CLOSE:-}" != "1" ]]; then
  REF_COUNT=$(printf '%s\n' "$REFERENCED" | grep -c . || true)
  if (( REF_COUNT > 3 )); then
    # Bounded, not an unbounded gh loop on the merge path.
    notice "follow-through label gate SKIPPED — $REF_COUNT referenced issues exceeds the fan-out cap of 3"
  else
    PROTECTED=""
    while IFS=$'\t' read -r n surface; do
      [[ -n "$n" ]] || continue
      # Per-issue lookup, never `gh issue list`: that paginates at 30 by default
      # and a full page is indistinguishable from a truncated one, which would
      # silently exempt the OLDEST trackers — the ones this gate most protects.
      labels=$( (cd "$WORK_DIR" && timeout "$(gh_budget)" gh issue view "$n" --json labels --jq '[.labels[].name]|join(",")') 2>/dev/null ) || labels="__ERR__"
      if [[ "$labels" == "__ERR__" ]]; then
        notice "follow-through label gate SKIPPED for #$n — gh issue view failed"
        continue
      fi
      [[ ",$labels," == *",follow-through,"* ]] && PROTECTED="${PROTECTED}  #$n — referenced from $surface"$'\n'
    done <<< "$REFERENCED"

    if [[ -n "$PROTECTED" ]]; then
      emit_deny "BLOCKED (follow-through tracker): this merge would auto-close an issue labelled 'follow-through':

$(printf '%s' "$PROTECTED")

Those issues are protected because closing one makes the daily sweeper skip it — the sweeper only evaluates OPEN issues — so the soak verification the tracker exists to enforce silently never runs. GitHub's parser reads BOTH the squash commit body and the PR body, so the keyword may have to be removed in both.

Fix: change the closing keyword to a non-closing reference ('Ref #N', 'Tracks #N') in whichever body is named above. If this PR genuinely resolves the tracker, re-run with SOLEUR_ACK_FOLLOWTHROUGH_CLOSE=1 (that hatch is scoped to THIS check and leaves the prose-embedded guard armed).

Not to be confused with ship-soak-followthrough-gate.sh, which denies the inverse case — a tracker that is MISSING sweeper enrollment — and is overridden by SOLEUR_SKIP_SOAK_FOLLOWTHROUGH_GATE=1."
    fi
  fi
fi

# --- prose-embedded arm (preserved for ALL issues, labelled or not) -----------
[[ -n "$EMBEDDED" ]] || exit 0

emit_deny "BLOCKED: a commit/PR body has a prose-embedded auto-close keyword that will auto-close an issue on merge (GitHub's parser is markdown- and position-blind):

$(printf '%s\n' "$EMBEDDED" | sed 's/^/  /')

Fix: reword the sentence to remove the close-keyword + #N adjacency — e.g. 'auto-resolves issue #N' or 'the sweeper will close issue #N' (no bare 'close(s)/fix(es)/resolve(s) #N'). A standalone 'Closes #N' line is fine and is NOT flagged. If this close is genuinely intended, re-run with SOLEUR_ACK_AUTOCLOSE=1."
