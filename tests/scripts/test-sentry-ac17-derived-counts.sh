#!/usr/bin/env bash
# AC17 in apply-sentry-infra.yml — the step that decides whether a failed Sentry
# apply was PARTIAL (#7650 Phase 2, #7866).
#
# WHY THIS EXISTS AS A TEST RATHER THAN A READING. Before #7866 nothing in the
# repo pinned this step: reverting its expectations to the literals `27`/`2`
# left every suite green, and the only thing that ever caught the wrong `2` was
# a live apply on `main` reding three times over two days.
#
# The step's shell is EXTRACTED FROM THE SHIPPED YAML and executed, never
# restated here — the same contract as test-sentry-alert-drift-workflow.sh. A
# restatement passes forever after the workflow changes underneath it. The
# anchor is `id: ac17`, NOT the step name: `cq-assert-anchor-not-bare-token`
# forbids anchoring on a token the step's own comment block also contains, and
# that block necessarily mentions `sentry_alert`, `27` and `2`.
#
# Every row runs the extracted bytes under `bash -e`, because Actions runs a
# bare `run:` as `bash -e {0}`. Running under plain `bash` would hide the entire
# silent-abort class these rows exist to pin: measured on #7866, four separate
# `VAR=$(grep ...)` assignments killed the step with NO annotation whenever
# their grep matched zero lines, including on a real partial adoption.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WF="$REPO_ROOT/.github/workflows/apply-sentry-infra.yml"
pass=0; fail=0
EXPECTED_TESTS=10
# APPEND-ONLY verdict ledger. The final gate reads THIS, not the counters.
# Measured on #7866: with the gate reading `pass`/`fail`, rewriting `_report`'s
# else-branch to `pass=$((pass + 1))` reported `8 passed, 0 failed` and exit 0
# with a real regression injected — a one-token silencing of the whole suite.
# The push below happens BEFORE any branching, so muting a verdict now requires
# deleting evidence rather than moving a number, and the conservation check at
# the bottom catches a single-site tamper of either the ledger or the counters.
VERDICTS=()

TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT
[[ -f "$WF" ]] || { echo "ERROR: $WF does not exist" >&2; exit 1; }

_report() {
  local label="$1" status="$2" detail="${3:-}"
  VERDICTS+=("$status")   # before the branch, deliberately — see the note above
  if [[ "$status" == "ok" ]]; then pass=$((pass + 1)); echo "[ok] $label"
  else fail=$((fail + 1)); echo "[FAIL] $label $detail" >&2; fi
}

# ── extract the step, anchored on id: ac17 ──────────────────────────────────
STEP="$TMPD/ac17.sh"
if ! python3 - "$WF" "$STEP" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
hits = [s for s in (d["jobs"]["apply"]["steps"] or []) if s.get("id") == "ac17"]
# UNIQUENESS is load-bearing: a first-match extractor is defeated by a decoy
# step, and the suite would then certify bytes nobody ships.
if len(hits) != 1:
    sys.exit(f"expected exactly 1 step with id: ac17, found {len(hits)}")
run = hits[0].get("run") or ""
if "terraform state list" not in run:
    sys.exit("extracted step does not contain `terraform state list` — the anchor moved")
open(sys.argv[2], "w").write(run)
PY
then
  echo "ERROR: could not extract the AC17 step from $WF — the anchor (id: ac17) moved." >&2
  exit 1
fi
# Non-vacuity on the extraction itself: an empty slice would make every row
# below pass by doing nothing.
[[ -s "$STEP" ]] || { echo "ERROR: extracted AC17 step is empty" >&2; exit 1; }

mkdir -p "$TMPD/stub"
cat > "$TMPD/stub/terraform" <<'STUB'
#!/usr/bin/env bash
if [[ "${1:-} ${2:-}" == "state list" ]]; then
  [[ "${TF_STATE_RC:-0}" -ne 0 ]] && exit "$TF_STATE_RC"
  printf '%s\n' ${TF_STATE_ADDRS:-}
  exit 0
fi
exit 9
STUB
chmod +x "$TMPD/stub/terraform"

# $1=label $2=want_rc $3=state addrs $4=.tf content $5=grep -E pattern the output MUST carry
_row() {
  local label="$1" want_rc="$2" addrs="$3" tf="$4" want_out="${5:-}"
  local dir="$TMPD/case"; rm -rf "$dir"; mkdir -p "$dir"
  printf '%s\n' "$tf" > "$dir/alerts.tf"
  local out rc
  out=$(cd "$dir" && GITHUB_STEP_SUMMARY="$TMPD/summary.md" \
        TF_STATE_ADDRS="$addrs" TF_STATE_RC="${TF_STATE_RC:-0}" \
        PATH="$TMPD/stub:$PATH" bash -e "$STEP" 2>&1); rc=$?
  if [[ "$rc" -ne "$want_rc" ]]; then
    _report "$label" fail "rc=$rc want $want_rc; out=${out:-<EMPTY>}"; return
  fi
  if [[ -n "$want_out" ]] && ! grep -qE "$want_out" <<<"$out"; then
    _report "$label" fail "rc ok but output lacks /$want_out/; out=${out:-<EMPTY — the silent-abort class}"; return
  fi
  _report "$label" ok
}

TF3='resource "sentry_alert" "a" {}
resource "sentry_alert" "b" {}
resource "sentry_issue_alert" "c" {}'

# R1 — the healthy path.
_row "R1 state matches the declared .tf -> green, and reports both sides" 0 \
  "sentry_alert.a sentry_alert.b sentry_issue_alert.c" "$TF3" \
  'AC17: state holds 2 sentry_alert and 1 sentry_issue_alert'

# R2 — a genuine partial adoption MUST red WITH an annotation naming the address.
# Before #7866 this exited 1 having printed nothing at all.
_row "R2 partial adoption -> red, and NAMES the missing address" 1 \
  "sentry_alert.a sentry_issue_alert.c" "$TF3" \
  'AC17 FAILED.*ABSENT FROM STATE: sentry_alert\.b'

# R3 — THE row that pins the derivation. A hardcoded `2` for sentry_issue_alert
# reds here; deriving from the .tf passes. Revert the derivation and this fails.
_row "R3 three issue-alerts declared and in state -> green (a literal 2 reds)" 0 \
  "sentry_alert.a sentry_issue_alert.c sentry_issue_alert.d sentry_issue_alert.e" \
  'resource "sentry_alert" "a" {}
resource "sentry_issue_alert" "c" {}
resource "sentry_issue_alert" "d" {}
resource "sentry_issue_alert" "e" {}' \
  'the \.tf declares 1 and 3'

# R4 — the #7650 END STATE: zero surviving sentry_issue_alert is correct, and
# must stay GREEN. This is why exp_issue deliberately carries no floor.
_row "R4 zero sentry_issue_alert declared and zero in state -> green" 0 \
  "sentry_alert.a" 'resource "sentry_alert" "a" {}' \
  'AC17: state holds 1 sentry_alert and 0 sentry_issue_alert'

# R5 — a broken anchor must reach the non-vacuity floor and SAY SO. Before
# #7866 the assignment died first and the floor was unreachable dead code.
_row "R5 broken anchor -> red, and the floor's message actually prints" 1 \
  "sentry_alert.a" 'resource "sentry_alertX" "a" {}' \
  'derived 0 sentry_alert resources from the \.tf'

# R6 — the orphan. Counts are EQUAL, so a count comparison passes; the step is
# named "no orphan" and the filer promises it, so it must red and name both sides.
_row "R6 one-for-one swap with equal counts -> red, names orphan AND missing" 1 \
  "sentry_alert.zzz_orphan sentry_alert.b sentry_issue_alert.c" "$TF3" \
  'ABSENT FROM STATE: sentry_alert\.a.*orphan\): sentry_alert\.zzz_orphan'

# R7 — total adoption failure: zero sentry_alert in state. Pre-#7866 this died
# at the n_alert assignment with no annotation.
_row "R7 zero sentry_alert in state -> red WITH the failure annotation" 1 \
  "sentry_issue_alert.c" "$TF3" \
  'AC17 FAILED.*ABSENT FROM STATE:'

# R8 — an unreadable state read is UNANSWERED, not clean.
TF_STATE_RC=1 _row "R8 terraform state list fails -> red, question UNANSWERED" 1 \
  "" "$TF3" 'could not read terraform state'
TF_STATE_RC=0

# R9 — the step must report ONCE. A partial edit that leaves a superseded
# comparison in place still passes every behavioural row above (the green cases
# satisfy both copies, the red cases exit at the first), so nothing else here
# can see it — measured on this very change, which shipped a duplicated summary
# table and a stale count-comparison past a green 8-row run.
_dup_check() {
  local body summaries verdicts
  body=$(cat "$STEP")
  summaries=$( { grep -c 'GITHUB_STEP_SUMMARY' <<<"$body" || true; } )
  verdicts=$(  { grep -c 'AC17 FAILED'          <<<"$body" || true; } )
  if [[ "$summaries" -eq 1 && "$verdicts" -eq 1 ]]; then
    _report "R9 the step writes ONE summary table and emits ONE verdict" ok
  else
    _report "R9 the step writes ONE summary table and emits ONE verdict" fail \
      "GITHUB_STEP_SUMMARY x$summaries, 'AC17 FAILED' x$verdicts — a superseded copy survived an edit"
  fi
}
_dup_check

# R10 — AC17 exits 1 on a disagreement, so any post-apply probe left on an
# implicit success() is SKIPPED exactly when its answer matters. Measured on run
# 34149741385: AC17 red, `sentry_alert live fidelity (AC19/AC20)` skipped, so the
# probe covering all 27 rules never ran on the apply whose state was in question.
# `always()` does NOT make a step's own failure non-poisoning downstream, which
# is why each probe needs its own status function rather than relying on AC17's.
_status_fn_check() {
  local bad
  bad=$(python3 - "$WF" <<'PY2'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
MUST = ("BYOK Art.33 detector liveness", "sentry_alert live fidelity")
bad = []
for st in (d["jobs"]["apply"]["steps"] or []):
    name = str(st.get("name", ""))
    if not any(m in name for m in MUST):
        continue
    cond = str(st.get("if", ""))
    if not any(f in cond for f in ("always()", "cancelled()", "failure()")):
        bad.append(f"{name} :: if: {cond or '<<none -> implicit success()>>'}")
for b in bad:
    print(b)
PY2
)
  if [[ -z "$bad" ]]; then
    _report "R10 post-apply probes carry a status function (an AC17 failure cannot skip them)" ok
  else
    _report "R10 post-apply probes carry a status function" fail "$bad"
  fi
}
_status_fn_check

echo "=== $pass passed, $fail failed ==="

# ── harness rows. None of these routes through _report: a backstop dispatched
#    through the helper it backstops is disarmed by the same edit. ───────────
led_total=${#VERDICTS[@]}
led_fail=0
for _v in ${VERDICTS[@]+"${VERDICTS[@]}"}; do [[ "$_v" == "fail" ]] && led_fail=$((led_fail + 1)); done
led_ok=$((led_total - led_fail))

# (a) EXACT count, never `-ge`: a floor that descends with the thing it guards
#     is not a floor. Deleting a row reds here even with every row green.
if [[ "$led_total" -ne "$EXPECTED_TESTS" ]]; then
  echo "[FAIL] harness: ran $led_total test(s), expected $EXPECTED_TESTS — a suite that silently stops running its assertions reports green" >&2
  exit 1
fi

# (b) conservation: the counters and the append-only ledger must agree. A
#     single-site tamper of either (a rewritten _report, a moved increment)
#     makes these disagree.
if [[ "$led_ok" -ne "$pass" || "$led_fail" -ne "$fail" ]]; then
  echo "[FAIL] harness: ledger says $led_ok ok / $led_fail fail but the counters say $pass / $fail — one of them was tampered with" >&2
  exit 1
fi

# (c) the verdict itself, read from the ledger.
if [[ "$led_fail" -ne 0 ]]; then
  echo "[FAIL] harness: $led_fail failing row(s)" >&2
  exit 1
fi
exit 0
