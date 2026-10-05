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
# Idempotent IN ITS WRITES. Re-running it when the directive and the label are
# already present appends nothing and adds nothing. Step 4 is NOT a write and is
# not idempotent in that sense: it dispatches a fresh dry-run sweep every time,
# because the only honest confirmation is a run this invocation caused. That is
# cheap and read-only, but it is a run, so say so rather than claim the whole
# script is a no-op.
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
# Same containment the probe applies, and for the same reason: this runs in a
# checkout that is not ours to modify. `--no-tags` alone is not the bound --
# FETCH_HEAD, an auto-gc and submodule recursion all write into the shared common
# dir. An explicit refspec, because a bare `origin main` still updates FETCH_HEAD.
#
# The `|| true` is deliberate (an offline operator should still get the clear
# "not on origin/main" refusal below rather than a fetch error), but it means the
# ref may be STALE. So the refusal names that possibility instead of asserting a
# fact about the remote.
if ! git -c gc.auto=0 fetch --no-tags --no-recurse-submodules --no-write-fetch-head \
       -q origin '+refs/heads/main:refs/remotes/origin/main' 2>/dev/null; then
  printf 'note: could not fetch origin/main; judging against the ref already in this checkout, which may be stale\n' >&2
fi
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
# Match on THIS directive, not on any directive. The verification below asserts
# `script=$PROBE_REL`, so a foreign `soleur:followthrough` line -- an operator
# enrolling a different probe on the same tracker -- would skip the append and
# then die reporting that the edit did not land, which describes the wrong fault
# and sends the reader to the wrong place.
if grep -qF "script=${PROBE_REL}" "$BODY_FILE"; then
  printf 'directive for %s already present on #%s — not appending a second one\n' "$PROBE_REL" "$TRACKER"
else
  printf '\n\n%s\n' "$DIRECTIVE" >> "$BODY_FILE"
  gh issue edit "$TRACKER" --body-file "$BODY_FILE" \
    || die "could not append the directive to #$TRACKER"
  printf 'appended the sweeper directive to #%s\n' "$TRACKER"
fi

# ---- 3. apply the label ---------------------------------------------------
# Materialise, THEN test. `producer | grep -q` under `pipefail` takes the pipe's
# status, so a gh failure here would assert "the label is not present" from a read
# that never happened -- and the remedy for that mistaken reading is a write.
labels="$(gh issue view "$TRACKER" --json labels --jq '.labels[].name')" \
  || die "could not read the labels of #$TRACKER"
if grep -qx 'follow-through' <<<"$labels"; then
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
verify_labels="$(gh issue view "$TRACKER" --json labels --jq '.labels[].name')" \
  || die "could not re-read the labels of #$TRACKER"
grep -qx 'follow-through' <<<"$verify_labels" \
  || die "the follow-through label is not present on #$TRACKER after the edit"
printf 'verified: #%s carries the directive and the label\n' "$TRACKER"

# ---- 4. dispatch a dry-run sweep and assert it names the probe ------------
# A dispatch that "succeeded" proves the workflow started, not that this
# tracker was picked up. The assertion is on the run LOG naming the probe.
# BIND THE CONFIRMATION TO THIS DISPATCH. `--limit 1` unfiltered names the newest
# run of the workflow, which on a DAILY schedule is very often last night's cron.
# That run already names the probe once enrolment has ever succeeded, so the check
# could CONFIRM from a run that predates this script -- and, on a busy repo, could
# equally deny from an unrelated newer one. Stamp the clock first, then require
# both `workflow_dispatch` and `createdAt >= T0`.
T0="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
gh workflow run "$WORKFLOW" -f dry_run=true \
  || die "could not dispatch $WORKFLOW"
printf 'dispatched %s (dry_run=true) at %s; waiting for that run to appear...\n' "$WORKFLOW" "$T0"

run_id=""
for _ in $(seq 1 30); do
  sleep 10
  runs="$(gh run list --workflow "$WORKFLOW" --event workflow_dispatch --limit 20 \
            --json databaseId,createdAt --jq '.[] | [.databaseId, .createdAt] | @tsv')" || continue
  run_id="$(awk -v t0="$T0" -F'\t' '$2 >= t0 { print $1; exit }' <<<"$runs")"
  [[ -n "$run_id" ]] && break
done
[[ -n "$run_id" ]] \
  || die "no workflow_dispatch run of $WORKFLOW created at or after $T0 appeared within ~5 minutes; check the Actions tab" 3

# WAIT FOR THE RUN TO ACTUALLY COMPLETE, AND SAY SO IF IT DOES NOT.
#
# The previous form was `gh run watch ... || true` followed immediately by
# `gh run view --log`. Both halves discard the outcome, and the failure that
# produces is not a missing confirmation -- it is a CONFIRMED DENIAL of
# something that never happened. Measured on the real #7922 enrolment: the
# dispatch queued for ELEVEN minutes (created 09:42:34, started 09:53:51),
# `gh run watch` returned without waiting, `gh run view --log` on a queued run
# prints "run is still in progress" to stderr and NOTHING to stdout, the grep
# found no probe name in an empty string, and the script reported
#
#   run 34336223631 did not name the probe
#
# The run went on to name it three times and the enrolment was fine. That is
# could-not-measure rendered as measured-bad, on the one line an operator reads
# to decide whether a legal tracker is being watched.
#
# So: poll the run's own status until it is `completed`, and give a queued or
# slow run its own exit code (3, transient) with its own message -- distinct
# from "it ran and the tracker was not swept" (still 3, but a different cause
# and a different next step).
run_status=""
for _ in $(seq 1 90); do
  run_status="$(gh run view "$run_id" --json status --jq .status 2>/dev/null)" || run_status=""
  [[ "$run_status" == "completed" ]] && break
  sleep 20
done
[[ "$run_status" == "completed" ]] \
  || die "run $run_id is still '${run_status:-unreadable}' after ~30 minutes; the enrolment writes (directive + label) are DONE and verified above -- only this confirmation step is unfinished. Nothing is broken; re-check with: gh run view $run_id --log" 3

log="$(gh run view "$run_id" --log 2>/dev/null || true)"
[[ -n "$log" ]] \
  || die "run $run_id completed but its log came back EMPTY, so the sweep could not be inspected. This is a read failure, NOT a finding that the tracker was unswept. Inspect: gh run view $run_id --log" 3
if grep -qF "ccla-representative-icla-7922" <<<"$log"; then
  printf 'enrolment CONFIRMED: run %s names the probe.\n' "$run_id"
  printf 'The sweeper will now comment on #%s daily. Exit 2 is NOT YET, 5 is ACTION, 3 is CANNOT ESTABLISH.\n' "$TRACKER"
  printf 'It never closes #%s — do that by hand when the roster row is recorded.\n' "$TRACKER"
else
  die "run $run_id did not name the probe. The tracker may not have been swept -- the sweeper bounds its open set (see OPEN_LIMIT in scripts/sweep-followthroughs.sh) and raises the run's verdict when that bound truncates, so check the run for a truncation line too. Inspect: gh run view $run_id --log" 3
fi
