#!/usr/bin/env bash
# shellcheck disable=SC2329,SC2015,SC2016,SC2034  # row functions are dispatched indirectly; A && B || why is the assertion idiom; jq programs are single-quoted on purpose; some fixture variables are read by sub-shell rows
# Suite for plugins/soleur/scripts/ci-head-verdict.sh -- Guard 2 of the S3 plan (#9728,
# knowledge-base/project/plans/2026-10-09-ci-s3-draft-pr-light-checks-plan.md): the one resolver every
# reader of a PR head's CI state goes through (`verdict`, `wait-ready-run`, `ready-count`).
#
# THE SEAM. `gh` is a PATH stub that answers ONLY the requests the SUT is expected to make, keyed on the
# FULL argv (real flags only: `api -i`, `api graphql -F/-f`, `api --paginate --slurp`), and refuses anything
# else with exit 64 after logging `STUB-MISS <argv>` (2026-09-25-gh-stub-must-mirror-real-cli-flags.md).
# Every row asserts the log holds no STUB-MISS, so a SUT that asks the wrong endpoint cannot turn a stub
# refusal into the exit 3 an error row wants. `sleep` is a PATH stub that logs its argument. The clock is
# injected (CI_HEAD_VERDICT_NOW) or read from the stub's `Date:` header; the local clock is never used.
#
# THE FIXTURES are synthesized (cq-test-fixtures-synthesized-only): one ready event at T, a head SHA, flat
# lists of `test` check runs and `ci.yml` pull_request runs, edited per row with jq. `pull_requests[]` is
# EMPTY on every run row by default (92% of real runs), so a resolver that joins through it cannot pass.
#
# MUTATION ROWS (M-rows) copy the SUT, apply ONE edit (asserted to have landed), and require that the named
# row FAILS against the mutant AND that the mutant exhibits the specific defect. A mutant that crashes is
# not a kill: the harness flags any bash-level error in a mutant's stderr (syntax error, command not found,
# unbound variable) as UNRESOLVED, and two control mutants prove it can report both a survivor and a crash. The anti-vacuity floor and the instrument self-test report through printf + exit, never
# through the pass()/fail() pair they backstop (scripts/guard-vacuity-floor.test.sh).
export TMPDIR="${TMPDIR:-/var/tmp}"
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAL_SUT="$SCRIPT_DIR/../scripts/ci-head-verdict.sh"
SUT="$REAL_SUT"

passes=0; fails=0; ASSERTED=0; ROW_BAD=0; FAILED=(); MODE=normal

pass() { passes=$((passes + 1)); echo "  PASS: $1"; }
fail() { fails=$((fails + 1)); FAILED+=("$1"); echo "  FAIL: $1" >&2; }

# Instrument self-test: both verdict helpers must record before any row is trusted.
_iv_p="$passes"; _iv_f="$fails"; _iv_n="${#FAILED[@]}"
{ pass "self-test"; fail "self-test"; } >/dev/null 2>&1
if [[ "$passes" -ne $((_iv_p + 1)) || "$fails" -ne $((_iv_f + 1)) || "${#FAILED[@]}" -ne $((_iv_n + 1)) ]]; then
  printf '[FATAL] instrument self-test: the verdict helpers did not both record\n' >&2; exit 1
fi
passes=0; fails=0; FAILED=(); ASSERTED=0

[[ -f "$REAL_SUT" ]] || { echo "[FATAL] SUT not found at $REAL_SUT" >&2; exit 1; }
for tool in jq python3 date timeout; do
  command -v "$tool" >/dev/null || { echo "[FATAL] $tool required" >&2; exit 1; }
done
TIMEOUT_BIN="$(command -v timeout)"

SANDBOX="$(mktemp -d "$TMPDIR/ci-head-verdict.XXXXXXXX")" || { echo "[FATAL] mktemp failed" >&2; exit 1; }
case "$SANDBOX" in /*) : ;; *) echo "[FATAL] sandbox is not absolute" >&2; exit 1 ;; esac
trap 'rm -rf "$SANDBOX"' EXIT

PR=4242
H=3c1f0c8d9b7a4e5f6a7b8c9d0e1f2a3b4c5d6e7f
OTHER_H=9999999999999999999999999999999999999999
T_ISO="2031-03-04T05:06:07Z"
T_EPOCH=$(date -u -d "$T_ISO" +%s)
iso_at() { date -u -d "@$((T_EPOCH + $1))" +%Y-%m-%dT%H:%M:%SZ; }   # <seconds relative to T>
http_date() { date -u -d "@$((T_EPOCH + $1))" '+%a, %d %b %Y %H:%M:%S GMT'; }

# ── the stubs ───────────────────────────────────────────────────────────────────────────────
BIN="$SANDBOX/bin"; mkdir -p "$BIN"
cat > "$BIN/gh" <<'GH'
#!/usr/bin/env bash
# Per-poll files: <name>.<poll>.json wins over <name>.json; the poll counter advances on the PR read.
args="$*"
printf '%s GH_REPO=%s\n' "$args" "${GH_REPO:-}" >> "$STUB_LOG"
if [[ -n "${STUB_EMPTY:-}" ]]; then exit 0; fi
poll=$(cat "$FX/.polls" 2>/dev/null || echo 0)
pick() { if [[ -f "$FX/$1.$poll.json" ]]; then cat "$FX/$1.$poll.json"; else cat "$FX/$1.json"; fi; }
failing() { [[ -f "$FX/$1.fail" || -f "$FX/$1.fail.$poll" ]]; }
case "$args" in
  "api -i repos/{owner}/{repo}/pulls/$STUB_PR")
    poll=$((poll + 1)); echo "$poll" > "$FX/.polls"
    failing pr && { echo "stub: pr read failed" >&2; exit 1; }
    printf 'HTTP/2.0 200 OK\r\n'
    if [[ -f "$FX/date" ]]; then printf 'Date: %s\r\n' "$(cat "$FX/date")"; fi
    printf 'Content-Type: application/json; charset=utf-8\r\n\r\n'
    pick pr ;;
  "api graphql -F owner={owner} -F name={repo} -F number=$STUB_PR -f query="*)
    case "$args" in *READY_FOR_REVIEW_EVENT*"last: 100"*|*"last: 100"*READY_FOR_REVIEW_EVENT*) : ;; *)
      printf 'STUB-MISS %s\n' "$args" >> "$STUB_LOG"; echo "stub: graphql query is not the ready-event timeline read" >&2; exit 64 ;; esac
    failing ready && { echo "stub: graphql failed" >&2; exit 1; }
    pick ready ;;
  "api --paginate --slurp repos/{owner}/{repo}/commits/$STUB_H/check-runs?check_name=test&per_page=100&filter=all")
    failing checkruns && { echo "stub: check-runs failed" >&2; exit 1; }
    f="$FX/checkruns.json"; [[ -f "$FX/checkruns.$poll.json" ]] && f="$FX/checkruns.$poll.json"
    if [[ -f "$FX/checkruns.raw" ]]; then cat "$FX/checkruns.raw"; else jq -c '[{total_count: length, check_runs: .}]' "$f"; fi ;;
  "api --paginate --slurp repos/{owner}/{repo}/actions/workflows/ci.yml/runs?event=pull_request&head_sha=$STUB_H&per_page=100")
    failing runs && { echo "stub: runs failed" >&2; exit 1; }
    f="$FX/runs.json"; [[ -f "$FX/runs.$poll.json" ]] && f="$FX/runs.$poll.json"
    if [[ -f "$FX/runs.raw" ]]; then cat "$FX/runs.raw"; else jq -c '[{total_count: length, workflow_runs: .}]' "$f"; fi ;;
  "api -H Accept: application/vnd.github.raw+json repos/{owner}/{repo}/contents/.github/workflows/ci.yml")
    failing ciyml && { echo "stub: ci.yml read failed" >&2; exit 1; }
    if [[ -f "$FX/ciyml.404" ]]; then echo "gh: Not Found (HTTP 404)" >&2; exit 1; fi
    cat "$FX/ciyml.yml" ;;
  *) printf 'STUB-MISS %s\n' "$args" >> "$STUB_LOG"; echo "stub: unexpected gh argv: $args" >&2; exit 64 ;;
esac
GH
cat > "$BIN/sleep" <<'SLP'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FX/sleeps"
SLP
chmod +x "$BIN/gh" "$BIN/sleep"

# ── row plumbing ────────────────────────────────────────────────────────────────────────────
jqf() { # <dir> <file> <filter>
  local t; t=$(mktemp "$SANDBOX/jqf.XXXXXX")
  jq -c "$3" "$1/$2" > "$t" && mv "$t" "$1/$2" || { echo "[FATAL] jq edit failed: $3" >&2; exit 1; }
}
mkrow() { # <name> -> prints the dir: a non-draft PR at H, ONE ready event at T, no rows, no runs, clock T+600
  local d="$SANDBOX/rows/$1"; rm -rf "$d"; mkdir -p "$d"
  printf '{"state":"open","draft":false,"head":{"sha":"%s"}}\n' "$H" > "$d/pr.json"
  setready "$d" "$T_ISO"
  echo '[]' > "$d/checkruns.json"; echo '[]' > "$d/runs.json"
  printf 'jobs:\n  detect-changes:\n    runs-on: ubuntu-latest\n  draft-light:\n    runs-on: ubuntu-latest\n' > "$d/ciyml.yml"
  http_date 600 > "$d/date"
  printf '%s' "$d"
}
setready() { # <dir> <iso...>  (oldest first; none = never readied)
  local d="$1"; shift
  local nodes; nodes=$(printf '%s\n' "$@" | jq -R '{createdAt: .}' | jq -sc '.')
  [[ $# -eq 0 ]] && nodes='[]'
  jq -nc --argjson n "$nodes" '{data:{repository:{pullRequest:{timelineItems:{pageInfo:{hasPreviousPage:false},nodes:$n}}}}}' > "$d/ready.json"
}
setdraft() { jqf "$1" pr.json ".draft = $2"; }
setnow() { http_date "$2" > "$1/date"; }                   # <dir> <seconds after T>
addtest() { # <dir> <id> <status> <conclusion|null> <run-id> [app]
  jqf "$1" checkruns.json ". + [{id: $2, name: \"test\", head_sha: \"$H\", status: \"$3\", conclusion: $( [[ "$4" == null ]] && echo null || echo "\"$4\"" ), app: {id: ${6:-15368}}, details_url: \"https://example.invalid/o/r/actions/runs/$5/job/$2\"}]"
}
addrun() { # <dir> <id> <status> <conclusion|null> <created-offset-from-T> [head-sha]
  jqf "$1" runs.json ". + [{id: $2, name: \"CI\", event: \"pull_request\", head_sha: \"${6:-$H}\", status: \"$3\", conclusion: $( [[ "$4" == null ]] && echo null || echo "\"$4\"" ), created_at: \"$(iso_at "$5")\", run_attempt: 1, pull_requests: []}]"
}

OUT=""; ERR=""; RC=""
vrun() { # <dir> <sut-args...>
  local d="$1"; shift
  : > "$d/log"; rm -f "$d/.polls" "$d/sleeps"
  local -a envv=(FX="$d" STUB_LOG="$d/log" STUB_PR="$PR" STUB_H="$H" PATH="$BIN:$PATH" CI_HEAD_VERDICT_POLL_SECONDS=0)
  env -u CI_HEAD_VERDICT_NOW -u GH_REPO "${envv[@]}" ${VRUN_ENV:+$VRUN_ENV} "$TIMEOUT_BIN" 30 bash "$SUT" "$@" > "$d/out" 2> "$d/err"
  RC=$?; OUT=$(cat "$d/out"); ERR=$(cat "$d/err")
  # A bash-level error out of a MUTANT is a crash, not a defect the rows detected: flag it for the harness.
  if [[ "$MODE" == mutant ]] && grep -qE 'syntax error|command not found|unbound variable|unexpected EOF|bad substitution' <<<"$ERR"; then
    : > "$SANDBOX/crashed"
  fi
}

why() { [[ "$MODE" == normal ]] && echo "      why: $*" >&2; return 1; }
# ok <label-for-why> <command...> : count the assertion at the CALL SITE, independent of its verdict
ok() { ASSERTED=$((ASSERTED + 1)); local label="$1"; shift
  if "$@"; then return 0; fi
  ROW_BAD=$((ROW_BAD + 1)); [[ "$MODE" == normal ]] && echo "      assertion failed: $label" >&2; return 1; }
eq() { [[ "$1" == "$2" ]] || why "got '$1', want '$2'"; }
marker_of() { grep '^SOLEUR_CI_HEAD_VERDICT ' <<<"$OUT" | tail -1; }
state_is() { # <state> [reason] [run]
  local m; m=$(marker_of)
  [[ "$m" == SOLEUR_CI_HEAD_VERDICT\ state="$1"\ pr="$PR"\ sha=*\ run=${3:-*}\ reason=${2:-*} ]] \
    || why "marker is '$m', want state=$1 reason=${2:-*} run=${3:-*} (rc=$RC err=$ERR)"
}
sha_is() { [[ "$(marker_of)" == *" sha=$1 "* ]] || why "marker sha is not $1: $(marker_of)"; }
rc_is() { [[ "$RC" == "$1" ]] || why "rc=$RC, want $1 (out: $OUT; err: $ERR)"; }
nomiss() { ! grep -q '^STUB-MISS' "$1/log" || why "stub refused: $(grep '^STUB-MISS' "$1/log" | head -1)"; }
called() { grep -Fq -- "$2" "$1/log" || why "stub log lacks request: $2"; }
notcalled() { ! grep -Fq -- "$2" "$1/log" || why "unexpected request: $2"; }
polls() { [[ "$(cat "$1/.polls" 2>/dev/null || echo 0)" == "$2" ]] || why "polls=$(cat "$1/.polls" 2>/dev/null), want $2"; }
nsleeps() { local n=0; [[ -f "$1/sleeps" ]] && n=$(wc -l < "$1/sleeps"); [[ "$n" == "$2" ]] || why "sleeps=$n, want $2"; }
one_marker() { [[ "$(grep -c '^SOLEUR_CI_HEAD_VERDICT ' <<<"$OUT")" == 1 && "$(tail -1 <<<"$OUT")" == SOLEUR_CI_HEAD_VERDICT\ * ]] || why "stdout is not exactly one marker as its last line: $OUT"; }
CLOSED='n/a full-decided pending-full no-run stalled awaiting-approval'
not_closed() { local s; s=$(sed -n 's/^SOLEUR_CI_HEAD_VERDICT state=\([^ ]*\) .*/\1/p' <<<"$OUT"); [[ -n "$s" && " $CLOSED " != *" $s "* ]] || why "state '$s' must be outside the closed set"; }
in_closed() { local s; s=$(sed -n 's/^SOLEUR_CI_HEAD_VERDICT state=\([^ ]*\) .*/\1/p' <<<"$OUT"); [[ " $CLOSED " == *" $s "* ]] || why "state '$s' is not in the closed set"; }
verdict_state() { sed -n 's/^SOLEUR_CI_HEAD_VERDICT state=\([^ ]*\) .*/\1/p' <<<"$OUT"; }
wmarker() { grep '^SOLEUR_CI_WAIT_READY_RUN ' <<<"$OUT" | tail -1; }
w_is() { # <result> <reason> [run]
  local m; m=$(wmarker)
  [[ "$m" == SOLEUR_CI_WAIT_READY_RUN\ result="$1"\ pr="$PR"\ sha=*\ run=${3:-*}\ reason="$2" ]] \
    || why "wait marker is '$m', want result=$1 reason=$2 run=${3:-*} (rc=$RC err=$ERR)"
}

# ── Guard 2 rows: verdict ───────────────────────────────────────────────────────────────────
# V1: never readied (bot-opened PR with synthetic rows and no pull_request run, read after 80 minutes) is n/a.
row_V1() { local d; d=$(mkrow V1); setready "$d"; addtest "$d" 11 completed success 7; setnow "$d" 4800
  vrun "$d" verdict "$PR"
  ok V1.rc rc_is 0; ok V1.state state_is n/a never-ready none; ok V1.nomiss nomiss "$d"
  ok V1.one one_marker
  ok V1.no-row-read notcalled "$d" check-runs; ok V1.no-run-read notcalled "$d" ci.yml/runs; }
# V2: a PR that is a draft NOW is n/a whatever its history (readers change nothing for a draft).
row_V2() { local d; d=$(mkrow V2); setdraft "$d" true; vrun "$d" verdict "$PR"
  ok V2.rc rc_is 0; ok V2.state state_is n/a draft none; ok V2.nomiss nomiss "$d"; ok V2.no-run-read notcalled "$d" ci.yml/runs; }
# V3: readied before S3 merged, green full draft-era test, read after 80 minutes: full-decided, never stalled.
row_V3() { local d; d=$(mkrow V3); addtest "$d" 11 completed success 7; setnow "$d" 4800; vrun "$d" verdict "$PR"
  ok V3.rc rc_is 0; ok V3.state state_is full-decided green-test 7; ok V3.sha sha_is "$H"; ok V3.nomiss nomiss "$d"; }
# V4: the ready run is in flight, the newest test row is the red draft-era one: pending-full, run named.
row_V4() { local d s; for s in in_progress queued waiting requested pending; do d=$(mkrow "V4-$s")
    addtest "$d" 11 completed failure 6; addrun "$d" 6 completed failure -900; addrun "$d" 8 "$s" null 2
    vrun "$d" verdict "$PR"
    ok V4.rc rc_is 0; ok V4.state state_is pending-full run-in-progress 8; ok V4.nomiss nomiss "$d"; done; }
# V5: ready run still in flight 130 minutes after the ready event: stalled, and the 120-minute boundary is exact
# (a healthy slow run is the declared 73-minute path plus a ~14-minute p90 queue wait: 87 minutes, still pending).
row_V5() { local d; d=$(mkrow V5); addtest "$d" 11 completed failure 6; addrun "$d" 8 in_progress null 2
  setnow "$d" 7800; vrun "$d" verdict "$PR"
  ok V5.rc rc_is 0; ok V5.state state_is stalled undecided-after-120m 8
  setnow "$d" 5220; vrun "$d" verdict "$PR"; ok V5.87m-slow-healthy-run-still-pending state_is pending-full run-in-progress 8
  setnow "$d" 7200; vrun "$d" verdict "$PR"; ok V5.at-120m-exactly-not-yet state_is pending-full run-in-progress 8
  setnow "$d" 7201; vrun "$d" verdict "$PR"; ok V5.120m-plus-1s state_is stalled undecided-after-120m 8; }
# V6: no run created at or after the ready event: no-run, then stalled after 120 minutes; the draft-era run is ignored.
row_V6() { local d; d=$(mkrow V6); addtest "$d" 11 completed failure 6; addrun "$d" 6 completed failure -900
  vrun "$d" verdict "$PR"
  ok V6.state state_is no-run no-run-after-ready none; ok V6.rc rc_is 0
  setnow "$d" 7800; vrun "$d" verdict "$PR"; ok V6.stalled state_is stalled undecided-after-120m none; }
# V7: a completed run created after the ready event decides, whatever its conclusion; its own rows are authoritative.
row_V7() { local d c want
  for c in success:run-success failure:run-failure timed_out:run-timed-out; do d=$(mkrow "V7-${c%%:*}")
    addtest "$d" 11 completed failure 6; addrun "$d" 8 completed "${c%%:*}" 2; setnow "$d" 4800
    vrun "$d" verdict "$PR"; want="${c##*:}"
    ok "V7.$c" state_is full-decided "$want" 8; done; }
# V8: a fork run waiting for approval is awaiting-approval, and 130 minutes does not turn it into stalled.
row_V8() { local d; d=$(mkrow V8); addtest "$d" 11 completed failure 6; addrun "$d" 8 completed action_required 2
  vrun "$d" verdict "$PR"; ok V8.state state_is awaiting-approval run-action-required 8
  setnow "$d" 7800; vrun "$d" verdict "$PR"; ok V8.not-overridden state_is awaiting-approval run-action-required 8; }
# V9: a cancelled, skipped, stale, neutral, startup_failure or unknown-conclusion newest run fails closed (no-run);
# 130 minutes later it is stalled; never full-decided and never pending-full forever.
row_V9() { local d c
  for c in cancelled skipped stale neutral startup_failure weird; do d=$(mkrow "V9-$c")
    addtest "$d" 11 completed failure 6; addrun "$d" 8 completed "$c" 2
    vrun "$d" verdict "$PR"; ok "V9.$c.no-run" state_is no-run "run-$(tr '_' '-' <<<"$c" | sed 's/^weird$/unknown-conclusion/')" 8
    setnow "$d" 7800; vrun "$d" verdict "$PR"; ok "V9.$c.stalled" state_is stalled undecided-after-120m 8; done
  d=$(mkrow V9-null); addtest "$d" 11 completed failure 6; addrun "$d" 8 completed null 2; vrun "$d" verdict "$PR"
  ok V9.null-conclusion state_is no-run run-unknown-conclusion 8; }
# V10: NO skew allowance: a run created at T or later is kept, a run created even 1 s before T is not (a draft push's
# light run created just before the ready call must never be adopted as the ready run; the ready run was measured +2 s..+3 s).
row_V10() { local d off want
  for off in -1:no-run -5:no-run -6:no-run 0:pending-full 1:pending-full; do d=$(mkrow "V10${off%%:*}")
    addtest "$d" 11 completed failure 6; addrun "$d" 8 in_progress null "${off%%:*}"
    vrun "$d" verdict "$PR"; want="${off##*:}"
    ok "V10.$off" state_is "$want"; done; }
# V11: the lookup is by head_sha on the workflow's run list, NEVER through pull_requests[]: rows whose
# pull_requests[] is empty (every default row) resolve, and a row whose pull_requests[] names ANOTHER PR still counts.
row_V11() { local d; d=$(mkrow V11); addtest "$d" 11 completed failure 6; addrun "$d" 8 in_progress null 2
  jqf "$d" runs.json 'map(.pull_requests = [{"number": 1}])'
  vrun "$d" verdict "$PR"; ok V11.other-pr-in-pull_requests state_is pending-full run-in-progress 8
  ok V11.queried-by-head-sha called "$d" "head_sha=$H"
  jqf "$d" runs.json 'map(.pull_requests = [])'; vrun "$d" verdict "$PR"; ok V11.empty-pull_requests state_is pending-full run-in-progress 8; }
# V12: the NEWEST kept run at THIS head decides: a newer run at another head is ignored, an older in-flight
# kept run does not outvote a newer completed one, and the id tiebreak is numeric.
row_V12() { local d; d=$(mkrow V12); addtest "$d" 11 completed failure 6
  addrun "$d" 8 in_progress null 2; addrun "$d" 9 completed failure 100; addrun "$d" 77 in_progress null 500 "$OTHER_H"
  vrun "$d" verdict "$PR"; ok V12.newest-at-this-head state_is full-decided run-failure 9
  d=$(mkrow V12b); addtest "$d" 11 completed failure 6; addrun "$d" 9 completed failure 100; addrun "$d" 10 in_progress null 100
  vrun "$d" verdict "$PR"; ok V12.numeric-id-tiebreak state_is pending-full run-in-progress 10
  # the real API lists newest first: the tie is inserted in DESCENDING id order and the higher id must still win
  d=$(mkrow V12c); addtest "$d" 11 completed failure 6; addrun "$d" 10 in_progress null 100; addrun "$d" 9 completed failure 100
  vrun "$d" verdict "$PR"; ok V12.descending-insert-order-tiebreak state_is pending-full run-in-progress 10
  # created_at orders before id: the lower id created LATER wins
  d=$(mkrow V12d); addtest "$d" 11 completed failure 6; addrun "$d" 50 completed failure 2; addrun "$d" 9 in_progress null 100
  vrun "$d" verdict "$PR"; ok V12.time-orders-before-id state_is pending-full run-in-progress 9; }
# V13: a manual re-run of a pre-T run completes red AFTER the ready run completed green: the newest test row is
# red and belongs to another run; the resolver reports the DECIDING run (the ready run) so a reader can name the row stale.
row_V13() { local d; d=$(mkrow V13); addtest "$d" 11 completed success 8; addtest "$d" 12 completed failure 6
  addrun "$d" 6 completed failure -900; addrun "$d" 8 completed success 2; setnow "$d" 4800
  vrun "$d" verdict "$PR"; ok V13.deciding-run-is-the-ready-run state_is full-decided run-success 8; }
# V14: only a test row from the github-actions app, named exactly `test`, counts as the green short-circuit; the
# newest row is chosen by numeric id.
row_V14() { local d; d=$(mkrow V14); addtest "$d" 12 completed failure 6; addtest "$d" 13 completed success 7 99999; addrun "$d" 8 in_progress null 2
  vrun "$d" verdict "$PR"; ok V14.foreign-app-green-ignored state_is pending-full run-in-progress 8
  d=$(mkrow V14b); addtest "$d" 9 completed failure 6; addtest "$d" 10 completed success 8; vrun "$d" verdict "$PR"
  ok V14.numeric-newest-is-green state_is full-decided green-test 8
  d=$(mkrow V14c); addtest "$d" 10 completed failure 6; addtest "$d" 9 completed success 8; addrun "$d" 8 in_progress null 2; vrun "$d" verdict "$PR"
  ok V14.numeric-newest-is-red state_is pending-full run-in-progress 8
  d=$(mkrow V14d); jqf "$d" checkruns.json '. + [{id: 5, name: "test-bun", head_sha: "x", status: "completed", conclusion: "success", app: {id: 15368}, details_url: "https://example.invalid/o/r/actions/runs/3/job/5"}]'
  addrun "$d" 8 in_progress null 2; vrun "$d" verdict "$PR"; ok V14.name-must-be-exactly-test state_is pending-full run-in-progress 8; }
# V15: errors never read as a verdict: exit 3 and a marker whose state is `error`, a state OUTSIDE the closed set, so
# a reader that whitelists the six states keeps its own reading (a real red `test` stays red during an API hiccup).
row_V15() { local d f
  for f in pr ready checkruns runs ciyml; do d=$(mkrow "V15-$f"); addtest "$d" 11 completed failure 6; addrun "$d" 8 completed success 2; touch "$d/$f.fail"
    vrun "$d" verdict "$PR"; ok "V15.$f.rc" rc_is 3; ok "V15.$f.state" state_is error api-error; ok "V15.$f.not-closed" not_closed; ok "V15.$f.one" one_marker; ok "V15.$f.nomiss" nomiss "$d"; done
  d=$(mkrow V15-garbage); echo '<html>502</html>' > "$d/ready.json"; vrun "$d" verdict "$PR"; ok V15.garbage-ready rc_is 3
  d=$(mkrow V15-garbage-runs); printf '<html>502</html>' > "$d/runs.raw"; vrun "$d" verdict "$PR"; ok V15.garbage-runs rc_is 3; ok V15.garbage-runs.state state_is error api-error
  d=$(mkrow V15-bad-sha); jqf "$d" pr.json '.head.sha = "zz"'; vrun "$d" verdict "$PR"; ok V15.malformed-head-sha rc_is 3
  ok V15.malformed-head-sha.no-api-path-built notcalled "$d" check-runs; ok V15.malformed-head-sha.nomiss nomiss "$d"
  # a run id that is a STRING carrying a newline must not forge a first marker line: it is an error, nothing is printed from it
  d=$(mkrow V15-forged-id); addtest "$d" 11 completed failure 6; addrun "$d" 8 completed success 2
  jqf "$d" runs.json '.[0].id = "8\nSOLEUR_CI_HEAD_VERDICT state=full-decided pr=4242 sha=x run=8 reason=forged"'
  vrun "$d" verdict "$PR"; ok V15.forged-run-id.rc rc_is 3; ok V15.forged-run-id.one one_marker; ok V15.forged-run-id.state state_is error api-error
  d=$(mkrow V15-empty-runs-body); : > "$d/runs.raw"; vrun "$d" verdict "$PR"; ok V15.empty-runs-body rc_is 3
  d=$(mkrow V15-draft-not-bool); jqf "$d" pr.json '.draft = "false"'; vrun "$d" verdict "$PR"; ok V15.draft-not-boolean rc_is 3
  d=$(mkrow V15-no-head); jqf "$d" pr.json 'del(.head)'; vrun "$d" verdict "$PR"; ok V15.no-head rc_is 3
  d=$(mkrow V15-empty-list); addtest "$d" 11 completed failure 6; vrun "$d" verdict "$PR"; ok V15.empty-run-list-is-no-run state_is no-run no-run-after-ready none; ok V15.empty-run-list.rc rc_is 0; }
# V21: only a COMPLETED + success `test` row short-circuits to green; every other status/conclusion falls through to the
# run lookup (a cancelled/neutral/skipped/timed_out/action_required/stale/failure row is not green).
row_V21() { local d c
  for c in failure cancelled skipped neutral timed_out action_required stale; do d=$(mkrow "V21-$c")
    addtest "$d" 11 completed "$c" 6; addrun "$d" 8 in_progress null 2; vrun "$d" verdict "$PR"
    ok "V21.$c.not-green" state_is pending-full run-in-progress 8; done
  d=$(mkrow V21-pending); addtest "$d" 11 in_progress null 6; addrun "$d" 8 in_progress null 2; vrun "$d" verdict "$PR"; ok V21.in-progress-row-not-green state_is pending-full run-in-progress 8; }
# V22: applicability. A repo whose default-branch ci.yml has no `draft-light` job, or has no ci.yml at all (404), never
# produces a ready run: verdict is n/a (no run or check read), and the wait answers ok at once (arming = today's flow).
row_V22() { local d
  d=$(mkrow V22-404); touch "$d/ciyml.404"; addtest "$d" 11 completed failure 6; setnow "$d" 7800; vrun "$d" verdict "$PR"
  ok V22.404.rc rc_is 0; ok V22.404.state state_is n/a no-draft-light none; ok V22.404.no-run-read notcalled "$d" ci.yml/runs; ok V22.404.no-row-read notcalled "$d" check-runs
  d=$(mkrow V22-nojob); printf 'jobs:\n  test:\n    runs-on: ubuntu-latest\n' > "$d/ciyml.yml"; addtest "$d" 11 completed failure 6; vrun "$d" verdict "$PR"
  ok V22.no-job.state state_is n/a no-draft-light none; ok V22.no-job.nomiss nomiss "$d"
  d=$(mkrow V22-wait404); touch "$d/ciyml.404"; setready "$d" "$(iso_at -3600)" "$T_ISO"
  vrun "$d" wait-ready-run "$PR" --before-count 1; ok V22.wait.rc rc_is 0; ok V22.wait.marker w_is ok not-applicable none; ok V22.wait.no-polling polls "$d" 0; ok V22.wait.nomiss nomiss "$d"
  d=$(mkrow V22-waitjob); setready "$d" "$(iso_at -3600)" "$T_ISO"; addrun "$d" 8 queued null 2; vrun "$d" wait-ready-run "$PR" --before-count 1
  ok V22.wait-applicable.marker w_is ok run-created 8
  d=$(mkrow V22-waiterr); touch "$d/ciyml.fail"; vrun "$d" wait-ready-run "$PR" --before-count 1; ok V22.wait-read-error.rc rc_is 3; ok V22.wait-read-error.marker w_is fail api-error none; }
# V16: every gh call returning an EMPTY body must fail the resolver, not pass it (harness row a).
row_V16() { local d; d=$(mkrow V16); addrun "$d" 8 completed success 2
  VRUN_ENV="STUB_EMPTY=1" vrun "$d" verdict "$PR"; ok V16.verdict-rc rc_is 3; ok V16.verdict-not-decided state_is error api-error
  VRUN_ENV="STUB_EMPTY=1" vrun "$d" wait-ready-run "$PR" --before-count 0 --timeout 20; ok V16.wait-rc rc_is 3; ok V16.wait-fails w_is fail api-error none
  VRUN_ENV="STUB_EMPTY=1" vrun "$d" ready-count "$PR"; ok V16.count-rc rc_is 3; ok V16.count-no-stdout eq "$OUT" ""; }
# V17: the clock is the SERVER's. The Date header decides when no override is injected, and a missing server time is an error.
row_V17() { local d; d=$(mkrow V17); addtest "$d" 11 completed failure 6; addrun "$d" 8 in_progress null 2; setnow "$d" 7800
  vrun "$d" verdict "$PR"; ok V17.date-header-130m state_is stalled undecided-after-120m 8
  setnow "$d" 300; vrun "$d" verdict "$PR"; ok V17.date-header-5m state_is pending-full run-in-progress 8
  rm -f "$d/date"; vrun "$d" verdict "$PR"; ok V17.no-server-time-rc rc_is 3; ok V17.no-server-time-state state_is error no-server-time
  # The injected clock wins over the header (test seam), and the real local clock never matters: T is in the past by years.
  setnow "$d" 300; VRUN_ENV="CI_HEAD_VERDICT_NOW=$(iso_at 7800)" vrun "$d" verdict "$PR"; ok V17.injected-clock state_is stalled undecided-after-120m 8
  VRUN_ENV="CI_HEAD_VERDICT_NOW=not-a-date" vrun "$d" verdict "$PR"; ok V17.bad-injected-clock rc_is 3; }
# V18: the output contract: exactly one marker, last, closed state set, over every conclusion the API can return.
row_V18() { local d c
  for c in success failure timed_out action_required cancelled skipped stale neutral startup_failure weird null; do d=$(mkrow "V18-$c")
    addtest "$d" 11 completed failure 6; addrun "$d" 8 completed "$c" 2; vrun "$d" verdict "$PR"
    ok "V18.$c.one" one_marker; ok "V18.$c.closed" in_closed; ok "V18.$c.rc" rc_is 0; done; }
# V19: usage errors exit 2 with no stdout marker and no gh call; --repo exports GH_REPO and rejects URLs.
row_V19() { local d a; d=$(mkrow V19)
  for a in "" "verdict" "verdict abc" "verdict 7 8" "bogus 7" "verdict 7 --bogus" "wait-ready-run 7" "wait-ready-run 7 --before-count x" \
           "wait-ready-run 7 --before-count 1 --timeout 0" "wait-ready-run 7 --before-count 1 --timeout x" "verdict 7 --repo https://x/y" "verdict 7 --repo a" "ready-count" "ready-count 7 8"; do
    # shellcheck disable=SC2086
    vrun "$d" $a; ok "V19.[$a].rc" rc_is 2; ok "V19.[$a].nocall" eq "$(cat "$d/log")" ""; ok "V19.[$a].no-marker" eq "$OUT" ""; done
  addrun "$d" 8 in_progress null 2; vrun "$d" verdict "$PR" --repo acme/widgets
  ok V19.repo-flag-exports-GH_REPO called "$d" "GH_REPO=acme/widgets"; ok V19.repo-flag.rc rc_is 0; }

# ── Guard 2 rows: wait-ready-run ────────────────────────────────────────────────────────────
# W1: the caller read K=1 before `gh pr ready`; the new event (count 2) is visible, the PR is not a draft and a
# run exists at the head: exit 0, one marker.
row_W1() { local d; d=$(mkrow W1); setready "$d" "$(iso_at -3600)" "$T_ISO"; addrun "$d" 6 completed failure -900; addrun "$d" 8 queued null 2
  vrun "$d" wait-ready-run "$PR" --before-count 1
  ok W1.rc rc_is 0; ok W1.marker w_is ok run-created 8; ok W1.sha eq "$(wmarker | sed -n 's/.* sha=\([^ ]*\) .*/\1/p')" "$H"; ok W1.nomiss nomiss "$d"; ok W1.one-poll polls "$d" 1; ok W1.no-sleep nsleeps "$d" 0
  ok W1.marker-is-the-last-stdout-line test "$(tail -1 <<<"$OUT" | cut -d' ' -f1)" = SOLEUR_CI_WAIT_READY_RUN; }
# W2: timeline read-after-write lag: the count never exceeds K, so the PREVIOUS ready event is never taken as T,
# even though a run exists at that old event's time. Fail closed with no-ready-event after the whole budget.
row_W2() { local d; d=$(mkrow W2); setready "$d" "$T_ISO"; addrun "$d" 8 in_progress null 2
  vrun "$d" wait-ready-run "$PR" --before-count 1 --timeout 30
  ok W2.rc rc_is 1; ok W2.marker w_is fail no-ready-event none; ok W2.polls polls "$d" 3; ok W2.sleeps nsleeps "$d" 2; }
# W3: the count exceeds K but the live read still says draft: keep waiting, fail closed.
row_W3() { local d; d=$(mkrow W3); setready "$d" "$(iso_at -3600)" "$T_ISO"; setdraft "$d" true; addrun "$d" 8 in_progress null 2
  vrun "$d" wait-ready-run "$PR" --before-count 1 --timeout 20; ok W3.rc rc_is 1; ok W3.marker w_is fail no-ready-event none; ok W3.polls polls "$d" 2; }
# W4: lag then arrival: poll 1 count == K, poll 2 count K+1 and not draft with a run: success on poll 2, T is the NEW event.
row_W4() { local d; d=$(mkrow W4); setready "$d" "$(iso_at -3600)"
  jq -c '.' "$d/ready.json" > "$d/ready.1.json"
  setready "$d" "$(iso_at -3600)" "$T_ISO"; cp "$d/ready.json" "$d/ready.2.json"
  addrun "$d" 6 completed failure -900; addrun "$d" 8 queued null 2
  vrun "$d" wait-ready-run "$PR" --before-count 1; ok W4.rc rc_is 0; ok W4.marker w_is ok run-created 8; ok W4.polls polls "$d" 2; ok W4.one-sleep nsleeps "$d" 1; }
# W5: a ready event exists but only a PRE-T draft run does (the ready run was never created): no-run after the budget.
row_W5() { local d; d=$(mkrow W5); setready "$d" "$(iso_at -3600)" "$T_ISO"; addrun "$d" 6 completed failure -900
  vrun "$d" wait-ready-run "$PR" --before-count 1 --timeout 30; ok W5.rc rc_is 1; ok W5.marker w_is fail no-run none; ok W5.polls polls "$d" 3; ok W5.not-armable nomiss "$d"
  ok W5.marker-is-the-last-stdout-line test "$(tail -1 <<<"$OUT" | cut -d' ' -f1)" = SOLEUR_CI_WAIT_READY_RUN; }
# W6: the run appears on poll 3: success then.
row_W6() { local d; d=$(mkrow W6); setready "$d" "$(iso_at -3600)" "$T_ISO"; addrun "$d" 6 completed failure -900
  cp "$d/runs.json" "$d/runs.1.json"; cp "$d/runs.json" "$d/runs.2.json"; addrun "$d" 8 in_progress null 3
  vrun "$d" wait-ready-run "$PR" --before-count 1; ok W6.rc rc_is 0; ok W6.marker w_is ok run-created 8; ok W6.polls polls "$d" 3; }
# W7: an action_required run is awaiting-approval: fail at once (waiting never clears it), with the reason.
row_W7() { local d; d=$(mkrow W7); setready "$d" "$(iso_at -3600)" "$T_ISO"; addrun "$d" 8 completed action_required 2
  vrun "$d" wait-ready-run "$PR" --before-count 1; ok W7.rc rc_is 1; ok W7.marker w_is fail awaiting-approval 8; ok W7.one-poll polls "$d" 1; }
# W8: a cancelled newest run is not a run that will decide: keep polling; a successor on poll 2 passes, none fails no-run.
row_W8() { local d; d=$(mkrow W8); setready "$d" "$(iso_at -3600)" "$T_ISO"; addrun "$d" 8 completed cancelled 2
  vrun "$d" wait-ready-run "$PR" --before-count 1 --timeout 20; ok W8.rc rc_is 1; ok W8.marker w_is fail no-run 8; ok W8.polls polls "$d" 2
  cp "$d/runs.json" "$d/runs.1.json"; addrun "$d" 9 queued null 4
  vrun "$d" wait-ready-run "$PR" --before-count 1; ok W8.successor-rc rc_is 0; ok W8.successor w_is ok run-created 9; ok W8.successor-polls polls "$d" 2; }
# W9: a run that already decided (any of success, failure, timed_out) is a run: the wait only proves creation.
row_W9() { local d c; for c in success failure timed_out; do d=$(mkrow "W9-$c"); setready "$d" "$(iso_at -3600)" "$T_ISO"; addrun "$d" 8 completed "$c" 2
    vrun "$d" wait-ready-run "$PR" --before-count 1; ok "W9.$c" rc_is 0; ok "W9.$c.marker" w_is ok run-created 8; done; }
# W10: the budget is counted in 10-second polls: default 300 s is 30 polls, 25 s is 3 polls, 5 s is 1 poll; a one-poll
# budget never sleeps.
row_W10() { local d; d=$(mkrow W10); setready "$d" "$T_ISO"
  vrun "$d" wait-ready-run "$PR" --before-count 1; ok W10.default-300s polls "$d" 30; ok W10.default.sleeps nsleeps "$d" 29
  vrun "$d" wait-ready-run "$PR" --before-count 1 --timeout 25; ok W10.25s polls "$d" 3; ok W10.sleep-arg eq "$(head -1 "$d/sleeps")" 0
  vrun "$d" wait-ready-run "$PR" --before-count 1 --timeout 5; ok W10.5s polls "$d" 1; ok W10.5s.no-sleep nsleeps "$d" 0; }
# W11: every poll erroring (PR read, timeline read, run list) is a fail-closed exit 3 with reason api-error: the ready state
# is UNKNOWN, which must never read as "no ready event" / "no run" (the caller would `gh pr ready --undo` a PR that is fine).
row_W11() { local d f; for f in pr ready runs; do d=$(mkrow "W11-$f"); setready "$d" "$(iso_at -3600)" "$T_ISO"; addrun "$d" 8 queued null 2; touch "$d/$f.fail"
    vrun "$d" wait-ready-run "$PR" --before-count 1 --timeout 20; ok "W11.$f.rc" rc_is 3; ok "W11.$f.nomiss" nomiss "$d"
    ok "W11.$f.reason" w_is fail api-error; done
  # a transient error on poll 1 followed by a healthy poll 2 is a success: only the LAST poll decides
  d=$(mkrow W11-transient); setready "$d" "$(iso_at -3600)" "$T_ISO"; addrun "$d" 8 queued null 2; touch "$d/pr.fail.1"
  vrun "$d" wait-ready-run "$PR" --before-count 1 --timeout 20; ok W11.transient-then-ok.rc rc_is 0; ok W11.transient-then-ok w_is ok run-created 8
  # a healthy last poll with nothing to find stays rc 1 (a measured negative), not 3
  d=$(mkrow W11-measured); setready "$d" "$(iso_at -3600)" "$T_ISO"; addrun "$d" 6 completed failure -900; touch "$d/pr.fail.1"
  vrun "$d" wait-ready-run "$PR" --before-count 1 --timeout 20; ok W11.measured-negative.rc rc_is 1; ok W11.measured-negative w_is fail no-run none; }
# W12: the wait uses the NEWEST event's time as T: with events at T-2h and T, a run 3 s after the old event is pre-T, a
# run 1 s before T is pre-T too (no skew allowance), and a run AT T is the ready run.
row_W12() { local d; d=$(mkrow W12); setready "$d" "$(iso_at -7200)" "$T_ISO"; addrun "$d" 6 in_progress null -7197
  vrun "$d" wait-ready-run "$PR" --before-count 1 --timeout 10; ok W12.rc rc_is 1; ok W12.marker w_is fail no-run none
  addrun "$d" 7 in_progress null -1; vrun "$d" wait-ready-run "$PR" --before-count 1 --timeout 10; ok W12.1s-before-T-dropped rc_is 1
  addrun "$d" 8 in_progress null 0; vrun "$d" wait-ready-run "$PR" --before-count 1 --timeout 10; ok W12.at-T-kept rc_is 0
  d=$(mkrow W12b); setready "$d" "$(iso_at -7200)" "$T_ISO"; addrun "$d" 6 in_progress null -6
  vrun "$d" wait-ready-run "$PR" --before-count 1 --timeout 10; ok W12.6s-before-dropped rc_is 1; }
# W13: more ready events than the timeline page holds cannot be counted: fail closed (exit 3, reason api-error), and
# ready-count exits 3 without printing a number.
row_W13() { local d; d=$(mkrow W13); setready "$d" "$(iso_at -3600)" "$T_ISO"; jqf "$d" ready.json '.data.repository.pullRequest.timelineItems.pageInfo.hasPreviousPage = true'
  addrun "$d" 8 queued null 2
  vrun "$d" wait-ready-run "$PR" --before-count 1 --timeout 10; ok W13.wait-rc rc_is 3; ok W13.wait-marker w_is fail api-error none
  vrun "$d" ready-count "$PR"; ok W13.count-rc rc_is 3; ok W13.count-no-number eq "$OUT" ""; }
# W14: ready-count prints the number of ReadyForReviewEvents (NOT the timeline totalCount) and nothing else.
row_W14() { local d; d=$(mkrow W14); setready "$d" "$(iso_at -3600)" "$(iso_at -1800)" "$T_ISO"
  vrun "$d" ready-count "$PR"; ok W14.rc rc_is 0; ok W14.count eq "$OUT" 3; ok W14.nomiss nomiss "$d"
  setready "$d"; vrun "$d" ready-count "$PR"; ok W14.zero eq "$OUT" 0
  touch "$d/ready.fail"; vrun "$d" ready-count "$PR"; ok W14.error-rc rc_is 3; ok W14.error-no-stdout eq "$OUT" ""; }

# ── reader-bypass lint (Guard 2 last row) ───────────────────────────────────────────────────
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
# Every SCRIPT under plugins/soleur and scripts/ that reads a PR's CI rows for a verdict, and every SKILL.md that carries a
# `required_failed=` poll, must reach the resolver through a CALL (a comment that names it does not count: the scripts are
# comment-stripped first). Exempt, each with its reason:
#   battery-owed.sh        reads check rows directly; a draft red test is NOT-GREEN (OWED), covered by its own rows
#   check-red-on-main.sh   attributes a failing check to main; it grades nothing
#   ci-head-verdict.sh     the resolver itself
#   audit-bot-codeql-coverage.sh, codeql-main-alert-gate.sh   CodeQL rows only, never `test`
#   merge-queue-cla-verify.sh                                  CLA contexts only, never `test`
# What this census cannot see (named, not hidden): apps/**, .github/**, .claude/hooks (none grade `test`; the web-platform
# route has its own draft filter and the ruleset is the merge authority), and prose-only recipes under references/.
LINT_EXEMPT='plugins/soleur/skills/ship/scripts/battery-owed.sh plugins/soleur/scripts/check-red-on-main.sh plugins/soleur/scripts/ci-head-verdict.sh scripts/audit-bot-codeql-coverage.sh scripts/codeql-main-alert-gate.sh scripts/merge-queue-cla-verify.sh'
calls_resolver() { local body; body=$(grep -v '^[[:space:]]*#' "$1"); grep -q 'ci-head-verdict' <<<"$body"; }
row_L1() { local f bad="" hits skills
  hits=$(cd "$REPO_ROOT" && { find plugins/soleur -name '*.sh' ! -name '*.test.sh' -print0 | xargs -0 grep -lE 'required_failed|statusCheckRollup|gh pr checks|check-runs\?'
                              grep -lE 'required_failed|statusCheckRollup|gh pr checks|check-runs\?' scripts/*.sh; } 2>/dev/null | grep -vE '\.test\.sh$' | sort -u)
  skills=$(cd "$REPO_ROOT" && grep -lE 'required_failed=' plugins/soleur/skills/*/SKILL.md 2>/dev/null | sort)
  ok L1.script-census-nonempty test -n "$hits"
  ok L1.census-sees-the-known-readers eq "$(for f in plugins/soleur/scripts/monitor-pr-checks.sh plugins/soleur/scripts/admin-merge-ready.sh plugins/soleur/skills/drain-prs/scripts/triage-prs.sh; do grep -c -x "$f" <<<"$hits"; done | tr '\n' ' ')" "1 1 1 "
  ok L1.skill-census-has-both-polls test "$(wc -w <<<"$skills")" -ge 2
  for f in $hits; do
    [[ " $LINT_EXEMPT " == *" $f "* ]] && continue
    calls_resolver "$REPO_ROOT/$f" || bad="$bad $f"
  done
  for f in $skills; do grep -q 'ci-head-verdict' "$REPO_ROOT/$f" || bad="$bad $f"; done
  ok "L1.every-reader-reaches-the-resolver:${bad:-none}" test -z "$bad"
  # known-positive: a script whose only mention is a comment must be reported
  local probe="$SANDBOX/comment-only.sh"; printf '#!/usr/bin/env bash\n# reads statusCheckRollup, see ci-head-verdict.sh\ngh pr checks 1\n' > "$probe"
  ok L1.comment-only-mention-is-not-a-call test "$(calls_resolver "$probe" && echo yes || echo no)" = no
  printf '#!/usr/bin/env bash\nbash "$ROOT/ci-head-verdict.sh" verdict 1\n' > "$probe"
  ok L1.a-real-call-is-seen test "$(calls_resolver "$probe" && echo yes || echo no)" = yes
  for f in ship merge-pr drain-prs; do
    ok "L1.$f-gates-arming-on-wait-ready-run" grep -q 'wait-ready-run' "$REPO_ROOT/plugins/soleur/skills/$f/SKILL.md"
  done; }

# ── mutation rows ───────────────────────────────────────────────────────────────────────────
MUT_PASS=0; MUT_RUN=0; VERDICTS_EXPECTED=0
# mutant_run <id> <python-old> <python-new> <kill-row...>: apply ONE edit, run the kill rows against the mutant. Sets
# MUT_SURV (kill rows still green), MUT_CRASH (1 when the mutant raised a bash-level error: syntax error, command not
# found, unbound variable) and MUT_LANDED (0 when the edit did not land exactly once or changed nothing).
MUT_SURV=""; MUT_CRASH=0; MUT_LANDED=1
mutant_run() {
  local id="$1" old="$2" new="$3"; shift 3
  local m="$SANDBOX/mut-$id.sh" r
  MUT_SURV=""; MUT_CRASH=0; MUT_LANDED=1; rm -f "$SANDBOX/crashed"
  cp "$REAL_SUT" "$m"
  if ! OLD="$old" NEW="$new" python3 -c '
import os, sys
p = sys.argv[1]; s = open(p).read(); o = os.environ["OLD"]
if s.count(o) != 1: sys.exit(1)
open(p, "w").write(s.replace(o, os.environ["NEW"]))' "$m"; then MUT_LANDED=0; return 0; fi
  if cmp -s "$m" "$REAL_SUT"; then MUT_LANDED=0; return 0; fi
  bash -n "$m" 2>/dev/null || MUT_CRASH=1
  for r in "$@"; do
    if ( SUT="$m"; MODE=mutant; ROW_BAD=0; "$r" >/dev/null 2>&1; exit $((ROW_BAD > 0 ? 1 : 0)) ); then MUT_SURV="$MUT_SURV $r"; fi
  done
  [[ -f "$SANDBOX/crashed" ]] && MUT_CRASH=1
  return 0
}
# mutant <id> <python-old> <python-new> <kill-row...> ; every kill row must FAIL against the mutant, and the mutant must
# not have crashed (a crash reddens every row and proves nothing). ONE verdict per mutant.
mutant() {
  local id="$1"
  VERDICTS_EXPECTED=$((VERDICTS_EXPECTED + 1)); ASSERTED=$((ASSERTED + 1)); MUT_RUN=$((MUT_RUN + 1))
  mutant_run "$@"
  if [[ "$MUT_LANDED" -eq 0 ]]; then fail "$id (mutation did not land exactly once, or changed nothing)"; return 0; fi
  if [[ "$MUT_CRASH" -eq 1 ]]; then fail "$id (mutant crashed: not a kill)"; return 0; fi
  if [[ -z "$MUT_SURV" ]]; then MUT_PASS=$((MUT_PASS + 1)); pass "$id (rows ${*:4} red against the mutant)"
  else fail "$id (still green against the mutant:$MUT_SURV)"; fi
}
# Harness controls: the helper must be able to report BOTH a survivor and a crash, or its green verdicts mean nothing.
mutant_selftest() {
  VERDICTS_EXPECTED=$((VERDICTS_EXPECTED + 1)); ASSERTED=$((ASSERTED + 2))
  mutant_run SELF-EQUIV 'readonly MARKER="SOLEUR_CI_HEAD_VERDICT"' "readonly MARKER='SOLEUR_CI_HEAD_VERDICT'" row_V3 row_V15
  local surv_ok=0 crash_ok=0
  [[ "$MUT_LANDED" -eq 1 && -n "$MUT_SURV" && "$MUT_CRASH" -eq 0 ]] && surv_ok=1
  mutant_run SELF-CRASH 'set -uo pipefail' 'set -uo pipefail; readonly MARKER=(' row_V3
  [[ "$MUT_LANDED" -eq 1 && "$MUT_CRASH" -eq 1 ]] && crash_ok=1
  if [[ "$surv_ok" -eq 1 && "$crash_ok" -eq 1 ]]; then pass "harness controls (an equivalent mutant survives, a crashing mutant is flagged)"
  else fail "harness controls (survivor reported: $surv_ok, crash flagged: $crash_ok)"; fi
}

run_row() { # <fn> <label>
  VERDICTS_EXPECTED=$((VERDICTS_EXPECTED + 1))
  ROW_BAD=0; MODE=normal
  "$1" || true
  if [[ "$ROW_BAD" -eq 0 ]]; then pass "$2"; else fail "$2"; fi
}

echo "== ci-head-verdict.sh: verdict =="
run_row row_V1 "V1  never readied (synthetic rows, no run, 80 min): n/a, no run lookup"
run_row row_V2 "V2  draft now: n/a"
run_row row_V3 "V3  readied before S3 with a green full test, 80 min: full-decided, never stalled"
run_row row_V4 "V4  ready run in flight (every in-flight status): pending-full"
run_row row_V5 "V5  in flight 130 min: stalled; the 120-minute boundary is exact"
run_row row_V6 "V6  no ready run: no-run, then stalled; the draft-era run is ignored"
run_row row_V7 "V7  completed ready run decides (success, failure, timed_out)"
run_row row_V8 "V8  action_required: awaiting-approval, not overridden by stalled"
run_row row_V9 "V9  cancelled/skipped/stale/neutral/startup_failure/unknown: no-run, then stalled"
run_row row_V10 "V10 no skew allowance: kept at T and later, dropped at -1s"
run_row row_V11 "V11 lookup by head_sha, never pull_requests[]"
run_row row_V12 "V12 newest run at THIS head decides"
run_row row_V13 "V13 manual re-run of a pre-T run: the deciding run is the ready run"
run_row row_V14 "V14 green short-circuit: github-actions app, exact name, numeric newest"
run_row row_V15 "V15 errors fail closed (exit 3, state=error outside the closed set, never a decision)"
run_row row_V16 "V16 an empty gh body fails every subcommand"
run_row row_V17 "V17 the clock is the server's (Date header / injected), never local"
run_row row_V18 "V18 one marker, last, closed state set, over every conclusion"
run_row row_V19 "V19 usage errors exit 2 with no gh call; --repo exports GH_REPO"
run_row row_V21 "V21 only a completed+success test row short-circuits to green"
run_row row_V22 "V22 a repo without the draft-light mechanism: n/a, wait is ok at once"
echo "== ci-head-verdict.sh: wait-ready-run / ready-count =="
run_row row_W1 "W1  event visible, not draft, run exists: exit 0"
run_row row_W2 "W2  timeline lag never takes the previous event as T"
run_row row_W3 "W3  count above K but still draft: waits, fails closed"
run_row row_W4 "W4  lag then arrival: success on the second poll"
run_row row_W5 "W5  only a pre-T run: no-run after the budget"
run_row row_W6 "W6  run appears on poll 3"
run_row row_W7 "W7  action_required: awaiting-approval at once"
run_row row_W8 "W8  cancelled newest run: keeps polling, successor passes"
run_row row_W9 "W9  a decided run is still a run"
run_row row_W10 "W10 budget counted in 10 s polls (default 300 s)"
run_row row_W11 "W11 erroring polls: api-error exit 3, never a measured negative"
run_row row_W12 "W12 newest event is T; no skew allowance"
run_row row_W13 "W13 uncountable timeline fails closed (api-error)"
run_row row_W14 "W14 ready-count counts ReadyForReviewEvents"
echo "== reader-bypass lint =="
run_row row_L1 "L1  every reader of a PR's CI state reaches the resolver"

echo "== mutation rows =="
mutant M1  'select(.head_sha == $h and .event == "pull_request")' 'select(.head_sha == $h and .event == "pull_request" and ([.pull_requests[]?.number] | index(4242)) != null)' row_V11 row_V4
mutant M2  'read_newest_run "$PR_SHA" "$t_epoch" || fail_api' 'read_newest_run "$PR_SHA" "$((t_epoch - 5))" || fail_api' row_V10
mutant M3  'read_newest_run "$PR_SHA" "$t_epoch" || { echo' 'read_newest_run "$PR_SHA" "$((t_epoch - 5))" || { echo' row_W12
mutant M4  'STALL_MINUTES=120' 'STALL_MINUTES=7500' row_V5 row_V6
mutant M5  'STALL_MINUTES=120' 'STALL_MINUTES=75' row_V5
mutant M6  'cancelled|skipped|stale|neutral|startup_failure) echo "no-run' 'cancelled|skipped|stale|neutral|startup_failure) echo "full-decided' row_V9
mutant M7  'timed_out) echo "full-decided' 'timed_out) echo "pending-full' row_V7
mutant M8  'action_required) echo "awaiting-approval' 'action_required) echo "pending-full' row_V8 row_W7
mutant M9  'st=stalled' 'st=$st' row_V5 row_V6
mutant M10 'completed) :' 'completed) return 1' row_V7
mutant M11 '"$READY_COUNT" -gt "$BEFORE"' '"$READY_COUNT" -ge "$BEFORE"' row_W2 row_W4
mutant M12 'DRAFT" == false' 'DRAFT" == false || true' row_W3
mutant M13 'NOW_EPOCH=$(server_now)' 'NOW_EPOCH=$(date -u +%s)' row_V5 row_V17
mutant M14 'reason="${2:-api-error}"' 'reason=none' row_V15
mutant M15 'fail_api() {' 'fail_api() { echo SOLEUR_CI_HEAD_VERDICT state=full-decided; exit 0' row_V15 row_V16
mutant M16 'emit full-decided "$TEST_RUN" green-test' 'emit no-run "$TEST_RUN" green-test' row_V3 row_V14
mutant M17 ".pageInfo.hasPreviousPage' \"\$WORK/ready.json\")\"" ".pageInfo.hasPreviousPageX' \"\$WORK/ready.json\")\"" row_W13
mutant M18 '.app.id == 15368' '.app.id != null' row_V14
mutant M19 'state=error pr=%s' 'state=no-run pr=%s' row_V15 row_V16
mutant M20 '[[ "$APPLICABLE" == 1 ]] || emit n/a "" no-draft-light' ':' row_V22
mutant M21 '(( WAIT_API_ERR == 1 ))' '(( WAIT_API_ERR == 7 ))' row_W11 row_W13
mutant M22 '[[ -z "$RUN_ID" || "$RUN_ID" =~ ^[0-9]+$ ]]' ':' row_V15
mutant M23 "HTTP 404|Not Found" "HTTP 4040" row_V22
mutant M24 '%S GMT")' '%S GMTX")' row_V17
mutant M25 '"$TEST_CONCLUSION" == success' '"$TEST_CONCLUSION" != failure' row_V21
mutant M26 'sort_by([.ts, .id])' 'sort_by(.ts)' row_V12
mutant M27 'sort_by([.ts, .id])' 'sort_by(.id)' row_V12
mutant M28 ' and (.head.sha | test("^[0-9a-f]{40}$"))' '' row_V15
mutant M29 'WAIT_API_ERR=0
  if [[ "$READY_COUNT"' 'WAIT_API_ERR=1
  if [[ "$READY_COUNT"' row_W2
mutant_selftest

# ── the floor: every row counted, every verdict accounted for ──────────────────────────────
# Reported through printf + exit, never through pass()/fail() (they are what it backstops).
MIN_ASSERTIONS=336
if [[ "$ASSERTED" -lt "$MIN_ASSERTIONS" ]]; then
  printf '[FATAL] anti-vacuity floor: only %s assertions ran, floor is %s\n' "$ASSERTED" "$MIN_ASSERTIONS" >&2; exit 1
fi
if [[ $((passes + fails)) -ne "$VERDICTS_EXPECTED" ]]; then
  printf '[FATAL] accounting: %s verdicts recorded for %s rows and mutants\n' "$((passes + fails))" "$VERDICTS_EXPECTED" >&2; exit 1
fi
MIN_MUTANTS=29
if [[ "$MUT_RUN" -lt "$MIN_MUTANTS" ]]; then
  printf '[FATAL] mutation floor: only %s mutants ran, floor is %s\n' "$MUT_RUN" "$MIN_MUTANTS" >&2; exit 1
fi

echo ""
echo "ci-head-verdict.test.sh: $passes passed, $fails failed ($ASSERTED assertions, $MUT_PASS/$MUT_RUN mutants killed)"
if [[ "$fails" -gt 0 ]]; then printf '  failed: %s\n' "${FAILED[@]}" >&2; exit 1; fi
exit 0
