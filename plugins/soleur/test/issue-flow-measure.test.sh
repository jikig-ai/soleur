#!/usr/bin/env bash
# Test: scripts/issue-flow-measure.sh
#
# First suite for the weekly measurement script. Fixture seam is at the I/O
# boundary ONLY: a stub `gh` on PATH that answers `gh api search/issues?q=…`
# with a canned `{"total_count": N}` keyed on substrings of the query URL, and
# honours `--jq '.total_count'` the way the real binary does. Nothing above the
# counting logic is stubbed, so the query strings, the label OR-join, the
# per-week arithmetic and the verdict are all exercised for real.
#
# What this pins (ADR-216 addendum, "the fourth population"):
#   1c. cron run-reports — the second irreducible floor, INSIDE the gate's reach
#       but not reducible by it. Counted by `author:app/soleur-ai` + the
#       OR-joined `scheduled-*` labels of RUN_REPORT_CRONS.
#   1d. filings that took exit 1 (`meta/machinery`), minus the `keep-open`
#       kill-switch so the standing measurement issue never counts itself.
#   PARITY: the script's RUN_REPORT_LABELS array and the substrate's
#       RUN_REPORT_CRONS (`_cron-run-reports.ts`) name the SAME label set, in
#       both directions. Two pins on one fact, kept in lockstep by this row.
#
# Foot-guns deliberately avoided (see work/SKILL.md):
#   - no `producer | grep -q` (SIGPIPE/pipefail early-match false-negative)
#   - stub `gh` records "$*" so the 1d query SHAPE is assertable, not inferred
#   - the happy path carries a positive control (script rc + VERDICT line)

set -uo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
MEASURE="$REPO_ROOT/scripts/issue-flow-measure.sh"
RUN_REPORTS_TS="$REPO_ROOT/apps/web-platform/server/inngest/functions/_cron-run-reports.ts"

fails=0
passes=0
# `cases` is the INDEPENDENT counter, incremented at every assertion CALL SITE
# and never inside pass()/fail(), so a neutered verdict helper cannot keep the
# count moving while losing the verdict. Never increment inside `$( )`.
cases=0
pass() { printf '  ok   %s\n' "$1"; passes=$((passes + 1)); }
fail() { printf '  FAIL %s\n' "$1"; fails=$((fails + 1)); }

# ---------------------------------------------------------------------------
# INSTRUMENT SELF-TEST. Drive BOTH verdict helpers once and require each to
# move its OWN counter before any real assertion runs. The conservation check
# at the bottom is direction-blind (passes+fails vs cases), so a fail() that
# bumps `passes` would satisfy it and report ALL PASS. Reported with printf +
# exit 1 DIRECTLY, never through fail(): a check enforced through the suspect
# cannot witness the suspect (ADR-193).
# ---------------------------------------------------------------------------
_p0=$passes; _f0=$fails
pass "instrument self-test: pass() records a pass" >/dev/null
fail "instrument self-test: fail() records a failure (EXPECTED, not a real failure)" >/dev/null
if [[ $((passes - _p0)) -ne 1 || $((fails - _f0)) -ne 1 ]]; then
  printf '\n[FATAL] verdict helpers are neutered: pass() moved passes by %d (want 1), fail() moved fails by %d (want 1).\n' \
    "$((passes - _p0))" "$((fails - _f0))" >&2
  printf '  Every verdict this suite records is therefore unreliable; refusing to report a result.\n' >&2
  exit 1
fi
passes=$_p0; fails=$_f0

if [[ ! -r "$MEASURE" ]]; then
  printf 'FAIL: measurement script missing: %s\n' "$MEASURE" >&2
  exit 1
fi

WORK="$(mktemp -d -t issue-flow-measure.XXXXXXXX)"
trap 'rm -rf "$WORK"' EXIT

# ---------------------------------------------------------------------------
# Stub gh. Dispatches on substrings of the query URL; every invocation is
# written to $GH_CALLS so the query SHAPE (not just the count) is assertable.
# Order matters: the more specific queries (1b, 1c, 1d) share the
# `is:issue+created:>=` prefix with the headline, so they are matched FIRST.
# An unhandled query exits 64 so a new line in the script cannot silently read
# as an empty count.
# ---------------------------------------------------------------------------
mkdir -p "$WORK/bin"
cat > "$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
ARGV="$*"
printf '%s\n' "$ARGV" >> "$GH_CALLS"
case "$ARGV" in
  "auth status"*) exit 0 ;;
esac
emit() { # $1 = canned total_count; honours --jq '.total_count' like the real gh
  local json; json="$(printf '{"total_count": %s}' "$1")"
  case "$ARGV" in
    *"--jq .total_count"*|*"--jq '.total_count'"*) printf '%s\n' "$json" | jq -r '.total_count' ;;
    *) printf '%s\n' "$json" ;;
  esac
}
case "$*" in
  *"is:issue+created:>="*"+author:app/github-actions"*)           emit "${STUB_1B:-11}" ;;
  *"is:issue+created:>="*"+author:app/soleur-ai+label:%22scheduled-"*) emit "${STUB_1C:-7}" ;;
  *"is:issue+created:>="*"+label:%22meta/machinery%22+-label:keep-open"*) emit "${STUB_1D:-5}" ;;
  *"is:issue+is:closed+label:%22meta/machinery%22"*)               emit 2 ;;
  *"in:comments"*)                                                 emit 1 ;;
  *"is:pr+is:merged"*)                                             emit 0 ;;
  *"is:issue+is:open"*)                                            emit 1400 ;;
  *"is:issue+created:"*".."*)                                      emit 80 ;;
  *"is:issue+created:>="*)                                         emit 100 ;;
  *) echo "stub gh: unhandled argv: $*" >&2; exit 64 ;;
esac
STUB
chmod +x "$WORK/bin/gh"

export PATH="$WORK/bin:$PATH"
export GH_CALLS="$WORK/gh-calls"
export GH_TOKEN="stub-token-never-used"
export WEEKS=4

# Run from a scratch CWD so the script's relative `.claude/.rule-incidents.jsonl`
# read never touches the operator's real hook-local log.
OUT="$WORK/out.txt"
( cd "$WORK" && bash "$MEASURE" ) > "$OUT" 2> "$WORK/err.txt"
RC=$?

# ---------------------------------------------------------------------------
# Positive control: the script runs to completion under the stub and prints
# its verdict. Every assertion below is vacuous if this one is not true.
# ---------------------------------------------------------------------------
cases=$((cases + 1))
if [[ "$RC" -eq 0 ]]; then pass "positive control: script exits 0 under the stub gh"
else fail "positive control: script exited $RC (stderr: $(head -c 400 "$WORK/err.txt"))"; fi

cases=$((cases + 1))
if grep -qE '^VERDICT: filing rate NOT below baseline \(25 >= 20\)$' "$OUT"; then
  pass "VERDICT line is untouched in shape and arithmetic (100/4 vs 80/4)"
else fail "VERDICT line missing or reshaped: $(grep -E '^VERDICT' "$OUT" || echo '<none>')"; fi

# (c) the headline is UNCHANGED in shape — a pure filing count, no run-report
# or machinery term subtracted from it.
cases=$((cases + 1))
if grep -qE '^1\. filed=100 filed_per_week=25 baseline_per_week=20 \(baseline derived over the same 4w window ending 2026-09-10\)$' "$OUT"; then
  pass "line 1 headline is unchanged in shape (pure filing count, stubbed 100)"
else fail "line 1 headline changed shape: $(grep -E '^1\. ' "$OUT" || echo '<none>')"; fi

cases=$((cases + 1))
if grep -qE '^1b\. of which workflow-authored \(OUTSIDE the gate.s reach\)=11 ' "$OUT"; then
  pass "line 1b still prints with the stubbed workflow-authored count"
else fail "line 1b missing or reshaped: $(grep -E '^1b\. ' "$OUT" || echo '<none>')"; fi

# (a) 1c prints with the stubbed count and the prescribed wording.
cases=$((cases + 1))
if grep -qE '^1c\. of which cron run-reports \(RUN_REPORT_CRONS labels\)=7 ' "$OUT"; then
  pass "line 1c prints the stubbed run-report count (7)"
else fail "line 1c missing or wrong: $(grep -E '^1c\. ' "$OUT" || echo '<none>')"; fi

cases=$((cases + 1))
if grep -qE '^1c\. .*INSIDE the gate.s reach but not reducible by it' "$OUT"; then
  pass "line 1c names the floor as INSIDE the gate's reach but not reducible by it"
else fail "line 1c does not carry the second-floor wording"; fi

# (b) 1d prints with the stubbed count.
cases=$((cases + 1))
if grep -qE '^1d\. of which took exit 1 \(meta/machinery\)=5$' "$OUT"; then
  pass "line 1d prints the stubbed exit-1 count (5)"
else fail "line 1d missing or wrong: $(grep -E '^1d\. ' "$OUT" || echo '<none>')"; fi

# Ordering: 1b, 1c, 1d appear in sequence, before line 2.
cases=$((cases + 1))
_order="$(grep -oE '^(1b|1c|1d|2)\.' "$OUT" | tr -d '.' | paste -sd, -)"
if [[ "$_order" == "1b,1c,1d,2" ]]; then pass "lines 1b, 1c, 1d precede line 2 in that order"
else fail "line ordering is '$_order', want '1b,1c,1d,2'"; fi

# (d) the 1d query passed to gh carries the keep-open exclusion — asserted on
# the RECORDED argv, not inferred from the count, so a query that dropped the
# token while the stub still matched cannot pass here.
cases=$((cases + 1))
if grep -qE 'search/issues\?q=repo:[^ ]*\+is:issue\+created:>=[0-9-]+\+label:%22meta/machinery%22\+-label:keep-open' "$GH_CALLS"; then
  pass "1d query carries -label:keep-open (the standing issue never counts itself)"
else fail "1d query lacks -label:keep-open: $(grep -F 'meta/machinery' "$GH_CALLS" | head -3)"; fi

# Negative shape control on 1d: it must NOT carry an author filter — exit 1 is
# taken by interactive filers AND crons, and the line counts both.
cases=$((cases + 1))
_q1d="$(grep -E 'meta/machinery%22\+-label:keep-open' "$GH_CALLS" | head -1)"
if [[ -z "$_q1d" ]]; then
  fail "1d query is population-wide: no 1d query was sent at all (control cannot pass vacuously)"
elif [[ "$_q1d" == *"author:"* ]]; then
  fail "1d query carries an author filter — exit 1 is population-wide"
else pass "1d query is population-wide (no author filter)"; fi

# 1c query shape: bot-authored, OR-joined labels (comma-joined `label:` is OR,
# the same convention as buildSearchQuery).
cases=$((cases + 1))
_q1c="$(grep -E 'author:app/soleur-ai\+label:%22scheduled-' "$GH_CALLS" | head -1)"
if [[ -n "$_q1c" && "$_q1c" == *"is:issue+created:>="* ]]; then
  pass "1c query is bot-authored (author:app/soleur-ai) and window-bound"
else fail "1c query shape wrong: ${_q1c:-<none>}"; fi

cases=$((cases + 1))
_q1c_labels="$(printf '%s' "$_q1c" | grep -oE 'label:[^ ]+' | head -1 | sed 's/^label://' | tr ',' '\n' | sed 's/%22//g' | sort -u)"
_q1c_n="$(printf '%s\n' "$_q1c_labels" | grep -c '^scheduled-' || true)"
if [[ "$_q1c_n" -ge 2 ]] && ! printf '%s\n' "$_q1c_labels" | grep -qvE '^scheduled-[a-z-]+$'; then
  pass "1c query OR-joins $_q1c_n scheduled-* labels and nothing else"
else fail "1c query label list malformed: $(printf '%s' "$_q1c_labels" | paste -sd, -)"; fi

# ---------------------------------------------------------------------------
# (e) PARITY. The script's RUN_REPORT_LABELS array must name exactly the label
# set RUN_REPORT_CRONS names in _cron-run-reports.ts, in BOTH directions. The
# TS file is read for `label: "scheduled-…"` strings. If the TS file is absent
# this row FAILS LOUDLY — an absent producer is not parity, it is one pin with
# nothing to be in lockstep with.
# ---------------------------------------------------------------------------
_script_labels="$(sed -n '/^RUN_REPORT_LABELS=(/,/^)/p' "$MEASURE" | grep -oE 'scheduled-[a-z-]+' | sort -u)"
cases=$((cases + 1))
if [[ -n "$_script_labels" ]]; then
  pass "script declares a RUN_REPORT_LABELS array ($(printf '%s\n' "$_script_labels" | wc -l) labels)"
else fail "script has no RUN_REPORT_LABELS=( … ) array"; fi

cases=$((cases + 1))
if grep -qE '^# Mirrors RUN_REPORT_CRONS in apps/web-platform/server/inngest/functions/_cron-run-reports\.ts' "$MEASURE"; then
  pass "array carries the parity comment pointing at _cron-run-reports.ts"
else fail "array lacks the '# Mirrors RUN_REPORT_CRONS in …' comment"; fi

cases=$((cases + 1))
if [[ ! -r "$RUN_REPORTS_TS" ]]; then
  fail "PARITY: $RUN_REPORTS_TS is absent — the script's label array has no producer to mirror"
else
  # LIVE rows only: the line must START with the row literal (`{ fn:`), so a
  # commented-out row (`// { fn: …`) is not a member, and the label is taken
  # from the `label:` field whatever its prefix (a row whose label lacks the
  # `scheduled-` prefix is a parity FAILURE, not an invisible member).
  _ts_labels="$(grep -E '^[[:space:]]*\{ fn:' "$RUN_REPORTS_TS" | grep -oE 'label: *"[^"]+"' | sed -E 's/label: *"([^"]+)"/\1/' | sort -u)"
  if [[ -z "$_ts_labels" ]]; then
    fail "PARITY: no 'label: \"scheduled-…\"' strings found in $RUN_REPORTS_TS"
  elif [[ "$_script_labels" == "$_ts_labels" ]]; then
    pass "PARITY: RUN_REPORT_LABELS ≡ RUN_REPORT_CRONS labels ($(printf '%s\n' "$_ts_labels" | wc -l) labels, both directions)"
  else
    fail "PARITY: label sets differ — only-in-script: [$(comm -23 <(printf '%s\n' "$_script_labels") <(printf '%s\n' "$_ts_labels") | paste -sd, -)] only-in-ts: [$(comm -13 <(printf '%s\n' "$_script_labels") <(printf '%s\n' "$_ts_labels") | paste -sd, -)]"
  fi
fi

# The query the script actually SENT must carry every array label — the array
# is not decorative.
cases=$((cases + 1))
_missing=""
while IFS= read -r _l; do
  [[ -n "$_l" ]] || continue
  printf '%s\n' "$_q1c_labels" | grep -qxF "$_l" || _missing+="${_missing:+,}$_l"
done <<<"$_script_labels"
if [[ -n "$_script_labels" && -z "$_missing" ]]; then
  pass "every RUN_REPORT_LABELS entry reaches the 1c query"
else fail "array labels missing from the 1c query: ${_missing:-<array empty>}"; fi

# ---------------------------------------------------------------------------
# CONSERVATION: passes+fails must equal cases. Reported DIRECTLY (printf +
# exit 1), never through fail().
# ---------------------------------------------------------------------------
if [[ $((passes + fails)) -ne "$cases" ]]; then
  printf '\n[FATAL] accounting: passes+fails (%d) != cases (%d).\n' \
    "$((passes + fails))" "$cases" >&2
  printf 'issue-flow-measure.test.sh: %d FAILED (%d passed, %d cases)\n' "$fails" "$passes" "$cases"
  exit 1
fi

# ---------------------------------------------------------------------------
# ANTI-VACUITY FLOOR. Set AT the running count, never below it. Reads `cases`,
# not `passes`, so a discarded verdict is named as an accounting fault above
# rather than as "too few assertions" here.
# ---------------------------------------------------------------------------
MIN_ASSERTIONS=16
if [[ "$cases" -lt "$MIN_ASSERTIONS" ]]; then
  printf '\n[FATAL] anti-vacuity floor: only %d assertion(s) ran, expected >= %d.\n' \
    "$cases" "$MIN_ASSERTIONS" >&2
  printf 'issue-flow-measure.test.sh: %d FAILED (%d passed, %d cases)\n' "$fails" "$passes" "$cases"
  exit 1
fi

if [[ "$fails" -eq 0 ]]; then
  printf 'issue-flow-measure.test.sh: ALL PASS (%d assertions)\n' "$cases"
  exit 0
fi
printf 'issue-flow-measure.test.sh: %d FAILED (%d passed)\n' "$fails" "$passes"
exit 1
