#!/usr/bin/env bash
# Guards watchdog-debounce-soak-9686.sh (#9686): the probe can never exit 0/1,
# and every verdict class is reachable on the fixture shape it asserts.
#
# STUB. `gh` on PATH is replaced by a fixture-backed stub answering ONLY the
# argv the probe may legitimately issue:
#   gh api repos/<r>/commits?path=<self>&sha=main&per_page=1 -> $FX/merge.json
#   gh api repos/<r>/actions/workflows/<wf>/runs?...          -> $FX/runs.json
#   gh api repos/<r>/compare/<base>...<head>                  -> $FX/compare-<head>.json
#   gh api repos/<r>/actions/runs/<id>/jobs?...               -> $FX/jobs-<id>.json
#   gh run view --job <id> --repo <r> --log                   -> $FX/log-<id>.txt (cat, no --jq)
# --jq <expr> is honored by piping the fixture through real jq — the same
# discipline as watchdog-arm-soak-9237.test.sh: a probe that drifts its jq
# expression reads the fixture wrongly and reds here, not in the sweeper.
# Anything else logs STUB-UNEXPECTED to $FX/calls.log and exits 64 — the
# probe's own `2>/dev/null` would swallow stub stderr.
#
# WIRE-SHAPE DISCIPLINE (#9686): `gh run view --log` prefixes every line with
# a timestamp — fixtures carry `2026-10-08T00:03:56.0422320Z <content>` lines,
# never bare content, and the dirty arm includes the ANSI-wrapped `run:`-block
# echo of the monitor's own `grep 'parent process gone'` source line. A probe
# that greps bare phrases reads that echo as a fire; a probe that anchors
# `^---` reads no banner at all. Both defects lived here before this note.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBE="$HERE/watchdog-debounce-soak-9686.sh"
fails=0

say() { printf '%s\n' "$*"; }
check() { # check <name> <want_rc> <got_rc> <output>
  if [ "$3" = "$2" ]; then say "ok   $1"; else say "FAIL $1 — want rc=$2 got rc=$3 :: $(tail -1 <<<"$4")"; fails=$((fails+1)); fi
}
check_body() { # check_body <name> <output> <want-substr>
  case "$2" in
    *"$3"*) say "ok   $1" ;;
    *) say "FAIL $1 — output lacks '$3' :: $(tail -1 <<<"$2")"; fails=$((fails+1)) ;;
  esac
}
check_never01() { # check_never01 <name> <got_rc> — the notify-only invariant
  case "$2" in
    0|1) say "FAIL $1 — probe exited $2; notify-only probes never take 0/1"; fails=$((fails+1)) ;;
    *) say "ok   $1" ;;
  esac
}
check_stub_clean() { # check_stub_clean <name> <dir> — no unexpected argv
  if grep -q 'STUB-UNEXPECTED' "$2/calls.log" 2>/dev/null; then
    say "FAIL $1 — stub saw unexpected argv: $(grep 'STUB-UNEXPECTED' "$2/calls.log" | head -1)"
    fails=$((fails+1))
  else
    say "ok   $1"
  fi
}

mk_stub() { # mk_stub <dir> — writes the gh stub into $1/bin/gh
  mkdir -p "$1/bin"
  cat > "$1/bin/gh" <<'STUB'
#!/usr/bin/env bash
set -uo pipefail
FX="${FIXTURE_DIR:?}"
echo "$*" >> "$FX/calls.log"
EXPR=""
prev=""
for a in "$@"; do
  [ "$prev" = "--jq" ] && EXPR="$a"
  prev="$a"
done
case "$*" in
  "run view --job "*"--log"*)
    JID="$(sed -n 's|.*--job \([0-9]*\).*|\1|p' <<<"$*" | head -1)"
    F="$FX/log-$JID.txt"
    [ -f "$F" ] || { echo "STUB-UNEXPECTED: no log fixture for job $JID" >> "$FX/calls.log"; exit 64; }
    cat "$F"; exit 0 ;;
  *"commits?path="*)           F="$FX/merge.json" ;;
  *"actions/workflows/"*"runs"*) F="$FX/runs.json" ;;
  *"/compare/"*)
    HEAD="$(sed -n 's|.*/compare/[0-9a-f]*\.\.\.\([0-9a-f]*\).*|\1|p' <<<"$*" | head -1)"
    F="$FX/compare-$HEAD.json"
    [ -f "$F" ] || { echo "STUB-UNEXPECTED: no compare fixture for head $HEAD" >> "$FX/calls.log"; exit 64; } ;;
  *"actions/runs/"*"/jobs"*)
    RID="$(sed -n 's|.*/actions/runs/\([0-9]*\)/jobs.*|\1|p' <<<"$*" | head -1)"
    F="$FX/jobs-$RID.json"
    [ -f "$F" ] || { echo "STUB-UNEXPECTED: no jobs fixture for run $RID" >> "$FX/calls.log"; exit 64; } ;;
  *) echo "STUB-UNEXPECTED: $*" >> "$FX/calls.log"; exit 64 ;;
esac
[ -f "$F" ] || { echo "STUB-UNEXPECTED: missing $F" >> "$FX/calls.log"; exit 64; }
if [ -n "$EXPR" ]; then jq "$EXPR" "$F"; else cat "$F"; fi
STUB
  chmod +x "$1/bin/gh"
}

run_probe() { # run_probe <dir> — prints probe output on stdout; rc in $?
  env PATH="$1/bin:/usr/bin:/bin" FIXTURE_DIR="$1" GH_TOKEN="stub-token" \
    timeout 120 bash "$PROBE" 2>&1
}

MERGE_SHA="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
TS="2026-10-08T00:03:56.0422320Z"
ARM_DIRS=()
mk_fixtures() { # mk_fixtures <dir> — shared base fixtures; arms mutate after
  mkdir -p "$1"
  : > "$1/calls.log"
  printf '[{"sha":"%s"}]\n' "$MERGE_SHA" > "$1/merge.json"
  ARM_DIRS+=("$1")
}
trap 'rm -rf "${ARM_DIRS[@]:-}"' EXIT

# --- Arm 1: CLEAN — two consecutive post-merge qualifying runs, zero kills ---
D="$(mktemp -d)"; mk_fixtures "$D"; mk_stub "$D"
cat > "$D/runs.json" <<'JSON'
{"workflow_runs":[
 {"id":901,"head_sha":"cccccccccccccccccccccccccccccccccccccccc","created_at":"2026-10-08T00:00:00Z","conclusion":"failure"},
 {"id":902,"head_sha":"dddddddddddddddddddddddddddddddddddddddd","created_at":"2026-10-07T18:00:00Z","conclusion":"success"},
 {"id":903,"head_sha":"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee","created_at":"2026-10-07T12:00:00Z","conclusion":"success"}
]}
JSON
printf '{"status":"ahead"}' > "$D/compare-cccccccccccccccccccccccccccccccccccccccc.json"
printf '{"status":"ahead"}' > "$D/compare-dddddddddddddddddddddddddddddddddddddddd.json"
printf '{"status":"ahead"}' > "$D/compare-eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee.json"
printf '{"jobs":[{"id":5001,"name":"health-check"}]}' > "$D/jobs-901.json"
printf '{"jobs":[{"id":5002,"name":"health-check"}]}' > "$D/jobs-902.json"
printf '{"jobs":[{"id":5003,"name":"health-check"}]}' > "$D/jobs-903.json"
# Timestamp-prefixed wire shape, INCLUDING the ANSI-wrapped echo of the
# monitor's own verdict-classifier source — the exact line that a bare-phrase
# grep would misread as a watchdog fire.
printf '%s \x1b[36;1m    gone_hits=$(grep -a -m 1 -E '"'"'^ERROR: parent process gone'"'"' "$file" | wc -l)\x1b[m\n' "$TS" > "$D/log-5001.txt"
printf '%s --- scripts/some-suite ---\n%s [ok] suite fine\n%s === 12/12 suites passed ===\n' "$TS" "$TS" "$TS" >> "$D/log-5001.txt"
printf '%s --- scripts/other-suite ---\n%s [FAIL] a real suite failure — monitor reds for a non-watchdog reason\n%s === 11/12 suites passed ===\n' "$TS" "$TS" "$TS" > "$D/log-5002.txt"
printf '%s --- scripts/another-suite ---\n%s === 12/12 suites passed ===\n' "$TS" "$TS" > "$D/log-5003.txt"
OUT="$(run_probe "$D")"; RC=$?
check "clean soak: two clean qualifying runs -> ACTION REQUIRED" 5 "$RC" "$OUT"
check_body "clean soak names the streak" "$OUT" "clean soak"
check_never01 "clean soak never takes 0/1" "$RC"
check_stub_clean "clean soak: stub argv all expected" "$D"

# --- Arm 2: DIRTY — newest post-merge run carries an EMITTED watchdog line ---
D="$(mktemp -d)"; mk_fixtures "$D"; mk_stub "$D"
cat > "$D/runs.json" <<'JSON'
{"workflow_runs":[
 {"id":910,"head_sha":"cccccccccccccccccccccccccccccccccccccccc","created_at":"2026-10-08T00:00:00Z","conclusion":"failure"},
 {"id":911,"head_sha":"dddddddddddddddddddddddddddddddddddddddd","created_at":"2026-10-07T18:00:00Z","conclusion":"success"}
]}
JSON
printf '{"status":"ahead"}' > "$D/compare-cccccccccccccccccccccccccccccccccccccccc.json"
printf '{"status":"ahead"}' > "$D/compare-dddddddddddddddddddddddddddddddddddddddd.json"
printf '{"jobs":[{"id":5010,"name":"health-check"}]}' > "$D/jobs-910.json"
printf '{"jobs":[{"id":5011,"name":"health-check"}]}' > "$D/jobs-911.json"
# Emitted shape only — no === terminal (a reaped runner may never reach the
# epilogue). The ANSI echo line proves the emitted-form grep, not the bare
# phrase, is what counts dirty.
printf '%s --- scripts/battery-tag-authorship-mutations ---\n' "$TS" > "$D/log-5010.txt"
printf '%s ERROR: parent process gone — orphaned test-all run terminating itself and in-flight suite children (#8993)\n' "$TS" >> "$D/log-5010.txt"
printf '%s [KILLED] scripts/battery-tag-authorship-mutations (exit=143)\n' "$TS" >> "$D/log-5010.txt"
printf '%s \x1b[36;1m    gone_hits=$(grep -a -m 1 -E '"'"'^ERROR: parent process gone'"'"' "$file" | wc -l)\x1b[m\n' "$TS" >> "$D/log-5010.txt"
printf '%s --- scripts/some-suite ---\n%s === 12/12 suites passed ===\n' "$TS" "$TS" > "$D/log-5011.txt"
OUT="$(run_probe "$D")"; RC=$?
check "dirty soak: emitted watchdog reap line -> ACTION REQUIRED" 5 "$RC" "$OUT"
check_body "dirty soak names the run id" "$OUT" "910"
check_never01 "dirty soak never takes 0/1" "$RC"
# early-exit: the scan stops at the first dirty run — run 911 must never be read
if grep -q 'actions/runs/911/jobs' "$D/calls.log" 2>/dev/null; then
  say "FAIL dirty soak did not early-exit — older run 911 was still inspected"
  fails=$((fails+1))
else
  say "ok   dirty soak early-exits at the first dirty run"
fi
check_stub_clean "dirty soak: stub argv all expected" "$D"

# --- Arm 3: NOT YET — two runs exist but NONE are post-merge ----------------
# Two rows so a mutant that counts a `behind` run as clean reaches CLEAN=2
# and reds here — one row is denominator-blind.
D="$(mktemp -d)"; mk_fixtures "$D"; mk_stub "$D"
cat > "$D/runs.json" <<'JSON'
{"workflow_runs":[
 {"id":920,"head_sha":"ffffffffffffffffffffffffffffffffffffffff","created_at":"2026-10-08T00:00:00Z","conclusion":"success"},
 {"id":921,"head_sha":"fafafafafafafafafafafafafafafafafafafafa","created_at":"2026-10-07T18:00:00Z","conclusion":"success"}
]}
JSON
printf '{"status":"behind"}' > "$D/compare-ffffffffffffffffffffffffffffffffffffffff.json"
printf '{"status":"behind"}' > "$D/compare-fafafafafafafafafafafafafafafafafafafafa.json"
OUT="$(run_probe "$D")"; RC=$?
check "pre-merge-only window (x2) -> NOT YET" 2 "$RC" "$OUT"
check_never01 "NOT YET never takes 0/1" "$RC"
check_stub_clean "pre-merge arm: stub argv all expected" "$D"

# --- Arm 4: NOT YET — post-merge runs that never reached the tests step -----
# Two non-qualifying rows: a counting mutant reaches CLEAN=2 and reds.
D="$(mktemp -d)"; mk_fixtures "$D"; mk_stub "$D"
cat > "$D/runs.json" <<'JSON'
{"workflow_runs":[
 {"id":930,"head_sha":"cccccccccccccccccccccccccccccccccccccccc","created_at":"2026-10-08T00:00:00Z","conclusion":"cancelled"},
 {"id":931,"head_sha":"dddddddddddddddddddddddddddddddddddddddd","created_at":"2026-10-07T18:00:00Z","conclusion":"cancelled"}
]}
JSON
printf '{"status":"ahead"}' > "$D/compare-cccccccccccccccccccccccccccccccccccccccc.json"
printf '{"status":"ahead"}' > "$D/compare-dddddddddddddddddddddddddddddddddddddddd.json"
printf '{"jobs":[{"id":5030,"name":"health-check"}]}' > "$D/jobs-930.json"
printf '{"jobs":[{"id":5031,"name":"health-check"}]}' > "$D/jobs-931.json"
printf '%s Run npm ci --ignore-scripts\n%s added 900 packages in 40s\n%s ##[error]The operation was canceled.\n' "$TS" "$TS" "$TS" > "$D/log-5030.txt"
printf '%s checkout\n%s ##[error]The operation was canceled.\n' "$TS" "$TS" > "$D/log-5031.txt"
OUT="$(run_probe "$D")"; RC=$?
check "two runs that never dispatched test-all -> excluded, NOT YET" 2 "$RC" "$OUT"
check_never01 "excluded-run NOT YET never takes 0/1" "$RC"
check_stub_clean "excluded-run arm: stub argv all expected" "$D"

# --- Arm 5: NOT YET — exactly one clean qualifying run so far ---------------
D="$(mktemp -d)"; mk_fixtures "$D"; mk_stub "$D"
cat > "$D/runs.json" <<'JSON'
{"workflow_runs":[
 {"id":940,"head_sha":"cccccccccccccccccccccccccccccccccccccccc","created_at":"2026-10-08T00:00:00Z","conclusion":"success"}
]}
JSON
printf '{"status":"ahead"}' > "$D/compare-cccccccccccccccccccccccccccccccccccccccc.json"
printf '{"jobs":[{"id":5040,"name":"health-check"}]}' > "$D/jobs-940.json"
printf '%s --- scripts/some-suite ---\n%s === 12/12 suites passed ===\n' "$TS" "$TS" > "$D/log-5040.txt"
OUT="$(run_probe "$D")"; RC=$?
check "one clean qualifying run -> NOT YET (needs 2 consecutive)" 2 "$RC" "$OUT"
check_never01 "single-clean NOT YET never takes 0/1" "$RC"
check_stub_clean "single-clean arm: stub argv all expected" "$D"

# --- Arm 6: CANNOT ESTABLISH — compare read fails ----------------------------
D="$(mktemp -d)"; mk_fixtures "$D"; mk_stub "$D"
cat > "$D/runs.json" <<'JSON'
{"workflow_runs":[
 {"id":950,"head_sha":"9999999999999999999999999999999999999999","created_at":"2026-10-08T00:00:00Z","conclusion":"success"}
]}
JSON
# no compare fixture for head 9999… — the stub exits 64, the probe must map it to 3
OUT="$(run_probe "$D")"; RC=$?
check "compare read failure -> CANNOT ESTABLISH" 3 "$RC" "$OUT"
check_never01 "CANNOT ESTABLISH never takes 0/1" "$RC"

# --- Arm 7: CANNOT ESTABLISH — GH_TOKEN unset --------------------------------
D="$(mktemp -d)"; mk_fixtures "$D"; mk_stub "$D"
OUT="$(env PATH="$D/bin:/usr/bin:/bin" FIXTURE_DIR="$D" env -u GH_TOKEN timeout 120 bash "$PROBE" 2>&1)"; RC=$?
check "GH_TOKEN unset -> CANNOT ESTABLISH" 3 "$RC" "$OUT"
check_never01 "token-less CANNOT ESTABLISH never takes 0/1" "$RC"

# --- Arm 8: xtrace refusal with a live token -> 78 ---------------------------
D="$(mktemp -d)"; mk_fixtures "$D"; mk_stub "$D"
OUT="$(env PATH="$D/bin:/usr/bin:/bin" FIXTURE_DIR="$D" GH_TOKEN="stub-token" timeout 120 bash -x "$PROBE" 2>&1)"; RC=$?
check "bash -x with GH_TOKEN set -> xtrace refusal 78" 78 "$RC" "$OUT"
check_never01 "xtrace refusal never takes 0/1" "$RC"

# --- Arm 9: diverged compare status is skipped, not counted ------------------
D="$(mktemp -d)"; mk_fixtures "$D"; mk_stub "$D"
cat > "$D/runs.json" <<'JSON'
{"workflow_runs":[
 {"id":960,"head_sha":"abababababababababababababababababababab","created_at":"2026-10-08T00:00:00Z","conclusion":"success"},
 {"id":961,"head_sha":"cdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd","created_at":"2026-10-07T18:00:00Z","conclusion":"success"}
]}
JSON
printf '{"status":"diverged"}' > "$D/compare-abababababababababababababababababababab.json"
printf '{"status":"diverged"}' > "$D/compare-cdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd.json"
OUT="$(run_probe "$D")"; RC=$?
check "diverged-only window (x2) -> NOT YET" 2 "$RC" "$OUT"
check_never01 "diverged NOT YET never takes 0/1" "$RC"
check_stub_clean "diverged arm: stub argv all expected" "$D"

# --- Arm 10: emitted 'runner died untrappably' counts as dirty ---------------
D="$(mktemp -d)"; mk_fixtures "$D"; mk_stub "$D"
cat > "$D/runs.json" <<'JSON'
{"workflow_runs":[
 {"id":970,"head_sha":"cccccccccccccccccccccccccccccccccccccccc","created_at":"2026-10-08T00:00:00Z","conclusion":"failure"}
]}
JSON
printf '{"status":"ahead"}' > "$D/compare-cccccccccccccccccccccccccccccccccccccccc.json"
printf '{"jobs":[{"id":5070,"name":"health-check"}]}' > "$D/jobs-970.json"
printf '%s --- scripts/some-suite ---\n' "$TS" > "$D/log-5070.txt"
printf '%s ERROR: runner died untrappably — reaping its in-flight suite children (#8993)\n' "$TS" >> "$D/log-5070.txt"
OUT="$(run_probe "$D")"; RC=$?
check "emitted runner-died line -> ACTION REQUIRED" 5 "$RC" "$OUT"
check_never01 "runner-died arm never takes 0/1" "$RC"
check_stub_clean "runner-died arm: stub argv all expected" "$D"

# --- Source pin: the never-0/never-1 invariant is enforced, not asserted -----
# A bare `exit 0`/`exit 1` on an unexercised path would pass every behavioral
# arm above; the pin fails on the form itself (sibling: watchdog-arm-soak-9237).
if grep -nE '^\s*exit\s+[01]\b' "$PROBE" >/dev/null; then
  say "FAIL probe source contains a bare exit 0/1 — notify-only invariant violated at source"
  fails=$((fails+1))
else
  say "ok   source pin: no bare exit 0/1 in the probe"
fi

echo ""
if [ "$fails" -eq 0 ]; then
  echo "watchdog-debounce-soak-9686.test.sh: ALL CHECKS PASSED"
else
  echo "watchdog-debounce-soak-9686.test.sh: $fails CHECK(S) FAILED"
fi
exit "$fails"
