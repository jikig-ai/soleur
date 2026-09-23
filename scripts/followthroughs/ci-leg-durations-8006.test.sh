#!/usr/bin/env bash
# Guard — ci-leg-durations-8006.sh cannot pass on stale, empty, or
# contaminated samples (#8006 soak probe).
#
# PROPERTY. The probe exits 0 only when ALL of:
#   - GH_TOKEN, gh, jq are present;
#   - SOLEUR_FT_EARLIEST is set, canonical ISO-8601 UTC, and parseable (runs
#     must postdate it — pre-merge legs predate the carve-out);
#   - >=3 COMPLETED push-arm main ci.yml runs postdate the cutoff AND are
#     QUALIFYING: all 8 expected legs present (test-scripts 1/5..5/5 +
#     test-scripts-heavy 1/3..3/3), each conclusion=success with non-null
#     started/completed timestamps;
#   - no qualifying leg measures >= 900 s.
# Every other shape exits non-zero: empty/stale-only samples, pre-carve-out
# runs (no heavy legs), runs with a skipped leg (unmeasurable AND fail-closed
# semantics: a skipped leg is not a green leg), breached legs, unparseable
# clock, gh failure, missing credential.
#
# STUB. `gh` is replaced by a fixture-backed stub on PATH that answers ONLY
# the argv the probe may legitimately issue:
#   gh api repos/.../actions/workflows/ci.yml/runs?...        -> $FIXTURE_DIR/runs.json
#   gh api --paginate repos/.../actions/runs/<id>/jobs?...    -> $FIXTURE_DIR/jobs-<id>.json
# Every invocation is appended to $FIXTURE_DIR/calls.log, and any other argv
# exits 64 after logging STUB-UNEXPECTED — a wandering probe fails loudly,
# not vacuously. FIXTURE_FAIL=1 makes the stub exit 1 on the runs call
# (CANNOT ESTABLISH arm).
#
# Values are synthesized (cq-test-fixtures-synthesized-only); every timestamp
# and run id is fabricated.
set -uo pipefail

PROBE="$(cd "$(dirname "$0")" && pwd)/ci-leg-durations-8006.sh"
PASS=0; FAIL=0
FIXTURE_DIRS=()
cleanup_fixtures() { rm -rf "${FIXTURE_DIRS[@]:-}"; }
trap cleanup_fixtures EXIT

ok()   { PASS=$((PASS+1)); echo "ok   $1"; }
bad()  { FAIL=$((FAIL+1)); echo "FAIL $1"; }

new_fixture() {
  FIXTURE_DIR="$(mktemp -d)"
  FIXTURE_DIRS+=("$FIXTURE_DIR")
  : > "$FIXTURE_DIR/calls.log"
  cat > "$FIXTURE_DIR/gh" <<'STUB'
#!/usr/bin/env bash
echo "$@" >> "$FIXTURE_DIR/calls.log"
url="${@: -1}"
case "$url" in
  *actions/workflows/ci.yml/runs*)
    if [ "${FIXTURE_FAIL:-0}" = "1" ]; then exit 1; fi
    cat "$FIXTURE_DIR/runs.json" ;;
  *actions/runs/*/jobs*)
    id="$(printf '%s' "$url" | sed -n 's|.*/runs/\([0-9]*\)/jobs.*|\1|p')"
    if [ -f "$FIXTURE_DIR/jobs-$id.json" ]; then cat "$FIXTURE_DIR/jobs-$id.json"; else exit 1; fi ;;
  *) echo "STUB-UNEXPECTED $*" >> "$FIXTURE_DIR/calls.log"; exit 64 ;;
esac
STUB
  chmod +x "$FIXTURE_DIR/gh"
}

# mk_run <id> <created_at> — one completed push-arm main run row.
mk_run() {
  jq -nc --argjson id "$1" --arg ca "$2" \
    '{id:$id, event:"push", head_branch:"main", status:"completed", created_at:$ca}'
}

# write_jobs <id> <leg_seconds> — a full 8-leg green page for run <id>.
write_jobs() {
  local id="$1" dur="$2" name
  {
    printf '{"jobs":['
    local first=1
    for name in "test-scripts (1/5)" "test-scripts (2/5)" "test-scripts (3/5)" \
                "test-scripts (4/5)" "test-scripts (5/5)" \
                "test-scripts-heavy (1/3)" "test-scripts-heavy (2/3)" \
                "test-scripts-heavy (3/3)"; do
      [[ $first -eq 0 ]] && printf ','
      first=0
      jq -nc --arg n "$name" --argjson d "$dur" '
        {name:$n, conclusion:"success",
         started_at:"2026-09-26T00:00:00Z",
         completed_at:(($d + 1790380800) | todateiso8601)}'
    done
    printf ']}'
  } > "$FIXTURE_DIR/jobs-$id.json"
}

run_probe() {
  GH_TOKEN="${GH_TOKEN_OVERRIDE-dummy}" \
  SOLEUR_FT_EARLIEST="${EARLIEST_OVERRIDE-2026-09-25T00:00:00Z}" \
  FIXTURE_DIR="$FIXTURE_DIR" FIXTURE_FAIL="${FIXTURE_FAIL:-0}" \
  PATH="$FIXTURE_DIR:$PATH" \
    bash "$PROBE" >"$FIXTURE_DIR/out" 2>&1
}

expect() { # <label> <want_rc>
  local label="$1" want="$2" got="$3"
  if [[ "$got" -eq "$want" ]]; then ok "$label (rc=$got)"; else
    bad "$label: want rc=$want got rc=$got -- $(tail -3 "$FIXTURE_DIR/out")"; fi
}

# T1: missing GH_TOKEN -> 2
new_fixture
GH_TOKEN_OVERRIDE= run_probe; expect "T1 no GH_TOKEN" 2 $?

# T2: missing cutoff -> 2
new_fixture
EARLIEST_OVERRIDE= run_probe; expect "T2 no cutoff" 2 $?

# T3: non-canonical cutoff -> 2
new_fixture
EARLIEST_OVERRIDE="now" run_probe; expect "T3 cutoff 'now'" 2 $?

# T4: xtrace + live credential -> 78 (#7797)
new_fixture
GH_TOKEN=dummy SOLEUR_FT_EARLIEST=2026-09-25T00:00:00Z \
  FIXTURE_DIR="$FIXTURE_DIR" PATH="$FIXTURE_DIR:$PATH" \
  bash -x "$PROBE" >/dev/null 2>&1
expect "T4 xtrace refusal" 78 $?

# T5: gh runs-api failure -> 3
new_fixture
jq -nc '{workflow_runs:[]}' > "$FIXTURE_DIR/runs.json"
FIXTURE_FAIL=1 run_probe; expect "T5 gh runs failure" 3 $?

# T6: empty run list -> 2 (0 qualifying)
new_fixture
jq -nc '{workflow_runs:[]}' > "$FIXTURE_DIR/runs.json"
run_probe; expect "T6 empty runs" 2 $?

# T7: three qualifying green runs, legs < 900 s -> 0
new_fixture
{ mk_run 101 2026-09-26T01:00:00Z; mk_run 102 2026-09-26T02:00:00Z
  mk_run 103 2026-09-26T03:00:00Z; } | jq -s '{workflow_runs:.}' > "$FIXTURE_DIR/runs.json"
write_jobs 101 500; write_jobs 102 600; write_jobs 103 700
run_probe; expect "T7 three green runs" 0 $?
grep -q '^PASS:' "$FIXTURE_DIR/out" && ok "T7 PASS marker" || bad "T7 missing PASS marker"

# T8: one breached leg -> 1
new_fixture
{ mk_run 101 2026-09-26T01:00:00Z; mk_run 102 2026-09-26T02:00:00Z
  mk_run 103 2026-09-26T03:00:00Z; } | jq -s '{workflow_runs:.}' > "$FIXTURE_DIR/runs.json"
write_jobs 101 500; write_jobs 102 950; write_jobs 103 700
run_probe; expect "T8 breached leg" 1 $?

# T9: pre-carve-out shape — runs present but heavy legs absent -> 2
new_fixture
{ mk_run 101 2026-09-26T01:00:00Z; mk_run 102 2026-09-26T02:00:00Z
  mk_run 103 2026-09-26T03:00:00Z; } | jq -s '{workflow_runs:.}' > "$FIXTURE_DIR/runs.json"
for id in 101 102 103; do
  { printf '{"jobs":['; first=1
    for name in "test-scripts (1/3)" "test-scripts (2/3)" "test-scripts (3/3)"; do
      [[ $first -eq 0 ]] && printf ','; first=0
      jq -nc --arg n "$name" '{name:$n, conclusion:"success",
        started_at:"2026-09-26T00:00:00Z", completed_at:"2026-09-26T00:10:00Z"}'
    done; printf ']}'; } > "$FIXTURE_DIR/jobs-$id.json"
done
run_probe; expect "T9 pre-carve-out legs" 2 $?

# T10: a skipped leg makes its run non-qualifying (2 qualifying < 3) -> 2
new_fixture
{ mk_run 101 2026-09-26T01:00:00Z; mk_run 102 2026-09-26T02:00:00Z
  mk_run 103 2026-09-26T03:00:00Z; } | jq -s '{workflow_runs:.}' > "$FIXTURE_DIR/runs.json"
write_jobs 101 500; write_jobs 103 700
write_jobs 102 600
jq '(.jobs[] | select(.name == "test-scripts-heavy (2/3)"))
    |= (.conclusion = "skipped" | .started_at = null | .completed_at = null)' \
  "$FIXTURE_DIR/jobs-102.json" > "$FIXTURE_DIR/jobs-102.json.tmp" \
  && mv "$FIXTURE_DIR/jobs-102.json.tmp" "$FIXTURE_DIR/jobs-102.json"
run_probe; expect "T10 skipped leg non-qualifying" 2 $?
grep -q 'non-qualifying' "$FIXTURE_DIR/out" && ok "T10 non-qualifying log" \
  || bad "T10 missing non-qualifying log"

# T11: jobs-api failure -> 3
new_fixture
{ mk_run 101 2026-09-26T01:00:00Z; } | jq -s '{workflow_runs:.}' > "$FIXTURE_DIR/runs.json"
# no jobs-101.json -> stub exits 1 on the jobs call
run_probe; expect "T11 gh jobs failure" 3 $?

rm -rf "$FIXTURE_DIR"
echo
echo "ci-leg-durations-8006.test.sh: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
