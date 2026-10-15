#!/usr/bin/env bash
# Exit-code + branch harness for registry-clientip-alert-7530.sh (#7530 post-merge evidence probe).
#
# THE PROBE'S EXIT CODE IS AN AUTHORIZATION ARTIFACT. The sweeper closes #7530 on exit 0 and REOPENS a
# closed tracker on exit 1. What this file exists to pin:
#   * exit 1 is ONLY a measured contradiction (a non-private clientIP counted by the predicate AS
#     WRITTEN, or the extracted predicate classifying the synthetic table wrongly). A failed apply, an
#     unreadable window, an empty population, a dead positive control and a predicate the probe cannot
#     extract are all exit 3, never 1;
#   * the probe NEVER echoes an address: the sweeper posts its output verbatim into a public issue, and
#     the very thing under test is whether a client address reached the sink. Every case below asserts,
#     on EVERY run, that the output contains no dotted-quad, no `::`-shaped or colon-run address, and
#     none of the 16 synthetic classification literals;
#   * the predicate it runs is the one COMMITTED in betterstack-logs-alerts.tf, extracted and
#     transformed mechanically. The suite compares the SQL the probe sends against the real file's text.
#
# SEAMS (all inert in production: the sweeper's launcher rebuilds the environment from nothing):
#   REG7530_REPO  the git checkout the probe reads history from
#   REG7530_TF    the file the alert SQL is extracted from (default: the committed .tf in the checkout)
#   REG7530_BQ    a betterstack-query.sh stand-in
# plus a PATH-first `gh` stub that answers `pr view` and `run list` from fixture files and RECORDS every
# call (any other verb is a write and is refused and logged).
#
# The stand-in cannot execute ClickHouse, so the ENGINE-semantics arms (classification table, counts) are
# fed from fixture files; what the suite verifies is the probe's construction of each query and its
# grading of the answers. The live engine run is the probe's own job after the merge.
#
# Fixtures are synthesized (cq-test-fixtures-synthesized-only): documentation addresses (RFC 5737 / 3849)
# and private ranges only, as literals in the classification table; fabricated boot ids and credentials.

# shellcheck disable=SC2016  # the mutation rows pass literal sed expressions; nothing is meant to expand
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
SUT="$HERE/registry-clientip-alert-7530.sh"
PROBE="$SUT"
[[ -f "$SUT" ]] || { echo "FATAL: probe not found at $SUT" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "FATAL: jq is required" >&2; exit 2; }
command -v git >/dev/null 2>&1 || { echo "FATAL: git is required" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "FATAL: python3 is required" >&2; exit 2; }

# shellcheck source=plugins/soleur/test/lib/git-fixture-env.sh disable=SC1091
. "$REPO_ROOT/plugins/soleur/test/lib/git-fixture-env.sh"

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

passes=0
fails=0
cases=0
pass() { printf '  PASS: %s\n' "$1"; passes=$((passes + 1)); }
fail() { printf '  FAIL: %s\n' "$1" >&2; fails=$((fails + 1)); }

WORK="$(mktemp -d -t regcip7530.XXXXXXXX)" || { echo "FATAL: mktemp failed" >&2; exit 2; }
assert_fixture_dir "$WORK"
# The suite's OWN stderr is buffered into a file for the whole run and replayed to the real stderr at exit,
# so a green run can PIN that it wrote nothing (a green run that carries error text trains reviewers to
# ignore stderr). fd 4 is the real stderr.
exec 4>&2
STDERR_LOG="$WORK/suite-stderr.log"
exec 2>"$STDERR_LOG"
trap 'cat -- "$STDERR_LOG" >&4 2>/dev/null; rm -rf -- "$WORK"' EXIT
# bash runs no EXIT trap when killed by a bare TERM/INT/HUP, which would drop every buffered stderr line: convert them to exits.
trap 'exit 143' TERM
trap 'exit 130' INT
trap 'exit 129' HUP
git_fixture_env "$WORK" || { printf 'FATAL: git_fixture_env refused %s\n' "$WORK" >&2; exit 2; }

FX="$WORK/fx"
BIN="$WORK/bin"
REPO="$WORK/repo"
OUT="$WORK/out"
MARKER_LOG="$WORK/markers.tsv"
: > "$MARKER_LOG"
assert_fixture_dir "$FX"
assert_fixture_dir "$BIN"
assert_fixture_dir "$REPO"
mkdir -p "$FX" "$BIN" "$REPO/apps/web-platform/infra"

REAL_TF="$REPO_ROOT/apps/web-platform/infra/betterstack-logs-alerts.tf"
[[ -f "$REAL_TF" ]] || { echo "FATAL: the committed alert file is missing at $REAL_TF" >&2; exit 1; }

# ── fabricated identities ─────────────────────────────────────────────────────────────────────
OLDBOOT="2f90a6e4-13bd-4c88-9a02-6b7e4f15c3d1"
NEWBOOT="7d41c0b2-9e53-4a17-b8f6-21c5de0374aa"
THIRDBOOT="5a1e7c93-44f0-4b26-8d71-0e9c2af6b538"
FAKE_GH="ghs_NOT_A_REAL_TOKEN_7530_synthetic"
FAKE_BS_PW="bspw-NOT-A-REAL-PASSWORD-7530"
CANARY="CANARY7530"
HOST="soleur-registry"

# The 16-literal classification table (RFC 5737 / 3849 documentation addresses and private ranges;
# flagged = alerts). Mirrors the committed .tf comment; the probe carries its own copy.
TABLE_LITS=("10.0.1.10:54321" "172.16.0.1:1" "172.31.255.255:9" "192.168.1.1:80" "::ffff:10.0.0.5" "default"
            "198.51.100.7:443" "127.0.0.1:5000" "172.15.0.1:1" "172.32.0.1:9" "192.169.0.1:80" "169.254.169.254:80"
            "100.64.0.1:80" "[2001:db8::1]:80" "2001:db8::1" "::ffff:198.51.100.7")
TABLE_FLAGS=(0 0 0 0 0 0  1 1 1 1 1 1  1 1 1 1)

# ── the fixture git history ───────────────────────────────────────────────────────────────────
git -C "$REPO" init -q || { echo "FATAL: git init failed" >&2; exit 2; }
printf 'c0\n' > "$REPO/apps/web-platform/infra/marker.txt"; git -C "$REPO" add -A && git -C "$REPO" commit -q -m c0 || exit 2
SHA_C0="$(git -C "$REPO" rev-parse HEAD)"
printf 'merge\n' >> "$REPO/apps/web-platform/infra/marker.txt"; git -C "$REPO" add -A && git -C "$REPO" commit -q -m merge || exit 2
SHA_M="$(git -C "$REPO" rev-parse HEAD)"
printf 'd1\n' >> "$REPO/apps/web-platform/infra/marker.txt"; git -C "$REPO" add -A && git -C "$REPO" commit -q -m d1 || exit 2
SHA_D1="$(git -C "$REPO" rev-parse HEAD)"
MAIN_BRANCH="$(git -C "$REPO" rev-parse --abbrev-ref HEAD)"
git -C "$REPO" switch -q -c side "$SHA_C0" || exit 2
printf 'side\n' >> "$REPO/apps/web-platform/infra/marker.txt"; git -C "$REPO" add -A && git -C "$REPO" commit -q -m side || exit 2
SHA_U="$(git -C "$REPO" rev-parse HEAD)"
git -C "$REPO" switch -q "$MAIN_BRANCH" || exit 2
SHA_ABSENT="0000000000000000000000000000000000000abc"

# ── the stubs ─────────────────────────────────────────────────────────────────────────────────
cat > "$BIN/gh" <<'GHEOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FX_DIR/gh.calls"
case "$1 $2" in
  "pr view")
    [[ -f "$FX_DIR/fail-pr" ]] && { echo "gh: HTTP 500" >&2; exit 1; }
    cat "$FX_DIR/pr.json" ;;
  "run list")
    [[ -f "$FX_DIR/fail-runs" ]] && { echo "gh: HTTP 500" >&2; exit 1; }
    cat "$FX_DIR/runs.json" ;;
  *)
    printf '%s\n' "$*" >> "$FX_DIR/writes.log"
    echo "gh stub: refusing $*" >&2
    exit 64 ;;
esac
GHEOF
chmod +x "$BIN/gh"

cat > "$BIN/bq.sh" <<'BQEOF'
#!/usr/bin/env bash
# Mode 2 (flags): the SOLEUR_ZOT_DISK row read. Mode 1 (a SELECT as $1): one of four engine queries,
# told apart by the alias the probe gives each. The SQL of every engine query is saved verbatim.
printf '%s\n' "$*" >> "$FX_DIR/bq.calls"
fail_with() {
  echo "betterstack-query: auth failed for user=stub password=$FAKE_CRED" >&2
  echo "curl: (22) https://stub/?token=$FAKE_CRED"
  exit "$1"
}
if [[ "$1" =~ ^[[:space:]]*SELECT ]]; then
  sql="$1"
  case "$sql" in
    *"arrayJoin("*)      kind=table ;;
    *"AS n_population"*) kind=population ;;
    *"AS n_as_written"*) kind=as_written ;;
    *"AS n_control"*)    kind=control ;;
    *) echo "STUB: unrecognised engine query" >&2; exit 64 ;;
  esac
  printf '%s' "$sql" > "$FX_DIR/sql.$kind"
  rc=0; [[ -f "$FX_DIR/$kind.rc" ]] && rc="$(cat "$FX_DIR/$kind.rc")"
  [[ "$rc" != "0" ]] && fail_with "$rc"
  [[ -f "$FX_DIR/$kind.out" ]] && cat "$FX_DIR/$kind.out"
  exit 0
fi
case "$*" in
  *"--grep SOLEUR_ZOT_DISK"*) : ;;
  *) echo "STUB: probe dropped the SOLEUR_ZOT_DISK grep (argv: $*)" >&2; exit 64 ;;
esac
lim="$(printf '%s\n' "$*" | sed -n 's/.*--limit \([0-9]*\).*/\1/p')"
if [[ -z "$lim" || "$lim" -lt 1000 ]]; then
  echo "STUB: probe must pass an explicit --limit >= 1000, got '$lim'" >&2; exit 64
fi
rc=0; [[ -f "$FX_DIR/disk.rc" ]] && rc="$(cat "$FX_DIR/disk.rc")"
[[ "$rc" != "0" ]] && fail_with "$rc"
# The real tool windows the read by --since; the stand-in does the same so a probe that mis-sets or drops
# the lookback changes what it sees (not only what it asked for).
since="$(printf '%s\n' "$*" | sed -n 's/.*--since \([^ ]*\).*/\1/p')"
if [[ -f "$FX_DIR/disk.jsonl" ]]; then
  if [[ -n "$since" ]]; then
    since_s="$(date -u -d "$since" '+%Y-%m-%d %H:%M:%S')"
    jq -c --arg s "$since_s" 'select(((.dt // "") | tostring | sub("T"; " ") | sub("Z$"; "") | sub("\\.[0-9]+$"; "")) >= $s)' "$FX_DIR/disk.jsonl"
  else
    cat "$FX_DIR/disk.jsonl"
  fi
fi
exit 0
BQEOF
chmod +x "$BIN/bq.sh"

# ── clock and fixture builders ────────────────────────────────────────────────────────────────
iso()   { date -u -d "$1" '+%Y-%m-%dT%H:%M:%SZ'; }
rowdt() { date -u -d "$1" '+%Y-%m-%d %H:%M:%S'; }
at()    { rowdt "@$(( $1 ))"; }
# The two other dt shapes the warehouse can return (decode_rows normalizes both to the `at` shape).
dtfrac() { date -u -d "@$1" '+%Y-%m-%d %H:%M:%S.123'; }   # fractional-second shape
dtisoz() { date -u -d "@$1" '+%Y-%m-%dT%H:%M:%SZ'; }       # ISO-T/Z shape
dtboth() { date -u -d "@$1" '+%Y-%m-%dT%H:%M:%S.123Z'; }    # BOTH at once: the Z hides the fraction from a `\.[0-9]+$` strip run first

# rowdisk <dt> <boot> — one SOLEUR_ZOT_DISK heartbeat row (real double-encoded JSONEachRow shape).
rowdisk() {
  printf '{"dt":"%s","raw":"{\\"message\\":\\"SOLEUR_ZOT_DISK pcent=8 zot_restarts=0 boot_id=%s htpasswd_pull_matches=true htpasswd_push_matches=true host=%s zot_last_err=level:info %s\\"}"}\n' \
    "$1" "$2" "$HOST" "$CANARY"
}
# rowfree <dt> <boot-or-empty> <head-fields> <tail> — a row whose HEAD the caller controls exactly.
rowfree() {
  local b=""
  [[ -n "$2" ]] && b="boot_id=$2 "
  printf '{"dt":"%s","raw":"{\\"message\\":\\"SOLEUR_ZOT_DISK pcent=8 %s%s host=%s zot_last_err=%s\\"}"}\n' "$1" "$b" "$3" "$HOST" "$4"
}
foreign() { # a Vector-shipped journald row QUOTING the marker
  printf '{"dt":"%s","raw":"{\\"PRIORITY\\":\\"6\\",\\"_HOSTNAME\\":\\"soleur-web-1\\",\\"message\\":\\"[zot] SOLEUR_ZOT_DISK egress FAILED: boot_id=%s host=%s zot_last_err=none %s\\"}"}\n' \
    "$1" "$2" "$HOST" "$CANARY"
}
quoting() { # an envelope whose decoded message quotes the marker at offset > 0
  printf '{"dt":"%s","raw":"{\\"message\\":\\"relayed: SOLEUR_ZOT_DISK boot_id=%s host=%s zot_last_err=none %s\\"}"}\n' \
    "$1" "$2" "$HOST" "$CANARY"
}
rowother() { # another host's heartbeat
  printf '{"dt":"%s","raw":"{\\"message\\":\\"SOLEUR_ZOT_DISK pcent=8 boot_id=%s host=soleur-web-platform zot_last_err=none\\"}"}\n' "$1" "$2"
}

# Time model: the PR merged AGE minutes ago. The old host reported before the merge; the new host's first
# row lands 20 minutes after it and then every 5 minutes up to "now - 5 minutes" (LAST_OFFSET).
AGE=240
set_clock() {
  AGE="$1"
  T_NOW="$(date -u +%s)"
  M_EPOCH=$(( T_NOW - AGE * 60 ))
}
new_boot_rows() { # <first-offset-min> <last-offset-min-from-now> <boot> [dt-shape-fn: at|dtfrac|dtisoz]
  local t=$(( M_EPOCH + $1 * 60 )) stop=$(( T_NOW - $2 * 60 ))
  while (( t <= stop )); do rowdisk "$("${4:-at}" "$t")" "$3"; t=$(( t + 300 )); done
}
add_run() { # <id> <sha> <conclusion> <status> [event]
  jq -n --argjson id "$1" --arg sha "$2" --arg c "$3" --arg st "$4" --arg ev "${5:-push}" \
        --arg cr "$(iso "@$(( M_EPOCH + 60 ))")" \
    '{databaseId:$id, headSha:$sha, conclusion:$c, status:$st, createdAt:$cr, updatedAt:$cr, event:$ev}' >> "$FX/runs.ndjson"
}
set_counts() { # <population> <as_written> <control>
  printf '{"n_population":"%s"}\n' "$1" > "$FX/population.out"
  printf '{"n_as_written":"%s"}\n' "$2" > "$FX/as_written.out"
  printf '{"n_control":"%s"}\n' "$3" > "$FX/control.out"
}
write_table() { # [flip-index] — the engine's answer for the 16 literals, optionally with ONE flag flipped
  local i flag
  : > "$FX/table.out"
  for i in "${!TABLE_LITS[@]}"; do
    flag="${TABLE_FLAGS[$i]}"
    [[ "${1:-}" == "$i" ]] && flag=$(( 1 - flag ))
    jq -nc --arg l "${TABLE_LITS[$i]}" --argjson f "$flag" '{lit:$l, flagged:$f}' >> "$FX/table.out"
  done
}

scenario() {
  rm -rf "$FX"; mkdir -p "$FX"
  : > "$FX/runs.ndjson"
  set_clock "${1:-240}"
  jq -n --arg sha "$SHA_M" --arg at "$(iso "@$M_EPOCH")" '{state:"MERGED", mergeCommit:{oid:$sha}, mergedAt:$at}' > "$FX/pr.json"
  add_run 601 "$SHA_M" success completed
  {
    rowdisk "$(at $(( M_EPOCH - 3600 )))" "$OLDBOOT"
    rowdisk "$(at $(( M_EPOCH - 1800 )))" "$OLDBOOT"
    rowdisk "$(at $(( M_EPOCH - 300 )))" "$OLDBOOT"
    new_boot_rows 20 5 "$NEWBOOT"
  } > "$FX/disk.jsonl"
  write_table
  set_counts 18767 0 18767
}
finalize_fx() { jq -s . "$FX/runs.ndjson" > "$FX/runs.json"; }

# ── the runner ────────────────────────────────────────────────────────────────────────────────
MUTANT_MODE=0
MUT_RED=0
# A mutant that dies with no `registry-clientip[#7530]: verdict=` line (a crash, an unbound variable, rc 1,
# which would REOPEN a closed tracker) is UNRESOLVED, not killed: a crash is not a designed kill.
MUT_CRASH=0
VERDICT_PREFIX='registry-clientip[#7530]: verdict='
# The re-date pointer's anchor. It belongs to the PASS comment ONLY: expect() forbids it on every case whose
# wanted exit is not 0, so a refactor that moves the pointer into say() (every FAIL / CANNOT ESTABLISH
# comment on the public tracker then tells the closer to re-date legal records) turns a case red.
PASS_POINTER_KEY='re-date them per knowledge-base/engineering/operations/runbooks/registry-clientip-rfc1918-7530.md'
# run_probe runs in a command substitution, so it cannot set MUT_CRASH itself: it drops a flag file that
# mutant() reads back. EVERY case that runs the probe in MUTANT_MODE (the expect-based cases and the custom
# query_windows / sql_parity cases alike) therefore classifies a verdict-less output as a crash.
CRASH_FLAG="$WORK/mutant-crash.flag"
#   CASE_NO_GH_TOKEN=1  CASE_NO_BS=1  CASE_TRACE=1  CASE_PATH=<path>  CASE_BQ=<path>  CASE_TF=<path>
run_probe() { # -> echoes the exit code; combined output in $OUT
  finalize_fx
  rm -f "$OUT"
  local -a envv=("PATH=${CASE_PATH:-$BIN:$PATH}" "FX_DIR=$FX" "FAKE_CRED=$FAKE_BS_PW" "REG7530_REPO=$REPO" "REG7530_BQ=${CASE_BQ:-$BIN/bq.sh}" "REG7530_TF=${CASE_TF:-$REAL_TF}")
  [[ "${CASE_NO_GH_TOKEN:-0}" == "1" ]] || envv+=("GH_TOKEN=$FAKE_GH")
  if [[ "${CASE_NO_BS:-0}" != "1" ]]; then
    envv+=("BETTERSTACK_QUERY_HOST=stub.betterstackdata.com" "BETTERSTACK_QUERY_USERNAME=stub-user" "BETTERSTACK_QUERY_PASSWORD=$FAKE_BS_PW")
  fi
  local -a sh=(bash)
  [[ "${CASE_TRACE:-0}" == "1" ]] && sh=(bash -x)
  env -i "${envv[@]}" "${sh[@]}" "$PROBE" >"$OUT" 2>&1
  local prc=$?
  if (( MUTANT_MODE )) && ! /usr/bin/grep -aqF -e "$VERDICT_PREFIX" -e "refusing to trace" "$OUT"; then : > "$CRASH_FLAG"; fi
  echo "$prc"
}

# The output of EVERY run must hold no address. A dotted quad, a `::`, a run of colon-separated hex groups
# (an IPv6 literal) or any of the 16 synthetic literals is a leak into a public comment.
leaks_address() {
  local lit
  if /usr/bin/grep -aqE '[0-9]{1,3}(\.[0-9]{1,3}){3}' "$OUT"; then return 0; fi
  if /usr/bin/grep -aqF '::' "$OUT"; then return 0; fi
  if /usr/bin/grep -aqiE '[0-9a-f]{1,4}(:[0-9a-f]{1,4}){3,}' "$OUT"; then return 0; fi
  for lit in "${TABLE_LITS[@]}"; do
    [[ "$lit" == "default" ]] && continue
    if /usr/bin/grep -aqF -- "$lit" "$OUT"; then return 0; fi
  done
  return 1
}

expect() { # <name> <rc> <marker>
  cases=$((cases + 1))
  local name="$1" want="$2" marker="$3" got ok=1 token leak
  got="$(run_probe)"
  [[ -s "$OUT" ]] || { (( MUTANT_MODE )) && { MUT_CRASH=1; return; }; fail "$name — probe produced NO output; did it run?"; return; }
  [[ "$got" == "$want" ]] || ok=0
  /usr/bin/grep -aqF -- "$marker" "$OUT" || ok=0
  if [[ -n "${CASE_REQUIRE:-}" ]] && ! /usr/bin/grep -aqF -- "$CASE_REQUIRE" "$OUT"; then
    ok=0; (( MUTANT_MODE )) || printf '        | missing required text: %s\n' "$CASE_REQUIRE" >&2
  fi
  if [[ -n "${CASE_FORBID:-}" ]] && /usr/bin/grep -aqF -- "$CASE_FORBID" "$OUT"; then
    ok=0; (( MUTANT_MODE )) || printf '        | output contains forbidden text: %s\n' "$CASE_FORBID" >&2
  fi
  if [[ "$want" != "0" ]] && /usr/bin/grep -aqF -- "$PASS_POINTER_KEY" "$OUT"; then
    ok=0; (( MUTANT_MODE )) || printf '        | a non-PASS verdict carries the PASS-only re-date pointer\n' >&2
  fi
  for leak in "$FAKE_GH" "$FAKE_BS_PW" "$CANARY"; do
    if /usr/bin/grep -aqF -- "$leak" "$OUT"; then
      ok=0; (( MUTANT_MODE )) || printf '        | LEAKED a credential or row text into public output: %s\n' "${leak:0:10}" >&2
    fi
  done
  if leaks_address; then
    ok=0; (( MUTANT_MODE )) || printf '        | the output contains an ADDRESS-shaped string\n' >&2
  fi
  if [[ -f "$FX/writes.log" ]]; then
    ok=0; (( MUTANT_MODE )) || printf '        | the probe made a WRITE call: %s\n' "$(head -1 "$FX/writes.log")" >&2
  fi
  if (( MUTANT_MODE )); then (( ok )) || MUT_RED=1; return; fi
  token="$(printf '%s\n' "$marker" | /usr/bin/grep -aoE 'verdict=[a-z0-9_]+' | head -1 | cut -d= -f2)"
  printf '%s\t%s\n' "$want" "$token" >> "$MARKER_LOG"
  if (( ok )); then
    pass "$name (exit $got, ${marker:0:48})"
  else
    fail "$name — expected exit $want + marker '${marker:0:48}', got exit $got"
    sed 's/^/        | /' "$OUT" >&2
  fi
}

# ══ the cases ═════════════════════════════════════════════════════════════════════════════════
case_trace() { scenario; CASE_TRACE=1 expect "xtrace with a live credential is REFUSED (78), credential not printed" 78 "refusing"; }
case_no_gh_token() { scenario; CASE_NO_GH_TOKEN=1 expect "GH_TOKEN absent -> CANNOT ESTABLISH" 3 "verdict=c_token_unset"; }
case_pr_read_failed() { scenario; : > "$FX/fail-pr"; expect "the PR read fails -> CANNOT ESTABLISH" 3 "verdict=c_pr_read_failed"; }
case_pr_open() {
  scenario; jq -n '{state:"OPEN", mergeCommit:null, mergedAt:null}' > "$FX/pr.json"
  expect "PR not merged -> NOT YET" 2 "verdict=n_pr_unmerged"
}
case_pr_sha_bad() {
  scenario; jq -n --arg at "$(iso "@$M_EPOCH")" '{state:"MERGED", mergeCommit:{oid:"nope"}, mergedAt:$at}' > "$FX/pr.json"
  expect "merged but the merge SHA is unreadable -> CANNOT ESTABLISH" 3 "verdict=c_pr_sha_unreadable"
}
case_merge_absent() {
  scenario; jq -n --arg sha "$SHA_ABSENT" --arg at "$(iso "@$M_EPOCH")" '{state:"MERGED", mergeCommit:{oid:$sha}, mergedAt:$at}' > "$FX/pr.json"
  expect "merge SHA absent from the checkout -> CANNOT ESTABLISH" 3 "verdict=c_history_unreadable which=merge"
}
case_merge_time_bad() {
  scenario; jq -n --arg sha "$SHA_M" '{state:"MERGED", mergeCommit:{oid:$sha}, mergedAt:"garbage"}' > "$FX/pr.json"
  expect "an unreadable merge time -> CANNOT ESTABLISH" 3 "verdict=c_merge_time_unreadable"
}
case_no_apply_runs() { scenario; : > "$FX/runs.ndjson"; expect "no push-apply run yet -> NOT YET" 2 "verdict=n_apply_pending"; }
case_apply_runs_read_failed() { scenario; : > "$FX/fail-runs"; expect "the run listing fails -> CANNOT ESTABLISH" 3 "verdict=c_runs_read_failed"; }
case_apply_in_progress() {
  scenario; : > "$FX/runs.ndjson"; add_run 602 "$SHA_M" "" in_progress
  expect "the push apply is still running -> NOT YET" 2 "verdict=n_apply_pending"
}
case_apply_failed() {
  # The sanctioned dispatch command stays visible but is LABELLED as not counted: this probe lists
  # `--event push` runs only, so a workflow_dispatch run cannot move the verdict.
  scenario; : > "$FX/runs.ndjson"; add_run 603 "$SHA_M" failure completed
  CASE_REQUIRE="Re-fire: gh workflow run apply-web-platform-infra.yml --ref main -f apply_target=manual-rerun  (NOT counted:" \
    expect "the push apply FAILED and nothing else is running -> CANNOT ESTABLISH; the sanctioned dispatch re-fire is printed but labelled NOT counted" 3 "verdict=c_apply_failed"
}
case_apply_failed_clears_by_push() {
  # What ACTUALLY clears c_apply_failed, as the probe's own run model reads it: a push-event apply for the
  # merge commit or a descendant. A transient failure is re-executed in place (same push-event run); a config
  # defect is fixed by a merge whose push apply descends from the merge commit (the descends() rule).
  scenario; : > "$FX/runs.ndjson"; add_run 603 "$SHA_M" failure completed
  CASE_REQUIRE="What clears this verdict: a push-event run of apply-web-platform-infra.yml for the merge commit or a descendant that concludes success" \
    expect "c_apply_failed names the push-event requirement (the only thing that clears it)" 3 "verdict=c_apply_failed"
  scenario; : > "$FX/runs.ndjson"; add_run 603 "$SHA_M" failure completed
  CASE_REQUIRE="Transient failure: gh run rerun <failed push run id> --failed (re-executes the same push-event run, which then counts)" \
    expect "c_apply_failed names the in-place rerun for a transient failure" 3 "verdict=c_apply_failed"
  scenario; : > "$FX/runs.ndjson"; add_run 603 "$SHA_M" failure completed
  CASE_REQUIRE="Config defect: merge a fix that touches apps/web-platform/infra/ to main; its push apply descends from the merge commit and counts once it succeeds" \
    expect "c_apply_failed names the descendant-fix route for a config defect" 3 "verdict=c_apply_failed"
}
case_apply_failed_dispatch_succeeded() {
  # The printed re-fire is a workflow_dispatch run. A failed PUSH run followed by a SUCCEEDED dispatch run at the
  # same SHA must leave the verdict at c_apply_failed (exit 3), and the prose must say why (push-event only).
  scenario; : > "$FX/runs.ndjson"
  add_run 603 "$SHA_M" failure completed
  add_run 609 "$SHA_M" success completed workflow_dispatch
  CASE_REQUIRE="(NOT counted: a workflow_dispatch run applies the current main but is not a push-event run, so this verdict stays c_apply_failed until a push-event apply succeeds)" \
    expect "a failed push run plus a SUCCEEDED dispatch run stays c_apply_failed (the dispatch is not counted) and the prose says push-event" 3 "verdict=c_apply_failed"
}
case_refire_parity() {
  # The re-fire the probe prints is the one the workflow documents (Bootstrap-cycle guard, #4195): same file
  # name, same ref, same input. A reword of that comment in the workflow fails here instead of drifting. The
  # third check reads the probe under test ($PROBE, the mutated copy in mutant mode), so a mutant bound to this
  # row alone can die here.
  local wf="$REPO_ROOT/.github/workflows/apply-web-platform-infra.yml" ok=1
  cases=$((cases + 1))
  /usr/bin/grep -aqF 'Bootstrap-cycle guard (#4195)' "$wf" || ok=0
  /usr/bin/grep -aqF -- 'apply-web-platform-infra.yml --ref main -f apply_target=manual-rerun' "$wf" || ok=0
  /usr/bin/grep -aqF -- 'Re-fire: gh workflow run apply-web-platform-infra.yml --ref main -f apply_target=manual-rerun' "$PROBE" || ok=0
  if (( MUTANT_MODE )); then (( ok )) || MUT_RED=1; return; fi
  printf '0\trefire_parity\n' >> "$MARKER_LOG"
  if (( ok )); then pass "the re-fire command in c_apply_failed matches the workflow's documented Bootstrap-cycle guard re-fire"
  else fail "the c_apply_failed re-fire and the workflow's documented re-fire differ"; fi
}
case_apply_displaced_descendant_ok() {
  # The merge SHA's apply was displaced (cancelled) by the single pending slot; a DESCENDANT's apply succeeded.
  scenario; : > "$FX/runs.ndjson"; add_run 604 "$SHA_M" cancelled completed; add_run 605 "$SHA_D1" success completed
  expect "a displaced apply followed by a successful descendant apply counts (PASS)" 0 "verdict=p_pass"
}
case_apply_not_descendant() {
  scenario; : > "$FX/runs.ndjson"; add_run 606 "$SHA_U" success completed
  expect "a successful apply for a SHA that does not descend from the merge does not count -> NOT YET" 2 "verdict=n_apply_pending"
}
case_apply_dispatch_event() {
  scenario; : > "$FX/runs.ndjson"; add_run 607 "$SHA_M" success completed workflow_dispatch
  expect "a workflow_dispatch apply is not the push apply -> NOT YET" 2 "verdict=n_apply_pending"
}
case_apply_unknown_sha() {
  scenario; : > "$FX/runs.ndjson"; add_run 608 "$SHA_ABSENT" success completed
  expect "an apply run whose SHA cannot be ordered -> CANNOT ESTABLISH" 3 "verdict=c_history_unreadable which=runs"
}
case_no_bs_creds() { scenario; CASE_NO_BS=1 expect "Better Stack credentials absent -> CANNOT ESTABLISH" 3 "verdict=c_bs_creds_unset"; }
case_query_missing() { scenario; CASE_BQ="$WORK/does-not-exist" expect "betterstack-query.sh missing -> CANNOT ESTABLISH" 3 "verdict=c_query_missing"; }
case_deps_missing() {
  scenario
  local nogit="$WORK/nogit" t
  assert_fixture_dir "$nogit"
  mkdir -p "$nogit"
  for t in bash env date jq awk sed sort tr head tail cut grep wc cat python3; do
    ln -sf "$(command -v "$t")" "$nogit/$t" 2>/dev/null
  done
  CASE_PATH="$BIN:$nogit" expect "git missing on the runner -> CANNOT ESTABLISH" 3 "verdict=c_deps_missing tool=git"
}
case_boot_read_failed() { scenario; echo 7 > "$FX/disk.rc"; expect "the SOLEUR_ZOT_DISK read fails -> CANNOT ESTABLISH" 3 "verdict=c_boot_read_failed"; }
case_channel_dark() { scenario; : > "$FX/disk.jsonl"; expect "no producer rows at all -> CANNOT ESTABLISH (channel dark)" 3 "verdict=c_channel_dark"; }
case_old_boot_only() {
  # The replace has not landed: every row belongs to the pre-merge boot.
  scenario; {
    rowdisk "$(at $(( M_EPOCH - 600 )))" "$OLDBOOT"
    new_boot_rows 10 5 "$OLDBOOT"
  } > "$FX/disk.jsonl"
  expect "the newest boot began before the merge -> NOT YET" 2 "verdict=n_no_post_merge_boot"
}
case_boot_too_young() {
  scenario 40; { rowdisk "$(at $(( M_EPOCH - 300 )))" "$OLDBOOT"; new_boot_rows 20 5 "$NEWBOOT"; } > "$FX/disk.jsonl"
  expect "the post-merge boot has under 30 minutes of rows -> NOT YET" 2 "verdict=n_boot_too_young"
}
case_producer_silent() {
  scenario; { rowdisk "$(at $(( M_EPOCH - 300 )))" "$OLDBOOT"; new_boot_rows 20 200 "$NEWBOOT"; } > "$FX/disk.jsonl"
  expect "the newest row is over 30 minutes old -> CANNOT ESTABLISH (producer silent)" 3 "verdict=c_producer_silent"
}
case_foreign_new_boot() {
  scenario; {
    rowdisk "$(at $(( M_EPOCH - 300 )))" "$OLDBOOT"
    foreign "$(at $(( T_NOW - 600 )))" "$THIRDBOOT"
  } > "$FX/disk.jsonl"
  expect "a quoting journald row cannot supply the post-merge boot -> NOT YET" 2 "verdict=n_no_post_merge_boot"
}
case_quoting_offset() {
  scenario; {
    rowdisk "$(at $(( M_EPOCH - 300 )))" "$OLDBOOT"
    quoting "$(at $(( T_NOW - 600 )))" "$THIRDBOOT"
  } > "$FX/disk.jsonl"
  expect "a marker quoted at offset > 0 cannot supply the post-merge boot -> NOT YET" 2 "verdict=n_no_post_merge_boot"
}
case_other_host() {
  scenario; {
    rowdisk "$(at $(( M_EPOCH - 300 )))" "$OLDBOOT"
    rowother "$(at $(( T_NOW - 600 )))" "$THIRDBOOT"
  } > "$FX/disk.jsonl"
  expect "another host's heartbeat cannot supply the post-merge boot -> NOT YET" 2 "verdict=n_no_post_merge_boot"
}
case_tail_forge_boot() {
  # A row whose HEAD has no boot_id and whose free-text tail forges one: the tail is untrusted.
  scenario; {
    rowdisk "$(at $(( M_EPOCH - 300 )))" "$OLDBOOT"
    rowfree "$(at $(( T_NOW - 600 )))" "" "pcent=8" "level:info boot_id=$THIRDBOOT $CANARY"
  } > "$FX/disk.jsonl"
  expect "a boot_id forged in the zot_last_err tail cannot supply the post-merge boot -> NOT YET" 2 "verdict=n_no_post_merge_boot"
}
case_tf_absent_main() {
  echo 'locals { unrelated = "x" }' > "$WORK/absent.tf"
  scenario; CASE_TF="$WORK/absent.tf" expect "the alert local is absent after the merge reached the checkout -> CANNOT ESTABLISH" 3 "verdict=c_sql_local_absent"
}
case_tf_absent_premerge() {
  # The checkout's HEAD does not contain the merge commit (the sweeper checked out before it landed).
  echo 'locals { unrelated = "x" }' > "$WORK/absent.tf"
  scenario; git -C "$REPO" switch -q side
  CASE_TF="$WORK/absent.tf" expect "the alert local is absent and the merge is not in the checkout -> NOT YET" 2 "verdict=n_sql_not_on_main"
  git -C "$REPO" switch -q "$MAIN_BRANCH"
}
case_tf_unreadable() {
  scenario; CASE_TF="$WORK/does-not-exist.tf" expect "the alert file is unreadable -> CANNOT ESTABLISH" 3 "verdict=c_sql_local_absent"
}
case_tf_shape() {
  sed 's/GROUP BY time/GROUP BY dt/' "$REAL_TF" > "$WORK/shape.tf"
  scenario; CASE_TF="$WORK/shape.tf" expect "a predicate that lost its GROUP BY time frame -> CANNOT ESTABLISH" 3 "verdict=c_sql_shape"
}
case_tf_no_private_clause() {
  sed "s/AND NOT match(n, '^(10\[.\]|/AND match(n, '^(10[.]|/" "$REAL_TF" > "$WORK/nonot.tf"
  scenario; CASE_TF="$WORK/nonot.tf" expect "a predicate without the private-exclusion clause cannot be turned into its control -> CANNOT ESTABLISH" 3 "verdict=c_sql_shape"
}
case_table_failed() { scenario; echo 7 > "$FX/table.rc"; expect "the classification query fails -> CANNOT ESTABLISH" 3 "verdict=c_query_failed which=table"; }
case_population_failed() { scenario; echo 7 > "$FX/population.rc"; expect "the population query fails -> CANNOT ESTABLISH" 3 "verdict=c_query_failed which=population"; }
case_as_written_failed() { scenario; echo 7 > "$FX/as_written.rc"; expect "the as-written query fails -> CANNOT ESTABLISH, never a clean 0" 3 "verdict=c_query_failed which=as_written"; }
case_control_failed() { scenario; echo 7 > "$FX/control.rc"; expect "the control query fails -> CANNOT ESTABLISH" 3 "verdict=c_query_failed which=control"; }
case_count_garbage() {
  scenario; printf '{"n_as_written":"lots"}\n' > "$FX/as_written.out"
  expect "a non-numeric count -> CANNOT ESTABLISH, never read as zero" 3 "verdict=c_query_failed which=as_written"
}
case_count_junk() {
  # Text that STARTS like a number: an end-unanchored INT_RE reads it as a count, the arithmetic then
  # errors out silently and the as-written zero is lost (a false PASS). Each must be CANNOT ESTABLISH.
  # Also all-digit values bash arithmetic misreads: a leading zero followed by 8 or 9 is an octal ERROR (read as
  # zero -> a false PASS), 007 is octal 7 (a different number than the engine said), and a 20-digit value
  # overflows 64-bit arithmetic and wraps.
  local junk
  for junk in 0abc 1e3 0x1 08 09 007 99999999999999999999; do
    scenario; printf '{"n_as_written":"%s"}\n' "$junk" > "$FX/as_written.out"
    expect "a count that only starts like an integer ($junk) -> CANNOT ESTABLISH, never read as a number" 3 "verdict=c_query_failed which=as_written"
  done
}
case_count_missing() {
  scenario; : > "$FX/as_written.out"
  expect "an EMPTY answer is not a zero -> CANNOT ESTABLISH" 3 "verdict=c_query_failed which=as_written"
}
case_table_short() {
  scenario; sed -i '$d' "$FX/table.out"
  expect "15 of 16 classification rows -> CANNOT ESTABLISH" 3 "verdict=c_table_unreadable"
}
case_table_unknown_lit() {
  scenario; sed -i '$d' "$FX/table.out"; printf '{"lit":"zzz-unknown","flagged":0}\n' >> "$FX/table.out"
  expect "an unknown literal in the classification answer -> CANNOT ESTABLISH" 3 "verdict=c_table_unreadable"
}
case_table_dup() {
  scenario; sed -i '$d' "$FX/table.out"
  local first; first="$(sed -n '1p' "$FX/table.out")"; printf '%s\n' "$first" >> "$FX/table.out"
  expect "a duplicated literal in the classification answer -> CANNOT ESTABLISH" 3 "verdict=c_table_unreadable"
}
case_table_mismatch() {
  scenario; write_table 8   # 172.15.x flipped to "not flagged": the predicate would miss a public address
  CASE_REQUIRE="table_mismatches=1" expect "the extracted predicate classifies one literal wrongly -> FAIL (measured, counts only)" 1 "verdict=f_table_mismatch"
}
case_table_mismatch_private() {
  scenario; write_table 0
  CASE_REQUIRE="table_mismatches=1" expect "a private literal flagged by the predicate -> FAIL" 1 "verdict=f_table_mismatch"
}
case_as_written_positive() {
  scenario; set_counts 18767 3 18767
  CASE_REQUIRE="as_written=3" expect "the predicate as written counts rows over the post-boot window -> FAIL (counts only, no address)" 1 "verdict=f_non_rfc1918"
}
case_population_empty() {
  scenario; set_counts 0 0 0
  expect "an empty population cannot vouch for a zero -> CANNOT ESTABLISH" 3 "verdict=c_population_empty"
}
case_control_dead() {
  scenario; set_counts 18767 0 0
  expect "the private-flagged control reads zero over a positive population -> CANNOT ESTABLISH" 3 "verdict=c_control_dead"
}
case_pass() {
  scenario; CASE_REQUIRE="population=18767 as_written=0 control=18767" expect "table correct, as-written 0 over a positive population, control above 0 -> PASS" 0 "verdict=p_pass"
}
# The re-dating pointer the closer must see: the sweeper closes #7530 on exit 0, and nothing else tells
# whoever reads the closing comment that the legal records still say NOT in force.
PASS_POINTER="register PA-8 (c)/(g) brackets, counsel-review-7440 addendum + frontmatter clientip_monitoring_pointer, ADR-211 and ADR-218 delivery-state lines say NOT in force / not treated as an enforced invariant until this PASS: re-date them per knowledge-base/engineering/operations/runbooks/registry-clientip-rfc1918-7530.md section 'After the first graded PASS'"
case_pass_redate_pointer() {
  scenario; CASE_REQUIRE="$PASS_POINTER" expect "the PASS comment tells the closer to re-date the legal records (runbook pointer, no row text)" 0 "verdict=p_pass"
}
# The pointer names a runbook section. This row is a REAL read of that file: the heading the PASS comment tells
# the closer to open must still exist, else the pointer is dead and nothing else notices.
runbook_has_heading() { # <file> -> 0 when the file holds the heading line the PASS pointer names
  /usr/bin/grep -aqxF '## After the first graded PASS' "$1" 2>/dev/null
}
case_runbook_heading() {
  local rb="$REPO_ROOT/knowledge-base/engineering/operations/runbooks/registry-clientip-rfc1918-7530.md" ok=1 scratch="$WORK/runbook-noheading.md"
  cases=$((cases + 1))
  runbook_has_heading "$rb" || ok=0
  # Negative control on a scratch copy WITHOUT the heading: the check must go red, or the row proves nothing.
  sed '/^## After the first graded PASS$/d' "$rb" > "$scratch" 2>/dev/null
  if runbook_has_heading "$scratch"; then ok=0; fi
  if (( MUTANT_MODE )); then (( ok )) || MUT_RED=1; return; fi
  printf '0\trunbook_heading\n' >> "$MARKER_LOG"
  if (( ok )); then pass "the runbook file (read: registry-clientip-rfc1918-7530.md) still has the heading '## After the first graded PASS' the PASS pointer names, and the check goes red on a copy without it"
  elif [[ ! -r "$rb" ]]; then fail "the runbook registry-clientip-rfc1918-7530.md is unreadable at $rb (a sandbox without knowledge-base/ cannot run this row)"
  else fail "the runbook registry-clientip-rfc1918-7530.md lost its '## After the first graded PASS' heading (or the check is vacuous): the PASS pointer is dead"; fi
}
case_pass_unquoted_counts() {
  scenario; printf '{"n_population":18767}\n' > "$FX/population.out"; printf '{"n_as_written":0}\n' > "$FX/as_written.out"; printf '{"n_control":18767}\n' > "$FX/control.out"
  expect "unquoted integer counts parse (JSONEachRow quoting does not matter)" 0 "verdict=p_pass"
}
case_table_flags_as_strings() {
  scenario; : > "$FX/table.out"
  local i
  for i in "${!TABLE_LITS[@]}"; do jq -nc --arg l "${TABLE_LITS[$i]}" --arg f "${TABLE_FLAGS[$i]}" '{lit:$l, flagged:$f}' >> "$FX/table.out"; done
  expect "flags quoted as strings (UInt64-style) parse" 0 "verdict=p_pass"
}

# SQL parity: the SQL the probe SENDS equals the committed .tf's predicate, mechanically transformed.
slurp_sql() { # <file> -> its content on one line; empty (and silent) when the probe never wrote it
  [[ -r "$1" ]] || return 0
  tr '\n' ' ' < "$1" | tr -s ' '
}
case_sql_parity() {
  scenario
  local rc norm tail ctl anchors cnt ok=1 why=""
  rc="$(run_probe)"
  cases=$((cases + 1))
  # The alert local, whitespace-collapsed exactly as the resource site collapses it.
  norm="$(sed -n '/^  registry_clientip_not_rfc1918_sql = <<-SQL$/,/^  SQL$/p' "$REAL_TF" | sed '1d;$d' | tr '\n' ' ' | tr -s ' ' | sed 's/^ //; s/ $//')"
  tail="${norm#*'{{end_time}} '}"; tail="${tail% GROUP BY time}"
  local q="'" npat nrep
  npat="AND NOT match(n, ${q}^(10[.]"; nrep="AND match(n, ${q}^(10[.]"
  ctl="${tail/"$npat"/"$nrep"}"
  anchors="${tail#AND }"; anchors="${anchors%% AND arrayExists(*}"
  local sql_aw sql_ctl sql_pop sql_tab
  # A probe that died before sending its queries wrote none of these files (the expected crash signature of the
  # crash self-check mutants): read them only when present, so a green run keeps an EMPTY stderr.
  sql_aw="$(slurp_sql "$FX/sql.as_written")"
  sql_ctl="$(slurp_sql "$FX/sql.control")"
  sql_pop="$(slurp_sql "$FX/sql.population")"
  sql_tab="$(slurp_sql "$FX/sql.table")"
  [[ -n "$tail" && "$tail" == "AND (startsWith("* ]] || { ok=0; why+=" tail-not-extracted"; }
  [[ "$sql_aw" == *"$tail"* ]] || { ok=0; why+=" as-written-not-verbatim"; }
  [[ "$sql_ctl" == *"$ctl"* && "$ctl" != "$tail" ]] || { ok=0; why+=" control-not-the-flipped-predicate"; }
  [[ "$sql_ctl" != *"AND NOT match(n, '^(10[.]"* ]] || { ok=0; why+=" control-kept-the-private-exclusion"; }
  [[ "$sql_pop" == *"AND $anchors"* ]] || { ok=0; why+=" population-lost-the-anchors"; }
  [[ "$sql_aw" == *"startsWith(raw, '{\"message\":\"SOLEUR_ZOT_LOG shipper=zot-log-shipper host=soleur-registry ')"* ]] || { ok=0; why+=" as-written-lost-the-envelope-anchor"; }
  [[ "$sql_aw" == *"remote(\$BS_TABLE)"* && "$sql_aw" == *"s3Cluster(primary, \$BS_TABLE_S3)"* && "$sql_aw" == *"_row_type = 1"* ]] || { ok=0; why+=" as-written-lost-the-archive-arm"; }
  [[ "$sql_aw" == *"parseDateTime64BestEffort('"* ]] || { ok=0; why+=" as-written-has-no-window-start"; }
  [[ "$sql_tab" == *"arrayExists(n -> "* && "$sql_tab" == *"concat('clientIP:', lit)"* && "$sql_tab" != *"JSONExtractString(raw, 'message')"* ]] || { ok=0; why+=" table-not-the-extracted-lambda"; }
  cnt="$(printf '%s\n' "${TABLE_LITS[@]}" | while IFS= read -r l; do [[ "$sql_tab" == *"'$l'"* ]] && echo x; done | wc -l)"
  [[ "$cnt" -eq 16 ]] || { ok=0; why+=" table-literals-$cnt-of-16"; }
  if (( MUTANT_MODE )); then (( ok )) || MUT_RED=1; return; fi
  printf '0\tsql_parity\n' >> "$MARKER_LOG"
  if (( ok )) && [[ "$rc" == "0" ]]; then pass "the SQL sent equals the committed predicate: verbatim as-written, flipped control, anchored population, extracted lambda over all 16 literals"
  else fail "SQL parity broken (rc=$rc):$why"; fi
}

case_old_host_premerge_only() {
  # Only the old host's pre-merge rows exist (the replace has not landed). The boot read must reach back
  # before the merge to SEE them: without the lookback they are invisible and the channel reads dark (3)
  # instead of "not yet" (2).
  scenario; {
    rowdisk "$(at $(( M_EPOCH - 3600 )))" "$OLDBOOT"
    rowdisk "$(at $(( M_EPOCH - 1800 )))" "$OLDBOOT"
    rowdisk "$(at $(( M_EPOCH - 300 )))" "$OLDBOOT"
  } > "$FX/disk.jsonl"
  expect "only pre-merge rows from the old boot -> NOT YET (the lookback makes them visible), never a dark channel" 2 "verdict=n_no_post_merge_boot"
}
case_boot_time_unparsable() {
  # The post-merge boot's first row sorts after the merge but its time does not parse: its own verdict
  # token, not the read-failure token.
  scenario; {
    rowdisk "$(at $(( M_EPOCH - 300 )))" "$OLDBOOT"
    rowdisk "9999-zz" "$THIRDBOOT"
  } > "$FX/disk.jsonl"
  expect "a post-merge boot whose row times do not parse -> CANNOT ESTABLISH with its own verdict token" 3 "verdict=c_boot_time_unparsable"
  # A VALID first row and an unparsable LAST row (the bad time sorts last), and the mirror: the check covers
  # BOTH ends of the boot's span, so dropping either half leaves a skewed span and a wrong verdict.
  scenario; {
    rowdisk "$(at $(( M_EPOCH - 300 )))" "$OLDBOOT"
    rowdisk "$(at $(( M_EPOCH + 1200 )))" "$THIRDBOOT"
    rowdisk "9999-zz" "$THIRDBOOT"
  } > "$FX/disk.jsonl"
  expect "a valid first row and an unparsable LAST row -> CANNOT ESTABLISH (c_boot_time_unparsable)" 3 "verdict=c_boot_time_unparsable"
  # The bad FIRST time must still sort after the merge second and before the valid last row: it shares the
  # merge-plus-20-minutes second and appends a character `date` rejects.
  scenario; {
    rowdisk "$(at $(( M_EPOCH - 300 )))" "$OLDBOOT"
    rowdisk "$(at $(( M_EPOCH + 1200 )))#" "$THIRDBOOT"
    new_boot_rows 25 5 "$THIRDBOOT"
  } > "$FX/disk.jsonl"
  expect "an unparsable FIRST row and a valid last row -> CANNOT ESTABLISH (c_boot_time_unparsable)" 3 "verdict=c_boot_time_unparsable"
}
case_dt_iso_pass() {
  # The whole post-merge boot reported in the ISO-T/Z dt shape: it grades like the plain shape.
  scenario; {
    rowdisk "$(at $(( M_EPOCH - 300 )))" "$OLDBOOT"
    new_boot_rows 20 5 "$NEWBOOT" dtisoz
  } > "$FX/disk.jsonl"
  expect "a post-merge boot in the ISO-T/Z dt shape grades like the plain shape (PASS)" 0 "verdict=p_pass"
}
case_dt_frac_pass() {
  scenario; {
    rowdisk "$(at $(( M_EPOCH - 300 )))" "$OLDBOOT"
    new_boot_rows 20 5 "$NEWBOOT" dtfrac
  } > "$FX/disk.jsonl"
  expect "a post-merge boot in the fractional-second dt shape grades like the plain shape (PASS)" 0 "verdict=p_pass"
}
case_dt_frac_boundary() {
  # A new boot whose FIRST row is in the merge's own second (fractional shape) did not begin AFTER the
  # merge. Unnormalized, `12:00:00.123` sorts after `12:00:00` and would count.
  scenario; {
    rowdisk "$(at $(( M_EPOCH - 300 )))" "$OLDBOOT"
    rowdisk "$(dtfrac "$M_EPOCH")" "$NEWBOOT"
    new_boot_rows 20 5 "$NEWBOOT"
  } > "$FX/disk.jsonl"
  expect "a boot whose first row is in the merge second (fractional shape) is not post-merge -> NOT YET" 2 "verdict=n_no_post_merge_boot"
}
case_dt_isoz_boundary() {
  scenario; {
    rowdisk "$(at $(( M_EPOCH - 300 )))" "$OLDBOOT"
    rowdisk "$(dtisoz "$M_EPOCH")" "$NEWBOOT"
    new_boot_rows 20 5 "$NEWBOOT"
  } > "$FX/disk.jsonl"
  expect "a boot whose first row is in the merge second (ISO-T/Z shape) is not post-merge -> NOT YET" 2 "verdict=n_no_post_merge_boot"
}
case_dt_both_pass() {
  scenario; {
    rowdisk "$(at $(( M_EPOCH - 300 )))" "$OLDBOOT"
    new_boot_rows 20 5 "$NEWBOOT" dtboth
  } > "$FX/disk.jsonl"
  expect "a post-merge boot in the combined fractional-second + ISO-T/Z dt shape grades like the plain shape (PASS)" 0 "verdict=p_pass"
}
case_dt_both_boundary() {
  # The combined shape in the merge's own second. The fraction is only strippable AFTER the trailing Z is gone,
  # so normalizing in the wrong order leaves `.123` behind, which sorts after the merge second.
  scenario; {
    rowdisk "$(at $(( M_EPOCH - 300 )))" "$OLDBOOT"
    rowdisk "$(dtboth "$M_EPOCH")" "$NEWBOOT"
    new_boot_rows 20 5 "$NEWBOOT"
  } > "$FX/disk.jsonl"
  expect "a boot whose first row is in the merge second (combined shape) is not post-merge -> NOT YET" 2 "verdict=n_no_post_merge_boot"
}
case_rows_descending() {
  # The real query tool returns dt ASC, but decode_rows must not DEPEND on it (its `| sort` is the guard): the
  # whole disk read arrives newest-first here. Unsorted, the newest boot and its first row are read off the
  # wrong end (the old boot's newest row), so the verdict would drift to NOT YET.
  scenario; tac "$FX/disk.jsonl" > "$FX/disk.desc" && mv -- "$FX/disk.desc" "$FX/disk.jsonl"
  expect "rows arriving in DESCENDING dt order grade like ascending ones (PASS): decode_rows sorts, it does not trust the tool's order" 0 "verdict=p_pass"
}
case_count_negative() {
  scenario; printf '{"n_as_written":"-1"}\n' > "$FX/as_written.out"
  expect "a negative count is not a count -> CANNOT ESTABLISH, never read as zero" 3 "verdict=c_query_failed which=as_written"
}
case_query_windows() {
  # What the probe asked for, by value. (1) The boot read starts PRE_MERGE_LOOKBACK before the merge.
  # (2) Every stream-reading engine query (population, as written, control) is windowed from the
  # post-merge boot's FIRST row, never from the pre-merge lookback start. (3) The classification query
  # reads no stream at all.
  # (4) The window is a LOWER bound everywhere: `dt >= <start>` appears exactly three times per stream query
  # (the outer filter, the hot-table arm and the archive arm), so a flipped comparison cannot hide behind a
  # correct literal. (5) The boot read's argv is asserted as a whole line, so an extra flag or a different
  # --limit is a failure, not a pass.
  scenario
  local rc ok=1 exp_boot exp_start k lits n_ge
  rc="$(run_probe)"
  cases=$((cases + 1))
  exp_boot="$(iso "@$(( M_EPOCH - 7200 ))")"
  exp_start="$(iso "@$(( M_EPOCH + 1200 ))")"
  [[ "$rc" == "0" ]] || ok=0
  # Files the probe never wrote (it died first) read as "not ok" without a stderr line.
  [[ -r "$FX/bq.calls" ]] || ok=0
  [[ -r "$FX/bq.calls" ]] && { /usr/bin/grep -aqxF -- "--since $exp_boot --grep SOLEUR_ZOT_DISK --limit 5000" "$FX/bq.calls" || ok=0; }
  for k in population as_written control; do
    if [[ ! -r "$FX/sql.$k" ]]; then ok=0; continue; fi
    lits="$(/usr/bin/grep -aoE "parseDateTime64BestEffort\('[^']*'" "$FX/sql.$k" | sort -u)"
    [[ "$lits" == "parseDateTime64BestEffort('$exp_start'" ]] || ok=0
    n_ge="$(/usr/bin/grep -aoF -- "dt >= parseDateTime64BestEffort('$exp_start', 3, 'UTC')" "$FX/sql.$k" | wc -l)"
    [[ "$n_ge" -eq 3 ]] || ok=0
  done
  if [[ ! -r "$FX/sql.table" ]]; then ok=0
  elif /usr/bin/grep -aqF 'parseDateTime64BestEffort' "$FX/sql.table"; then ok=0; fi
  if (( MUTANT_MODE )); then (( ok )) || MUT_RED=1; return; fi
  if (( ok )); then
    pass "boot read is exactly --since <merge-2h> --grep --limit 5000; the three stream queries are lower-bounded (>=, three times each) at the post-merge boot's first row; the table query reads no stream"
  else
    fail "query windows wrong (rc=$rc): $(tr '\n' '|' < "$FX/bq.calls" 2>/dev/null | cut -c1-300)"
  fi
}
case_local_parity() {
  # The probe extracts the committed SQL by a HARD-CODED local name. It must be the local the exploration's
  # sql_query actually references, else a rename in the .tf silently turns the probe into c_sql_local_absent.
  local probe_local tf_local ok=1
  cases=$((cases + 1))
  probe_local="$(sed -n 's/^LOCAL = "\([a-z0-9_]*\)"$/\1/p' "$PROBE" | head -n 1)"
  tf_local="$(sed -n '/^resource "logtail_exploration" "registry_clientip_not_rfc1918" {$/,/^}$/p' "$REAL_TF" \
    | sed -n 's/^ *sql_query *= *replace(trimspace(local\.\([a-z0-9_]*\)).*$/\1/p' | head -n 1)"
  [[ -n "$probe_local" && -n "$tf_local" && "$probe_local" == "$tf_local" ]] || ok=0
  /usr/bin/grep -aqE "^  ${tf_local} = <<-SQL\$" "$REAL_TF" || ok=0
  if (( MUTANT_MODE )); then (( ok )) || MUT_RED=1; return; fi
  printf '0\tlocal_parity\n' >> "$MARKER_LOG"
  if (( ok )); then pass "the probe's hard-coded LOCAL equals the local the exploration's sql_query references, and that local is defined"
  else fail "LOCAL parity broken: probe='$probe_local' tf='$tf_local'"; fi
}

echo "=== registry-clientip-alert-7530 probe cases ==="
for c in trace no_gh_token pr_read_failed pr_open pr_sha_bad merge_absent merge_time_bad no_apply_runs apply_runs_read_failed \
         apply_in_progress apply_failed apply_failed_clears_by_push apply_failed_dispatch_succeeded refire_parity apply_displaced_descendant_ok apply_not_descendant apply_dispatch_event apply_unknown_sha \
         no_bs_creds query_missing deps_missing boot_read_failed channel_dark old_boot_only boot_too_young producer_silent \
         foreign_new_boot quoting_offset other_host tail_forge_boot tf_absent_main tf_absent_premerge tf_unreadable tf_shape \
         tf_no_private_clause table_failed population_failed as_written_failed control_failed count_garbage count_junk count_missing \
         table_short table_unknown_lit table_dup table_mismatch table_mismatch_private as_written_positive population_empty \
         control_dead pass pass_redate_pointer runbook_heading pass_unquoted_counts table_flags_as_strings sql_parity \
         old_host_premerge_only boot_time_unparsable dt_iso_pass dt_frac_pass dt_frac_boundary dt_isoz_boundary count_negative dt_both_pass dt_both_boundary rows_descending query_windows local_parity; do
  "case_$c"
done

# ── what the probe asked gh and the query tool for ───────────────────────────────────────────
scenario
rc="$(run_probe)"
cases=$((cases + 1))
if [[ "$rc" == "0" ]] && /usr/bin/grep -aqE '^pr view 10320 .*--json [a-zA-Z,]*state' "$FX/gh.calls" \
   && /usr/bin/grep -aqF -- "--workflow apply-web-platform-infra.yml" "$FX/gh.calls" \
   && /usr/bin/grep -aqF -- "--event push" "$FX/gh.calls"; then
  pass "gh was asked for PR 10320 and the apply workflow's PUSH runs"
else
  fail "gh calls wrong (rc=$rc): $(tr '\n' '|' < "$FX/gh.calls")"
fi
cases=$((cases + 1))
if ! /usr/bin/grep -aqE '^(issue|api|pr (close|comment|edit|merge)|workflow|run (rerun|cancel|view))' "$FX/gh.calls" && [[ ! -f "$FX/writes.log" ]]; then
  pass "the probe made no write call (no issue close, no comment, no dispatch, no rerun)"
else
  fail "a write-shaped or unexpected gh call was recorded: $(tr '\n' '|' < "$FX/gh.calls")"
fi
cases=$((cases + 1))
n_engine="$(/usr/bin/grep -ac '^SELECT' "$FX/bq.calls")"
n_disk="$(/usr/bin/grep -ac -- '--grep SOLEUR_ZOT_DISK' "$FX/bq.calls")"
if [[ "$n_engine" -eq 4 && "$n_disk" -eq 1 ]]; then
  pass "exactly one boot read and four engine queries (table, population, as written, control)"
else
  fail "unexpected query set: engine=$n_engine disk=$n_disk"
fi

# ── static properties of the shipped probe ───────────────────────────────────────────────────
HDR="$(sed -n '1,/^set -uo pipefail/p' "$SUT")"
cases=$((cases + 1))
if [[ "$HDR" == *"RETIREMENT:"* && "$HDR" == *"EXIT CONTRACT"* && "$HDR" == *"CREDENTIAL POSTURE"* ]]; then
  pass "header states the credential posture, the exit contract and a RETIREMENT line"
else
  fail "header lacks RETIREMENT: / EXIT CONTRACT / CREDENTIAL POSTURE"
fi
cases=$((cases + 1))
# The RETIREMENT list is a claim about where this probe is registered: each named registration must exist, and
# the BASELINE_DECLARED_PROBES sentence must say what is TRUE: the constant counts declaring PLANS, so deleting
# a probe leaves it alone (the earlier "lower it by one" clause would have turned G1 red).
if [[ "$HDR" == *"suite-shard-legs.tsv"* && "$HDR" == *"suite-durations.tsv"* && "$HDR" == *"WHAT A PASS DOES AND DOES NOT PROVE"* && "$HDR" == *"COUPLING"* ]] \
   && [[ "$HDR" == *"BASELINE_DECLARED_PROBES in plugins/soleur/test/preflight-discoverability-test.test.ts is UNCHANGED by this retirement."* ]] \
   && [[ "$HDR" == *"names this probe keeps its declaration, so the constant falls only if that plan file is deleted or its declaration removed."* ]] \
   && [[ "$HDR" != *"lower BASELINE_DECLARED_PROBES"* ]] \
   && [[ "$HDR" == *"apps/web-platform/test/infra/registry-clientip-not-rfc1918-alert.test.sh"* && "$HDR" == *"reconcile the two rename guards"* ]] \
   && [[ -f "$REPO_ROOT/apps/web-platform/test/infra/registry-clientip-not-rfc1918-alert.test.sh" ]] \
   && /usr/bin/grep -aqF 'scripts/followthroughs/registry-clientip-alert-7530' "$REPO_ROOT/scripts/suite-shard-legs.tsv" \
   && /usr/bin/grep -aqF 'scripts/followthroughs/registry-clientip-alert-7530' "$REPO_ROOT/scripts/suite-durations.tsv" \
   && /usr/bin/grep -aqF 'fix-registry-phase2-batch-htpasswd-stdin-clientip-alert-plan.md' "$REPO_ROOT/plugins/soleur/test/preflight-discoverability-test.test.ts"; then
  pass "header lists every registration to unwind (both TSV rows, the cross-referenced alert-suite rename guard) and states that BASELINE_DECLARED_PROBES is UNCHANGED (plan-counted); each exists"
else
  fail "header RETIREMENT/limits lists are incomplete, state the false 'lower BASELINE_DECLARED_PROBES' clause, or a named registration is missing"
fi
cases=$((cases + 1))
# The documented limits that bound what a PASS means: the shipper-only population, the hard-coded PR number,
# the pre-merge lookback and the unchecked workflow name.
if [[ "$HDR" == *"The measured population is the SHIPPER arm only"* && "$HDR" == *"control: 0 SOLEUR_ZOT_DISK rows with a clientIP at the time of writing"* \
   && "$HDR" == *"PR_NUMBER=10320 is hard-coded"* && "$HDR" == *"exit 2 (n_pr_unmerged) forever"* \
   && "$HDR" == *"PRE_MERGE_LOOKBACK_SECS=7200: the boot read starts 2 hours before the merge"* && "$HDR" == *"(c_channel_dark) until a new boot reports"* \
   && "$HDR" == *"APPLY_WF is restated here with no parity check against the workflow YAML"* ]]; then
  pass "header documents the shipper-only population, the hard-coded PR number, the 2h pre-merge lookback and the unchecked workflow name"
else
  fail "header lacks a documented limit (shipper-only population, PR_NUMBER, PRE_MERGE_LOOKBACK_SECS, APPLY_WF)"
fi
cases=$((cases + 1))
if ! /usr/bin/grep -aqE 'gh[[:space:]]+(issue|pr[[:space:]]+(close|comment|edit|merge)|api[[:space:]]+(-X|--method))' <(sed -E 's/^[[:space:]]*#.*$//' "$SUT"); then
  pass "no write-shaped gh invocation in the probe's code"
else
  fail "the probe's code contains a write-shaped gh invocation"
fi
cases=$((cases + 1))
if /usr/bin/grep -aqE '^[[:space:]]*case "\$-" in' "$SUT" && /usr/bin/grep -aqF 'exit 78' "$SUT"; then
  pass "the xtrace refusal is present (exit 78)"
else
  fail "no xtrace refusal in the probe"
fi
cases=$((cases + 1))
if /usr/bin/grep -aqF 'secrets=GH_TOKEN,BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD' "$SUT"; then
  pass "the header carries the tracker directive with a COMMA-separated secrets= list"
else
  fail "directive missing or its secrets= list is not comma-separated"
fi

# ── mutation rows ────────────────────────────────────────────────────────────────────────────
mutant() { # <name> <sed-expr> <case-fn>...
  local name="$1" expr="$2"; shift 2
  local d="$WORK/mut-$name"; assert_fixture_dir "$d"
  mkdir -p "$d/scripts/followthroughs"
  local m="$d/scripts/followthroughs/registry-clientip-alert-7530.sh"
  cp "$SUT" "$m"
  sed -E -i "$expr" "$m"
  cases=$((cases + 1))
  if cmp -s "$SUT" "$m"; then
    fail "mutant $name: the edit did not land (the probe text drifted from this row)"
    return
  fi
  bash -n "$m" 2>/dev/null || { fail "mutant $name: the edit produced a syntax error, so it proves nothing"; return; }
  local c
  MUT_RED=0; MUT_CRASH=0; MUTANT_MODE=1; PROBE="$m"; rm -f "$CRASH_FLAG"
  for c in "$@"; do "case_$c"; done
  MUTANT_MODE=0; PROBE="$SUT"
  [[ -e "$CRASH_FLAG" ]] && MUT_CRASH=1
  rm -f "$CRASH_FLAG"
  # MUT_WANT=crash is the harness's own self-check: a verdict-less death MUST classify as UNRESOLVED.
  if [[ "${MUT_WANT:-red}" == "crash" ]]; then
    if (( MUT_CRASH )); then pass "mutant $name -> UNRESOLVED (a verdict-less death is not a kill: $*)"; else fail "mutant $name: a crash was credited as a kill or missed: $*"; fi
    return
  fi
  if (( MUT_CRASH )); then fail "mutant $name died by a crash or a verdict-less exit (UNRESOLVED, not a designed kill): $*"; return; fi
  if (( MUT_RED )); then pass "mutant $name -> RED (killed by: $*)"; else fail "mutant $name SURVIVED: $*"; fi
}

mutant ancestry                's/^descends\(\) \{$/descends() { return 0/' apply_not_descendant
mutant descendant_only_merge   's/^descends\(\) \{$/descends() { [[ "$1" == "$MERGE_SHA" ]]; return $?/' apply_displaced_descendant_ok
mutant refire_is_rerun         's/Re-fire: gh workflow run apply-web-platform-infra.yml --ref main -f apply_target=manual-rerun/Re-fire: gh run rerun 1 --failed/' apply_failed refire_parity
mutant refire_parity_alone     's/Re-fire: gh workflow run apply-web-platform-infra.yml --ref main -f apply_target=manual-rerun/Re-fire: gh run rerun 1 --failed/' refire_parity
mutant refire_prose_old        '/What clears this verdict/d; /Transient failure:/d; /Config defect:/d; s/  \(NOT counted:[^"]*"/ (or push a no-op change under apps\/web-platform\/infra\/ so a descendant apply runs)."/' apply_failed apply_failed_clears_by_push apply_failed_dispatch_succeeded
mutant push_event_clause_dropped '/What clears this verdict/d' apply_failed_clears_by_push
mutant not_counted_label_dropped 's/  \(NOT counted:[^"]*"/"/' apply_failed apply_failed_dispatch_succeeded
mutant dispatch_counted        's/\[\.\[\] \| select\(\.event == "push"\)\]/[.[]]/' apply_failed_dispatch_succeeded apply_dispatch_event
mutant apply_failed_is_1       '/verdict=c_apply_failed/,/exit 3/ s/exit 3/exit 1/' apply_failed
mutant offset0_anchor          's/startswith\(\$pfx\)/contains($pfx)/' quoting_offset
mutant tail_cut                's/i = index\(m, " zot_last_err="\)/i = 0 * index(m, " zot_last_err=")/' tail_forge_boot
mutant host_scope              's/^EXPECTED_HOST="[a-z-]+"$/EXPECTED_HOST=".*"/' other_host
mutant post_merge_boot         's/if ! \[\[ "\$MERGE_STR" < "\$FIRST_DT" \]\]; then/if false; then/' old_boot_only foreign_new_boot
mutant min_span                's/^MIN_SPAN_SECS=[0-9]+$/MIN_SPAN_SECS=0/' boot_too_young
mutant silent_threshold        's/^SILENT_SECS=[0-9]+$/SILENT_SECS=99999999/' producer_silent
mutant as_written_is_pass      '/verdict=f_non_rfc1918/,/exit 1/ s/exit 1/exit 0/' as_written_positive
mutant table_mismatch_is_pass  '/verdict=f_table_mismatch/,/exit 1/ s/exit 1/exit 0/' table_mismatch table_mismatch_private
mutant population_empty_is_1   '/verdict=c_population_empty/,/exit 3/ s/exit 3/exit 1/' population_empty
mutant control_dead_is_1       '/verdict=c_control_dead/,/exit 3/ s/exit 3/exit 1/' control_dead
mutant control_not_flipped     's/ctl_tail = tail\.replace\(NOT_PRIVATE, POS_PRIVATE\)/ctl_tail = tail/' sql_parity
mutant count_accepts_empty     "s/^INT_RE=.*/INT_RE='^[0-9]*\$'/" count_missing
mutant count_accepts_signed    "s/^INT_RE=.*/INT_RE='^-?[0-9]+\$'/" count_negative
mutant start_is_boot_since     's/^START_ISO=.*/START_ISO="$BOOT_SINCE"/' query_windows
mutant boot_read_unwindowed    's/ --since "\$BOOT_SINCE"//' query_windows
mutant lookback_zero           's/^PRE_MERGE_LOOKBACK_SECS=[0-9]+$/PRE_MERGE_LOOKBACK_SECS=0/' old_host_premerge_only
mutant boot_time_token_shared  's/verdict=c_boot_time_unparsable/verdict=c_boot_read_failed rc=0/' boot_time_unparsable
mutant dt_norm_all             's/ \| sub\("T"; " "\) \| sub\("Z\$"; ""\) \| sub\("[\\][\\]\.[^"]*"; ""\)//' dt_iso_pass dt_frac_boundary dt_isoz_boundary
mutant dt_norm_frac            's/ \| sub\("[\\][\\]\.[^"]*"; ""\)//' dt_frac_boundary
mutant dt_norm_tz              's/ \| sub\("T"; " "\) \| sub\("Z\$"; ""\)//' dt_iso_pass dt_isoz_boundary
mutant pass_pointer_dropped    's/re-date them per knowledge-base/REDATED/' pass_redate_pointer
mutant pointer_in_every_say    's/^  local l$/  local l; printf "  %s\\n" "re-date them per knowledge-base\/engineering\/operations\/runbooks\/registry-clientip-rfc1918-7530.md"/' apply_failed as_written_positive control_dead table_mismatch
mutant count_leading_zero_ok   "s/^INT_RE=.*/INT_RE='^[0-9]+\$'/" count_junk
mutant decode_sort_dropped     's/(@tsv.? 2>\/dev\/null) \| sort$/\1 | cat/' rows_descending
mutant dt_norm_order           's/ \| sub\("[\\][\\]\.[^"]*"; ""\)//; s/\| sub\("T"; " "\)/| sub("\\\\.[0-9]+$"; "") | sub("T"; " ")/' dt_both_boundary
mutant local_name_drift        's/^LOCAL = "registry_clientip_not_rfc1918_sql"$/LOCAL = "registry_clientip_not_rfc1918_query"/' local_parity
mutant xtrace_refusal          's/exit 78/exit 0/' trace
mutant table_count_floor       's/^TABLE_ROWS=16$/TABLE_ROWS=15/' pass table_short
mutant count_unanchored_end     "s/^INT_RE=.*/INT_RE='^[0-9]+'/" count_junk
mutant count_accepts_junk       "s/^INT_RE=.*/INT_RE='^.*\$'/" count_junk
mutant window_outer_le          's/(base = " FROM " \+ src \+ " WHERE dt )>=/\1<=/' query_windows
mutant window_remote_le         's/(FROM remote\(\$BS_TABLE\) WHERE dt )>=/\1<=/' query_windows
mutant window_s3_le             's/(_row_type = 1 AND dt )>=/\1<=/' query_windows
mutant boot_read_until          's/(BOOT_RAW=.*--limit "\$WINDOW_LIMIT")/\1 --until "$BOOT_SINCE"/' query_windows
mutant window_limit_1000        's/^WINDOW_LIMIT=5000$/WINDOW_LIMIT=1000/' query_windows
mutant boot_last_check_dropped  's/ && "\$LAST_EPOCH" =~ \$INT_RE//' boot_time_unparsable
mutant boot_first_check_dropped 's/"\$FIRST_EPOCH" =~ \$INT_RE && //' boot_time_unparsable
# A verdict-less death must be UNRESOLVED in the cases that do not go through expect() as well.
MUT_WANT=crash mutant crash_is_not_a_kill_query_windows '/^PRE_MERGE_LOOKBACK_SECS=/ s/=.*/=${UNDEF_X}/' query_windows
MUT_WANT=crash mutant crash_is_not_a_kill_sql_parity    '/^PRE_MERGE_LOOKBACK_SECS=/ s/=.*/=${UNDEF_X}/' sql_parity

# The suite's own stderr (buffered in $STDERR_LOG since the top of the file) must be EMPTY on a green run: the
# crash self-check mutants kill the probe before it writes its fixtures, and the custom cases that read those
# fixtures are guarded, so no `No such file` text may reach stderr. A failing run also trips this (its FAIL lines
# are stderr), which is harmless: the run is red already.
cases=$((cases + 1))
if [[ ! -s "$STDERR_LOG" ]]; then
  pass "the suite wrote nothing to stderr (a green run has an empty stderr)"
else
  fail "the suite wrote $(wc -l < "$STDERR_LOG") line(s) to stderr; first: $(head -n 1 "$STDERR_LOG" | cut -c1-160)"
fi

echo ""
echo "=== registry-clientip-alert-7530.test.sh: ${passes} passed, ${fails} failed (${cases} asserted) ==="
declare -A seen_rc=()
while IFS=$'\t' read -r want _tok; do seen_rc["$want"]=1; done < "$MARKER_LOG"
for want in 0 1 2 3 78; do
  if [[ -z "${seen_rc[$want]:-}" ]]; then
    echo "FAIL: no case exercised exit code $want" >&2
    fails=$((fails + 1))
  fi
done
probe_tokens="$(/usr/bin/grep -aoE 'verdict=[a-z][a-z0-9_]*' "$SUT" | cut -d= -f2 | sort -u)"
missing_tokens=""
for t in $probe_tokens; do
  /usr/bin/grep -aqF -- "$t" "$MARKER_LOG" || missing_tokens+=" $t"
done
if [[ -n "$missing_tokens" ]]; then
  echo "FAIL: verdict tokens in the probe that no case asserts:$missing_tokens" >&2
  fails=$((fails + 1))
fi
n_tokens="$(cut -f2 "$MARKER_LOG" | sort -u | /usr/bin/grep -ac .)"
if [[ "$n_tokens" -lt 32 ]]; then
  echo "FAIL: only $n_tokens distinct verdict tokens were asserted (floor 32, the measured count) — a case block stopped running" >&2
  fails=$((fails + 1))
fi
if [[ "$passes" -lt 136 ]]; then
  echo "FAIL: only $passes assertions passed (floor 136) — a case block stopped running" >&2
  exit 1
fi
[[ "$fails" -eq 0 ]] || exit 1
