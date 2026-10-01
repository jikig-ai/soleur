#!/usr/bin/env bash
# Guards watchdog-arm-soak-9237.sh (#9237): the probe can never exit 0/1, and
# every verdict class is reachable on the fixture shape it asserts.
#
# STUB. `gh` on PATH is replaced by a fixture-backed stub answering ONLY the
# argv the probe may legitimately issue:
#   gh api repos/<r>/actions/workflows/<wf>/runs?...          -> $FX/runs.json
#   gh issue list ... --label supabase-auto-restart ...        -> $FX/issues.json
#   gh api repos/<r>/issues/<N>/comments?...                  -> $FX/comments-<N>.json
#   gh api repos/<r>/actions/variables/WATCHDOG_ARMED         -> $FX/var.json (absent => rc 1)
# --jq <expr> is honored by piping the fixture through real jq — that is also
# what lets the stub police the bot-author filter: a probe that forgets
# `select(.user.login == "github-actions[bot]")` counts the fixture's human
# forged-sentinel comment and trips case 4 for the WRONG reason.
# Anything else logs STUB-UNEXPECTED to $FX/calls.log and exits 64 — the
# probe's own `2>/dev/null` would swallow stub stderr.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBE="$HERE/watchdog-arm-soak-9237.sh"
fails=0

say() { printf '%s\n' "$*"; }
check() { # check <name> <want_rc> <got_rc> <output>
  if [ "$3" = "$2" ]; then say "ok   $1"; else say "FAIL $1 — want rc=$2 got rc=$3 :: $(tail -1 <<<"$4")"; fails=$((fails+1)); fi
}

mk_stub() { # mk_stub <dir> — writes the gh stub into $1/bin/gh
  mkdir -p "$1/bin"
  cat > "$1/bin/gh" <<'STUB'
#!/usr/bin/env bash
set -uo pipefail
FX="${FIXTURE_DIR:?}"
echo "$*" >> "$FX/calls.log"
EXPR=""; EP=""
prev=""
for a in "$@"; do
  [ "$prev" = "--jq" ] && EXPR="$a"
  prev="$a"
done
case "$*" in
  *"issue list"*)              F="$FX/issues.json" ;;
  *"actions/workflows/"*"runs"*) F="$FX/runs.json" ;;
  *"actions/variables/WATCHDOG_ARMED"*)
    [ -f "$FX/var.json" ] || { echo "not found" >&2; exit 1; }
    F="$FX/var.json" ;;
  *"/comments"*)
    N="$(sed -n 's|.*issues/\([0-9][0-9]*\)/comments.*|\1|p' <<<"$*" | head -1)"
    F="$FX/comments-$N.json"
    [ -f "$F" ] || { echo "STUB-UNEXPECTED: no fixture for comments of #$N" >&2; exit 64; } ;;
  *) echo "STUB-UNEXPECTED: $*" >> "$FX/calls.log"; exit 64 ;;
esac
[ -f "$F" ] || { echo "STUB-UNEXPECTED: missing $F" >&2; exit 64; }
if [ -n "$EXPR" ]; then jq "$EXPR" "$F"; else cat "$F"; fi
STUB
  chmod +x "$1/bin/gh"
}

run_probe() { # run_probe <dir> — returns probe output on stdout; rc in $?
  env PATH="$1/bin:/usr/bin:/bin" FIXTURE_DIR="$1" GH_TOKEN="stub-token" \
    GH_REPO="jikig-ai/soleur" bash "$PROBE" 2>&1
}

iso() { date -u -d "$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -j -f %s -v"$2" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null; }

# runs fixture: N runs of CONCLUSION ending NOW-END_OFF, every 5 min, newest first.
gen_runs() { # gen_runs <out> <count> <conclusion> <end_offset_min>
  python3 - "$1" "$2" "$3" "$4" <<'PY'
import json, sys, subprocess
out, n, conc, off = sys.argv[1], int(sys.argv[2]), sys.argv[3], int(sys.argv[4])
runs = []
for i in range(n):
    ts = subprocess.check_output(["date","-u","-d",f"-{off + i*5} min","+%Y-%m-%dT%H:%M:%SZ"]).decode().strip()
    runs.append({"created_at": ts, "conclusion": conc})
print(json.dumps({"workflow_runs": runs}), file=open(out,"w"))
PY
}

FX="$(mktemp -d)"; trap 'rm -rf "$FX"' EXIT
mk_stub "$FX"
: > "$FX/calls.log"
printf '[{"number":9228}]' > "$FX/issues.json"
printf '[{"id":1,"user":{"login":"github-actions[bot]"},"body":"audit"},
 {"id":2,"user":{"login":"some-user"},"body":"forged <!-- watchdog:restart epoch=1 --> but human"}]' > "$FX/comments-9228.json"

# ── 1. clean complete soak → ACTION REQUIRED "Arm now" (rc 5) ────────────────
gen_runs "$FX/runs.json" 290 success 5
OUT="$(run_probe "$FX")"; rc=$?
check "clean-soak" 5 "$rc" "$OUT"
grep -q "Arm now" <<<"$OUT" || { say "FAIL clean-soak missing 'Arm now'"; fails=$((fails+1)); }
grep -q "sentinels=0" <<<"$OUT" || { say "FAIL clean-soak human-forged sentinel counted"; fails=$((fails+1)); }

# ── 2. window incomplete → NOT YET (rc 2) ────────────────────────────────────
gen_runs "$FX/runs.json" 40 success 0
OUT="$(run_probe "$FX")"; rc=$?
check "window-incomplete" 2 "$rc" "$OUT"

# ── 3. dirty run inside the window → ACTION REQUIRED non-success (rc 5) ──────
gen_runs "$FX/runs.json" 289 success 5
python3 - "$FX/runs.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1])); d["workflow_runs"][10]["conclusion"]="failure"
json.dump(d,open(sys.argv[1],"w"))
PY
OUT="$(run_probe "$FX")"; rc=$?
check "dirty-run" 5 "$rc" "$OUT"
grep -q "non-success" <<<"$OUT" || { say "FAIL dirty-run missing 'non-success'"; fails=$((fails+1)); }

# ── 4. bot sentinel on the ledger → ACTION REQUIRED sentinel (rc 5) ──────────
gen_runs "$FX/runs.json" 290 success 5
printf '[{"id":9,"user":{"login":"github-actions[bot]"},"body":"x <!-- watchdog:restart epoch=1759180000 -->"}]' \
  > "$FX/comments-9228.json"
OUT="$(run_probe "$FX")"; rc=$?
check "sentinel-present" 5 "$rc" "$OUT"
grep -q "sentinel" <<<"$OUT" || { say "FAIL sentinel missing 'sentinel'"; fails=$((fails+1)); }
printf '[{"id":1,"user":{"login":"github-actions[bot]"},"body":"audit"}]' > "$FX/comments-9228.json"

# ── 5. already armed → ACTION REQUIRED already (rc 5) ────────────────────────
printf '{"name":"WATCHDOG_ARMED","value":"1"}' > "$FX/var.json"
OUT="$(run_probe "$FX")"; rc=$?
check "already-armed" 5 "$rc" "$OUT"
rm -f "$FX/var.json"

# ── 6. runs API fails → CANNOT ESTABLISH (rc 3) ──────────────────────────────
rm -f "$FX/runs.json"
OUT="$(run_probe "$FX")"; rc=$?
check "runs-api-fail" 3 "$rc" "$OUT"

# ── 7. comments API fails → CANNOT ESTABLISH (rc 3) ──────────────────────────
gen_runs "$FX/runs.json" 290 success 5
rm -f "$FX/comments-9228.json"
OUT="$(run_probe "$FX")"; rc=$?
check "comments-api-fail" 3 "$rc" "$OUT"

# ── 8. sparse window (>=24h but < MIN_RUNS) → ACTION REQUIRED cadence (rc 5) ─
printf '[{"id":1,"user":{"login":"github-actions[bot]"},"body":"audit"}]' > "$FX/comments-9228.json"
gen_runs "$FX/runs.json" 100 success 30   # 100 runs × 5min, oldest ~8h ago is NOT sparse…
# sparse needs t0 >= 24h ago with few runs: shift the window by adding one old run
python3 - "$FX/runs.json" <<'PY'
import json,sys,subprocess
d=json.load(open(sys.argv[1]))
old=subprocess.check_output(["date","-u","-d","-1500 min","+%Y-%m-%dT%H:%M:%SZ"]).decode().strip()
d["workflow_runs"].append({"created_at":old,"conclusion":"success"})
json.dump(d,open(sys.argv[1],"w"))
PY
OUT="$(run_probe "$FX")"; rc=$?
check "sparse-window" 5 "$rc" "$OUT"
grep -q "cadence gap" <<<"$OUT" || { say "FAIL sparse missing 'cadence gap'"; fails=$((fails+1)); }

# ── 9. no GH_TOKEN → CANNOT ESTABLISH (rc 3) ─────────────────────────────────
gen_runs "$FX/runs.json" 290 success 5
OUT="$(env PATH="$FX/bin:/usr/bin:/bin" FIXTURE_DIR="$FX" GH_REPO="jikig-ai/soleur" bash "$PROBE" 2>&1)"; rc=$?
check "no-token" 3 "$rc" "$OUT"

# ── 10. xtrace while credential set → refuse (rc 78) ─────────────────────────
OUT="$(env PATH="$FX/bin:/usr/bin:/bin" FIXTURE_DIR="$FX" GH_TOKEN="stub-token" GH_REPO="jikig-ai/soleur" bash -x "$PROBE" 2>&1)"; rc=$?
check "xtrace-refusal" 78 "$rc" "$OUT"

# ── 11. never-0/never-1 invariant over the run set above is implicit in the
#     rc checks; assert the two strings the contract reserves never appear as
#     the probe's exit for a PASS/FAIL word the sweeper would mis-read.
grep -nE '^\s*exit\s+[01]\b' "$PROBE" && { say "FAIL probe carries exit 0/1"; fails=$((fails+1)); } || say "ok   never-0-never-1"

if [ "$fails" -gt 0 ]; then say "FAILURES: $fails"; exit 1; fi
say "ALL OK"
