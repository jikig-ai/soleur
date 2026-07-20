#!/usr/bin/env bash
# Tests for scripts/cron-artifact-age.sh (#6737, ADR-126 follow-up).
#
# BOTH ARMS ARE MANDATORY. A staleness detector that only ever reports STALE is
# indistinguishable from `echo STALE`, and one that only ever reports PASS is
# indistinguishable from `true`. Every case below therefore has a counterpart
# that must reach the OPPOSITE verdict through the same code path.
#
# FIXTURES ARE SYNTHESIZED, NEVER COPIED (`cq-test-fixtures-synthesized-only`).
# The synthetic repo contains two invented producers — `cron-synthetic-alpha`
# and `cron-synthetic-beta` — whose commit-message anchors appear nowhere in the
# real handler table. Copying a real subject would make these cases go vacuous
# the moment the real cron recovers (or is renamed), which is the precise way
# this repo's recent mutation batteries went hollow.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/cron-artifact-age.sh"

PASS=0
FAIL=0
assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    echo "  PASS: $desc"; PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc"; echo "    expected: $expected"; echo "    actual:   $actual"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== cron-artifact-age.sh tests ==="

# Snapshot the REAL producer table before section 4 overrides
# `cron_producer_rows`. Re-sourcing the script later is not an option: its
# `readonly` threshold constants abort a second source, and a test that silently
# tolerated that would be asserting against the override rather than the
# shipped table.
REAL_ROWS="$(cron_producer_rows)"

# --------------------------------------------------------------------------
# Synthesized git fixture. Two invented producers on a synthetic default
# branch, backdated with GIT_{AUTHOR,COMMITTER}_DATE so the ages are exact
# rather than dependent on wall-clock at test time.
# --------------------------------------------------------------------------
FIXTURE_ROOT="$(mktemp -d)"
cleanup() { rm -rf "$FIXTURE_ROOT"; }
trap cleanup EXIT

REPO="$FIXTURE_ROOT/synthetic-repo"
mkdir -p "$REPO"
git -C "$REPO" init -q -b synthetic-main
git -C "$REPO" config user.email "fixture@invalid.test"
git -C "$REPO" config user.name "Fixture Bot"

# A fixed "now" so ages never drift with the calendar.
FIXTURE_NOW_EPOCH=$(date -u -d '2026-07-20T00:00:00Z' +%s)

synth_commit() {
  local days_ago="$1" message="$2" iso
  iso="$(date -u -d "@$((FIXTURE_NOW_EPOCH - days_ago * 86400))" +'%Y-%m-%dT%H:%M:%S+0000')"
  echo "$message $days_ago" >>"$REPO/synthetic-artifact.md"
  git -C "$REPO" add -A
  GIT_AUTHOR_DATE="$iso" GIT_COMMITTER_DATE="$iso" \
    git -C "$REPO" commit -q -m "$message"
}

# `cron-synthetic-beta` landed 2 days ago  -> FRESH against a 15d threshold.
# `cron-synthetic-alpha` landed 40 days ago -> STALE against the same threshold.
# Beta's commit is created LAST so that HEAD is the fresh one; this also proves
# the anchor grep selects by MESSAGE and not merely by recency.
synth_commit 40 "docs(synthetic): alpha widget rollup"
synth_commit 2 "docs(synthetic): beta widget rollup"

SYNTH_ALPHA='^docs\(synthetic\): alpha widget rollup'
SYNTH_BETA='^docs\(synthetic\): beta widget rollup'
SYNTH_ABSENT='^docs\(synthetic\): gamma widget rollup'

# --------------------------------------------------------------------------
# 1. age_days — the git-history read, both arms.
# --------------------------------------------------------------------------
echo "--- age_days (synthesized history) ---"

assert_eq "stale synthetic producer reads 40 days" "40" \
  "$(age_days "$REPO" synthetic-main "$SYNTH_ALPHA" "$FIXTURE_NOW_EPOCH")"

# POSITIVE CONTROL for the case above: the same call shape against the fresh
# anchor must return a DIFFERENT number. Without this, a bug returning a
# constant 40 would satisfy the assertion above.
assert_eq "fresh synthetic producer reads 2 days" "2" \
  "$(age_days "$REPO" synthetic-main "$SYNTH_BETA" "$FIXTURE_NOW_EPOCH")"

# A producer that never landed is NEVER, not 0 and not an error.
assert_eq "never-landed synthetic producer reads NEVER" "NEVER" \
  "$(age_days "$REPO" synthetic-main "$SYNTH_ABSENT" "$FIXTURE_NOW_EPOCH")"

# --------------------------------------------------------------------------
# 2. classify_age — both arms across the threshold boundary.
# --------------------------------------------------------------------------
echo "--- classify_age (boundary) ---"

assert_eq "age 40 over threshold 15 -> STALE" "STALE" "$(classify_age 40 15)"
assert_eq "age 2 under threshold 15 -> PASS" "PASS" "$(classify_age 2 15)"
# Boundary is inclusive-PASS: exactly at threshold is still healthy, one past is not.
assert_eq "age 15 exactly at threshold 15 -> PASS" "PASS" "$(classify_age 15 15)"
assert_eq "age 16 one past threshold 15 -> STALE" "STALE" "$(classify_age 16 15)"
# NEVER must fail closed. A detector that PASSes an unobserved artifact is the
# fail-open ADR-126 forbids ("livenessOk is initialised false").
assert_eq "NEVER fails closed -> STALE" "STALE" "$(classify_age NEVER 999)"

# --------------------------------------------------------------------------
# 3. threshold_days — cadence-derived, class-differentiated, and capped.
# --------------------------------------------------------------------------
echo "--- threshold_days (cadence derivation) ---"

# Weekly Class A: 7 * 2 + 1.
assert_eq "weekly Class A -> 15d" "15" "$(threshold_days 7 A)"
# Weekly Class B gets exactly one extra interval: 7 * 3 + 1.
assert_eq "weekly Class B -> 22d" "22" "$(threshold_days 7 B)"
# Daily Class A: 1 * 2 + 1. Proves the threshold TRACKS cadence rather than
# being a constant that merely happens to fit the weekly rows above.
assert_eq "daily Class A -> 3d" "3" "$(threshold_days 1 A)"
# Monthly Class B would be 31 * 3 + 1 = 94; the absolute ceiling clamps it.
assert_eq "monthly Class B clamps to the 75d ceiling" "75" "$(threshold_days 31 B)"
# The class distinction must be REAL: same interval, different verdict window.
assert_eq "class A and B differ at the same interval" "differ" \
  "$([[ "$(threshold_days 7 A)" != "$(threshold_days 7 B)" ]] && echo differ || echo same)"

# --------------------------------------------------------------------------
# 4. End-to-end report_all against the synthesized table — BOTH ARMS.
#    cron_producer_rows is overridden so no real subject is consulted.
# --------------------------------------------------------------------------
echo "--- report_all (synthesized producer table, both arms) ---"

cron_producer_rows() {
  cat <<ROWS
cron-synthetic-alpha|0 7 * * 1|7|A|$SYNTH_ALPHA
cron-synthetic-beta|0 7 * * 1|7|A|$SYNTH_BETA
ROWS
}

REPO_DIR="$REPO" DEFAULT_REF=synthetic-main NOW_EPOCH="$FIXTURE_NOW_EPOCH" \
  report_all >"$FIXTURE_ROOT/report.txt" 2>&1 && report_rc=0 || report_rc=$?
REPORT="$(cat "$FIXTURE_ROOT/report.txt")"

# Herestring, NOT `printf ... | grep -q`. Under `set -o pipefail` an early grep
# match closes the pipe, the producer takes SIGPIPE (141), and the pipeline
# fails EVEN THOUGH the pattern matched — a gate that reports failure on
# success. The herestring has no producer process to kill.
assert_eq "report flags the synthesized STALE producer" "1" \
  "$(grep -cE '^cron-synthetic-alpha .* STALE$' <<<"$REPORT" || true)"
assert_eq "report passes the synthesized FRESH producer" "1" \
  "$(grep -cE '^cron-synthetic-beta .* PASS$' <<<"$REPORT" || true)"

# The two arms must not collapse into each other.
assert_eq "the STALE producer is not also reported PASS" "0" \
  "$(grep -cE '^cron-synthetic-alpha .* PASS$' <<<"$REPORT" || true)"
assert_eq "the FRESH producer is not also reported STALE" "0" \
  "$(grep -cE '^cron-synthetic-beta .* STALE$' <<<"$REPORT" || true)"

# Cadence must be printed — the audit's whole cadence discipline depends on a
# reader never seeing an age without the schedule that gives it meaning.
assert_eq "report prints each producer's cadence" "2" \
  "$(grep -cE '^cron-synthetic-(alpha|beta) +0 7 \* \* 1 ' <<<"$REPORT" || true)"

# Exit status is load-bearing: the workflow gates on it.
assert_eq "report_all exits 1 when any producer is STALE" "1" "$report_rc"

# ALL-FRESH ARM: the same code path must exit 0 and print no STALE verdict.
cron_producer_rows() {
  cat <<ROWS
cron-synthetic-beta|0 7 * * 1|7|A|$SYNTH_BETA
ROWS
}
REPO_DIR="$REPO" DEFAULT_REF=synthetic-main NOW_EPOCH="$FIXTURE_NOW_EPOCH" \
  report_all >"$FIXTURE_ROOT/report-fresh.txt" 2>&1 && fresh_rc=0 || fresh_rc=$?
REPORT_FRESH="$(cat "$FIXTURE_ROOT/report-fresh.txt")"

assert_eq "all-fresh report_all exits 0" "0" "$fresh_rc"
assert_eq "all-fresh report contains no STALE verdict" "0" \
  "$(grep -cE ' STALE$' <<<"$REPORT_FRESH" || true)"
assert_eq "all-fresh report states the all-within-threshold result" "1" \
  "$(grep -cE '^RESULT: all producers within threshold' <<<"$REPORT_FRESH" || true)"

# --------------------------------------------------------------------------
# 5. The real producer table is intact — 9 producers, 9 anchors.
#    Asserted on SYNTAX A COMMENT CANNOT PRODUCE (`cq-assert-anchor-not-bare-token`):
#    the five-field pipe-delimited row shape, not the bare cron names, which also
#    appear in this file's prose and in the script's own header comment.
# --------------------------------------------------------------------------
echo "--- real producer table shape ---"

assert_eq "real table enumerates 9 producers" "9" \
  "$(grep -cE '^cron-[a-z-]+\|[0-9*, /-]+\|[0-9]+\|[AB]\|' <<<"$REAL_ROWS" || true)"

# The 9th site: cron-roadmap-review is OUTSIDE MIGRATED_PROMPT and outside every
# handler-local remedy, which is exactly why it must be in this table.
assert_eq "the 9th site (cron-roadmap-review) carries a full row" "1" \
  "$(grep -cE '^cron-roadmap-review\|0 9 \* \* 1\|7\|B\|' <<<"$REAL_ROWS" || true)"

# Both classes are represented; a table that had collapsed to one class would
# make the Class A/B threshold split dead code.
assert_eq "real table contains Class A rows" "4" \
  "$(grep -cE '^cron-[a-z-]+\|.*\|A\|' <<<"$REAL_ROWS" || true)"
assert_eq "real table contains Class B rows" "5" \
  "$(grep -cE '^cron-[a-z-]+\|.*\|B\|' <<<"$REAL_ROWS" || true)"

echo
echo "Total: $((PASS + FAIL))  Pass: $PASS  Fail: $FAIL"
[[ $FAIL -eq 0 ]] || exit 1
