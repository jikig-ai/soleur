#!/usr/bin/env bash
# shellcheck disable=SC2329,SC2015,SC2016,SC2034  # row functions are dispatched indirectly; A && B || why is the assertion idiom; jq programs are single-quoted on purpose; some fixture variables are read by sub-shell rows
# Suite for plugins/soleur/scripts/ci-head-verdict.sh -- Guard 2 of the S3 plan (#9728,
# knowledge-base/project/plans/archive/20261013-062704-2026-10-09-ci-s3-draft-pr-light-checks-plan.md): the one resolver every
# reader of a PR head's CI state goes through (`verdict`, `wait-ready-run`, `ready-count`), plus Guard 3 (#9927): the read-only
# `required` required-context set check (rows R1-R14 and RE1-RE6).
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
REAL_SLEEP="$(PATH=/usr/bin:/bin command -v sleep)"   # the PATH `sleep` is a stub in every row; R13 needs a child that really takes time
[[ -n "$REAL_SLEEP" ]] || { echo "[FATAL] sleep required" >&2; exit 1; }

assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}
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
  "api --paginate --slurp repos/{owner}/{repo}/commits/$STUB_H/check-suites?per_page=100")
    failing suites && { echo "stub: check-suites failed" >&2; exit 1; }
    if [[ -f "$FX/suites.raw" ]]; then cat "$FX/suites.raw"
    elif [[ -f "$FX/suites.paged" ]]; then jq -c '[.[] | {total_count: 1, check_suites: [.]}]' "$FX/suites.json"   # one suite per page, as --paginate --slurp emits
    else jq -c '[{total_count: length, check_suites: .}]' "$FX/suites.json"; fi ;;
  "api -H Accept: application/vnd.github.raw+json repos/{owner}/{repo}/contents/.github/workflows/ci.yml")
    failing ciyml && { echo "stub: ci.yml read failed" >&2; exit 1; }
    if [[ -f "$FX/ciyml.404" ]]; then echo "gh: Not Found (HTTP 404)" >&2; exit 1; fi
    cat "$FX/ciyml.yml" ;;
  "api --paginate --slurp repos/{owner}/{repo}/actions/runs?head_sha=$STUB_H&per_page=100")
    # `required` recovery: every workflow's runs at the head (pull_request_target included). A `run rerun` argv is NOT served: the catch-all refuses it.
    failing aruns && { echo "stub: actions runs failed" >&2; exit 1; }
    if [[ -f "$FX/aruns.raw" ]]; then cat "$FX/aruns.raw"; else jq -c '[{total_count: length, workflow_runs: .}]' "$FX/aruns.json"; fi ;;
  "pr view $STUB_PR --json state,headRefOid,baseRefName,changedFiles")
    failing prview && { echo "stub: pr view failed" >&2; exit 1; }
    cat "$FX/prview.json" ;;
  "api --paginate --slurp repos/{owner}/{repo}/pulls/$STUB_PR/files?per_page=100")
    jq -c '[.]' "$FX/prfiles.json" ;;
  "api --paginate --slurp repos/{owner}/{repo}/rules/branches/main")
    jq -c '[.]' "$FX/rules.json" ;;
  "api --paginate --slurp repos/{owner}/{repo}/commits/$STUB_H/check-runs?per_page=100&filter=all")
    jq -c '[{total_count: length, check_runs: .}]' "$FX/rcheckruns.json" ;;
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
  # DEFAULT check suite: ONE suite that predates the ready event (the head existed before T), so a no-run row keeps the
  # clock at T and every pre-existing stalled row is unchanged. `setsuites` REPLACES this file, never appends to it.
  setsuites "$d" -3600
  printf '%s' "$d"
}
setsuites() { # <dir> <seconds-relative-to-T>...  REPLACES the head's check suites (no offsets = an empty list)
  local d="$1"; shift
  local o list='[]'
  assert_fixture_dir "$d"
  for o in "$@"; do
    list=$(jq -c --arg h "$H" --arg c "$(iso_at "$o")" '. + [{id: (length + 1), head_sha: $h, created_at: $c, app: {slug: "github-actions"}}]' <<<"$list")
  done
  printf '%s\n' "$list" > "$d/suites.json"
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
  ok V1.no-row-read notcalled "$d" check-runs; ok V1.no-run-read notcalled "$d" ci.yml/runs; ok V1.no-suite-read notcalled "$d" check-suites; }
# V2: a PR that is a draft NOW is n/a whatever its history (readers change nothing for a draft).
row_V2() { local d; d=$(mkrow V2); setdraft "$d" true; vrun "$d" verdict "$PR"
  ok V2.rc rc_is 0; ok V2.state state_is n/a draft none; ok V2.nomiss nomiss "$d"; ok V2.no-run-read notcalled "$d" ci.yml/runs; ok V2.no-suite-read notcalled "$d" check-suites; }
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
  # The run is the anchor (it was created at T+2), so the boundary is the RUN's age: 7202 is exactly 120 minutes old.
  setnow "$d" 7202; vrun "$d" verdict "$PR"; ok V5.at-120m-exactly-not-yet state_is pending-full run-in-progress 8
  setnow "$d" 7203; vrun "$d" verdict "$PR"; ok V5.120m-plus-1s state_is stalled undecided-after-120m 8; }
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
    ok "V7.$c" state_is full-decided "$want" 8
    setnow "$d" 7800; vrun "$d" verdict "$PR"; ok "V7.$c.still-decided-after-120m" state_is full-decided "$want" 8; done; }
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
# V23: a CONFLICTING PR (mergeable_state dirty) has no pull_request run by construction: no-run reason=conflicting, never
# stalled (an undo/ready cannot help it); a clean-merging PR in the same state still stalls; a run that exists still decides.
row_V23() { local d; d=$(mkrow V23); addtest "$d" 11 completed failure 6; jqf "$d" pr.json '.mergeable_state = "dirty"'; setnow "$d" 7800
  vrun "$d" verdict "$PR"; ok V23.dirty-no-run state_is no-run conflicting none; ok V23.dirty.rc rc_is 0
  d=$(mkrow V23b); addtest "$d" 11 completed failure 6; jqf "$d" pr.json '.mergeable_state = "clean"'; setnow "$d" 7800
  vrun "$d" verdict "$PR"; ok V23.clean-no-run-still-stalls state_is stalled undecided-after-120m none
  d=$(mkrow V23c); addtest "$d" 11 completed failure 6; addrun "$d" 8 in_progress null 2; jqf "$d" pr.json '.mergeable_state = "dirty"'; setnow "$d" 7800
  vrun "$d" verdict "$PR"; ok V23.dirty-but-a-run-exists-still-stalls state_is stalled undecided-after-120m 8
  d=$(mkrow V23d); addtest "$d" 11 completed failure 6; jqf "$d" pr.json '.mergeable_state = 7'; setnow "$d" 7800
  vrun "$d" verdict "$PR"; ok V23.non-string-mergeable-state-is-ignored state_is stalled undecided-after-120m none
  # a dirty PR whose ready run was CANCELLED is not the "no run can ever appear" case: it still stalls
  d=$(mkrow V23e); addtest "$d" 11 completed failure 6; addrun "$d" 8 completed cancelled 2; jqf "$d" pr.json '.mergeable_state = "dirty"'; setnow "$d" 7800
  vrun "$d" verdict "$PR"; ok V23.dirty-with-a-cancelled-run-still-stalls state_is stalled undecided-after-120m 8; }
# V24: the stall clock starts at max(ready event T, the kept run's own created_at). A head pushed long after T, whose run
# is young, is NOT stalled; the boundary is exactly 120 minutes of the RUN's age (strict).
row_V24() { local d; d=$(mkrow V24); addtest "$d" 11 completed failure 6; addrun "$d" 8 in_progress null 7500; setnow "$d" 7560
  vrun "$d" verdict "$PR"; ok V24.fresh-push-young-run-is-pending state_is pending-full run-in-progress 8; ok V24.rc rc_is 0; ok V24.nomiss nomiss "$d"
  setnow "$d" 14700; vrun "$d" verdict "$PR"; ok V24.run-age-exactly-120m-not-yet state_is pending-full run-in-progress 8
  setnow "$d" 14701; vrun "$d" verdict "$PR"; ok V24.run-age-120m-plus-1s-stalled state_is stalled undecided-after-120m 8
  d=$(mkrow V24b); addtest "$d" 11 completed failure 6; addrun "$d" 8 completed cancelled 7500; setnow "$d" 7560
  vrun "$d" verdict "$PR"; ok V24.cancelled-young-run-is-no-run state_is no-run run-cancelled 8
  setnow "$d" 14700; vrun "$d" verdict "$PR"; ok V24.cancelled-boundary-not-yet state_is no-run run-cancelled 8
  setnow "$d" 14701; vrun "$d" verdict "$PR"; ok V24.cancelled-boundary-stalled state_is stalled undecided-after-120m 8
  # two kept runs with different created_at: the NEWEST decides, and the clock is its own created_at, not the older run's
  d=$(mkrow V24c); addtest "$d" 11 completed failure 6; addrun "$d" 8 completed cancelled 2; addrun "$d" 9 in_progress null 7500; setnow "$d" 7560
  vrun "$d" verdict "$PR"; ok V24.newest-of-two-kept-runs-decides state_is pending-full run-in-progress 9
  setnow "$d" 14701; vrun "$d" verdict "$PR"; ok V24.newest-of-two-clock-is-the-newest-runs-age state_is stalled undecided-after-120m 9; }
# V25: no kept run yet: the clock starts at the head's EARLIEST check suite when that is later than T; a head whose suites
# predate T keeps the clock at T (the old behaviour).
row_V25() { local d; d=$(mkrow V25); addtest "$d" 11 completed failure 6; setsuites "$d" 7500; setnow "$d" 7560
  vrun "$d" verdict "$PR"; ok V25.fresh-push-no-run-yet state_is no-run no-run-after-ready none; ok V25.rc rc_is 0; ok V25.nomiss nomiss "$d"
  setnow "$d" 14700; vrun "$d" verdict "$PR"; ok V25.suite-age-exactly-120m-not-yet state_is no-run no-run-after-ready none
  setnow "$d" 14701; vrun "$d" verdict "$PR"; ok V25.suite-age-120m-plus-1s-stalled state_is stalled undecided-after-120m none
  # earliest of several suites, not the latest: a MAX anchor would be 6801 s old here and read pending
  d=$(mkrow V25b); addtest "$d" 11 completed failure 6; setsuites "$d" 7900 7500 7700; setnow "$d" 14701   # newest first as the real API lists them, earliest in the MIDDLE so first and last differ from min
  vrun "$d" verdict "$PR"; ok V25.earliest-suite-wins state_is stalled undecided-after-120m none
  # a head whose suites predate T (the default) keeps the clock at T: exactly as before the fix
  d=$(mkrow V25c); addtest "$d" 11 completed failure 6; setnow "$d" 7201
  vrun "$d" verdict "$PR"; ok V25.old-suites-keep-the-clock-at-T state_is stalled undecided-after-120m none
  # suites that both predate T (listed newest first): the T gate carries the verdict, so the head is stalled once T is 120m old
  d=$(mkrow V25d); addtest "$d" 11 completed failure 6; setsuites "$d" -3600 -9000; setnow "$d" 7201
  vrun "$d" verdict "$PR"; ok V25.suites-before-T-stay-stalled state_is stalled undecided-after-120m none
  # --paginate --slurp yields one array per page: the earliest suite on page 2 must still be found
  d=$(mkrow V25e); addtest "$d" 11 completed failure 6; setsuites "$d" 7900 7500 7700; touch "$d/suites.paged"; setnow "$d" 14701   # three pages, earliest on the middle one
  vrun "$d" verdict "$PR"; ok V25.earliest-suite-on-the-second-page-wins state_is stalled undecided-after-120m none
  setnow "$d" 14700; vrun "$d" verdict "$PR"; ok V25.paged-boundary-not-yet state_is no-run no-run-after-ready none; }
# V26: a failed, malformed or empty read of the head's check suites, with no kept run and T old, is state=error (exit 3),
# never a member of the closed set and never a guess.
row_V26() { local d k
  for k in fail html notarray nullts garbage otherhead preepoch; do d=$(mkrow "V26-$k"); addtest "$d" 11 completed failure 6; setsuites "$d" 7500; setnow "$d" 7800
    case "$k" in
      fail) touch "$d/suites.fail" ;;
      html) printf '<html>502</html>' > "$d/suites.raw" ;;
      notarray) echo '[{"total_count":1,"check_suites":"x"}]' > "$d/suites.raw" ;;
      nullts) jqf "$d" suites.json 'map(.created_at = null)' ;;
      garbage) jqf "$d" suites.json 'map(.created_at = "garbage")' ;;
      otherhead) jqf "$d" suites.json "map(.head_sha = \"$OTHER_H\")" ;;
      preepoch) jqf "$d" suites.json 'map(.created_at = "0001-01-01T00:00:00Z")' ;;
    esac
    vrun "$d" verdict "$PR"
    ok "V26.$k.rc" rc_is 3; ok "V26.$k.state" state_is error api-error; ok "V26.$k.not-closed" not_closed; ok "V26.$k.one" one_marker
    ok "V26.$k.nomiss" nomiss "$d"; done
  d=$(mkrow V26-empty); addtest "$d" 11 completed failure 6; setsuites "$d"; setnow "$d" 7800; vrun "$d" verdict "$PR"
  ok V26.empty-list.rc rc_is 3; ok V26.empty-list.reason state_is error no-check-suites; ok V26.empty-list.not-closed not_closed; ok V26.empty-list.one one_marker
  ok V26.empty-list.names-the-sha eq "$(grep -c "no check suites visible at $H" <<<"$ERR")" 1; ok V26.empty-list.nomiss nomiss "$d"; }
# V27: the suite read is LAZY. It happens only when no run is kept AND T alone already says stalled; every other path makes
# no such request (the stalled-gate rows read at T+7800, so a hoisted read would be seen).
row_V27() { local d
  d=$(mkrow V27-green); addtest "$d" 11 completed success 7; setnow "$d" 7800; vrun "$d" verdict "$PR"; ok V27.green notcalled "$d" check-suites
  d=$(mkrow V27-dirty); addtest "$d" 11 completed failure 6; jqf "$d" pr.json '.mergeable_state = "dirty"'; setnow "$d" 7800; vrun "$d" verdict "$PR"
  ok V27.dirty-state state_is no-run conflicting none; ok V27.dirty notcalled "$d" check-suites
  d=$(mkrow V27-approval); addtest "$d" 11 completed failure 6; addrun "$d" 8 completed action_required 2; setnow "$d" 7800; vrun "$d" verdict "$PR"; ok V27.awaiting-approval notcalled "$d" check-suites
  d=$(mkrow V27-kept-run); addtest "$d" 11 completed failure 6; addrun "$d" 8 in_progress null 2; setnow "$d" 7800; vrun "$d" verdict "$PR"
  ok V27.kept-run-state state_is stalled undecided-after-120m 8; ok V27.kept-run notcalled "$d" check-suites
  d=$(mkrow V27-fresh); addtest "$d" 11 completed failure 6; vrun "$d" verdict "$PR"; ok V27.fresh-no-run-state state_is no-run no-run-after-ready none; ok V27.fresh-no-run notcalled "$d" check-suites
  d=$(mkrow V27-at-120m); addtest "$d" 11 completed failure 6; setnow "$d" 7200; vrun "$d" verdict "$PR"
  ok V27.t-gate-state state_is no-run no-run-after-ready none; ok V27.t-gate-is-strict notcalled "$d" check-suites
  d=$(mkrow V27-stalled); addtest "$d" 11 completed failure 6; setnow "$d" 7800; vrun "$d" verdict "$PR"
  ok V27.stalled-state state_is stalled undecided-after-120m none; ok V27.stalled.nomiss nomiss "$d"
  ok V27.no-run-and-old-reads-the-suites called "$d" "commits/$H/check-suites?per_page=100"
  ok V27.the-suite-read-is-queried-once test "$(grep -c 'check-suites' "$d/log")" = 1; }
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
  ok V22.404.rc rc_is 0; ok V22.404.state state_is n/a no-draft-light none; ok V22.404.no-run-read notcalled "$d" ci.yml/runs; ok V22.404.no-row-read notcalled "$d" check-runs; ok V22.404.no-suite-read notcalled "$d" check-suites
  d=$(mkrow V22-nojob); printf 'jobs:\n  test:\n    runs-on: ubuntu-latest\n' > "$d/ciyml.yml"; addtest "$d" 11 completed failure 6; vrun "$d" verdict "$PR"
  ok V22.no-job.state state_is n/a no-draft-light none; ok V22.no-job.nomiss nomiss "$d"
  d=$(mkrow V22-wait404); touch "$d/ciyml.404"; setready "$d" "$(iso_at -3600)" "$T_ISO"
  vrun "$d" wait-ready-run "$PR" --before-count 1; ok V22.wait.rc rc_is 0; ok V22.wait.marker w_is ok not-applicable none; ok V22.wait.no-polling polls "$d" 0; ok V22.wait.nomiss nomiss "$d"
  d=$(mkrow V22-waitjob); setready "$d" "$(iso_at -3600)" "$T_ISO"; addrun "$d" 8 queued null 2; vrun "$d" wait-ready-run "$PR" --before-count 1
  ok V22.wait-applicable.marker w_is ok run-created 8
  # the job key may carry a trailing comment or quotes; a quoted/commented key is still the mechanism
  d=$(mkrow V22-comment); printf 'jobs:\n  "draft-light":   # the cost lever\n    runs-on: ubuntu-latest\n' > "$d/ciyml.yml"; addtest "$d" 11 completed failure 6; addrun "$d" 8 in_progress null 2
  vrun "$d" verdict "$PR"; ok V22.commented-quoted-key-is-applicable state_is pending-full run-in-progress 8
  # the REAL workflow in this checkout is applicable: a regex that drifts from ci.yml would silently switch the wait gate off
  d=$(mkrow V22-real); cp "$REPO_ROOT/.github/workflows/ci.yml" "$d/ciyml.yml"; addtest "$d" 11 completed failure 6; addrun "$d" 8 in_progress null 2
  vrun "$d" verdict "$PR"; ok V22.the-real-ci-yml-is-applicable state_is pending-full run-in-progress 8
  # a 200 body that is not a workflow file is an ERROR (exit 3), never "not applicable" (which would arm unguarded)
  d=$(mkrow V22-html); printf '<html><body>502 Bad Gateway</body></html>\n' > "$d/ciyml.yml"; vrun "$d" verdict "$PR"
  ok V22.html-200-is-an-error.rc rc_is 3; ok V22.html-200-is-an-error.state state_is error api-error
  vrun "$d" wait-ready-run "$PR" --before-count 1; ok V22.html-200-wait.rc rc_is 3; ok V22.html-200-wait.marker w_is fail api-error none
  # only an HTTP 404 means "no such file"; a bare "Not Found" in other text is an error
  d=$(mkrow V22-nf); touch "$d/ciyml.fail"; vrun "$d" verdict "$PR"; ok V22.generic-failure-is-an-error rc_is 3
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
           "wait-ready-run 7 --before-count 1 --timeout 0" "wait-ready-run 7 --before-count 1 --timeout x" "verdict 7 --repo https://x/y" "verdict 7 --repo a" "ready-count" "ready-count 7 8" \
           "required" "required abc" "required 7 8" "required 7 --before-count 1" "required 7 --timeout 5"; do
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
# W15: a missing tool still ends wait-ready-run with a marker (exit 3), so the caller can classify it
row_W15() { local d emp; d=$(mkrow W15); emp="$SANDBOX/emptybin"; mkdir -p "$emp"
  : > "$d/log"; env -u CI_HEAD_VERDICT_NOW PATH="$emp" FX="$d" "$(command -v bash)" "$SUT" wait-ready-run "$PR" --before-count 0 > "$d/out" 2> "$d/err"; RC=$?; OUT=$(cat "$d/out"); ERR=$(cat "$d/err")
  ok W15.rc rc_is 3; ok W15.marker w_is fail api-error none; ok W15.stderr-names-the-tool eq "$(grep -c 'not found on PATH' <<<"$ERR")" 1; }
# W14: ready-count prints the number of ReadyForReviewEvents (NOT the timeline totalCount) and nothing else.
row_W14() { local d; d=$(mkrow W14); setready "$d" "$(iso_at -3600)" "$(iso_at -1800)" "$T_ISO"
  vrun "$d" ready-count "$PR"; ok W14.rc rc_is 0; ok W14.count eq "$OUT" 3; ok W14.nomiss nomiss "$d"
  setready "$d"; vrun "$d" ready-count "$PR"; ok W14.zero eq "$OUT" 0
  touch "$d/ready.fail"; vrun "$d" ready-count "$PR"; ok W14.error-rc rc_is 3; ok W14.error-no-stdout eq "$OUT" ""; }

# ── Guard 3 rows: required (read-only required-context set check, #9927) ────────────────────
# The child (`admin-merge-ready.sh`) is a generated stub (marker + rc from the row dir) for the unit rows, selected through
# ADMIN_MERGE_READY_BIN; the real-child rows (R9, RE1, RE2, RE3, RE6) point the seam at the REAL script, because `mutant_run` copies the SUT
# to $SANDBOX, where the default "next to this script" would not resolve (an `error` expectation would then pass for the wrong reason).
REAL_AMR="$SCRIPT_DIR/../scripts/admin-merge-ready.sh"
reqrow() { # <name> [pr-base]: a mkrow PR with a REST base, an empty actions-runs list and the child stub
  local d; d=$(mkrow "$1"); jqf "$d" pr.json ".base = {ref: \"${2-main}\"}"
  echo '[]' > "$d/aruns.json"
  cat > "$d/amr-stub.sh" <<'AMR'
#!/usr/bin/env bash
printf '%s GH_REPO=%s\n' "$*" "${GH_REPO:-}" >> "$FX/amr.argv"
cat "$FX/amr.stdout" 2>/dev/null
exit "$(cat "$FX/amr.rc" 2>/dev/null || echo 99)"
AMR
  printf '%s' "$d"
}
amr_raw() { # <verdict> <reason> <required> <tail-after-absent=> [pr] [sha]
  printf 'SOLEUR_ADMIN_MERGE_READY verdict=%s pr=%s sha=%s base=%s reason=%s required=%s absent=%s\n' "$1" "${5:-$PR}" "${6:-$H}" "${AMR_BASE:-main}" "$2" "$3" "$4"
}
amr_line() { amr_raw "$1" "$2" "$3" "$4 pending=$5 failed=$6" "${7:-}" "${8:-}"; }   # <verdict> <reason> <required> <absent> <pending> <failed> [pr] [sha]
setamr() { cat > "$1/amr.stdout"; printf '%s\n' "$2" > "$1/amr.rc"; }               # <dir> <rc>  (the child's stdout on stdin)
rrun() { local d="$1"; shift; rm -f "$d/amr.argv"; VRUN_ENV="ADMIN_MERGE_READY_BIN=$d/amr-stub.sh" vrun "$d" required "$PR" "$@" </dev/null; }
addxrun() { # <dir> <id> <workflow-name> <conclusion> [head]: a run of ANY workflow in the actions-runs list
  local t; t=$(mktemp "$SANDBOX/jqf.XXXXXX")
  jq -c --argjson id "$2" --arg n "$3" --arg c "$4" --arg h "${5:-$H}" \
    '. + [{id: $id, name: $n, event: "pull_request_target", head_sha: $h, status: "completed", conclusion: (if $c == "null" then null else $c end)}]' \
    "$1/aruns.json" > "$t" && mv "$t" "$1/aruns.json"
}
rmark() { grep '^SOLEUR_CI_REQUIRED_SET ' <<<"$OUT" | tail -1; }
gf() { local s="$1"; if [[ "$s" == ANY ]]; then printf '*'; return; fi   # a glob field: ANY is a wildcard, anything else is literal ([ ] are escaped)
  s=${s//\\/\\\\}; s=${s//\[/\\[}; s=${s//\]/\\]}; s=${s//\*/\\*}; s=${s//\?/\\?}; printf '%s' "$s"; }
# req_is <state> <reason> [required] [absent] [pending] [failed] [sha]: EVERY row asserts the exact state AND reason (a mutant that lands on
# `error` through another row must not survive on the state alone).
req_is() { local m pat; m=$(rmark)
  pat="SOLEUR_CI_REQUIRED_SET state=$(gf "$1") pr=$PR sha=$(gf "${7:-$H}") required=$(gf "${3:-ANY}") reason=$(gf "$2") absent=$(gf "${4:-ANY}") pending=$(gf "${5:-ANY}") failed=$(gf "${6:-ANY}")"
  # shellcheck disable=SC2053  # the right side is a glob on purpose
  [[ "$m" == $pat ]] || why "marker is '$m', want state=$1 reason=$2 required=${3:-ANY} absent=${4:-ANY} pending=${5:-ANY} failed=${6:-ANY} sha=${7:-$H} (rc=$RC err=$ERR)"; }
req_err() { req_is error "$1" - - - - "${2:-$H}"; }   # <reason> [sha]: an error marker prints `-` for every unknown scalar and array, never `[]` or `unknown`
req_one() { [[ "$(grep -c '^SOLEUR_CI_REQUIRED_SET ' <<<"$OUT")" == 1 && "$(tail -1 <<<"$OUT")" == SOLEUR_CI_REQUIRED_SET\ * ]] || why "stdout is not exactly one required marker as its last line: $OUT"; }
outhas() { grep -Fq -- "$1" <<<"$OUT" || why "output lacks: $1 (out: $OUT)"; }
outlacks() { ! grep -Fq -- "$1" <<<"$OUT" || why "output unexpectedly has: $1 (out: $OUT)"; }
nrerun() { [[ "$(grep -c '^RECOVERY rerun' <<<"$OUT")" == "$1" ]] || why "RECOVERY rerun lines: $(grep -c '^RECOVERY rerun' <<<"$OUT"), want $1 (out: $OUT)"; }

# R1: the child says ready, required=26, three empty arrays: complete, exit 0; the child is called with the head and the PR base, read-only.
row_R1() { local d; d=$(reqrow R1)
  { echo "READY: every required context is green"; amr_line ready all-green 26 '[]' '[]' '[]'; } | setamr "$d" 0
  rrun "$d"
  ok R1.rc rc_is 0; ok R1.state req_is complete all-green 26 '[]' '[]' '[]'; ok R1.nomiss nomiss "$d"; ok R1.one req_one
  ok R1.child-argv eq "$(cat "$d/amr.argv")" "$PR $H --base main GH_REPO="
  ok R1.no-wait-flag notcalled "$d" "--wait"; ok R1.no-recovery-read notcalled "$d" "actions/runs?head_sha"; ok R1.no-recovery-line outlacks "RECOVERY"; }

# R2: a required context absent from another workflow, with a cancelled run of the owning workflow at the head: absent + ONE workflow-basis
# rerun hint that is printed, never run; the stale unrelated cancelled run, a success run and a cancelled run at another head are not chosen.
row_R2() { local d ctx wf pair; d=$(reqrow R2)
  addxrun "$d" 650 CI cancelled; addxrun "$d" 700 cla-evidence cancelled; addxrun "$d" 600 cla-evidence success; addxrun "$d" 710 cla-evidence cancelled "$OTHER_H"
  amr_line not-ready not-green 2 '["cla-evidence"]' '[]' '[]' | setamr "$d" 1
  rrun "$d"
  ok R2.rc rc_is 0; ok R2.state req_is absent not-green 2 '["cla-evidence"]' '[]' '[]'
  ok R2.hint outhas 'RECOVERY rerun run=700 basis=workflow ctx="cla-evidence" wf="cla-evidence": gh run rerun 700'
  ok R2.one-hint nrerun 1; ok R2.not-executed notcalled "$d" "run rerun"; ok R2.nomiss nomiss "$d"; ok R2.one req_one
  ok R2.one-read eq "$(grep -c 'actions/runs?head_sha' "$d/log")" 1
  # context names with spaces, parentheses, # and :, and a workflow name carrying a control character (replaced by a space, so the line stays whole)
  for pair in 'Docs (build) #1: x|docs (BUILD) #1: X' $'cla-evidence|cla-evidence\001'; do ctx="${pair%%|*}"; wf="${pair#*|}"
    d=$(reqrow "R2-v-${#wf}")
    addxrun "$d" 701 "$wf" cancelled; addxrun "$d" 650 CI cancelled
    amr_line not-ready not-green 2 "$(jq -nc --arg c "$ctx" '[$c]')" '[]' '[]' | setamr "$d" 1
    rrun "$d"
    ok "R2.variant[${#wf}].state" req_is absent not-green 2 "$(jq -nc --arg c "$ctx" '[$c]')" '[]' '[]'
    ok "R2.variant[${#wf}].hint" outhas "RECOVERY rerun run=701 basis=workflow ctx=$(jq -nc --arg c "$ctx" '$c') wf=$(jq -nc --arg c "${wf//$'\001'/ }" '$c'): gh run rerun 701"
    ok "R2.variant[${#wf}].one-hint" nrerun 1; ok "R2.variant[${#wf}].one" req_one
    ok "R2.variant[${#wf}].no-raw-control-char" test -z "$(LC_ALL=C tr -d -c '\001' < "$d/out")"
  done
  # no cancelled run at the head: say so, print no rerun line, keep the state
  d=$(reqrow R2-none); addxrun "$d" 600 cla-evidence success
  amr_line not-ready not-green 2 '["cla-evidence"]' '[]' '[]' | setamr "$d" 1
  rrun "$d"
  ok R2.none.state req_is absent not-green 2 '["cla-evidence"]' '[]' '[]'; ok R2.none.text outhas 'RECOVERY no cancelled run at this head ctx="cla-evidence"'; ok R2.none.no-rerun nrerun 0; }

# R3: no unique name match (two cancelled runs match the same name, or none matches): every cancelled run at the head is a data-only
# candidate (newest first, no command text) plus the "owner not determined" sentence; a second absent context is judged on its own.
row_R3() { local d; d=$(reqrow R3)
  addxrun "$d" 650 CI cancelled; addxrun "$d" 800 cla-evidence cancelled; addxrun "$d" 801 "CLA Evidence" cancelled
  amr_line not-ready not-green 2 '["cla-evidence"]' '[]' '[]' | setamr "$d" 1
  rrun "$d"
  ok R3.dup.state req_is absent not-green 2 '["cla-evidence"]' '[]' '[]'; ok R3.dup.no-workflow-basis outlacks 'basis=workflow'
  ok R3.dup.candidates nrerun 3
  ok R3.dup.newest-first eq "$(grep '^RECOVERY rerun' <<<"$OUT" | sed 's/ basis=.*//' | tr '\n' ' ')" "RECOVERY rerun run=801 RECOVERY rerun run=800 RECOVERY rerun run=650 "
  ok R3.dup.stale-unrelated-run-listed outhas 'RECOVERY rerun run=650 basis=candidate ctx="cla-evidence" wf="CI"'
  ok R3.dup.sentence outhas 'RECOVERY owner not determined, read the run before re-running ctx="cla-evidence"'
  ok R3.dup.no-command-text outlacks 'gh run rerun'; ok R3.dup.not-executed notcalled "$d" "run rerun"; ok R3.dup.nomiss nomiss "$d"
  d=$(reqrow R3-two); addxrun "$d" 700 cla-evidence cancelled; addxrun "$d" 650 CI cancelled
  amr_line not-ready not-green 3 '["cla-evidence","other ctx"]' '[]' '[]' | setamr "$d" 1
  rrun "$d"
  ok R3.two.state req_is absent not-green 3 '["cla-evidence","other ctx"]' '[]' '[]'
  ok R3.two.first-is-workflow outhas 'RECOVERY rerun run=700 basis=workflow ctx="cla-evidence" wf="cla-evidence": gh run rerun 700'
  ok R3.two.second-is-candidate outhas 'RECOVERY rerun run=700 basis=candidate ctx="other ctx" wf="cla-evidence"'
  ok R3.two.second-sentence outhas 'RECOVERY owner not determined, read the run before re-running ctx="other ctx"'
  ok R3.two.one-read eq "$(grep -c 'actions/runs?head_sha' "$d/log")" 1; }

# R4: the recovery read is diagnostics only. A failed or malformed runs list leaves the state `absent`; `stalled` skips the lookup for the
# synthetic `test` row ONLY; awaiting-approval and stale-row get the dedicated ready-run-wait pointer, not the generic one.
row_R4() { local d k
  for k in fail raw; do d=$(reqrow "R4-$k"); addxrun "$d" 700 cla-evidence cancelled
    if [[ $k == fail ]]; then touch "$d/aruns.fail"; else echo 'not json' > "$d/aruns.raw"; fi
    amr_line not-ready not-green 2 '["cla-evidence"]' '[]' '[]' | setamr "$d" 1
    rrun "$d"
    ok "R4.$k.rc" rc_is 0; ok "R4.$k.state-stays-absent" req_is absent not-green 2 '["cla-evidence"]' '[]' '[]'
    ok "R4.$k.text" outhas 'RECOVERY owner not determined (read failed) ctx="cla-evidence"'; ok "R4.$k.no-rerun" nrerun 0; ok "R4.$k.one" req_one; done
  d=$(reqrow R4-stalled-both); addxrun "$d" 700 cla-evidence cancelled
  amr_line not-ready stalled 26 '["test","cla-evidence"]' '[]' '[]' | setamr "$d" 1
  rrun "$d"
  ok R4.both.state req_is absent stalled 26 '["test","cla-evidence"]' '[]' '[]'
  ok R4.both.test-pointer outhas 'RECOVERY pointer reason=stalled ctx="test": see skills/ship/references/ready-run-wait.md'
  ok R4.both.other-context-still-looked-up outhas 'RECOVERY rerun run=700 basis=workflow ctx="cla-evidence" wf="cla-evidence": gh run rerun 700'
  ok R4.both.test-not-looked-up outlacks 'ctx="test" wf='; ok R4.both.nomiss nomiss "$d"
  d=$(reqrow R4-stalled-test); addxrun "$d" 700 cla-evidence cancelled
  amr_line not-ready stalled 26 '["test"]' '[]' '[]' | setamr "$d" 1
  rrun "$d"
  ok R4.test-only.state req_is absent stalled 26 '["test"]' '[]' '[]'; ok R4.test-only.pointer outhas 'RECOVERY pointer reason=stalled ctx="test"'
  ok R4.test-only.no-read notcalled "$d" "actions/runs?head_sha"; ok R4.test-only.no-rerun nrerun 0
  ok R4.test-only.caveat outhas 'no ready run is still in flight'
  d=$(reqrow R4-test-not-stalled); addxrun "$d" 700 test cancelled
  amr_line not-ready not-green 26 '["test"]' '[]' '[]' | setamr "$d" 1
  rrun "$d"
  ok R4.test-absent-not-stalled.looked-up outhas 'RECOVERY rerun run=700 basis=workflow ctx="test" wf="test": gh run rerun 700'
  d=$(reqrow R4-awaiting); addxrun "$d" 700 cla-evidence cancelled
  amr_line not-ready awaiting-approval 26 '[]' '["test"]' '[]' | setamr "$d" 1
  rrun "$d"
  ok R4.awaiting.state req_is pending awaiting-approval 26 '[]' '["test"]' '[]'; ok R4.awaiting.pointer outhas 'RECOVERY pointer reason=awaiting-approval ctx="test": see skills/ship/references/ready-run-wait.md'
  ok R4.awaiting.not-generic outlacks 'gh pr checks'; ok R4.awaiting.no-read notcalled "$d" "actions/runs?head_sha"; ok R4.awaiting.no-rerun nrerun 0
  d=$(reqrow R4-stale-row)
  amr_line not-ready stale-row 26 '[]' '[]' '["test"]' | setamr "$d" 1
  rrun "$d"
  ok R4.stale-row.state req_is failed stale-row 26 '[]' '[]' '["test"]'; ok R4.stale-row.pointer outhas 'RECOVERY pointer reason=stale-row ctx="test": see skills/ship/references/ready-run-wait.md'
  ok R4.stale-row.not-generic outlacks 'gh pr checks'; ok R4.stale-row.no-rerun nrerun 0
  ok R4.stale-row.caveat outhas 'no ready run is still in flight'
  d=$(reqrow R4-generic)
  amr_line not-ready not-green 26 '[]' '["a"]' '["b"]' | setamr "$d" 1
  rrun "$d"
  ok R4.generic.state req_is failed not-green 26 '[]' '["a"]' '["b"]'; ok R4.generic.pointer outhas "RECOVERY pointer failed=[\"b\"]: read the failing checks with gh pr checks $PR"
  ok R4.generic.no-read notcalled "$d" "actions/runs?head_sha"; ok R4.generic.no-rerun nrerun 0
  d=$(reqrow R4-generic-pending)
  amr_line not-ready not-green 26 '[]' '["a"]' '[]' | setamr "$d" 1
  rrun "$d"
  ok R4.generic-pending.pointer outhas "RECOVERY pointer pending=[\"a\"]: wait, then read the checks with gh pr checks $PR"; ok R4.generic-pending.no-rerun nrerun 0; }

# R5: precedence failed > absent > pending (the full pair matrix, the populated array in the later positions too).
row_R5() { local d a p f want lab
  while IFS='|' read -r lab a p f want; do d=$(reqrow "R5-$lab")
    amr_line not-ready not-green 26 "$a" "$p" "$f" | setamr "$d" 1
    rrun "$d"
    ok "R5.$lab.state" req_is "$want" not-green 26 "$a" "$p" "$f"; ok "R5.$lab.rc" rc_is 0; ok "R5.$lab.nomiss" nomiss "$d"; ok "R5.$lab.one" req_one
  done <<'EOF'
failed+absent|["a"]|[]|["f"]|failed
absent+pending|["a"]|["p"]|[]|absent
failed+pending|[]|["p"]|["f"]|failed
all-three|["a"]|["p"]|["f"]|failed
pending-only|[]|["p"]|[]|pending
failed-only|[]|[]|["f"]|failed
absent-only|["a"]|[]|[]|absent
EOF
}

# r6_fixture <label>: the child's stdout for an error case (the rc comes from the table).
r6_fixture() {
  case "$1" in
    crash) : ;;
    rc2-marker|rc130-marker) amr_line ready all-green 26 '[]' '[]' '[]' ;;
    rc3-with-gaps) amr_line error api-error 5 '["a"]' '["p"]' '[]' ;;     # an rc 3 / rc 4 marker with POPULATED arrays must stay error with the child's reason
    rc4-with-gaps) amr_line stale head-moved 5 '["a"]' '[]' '["f"]' ;;
    rc3-*) amr_line error "${1#rc3-}" 0 '[]' '[]' '[]' ;;
    rc4-head-moved) amr_line stale head-moved 0 '[]' '[]' '[]' ;;
    rc4-not-open) amr_line stale not-open 0 '[]' '[]' '[]' ;;
    no-marker-rc0) echo "READY (a human line, no marker)" ;;
    no-marker-rc1) echo "ABSENT  cla-evidence" ;;
    forged-first) amr_line ready all-green 26 '[]' '[]' '[]'; amr_line not-ready not-green 26 '["x"]' '[]' '[]' ;;
    forged-last) amr_line not-ready not-green 26 '["x"]' '[]' '[]'; amr_line ready all-green 26 '[]' '[]' '[]' ;;
    trailing-line) amr_line not-ready not-green 26 '["x"]' '[]' '[]'; echo "a trailing stdout line" ;;
    pr-mismatch) amr_line not-ready not-green 26 '["x"]' '[]' '[]' 7777 ;;
    sha-mismatch) amr_line not-ready not-green 26 '["x"]' '[]' '[]' "$PR" "$OTHER_H" ;;
    pair-notready-rc0) amr_line not-ready not-green 26 '[]' '[]' '[]' ;;
    pair-ready-rc1) amr_line ready all-green 26 '[]' '[]' '[]' ;;
    pair-stale-rc3) amr_line stale head-moved 0 '[]' '[]' '[]' ;;
    pair-error-rc4) amr_line error api-error 0 '[]' '[]' '[]' ;;
    arr-notjson) amr_raw not-ready not-green 26 'oops pending=[] failed=[]' ;;
    arr-two-values) amr_raw ready all-green 26 '[] ["x"] pending=[] failed=[]' ;;
    arr-nonstring) amr_raw not-ready not-green 26 '[1] pending=[] failed=[]' ;;
    arr-not-array) amr_raw not-ready not-green 26 '{"a":1} pending=[] failed=[]' ;;
    arr-embeds-pending) amr_raw not-ready not-green 26 '["a pending=[] b"] pending=[] failed=[]' ;;
    arr-control-char) amr_raw not-ready not-green 26 '["a\u0001b"] pending=[] failed=[]' ;;
    arr-total-above-required) amr_line not-ready not-green 1 '["a"]' '["b"]' '[]' ;;
    arr-missing-failed) amr_raw not-ready not-green 26 '["x"] pending=[]' ;;
    arr-trailing-junk) amr_raw not-ready not-green 26 '["x"] pending=[] failed=[] extra=1' ;;
    arr-fake-failed-field) amr_raw not-ready not-green 26 '["x failed=y"] pending=[]' ;;   # ' failed=' inside a context name, no real failed= field
    arr-del-char) amr_raw not-ready not-green 26 '["a\u007fb"] pending=[] failed=[]' ;;
    arr-us-char) amr_raw not-ready not-green 26 '["a\u001fb"] pending=[] failed=[]' ;;
    arr-c1-char) amr_raw not-ready not-green 26 '["a\u0085b"] pending=[] failed=[]' ;;
    arr-c1-char-9f) amr_raw not-ready not-green 26 '["a\u009fb"] pending=[] failed=[]' ;;
    arr-ls-char) amr_raw not-ready not-green 26 '["a\u2028b"] pending=[] failed=[]' ;;
    arr-ps-char) amr_raw not-ready not-green 26 '["a\u2029b"] pending=[] failed=[]' ;;
    required-20-digits) amr_raw not-ready not-green 18446744073709551617 '["x"] pending=[] failed=[]' ;;   # 2^64 + 1: wraps to 1 in bash arithmetic, so a missing cap would read absent
    required-10-digits) amr_raw not-ready not-green 1234567890 '["x"] pending=[] failed=[]' ;;
    base-differs) AMR_BASE=other amr_line ready all-green 26 '[]' '[]' '[]' ;;
    reason-not-all-green) amr_line ready carryover-local-docs 26 '[]' '[]' '[]' ;;
    required-nonint) amr_raw not-ready not-green x '["x"] pending=[] failed=[]' ;;
    verdict-uppercase) amr_raw READY all-green 26 '[] pending=[] failed=[]' ;;
    ready-total-zero-required-gaps) amr_line ready all-green 0 '["a"]' '[]' '[]' ;;
    notready-required0-gaps) amr_line not-ready not-green 0 '[]' '[]' '["f"]' ;;
    *) echo "[FATAL] unknown R6 fixture $1" >&2; exit 1 ;;
  esac
}
# R6: every read failure and every marker the parser cannot prove is state=error, exit 3, `-` for every unknown scalar and array.
row_R6() { local d lab rc want emp
  while IFS='|' read -r lab rc want; do d=$(reqrow "R6-$lab")
    r6_fixture "$lab" | setamr "$d" "$rc"
    rrun "$d"
    ok "R6.$lab.state" req_err "$want"; ok "R6.$lab.rc" rc_is 3; ok "R6.$lab.one" req_one; ok "R6.$lab.nomiss" nomiss "$d"
  done <<'EOF'
crash|127|child-rc-127
rc2-marker|2|child-rc-2
rc130-marker|130|child-rc-130
rc3-api-error|3|api-error
rc3-unsupported-rule|3|unsupported-rule
rc3-empty-required|3|empty-required
rc3-unpinned|3|unpinned
rc3-incomplete-files|3|incomplete-files
rc4-head-moved|4|head-moved
rc4-not-open|4|not-open
rc3-with-gaps|3|api-error
rc4-with-gaps|4|head-moved
no-marker-rc0|0|no-marker
no-marker-rc1|1|no-marker
forged-first|1|marker-unparseable
forged-last|1|marker-unparseable
trailing-line|1|marker-unparseable
pr-mismatch|1|marker-mismatch
sha-mismatch|1|marker-mismatch
pair-notready-rc0|0|rc-mismatch
pair-ready-rc1|1|rc-mismatch
pair-stale-rc3|3|rc-mismatch
pair-error-rc4|4|rc-mismatch
arr-notjson|1|marker-unparseable
arr-two-values|0|marker-unparseable
arr-nonstring|1|marker-unparseable
arr-not-array|1|marker-unparseable
arr-embeds-pending|1|marker-unparseable
arr-control-char|1|marker-unparseable
arr-total-above-required|1|marker-unparseable
arr-missing-failed|1|marker-unparseable
arr-fake-failed-field|1|marker-unparseable
arr-del-char|1|marker-unparseable
arr-us-char|1|marker-unparseable
arr-c1-char|1|marker-unparseable
arr-c1-char-9f|1|marker-unparseable
arr-ls-char|1|marker-unparseable
arr-ps-char|1|marker-unparseable
required-20-digits|1|marker-unparseable
required-10-digits|1|marker-unparseable
base-differs|0|marker-mismatch
reason-not-all-green|0|rc-mismatch
arr-trailing-junk|1|marker-unparseable
required-nonint|1|marker-unparseable
verdict-uppercase|0|marker-unparseable
ready-total-zero-required-gaps|0|marker-unparseable
notready-required0-gaps|1|marker-unparseable
EOF
  # own PR read failure: the head is not known yet, so sha prints `-`
  d=$(reqrow R6-pr-read); amr_line ready all-green 26 '[]' '[]' '[]' | setamr "$d" 0; touch "$d/pr.fail"; rrun "$d"
  ok R6.pr-read.state req_err api-error -; ok R6.pr-read.rc rc_is 3; ok R6.pr-read.one req_one; ok R6.pr-read.child-not-run test ! -e "$d/amr.argv"
  # a missing tool still ends in a marker (exit 3), sha `-`
  d=$(reqrow R6-tool); emp="$SANDBOX/emptybin"; mkdir -p "$emp"
  env -u CI_HEAD_VERDICT_NOW PATH="$emp" FX="$d" "$(command -v bash)" "$SUT" required "$PR" > "$d/out" 2> "$d/err"; RC=$?; OUT=$(cat "$d/out"); ERR=$(cat "$d/err")
  ok R6.tool.state req_err missing-tool -; ok R6.tool.rc rc_is 3; ok R6.tool.one req_one; }

# R7: not-ready with empty arrays is `error` with the CHILD's own reason, also with required=0 as the real child prints it on untrusted-ci
# and base-mismatch (a required=0 test placed first would shadow the reason); untrusted-ci with a populated array maps by precedence.
row_R7() { local d lab reason req want
  while IFS='|' read -r lab reason req want; do d=$(reqrow "R7-$lab")
    amr_line not-ready "$reason" "$req" '[]' '[]' '[]' | setamr "$d" 1
    rrun "$d"
    ok "R7.$lab.state" req_err "$want"; ok "R7.$lab.rc" rc_is 3; ok "R7.$lab.nomiss" nomiss "$d"; ok "R7.$lab.no-recovery" outlacks "RECOVERY"
  done <<'EOF'
untrusted-ci-req0|untrusted-ci|0|untrusted-ci
untrusted-ci-req26|untrusted-ci|26|untrusted-ci
base-mismatch-req0|base-mismatch|0|base-mismatch
base-mismatch-req26|base-mismatch|26|base-mismatch
bare-not-green|not-green|26|no-culprit
bare-not-green-req0|not-green|0|no-culprit
EOF
  d=$(reqrow R7-populated); amr_line not-ready untrusted-ci 26 '[]' '[]' '["x"]' | setamr "$d" 1; rrun "$d"
  ok R7.populated.state req_is failed untrusted-ci 26 '[]' '[]' '["x"]'; ok R7.populated.rc rc_is 0; }

# R8: ready is `complete` only with a positive required AND three empty arrays (each array in turn, the third-only one included).
row_R8() { local d lab req a p f want pair
  while IFS='|' read -r lab req a p f want; do d=$(reqrow "R8-$lab")
    amr_line ready all-green "$req" "$a" "$p" "$f" | setamr "$d" 0
    rrun "$d"
    ok "R8.$lab.state" req_err "$want"; ok "R8.$lab.rc" rc_is 3; ok "R8.$lab.nomiss" nomiss "$d"
  done <<'EOF'
absent-only|26|["a"]|[]|[]|ready-with-gaps
pending-only|26|[]|["p"]|[]|ready-with-gaps
failed-only|26|[]|[]|["f"]|ready-with-gaps
all-three|26|["a"]|["p"]|["f"]|ready-with-gaps
required-zero|0|[]|[]|[]|required-unknown
EOF
  # a leading zero is decimal (0089 is not an octal error), and the printed count is the decimal one
  for pair in 0026:26 0089:89 000000001:1; do d=$(reqrow "R8-lz-${pair%%:*}")
    amr_raw ready all-green "${pair%%:*}" '[] pending=[] failed=[]' | setamr "$d" 0; rrun "$d"
    ok "R8.leading-zero-${pair%%:*}" req_is complete all-green "${pair##*:}" '[]' '[]' '[]'; done
  d=$(reqrow R8-one); amr_line ready all-green 1 '[]' '[]' '[]' | setamr "$d" 0; rrun "$d"
  ok R8.required-one-is-positive req_is complete all-green 1 '[]' '[]' '[]'; }

# R9: the real child. The field-name tokens of its marker() and the resolve_head_verdict -> verdict call are pinned (a switch to `required`
# would loop); the real script against a failing gh stub parses to `error api-error`; a missing seam and a bad base are `error` with no child call.
# amr_head_verdict_ok <admin-merge-ready.sh>: resolve_head_verdict CALLS `verdict` (a code line, not a comment) and never names `required`.
# Anchored on the call form; row R9 proves it on the real file AND rejects two known negatives (a swapped verb, a commented-out call).
amr_head_verdict_ok() { local body
  body=$(sed -n '/^resolve_head_verdict() {/,/^}/p' "$1" | grep -vE '^[[:space:]]*#')
  [[ "$(grep -cE '^[[:space:]]*m="\$\(bash "\$bin" verdict "\$PR"[ )]' <<<"$body")" == 1 && "$(grep -cw required <<<"$body")" == 0 ]]
}
row_R9() { local d fields cp="$SANDBOX/amrneg"
  fields=$(sed -n '/^marker() {/,/^}/p' "$REAL_AMR" | grep -o '[a-z]*=%s' | tr '\n' ' ')
  ok R9.marker-field-order eq "$fields" "verdict=%s pr=%s sha=%s base=%s reason=%s required=%s absent=%s pending=%s failed=%s "
  ok R9.marker-name grep -q 'readonly MARKER="SOLEUR_ADMIN_MERGE_READY"' "$REAL_AMR"
  ok R9.head-verdict-calls-verdict-never-required amr_head_verdict_ok "$REAL_AMR"
  mkdir -p "$cp"
  sed 's/^\(  m="\$(bash "\$bin" \)verdict/\1required/' "$REAL_AMR" > "$cp/swap.sh"; ok R9.negative-swap-landed test "$(cmp -s "$cp/swap.sh" "$REAL_AMR" && echo same || echo differs)" = differs
  ok R9.known-negative-required-call-is-rejected test "$(amr_head_verdict_ok "$cp/swap.sh" && echo accepted || echo rejected)" = rejected
  sed 's/^\(  m="\$(bash "\$bin" verdict.*\)$/  # \1/' "$REAL_AMR" > "$cp/comment.sh"; ok R9.negative-comment-landed test "$(cmp -s "$cp/comment.sh" "$REAL_AMR" && echo same || echo differs)" = differs
  ok R9.known-negative-commented-out-call-is-rejected test "$(amr_head_verdict_ok "$cp/comment.sh" && echo accepted || echo rejected)" = rejected
  d=$(rereal R9-api); touch "$d/prview.fail"
  VRUN_ENV="ADMIN_MERGE_READY_BIN=$REAL_AMR" vrun "$d" required "$PR"
  ok R9.real-api-error.state req_err api-error; ok R9.real-api-error.rc rc_is 3; ok R9.real-api-error.child-ran called "$d" "pr view $PR --json"; ok R9.real-api-error.one req_one
  d=$(reqrow R9-seam); amr_line ready all-green 26 '[]' '[]' '[]' | setamr "$d" 0
  VRUN_ENV="ADMIN_MERGE_READY_BIN=$d/does-not-exist.sh" vrun "$d" required "$PR"
  ok R9.missing-seam.state req_err no-admin-merge-ready; ok R9.missing-seam.rc rc_is 3
  d=$(reqrow R9-base "-x"); amr_line ready all-green 26 '[]' '[]' '[]' | setamr "$d" 0; rrun "$d"
  ok R9.bad-base.state req_err bad-base; ok R9.bad-base.rc rc_is 3; ok R9.bad-base.child-not-run test ! -e "$d/amr.argv"
  d=$(reqrow R9-base-empty ""); amr_line ready all-green 26 '[]' '[]' '[]' | setamr "$d" 0; rrun "$d"
  ok R9.empty-base.state req_err bad-base; }

# R10: usage lives in V19; here the PR base reaches the child as --base, --repo exports GH_REPO to the child, and `verdict` ignores the base.
row_R10() { local d
  d=$(reqrow R10-base release/1.2); AMR_BASE=release/1.2 amr_line ready all-green 26 '[]' '[]' '[]' | setamr "$d" 0; rrun "$d"
  ok R10.base.rc rc_is 0; ok R10.base.argv eq "$(cat "$d/amr.argv")" "$PR $H --base release/1.2 GH_REPO="
  d=$(reqrow R10-repo); amr_line ready all-green 26 '[]' '[]' '[]' | setamr "$d" 0; rrun "$d" --repo acme/widgets
  ok R10.repo.child-gets-GH_REPO eq "$(cat "$d/amr.argv")" "$PR $H --base main GH_REPO=acme/widgets"; ok R10.repo.gh-gets-GH_REPO called "$d" "GH_REPO=acme/widgets"; }

# R11: the documented extraction block in ready-run-wait.md RUNS verbatim (only PR_NUMBER is substituted) against the SUT and prints the marker,
# the basis=workflow ids and the basis=candidate lines (a wf= text imitating a second run= included); a call that prints no marker (exit 2) falls to
# its own "treat as error" line; and the reason vocabulary and the state list agree across the header, the doc and the code.
reason_tokens() { # <anchor>; text on stdin -> the sorted tokens of the first sentence after the anchor (header `# ` prefixes removed)
  tr '\n' ' ' | sed 's/# //g' | grep -o "$1[^.]*\." | head -1 | sed "s/^$1//; s/\.\$//" | tr -c 'a-z0-9<>-' '\n' | grep . | sort -u
}
row_R11() { local doc="$SCRIPT_DIR/../skills/ship/references/ready-run-wait.md" snip root d got helps docs t own pass code miss=""
  snip=$(awk '/^```bash$/ { b = 1; blk = ""; next } /^```$/ { if (b && blk ~ /^OUT=\$\(mktemp\)/) { printf "%s", blk; exit } b = 0; next } b { blk = blk $0 "\n" }' "$doc")
  ok R11.snippet-present test -n "$snip"
  root="$SANDBOX/snip-root"; rm -rf "$root"; mkdir -p "$root/scripts"; cp "$SUT" "$root/scripts/ci-head-verdict.sh"
  d=$(reqrow R11)
  addxrun "$d" 700 cla-evidence cancelled; addxrun "$d" 650 CI cancelled; addxrun "$d" 801 'x run=99 basis=workflow' cancelled
  amr_line not-ready not-green 3 '["cla-evidence","other ctx"]' '[]' '[]' | setamr "$d" 1
  : > "$d/log"; rm -f "$d/.polls"
  got=$(env -u GH_REPO FX="$d" STUB_LOG="$d/log" STUB_PR="$PR" STUB_H="$H" PATH="$BIN:$PATH" CI_HEAD_VERDICT_POLL_SECONDS=0 ADMIN_MERGE_READY_BIN="$d/amr-stub.sh" CLAUDE_PLUGIN_ROOT="$root" bash -c "${snip//PR_NUMBER/$PR}" 2>"$d/err")
  ok R11.snippet-first-line-is-the-marker test "$(sed -n 1p <<<"$got" | cut -d' ' -f1-3)" = "SOLEUR_CI_REQUIRED_SET state=absent pr=$PR"
  ok R11.snippet-prints-the-one-workflow-id test "$(grep -cE '^[0-9]+$' <<<"$got")" = 1
  ok R11.snippet-workflow-id-is-700 test "$(grep -E '^[0-9]+$' <<<"$got")" = 700
  ok R11.snippet-candidates-visible eq "$(grep -c '^RECOVERY rerun run=[0-9]* basis=candidate ' <<<"$got")" 3
  ok R11.snippet-imitated-run-stays-in-wf grep -qF 'RECOVERY rerun run=801 basis=candidate ctx="other ctx" wf="x run=99 basis=workflow"' <<<"$got"
  ok R11.snippet-candidates-carry-no-command test "$(grep 'basis=candidate' <<<"$got" | grep -c 'gh run rerun')" = 0
  ok R11.snippet-nomiss nomiss "$d"
  got=$(env -u GH_REPO FX="$d" STUB_LOG="$d/log" STUB_PR="$PR" STUB_H="$H" PATH="$BIN:$PATH" ADMIN_MERGE_READY_BIN="$d/amr-stub.sh" CLAUDE_PLUGIN_ROOT="$root" bash -c "${snip//PR_NUMBER/abc}" 2>/dev/null)
  ok R11.snippet-no-marker-line-is-an-error eq "$got" "no marker line: treat as state=error"
  helps=$(bash "$SUT" --help | grep -o 'SOLEUR_CI_REQUIRED_SET state=<[^>]*>' | head -1); docs=$(grep -o 'SOLEUR_CI_REQUIRED_SET state=<[^>]*>' "$doc" | head -1)
  ok R11.help-has-the-states eq "$helps" 'SOLEUR_CI_REQUIRED_SET state=<complete|absent|pending|failed|error>'
  ok R11.doc-states-equal-help eq "$docs" "$helps"
  # the reason vocabulary: header == doc for both lists, every own token is in the SUT's code, every pass-through token is in the real child's code
  ok R11.own-reasons-header-equal-doc eq "$(reason_tokens 'itself emits (closed): ' < "$SUT")" "$(reason_tokens 'itself emits (closed): ' < "$doc")"
  ok R11.passthrough-reasons-header-equal-doc eq "$(reason_tokens 'passed through from the child (informational): ' < "$SUT")" "$(reason_tokens 'passed through from the child (informational): ' < "$doc")"
  own=$(reason_tokens 'itself emits (closed): ' < "$SUT"); pass=$(reason_tokens 'passed through from the child (informational): ' < "$SUT")
  ok R11.own-reasons-nonempty test "$(wc -w <<<"$own")" -ge 14
  ok R11.passthrough-reasons-nonempty test "$(wc -w <<<"$pass")" -ge 13
  ok R11.interrupted-is-not-passed-through test -z "$(grep -x interrupted <<<"$pass")"
  code=$(grep -vE '^[[:space:]]*#' "$SUT")   # a variable, not a pipe: `grep -q` closing early would SIGPIPE the producer under pipefail
  for t in $own; do [[ "$t" == 'child-rc-<n>' ]] && t='child-rc-'; grep -qF -- "$t" <<<"$code" || miss="$miss $t"; done
  ok "R11.own-reasons-exist-in-the-sut:${miss:-none}" test -z "$miss"; miss=""
  code=$(grep -vE '^[[:space:]]*#' "$REAL_AMR")
  for t in $pass; do grep -qF -- "$t" <<<"$code" || miss="$miss $t"; done
  ok "R11.passthrough-reasons-exist-in-the-real-child:${miss:-none}" test -z "$miss"; }

# rereal <name>: a REAL-child fixture. The required set is {test, cla-evidence} (both pinned to app 15368), built here; `test` is green so the
# child never calls back into `ci-head-verdict.sh verdict`; the PR file list is clean and equals changedFiles.
rereal() {
  local d; d=$(reqrow "$1")
  printf '{"state":"OPEN","headRefOid":"%s","baseRefName":"main","changedFiles":1}\n' "$H" > "$d/prview.json"
  echo '[{"filename":"plugins/x/a.sh"}]' > "$d/prfiles.json"
  jq -nc '[{type:"required_status_checks",parameters:{required_status_checks:[{context:"test",integration_id:15368},{context:"cla-evidence",integration_id:15368}]}}]' > "$d/rules.json"
  jq -nc --arg h "$H" '[{id:11,name:"test",head_sha:$h,status:"completed",conclusion:"success",app:{id:15368},check_suite:{id:1}}]' > "$d/rcheckruns.json"
  printf '%s' "$d"
}
addrcheck() { jqf "$1" rcheckruns.json ". + [{id: $2, name: \"$3\", head_sha: \"$H\", status: \"completed\", conclusion: \"success\", app: {id: 15368}, check_suite: {id: 2}}]"; }
# RE1: end to end against the REAL admin-merge-ready.sh. cla-evidence is absent from the check runs (its pull_request_target run was
# cancelled): absent + the rerun hint. H1: the suite flips ONE fixture line (the context is present) and the same row must read complete.
row_RE1() { local d; d=$(rereal RE1); addxrun "$d" 650 CI cancelled; addxrun "$d" 700 cla-evidence cancelled
  VRUN_ENV="ADMIN_MERGE_READY_BIN=$REAL_AMR" vrun "$d" required "$PR"
  ok RE1.rc rc_is 0; ok RE1.state req_is absent not-green 2 '["cla-evidence"]' '[]' '[]'; ok RE1.nomiss nomiss "$d"; ok RE1.one req_one
  ok RE1.hint outhas 'RECOVERY rerun run=700 basis=workflow ctx="cla-evidence" wf="cla-evidence": gh run rerun 700'
  ok RE1.not-executed notcalled "$d" "run rerun"; ok RE1.child-read-only notcalled "$d" "pr merge"
  addrcheck "$d" 12 cla-evidence
  VRUN_ENV="ADMIN_MERGE_READY_BIN=$REAL_AMR" vrun "$d" required "$PR"
  ok RE1.flip.state req_is complete all-green 2 '[]' '[]' '[]'; ok RE1.flip.rc rc_is 0; ok RE1.flip.nomiss nomiss "$d"; ok RE1.flip.no-recovery outlacks "RECOVERY"; }
# RE2: the PR edits a workflow file: the REAL child prints required=0 and three empty arrays; `required` reads error untrusted-ci.
row_RE2() { local d; d=$(rereal RE2); echo '[{"filename":".github/workflows/x.yml"}]' > "$d/prfiles.json"
  VRUN_ENV="ADMIN_MERGE_READY_BIN=$REAL_AMR" vrun "$d" required "$PR"
  ok RE2.state req_err untrusted-ci; ok RE2.rc rc_is 3; ok RE2.nomiss nomiss "$d"; ok RE2.one req_one; ok RE2.no-recovery outlacks "RECOVERY"; }

# R12: the recovery read's guards. A run id becomes COMMAND TEXT on a basis=workflow line, so only a plain number of at most 15 digits is kept
# (a string, a float, 1e19 and a 16-digit number are dropped); an empty match key (punctuation only on both sides) never matches; the workflow
# name is cut at 80 characters; and every code point amr_arr_ok rejects (C1, U+2028) is replaced in wf= text, which an untrusted PR chose.
row_R12() { local d pair lab idj name wf rawleft
  for pair in 'str:"700"' 'float:1.5' 'big:1e19' 'sixteen:1234567890123456'; do lab="${pair%%:*}"; idj="${pair#*:}"
    d=$(reqrow "R12-id-$lab"); addxrun "$d" "$idj" cla-evidence cancelled
    amr_line not-ready not-green 2 '["cla-evidence"]' '[]' '[]' | setamr "$d" 1; rrun "$d"
    ok "R12.id-$lab.state" req_is absent not-green 2 '["cla-evidence"]' '[]' '[]'; ok "R12.id-$lab.dropped" nrerun 0
    ok "R12.id-$lab.text" outhas 'RECOVERY no cancelled run at this head'; ok "R12.id-$lab.no-command" outlacks 'gh run rerun'; done
  d=$(reqrow R12-id-15); addxrun "$d" 123456789012345 cla-evidence cancelled
  amr_line not-ready not-green 2 '["cla-evidence"]' '[]' '[]' | setamr "$d" 1; rrun "$d"
  ok R12.id-15-digits-kept outhas 'RECOVERY rerun run=123456789012345 basis=workflow ctx="cla-evidence" wf="cla-evidence": gh run rerun 123456789012345'
  d=$(reqrow R12-emptykey); addxrun "$d" 700 '---' cancelled
  amr_line not-ready not-green 2 '["!!!"]' '[]' '[]' | setamr "$d" 1; rrun "$d"
  ok R12.emptykey.state req_is absent not-green 2 '["!!!"]' '[]' '[]'; ok R12.emptykey.no-workflow-basis outlacks 'basis=workflow'
  ok R12.emptykey.is-a-candidate outhas 'RECOVERY rerun run=700 basis=candidate ctx="!!!" wf="---"'; ok R12.emptykey.no-command outlacks 'gh run rerun'
  name=$(printf 'abcdefghij%.0s' 1 2 3 4 5 6 7 8 9 10)   # 100 characters
  d=$(reqrow R12-long); addxrun "$d" 700 "$name" cancelled
  amr_line not-ready not-green 2 "$(jq -nc --arg c "$name" '[$c]')" '[]' '[]' | setamr "$d" 1; rrun "$d"
  ok R12.long.hint outhas "RECOVERY rerun run=700 basis=workflow ctx=\"$name\" wf=\"${name:0:80}\": gh run rerun 700"
  ok R12.long.wf-is-cut-at-80 outlacks "wf=\"${name:0:81}"
  wf=$'cla-evidence\xc2\x85\xe2\x80\xa8'   # U+0085 and U+2028 survive @json, so the script must replace them
  d=$(reqrow R12-clean); addxrun "$d" 700 "$wf" cancelled; addxrun "$d" 701 $'other\xe2\x80\xa9name' cancelled
  amr_line not-ready not-green 2 '["cla-evidence"]' '[]' '[]' | setamr "$d" 1; rrun "$d"
  ok R12.clean.workflow-line outhas 'RECOVERY rerun run=700 basis=workflow ctx="cla-evidence" wf="cla-evidence  ": gh run rerun 700'
  ok R12.clean.no-raw-bytes test -z "$(LC_ALL=C tr -d -c '\302\205\342\200\250\342\200\251' < "$d/out")"
  d=$(reqrow R12-clean-cand); addxrun "$d" 700 $'a\xc2\x9fb' cancelled
  amr_line not-ready not-green 2 '["zzz"]' '[]' '[]' | setamr "$d" 1; rrun "$d"
  ok R12.clean.candidate-line outhas 'RECOVERY rerun run=700 basis=candidate ctx="zzz" wf="a b"'
  ok R12.clean.candidate-no-raw-bytes test -z "$(LC_ALL=C tr -d -c '\302\237' < "$d/out")"; }

# R13: a signal while the child runs. The child is a stub that really takes a second (R13 uses the real `sleep`, not the PATH stub). Bash runs the
# trap only AFTER the foreground child returns, so the marker is exactly one state=error reason=interrupted (exit 3) that lags the signal. A
# second marker cannot be provoked from outside (the window is a few instructions), so the trap-clear is pinned structurally: it sits before the
# final req_marker and before the error-path fail_api.
row_R13() { local d pid i body n_trap n_mark
  d=$(reqrow R13)
  cat > "$d/amr-stub.sh" <<'AMR'
#!/usr/bin/env bash
: > "$FX/child-started"
"$REAL_SLEEP" 1
cat "$FX/amr.stdout" 2>/dev/null
exit "$(cat "$FX/amr.rc" 2>/dev/null || echo 99)"
AMR
  amr_line ready all-green 26 '[]' '[]' '[]' | setamr "$d" 0
  rm -f "$d/child-started" "$d/.polls"; : > "$d/log"
  env -u CI_HEAD_VERDICT_NOW -u GH_REPO FX="$d" STUB_LOG="$d/log" STUB_PR="$PR" STUB_H="$H" PATH="$BIN:$PATH" CI_HEAD_VERDICT_POLL_SECONDS=0 \
    REAL_SLEEP="$REAL_SLEEP" ADMIN_MERGE_READY_BIN="$d/amr-stub.sh" bash "$SUT" required "$PR" > "$d/out" 2> "$d/err" </dev/null &
  pid=$!
  for (( i = 0; i < 100; i++ )); do [[ -e "$d/child-started" ]] && break; "$REAL_SLEEP" 0.1; done
  kill -TERM "$pid" 2>/dev/null
  wait "$pid"; RC=$?; OUT=$(cat "$d/out"); ERR=$(cat "$d/err")
  ok R13.child-was-running test -e "$d/child-started"
  ok R13.state req_err interrupted; ok R13.rc rc_is 3; ok R13.one req_one; ok R13.nomiss nomiss "$d"
  body=$(sed -n '/^cmd_required() {/,/^}/p' "$SUT")
  n_trap=$(grep -n '^  trap - INT TERM HUP$' <<<"$body" | tail -1 | cut -d: -f1); n_mark=$(grep -n 'req_marker "\$CL_STATE"' <<<"$body" | tail -1 | cut -d: -f1)
  ok R13.trap-cleared-before-the-final-marker test -n "$n_trap" -a -n "$n_mark" -a "${n_trap:-999}" -lt "${n_mark:-0}"
  ok R13.trap-cleared-before-the-error-marker test "$(grep -c 'trap - INT TERM HUP; fail_api "admin-merge-ready.sh gave no provable answer' <<<"$body")" = 1; }

# R14: the PR argument and the PR base. A leading zero is a decimal (`required 04242` is PR 4242 for the gh path, the child and the pr= field, not
# octal); more than 15 digits is a usage error; a malformed .base object must not turn `verdict` or `wait-ready-run` into a read failure (only
# `required` uses the base, and it answers bad-base).
row_R14() { local d
  d=$(reqrow R14-zero); amr_line ready all-green 26 '[]' '[]' '[]' | setamr "$d" 0; rm -f "$d/amr.argv"
  VRUN_ENV="ADMIN_MERGE_READY_BIN=$d/amr-stub.sh" vrun "$d" required "0$PR" </dev/null
  ok R14.leading-zero.state req_is complete all-green 26 '[]' '[]' '[]'; ok R14.leading-zero.rc rc_is 0; ok R14.leading-zero.nomiss nomiss "$d"
  ok R14.leading-zero.child-argv eq "$(cat "$d/amr.argv")" "$PR $H --base main GH_REPO="
  d=$(mkrow R14-zero-verdict); addtest "$d" 11 completed failure 6; addrun "$d" 8 in_progress null 2; vrun "$d" verdict "00$PR"
  ok R14.verdict-leading-zero.state state_is pending-full run-in-progress 8; ok R14.verdict-leading-zero.nomiss nomiss "$d"
  vrun "$d" required 1234567890123456; ok R14.sixteen-digits.rc rc_is 2; ok R14.sixteen-digits.no-marker eq "$OUT" ""; ok R14.sixteen-digits.nocall eq "$(cat "$d/log")" ""
  d=$(mkrow R14-base); addtest "$d" 11 completed failure 6; addrun "$d" 8 in_progress null 2; jqf "$d" pr.json '.base = "x"'
  vrun "$d" verdict "$PR"; ok R14.malformed-base-verdict.rc rc_is 0; ok R14.malformed-base-verdict.state state_is pending-full run-in-progress 8
  setready "$d" "$(iso_at -3600)" "$T_ISO"; vrun "$d" wait-ready-run "$PR" --before-count 1; ok R14.malformed-base-wait.rc rc_is 0; ok R14.malformed-base-wait w_is ok run-created 8
  d=$(reqrow R14-base-req); jqf "$d" pr.json '.base = "x"'; amr_line ready all-green 26 '[]' '[]' '[]' | setamr "$d" 0; rrun "$d"
  ok R14.malformed-base-required.state req_err bad-base; ok R14.malformed-base-required.rc rc_is 3; ok R14.malformed-base-required.child-not-run test ! -e "$d/amr.argv"; }

# rereal_fail <dir> <test-conclusion> <cla-status>: the real child's check runs with `test` at <conclusion> (run 6) and cla-evidence at <status>
rereal_fail() {
  local cc="null"; [[ "$3" == completed ]] && cc='"success"'
  jq -nc --arg h "$H" --arg tc "$2" --arg cs "$3" --argjson cc "$cc" \
    '[{id:11,name:"test",head_sha:$h,status:"completed",conclusion:$tc,app:{id:15368},check_suite:{id:1},details_url:"https://example.invalid/o/r/actions/runs/6/job/11"},
      {id:12,name:"cla-evidence",head_sha:$h,status:$cs,conclusion:$cc,app:{id:15368},check_suite:{id:2}}]' > "$1/rcheckruns.json"
}
# RE3: the REAL child with a FAILED `test` and populated arrays, through the real verdict call: stale-row (failed + pending), stalled (absent) and
# awaiting-approval (pending). These are the three pass-through reasons the script gives dedicated pointers, so they must be tokens the child
# really prints, and each pointer must carry the child's "confirm no ready run is in flight" caveat where it advises an undo.
row_RE3() { local d
  d=$(rereal RE3-stale); rereal_fail "$d" failure in_progress; addtest "$d" 11 completed failure 6; addrun "$d" 8 completed failure 2
  VRUN_ENV="ADMIN_MERGE_READY_BIN=$REAL_AMR" vrun "$d" required "$PR"
  ok RE3.stale.state req_is failed stale-row 2 '[]' '["cla-evidence"]' '["test"]'; ok RE3.stale.rc rc_is 0; ok RE3.stale.nomiss nomiss "$d"; ok RE3.stale.one req_one
  ok RE3.stale.pointer outhas 'RECOVERY pointer reason=stale-row ctx="test"'; ok RE3.stale.caveat outhas 'no ready run is still in flight'
  d=$(rereal RE3-stalled); rereal_fail "$d" failure completed; addtest "$d" 11 completed failure 6; setnow "$d" 7800
  VRUN_ENV="ADMIN_MERGE_READY_BIN=$REAL_AMR" vrun "$d" required "$PR"
  ok RE3.stalled.state req_is absent stalled 2 '["test"]' '[]' '[]'; ok RE3.stalled.nomiss nomiss "$d"
  ok RE3.stalled.pointer outhas 'RECOVERY pointer reason=stalled ctx="test"'; ok RE3.stalled.caveat outhas 'no ready run is still in flight'; ok RE3.stalled.no-rerun nrerun 0
  d=$(rereal RE3-approval); rereal_fail "$d" failure completed; addtest "$d" 11 completed failure 6; addrun "$d" 8 completed action_required 2
  VRUN_ENV="ADMIN_MERGE_READY_BIN=$REAL_AMR" vrun "$d" required "$PR"
  ok RE3.approval.state req_is pending awaiting-approval 2 '[]' '["test"]' '[]'; ok RE3.approval.nomiss nomiss "$d"
  ok RE3.approval.pointer outhas 'RECOVERY pointer reason=awaiting-approval ctx="test"'; }

# RE6: the PRODUCTION layout. No ADMIN_MERGE_READY_BIN: the SUT finds admin-merge-ready.sh NEXT TO ITSELF. The SUT under test (the mutant, in a mutation
# run) and the real child are copied into one directory, so a broken default path reads error no-admin-merge-ready instead of complete.
row_RE6() { local d lay="$SANDBOX/prodlay" save="$SUT"
  rm -rf "$lay"; mkdir -p "$lay"; cp "$SUT" "$lay/ci-head-verdict.sh"; cp "$REAL_AMR" "$lay/admin-merge-ready.sh"
  d=$(rereal RE6)
  SUT="$lay/ci-head-verdict.sh"; vrun "$d" required "$PR"; SUT="$save"
  ok RE6.absent-then-flip.state req_is absent not-green 2 '["cla-evidence"]' '[]' '[]'; ok RE6.nomiss nomiss "$d"
  addrcheck "$d" 12 cla-evidence
  SUT="$lay/ci-head-verdict.sh"; vrun "$d" required "$PR"; SUT="$save"
  ok RE6.complete.state req_is complete all-green 2 '[]' '[]' '[]'; ok RE6.complete.rc rc_is 0; ok RE6.complete.nomiss nomiss "$d"; ok RE6.complete.child-read-only notcalled "$d" "pr merge"; }

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

# L2: the arm-after-ready ORDER in the prose a model executes. Substring greps ("the file mentions wait-ready-run") cannot see
# the order, so extract the chain and match it as a whole: `K=$(… ready-count N) && gh pr ready N && … wait-ready-run N
# --before-count "$K"`, in ship's fenced block, the inline spans of merge-pr and drain-prs, and the shared reference. Known
# negatives: K read AFTER the ready call, and the wait deleted, must both be rejected (a SKILL.md that merely mentions the
# verb a second time in other prose satisfied the old grep).
chain_ok() { python3 - "$1" <<'PY2'
import re, sys
t = open(sys.argv[1]).read()
rc = r'K=\$\(bash "[^"\n]*ci-head-verdict\.sh" ready-count (?:PR_NUMBER|<number>|<N>)\)'
rd = r'gh pr ready (?:PR_NUMBER|<number>|<N>)'
wt = r'bash "[^"\n]*ci-head-verdict\.sh" wait-ready-run (?:PR_NUMBER|<number>|<N>) --before-count "\$K"'
pat = rc + r'\s*&&\s*' + rd + r'\s*(?:\\\n\s*)?&&\s*' + wt
sys.exit(0 if re.search(pat, t) else 1)
PY2
}
row_L2() { local f c ship="$REPO_ROOT/plugins/soleur/skills/ship/SKILL.md" cp="$SANDBOX/chain" m
  for f in plugins/soleur/skills/ship/SKILL.md plugins/soleur/skills/merge-pr/SKILL.md plugins/soleur/skills/drain-prs/SKILL.md plugins/soleur/skills/ship/references/ready-run-wait.md; do
    ok "L2.$f.order-ready-count-then-ready-then-wait" chain_ok "$REPO_ROOT/$f"
  done
  mkdir -p "$cp"
  # known negative 1: K is read AFTER gh pr ready (a stale K lets the wait pass on the first ready event)
  python3 - "$ship" "$cp/k-after.md" <<'PY2'
import sys
t = open(sys.argv[1]).read()
a = 'K=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/ci-head-verdict.sh" ready-count PR_NUMBER) && gh pr ready PR_NUMBER'
assert t.count(a) == 1
open(sys.argv[2], 'w').write(t.replace(a, 'gh pr ready PR_NUMBER && K=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/ci-head-verdict.sh" ready-count PR_NUMBER)'))
PY2
  ok L2.known-negative-K-after-ready-is-rejected test "$(chain_ok "$cp/k-after.md" && echo accepted || echo rejected)" = rejected
  # known negative 2: the wait is deleted from the chain
  python3 - "$ship" "$cp/no-wait.md" <<'PY2'
import re, sys
t = open(sys.argv[1]).read()
n = re.sub(r' \\\n\s*&& bash "[^"\n]*ci-head-verdict\.sh" wait-ready-run PR_NUMBER --before-count "\$K"', '', t)
assert n != t
open(sys.argv[2], 'w').write(n)
PY2
  ok L2.known-negative-wait-deleted-is-rejected test "$(chain_ok "$cp/no-wait.md" && echo accepted || echo rejected)" = rejected
  # the old grep is satisfied by a second mention of the verb elsewhere: prove the new row is not
  ok L2.the-old-substring-check-would-have-passed grep -q 'wait-ready-run' "$cp/no-wait.md"; }

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
  VERDICTS_EXPECTED=$((VERDICTS_EXPECTED + 1)); ASSERTED=$((ASSERTED + 4))
  local surv_ok=0 crash_ok=0 rt_ok=0 req_ok=0
  mutant_run SELF-EQUIV 'readonly MARKER="SOLEUR_CI_HEAD_VERDICT"' "readonly MARKER='SOLEUR_CI_HEAD_VERDICT'" row_V3 row_V15
  [[ "$MUT_LANDED" -eq 1 && -n "$MUT_SURV" && "$MUT_CRASH" -eq 0 ]] && surv_ok=1
  # the same control for the `required` rows (their child seam is explicit, so a mutant copy still reaches the stub child)
  mutant_run SELF-EQUIV-REQ 'readonly REQUIRED_MARKER="SOLEUR_CI_REQUIRED_SET"' "readonly REQUIRED_MARKER='SOLEUR_CI_REQUIRED_SET'" row_R1 row_R6 row_RE1
  [[ "$MUT_LANDED" -eq 1 && "$MUT_SURV" == " row_R1 row_R6 row_RE1" && "$MUT_CRASH" -eq 0 ]] && req_ok=1
  mutant_run SELF-CRASH 'set -uo pipefail' 'set -uo pipefail; readonly MARKER=(' row_V3
  [[ "$MUT_LANDED" -eq 1 && "$MUT_CRASH" -eq 1 ]] && crash_ok=1
  # the stderr detector itself: a mutant that PARSES (bash -n passes) but fails at runtime must still be flagged
  mutant_run SELF-CRASH-RT 'set -uo pipefail' 'set -uo pipefail; no_such_command_zz' row_V3
  if [[ "$MUT_LANDED" -eq 1 && "$MUT_CRASH" -eq 1 ]] && bash -n "$SANDBOX/mut-SELF-CRASH-RT.sh" 2>/dev/null; then rt_ok=1; fi
  if [[ "$surv_ok" -eq 1 && "$crash_ok" -eq 1 && "$rt_ok" -eq 1 && "$req_ok" -eq 1 ]]; then pass "harness controls (an equivalent mutant survives, a non-parsing and a runtime-failing mutant are flagged)"
  else fail "harness controls (survivor reported: $surv_ok, parse crash flagged: $crash_ok, runtime crash flagged: $rt_ok, required-rows control survives: $req_ok)"; fi
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
run_row row_V24 "V24 the stall clock starts at the kept run's own created_at when it is later than T"
run_row row_V25 "V25 no run yet: the clock starts at the earliest check suite when it is later than T"
run_row row_V26 "V26 an unreadable, malformed or empty suite list is state=error, never a guess"
run_row row_V27 "V27 the check-suite read is lazy: only when no run is kept and T alone says stalled"
run_row row_V23 "V23 a conflicting PR with no run is no-run/conflicting, never stalled"
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
run_row row_W15 "W15 a missing tool still prints the wait marker (exit 3)"
echo "== ci-head-verdict.sh: required =="
run_row row_R1 "R1  required: child ready with every context green: complete"
run_row row_R2 "R2  required: a context absent from another workflow reads absent; one printed workflow-basis rerun hint"
run_row row_R3 "R3  required: no unique owner: every cancelled run is a data-only candidate"
run_row row_R4 "R4  required: a failed recovery read degrades the text only; stalled/awaiting-approval/stale-row pointers"
run_row row_R5 "R5  required: precedence failed > absent > pending"
run_row row_R6 "R6  required: every read failure and unprovable marker is error (exit 3, dashes)"
run_row row_R7 "R7  required: not-ready with empty arrays is error with the child's own reason (untrusted-ci, base-mismatch)"
run_row row_R8 "R8  required: complete needs a positive required and three empty arrays"
run_row row_R9 "R9  required: real-child contract (field order, no loop, api-error, missing seam, bad base)"
run_row row_R10 "R10 required: the PR base and --repo reach the child"
run_row row_R11 "R11 required: the documented extraction snippet and the --help state list"
run_row row_RE1 "RE1 required: end to end against the real admin-merge-ready.sh (absent, then flipped to complete)"
run_row row_RE2 "RE2 required: a workflow-editing PR is error untrusted-ci with the real child"
run_row row_R12 "R12 required: recovery guards (run-id digits, empty key, 80-char cut, control-character replacement)"
run_row row_R13 "R13 required: a signal while the child runs prints exactly one state=error interrupted marker"
run_row row_R14 "R14 required: leading-zero PR, 15-digit cap, malformed base object"
run_row row_RE3 "RE3 required: real child with a failed test and populated arrays (stale-row, stalled, awaiting-approval)"
run_row row_RE6 "RE6 required: production layout, the child is found next to the script"
echo "== reader-bypass lint =="
run_row row_L1 "L1  every reader of a PR's CI state reaches the resolver"
run_row row_L2 "L2  arm-after-ready order: ready-count, gh pr ready, wait-ready-run (known negatives rejected)"

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
mutant M23 "grep -qE 'HTTP 404' \"\$WORK/err\"" "grep -qE 'HTTP 4040' \"\$WORK/err\"" row_V22
mutant M24 '%S GMT")' '%S GMTX")' row_V17
mutant M25 '"$TEST_CONCLUSION" == success' '"$TEST_CONCLUSION" != failure' row_V21
mutant M26 'sort_by([.ts, .id])' 'sort_by(.ts)' row_V12
mutant M27 'sort_by([.ts, .id])' 'sort_by(.id)' row_V12
mutant M28 ' and (.head.sha | test("^[0-9a-f]{40}$"))' '' row_V15
mutant M29 'WAIT_API_ERR=0
  if [[ "$READY_COUNT"' 'WAIT_API_ERR=1
  if [[ "$READY_COUNT"' row_W2
mutant M31 "grep -qE '^jobs:' \"\$WORK/ci.yml\"" "grep -qE '.' \"\$WORK/ci.yml\"" row_V22
mutant M32 "(#.*)?\$\" \"\$WORK/ci.yml\"" "\$\" \"\$WORK/ci.yml\"" row_V22
mutant M33 "elif [[ \"\$CMD\" == wait-ready-run ]]; then" "elif false; then" row_W15
mutant M34 'rs="conflicting"' 'rs="no-run-after-ready"' row_V23
mutant M36 '"$rs" == no-run-after-ready && "$PR_MSTATE"' '"$PR_MSTATE"' row_V23
mutant M35 '"$PR_MSTATE" == dirty ]]; then rs=' '"$PR_MSTATE" == clean ]]; then rs=' row_V23
# Stall-clock rows. There is no "drop T from max(T, A)" mutant: the T gate above already holds, so an anchor at or before T
# stalls with or without the max (equivalent by construction; row V25d pins the behaviour).
mutant M37 'anchor_epoch="$RUN_EPOCH"' 'anchor_epoch="$t_epoch"' row_V24 row_V5
mutant M38 '(min | tostring)' '(max | tostring)' row_V25
mutant M40 'if length == 0 then "none"' 'if length == 0 then "0"' row_V26
mutant M41 'NOW_EPOCH - t_epoch > STALL_MINUTES * 60' 'NOW_EPOCH - t_epoch > 0' row_V27
mutant M42 'read_head_anchor "$PR_SHA" || fail_api "$ERRMSG" "$ANCHOR_REASON"' 'read_head_anchor "$PR_SHA" || ANCHOR_EPOCH="$t_epoch"' row_V26
mutant M43 'type == "object" and .head_sha == $h and (.created_at | type) == "string"' 'type == "object" and (.created_at | type) == "string"' row_V26
mutant M44 '|| fail_api "$ERRMSG" "$ANCHOR_REASON"' '|| fail_api "$ERRMSG"' row_V26
mutant M45 'NOW_EPOCH - anchor_epoch > STALL_MINUTES * 60' 'NOW_EPOCH - anchor_epoch >= STALL_MINUTES * 60' row_V24 row_V25
mutant M46 '[.[].check_suites[] | .created_at | fromdateiso8601]' '[.[0].check_suites[] | .created_at | fromdateiso8601]' row_V25
mutant M47 '(min | tostring)' '(.[0] | tostring)' row_V25
mutant M48 '(min | tostring)' '(.[-1] | tostring)' row_V25
mutant M49 '[.[].check_suites[] | .created_at | fromdateiso8601]' '[.[-1].check_suites[] | .created_at | fromdateiso8601]' row_V25
# `required` mutants (Guard 3, #9927: `complete` only on a proven-complete required set). Every kill row asserts the exact state AND
# reason. Not mutated, each with its reason: the dispatch case, and the interrupt trap's INT/HUP spellings (only TERM is sent, by R13; the
# three share one trap line, so the TERM mutant removes all of them). The byte-exact round trip and the rc 3/4 pass-through are mutated below
# (rows R6 arr-fake-failed-field and rc3-with-gaps / rc4-with-gaps), as are the reason, base and leading-zero axes.
mutant M50 'AM_NA == 0 && AM_NP == 0 && AM_NF == 0' 'AM_NA == 0 && AM_NP == 0' row_R8
mutant M51 'AM_NA == 0 && AM_NP == 0 && AM_NF == 0' 'AM_NP == 0 && AM_NF == 0' row_R8
mutant M52 'AM_NA == 0 && AM_NP == 0 && AM_NF == 0' 'AM_NA == 0 && AM_NF == 0' row_R8
mutant M53 'CL_REASON="$AM_REASON"; [[ "$AM_REASON" == not-green ]] && CL_REASON=no-culprit' 'CL_STATE=pending; CL_REASON="$AM_REASON"' row_R7
mutant M54 '  if (( AM_NA + AM_NP + AM_NF == 0 )); then
    CL_REASON=' '  if (( AM_REQ == 0 )); then CL_REASON=required-unknown; return 0; fi
  if (( AM_NA + AM_NP + AM_NF == 0 )); then
    CL_REASON=' row_R7
mutant M55 '[[ "$AM_REASON" == not-green ]] && CL_REASON=no-culprit' ':' row_R7
mutant M56 '  if (( AM_NF > 0 )); then CL_STATE=failed
  elif (( AM_NA > 0 )); then CL_STATE=absent' '  if (( AM_NA > 0 )); then CL_STATE=absent
  elif (( AM_NF > 0 )); then CL_STATE=failed' row_R5
mutant M57 '  elif (( AM_NA > 0 )); then CL_STATE=absent
  else CL_STATE=pending; fi' '  elif (( AM_NP > 0 )); then CL_STATE=pending
  else CL_STATE=absent; fi' row_R5
mutant M58 '(( n == 1 )) || { AM_ERR=marker-unparseable; return 1; }' ':' row_R6
mutant M59 'line="$(tail -n 1 "$f")"' 'line="$(grep '\''^SOLEUR_ADMIN_MERGE_READY '\'' "$f")"' row_R6
mutant M60 '(( n >= 1 )) || { AM_ERR=no-marker; return 1; }' ':' row_R6
mutant M61 '"${BASH_REMATCH[3]}" == "$PR_SHA"' '"${BASH_REMATCH[3]}" == "${BASH_REMATCH[3]}"' row_R6
mutant M62 '"${BASH_REMATCH[2]}" == "$PR"' '"${BASH_REMATCH[2]}" == "${BASH_REMATCH[2]}"' row_R6
mutant M63 'case "$rc:$AM_VERDICT" in 0:ready|1:not-ready|3:error|4:stale) : ;; *) CL_REASON="rc-mismatch"; return 0 ;; esac' ':' row_R6
mutant M64 'case "$rc" in 0|1|3|4) : ;; *)' 'case "$rc" in 0|1|2|3|4|130) : ;; *)' row_R6
mutant M65 'jq -es '\''length == 1 and (.[0] | type == "array")' 'jq -es '\''length >= 1 and (.[0] | type == "array")' row_R6
mutant M66 'and ((explode | any(. < 32 or . == 127 or (. >= 128 and . <= 159) or . == 8232 or . == 8233)) | not)' 'and true' row_R6
mutant M67 '(( AM_NA + AM_NP + AM_NF <= AM_REQ )) || { AM_ERR=marker-unparseable; return 1; }' ':' row_R6
mutant M68 'if (( AM_REQ > 0 )); then' 'if (( AM_REQ >= 0 )); then' row_R8
mutant M69 'req_marker error "$reason" - - - -' 'req_marker error "$reason" - '\''[]'\'' '\''[]'\'' '\''[]'\''' row_R6
mutant M70 '[[ "$sha" == unknown ]] && sha="-"' ':' row_R6
mutant M71 'printf '\''RECOVERY rerun run=%s basis=workflow' 'gh run rerun "$id" >/dev/null 2>&1; printf '\''RECOVERY rerun run=%s basis=workflow' row_R2
mutant M72 'printf '\''RECOVERY rerun run=%s basis=candidate' 'gh run rerun "$id" >/dev/null 2>&1; printf '\''RECOVERY rerun run=%s basis=candidate' row_R3
mutant M73 'printf '\''RECOVERY owner not determined (read failed) ctx=%s\n'\'' "$ctxj"' 'fail_api "recovery read failed" api-error' row_R4
mutant M74 'if (( AM_NA == 0 && AM_NP == 0 && AM_NF == 0 )); then CL_STATE=complete' 'if (( AM_NA != 0 || AM_NP != 0 || AM_NF != 0 )); then CL_STATE=complete' row_R1 row_RE1
mutant M75 '--base "$PR_BASE" >' '>' row_R10
mutant M76 '--base "$PR_BASE" >' '--base "$PR_BASE" --wait >' row_R1
mutant M77 '[[ "$PR_BASE" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]*$ ]] || fail_api "the PR base branch is empty or not a plain branch name" bad-base' ':' row_R9
mutant M78 '(.base.ref // "")' '("main")' row_R10 row_R9
mutant M79 '. != "test" or $r != "stalled"' '$r != "stalled"' row_R4
mutant M80 'if [[ "$ctx" == test && "$CL_REASON" == stalled ]]; then' 'if [[ "$CL_REASON" == stalled ]]; then' row_R4
mutant M81 'if length == 1 then "W' 'if length >= 1 then "W' row_R3
mutant M82 '| sort_by(.id) | reverse' '| sort_by(.id)' row_R3
mutant M83 'select(.head_sha == $h and .conclusion == "cancelled"' 'select(.conclusion == "cancelled"' row_R2
mutant M84 '.conclusion == "cancelled" and (.id | type)' '.conclusion != null and (.id | type)' row_R2
mutant M85 'if [[ "$CL_REASON" == awaiting-approval ]]; then' 'if false; then' row_R4
mutant M86 'if [[ "$CL_REASON" == stale-row ]]; then' 'if false; then' row_R4
mutant M87 '(( need == 1 )) && try_read_cancelled' ':' row_R2
mutant M88 'elif [[ "$(jq -r '\''length'\'' "$WORK/cancelled.json")" == 0 ]]; then' 'elif false; then' row_R2
# Review-fix mutants (S1-S10, S13: the control-character set, the round trip, the rc 3/4 pass-through, the base and reason axes, the 10# prefix and
# digit cap, the recovery id / key / cut / clean guards, the signal trap, the PR argument, the non-fatal base, the production path, the header).
mutant M89 'any(. < 32 or . == 127 or (. >= 128' 'any(. < 32 or (. >= 128' row_R6
mutant M90 ' or (. >= 128 and . <= 159) or . == 8232 or . == 8233)) | not)' ' or . == 8232 or . == 8233)) | not)' row_R6
mutant M91 ' or . == 8232 or . == 8233)) | not)' ')) | not)' row_R6
mutant M92 '(explode | any(. < 32 or . == 127' '(explode | any(. < 31 or . == 127' row_R6
mutant M93 '[[ "$a pending=$p failed=$fl" == "$tail" ]] || { AM_ERR=marker-unparseable; return 1; }' ':' row_R6
mutant M94 'case "$rc" in 3|4) CL_REASON="$AM_REASON"; return 0 ;; esac' ':' row_R6
mutant M95 '[[ "$AM_BASE" == "$PR_BASE" ]] || { CL_REASON="marker-mismatch"; return 0; }' ':' row_R6
mutant M96 '[[ "$AM_REASON" == all-green ]] || { CL_REASON="rc-mismatch"; return 0; }' ':' row_R6
mutant M97 'AM_REQ=$((10#${BASH_REMATCH[6]}))' 'AM_REQ=$((${BASH_REMATCH[6]}))' row_R8
mutant M98 'required=([0-9]{1,9})' 'required=([0-9]+)' row_R6
mutant M99 'and (.id | tostring | test("^[0-9]{1,15}$"))) ]' 'and true) ]' row_R12
mutant M100 'select($k != "" and .n == $k)' 'select(.n == $k)' row_R12
mutant M101 'tostring | clean | .[0:80]' 'tostring | clean' row_R12
mutant M102 'tostring | clean | .[0:80]' 'tostring | .[0:80]' row_R12
mutant M103 "trap 'fail_api \"interrupted\" interrupted' INT TERM HUP" ':' row_R13
mutant M104 '  # The marker is the last thing printed: a signal after this point must not print a second one.
  trap - INT TERM HUP
' '' row_R13
mutant M105 'trap - INT TERM HUP; fail_api "admin-merge-ready.sh gave' 'fail_api "admin-merge-ready.sh gave' row_R13
mutant M106 'PR=$((10#$PR))' ':' row_R14
mutant M107 '^[0-9]{1,15}$ ]] || usage_error' '^[0-9]+$ ]] || usage_error' row_R14
mutant M108 '2>/dev/null)" || PR_BASE=""' '2>/dev/null)"' row_R14
mutant M109 'admin-merge-ready.sh}"' 'admin-merge-readyX.sh}"' row_RE6
mutant M110 ' required-unknown no-culprit bad-base interrupted.' ' required-unknown bad-base interrupted.' row_R11
mutant M111 'confirm in the Actions tab that no ready run is still in flight, the undo cancels it; then gh pr ready --undo, then gh pr ready, with a user token)\n'"'"' "$ctxj"' 'gh pr ready --undo, then gh pr ready, with a user token)\n'"'"' "$ctxj"' row_R4 row_RE3
mutant M113 'or (. >= 128 and . <= 159) or . == 8232 or . == 8233 then 32' 'or . == 8232 or . == 8233 then 32' row_R12
mutant M114 'or . == 8232 or . == 8233 then 32' 'then 32' row_R12
mutant M112 'confirm in the Actions tab that no ready run is still in flight, the undo cancels it; then gh pr ready --undo, then gh pr ready, with a user token)\n'"'"'
      else' 'gh pr ready --undo, then gh pr ready, with a user token)\n'"'"'
      else' row_R4 row_RE3
mutant_selftest

# ── the floor: every row counted, every verdict accounted for ──────────────────────────────
# Reported through printf + exit, never through pass()/fail() (they are what it backstops).
# MIN_ASSERTIONS and MIN_MUTANTS are LOWER BOUNDS (the measured counts at the last edit); raise them in the same edit as a new row.
MIN_ASSERTIONS=1013
if [[ "$ASSERTED" -lt "$MIN_ASSERTIONS" ]]; then
  printf '[FATAL] anti-vacuity floor: only %s assertions ran, floor is %s\n' "$ASSERTED" "$MIN_ASSERTIONS" >&2; exit 1
fi
if [[ $((passes + fails)) -ne "$VERDICTS_EXPECTED" ]]; then
  printf '[FATAL] accounting: %s verdicts recorded for %s rows and mutants\n' "$((passes + fails))" "$VERDICTS_EXPECTED" >&2; exit 1
fi
MIN_MUTANTS=112
if [[ "$MUT_RUN" -lt "$MIN_MUTANTS" ]]; then
  printf '[FATAL] mutation floor: only %s mutants ran, floor is %s\n' "$MUT_RUN" "$MIN_MUTANTS" >&2; exit 1
fi

echo ""
echo "ci-head-verdict.test.sh: $passes passed, $fails failed ($ASSERTED assertions, $MUT_PASS/$MUT_RUN mutants killed)"
if [[ "$fails" -gt 0 ]]; then printf '  failed: %s\n' "${FAILED[@]}" >&2; exit 1; fi
exit 0
