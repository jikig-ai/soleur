#!/usr/bin/env bash
# PreToolUse hook on `gh pr merge`. GitHub's issue-closing parser reads the PR
# title, the PR body AND the squash commit body, so a closing keyword in any of
# the three auto-closes on merge. Two checks, evaluated in this order:
#
#   1. follow-through label gate — denies a close of ANY form (standalone or
#      prose-embedded) when the target issue is OPEN and carries
#      `follow-through`. Closing such a tracker makes the daily sweeper skip it
#      (it evaluates only OPEN issues), so the soak it exists to enforce never
#      runs and nobody is told.
#   2. prose-embedded arm — denies a close-keyword that appears AFTER prose on
#      its line, for any issue. A standalone `Closes #N` on its own line stays
#      ALLOWED; that is the form every ordinary fix-PR uses.
#
# Escape hatches (each disarms exactly one thing):
#   SOLEUR_ACK_AUTOCLOSE=1            BOTH checks — read above corpus construction
#   SOLEUR_ACK_FOLLOWTHROUGH_CLOSE=1  the label gate only; prose arm stays armed
#
# This is one of five surfaces enforcing the same lifecycle, two of which deny
# on INVERSE readings of the `follow-through` label. The full map, and which is
# authoritative for which bypass class, lives in `.claude/hooks/README.md`
# §"Merge-boundary auto-close guard" — kept in one place so the two copies
# cannot drift.
#
# Best-effort, NOT a boundary. It only sees merges this harness intercepts.
# Known bypasses: merging from `main` (the branch guard exits first), the GitHub
# web UI, an admin merge, a CI-queued `--auto` merge that GitHub completes later
# (title, body and labels can all change in that window — and `--auto` is the
# workflow's MANDATED merge form, so this is the common case, not an edge), the
# OpenHands harness, and the `OWNER/REPO#N` / full-issue-URL reference forms the
# canonical scanner does not recognise. `main` does carry server-side rulesets
# with required status checks, so a durable backstop CAN be added there; none
# covers this class today.
#
# Fail-open: any infrastructure error exits 0 (allow). A hook must never wedge a
# merge on its own bug — but every skipped arm reports itself, via a
# `systemMessage` the operator sees and an incident row the CI aggregator reads.
# Silence is how the PR-body arm stayed dead for 17 days at 8/8 green.
set -uo pipefail

_LIB_DIR="$(dirname "${BASH_SOURCE[0]}")/lib"
# strip_command_bodies (blank quoted/heredoc bodies so a commit MESSAGE that
# documents "gh pr merge" is not mis-detected as a merge — same #4600/#5192
# canonical helper pre-merge-rebase.sh uses) + emit_incident.
if [[ -f "$_LIB_DIR/incidents.sh" ]]; then
  # shellcheck source=/dev/null
  source "$_LIB_DIR/incidents.sh"
else
  strip_command_bodies() { cat; }
fi
export SOLEUR_HOOK_NAME="pre-merge-auto-close-scan"

# jq is load-bearing twice over: it parses the payload AND carries the deny
# verdict. Without it the hook cannot speak at all, so say so once, loudly,
# rather than dying wordlessly at the first use.
if ! command -v jq >/dev/null 2>&1; then
  printf 'pre-merge-auto-close-scan: SKIPPED — jq unavailable, merge NOT scanned\n' >&2
  exit 0
fi

INPUT=$(cat)
# `|| true`: jq exits non-zero on malformed/empty stdin under pipefail; degrade
# to "" (no detection → clean allow) rather than aborting.
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // ""' || true)
SCAN=$(printf '%s' "$CMD" | strip_command_bodies || printf '%s' "$CMD")

# Only intercept `gh pr merge` (incl. the `… -- gh pr merge` wrapped form).
if ! echo "$SCAN" | grep -qE '(^|&&|\|\||;|\s--\s)\s*gh\s+pr\s+merge(\s|$)'; then
  exit 0
fi

# Notices accumulate and are reported on the allow path. stderr alone is NOT
# sufficient: Claude Code discards a PreToolUse hook's stderr on exit 0 (the
# repo's own `headless_or_stderr` in lib/session-state.sh exists for exactly
# this), so a stderr-only notice is invisible to both operator and agent —
# which would reinstate, inside this fix, the silent-degradation defect the fix
# exists to remove. `systemMessage` is the operator-visible exit-0 channel;
# `emit_incident` is the durable one the CI aggregator reads.
NOTICES=""
notice() {
  NOTICES="${NOTICES}${NOTICES:+$'\n'}pre-merge-auto-close-scan: $1"
  printf 'pre-merge-auto-close-scan: %s\n' "$1" >&2
  declare -f emit_incident >/dev/null && \
    emit_incident pre-merge-auto-close-scan degraded "$1" "$CMD" 2>/dev/null || true
}

# Every allow path that may carry a notice exits through here.
allow_exit() {
  [[ -n "$NOTICES" ]] && jq -n --arg m "$NOTICES" '{systemMessage:$m}' 2>/dev/null
  exit 0
}

WORK_DIR=$(echo "$INPUT" | jq -r '.cwd // ""' || true)
if [[ -z "$WORK_DIR" || ! -d "$WORK_DIR" ]]; then
  notice "SKIPPED — no usable cwd in the hook payload"
  allow_exit
fi
# Not a git repo: nothing to scan, and not a failure worth announcing.
git -C "$WORK_DIR" rev-parse --git-dir >/dev/null 2>&1 || exit 0

BRANCH=$(git -C "$WORK_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
# main/master and detached HEAD are documented bypasses, deliberately silent.
[[ -n "$BRANCH" && "$BRANCH" != "main" && "$BRANCH" != "master" && "$BRANCH" != "HEAD" ]] || exit 0

# Broad ack hatch. Announced: an env var inherited from a shell profile or an
# earlier session would otherwise leave the guard permanently dark with no
# signal at all — the exact 17-day shape.
if [[ "${SOLEUR_ACK_AUTOCLOSE:-}" == "1" ]]; then
  notice "BOTH checks disarmed by SOLEUR_ACK_AUTOCLOSE=1"
  allow_exit
fi

SCAN_FILE=$(mktemp 2>/dev/null) || { notice "SKIPPED — mktemp failed"; allow_exit; }
trap 'rm -f "$SCAN_FILE" "${GH_ERR:-}"' EXIT INT TERM
GH_ERR=$(mktemp 2>/dev/null) || { notice "SKIPPED — mktemp failed"; allow_exit; }

# ONE shared deadline per gh phase. Reset before the label-gate phase so local
# CPU work cannot silently spend the network budget (a large corpus would
# otherwise starve every label lookup and disarm the gate). Note the floor of 1
# is load-bearing, not cosmetic: `timeout 0` DISABLES the timeout, so an
# exhausted budget without the floor would mean an UNBOUNDED gh call on the
# merge path. Consequence: total time can exceed the nominal budget by the
# number of floored calls.
GH_DEADLINE=$(( SECONDS + 8 ))
gh_budget() { local r=$(( GH_DEADLINE - SECONDS )); (( r > 0 )) || r=1; printf '%s' "$r"; }

if ! git -C "$WORK_DIR" log origin/main..HEAD --format=%B 2>/dev/null >>"$SCAN_FILE"; then
  notice "scanned WITHOUT branch commit bodies (git log origin/main..HEAD failed)"
fi
COMMIT_LINES=$(wc -l < "$SCAN_FILE" 2>/dev/null | tr -d '[:space:]')
[[ "$COMMIT_LINES" =~ ^[0-9]+$ ]] || COMMIT_LINES=0

# Prefer an explicit PR number/URL from the intercepted command over the current
# branch: `gh pr merge 1234` from an unrelated branch would otherwise scan the
# WRONG PR and apply that verdict to #1234.
PR_REF=$(printf '%s' "$SCAN" | grep -oE 'gh[[:space:]]+pr[[:space:]]+merge[[:space:]]+([0-9]+|https://[^[:space:]]+)' | awk '{print $NF}' | head -1)
[[ -n "$PR_REF" ]] || PR_REF="$BRANCH"

# Title AND body: GitHub pre-fills the squash commit SUBJECT from the PR title,
# so a title-borne `Closes #N` closes on merge. Both sibling surfaces (/ship
# Phase 6 and pr-auto-close-scanner.yml) already scan it. No --repo: gh resolves
# the repository from the working directory, which also handles SSH-alias
# remotes, insteadOf rewrites and GH_REPO. Hand-building the slug is what made
# this arm dead code — the sed kept the trailing `.git` on SSH remotes, gh
# answered `Could not resolve to a Repository`, and `|| true` swallowed it.
if ! (cd "$WORK_DIR" && timeout "$(gh_budget)" gh pr view "$PR_REF" --json title,body --jq '.title, .body') \
     >>"$SCAN_FILE" 2>"$GH_ERR"; then
  # gh exits non-zero BOTH when no PR exists for the branch — a normal pre-PR
  # state — and when it cannot reach GitHub. Only the latter is worth a line;
  # announcing the former would cry wolf on every pre-PR merge attempt.
  if ! grep -qiE 'no (open )?pull requests? found' "$GH_ERR"; then
    notice "scanned WITHOUT the PR title and body (gh pr view failed) — commit bodies only"
  fi
fi
[[ -s "$SCAN_FILE" ]] || allow_exit

# The canonical scanner single-sources GitHub's keyword set and locale pin.
# Resolve it from the repo toplevel, not the payload cwd: a `gh pr merge` issued
# from a subdirectory would otherwise miss it and exit 0 in silence.
REPO_TOP=$(git -C "$WORK_DIR" rev-parse --show-toplevel 2>/dev/null || echo "$WORK_DIR")
SCANNER="$REPO_TOP/plugins/soleur/skills/ship/scripts/auto-close-scan.sh"
if [[ ! -f "$SCANNER" ]]; then
  notice "SKIPPED — scanner not found at $SCANNER"
  allow_exit
fi

# Run the canonical scanner ONCE and derive BOTH arms from its output. The
# ordering is load-bearing: the label arm's target population is the STANDALONE
# `Closes #N`, which by construction yields an EMPTY prose arm — so a label gate
# placed after the prose arm's early exit could never fire on any input it
# exists for, while still passing every test. Exit only when BOTH are empty.
# (T3 pins this reachability as executable fact.)
if ! RAW=$(bash "$SCANNER" "$SCAN_FILE" 2>"$GH_ERR"); then
  notice "SKIPPED — scanner failed to run"
  allow_exit
fi
[[ -n "$RAW" ]] || allow_exit

DIRECTIVE='^[0-9]+:[[:space:]]*([-*>][[:space:]]*)*(close[sd]?|fix(es|ed)?|resolve[sd]?)[[:space:]]+(#[0-9]+|GH-[0-9]+)'
EMBEDDED=$(printf '%s\n' "$RAW" | grep -viE "$DIRECTIVE" || true)

# Extraction contract. The scanner emits `<line-number>:<matched-text>`, so:
#   (a) strip the `^N:` prefix FIRST, or a line number is read as an issue
#       number (`12:` yields issue 12);
#   (b) pair each number with ITS OWN preceding keyword — a bare `#N` scrape
#       denies over an issue the PR declined to close;
#   (c) require a word boundary before the keyword, or `prefixes #4242` matches
#       as `fixes #4242` and denies over an unrelated issue;
#   (d) match globally per line, since a line-leading directive launders every
#       later close on that line past the prose filter.
# One awk pass, not a per-line fork chain: a max-size PR body of close keywords
# is ~6.5k matches, and three forks per match put a four-minute stall on the
# merge path (bulk-close PRs from the drain skills reach this in practice).
# Surface is attributed from the line number so the deny says WHICH text to
# scrub — the whole lesson of #6775 was that the keyword lived in two places.
REFERENCED=$(printf '%s\n' "$RAW" | awk -v cl="$COMMIT_LINES" '
{
  n = $0; sub(/:.*/, "", n)
  text = substr($0, index($0, ":") + 1)
  if (n !~ /^[0-9]+$/)      surface = "a commit message"
  else if (n+0 <= cl+0)     surface = "a commit message"
  else if (n+0 == cl+1)     surface = "the PR title"
  else                      surface = "the PR body"
  low = tolower(text)
  while (match(low, /(^|[^a-z0-9_])(close[sd]?|fix(es|ed)?|resolve[sd]?)[ \t]+(#|gh-)[0-9]+/)) {
    m = substr(low, RSTART, RLENGTH)
    sub(/^.*[^0-9]/, "", m)
    print m "\t" surface
    low = substr(low, RSTART + RLENGTH)
  }
}' | sort -u)

[[ -n "$EMBEDDED" || -n "$REFERENCED" ]] || allow_exit

emit_deny() {
  local payload
  # Build first, then verify it parsed: if jq fails here the verdict is LOST and
  # exit 0 reads as allow — the one fail-open that would discard a deny the hook
  # had already reached.
  payload=$(jq -n --arg r "$1" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}' 2>/dev/null)
  if [[ -z "$payload" ]]; then
    printf 'pre-merge-auto-close-scan: DENY LOST — could not encode verdict. Reason follows:\n%s\n' "$1" >&2
    exit 2   # non-zero surfaces stderr to the agent; a lost deny must not read as allow
  fi
  declare -f emit_incident >/dev/null && \
    emit_incident pre-merge-auto-close-scan deny "${1:0:50}" "$CMD" 2>/dev/null || true
  printf '%s\n' "$payload"
  exit 0
}

# --- follow-through label gate ------------------------------------------------
# A standalone `Closes #N` is allowed BY DESIGN — it is the form every ordinary
# fix-PR uses. But when #N is an OPEN issue carrying `follow-through`, closing it
# at merge makes the daily sweeper skip the tracker and the soak silently never
# runs. The hatch is SCOPED, deliberately not the broad SOLEUR_ACK_AUTOCLOSE:
# that one is read above corpus construction and would disarm the prose arm too.
if [[ -n "$REFERENCED" ]]; then
  if [[ "${SOLEUR_ACK_FOLLOWTHROUGH_CLOSE:-}" == "1" ]]; then
    notice "follow-through label gate disarmed by SOLEUR_ACK_FOLLOWTHROUGH_CLOSE=1"
  else
    GH_DEADLINE=$(( SECONDS + 8 ))   # network budget, unspent by the local work above
    PROTECTED=""
    UNCHECKED=""
    checked=0
    while IFS= read -r n; do
      [[ "$n" =~ ^[0-9]+$ ]] || continue
      # Bounded fan-out, but NOT all-or-nothing: skipping the whole gate above a
      # threshold fails open on exactly the bulk-close PRs the drain skills
      # produce, which are the likeliest to sweep up a tracker. Two independent
      # bounds, and note the iteration order is numeric-sorted rather than
      # document order — so a low cap does not check "the first few referenced",
      # it checks an arbitrary subset, which is why the cap is set well above the
      # observed maximum (2 close-refs across the last 400 commits on main).
      if (( checked >= 10 )) || (( SECONDS >= GH_DEADLINE )); then
        UNCHECKED="${UNCHECKED}${UNCHECKED:+ }#$n"
        continue
      fi
      checked=$((checked+1))
      # Per-issue lookup, never a paginating list call: `gh issue list` caps at
      # 30 by default and a full page is indistinguishable from a truncated one,
      # which would silently exempt the OLDEST trackers. state+labels in ONE call.
      meta=$( (cd "$WORK_DIR" && timeout "$(gh_budget)" gh issue view "$n" --json state,labels --jq '.state + "|" + ([.labels[].name]|join(","))') 2>/dev/null ) || meta="__ERR__"
      if [[ "$meta" == "__ERR__" || -z "$meta" ]]; then
        notice "follow-through label gate SKIPPED for #$n — gh issue view failed"
        continue
      fi
      # A CLOSED tracker cannot be closed again by this merge, and the harm the
      # gate prevents is already realised — denying there is a pure false positive.
      [[ "${meta%%|*}" == "OPEN" ]] || continue
      [[ ",${meta#*|}," == *",follow-through,"* ]] || continue
      # `paste -sd', '` would use the delimiter set cyclically — only the comma
      # for two items, giving "message,the". Join with a real ", ".
      surfaces=$(printf '%s\n' "$REFERENCED" | awk -F'\t' -v k="$n" '$1==k{print $2}' | sort -u | paste -sd, - | sed 's/,/, /g')
      PROTECTED="${PROTECTED}  #$n — referenced from ${surfaces}"$'\n'
    done <<< "$(printf '%s\n' "$REFERENCED" | cut -f1 | sort -u)"

    [[ -n "$UNCHECKED" ]] && notice "follow-through label gate could not vouch for $UNCHECKED (fan-out cap or time budget reached) — those issues were NOT checked"

    if [[ -n "$PROTECTED" ]]; then
      emit_deny "BLOCKED (follow-through tracker): this merge would auto-close an OPEN issue labelled 'follow-through':

$(printf '%s' "$PROTECTED")

Those issues are protected because closing one makes the daily sweeper skip it — the sweeper only evaluates OPEN issues — so the soak verification the tracker exists to enforce silently never runs. GitHub's parser reads the PR title, the PR body AND the squash commit body, so the keyword may have to be removed from more than one of them.

Fix: change the closing keyword to a non-closing reference ('Ref #N', 'Tracks #N') in each surface named above. 'Ref #N' deliberately keeps the tracker in the soak gate's scope — that is intended, not a new problem. For a surface that is 'a commit message', you do not need an interactive rebase: 'gh pr merge --squash --body <clean text>' overrides the squash message without rewriting history.

If this PR genuinely resolves the tracker, re-run with SOLEUR_ACK_FOLLOWTHROUGH_CLOSE=1 — that hatch is scoped to THIS check and leaves the prose-embedded guard armed.

Not to be confused with ship-soak-followthrough-gate.sh, which denies the INVERSE case — a tracker that is MISSING sweeper enrollment — and is overridden by SOLEUR_SKIP_SOAK_FOLLOWTHROUGH_GATE=1."
    fi
  fi
fi

# --- prose-embedded arm (preserved for ALL issues, labelled or not) -----------
[[ -n "$EMBEDDED" ]] || allow_exit

# Attribute each match to its surface. The raw scanner prefix is a line number
# into a temp file this hook deletes on exit, so quoting it verbatim would hand
# the reader an offset that indexes nothing.
EMBEDDED_RENDERED=$(printf '%s\n' "$EMBEDDED" | awk -v cl="$COMMIT_LINES" '
{
  n = $0; sub(/:.*/, "", n)
  text = substr($0, index($0, ":") + 1)
  if (n !~ /^[0-9]+$/)      surface = "a commit message"
  else if (n+0 <= cl+0)     surface = "a commit message"
  else if (n+0 == cl+1)     surface = "the PR title"
  else                      surface = "the PR body"
  printf "  %s: %s\n", surface, text
}')

emit_deny "BLOCKED: a commit/PR body has a prose-embedded auto-close keyword that will auto-close an issue on merge (GitHub's parser is markdown- and position-blind):

$EMBEDDED_RENDERED

Fix: reword the sentence to remove the close-keyword + #N adjacency — e.g. 'auto-resolves issue #N' or 'the sweeper will close issue #N' (no bare 'close(s)/fix(es)/resolve(s) #N'). A standalone 'Closes #N' line is fine and is NOT flagged.

If this close is genuinely intended, re-run with SOLEUR_ACK_AUTOCLOSE=1 — but note that hatch is NOT scoped to this message: it disarms the follow-through tracker gate in this hook as well. To keep that gate armed, reword instead."
