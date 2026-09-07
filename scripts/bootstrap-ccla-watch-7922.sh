#!/usr/bin/env bash
# Post-merge enrolment for the #7922 ICLA-signature watch.
#
# WHY THIS IS A SCRIPT AND NOT A CHECKLIST. `hr-multi-step-post-merge-bootstrap-script`:
# a post-merge sequence of more than one step is a script, because a checklist
# is a set of steps someone can do three of. All four steps below are
# scriptable, so none of them is handed to the operator.
#
# WHY IT RUNS AFTER MERGE AND NOT BEFORE. `scripts/sweep-followthroughs.sh`
# resolves a directive's `script=` against the checked-out DEFAULT BRANCH. A
# `follow-through` label applied while the probe still lives only on a feature
# branch produces a daily "script missing" line on stderr that nobody reads --
# a silent never-notice, which is the failure mode #7910 exists to remove.
#
# Idempotent: re-running it when the directive is already present is a no-op
# that reports so, rather than appending a second directive.
set -euo pipefail

TRACKER=7922
PROBE_REL="scripts/followthroughs/ccla-representative-icla-7922.sh"
# `earliest=` is the FILING date of the tracker, per followthrough-convention.
# NOT a far-future date: that would suppress the daily comment across exactly
# the window in which the operator must act, and the convention forbids it in
# terms. The probe self-gates via its own transient exit instead.
EARLIEST="2026-09-07T00:00:00Z"
WORKFLOW="scheduled-followthrough-sweeper.yml"

die() { printf '::error::bootstrap-ccla-watch: %s\n' "$1" >&2; exit "${2:-2}"; }

command -v gh >/dev/null 2>&1 || die "gh CLI is required"
gh auth status >/dev/null 2>&1 || die "gh is not authenticated"

REPO_ROOT="$(git rev-parse --show-toplevel)" || die "not inside a git repository"
cd "$REPO_ROOT"

# The gate the sweeper applies, applied here first so a broken enrolment is
# refused rather than published. `follow-through-directive-gate.sh` covers
# `gh issue create --label follow-through` and NOT `gh issue edit --add-label`,
# which is the path this script takes -- so this check is the only one standing.
[[ -f "$PROBE_REL" ]] || die "the probe is missing at $PROBE_REL -- has this merged to the default branch yet?"
[[ -x "$PROBE_REL" ]] || die "the probe at $PROBE_REL is not executable; the sweeper would refuse it"

# Refuse to enrol a probe that is not on the DEFAULT BRANCH, because that is the
# tree the sweeper actually resolves `script=` against. Present-in-the-worktree
# is not the property that matters.
git fetch --no-tags -q origin main 2>/dev/null || true
if ! git cat-file -e "origin/main:$PROBE_REL" 2>/dev/null; then
  die "the probe is not present at origin/main:$PROBE_REL. Enrolling now would give the sweeper a script= it cannot resolve, which fails as a daily stderr line nobody reads rather than loudly. Merge first, then re-run."
fi

# ---- 1. fetch the CURRENT body -------------------------------------------
# Read-modify-append, never a bare `--body-file` over a body that was not first
# fetched: `gh issue edit --body-file` REPLACES the whole body, so writing a
# constructed one would silently discard whatever the tracker has accumulated.
BODY_FILE="$(mktemp -t ccla-watch-body.XXXXXXXX.md)"
trap 'rm -f "$BODY_FILE"' EXIT
gh issue view "$TRACKER" --json body --jq .body > "$BODY_FILE" \
  || die "could not read the body of #$TRACKER"
[[ -s "$BODY_FILE" ]] || die "the body of #$TRACKER came back empty; refusing to overwrite it"

state="$(gh issue view "$TRACKER" --json state --jq .state)" || die "could not read the state of #$TRACKER"
[[ "$state" == "OPEN" ]] || die "#$TRACKER is $state; refusing to enrol a closed tracker"

# ---- 2. append the directive (idempotently) ------------------------------
DIRECTIVE="<!-- soleur:followthrough script=${PROBE_REL} earliest=${EARLIEST} -->"
if grep -qF 'soleur:followthrough' "$BODY_FILE"; then
  printf 'directive already present on #%s — not appending a second one\n' "$TRACKER"
else
  printf '\n\n%s\n' "$DIRECTIVE" >> "$BODY_FILE"
  gh issue edit "$TRACKER" --body-file "$BODY_FILE" \
    || die "could not append the directive to #$TRACKER"
  printf 'appended the sweeper directive to #%s\n' "$TRACKER"
fi

# ---- 3. apply the label ---------------------------------------------------
if gh issue view "$TRACKER" --json labels --jq '.labels[].name' | grep -qx 'follow-through'; then
  printf 'label follow-through already present on #%s\n' "$TRACKER"
else
  gh issue edit "$TRACKER" --add-label follow-through \
    || die "could not add the follow-through label to #$TRACKER"
  printf 'added the follow-through label to #%s\n' "$TRACKER"
fi

# Verify BOTH landed, from the server rather than from our own exit codes.
verify_body="$(gh issue view "$TRACKER" --json body --jq .body)" || die "could not re-read #$TRACKER"
grep -qF "script=${PROBE_REL}" <<<"$verify_body" \
  || die "the directive is not present on #$TRACKER after the edit"
gh issue view "$TRACKER" --json labels --jq '.labels[].name' | grep -qx 'follow-through' \
  || die "the follow-through label is not present on #$TRACKER after the edit"
printf 'verified: #%s carries the directive and the label\n' "$TRACKER"

# ---- 4. dispatch a dry-run sweep and assert it names the probe ------------
# A dispatch that "succeeded" proves the workflow started, not that this
# tracker was picked up. The assertion is on the run LOG naming the probe.
gh workflow run "$WORKFLOW" -f dry_run=true \
  || die "could not dispatch $WORKFLOW"
printf 'dispatched %s (dry_run=true); waiting for the run to appear...\n' "$WORKFLOW"

run_id=""
for _ in $(seq 1 30); do
  sleep 10
  run_id="$(gh run list --workflow "$WORKFLOW" --limit 1 --json databaseId,status --jq '.[0].databaseId')" || true
  [[ -n "$run_id" && "$run_id" != "null" ]] && break
done
[[ -n "$run_id" && "$run_id" != "null" ]] \
  || die "no run appeared for $WORKFLOW within ~5 minutes; check the Actions tab" 3

gh run watch "$run_id" --exit-status >/dev/null 2>&1 || true
log="$(gh run view "$run_id" --log 2>/dev/null || true)"
if grep -qF "ccla-representative-icla-7922" <<<"$log"; then
  printf 'enrolment CONFIRMED: run %s names the probe.\n' "$run_id"
  printf 'The sweeper will now comment on #%s daily. Exit 2 is NOT YET, 5 is ACTION, 3 is CANNOT ESTABLISH.\n' "$TRACKER"
  printf 'It never closes #%s — do that by hand when the roster row is recorded.\n' "$TRACKER"
else
  die "run $run_id did not name the probe. The tracker may not have been swept (the sweeper caps at --limit 50 against the open follow-through set, newest first). Inspect: gh run view $run_id --log" 3
fi
