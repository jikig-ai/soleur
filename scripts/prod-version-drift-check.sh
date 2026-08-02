#!/usr/bin/env bash
# prod-version-drift-check.sh (#7091) — is production serving a build that is missing
# commits it should have?
#
# SOURCED by scripts/prod-version-drift-check.test.sh (which drives classify_drift and
# oldest_epoch_from_log directly) and INVOKED by
# .github/workflows/scheduled-prod-version-drift.yml. Sourcing must not run main().
#
# THE INVARIANT: prod is healthy iff it is missing no commit that would have TRIGGERED a
# deploy. That is a range query, not a SHA equality test:
#
#     git log --first-parent --format='%H %ct' "<prod_sha>..origin/main" -- "${PATHSPEC[@]}"
#
# Equality against main's HEAD false-alarms continuously, because the release workflow is
# path-filtered — a knowledge-base/-only commit never deploys, so main's HEAD is routinely
# a commit prod is CORRECT not to be serving. The range query is also empty when prod is
# AHEAD (a `workflow_dispatch` with `force_run: true` deploys whatever `github.sha` points
# at, path filter bypassed), so that whole false-positive class needs no special case.
#
# WHY `skip_deploy` DISPATCHES ALERT, AND THAT IS CORRECT. A `skip_deploy: true` dispatch
# leaves prod deliberately behind. This checker reports DRIFT_SUSTAINED for it. That is a
# TRUE positive — prod really is stale — and suppressing it would require the checker to
# keep cross-run state about operator intent, which it deliberately does not. The tracking
# issue auto-closes on the next deploy.
#
# WHY `--first-parent` IS LOAD-BEARING, NOT DECORATION. `allow_merge_commit` is true on this
# repo and main already carries merge commits. Without --first-parent, history simplification
# can resolve to a commit on a merged FEATURE BRANCH rather than to the merge commit that
# actually triggered the release — a permanent, silent disagreement with the release job's own
# `check_changed`. On today's history it is a verified no-op, which makes it free insurance.
#
# THE STALENESS CLOCK IS THE OLDEST MISSING COMMIT, NEVER THE NEWEST. A newest-commit clock
# RESETS every time another qualifying commit lands, so under a steady commit stream with a
# broken deploy it never escalates while prod rots. Anchoring to the oldest undeployed commit
# measures how long prod has actually been stale, and cannot reset.
#
# THREE VERDICTS — "we could not evaluate" must NEVER be encoded as "no drift":
#
#   CLEAN            exit 0   no alert    prod has every qualifying commit (equal or ahead)
#   DRIFT_PENDING    exit 0   no alert    behind, but within one release cycle — legitimately in flight
#   DRIFT_SUSTAINED  exit 1   ALERT       behind for longer than the pipeline's own declared ceiling
#   CHECK_ERROR      exit 2   ALERT       unreachable, malformed build_sha, or a failed range query
#
# Exit codes are DATA for the workflow to branch on; the caller captures them into
# $GITHUB_OUTPUT rather than letting a non-zero fail the step (a failed step would self-dark
# the liveness heartbeat, which is the one signal that says the monitor ran at all).

set -uo pipefail

# The DEFINITION of "a commit that should have deployed". Parity-asserted at CI time (Part B,
# B8) against `jobs.release.with.path_filter` in .github/workflows/web-platform-release.yml —
# if that filter changes and this constant does not, the checker would silently redefine
# correctness, so the suite goes red at the moment of divergence rather than at 03:00.
PATHSPEC=(apps/web-platform/ plugins/soleur/ ':(exclude)plugins/soleur/docs/' ':(exclude)plugins/soleur/test/')

# The longest LEGITIMATE commit-to-deployed latency, as the sum of the release pipeline's own
# declared ceilings on the serial critical path: await-ci 60 + migrate 30 + verify-migrations 15
# + deploy 90. A principled bound rather than a guess, and ~4x every observed run.
# (verify-doppler-secrets, 10 min, runs in parallel and is not additive.)
#
# Deliberately NOT a tick count. This repo measured GitHub Actions `schedule:` dispatch jitter
# at a median 80-134 minutes late (max 339), so "N consecutive ticks" measures an interval that
# is not the interval. A commit timestamp is immutable and readable from a single sample, so
# jitter can only DELAY detection here — it can never manufacture a false positive.
# Part B (B9) asserts this stays >= that serial sum, so a pipeline timeout INCREASE fails the
# suite: the threshold can never silently become smaller than legitimate latency.
DRIFT_SUSTAINED_THRESHOLD_MIN=195

PROD_HEALTH_URL="${PROD_HEALTH_URL:-https://app.soleur.ai/health}"

# Caller-visible outputs. classify_drift sets these; it must therefore be called DIRECTLY and
# never inside `$( )`, which would discard every one of them while still yielding a plausible
# exit code.
DRIFT_VERDICT=""
DRIFT_REASON=""
DRIFT_DETAIL=""
DRIFT_MISSING_COUNT=""

# Reads `<sha> <committer-epoch>` lines on stdin, emits the NUMERIC MINIMUM epoch.
#
# `sort -n | head -1`, not a positional `tail -1`: reverse-chronological output is git's
# DEFAULT, not a documented contract, so `--topo-order` or a future default change would
# silently invert a positional read and hand the clock the newest commit — the exact hole
# described in the header.
oldest_epoch_from_log() {
  awk '{print $2}' | sort -n | head -1
}

# classify_drift <prod_json> <curl_rc> <missing_count> <oldest_epoch> <revlist_rc> <now_epoch>
#
# PURE: no network, no git, no clock read. Every input is passed in, so the whole verdict table
# is drivable from fixtures. Sets DRIFT_VERDICT / DRIFT_REASON / DRIFT_DETAIL /
# DRIFT_MISSING_COUNT and returns the exit code the workflow branches on.
classify_drift() {
  local prod_json="${1:-}" curl_rc="${2:-}" missing_count="${3:-}"
  local oldest_epoch="${4:-}" revlist_rc="${5:-}" now_epoch="${6:-}"

  DRIFT_VERDICT=""
  DRIFT_REASON=""
  DRIFT_DETAIL=""
  DRIFT_MISSING_COUNT="$missing_count"

  # ORDER IS THE CONTRACT: an inability to evaluate OUTRANKS a drift signal. If we could not
  # read prod, we do not get to claim we know prod is stale.
  if [[ "$curl_rc" != "0" ]]; then
    DRIFT_VERDICT="CHECK_ERROR"
    DRIFT_REASON="prod_unreachable_curl_rc_${curl_rc:-unset}"
    DRIFT_DETAIL="curl exhausted its retries against ${PROD_HEALTH_URL} (rc=${curl_rc:-unset})"
    return 2
  fi

  # `jq -r .build_sha` prints the LITERAL STRING "null" for BOTH `{}` and `{"build_sha":null}`
  # (measured — both exit 0), empty for `{"build_sha":""}`, and fails outright on a non-JSON
  # body such as an HTML error page served with HTTP 200. The 40-hex gate below is the single
  # guard covering all four; an unguarded consumer would treat "null" as a SHA and hand it to
  # git, where it becomes a range-query failure at best and a wrong answer at worst.
  local sha
  sha="$(printf '%s' "$prod_json" | jq -r '.build_sha' 2>/dev/null || true)"
  if [[ "$sha" =~ ^[0-9a-f]{40}$ ]]; then
    DRIFT_DETAIL="prod build_sha ${sha}"
  else
    # ECHOING BACK UNTRUSTED INPUT: this is the ONE path where a value we did not validate is
    # quoted into an operator-visible surface. DRIFT_DETAIL reaches a GitHub issue body AND an
    # HTML email body (inside <code>...</code>), and the workflow's strip_log_injection removes
    # CONTROL characters only -- it does not escape `<`, `>` or `&`. A hostile or MITM'd /health
    # could therefore inject markup into the very alert that says it is untrustworthy. Bound the
    # length and restrict the charset here, at the source, so every downstream consumer is
    # covered rather than each having to remember.
    local sha_display
    sha_display="$(printf '%s' "$sha" | LC_ALL=C tr -cd '[:alnum:]._:/-' | cut -c1-64)"
    DRIFT_VERDICT="CHECK_ERROR"
    DRIFT_REASON="malformed_build_sha"
    DRIFT_DETAIL="/health did not yield a 40-hex build_sha (got: ${sha_display:-[empty or unparseable]})"
    return 2
  fi

  # A failed range query means the question is UNANSWERED. Reporting CLEAN here is precisely
  # the silent-failure this whole workflow exists to catch, one layer up.
  if [[ "$revlist_rc" != "0" ]]; then
    DRIFT_VERDICT="CHECK_ERROR"
    DRIFT_REASON="range_query_failed_rc_${revlist_rc:-unset}"
    DRIFT_DETAIL="git could not evaluate ${sha}..origin/main (rc=${revlist_rc:-unset}) — unknown SHA, or a shallow clone"
    return 2
  fi

  if ! [[ "$missing_count" =~ ^[0-9]+$ ]]; then
    DRIFT_VERDICT="CHECK_ERROR"
    DRIFT_REASON="unparseable_missing_count"
    DRIFT_DETAIL="missing-commit count was not a non-negative integer (got: ${missing_count:-<empty>})"
    return 2
  fi

  if [[ "$missing_count" -eq 0 ]]; then
    DRIFT_VERDICT="CLEAN"
    DRIFT_REASON="prod_has_every_qualifying_commit"
    DRIFT_DETAIL="${DRIFT_DETAIL} is missing no commit matching the release path filter"
    return 0
  fi

  if ! [[ "$oldest_epoch" =~ ^[0-9]+$ ]] || ! [[ "$now_epoch" =~ ^[0-9]+$ ]]; then
    DRIFT_VERDICT="CHECK_ERROR"
    DRIFT_REASON="unparseable_clock"
    DRIFT_DETAIL="could not read the staleness clock (oldest=${oldest_epoch:-<empty>} now=${now_epoch:-<empty>})"
    return 2
  fi

  local age_s=$(( now_epoch - oldest_epoch ))
  local threshold_s=$(( DRIFT_SUSTAINED_THRESHOLD_MIN * 60 ))

  # STRICTLY greater, so a legitimate release finishing exactly at its declared ceiling is not
  # paged. A future-dated commit (clock skew) yields a negative age and likewise cannot page.
  if [[ "$age_s" -gt "$threshold_s" ]]; then
    DRIFT_VERDICT="DRIFT_SUSTAINED"
    DRIFT_REASON="stale_beyond_threshold"
    DRIFT_DETAIL="${DRIFT_DETAIL}; ${missing_count} qualifying commit(s) undeployed, oldest is $(( age_s / 60 ))m old (threshold ${DRIFT_SUSTAINED_THRESHOLD_MIN}m)"
    return 1
  fi

  DRIFT_VERDICT="DRIFT_PENDING"
  DRIFT_REASON="release_in_flight"
  DRIFT_DETAIL="${DRIFT_DETAIL}; ${missing_count} qualifying commit(s) undeployed, oldest is $(( age_s / 60 ))m old — within the ${DRIFT_SUSTAINED_THRESHOLD_MIN}m release cycle"
  return 0
}

# I/O only. Everything it learns is handed to classify_drift, which owns every decision.
main() {
  local body="" curl_rc=1 attempt

  # Three attempts with backoff BEFORE declaring CHECK_ERROR: a single blip must not be able to
  # open an issue and send an email.
  for attempt in 1 2 3; do
    body="$(curl -fsS --max-time 15 "$PROD_HEALTH_URL" 2>/dev/null)"
    curl_rc=$?
    [[ "$curl_rc" -eq 0 ]] && break
    [[ "$attempt" -lt 3 ]] && sleep $(( attempt * 5 ))
  done

  local sha="" missing="" revlist_rc=0 missing_count=0 oldest_epoch=""

  if [[ "$curl_rc" -eq 0 ]]; then
    sha="$(printf '%s' "$body" | jq -r '.build_sha' 2>/dev/null || true)"
    if [[ "$sha" =~ ^[0-9a-f]{40}$ ]]; then
      # rc CAPTURED DIRECTLY FROM git, NEVER THROUGH A PIPE. Measured: a bad revision returns
      # rc=128 direct but rc=0 when piped (the pipe reports the LAST stage's status), and rc=0
      # with empty output is indistinguishable from CLEAN. That single character is the whole
      # difference between a working alarm and one that is permanently, silently green.
      missing="$(git log --first-parent --format='%H %ct' "${sha}..origin/main" -- "${PATHSPEC[@]}" 2>/dev/null)"
      revlist_rc=$?
      if [[ "$revlist_rc" -eq 0 ]]; then
        # `grep -c` EXITS 1 on a zero count, so the count is taken as data with `|| true`
        # rather than allowed to read as a failure.
        missing_count="$(printf '%s' "$missing" | grep -c . || true)"
        if [[ "$missing_count" -gt 0 ]]; then
          oldest_epoch="$(printf '%s\n' "$missing" | oldest_epoch_from_log)"
        fi
      fi
    fi
  fi

  classify_drift "$body" "$curl_rc" "$missing_count" "$oldest_epoch" "$revlist_rc" "$(date -u +%s)"
  local verdict_rc=$?

  echo "DRIFT_VERDICT=${DRIFT_VERDICT}"
  echo "DRIFT_REASON=${DRIFT_REASON}"
  echo "DRIFT_DETAIL=${DRIFT_DETAIL}"
  echo "DRIFT_MISSING_COUNT=${DRIFT_MISSING_COUNT}"

  return "$verdict_rc"
}

# Sourcing must expose the functions and constants WITHOUT running main().
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
