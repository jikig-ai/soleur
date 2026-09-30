#!/usr/bin/env bash
# Guard for ci-leg-balance-9232.sh — the probe cannot pass on stale, empty,
# partial, or contaminated samples (#9232 leg-balance soak).
#
# PROPERTY. The probe exits 0 only when >=3 COMPLETED successful push-arm runs
# of ci.yml on main postdate the SOLEUR_FT_EARLIEST cutoff AND each run carried
# all N light-leg `suite-timings-scripts-*` artifacts AND every leg's summed
# suite ms is within ~2x of the run's mean (excluding legs whose largest single
# suite alone exceeds the mean). Every other shape exits non-zero: no cutoff,
# unparseable cutoff, gh failure, a run missing a leg, a breached balance.
#
# STUB. `gh` is replaced by a fixture-backed stub on PATH that answers ONLY the
# argv the probe may legitimately issue:
#   gh api repos/.../workflows/ci.yml/runs?...        -> $FIXTURE_DIR/runs.json
#   gh api repos/.../actions/runs/<id>/artifacts?...  -> $FIXTURE_DIR/arts-<id>.json
#   gh api repos/.../artifacts/<aid>/zip              -> $FIXTURE_DIR/art-<aid>.zip
# The stub honors --jq by piping the fixture through real jq. Any other argv
# exits 64 — the probe's own `2>/dev/null` would swallow stub stderr, so the
# calls log keeps a wandering probe loud, not silently vacuous.
#
# Values are synthesized (cq-test-fixtures-synthesized-only); every timestamp,
# run id, and timing is fabricated. Artifact zips are built by python3 at
# fixture-setup time, never downloaded.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBE="$HERE/ci-leg-balance-9232.sh"

fails=0
passes=0
pass() { printf '  PASS: %s\n' "$1"; passes=$((passes + 1)); }
fail() { printf '  FAIL: %s\n' "$1" >&2; fails=$((fails + 1)); }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# The probe reads the expected leg count from the committed manifest's `# n=`
# header — derive N here the same way rather than hardcoding a count.
N_HDR="$(grep -m1 '^# n=' "$HERE/../suite-shard-legs.tsv" | sed 's/^# n=//' || true)"
if [[ ! "$N_HDR" =~ ^[0-9]+$ ]]; then
  echo "FATAL: cannot derive N from scripts/suite-shard-legs.tsv — the probe's"
  echo "  qualifying rule is ungrounded." >&2
  exit 2
fi
N=$((10#$N_HDR))

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
    --paginate) shift ;;
    api) shift ;;
    *) api_args+=("$1"); shift ;;
  esac
done
url="${api_args[0]:-}"
out=""
case "$url" in
  repos/jikig-ai/soleur/actions/workflows/ci.yml/runs*)
    out="$FIXTURE_DIR/runs.json" ;;
  repos/jikig-ai/soleur/actions/runs/*/artifacts*)
    id="$(printf '%s' "$url" | sed -nE 's#.*/runs/([0-9]+)/artifacts.*#\1#p')"
    out="$FIXTURE_DIR/arts-$id.json" ;;
  repos/jikig-ai/soleur/actions/artifacts/*/zip)
    aid="$(printf '%s' "$url" | sed -nE 's#.*/artifacts/([0-9]+)/zip.*#\1#p')"
    # Binary payload — cat it verbatim, never through jq.
    cat "$FIXTURE_DIR/art-$aid.zip" 2>/dev/null || { echo "STUB-MISSING-FIXTURE: art-$aid.zip" >&2; exit 64; }
    exit 0 ;;
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

expect() { # <label> <want-rc>
  local label="$1" want="$2" rc
  rc="$(run_probe)"
  if [ "$rc" = "$want" ]; then
    pass "$label (rc=$rc)"
  else
    fail "$label: rc=$rc, want $want — $(tail -3 "$FIXTURE_DIR/out.log")"
  fi
}

# --- Fixture builders -------------------------------------------------------
# mk_runs <file> <id:created pairs...>: runs list fixture (conclusion=success).
mk_runs() {
  local out="$1"; shift
  {
    printf '{"workflow_runs": ['
    local first=1
    for pair in "$@"; do
      [ "$first" = 1 ] || printf ','
      first=0
      printf '{"id": %s, "created_at": "%s", "conclusion": "success"}' \
        "${pair%%:*}" "${pair#*:}"
    done
    printf ']}'
  } > "$out"
}

# mk_arts <file> <run_id> <leg-count>: artifact listing, ids <run_id>0<k>,
# names suite-timings-scripts-<k>.
mk_arts() {
  local out="$1" rid="$2" cnt="$3" k
  {
    printf '{"artifacts": ['
    for k in $(seq 1 "$cnt"); do
      [ "$k" -gt 1 ] && printf ','
      printf '{"id": %s, "name": "suite-timings-scripts-%s"}' "${rid}0${k}" "$k"
    done
    printf ']}'
  } > "$out"
}

# mk_leg <dir> <run_id> <leg> <suite_ms...>: write art-<run_id>0<leg>.zip
# holding suite-timings.tsv with one row per arg.
mk_leg() {
  local dir="$1" rid="$2" leg="$3"; shift 3
  python3 - "$dir" "$rid" "$leg" "$@" <<'PY'
import sys, zipfile, os
d, rid, leg = sys.argv[1], sys.argv[2], sys.argv[3]
rows = "".join(f"suite-{i}\t{ms}\n" for i, ms in enumerate(sys.argv[4:]))
zp = os.path.join(d, f"art-{rid}0{leg}.zip")
with zipfile.ZipFile(zp, "w") as z:
    z.writestr("suite-timings.tsv", rows)
PY
}

# mk_balanced_run <run_id>: all N legs present, each summing 1000ms.
mk_balanced_run() {
  local rid="$1" k
  mk_arts "$FIXTURE_DIR/arts-$rid.json" "$rid" "$N"
  for k in $(seq 1 "$N"); do
    mk_leg "$FIXTURE_DIR" "$rid" "$k" 500 500
  done
}

echo "=== ci-leg-balance-9232 guard ==="

# --- Case 1: no GH_TOKEN → NOT YET -------------------------------------------
setup
mk_runs "$FIXTURE_DIR/runs.json"
rc="$(PATH="$FIXTURE_DIR/bin:$PATH" FIXTURE_DIR="$FIXTURE_DIR" \
      SOLEUR_FT_EARLIEST="2099-01-01T00:00:00Z" bash "$PROBE" 2>/dev/null; echo $?)"
if [ "$rc" = "2" ]; then pass "no GH_TOKEN -> NOT YET"; else fail "no GH_TOKEN: rc=$rc want 2"; fi

# --- Case 2: unparseable cutoff → NOT YET -------------------------------------
setup
mk_runs "$FIXTURE_DIR/runs.json"
SOLEUR_FT_EARLIEST="yesterday" expect "non-ISO cutoff -> NOT YET" 2

# --- Case 3: runs-list gh failure → CANNOT ESTABLISH ---------------------------
setup   # no runs.json — the stub exits 64 on a missing fixture
SOLEUR_FT_EARLIEST="2020-01-01T00:00:00Z" expect "gh failure on runs list -> CANNOT ESTABLISH" 3

# --- Case 4: fewer than MIN_RUNS qualifying → NOT YET --------------------------
setup
mk_runs "$FIXTURE_DIR/runs.json" "9001:2099-06-02T00:00:00Z" "9002:2099-06-03T00:00:00Z"
mk_balanced_run 9001
mk_balanced_run 9002
SOLEUR_FT_EARLIEST="2099-06-01T00:00:00Z" expect "2 of 3 qualifying runs -> NOT YET" 2

# --- Case 5: a run missing one leg is non-qualifying → NOT YET -----------------
setup
mk_runs "$FIXTURE_DIR/runs.json" \
  "9001:2099-06-02T00:00:00Z" "9002:2099-06-03T00:00:00Z" "9003:2099-06-04T00:00:00Z"
mk_balanced_run 9001
mk_balanced_run 9002
# run 9003 uploads only N-1 legs — a missing leg is unmeasurable, not balanced.
mk_arts "$FIXTURE_DIR/arts-9003.json" 9003 "$((N - 1))"
for k in $(seq 1 "$((N - 1))"); do mk_leg "$FIXTURE_DIR" 9003 "$k" 500 500; done
SOLEUR_FT_EARLIEST="2099-06-01T00:00:00Z" expect "partial-upload run does not qualify -> NOT YET" 2

# --- Case 6: three qualifying balanced runs → PASS -----------------------------
setup
mk_runs "$FIXTURE_DIR/runs.json" \
  "9001:2099-06-02T00:00:00Z" "9002:2099-06-03T00:00:00Z" "9003:2099-06-04T00:00:00Z"
mk_balanced_run 9001; mk_balanced_run 9002; mk_balanced_run 9003
SOLEUR_FT_EARLIEST="2099-06-01T00:00:00Z" expect "3 balanced qualifying runs -> PASS" 0

# --- Case 6b: every /artifacts LIST call carries --paginate ---------------------
# A first-page-only fetch truncates a >100-artifact run and reads identically
# to a leg that died before its feed write — the qualifying-runs filter would
# silently under-sample. Assert on call SHAPE, not just output: the stub serves
# its fixture regardless, so only the argv log sees a dropped flag. Mirrors
# actions-queue-health.test.sh's jobs-call pin. Anchored on /actions/runs/ so
# the binary /actions/artifacts/<id>/zip downloads are excluded. Reads case 6's
# calls.log — case 9's pre-cutoff runs never reach the artifacts call.
art_calls="$(grep '/actions/runs/.*/artifacts' "$FIXTURE_DIR/calls.log" | grep -vc '/zip' || true)"
art_calls_paginated="$(grep '/actions/runs/.*/artifacts' "$FIXTURE_DIR/calls.log" | grep -v '/zip' | grep -c -- '--paginate' || true)"
if [ "$art_calls" -gt 0 ] && [ "$art_calls" -eq "$art_calls_paginated" ]; then
  pass "every artifacts list call carried --paginate ($art_calls_paginated/$art_calls)"
else
  fail "artifacts list call(s) missing --paginate ($art_calls_paginated/$art_calls): $(grep '/actions/runs/.*/artifacts' "$FIXTURE_DIR/calls.log" | grep -v '/zip')"
fi

# --- Case 7: a breaching leg → FAIL ---------------------------------------------
# N legs of 1000ms plus one leg of 4000ms built from small suites: total
# (N+3)*1000 over N legs; the hot leg sits above ~2x the mean with no single
# suite above the mean — a real imbalance, not the mega-suite carve-out.
setup
mk_runs "$FIXTURE_DIR/runs.json" \
  "9001:2099-06-02T00:00:00Z" "9002:2099-06-03T00:00:00Z" "9003:2099-06-04T00:00:00Z"
mk_balanced_run 9001; mk_balanced_run 9002
mk_arts "$FIXTURE_DIR/arts-9003.json" 9003 "$N"
for k in $(seq 1 "$N"); do
  if [ "$k" -eq 1 ]; then
    mk_leg "$FIXTURE_DIR" 9003 "$k" 1000 1000 1000 1000   # 4000ms of small suites
  else
    mk_leg "$FIXTURE_DIR" 9003 "$k" 500 500
  fi
done
SOLEUR_FT_EARLIEST="2099-06-01T00:00:00Z" expect "hot leg >2x mean of small suites -> FAIL" 1

# --- Case 8: mega-suite carve-out → PASS ---------------------------------------
# One leg dominated by a single suite above the mean — the issue's carve-out;
# no K can split it, so the leg is exempt and the run still qualifies as
# balanced.
setup
mk_runs "$FIXTURE_DIR/runs.json" \
  "9001:2099-06-02T00:00:00Z" "9002:2099-06-03T00:00:00Z" "9003:2099-06-04T00:00:00Z"
mk_balanced_run 9001; mk_balanced_run 9002
mk_arts "$FIXTURE_DIR/arts-9003.json" 9003 "$N"
for k in $(seq 1 "$N"); do
  if [ "$k" -eq 1 ]; then
    mk_leg "$FIXTURE_DIR" 9003 "$k" 9000                  # one atomic mega-suite
  else
    mk_leg "$FIXTURE_DIR" 9003 "$k" 500 500
  fi
done
SOLEUR_FT_EARLIEST="2099-06-01T00:00:00Z" expect "mega-suite leg exempt -> PASS" 0

# --- Case 9: pre-cutoff runs never contribute → NOT YET -------------------------
setup
mk_runs "$FIXTURE_DIR/runs.json" \
  "9001:2020-06-02T00:00:00Z" "9002:2020-06-03T00:00:00Z" "9003:2020-06-04T00:00:00Z"
mk_balanced_run 9001; mk_balanced_run 9002; mk_balanced_run 9003
SOLEUR_FT_EARLIEST="2099-06-01T00:00:00Z" expect "runs before cutoff are stale -> NOT YET" 2

echo ""
echo "ci-leg-balance-9232.test.sh: $((passes + fails)) checks, $passes passed, $fails failed"
[ "$fails" -eq 0 ] || exit 1
echo "All tests passed"
