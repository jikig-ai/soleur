#!/usr/bin/env bash
# Guard for deploy-script-tests-legs-8736.sh — the probe cannot pass on stale,
# empty, or contaminated samples (#8736 soak probe).
#
# PROPERTY. The probe exits 0 only when >=5 COMPLETED successful push-arm runs
# of infra-validation.yml on main postdate the SOLEUR_FT_EARLIEST cutoff AND
# every qualifying run carries all six jobs (4 matrix legs + fixed + done),
# each concluded success with non-null timestamps, every one < 600 s.
# Every other shape exits non-zero: no cutoff, unparseable cutoff, gh failure,
# a run missing a leg, a leg that never finished, a breached budget.
#
# STUB. `gh` is replaced by a fixture-backed stub on PATH that answers ONLY the
# argv the probe may legitimately issue:
#   gh api repos/.../workflows/infra-validation.yml/runs?...  -> $FIXTURE_DIR/runs.json
#   gh api [--paginate] repos/.../actions/runs/<id>/jobs?...  -> $FIXTURE_DIR/jobs-<id>.json
# The stub honors --jq by piping the fixture through real jq. Any other argv
# exits 64 — the probe's own `2>/dev/null` would swallow stub stderr, so the
# calls log keeps a wandering probe loud, not silently vacuous.
#
# Values are synthesized (cq-test-fixtures-synthesized-only); every timestamp
# and run id is fabricated.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBE="$HERE/deploy-script-tests-legs-8736.sh"

fails=0
passes=0
pass() { printf '  PASS: %s\n' "$1"; passes=$((passes + 1)); }
fail() { printf '  FAIL: %s\n' "$1" >&2; fails=$((fails + 1)); }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Fixture dir must be a real writable scratch dir, never a synthetic fs.
FIXTURE_DIR=""
setup() {
  FIXTURE_DIR="$WORK/fx"
  rm -rf "$FIXTURE_DIR"; mkdir -p "$FIXTURE_DIR/bin"
  : > "$FIXTURE_DIR/calls.log"

  cat > "$FIXTURE_DIR/bin/gh" <<'STUB'
#!/usr/bin/env bash
set -u
printf '%s\n' "$*" >> "$FIXTURE_DIR/calls.log"
jqargs=()
api_args=()
while [ $# -gt 0 ]; do
  case "$1" in
    --jq) jqargs+=("$2"); shift 2 ;;
    --paginate) shift ;;                 # accepted, ignored
    api) shift ;;
    *) api_args+=("$1"); shift ;;
  esac
done
url="${api_args[0]:-}"
out=""
case "$url" in
  repos/jikig-ai/soleur/actions/workflows/infra-validation.yml/runs*)
    out="$FIXTURE_DIR/runs.json" ;;
  repos/jikig-ai/soleur/actions/runs/*/jobs*)
    id="$(printf '%s' "$url" | sed -nE 's#.*/runs/([0-9]+)/jobs.*#\1#p')"
    out="$FIXTURE_DIR/jobs-$id.json" ;;
  *) echo "STUB-UNEXPECTED: $url" >> "$FIXTURE_DIR/calls.log"; exit 64 ;;
esac
[ -f "$out" ] || { echo "STUB-MISSING-FIXTURE: $out" >&2; exit 64; }
if [ "${#jqargs[@]}" -gt 0 ]; then
  jq -r "${jqargs[0]}" < "$out"
else
  cat "$out"
fi
STUB
  chmod +x "$FIXTURE_DIR/bin/gh"
}

run_probe() {
  PATH="$FIXTURE_DIR/bin:$PATH" GH_TOKEN=fake FIXTURE_DIR="$FIXTURE_DIR" \
    SOLEUR_FT_EARLIEST="${SOLEUR_FT_EARLIEST:-}" \
    bash "$PROBE" >"$FIXTURE_DIR/out.log" 2>&1
  echo $?
}

# --- fixture writers ------------------------------------------------------
# mk_run <id> <created_at> : append a completed successful push run row.
mk_run() {
  cat >> "$FIXTURE_DIR/runs-frag.jsonl" <<EOF
{"id": $1, "created_at": "$2", "conclusion": "success", "event": "push", "status": "completed"}
EOF
}

# mk_jobs <id> <leg_seconds> : write jobs-<id>.json with all six jobs green,
# each leg running <leg_seconds> starting at 12:00:00Z on the created day.
mk_jobs() {
  local id="$1" secs="$2" day="${3:-2026-09-25}"
  python3 - "$FIXTURE_DIR/jobs-$id.json" "$secs" "$day" <<'PY'
import json, sys, datetime
out, secs, day = sys.argv[1], int(sys.argv[2]), sys.argv[3]
def job(name, secs):
    t0 = datetime.datetime.fromisoformat(day + "T12:00:00+00:00")
    t1 = t0 + datetime.timedelta(seconds=secs)
    return {"name": name, "conclusion": "success",
            "started_at": t0.strftime("%Y-%m-%dT%H:%M:%SZ"),
            "completed_at": t1.strftime("%Y-%m-%dT%H:%M:%SZ")}
names = [f"deploy-script-tests ({k}/4)" for k in range(1, 5)] + \
        ["deploy-script-tests-fixed", "deploy-script-tests-done"]
json.dump({"jobs": [job(n, secs) for n in names]}, open(out, "w"))
PY
}

# mk_jobs_partial <id> : a run missing the -done job (5 jobs) — non-qualifying.
mk_jobs_partial() {
  local id="$1" day="${2:-2026-09-25}"
  python3 - "$FIXTURE_DIR/jobs-$1.json" "$day" <<'PY'
import json, sys
out, day = sys.argv[1], sys.argv[2]
def job(name):
    return {"name": name, "conclusion": "success",
            "started_at": day + "T12:00:00Z", "completed_at": day + "T12:05:00Z"}
names = [f"deploy-script-tests ({k}/4)" for k in range(1, 5)] + \
        ["deploy-script-tests-fixed"]
json.dump({"jobs": [job(n) for n in names]}, open(out, "w"))
PY
}

finalize_runs() {
  python3 - "$FIXTURE_DIR/runs-frag.jsonl" "$FIXTURE_DIR/runs.json" <<'PY'
import json, sys
rows = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
json.dump({"workflow_runs": rows}, open(sys.argv[2], "w"))
PY
}

CUTOFF="2026-09-25T00:00:00Z"

# --- Case A: five qualifying runs, all legs 420 s -> PASS -------------------
setup
for i in 1 2 3 4 5; do
  mk_run "100$i" "2026-09-25T0${i}:00:00Z"
  mk_jobs "100$i" 420
done
finalize_runs
rc=$(SOLEUR_FT_EARLIEST="$CUTOFF" run_probe)
if [[ "$rc" == "0" ]] && grep -q "^PASS: 5 qualifying" "$FIXTURE_DIR/out.log"; then
  pass "A: 5 qualifying runs under budget -> PASS"
else
  fail "A: expected PASS, got rc=$rc: $(tail -3 "$FIXTURE_DIR/out.log")"
fi

# --- Case B: a 601 s leg in one qualifying run -> FAIL ----------------------
setup
for i in 1 2 3 4 5; do
  mk_run "100$i" "2026-09-25T0${i}:00:00Z"
  mk_jobs "100$i" 420
done
mk_jobs 1003 601   # overwrite run 3's jobs with a breaching leg
finalize_runs
rc=$(SOLEUR_FT_EARLIEST="$CUTOFF" run_probe)
if [[ "$rc" == "1" ]] && grep -q "BREACH" "$FIXTURE_DIR/out.log"; then
  pass "B: a breached leg -> FAIL with BREACH named"
else
  fail "B: expected FAIL rc=1, got rc=$rc: $(tail -3 "$FIXTURE_DIR/out.log")"
fi

# --- Case C: only 3 qualifying runs -> NOT YET -------------------------------
setup
for i in 1 2 3; do
  mk_run "100$i" "2026-09-25T0${i}:00:00Z"
  mk_jobs "100$i" 420
done
finalize_runs
rc=$(SOLEUR_FT_EARLIEST="$CUTOFF" run_probe)
if [[ "$rc" == "2" ]]; then
  pass "C: <5 qualifying runs -> NOT YET (rc=2, never auto-closes)"
else
  fail "C: expected NOT YET rc=2, got rc=$rc: $(tail -3 "$FIXTURE_DIR/out.log")"
fi

# --- Case D: a run missing the -done job is skipped, not counted -------------
setup
for i in 1 2 3 4; do
  mk_run "100$i" "2026-09-25T0${i}:00:00Z"
  mk_jobs "100$i" 420
done
mk_run 1005 "2026-09-25T05:00:00Z"; mk_jobs_partial 1005
finalize_runs
rc=$(SOLEUR_FT_EARLIEST="$CUTOFF" run_probe)
if [[ "$rc" == "2" ]] && grep -q "non-qualifying" "$FIXTURE_DIR/out.log"; then
  pass "D: a run missing a job is non-qualifying, not a sample point"
else
  fail "D: expected NOT YET with non-qualifying skip, got rc=$rc: $(tail -3 "$FIXTURE_DIR/out.log")"
fi

# --- Case E: no cutoff -> NOT YET -------------------------------------------
setup
mk_run 1001 "2026-09-25T01:00:00Z"; mk_jobs 1001 420; finalize_runs
rc=$(SOLEUR_FT_EARLIEST="" run_probe)
if [[ "$rc" == "2" ]]; then
  pass "E: unset cutoff -> NOT YET (rc=2)"
else
  fail "E: expected rc=2, got rc=$rc: $(tail -3 "$FIXTURE_DIR/out.log")"
fi

# --- Case F: a failed leg disqualifies the run -------------------------------
setup
for i in 1 2 3 4 5; do
  mk_run "100$i" "2026-09-25T0${i}:00:00Z"
  mk_jobs "100$i" 420
done
# flip one leg's conclusion in run 1004
python3 - "$FIXTURE_DIR/jobs-1004.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["jobs"][0]["conclusion"] = "failure"
json.dump(d, open(sys.argv[1], "w"))
PY
finalize_runs
rc=$(SOLEUR_FT_EARLIEST="$CUTOFF" run_probe)
if [[ "$rc" == "2" ]] && grep -q "non-qualifying" "$FIXTURE_DIR/out.log"; then
  pass "F: a run with a failed leg is non-qualifying (delays PASS, never fabricates)"
else
  fail "F: expected NOT YET, got rc=$rc: $(tail -3 "$FIXTURE_DIR/out.log")"
fi

echo ""
echo "=== deploy-script-tests-legs-8736: $passes passed, $fails failed ==="
(( fails == 0 ))
