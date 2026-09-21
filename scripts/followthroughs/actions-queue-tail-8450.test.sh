#!/usr/bin/env bash
# Guard 2 — actions-queue-tail-8450.sh cannot pass on stale, empty, or
# contaminated samples (#8450 soak probe).
#
# PROPERTY. The probe exits 0 only when ALL of:
#   - `gh api orgs/jikig-ai --jq .plan.name` == team (precondition);
#   - >=5 deploy-arm runs of web-platform-release.yml (event=workflow_run)
#     postdate the UPGRADE_NOT_BEFORE / SOLEUR_FT_EARLIEST cutoff;
#   - p95 of the per-JOB (started_at - created_at) waits on the deploy-arm jobs
#     (migrate, deploy) is < 900 s.
# Every other shape exits non-zero: empty window, stale-only samples,
# push-arm contamination, breached p95, unparseable/missing clock, gh failure.
#
# SEMANTICS NOTE (vs the plan's written matrix): the plan said SKIP-DECLARED
# exits 0. Under sweep-followthroughs.sh, exit 0 AUTO-CLOSES the tracked
# issue — a false resolution of #8450 if the org plan silently stayed
# `free`. The correct sweeper verdict for a precondition-not-yet-met is
# exit 2 ("NOT YET": leaves open, retries next sweep). The probe still prints
# the SKIP-DECLARED marker in its output so the vocabulary survives; only the
# code changed. Recorded in measurements.md.
#
# STUB. `gh` is replaced by a fixture-backed stub on PATH that answers ONLY
# the argv the probe may legitimately issue:
#   gh api orgs/jikig-ai                      -> $FIXTURE_DIR/plan.json
#   gh api repos/.../workflows/web-platform-release.yml/runs...  -> runs.json
#   gh api repos/.../actions/runs/<id>/jobs   -> jobs-<id>.json
# Any other argv exits 64 with STUB-UNEXPECTED so a probe that wanders off the
# pinned endpoints is loud, not silently vacuous.
#
# Values are synthesized (cq-test-fixtures-synthesized-only); every timestamp
# and run id is fabricated.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBE="$HERE/actions-queue-tail-8450.sh"

fails=0
passes=0
pass() { printf '  PASS: %s\n' "$1"; passes=$((passes + 1)); }
fail() { printf '  FAIL: %s\n' "$1" >&2; fails=$((fails + 1)); }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

command -v jq >/dev/null || { echo "FATAL: jq required for the fixture stub" >&2; exit 1; }

CUTOFF="2026-09-22T00:00:00Z"   # fabricated upgrade-verification timestamp

# ── fixture builders ────────────────────────────────────────────────────────
# A runs.json page: id + created_at + event + status per run.
run_row() { # <id> <created_at> <event> <status>
  printf '{"id":%s,"created_at":"%s","event":"%s","status":"%s","conclusion":"success"}' "$1" "$2" "$3" "$4"
}

# A jobs-<id>.json: deploy-arm jobs with controlled waits (seconds).
jobs_fixture() { # <file> <wait_seconds>...
  local file="$1"; shift
  local jobs="" first=1
  for w in "$@"; do
    # job created_at = 2026-09-22T01:00:00Z; started_at = created + w
    local start
    start="$(jq -nr --argjson w "$w" '(1790038800 + $w) | strftime("%Y-%m-%dT%H:%M:%SZ")')"
    local row
    row="$(jq -nc --arg s "$start" '{name:"migrate",status:"completed",created_at:"2026-09-22T01:00:00Z",started_at:$s,completed_at:$s}')"
    if [ "$first" -eq 1 ]; then jobs="$row"; first=0; else jobs="$jobs,$row"; fi
  done
  printf '{"total_count":%d,"jobs":[%s]}\n' "$#" "$jobs" > "$file"
}

# write_runs <file> <run_row>...
write_runs() {
  local file="$1"; shift
  local rows="" first=1
  for r in "$@"; do
    if [ "$first" -eq 1 ]; then rows="$r"; first=0; else rows="$rows,$r"; fi
  done
  printf '{"total_count":%d,"workflow_runs":[%s]}\n' "$#" "$rows" > "$file"
}

mkplan() { printf '{"plan":{"name":"%s"}}\n' "$1" > "$WORK/fix/plan.json"; }

# run_probe <desc-irrelevant> — probe env: GH_TOKEN dummy, cutoff set.
run_probe() {
  local out rc
  out="$(env -i PATH="$WORK/bin:/usr/bin:/bin" HOME="$WORK" GH_TOKEN=fake \
        FIXTURE_DIR="$WORK/fix" UPGRADE_NOT_BEFORE="$CUTOFF" bash "$PROBE" 2>&1)"
  rc=$?
  printf '%s' "$out" > "$WORK/out"
  return $rc
}

expect() { # <desc> <want_rc> <needle-in-output-or-"">
  local desc="$1" want="$2" needle="${3:-}" rc=0
  run_probe || rc=$?
  if grep -q 'STUB-UNEXPECTED' "$WORK/out"; then
    fail "$desc (probe hit an unstubbed endpoint: $(grep STUB-UNEXPECTED "$WORK/out" | head -1))"
    return
  fi
  if [ "$rc" -ne "$want" ]; then
    fail "$desc (want rc=$want got rc=$rc; out: $(tail -3 "$WORK/out"))"
    return
  fi
  if [ -n "$needle" ] && ! grep -qF "$needle" "$WORK/out"; then
    fail "$desc (rc ok but output missing '$needle')"
    return
  fi
  pass "$desc"
}

mkdir -p "$WORK/bin" "$WORK/fix"
cat > "$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
set -uo pipefail
FIX="${FIXTURE_DIR:?}"
[[ "${1:-}" == "api" ]] || { printf 'STUB-UNEXPECTED: gh %s\n' "$*" >&2; exit 64; }
ep="${2:-}"
shift 2
# Emulate gh's client-side --jq flag: collect it, apply with real jq.
JQEXPR=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --jq) JQEXPR="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done
out() { if [[ -n "$JQEXPR" ]]; then jq -r "$JQEXPR"; else cat; fi; }
case "$ep" in
  orgs/jikig-ai) out < "$FIX/plan.json" ;;
  repos/jikig-ai/soleur/actions/workflows/web-platform-release.yml/runs*)
    out < "$FIX/runs.json" ;;
  repos/jikig-ai/soleur/actions/runs/*/jobs)
    id="$(printf '%s' "$ep" | sed -n 's|.*/runs/\([0-9]*\)/jobs|\1|p')"
    f="$FIX/jobs-$id.json"
    [[ -f "$f" ]] || { printf 'STUB-UNEXPECTED: no jobs fixture for run %s\n' "$id" >&2; exit 64; }
    out < "$f" ;;
  *) printf 'STUB-UNEXPECTED: gh api %s\n' "$ep" >&2; exit 64 ;;
esac
STUB
chmod +x "$WORK/bin/gh"
export FIXTURE_DIR="$WORK/fix"

echo "── Guard 2: precondition + sampling matrix"

# 1. Non-team plan -> SKIP-DECLARED, exit 2 (NOT YET — never close #8450 on it).
mkplan free
write_runs "$WORK/fix/runs.json"
expect "plan=free is SKIP-DECLARED (exit 2, not a close)" 2 "SKIP-DECLARED"

# 2. Team plan + zero deploy-arm runs in window -> non-zero (no vacuous pass).
mkplan team
write_runs "$WORK/fix/runs.json"
expect "empty run window cannot pass" 2 "INSUFFICIENT"

# 3. Team + runs ALL predating the cutoff -> non-zero (stale window rejected).
write_runs "$WORK/fix/runs.json" \
  "$(run_row 1001 2026-09-20T10:00:00Z workflow_run completed)" \
  "$(run_row 1002 2026-09-20T11:00:00Z workflow_run completed)" \
  "$(run_row 1003 2026-09-20T12:00:00Z workflow_run completed)" \
  "$(run_row 1004 2026-09-20T13:00:00Z workflow_run completed)" \
  "$(run_row 1005 2026-09-20T14:00:00Z workflow_run completed)"
expect "pre-upgrade samples are stale, not evidence" 2 ""

# 4. Team + 5 fresh workflow_run runs, p95 wait < 15 min -> PASS exit 0.
write_runs "$WORK/fix/runs.json" \
  "$(run_row 2001 2026-09-22T01:00:00Z workflow_run completed)" \
  "$(run_row 2002 2026-09-22T02:00:00Z workflow_run completed)" \
  "$(run_row 2003 2026-09-22T03:00:00Z workflow_run completed)" \
  "$(run_row 2004 2026-09-22T04:00:00Z workflow_run completed)" \
  "$(run_row 2005 2026-09-22T05:00:00Z workflow_run completed)"
for id in 2001 2002 2003 2004 2005; do jobs_fixture "$WORK/fix/jobs-$id.json" 30 60; done
expect "passing dataset (fresh, p95<15min) exits 0" 0 "PASS"

# 5. Team + 5 fresh runs but p95 wait >= 15 min -> FAIL exit 1.
for id in 2001 2002 2003 2004 2005; do jobs_fixture "$WORK/fix/jobs-$id.json" 30 1200; done
expect "p95>=15min breaches -> FAIL" 1 "FAIL"

# 6. Push-arm contamination: a 'push'-event run must be excluded by the probe's
#    own event=workflow_run filter. Fixture returns ONLY push-arm runs (as if
#    the probe forgot the filter); the probe's URL must carry the filter so the
#    stubbed runs.json is the workflow_run-filtered page — here we simulate the
#    unfiltered reality: push-only rows yield no deploy-arm evidence.
write_runs "$WORK/fix/runs.json" \
  "$(run_row 3001 2026-09-22T01:00:00Z push completed)" \
  "$(run_row 3002 2026-09-22T02:00:00Z push completed)" \
  "$(run_row 3003 2026-09-22T03:00:00Z push completed)" \
  "$(run_row 3004 2026-09-22T04:00:00Z push completed)" \
  "$(run_row 3005 2026-09-22T05:00:00Z push completed)"
expect "push-arm runs are not deploy-arm evidence" 2 "INSUFFICIENT"

# 7. Fewer than 5 usable runs -> INSUFFICIENT, non-zero.
write_runs "$WORK/fix/runs.json" \
  "$(run_row 4001 2026-09-22T01:00:00Z workflow_run completed)" \
  "$(run_row 4002 2026-09-22T02:00:00Z workflow_run completed)"
jobs_fixture "$WORK/fix/jobs-4001.json" 10
jobs_fixture "$WORK/fix/jobs-4002.json" 10
expect "<5 usable runs is INSUFFICIENT" 2 "INSUFFICIENT"

# 8. Missing clock: no UPGRADE_NOT_BEFORE / SOLEUR_FT_EARLIEST -> non-zero.
mkplan team
write_runs "$WORK/fix/runs.json" "$(run_row 5001 2026-09-22T01:00:00Z workflow_run completed)"
jobs_fixture "$WORK/fix/jobs-5001.json" 10
out="$(env -i PATH="$WORK/bin:/usr/bin:/bin" HOME="$WORK" GH_TOKEN=fake FIXTURE_DIR="$WORK/fix" bash "$PROBE" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then fail "missing clock must not pass"; else pass "missing clock is non-zero (rc=$rc)"; fi

echo
echo "Guard 2: $passes passed, $fails failed"
[ "$fails" -eq 0 ]
