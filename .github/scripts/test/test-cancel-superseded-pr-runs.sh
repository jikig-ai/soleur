#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2016  # `c && pass || fail` is safe (pass returns 0); literal `${{` / backticks are intended
# Fixture tests for .github/scripts/cancel-superseded-pr-runs.sh — the reaper that
# cancel-superseded-pr-runs.yml runs on every same-repo PR push. It cancels runs, so its
# safety envelope is pinned here (plan §Guard Contract, Guard 1): it never cancels a
# current-head run, a run outside this PR's PR-scoped events, or a run newer than itself.
#
# Two layers:
#   S* — the pure `select` mode, fed jq-synthesized run objects (no real run ids). Every
#        rule has a row that FIRES it and a row one field away that PASSES THROUGH it.
#   O* — the `run` mode against a PATH-shimmed `gh` that serves canned responses per URL,
#        REFUSES any request it does not expect (exit 64, logged), and records every call
#        so call ORDER and call SHAPE are asserted, not inferred.
#   W* — the workflow's wiring (trigger, permissions, default-branch checkout, env-only
#        use of PR-controlled values).
#
# Bash + jq only (run-all.sh contract, #6454): this suite gates every PR.
set -uo pipefail
export LC_ALL=C

REPO_ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
SCRIPT="$REPO_ROOT/.github/scripts/cancel-superseded-pr-runs.sh"
WORKFLOW="$REPO_ROOT/.github/workflows/cancel-superseded-pr-runs.yml"
[[ -f "$SCRIPT" ]] || { echo "FAIL: $SCRIPT not found"; exit 1; }
[[ -f "$WORKFLOW" ]] || { echo "FAIL: $WORKFLOW not found"; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
pass() { echo "PASS [$1]"; PASS=$((PASS+1)); }
fail() { echo "FAIL [$1]: $2"; FAIL=$((FAIL+1)); }

# Instrument self-test: both helpers must move their counters, or every verdict below
# is meaningless. Reported with printf+exit, never through the helpers it checks.
pass "selftest-pass" >/dev/null
fail "selftest-fail" "expected" >/dev/null
if [[ "$PASS" -ne 1 || "$FAIL" -ne 1 ]]; then
  printf 'FATAL: pass()/fail() did not move their counters (PASS=%s FAIL=%s)\n' "$PASS" "$FAIL"
  exit 1
fi
PASS=0
FAIL=0

# ---------------------------------------------------------------------------
# Selection layer
# ---------------------------------------------------------------------------
CUR="$(printf 'a%.0s' $(seq 1 40))"   # the PR head
OLD="$(printf 'b%.0s' $(seq 1 40))"   # a superseded head
SELF_AT="2026-09-24T12:00:00Z"
BASE='{"id":0,"name":"CI","event":"pull_request","status":"queued","head_branch":"feat-x","head_sha":"'"$OLD"'","created_at":"2026-09-24T10:00:00Z","head_repository":{"full_name":"acme/widgets"},"path":".github/workflows/ci.yml","pull_requests":[{"number":12}]}'

# r '<jq object/filter applied over BASE>' — one compact run object.
r() { jq -c -n --argjson b "$BASE" "\$b + $1"; }

# sel <fixture-file> [VAR=value ...] — select output (TSV) for the fixture array.
sel() {
  local f="$1"; shift
  env HEAD_SHA="$CUR" HEAD_REF="feat-x" HEAD_REPO="acme/widgets" PR_NUMBER=12 \
      SELF_RUN_ID=9000 SELF_CREATED_AT="$SELF_AT" DEFAULT_BRANCH=main "$@" \
      bash "$SCRIPT" select < "$f"
}

# fx <name> <run-object>... — write a JSON array fixture, print its path.
fx() {
  local name="$1"; shift
  printf '%s\n' "$@" | jq -s '.' > "$TMP/$name.json"
  printf '%s' "$TMP/$name.json"
}

# expect <label> <tsv-output> <id> "<decision> <reason>"
expect() {
  local got
  got=$(awk -F '\t' -v id="$3" '$2 == id { print $1 " " $3 }' <<< "$2")
  if [[ "$got" == "$4" ]]; then pass "$1"; else fail "$1" "id=$3 expected '$4', got '${got:-<no row>}'"; fi
}

# S0 — rule 0: context validation.
F=$(fx s0 "$(r '{id:1}')")
out=$(sel "$F" SELF_CREATED_AT=null);    expect "S0a self_created=null" "$out" 1 "skip bad-context"
out=$(sel "$F" SELF_CREATED_AT=);        expect "S0b self_created empty" "$out" 1 "skip bad-context"
out=$(sel "$F" SELF_CREATED_AT="2026-09-24 12:00:00"); expect "S0a non-ISO self_created" "$out" 1 "skip bad-context"
out=$(sel "$F" HEAD_SHA="${CUR:0:39}");  expect "S0c head_sha 39 hex" "$out" 1 "skip bad-context"
out=$(sel "$F" HEAD_SHA="${CUR^^}");     expect "S0c head_sha uppercase" "$out" 1 "skip bad-context"
out=$(sel "$F");                         expect "S0 valid context passes through" "$out" 1 "cancel superseded"

# S1 — rule 1: missing/null fields fail closed.
F=$(fx s1 "$(r '{id:1} | del(.head_sha)')" "$(r '{id:2, created_at:null}')" "$(r '{id:3} | del(.event)')" \
          "$(r '{id:4, status:null}')" "$(r '{id:5, head_sha:12345}')" "$(r '{id:6, created_at:"yesterday"}')" \
          "$(r '{id:7}')" "$(r '{id:null}')")
out=$(sel "$F")
expect "S1 head_sha absent" "$out" 1 "skip malformed"
expect "S1 created_at null" "$out" 2 "skip malformed"
expect "S1 event absent" "$out" 3 "skip malformed"
expect "S1 status null" "$out" 4 "skip malformed"
expect "S1 head_sha non-string" "$out" 5 "skip malformed"
expect "S1 created_at non-ISO" "$out" 6 "skip malformed"
expect "S1 all present passes through" "$out" 7 "cancel superseded"
if [[ "$(grep -c '^skip	-	malformed' <<< "$out")" == "1" ]]; then pass "S1 id null"; else fail "S1 id null" "expected one malformed row with id '-': $out"; fi
if ! grep -q '^cancel' <<< "$(grep -v '	7	' <<< "$out")"; then pass "S1 no malformed row is cancelled"; else fail "S1 no malformed row is cancelled" "$out"; fi

# S1p — rule 1/5: an absent path is "" (never a jq error).
F=$(fx s1p "$(r '{id:1, event:"dynamic", head_branch:"refs/pull/12/head"} | del(.path)')" "$(r '{id:2} | del(.path)')")
out=$(sel "$F"); rc=$?
[[ "$rc" == 0 ]] && pass "S1p select rc=0 on absent path" || fail "S1p select rc=0 on absent path" "rc=$rc"
expect "S1p dynamic without path" "$out" 1 "skip dynamic-path"
expect "S1p pull_request without path" "$out" 2 "cancel superseded"

# S2 — rule 2: self (numeric compare via --argjson).
F=$(fx s2 "$(r '{id:9000}')" "$(r '{id:9001}')")
out=$(sel "$F")
expect "S2 self" "$out" 9000 "skip self"
expect "S2 id+1 passes through" "$out" 9001 "cancel superseded"

# S3 — rule 3: event allowlist.
F=$(fx s3 "$(r '{id:1, event:"push"}')" "$(r '{id:2, event:"schedule"}')" "$(r '{id:3, event:"workflow_run"}')" \
          "$(r '{id:4, event:"workflow_dispatch"}')" "$(r '{id:5, event:"merge_group"}')" "$(r '{id:6, event:"issue_comment"}')" \
          "$(r '{id:7, event:"pull_request"}')" "$(r '{id:8, event:"pull_request_target"}')" \
          "$(r '{id:9, event:"dynamic", head_branch:"refs/pull/12/head", path:"dynamic/github-code-scanning/codeql"}')" \
          "$(r '{id:10, event:"pull"}')")
out=$(sel "$F")
for i in 1 2 3 4 5 6 10; do expect "S3 event id=$i" "$out" "$i" "skip event"; done
expect "S3 pull_request passes" "$out" 7 "cancel superseded"
expect "S3 pull_request_target passes" "$out" 8 "cancel superseded"
expect "S3 dynamic passes" "$out" 9 "cancel superseded"

# S4 — rule 4: default branch, reachable form (a same-repo PR opened FROM main).
F=$(fx s4 "$(r '{id:1, head_branch:"main"}')" "$(r '{id:2, head_branch:"refs/heads/main"}')")
out=$(sel "$F" HEAD_REF=main)
expect "S4 PR from main" "$out" 1 "skip default-branch"
expect "S4 refs/heads/main" "$out" 2 "skip default-branch"
out=$(sel "$F" HEAD_REF=main DEFAULT_BRANCH=trunk)
expect "S4 default=trunk passes through" "$out" 1 "cancel superseded"

# S5 — rule 5: dynamic path allowlist (with the trailing slash).
D='event:"dynamic", head_branch:"refs/pull/12/head"'
F=$(fx s5 "$(r "{id:1, $D, path:\"dynamic/dependabot/dependabot-updates\"}")" \
          "$(r "{id:2, $D, path:\"dynamic/copilot-swe-agent/x\"}")" \
          "$(r "{id:3, $D, path:\"dynamic/github-code-scanning/codeql\"}")" \
          "$(r "{id:4, $D, path:\"dynamic/github-code-quality/codeql\"}")" \
          "$(r "{id:5, $D, path:\"dynamic/github-code-scanning-evil/x\"}")")
out=$(sel "$F")
expect "S5 dependabot dynamic" "$out" 1 "skip dynamic-path"
expect "S5 unknown dynamic" "$out" 2 "skip dynamic-path"
expect "S5 code-scanning passes" "$out" 3 "cancel superseded"
expect "S5 code-quality passes" "$out" 4 "cancel superseded"
expect "S5b prefix trap" "$out" 5 "skip dynamic-path"

# S6 — rule 6: dynamic branch key is exact.
P='path:"dynamic/github-code-scanning/codeql", event:"dynamic"'
F=$(fx s6 "$(r "{id:1, $P, head_branch:\"refs/pull/13/head\"}")" "$(r "{id:2, $P, head_branch:\"refs/pull/120/head\"}")" \
          "$(r "{id:3, $P, head_branch:\"refs/pull/12/head\"}")" "$(r "{id:4, $P, head_branch:\"feat-x\"}")")
out=$(sel "$F")
expect "S6 other PR" "$out" 1 "skip branch"
expect "S6b N0 not a prefix match" "$out" 2 "skip branch"
expect "S6 this PR passes" "$out" 3 "cancel superseded"
expect "S6 dynamic on head branch name" "$out" 4 "skip branch"

# S7 — rule 7: PR branch; S7b a stacked PR on the same branch is still superseded.
F=$(fx s7 "$(r '{id:1, head_branch:"feat-y"}')" "$(r '{id:2, pull_requests:[{number:99}]}')" "$(r '{id:3, head_branch:null}')")
out=$(sel "$F")
expect "S7 other branch" "$out" 1 "skip branch"
expect "S7b stacked PR same branch" "$out" 2 "cancel superseded"
expect "S7 null head_branch" "$out" 3 "skip branch"

# S8 — rule 8: head repository.
F=$(fx s8 "$(r '{id:1, head_repository:{full_name:"evil/widgets"}}')" "$(r '{id:2} | del(.head_repository)')" \
          "$(r '{id:3, event:"pull_request_target", head_repository:{full_name:"evil/widgets"}}')" \
          "$(r '{id:4, event:"pull_request_target"}')" "$(r '{id:5, head_repository:"acme/widgets"}')")
out=$(sel "$F")
expect "S8 fork same branch name" "$out" 1 "skip repo"
expect "S8 head_repository absent" "$out" 2 "skip repo"
expect "S8t fork pull_request_target" "$out" 3 "skip repo"
expect "S8t same-repo pull_request_target (CLA shape)" "$out" 4 "cancel superseded"
expect "S8 head_repository wrong type" "$out" 5 "skip repo"

# S9 / S9b — rule 9 status allowlist, rule 9b privileged in-progress.
F=$(fx s9 "$(r '{id:1, status:"completed"}')" "$(r '{id:2, status:"action_required"}')" \
          "$(r '{id:3, status:"queued"}')" "$(r '{id:4, status:"in_progress"}')" "$(r '{id:5, status:"waiting"}')" \
          "$(r '{id:6, status:"pending"}')" "$(r '{id:7, status:"requested"}')" \
          "$(r '{id:8, event:"pull_request_target", status:"in_progress"}')" \
          "$(r '{id:9, event:"pull_request_target", status:"queued"}')")
out=$(sel "$F")
expect "S9 completed" "$out" 1 "skip status"
expect "S9 action_required" "$out" 2 "skip status"
for i in 3 4 5 6 7; do expect "S9 active status id=$i" "$out" "$i" "cancel superseded"; done
expect "S9b pull_request_target in_progress" "$out" 8 "skip privileged-in-progress"
expect "S9b pull_request_target queued" "$out" 9 "cancel superseded"

# S10 — rule 10: the current head is never cancelled, in any active status (P2).
F=$(fx s10 "$(r "{id:1, head_sha:\"$CUR\", status:\"queued\"}")" "$(r "{id:2, head_sha:\"$CUR\", status:\"in_progress\"}")" \
           "$(r "{id:3, head_sha:\"$CUR\", status:\"waiting\"}")" "$(r "{id:4, head_sha:\"$CUR\", status:\"pending\"}")" \
           "$(r "{id:5, head_sha:\"$CUR\", status:\"requested\"}")" \
           "$(r "{id:6, head_sha:\"$CUR\", event:\"dynamic\", head_branch:\"refs/pull/12/head\", path:\"dynamic/github-code-scanning/codeql\"}")" \
           "$(r "{id:7, head_sha:\"${CUR:0:39}b\"}")")
out=$(sel "$F")
for i in 1 2 3 4 5 6; do expect "S10 current head id=$i" "$out" "$i" "skip current-head"; done
expect "S10 last char differs" "$out" 7 "cancel superseded"

# S11 — rule 11: created at/after this run is too new (P4).
F=$(fx s11 "$(r "{id:1, created_at:\"$SELF_AT\"}")" "$(r '{id:2, created_at:"2026-09-24T12:00:01Z"}')" \
           "$(r '{id:3, created_at:"2026-09-24T11:59:59Z"}')")
out=$(sel "$F")
expect "S11 same second" "$out" 1 "skip too-new"
expect "S11 one second later" "$out" 2 "skip too-new"
expect "S11 one second earlier" "$out" 3 "cancel superseded"

# S12 — every member is decided, in input order (no first()/limit()).
F=$(fx s12 "$(r '{id:21}')" "$(r "{id:22, head_sha:\"$CUR\"}")" "$(r '{id:23}')" "$(r '{id:9000}')")
out=$(sel "$F")
got=$(awk -F '\t' '{ printf "%s:%s:%s ", $2, $1, $3 }' <<< "$out")
want="21:cancel:superseded 22:skip:current-head 23:cancel:superseded 9000:skip:self "
[[ "$got" == "$want" ]] && pass "S12 second member" || fail "S12 second member" "got '$got'"

# S13 — @tsv: a TAB/newline in a name cannot forge a row; empty fields are sentinelled.
F=$(fx s13 "$(r '{id:31, name:"evil\tname\nskip\t32\tforged"}')" "$(r '{id:33, name:""}')")
out=$(sel "$F")
[[ "$(wc -l <<< "$out" | tr -d ' ')" == "2" ]] && pass "S13 one row per run" || fail "S13 one row per run" "$out"
expect "S13 crafted name still decided" "$out" 31 "cancel superseded"
if awk -F '\t' '$2 == 33 && NF == 6 && $5 == "-"' <<< "$out" | grep -q .; then pass "S13 empty name sentinelled"; else fail "S13 empty name sentinelled" "$out"; fi

# H7 — non-canonical input (extra fields, reordered keys) decides identically.
F=$(fx h7 '{"zzz":1,"status":"queued","pull_requests":[],"head_repository":{"full_name":"acme/widgets","x":2},"created_at":"2026-09-24T10:00:00Z","head_sha":"'"$OLD"'","head_branch":"feat-x","event":"pull_request","name":"CI","id":41,"extra":{"a":[1]}}')
out=$(sel "$F")
expect "H7 extra fields + reordered keys" "$out" 41 "cancel superseded"

# select usage errors.
F=$(fx s0 "$(r '{id:1}')")
sel "$F" SELF_RUN_ID=abc >/dev/null 2>&1; rc=$?
[[ "$rc" == 2 ]] && pass "S select non-numeric SELF_RUN_ID exits 2" || fail "S select non-numeric SELF_RUN_ID exits 2" "rc=$rc"
sel "$F" PR_NUMBER= >/dev/null 2>&1; rc=$?
[[ "$rc" == 2 ]] && pass "S select empty PR_NUMBER exits 2" || fail "S select empty PR_NUMBER exits 2" "rc=$rc"

# ---------------------------------------------------------------------------
# Orchestration layer — PATH-shimmed gh
# ---------------------------------------------------------------------------
BIN="$TMP/bin"
mkdir -p "$BIN"
# gh stub. State (per case, under $MOCK):
#   pr_created            PR created_at
#   self_created          this run's created_at (may be the literal null)
#   heads                 space-separated head SHAs served in order to .head.sha reads (last repeats)
#   runs/<enc-branch>     NDJSON served for that branch key; list_fail => HTTP 500
#   cancel/<id>           "<code>|<stderr message>" (default 202)
# Every call is logged to $MOCK/log. A request the stub does not recognise is logged
# as UNEXPECTED and exits 64, so a wrong URL/flag cannot read a fixture by accident.
cat > "$BIN/gh" <<'STUB'
#!/usr/bin/env bash
set -uo pipefail
M="${MOCK:?unset}"
printf '%s\n' "$*" >> "$M/log"
refuse() { echo "UNEXPECTED gh $*" >> "$M/log"; echo "gh-stub: unexpected request: $*" >&2; exit 64; }
[[ "${1:-}" == "api" ]] || refuse "$@"
shift
if [[ "${1:-}" == "rate_limit" && "${2:-}" == "--jq" && "${3:-}" == ".resources.core.remaining" ]]; then
  echo 4321; exit 0
fi
if [[ "${1:-}" == "--paginate" ]]; then
  url="${2:-}"
  [[ "${3:-}" == "--jq" && "${4:-}" == ".workflow_runs[]" && $# -eq 4 ]] || refuse "$@"
  [[ "$url" =~ ^repos/acme/widgets/actions/runs\?branch=([^&]+)\&created=%3E%3D([0-9-]{10})\&per_page=100$ ]] || refuse "$@"
  enc="${BASH_REMATCH[1]}"
  if [[ -f "$M/list_fail" ]]; then
    echo '{"message":"Server Error","status":"500"}'; echo "gh: Server Error (HTTP 500)" >&2; exit 1
  fi
  [[ -f "$M/runs/$enc" ]] && cat "$M/runs/$enc"
  exit 0
fi
if [[ "${1:-}" == "-i" && "${2:-}" == "-X" && "${3:-}" == "POST" && $# -eq 4 ]]; then
  [[ "$4" =~ ^repos/acme/widgets/actions/runs/([0-9]+)/cancel$ ]] || refuse "$@"
  id="${BASH_REMATCH[1]}"
  spec="202|"; [[ -f "$M/cancel/$id" ]] && spec="$(<"$M/cancel/$id")"
  code="${spec%%|*}"; msg="${spec#*|}"
  if [[ "$code" == "202" ]]; then printf 'HTTP/2.0 202 Accepted\r\ncontent-type: application/json\r\n\r\n{}\n'; exit 0; fi
  printf 'HTTP/2.0 %s Err\r\ncontent-type: application/json\r\n\r\n{"message":"%s","status":"%s"}\n' "$code" "$msg" "$code"
  echo "gh: $msg (HTTP $code)" >&2
  exit 1
fi
if [[ "$#" -eq 3 && "${2:-}" == "--jq" ]]; then
  case "$1|$3" in
    "repos/acme/widgets/pulls/12|.created_at") cat "$M/pr_created"; exit 0 ;;
    "repos/acme/widgets/actions/runs/9000|.created_at") cat "$M/self_created"; exit 0 ;;
    "repos/acme/widgets/pulls/12|.head.sha")
      n=$(( $(cat "$M/head_n" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$M/head_n"
      read -ra hs < "$M/heads"
      idx=$(( n - 1 )); (( idx >= ${#hs[@]} )) && idx=$(( ${#hs[@]} - 1 ))
      echo "${hs[$idx]}"; exit 0 ;;
  esac
fi
refuse "$@"
STUB
chmod +x "$BIN/gh"

C_SHA="$(printf 'c%.0s' $(seq 1 40))"
ENC_HEAD="feat-x"
ENC_PULL="refs%2Fpull%2F12%2Fhead"
CASE=0
# new_case — fresh mock dir; defaults: PR created today, self at SELF_AT, head = CUR.
new_case() {
  CASE=$((CASE + 1))
  MOCK="$TMP/case$CASE"
  mkdir -p "$MOCK/runs" "$MOCK/cancel"
  : > "$MOCK/log"
  echo "2026-09-24T09:00:00Z" > "$MOCK/pr_created"
  echo "$SELF_AT" > "$MOCK/self_created"
  echo "$CUR" > "$MOCK/heads"
  export MOCK
}
# runs_on <enc-branch> <run-object>... — NDJSON served for that branch key.
runs_on() { local b="$1"; shift; printf '%s\n' "$@" >> "$MOCK/runs/$b"; }
# orch [VAR=value ...] — run the script in run mode; sets OUT (stdout+stderr) and RC.
orch() {
  OUT=$(env PATH="$BIN:$PATH" REPO=acme/widgets PR_NUMBER=12 EVENT_HEAD_SHA="$CUR" HEAD_REF=feat-x \
        HEAD_REPO=acme/widgets DEFAULT_BRANCH=main SELF_RUN_ID=9000 CSPR_HEAD_RETRY_SLEEP=0 \
        GITHUB_STEP_SUMMARY= "$@" bash "$SCRIPT" 2>&1)
  RC=$?
}
cancels() { grep -c '/cancel' "$MOCK/log" | tr -d ' '; }
cancelled_ids() { sed -nE 's#.*actions/runs/([0-9]+)/cancel.*#\1#p' "$MOCK/log" | sort | tr '\n' ' '; }
no_unexpected() {
  if grep -q '^UNEXPECTED' "$MOCK/log"; then fail "$1 stub saw no unexpected request" "$(grep '^UNEXPECTED' "$MOCK/log")"
  else pass "$1 stub saw no unexpected request"; fi
}
# line_of <pattern> — first log line number matching (0 if none).
line_of() { local n; n=$(grep -n -- "$1" "$MOCK/log" | head -1 | cut -d: -f1); printf '%s' "${n:-0}"; }
last_line_of() { local n; n=$(grep -n -- "$1" "$MOCK/log" | tail -1 | cut -d: -f1); printf '%s' "${n:-0}"; }

# O-happy — the basic reap, with the call order and URL shape pinned.
new_case
runs_on "$ENC_HEAD" "$(r '{id:101}')" "$(r "{id:102, head_sha:\"$CUR\"}")" "$(r '{id:9000, head_sha:"'"$CUR"'"}')" \
                    "$(r '{id:103, event:"push"}')"
runs_on "$ENC_PULL" "$(r '{id:104, event:"dynamic", head_branch:"refs/pull/12/head", path:"dynamic/github-code-scanning/codeql"}')"
orch
[[ "$RC" == 0 ]] && pass "O happy rc=0" || fail "O happy rc=0" "rc=$RC out=$OUT"
[[ "$(cancelled_ids)" == "101 104 " ]] && pass "O happy cancels exactly the superseded runs" || fail "O happy cancels exactly the superseded runs" "$(cancelled_ids)"
grep -q 'cancel-superseded-pr-runs: pr=#12 head=aaaaaaa listed=5 cancelled=2 skipped=3 failed=0 reasons=current-head:1,event:1,self:1 ratelimit_remaining=4321' <<< "$OUT" \
  && pass "O14 summary line" || fail "O14 summary line" "$OUT"
no_unexpected "O happy"
# O5 — exactly two list URLs, no status=, created>= bound from the PR's created_at date.
lists=$(grep -- '--paginate' "$MOCK/log" | sed -nE 's#.*(repos/[^ ]+).*#\1#p' | sort | tr '\n' ' ')
want="repos/acme/widgets/actions/runs?branch=feat-x&created=%3E%3D2026-09-24&per_page=100 repos/acme/widgets/actions/runs?branch=refs%2Fpull%2F12%2Fhead&created=%3E%3D2026-09-24&per_page=100 "
[[ "$lists" == "$want" ]] && pass "O5 exact list URL set" || fail "O5 exact list URL set" "$lists"
grep -q 'status=' "$MOCK/log" && fail "O5 no status= filter" "$(grep status= "$MOCK/log")" || pass "O5 no status= filter"
# O2/O13 — head read after both lists; cancels after the head read; graceful only.
lastlist=$(last_line_of '--paginate'); headread=$(line_of '.head.sha'); firstcancel=$(line_of '/cancel')
if (( lastlist > 0 && headread > lastlist && firstcancel > headread )); then pass "O2 order list -> head -> cancel"
else fail "O2 order list -> head -> cancel" "lastlist=$lastlist head=$headread cancel=$firstcancel"; fi
grep -q 'force-cancel' "$MOCK/log" && fail "O13 never force-cancel" "$(cat "$MOCK/log")" || pass "O13 never force-cancel"
[[ "$(grep -c '/cancel$' "$MOCK/log" | tr -d ' ')" == "$(cancels)" ]] && pass "O13 every cancel URL ends in /cancel" || fail "O13 every cancel URL ends in /cancel" "$(cat "$MOCK/log")"
[[ "$(grep -c '\.head\.sha' "$MOCK/log" | tr -d ' ')" == "1" ]] && pass "O happy one head read when it matches" || fail "O happy one head read when it matches" "$(cat "$MOCK/log")"

# O1 — the head differs on all three reads: nothing is cancelled.
new_case
runs_on "$ENC_HEAD" "$(r '{id:101}')"
echo "$C_SHA" > "$MOCK/heads"
orch
[[ "$RC" == 0 ]] && pass "O1 rc=0" || fail "O1 rc=0" "rc=$RC"
[[ "$(cancels)" == 0 ]] && pass "O1 zero cancels" || fail "O1 zero cancels" "$(cat "$MOCK/log")"
[[ "$(grep -c '\.head\.sha' "$MOCK/log" | tr -d ' ')" == "3" ]] && pass "O1 three head reads" || fail "O1 three head reads" "$(cat "$MOCK/log")"
grep -q "event-head=aaaaaaa live-head=ccccccc — head is not this run's" <<< "$OUT" && pass "O1 says why" || fail "O1 says why" "$OUT"
(( $(line_of '.head.sha') > $(last_line_of '--paginate') )) && pass "O1 head reads follow the listing" || fail "O1 head reads follow the listing" "$(cat "$MOCK/log")"

# O2 — API lag: old, old, then the event head -> proceeds.
new_case
runs_on "$ENC_HEAD" "$(r '{id:101}')"
echo "$OLD $OLD $CUR" > "$MOCK/heads"
orch
[[ "$RC" == 0 && "$(cancelled_ids)" == "101 " ]] && pass "O2 lagging head converges and reaps" || fail "O2 lagging head converges and reaps" "rc=$RC ids=$(cancelled_ids)"
[[ "$(grep -c '\.head\.sha' "$MOCK/log" | tr -d ' ')" == "3" ]] && pass "O2 three head reads" || fail "O2 three head reads" "$(cat "$MOCK/log")"

# O3 — A->B->A: the first push of A and the B push are listed; the head reads A.
new_case
runs_on "$ENC_HEAD" "$(r "{id:111, head_sha:\"$CUR\", created_at:\"2026-09-24T09:10:00Z\"}")" \
                    "$(r "{id:112, head_sha:\"$OLD\", created_at:\"2026-09-24T09:20:00Z\"}")"
orch
[[ "$(cancelled_ids)" == "112 " ]] && pass "O3 A->B->A cancels only B" || fail "O3 A->B->A cancels only B" "$(cancelled_ids)"

# O4 — the head moved to C during listing: zero cancels. Variant: C's runs are listed but
# the pulls endpoint still reports A (lag) -> C's runs are too new (rule 11).
new_case
runs_on "$ENC_HEAD" "$(r '{id:121}')"
echo "$C_SHA" > "$MOCK/heads"
orch
[[ "$RC" == 0 && "$(cancels)" == 0 ]] && pass "O4 head moved: zero cancels" || fail "O4 head moved: zero cancels" "rc=$RC $(cat "$MOCK/log")"
new_case
runs_on "$ENC_HEAD" "$(r '{id:121}')" "$(r "{id:122, head_sha:\"$C_SHA\", created_at:\"2026-09-24T12:00:05Z\"}")"
orch
[[ "$(cancelled_ids)" == "121 " ]] && pass "O4 lagged newer push is too new" || fail "O4 lagged newer push is too new" "$(cancelled_ids)"
grep -q 'too-new:1' <<< "$OUT" && pass "O4 too-new counted" || fail "O4 too-new counted" "$OUT"

# O5 — a branch with a slash and a space is URL-encoded.
new_case
orch HEAD_REF="feat/x y"
grep -q 'branch=feat%2Fx%20y&' "$MOCK/log" && pass "O5 branch urlencoded" || fail "O5 branch urlencoded" "$(cat "$MOCK/log")"
no_unexpected "O5 urlencoded"

# O5e — empty listing.
new_case
orch
[[ "$RC" == 0 && "$(cancels)" == 0 ]] && grep -q 'listed=0 cancelled=0 skipped=0 failed=0 reasons=-' <<< "$OUT" \
  && pass "O5e empty listing" || fail "O5e empty listing" "rc=$RC $OUT"

# O6 — the same run from both branch keys is cancelled once.
new_case
runs_on "$ENC_HEAD" "$(r '{id:131}')"
runs_on "$ENC_PULL" "$(r '{id:131}')"
orch
[[ "$(cancelled_ids)" == "131 " ]] && grep -q 'listed=1 ' <<< "$OUT" && pass "O6 dedupe" || fail "O6 dedupe" "$(cancelled_ids) $OUT"

# O7 — 202 / 409 / 404.
new_case
runs_on "$ENC_HEAD" "$(r '{id:141}')" "$(r '{id:142}')" "$(r '{id:143}')"
echo "409|Cannot cancel a workflow run that is completed." > "$MOCK/cancel/142"
echo "404|Not Found" > "$MOCK/cancel/143"
orch
[[ "$RC" == 0 ]] && grep -q 'cancelled=1 skipped=2 failed=0 reasons=gone:2' <<< "$OUT" && pass "O7 202/409/404" || fail "O7 202/409/404" "rc=$RC $OUT"

# O8 — 403 refused on a dynamic run: warning, not red.
new_case
runs_on "$ENC_PULL" "$(r '{id:151, event:"dynamic", head_branch:"refs/pull/12/head", path:"dynamic/github-code-scanning/codeql"}')"
echo "403|Resource not accessible by integration" > "$MOCK/cancel/151"
orch
[[ "$RC" == 0 ]] && grep -q '::warning::' <<< "$OUT" && grep -q 'reasons=refused:1' <<< "$OUT" \
  && pass "O8 dynamic 403 refused is a warning" || fail "O8 dynamic 403 refused is a warning" "rc=$RC $OUT"

# O9 — the same 403 on a pull_request run is red.
new_case
runs_on "$ENC_HEAD" "$(r '{id:161}')"
echo "403|Resource not accessible by integration" > "$MOCK/cancel/161"
orch
[[ "$RC" == 1 ]] && grep -q '::error::.*failed:refused' <<< "$OUT" && pass "O9 pull_request 403 is failed:refused" || fail "O9 pull_request 403 is failed:refused" "rc=$RC $OUT"

# O10 — 429 and a 403 rate limit.
new_case
runs_on "$ENC_HEAD" "$(r '{id:171}')" "$(r '{id:172}')"
echo "429|Too Many Requests" > "$MOCK/cancel/171"
echo "403|API rate limit exceeded for installation" > "$MOCK/cancel/172"
orch
[[ "$RC" == 1 ]] && grep -q 'failed=2 reasons=failed:rate-limited:2' <<< "$OUT" && pass "O10 rate limits" || fail "O10 rate limits" "rc=$RC $OUT"

# O11 — 500 on a cancel.
new_case
runs_on "$ENC_HEAD" "$(r '{id:181}')" "$(r '{id:182}')"
echo "500|Server Error" > "$MOCK/cancel/181"
orch
[[ "$RC" == 1 ]] && grep -q 'cancelled=1 skipped=0 failed=1 reasons=failed:http-500:1' <<< "$OUT" && pass "O11 500 fails, others still cancelled" || fail "O11 500 fails, others still cancelled" "rc=$RC $OUT"

# O12 — a list failure: red, zero cancels, zero head reads.
new_case
runs_on "$ENC_HEAD" "$(r '{id:191}')"
: > "$MOCK/list_fail"
orch
[[ "$RC" == 1 && "$(cancels)" == 0 ]] && grep -q '::error::.*listing runs.*HTTP 500' <<< "$OUT" && pass "O12 list failure" || fail "O12 list failure" "rc=$RC $OUT"
grep -q '\.head\.sha' "$MOCK/log" && fail "O12 no head read after a failed list" "$(cat "$MOCK/log")" || pass "O12 no head read after a failed list"

# O14 — GITHUB_STEP_SUMMARY written when set.
new_case
runs_on "$ENC_HEAD" "$(r '{id:201, name:"Tenant integration"}')"
orch GITHUB_STEP_SUMMARY="$MOCK/summary.md"
grep -q 'cancelled=1 ' "$MOCK/summary.md" 2>/dev/null && grep -q 'cancelled run 201 `Tenant integration`' "$MOCK/summary.md" \
  && pass "O14 step summary written" || fail "O14 step summary written" "$(cat "$MOCK/summary.md" 2>/dev/null)"

# O15 — bad context: exit 2 before any listing.
new_case
orch PR_NUMBER=
[[ "$RC" == 2 && ! -s "$MOCK/log" ]] && pass "O15 missing PR_NUMBER exits 2, no calls" || fail "O15 missing PR_NUMBER exits 2, no calls" "rc=$RC $(cat "$MOCK/log")"
new_case
echo null > "$MOCK/self_created"
orch
[[ "$RC" == 2 ]] && ! grep -q -- '--paginate' "$MOCK/log" && grep -q "::error::.*created_at is not ISO" <<< "$OUT" \
  && pass "O15 self created_at null exits 2 before listing" || fail "O15 self created_at null exits 2 before listing" "rc=$RC $OUT"
new_case
runs_on "$ENC_HEAD" "$(r '{id:211}')"
echo null > "$MOCK/heads"
orch
[[ "$RC" == 2 && "$(cancels)" == 0 ]] && pass "O15 live head null exits 2, zero cancels" || fail "O15 live head null exits 2, zero cancels" "rc=$RC $OUT"
new_case
orch EVENT_HEAD_SHA=abc
[[ "$RC" == 2 && ! -s "$MOCK/log" ]] && pass "O15 bad EVENT_HEAD_SHA exits 2" || fail "O15 bad EVENT_HEAD_SHA exits 2" "rc=$RC"

# O16 — dry run: would-cancel lines, zero POSTs.
new_case
runs_on "$ENC_HEAD" "$(r '{id:221}')" "$(r '{id:222}')"
orch CSPR_DRY_RUN=1
[[ "$RC" == 0 && "$(cancels)" == 0 ]] && [[ "$(grep -c '^would-cancel ' <<< "$OUT" | tr -d ' ')" == 2 ]] \
  && grep -q 'cancelled=0 skipped=0 failed=0 would_cancel=2' <<< "$OUT" && pass "O16 dry run" || fail "O16 dry run" "rc=$RC $OUT"

# O17 — a crafted run name cannot forge a workflow command or a line in the output.
new_case
runs_on "$ENC_HEAD" "$(r '{id:231, name:"::error::pwned x"}')"
orch GITHUB_STEP_SUMMARY="$MOCK/summary.md"
if grep -q '^::error::pwned' <<< "$OUT" || grep -q '::error::pwned' "$MOCK/summary.md"; then fail "O17 name sanitised" "$OUT"
else pass "O17 name sanitised"; fi

# ---------------------------------------------------------------------------
# Workflow wiring
# ---------------------------------------------------------------------------
wf=$(<"$WORKFLOW")
grep -qE '^    types: \[synchronize, reopened\]$' <<< "$wf" && pass "W1 trigger types" || fail "W1 trigger types" "types line"
perm=$(awk '/^permissions:/{f=1;next} f&&/^[^ ]/{f=0} f&&/^  [a-z-]+:/{sub(/ *#.*/,""); gsub(/^ +/,""); print}' "$WORKFLOW" | sort | tr '\n' ' ')
[[ "$perm" == "actions: write contents: read pull-requests: read " ]] && pass "W1 permissions exact" || fail "W1 permissions exact" "$perm"
for clause in "github.event.pull_request.head.repo.full_name == github.repository" \
              "github.actor != 'dependabot[bot]'" "github.triggering_actor != 'dependabot[bot]'" \
              "github.event.pull_request.head.ref != github.event.repository.default_branch"; do
  grep -qF -- "$clause" <<< "$wf" && pass "W2 if: $clause" || fail "W2 if: $clause" "missing"
done
grep -qE '^ +ref: \$\{\{ github\.event\.repository\.default_branch \}\}$' <<< "$wf" && pass "W2 checkout pins default branch" || fail "W2 checkout pins default branch" "ref line"
grep -qE '^ +sparse-checkout: \.github/scripts$' <<< "$wf" && pass "W2 sparse checkout" || fail "W2 sparse checkout" "sparse line"
bad_uses=$(grep -E '^ +(- )?uses: ' "$WORKFLOW" | grep -vE 'uses: [^@]+@[0-9a-f]{40}( |$)' || true)
[[ -z "$bad_uses" ]] && pass "W2 uses: SHA-pinned" || fail "W2 uses: SHA-pinned" "$bad_uses"
# W3 — no ${{ }} expression inside the run: body (PR-controlled values go through env: only).
runbody=$(awk '/^ +run: \|$/{f=1; ind=match($0,/[^ ]/); next} f{ if (match($0,/[^ ]/) && match($0,/[^ ]/) <= ind) f=0; else print }' "$WORKFLOW")
[[ -n "$runbody" ]] && pass "W3 run body extracted" || fail "W3 run body extracted" "empty"
grep -q '\${{' <<< "$runbody" && fail "W3 no expression in run body" "$runbody" || pass "W3 no expression in run body"
grep -qE '^ +bash \.github/scripts/cancel-superseded-pr-runs\.sh$' <<< "$runbody" && pass "W3 runs the default-branch script" || fail "W3 runs the default-branch script" "$runbody"
grep -q 'force-cancel' "$SCRIPT" "$WORKFLOW" && grep -v '^ *#' "$SCRIPT" "$WORKFLOW" | grep -q 'force-cancel' \
  && fail "W4 force-cancel appears only in comments" "found in code" || pass "W4 force-cancel appears only in comments"

# ---------------------------------------------------------------------------
TOTAL=$((PASS + FAIL))
echo ""
echo "$PASS passed, $FAIL failed ($TOTAL assertions)"
# Anti-vacuity floor (= the green count, 2026-09-24): raise when adding rows, never lower it silently.
MIN_ASSERTIONS=128
if (( TOTAL < MIN_ASSERTIONS )); then
  printf 'FAIL: only %s assertions ran, expected >= %s (a block was deleted or short-circuited)\n' "$TOTAL" "$MIN_ASSERTIONS"
  exit 1
fi
(( FAIL == 0 )) || exit 1
exit 0
