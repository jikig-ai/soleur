#!/usr/bin/env bash
# Companion suite for scripts/followthroughs/git-data-rehearsal-evidence.sh (#8211, T2 build 2).
#
# Registered EXPLICITLY in scripts/test-all.sh: scripts/followthroughs/ matches no SUITE_GLOBS entry, so an
# unregistered .test.sh is an orphan that gates nothing while looking exactly like coverage.
#
# OFFLINE BY CONSTRUCTION. The collector is copied into a synthesized tree beside a STUB scripts/betterstack-query.sh,
# the real scripts/lib/{bearer-curl,betterstack-sources,betterstack-read-classify,git-data-rotate-stamp}.sh, and `gh` / `curl`
# shims first on PATH. No network, no Doppler, no credential: the "credentials" below are synthetic strings, and a positive
# control proves the Sentry one travelled on curl's stdin config (so "no secret in argv" cannot pass for lack of a request).
#
# THE FAKES ARE STRICT. The gh shim answers only the exact argv shapes the collector is modelled to send (anything else exits
# 64), the curl shim answers 405 to a body-carrying request that is not a GET (-G), and the reader stub records both pinned
# tables. The SQL the collector sends is asserted literally (lower and upper time bounds, host list, stage, archive arm), because
# a stub that answers by query SHAPE cannot see a bound that went to 1970.
#
# WHAT THIS PINS, in the order a reviewer would ask:
#   * the section 5 block is filled from the fixtures, line by line, and decoys (the step source that `run:` echoes at the head
#     of a log group, and a forged line in another step) are NOT counted as log lines;
#   * the collector is read-only: every gh call is `run view` / `issue view`, every SQL is a SELECT, every curl is a GET;
#   * no secret, no row body, no host name and no malformed fingerprint reaches stdout or stderr;
#   * a read that did not run reads UNREAD(<token>) with exit 3, never a printed zero: a wrong run id (every identity conjunct),
#     a step that did not succeed but carries a timestamp, a renamed step, an empty log, a silent host, an all-zero window,
#     Better Stack credentials not injected, an absent, refused or rejected Sentry token, a Sentry that is silent.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SUT="$HERE/git-data-rehearsal-evidence.sh"

[[ -f "$SUT" ]] || { echo "FATAL: SUT not found at $SUT" >&2; exit 1; }
[[ -x "$SUT" ]] || { echo "FATAL: SUT not executable at $SUT" >&2; exit 1; }
for _lib in bearer-curl.sh betterstack-sources.sh betterstack-read-classify.sh git-data-rotate-stamp.sh; do
  [[ -f "$ROOT/scripts/lib/$_lib" ]] || { echo "FATAL: scripts/lib/$_lib missing" >&2; exit 1; }
done
command -v jq >/dev/null 2>&1 || { echo "FATAL: jq is required" >&2; exit 1; }

# Refuses an empty, relative, root or synthetic-fs fixture dir (byte-identical copy; the
# fixture-dir-operand-assert suite pins every tracked copy).
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

total=0
fails=0
pass() { total=$((total + 1)); printf '  PASS: %s\n' "$1"; }
fail() { total=$((total + 1)); fails=$((fails + 1)); printf '  FAIL: %s\n' "$1" >&2; }

# Instrument self-test: both counters must move before any verdict is trusted.
_t0=$total; _f0=$fails
pass "instrument" >/dev/null
fail "instrument" 2>/dev/null
if (( total != _t0 + 2 || fails != _f0 + 1 )); then
  printf 'FATAL: instrument self-test -- pass()/fail() did not both move counters\n' >&2; exit 1
fi
total=$_t0; fails=$_f0

WORK="$(mktemp -d -t gdre-evidence.XXXXXXXX)" || { echo "FATAL: mktemp failed" >&2; exit 2; }
assert_fixture_dir "$WORK"
trap 'rm -rf "$WORK" 2>/dev/null' EXIT INT TERM HUP
FX="$WORK/fx"
TREE="$WORK/tree"
BIN="$WORK/bin"
NOJQ="$WORK/nojq"
assert_fixture_dir "$FX"
assert_fixture_dir "$TREE"
assert_fixture_dir "$BIN"
assert_fixture_dir "$NOJQ"
mkdir -p "$FX" "$BIN" "$NOJQ" "$TREE/scripts/followthroughs" "$TREE/scripts/lib"

# --- the synthesized tree ---------------------------------------------------------------------------------------------
cp "$SUT" "$TREE/scripts/followthroughs/git-data-rehearsal-evidence.sh"
chmod +x "$TREE/scripts/followthroughs/git-data-rehearsal-evidence.sh"
for _lib in bearer-curl.sh betterstack-sources.sh betterstack-read-classify.sh git-data-rotate-stamp.sh; do
  cp "$ROOT/scripts/lib/$_lib" "$TREE/scripts/lib/$_lib"
done
MUT="$TREE/scripts/followthroughs/git-data-rehearsal-evidence.sh"

# Synthetic credentials. They are recognisable so a leak is unambiguous, and shaped to pass the real token guards.
SENTRY_SYN="synsentrytoken0123456789abcdef"
BS_PASS_SYN="synbspassword0123456789abcdef"

cat > "$TREE/scripts/betterstack-query.sh" <<'STUB'
#!/usr/bin/env bash
# Stub reader: records its argv, both pinned tables and the SQL; answers from $FX by query shape.
printf '%s\n' "$*" >> "$FX/bs.argv"
printf '%s|%s\n' "${BS_TABLE:-unset}" "${BS_TABLE_S3:-unset}" >> "$FX/bs.table"
printf '%s\n----\n' "$1" >> "$FX/bs.sql"
[[ -n "${BS_STUB_RC:-}" ]] && exit "$BS_STUB_RC"
case "$1" in
  *"AS pin_n"*) cat "$FX/bs-app.jsonl" ;;
  *boot_complete*) cat "$FX/bs-boot.jsonl" ;;
  *) exit 99 ;;
esac
STUB
chmod +x "$TREE/scripts/betterstack-query.sh"

# STRICT gh: the exact argv shapes the collector is modelled to send; anything else is exit 64.
cat > "$BIN/gh" <<'GH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FX/gh.argv"
JSONF='databaseId,attempt,workflowName,displayTitle,headBranch,event,status,conclusion,createdAt,updatedAt,jobs'
if [[ "$*" =~ ^run\ view\ ([0-9]+)\ --repo\ jikig-ai/soleur\ --json\ $JSONF$ ]]; then
  id="${BASH_REMATCH[1]}"
  for f in ${GH_FAIL_IDS:-}; do [[ "$f" == "$id" ]] && exit 1; done
  cat "$FX/run-$id.json" || exit 1
elif [[ "$*" =~ ^run\ view\ ([0-9]+)\ --repo\ jikig-ai/soleur\ --attempt\ ([0-9]+)\ --log$ ]]; then
  id="${BASH_REMATCH[1]}"
  for f in ${GH_FAIL_LOG_IDS:-}; do [[ "$f" == "$id" ]] && exit 1; done
  cat "$FX/log-$id.txt" || exit 1
elif [[ "$*" == "issue view 10166 --repo jikig-ai/soleur --json state -q .state" ]]; then
  printf '%s\n' "${GH_ISSUE_STATE:-CLOSED}"
else
  exit 64
fi
GH
chmod +x "$BIN/gh"

# STRICT curl: a request carrying --data-urlencode without -G would be a POST; the shim answers 405 to it.
cat > "$BIN/curl" <<'CURL'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FX/curl.argv"
cat >> "$FX/curl.stdin"
out=""; q="__unset__"; get=0; body=0; args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  case "${args[i]}" in
    -o) out="${args[i+1]}" ;;
    -G|--get|-sS*G*) get=1 ;;
    --data-urlencode) body=1; v="${args[i+1]}"; case "$v" in query=*) q="${v#query=}" ;; esac ;;
  esac
done
for a in "$@"; do [[ "$a" == "-G" ]] && get=1; done
if (( body && ! get )); then printf '405'; exit 0; fi
case "$q" in
  "") n="${SENTRY_ALL_N:-5}" ;;
  *git-data-bare-repo-erasure*) n="${SENTRY_ERASURE_N:-0}" ;;
  *pin_fault*) n="${SENTRY_PINFAULT_N:-0}" ;;
  *) n=0 ;;
esac
[[ -n "$out" ]] && printf '{"data":[{"count()":%s}]}' "$n" > "$out"
printf '%s' "${CURL_CODE:-200}"
CURL
chmod +x "$BIN/curl"

# --- fixtures ---------------------------------------------------------------------------------------------------------
FLIP=1001
ROLLBACK=1002
EXITRUN=1003
PB=1004
ROTATE=1005
REFS=1006
WFNAME='git-data cutover (#5274 / ADR-220 / ADR-239)'

# write_run <id> <title> <createdAt> <jobs-json> [workflowName]
write_run() {
  jq -n --argjson id "$1" --arg t "$2" --arg c "$3" --arg w "${5:-$WFNAME}" --argjson jobs "$4" \
    '{databaseId: $id, attempt: 1, workflowName: $w, displayTitle: $t, headBranch: "main", event: "workflow_dispatch",
      status: "completed", conclusion: "success", createdAt: $c, updatedAt: $c, jobs: $jobs}' > "$FX/run-$1.json"
}
FLIP_JOBS='[{"name":"cutover","steps":[
  {"name":"Write GIT_DATA_STORE_ENABLED (via the","conclusion":"success","completedAt":"2026-10-20T09:10:00Z"},
  {"name":"Write GIT_DATA_LUKS_CUTOVER_AT (last — proven cutover only)","conclusion":"success","completedAt":"2026-10-20T09:25:00Z"},
  {"name":"Finalizer — total unwind on an incomplete flip","conclusion":"success","completedAt":"2026-10-20T09:26:00Z"}]}]'
RB_JOBS='[{"name":"cutover","steps":[
  {"name":"Write GIT_DATA_STORE_ENABLED (via the","conclusion":"success","completedAt":"2026-10-20T09:40:30Z"},
  {"name":"Positive replication probe","conclusion":"success","completedAt":"2026-10-20T09:45:00Z"},
  {"name":"Finalizer — total unwind on an incomplete flip","conclusion":"success","completedAt":"2026-10-20T09:46:00Z"}]}]'
write_run "$FLIP" "git-data flip" "2026-10-20T09:00:00Z" "$FLIP_JOBS"
write_run "$ROLLBACK" "git-data rollback" "2026-10-20T09:30:00Z" "$RB_JOBS"
write_run "$EXITRUN" "git-data proof" "2026-10-20T10:00:00Z" '[]'
write_run "$PB" "git-data proof" "2026-10-20T09:50:00Z" '[]'
REFS_JOBS='[{"name":"cutover","steps":[
  {"name":"Host-side refs assertion (store probes + one refs read)","conclusion":"success","completedAt":"2026-10-20T09:36:00Z"}]}]'
write_run "$REFS" "git-data refs_assert" "2026-10-20T09:35:00Z" "$REFS_JOBS"

# A log line is `<job>\t<step>\t<timestamp> <message>`. The DECOY lines are the step source `run:` echoes at the head of a
# group (same words, after `echo "`), and a forged line in a DIFFERENT step: neither may count.
BOM=$'\357\273\277'
ll() { printf 'cutover\t%s\t%s %s\n' "$1" "$2" "$3"; }
# shellcheck disable=SC2016  # literal step source: nothing may expand
{
  ll "Validate mode" "2026-10-20T09:00:05.0000000Z" "host web-1: git_data_store=enabled observed (attempt 1)"
  ll "Per-host git_data_store= assertion (Better Stack)" "2026-10-20T09:11:00.0000000Z" '      echo "host $leg: git_data_store=${EXPECTED} observed (attempt $i)"'
  printf 'cutover\t%s\t%s%s %s\n' "Per-host git_data_store= assertion (Better Stack)" "$BOM" "2026-10-20T09:12:01.1234567Z" "host web-1: git_data_store=enabled observed (attempt 1)"
  ll "Per-host git_data_store= assertion (Better Stack)" "2026-10-20T09:13:02.7654321Z" "host web-2: git_data_store=enabled observed (attempt 2)"
  ll "Finalizer — total unwind on an incomplete flip" "2026-10-20T09:26:00.0000000Z" '          echo "finalizer: unwind complete."'
  ll "Finalizer — total unwind on an incomplete flip" "2026-10-20T09:26:01.0000000Z" "finalizer: flip concluded — nothing to unwind."
} > "$FX/log-$FLIP.txt"
# shellcheck disable=SC2016  # literal step source: nothing may expand
{
  ll "Per-host git_data_store= assertion (Better Stack)" "2026-10-20T09:41:11.0000000Z" "host web-1: git_data_store=disabled observed (attempt 1)"
  ll "Per-host git_data_store= assertion (Better Stack)" "2026-10-20T09:42:22.0000000Z" "host web-2: git_data_store=disabled observed (attempt 1)"
  ll "Positive replication probe" "2026-10-20T09:44:00.0000000Z" '        log "STORE probe=probe verdict=ok"'
  ll "Positive replication probe" "2026-10-20T09:44:30.0000000Z" "[git-data-cutover] STORE probe=probe verdict=ok"
} > "$FX/log-$ROLLBACK.txt"
# shellcheck disable=SC2016  # literal step source: nothing may expand
{
  ll "Validate mode" "2026-10-20T10:00:30.0000000Z" "##[notice]verdict=store_not_empty"
  ll "Host-side proof (access gate + store probes + fence)" "2026-10-20T10:01:00.0000000Z" '      echo "::notice title=git-data-cutover store::verdict=clear"'
  ll "Host-side proof (access gate + store probes + fence)" "2026-10-20T10:01:30.0000000Z" "##[notice]verdict=clear"
} > "$FX/log-$EXITRUN.txt"
{
  ll "Host-side proof (access gate + store probes + fence)" "2026-10-20T09:51:00.0000000Z" "##[error]probe=store-empty verdict=store_not_empty"
} > "$FX/log-$PB.txt"

# The refs_assert run's log: the step source echo (decoy), the real lines, and a forged confirmation in a DIFFERENT step.
REFS_SHA1="0123456789abcdef0123456789abcdef01234567"
REFS_SHA2="89abcdef0123456789abcdef0123456789abcdef"
REFS_STEP_NAME="Host-side refs assertion (store probes + one refs read)"
# shellcheck disable=SC2016  # literal step source: nothing may expand
{
  ll "$REFS_STEP_NAME" "2026-10-20T09:35:10.0000000Z" '        log "REFS-CONFIRMED"'
  ll "$REFS_STEP_NAME" "2026-10-20T09:35:30.0000000Z" "[git-data-cutover] STORE probe=refs-assert verdict=ok"
  ll "$REFS_STEP_NAME" "2026-10-20T09:35:31.0000000Z" "[git-data-cutover] REFS-CONFIRMED"
  ll "$REFS_STEP_NAME" "2026-10-20T09:35:32.0000000Z" "[git-data-cutover] REFS_ASSERT ok repos=1 namespaces=1 refs=2 heads=2 shas=${REFS_SHA1},${REFS_SHA2}"
  ll "Validate mode" "2026-10-20T09:35:40.0000000Z" "[git-data-cutover] REFS-CONFIRMED"
} > "$FX/log-$REFS.txt"

FP_OK="SHA256:abcdefghijklmnopqrstuvwxyz0123456789ABCDEFG"
FP_B="SHA256:ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefg"
# web-1 has TWO source names (platform and the not-yet-retired inngest alias): the label must SUM them.
write_app_rows() { # <fps json array for the web-1 platform row>
  {
    jq -cn --argjson f "$1" '{h:"soleur-web-platform",pin_n:2,ssh_n:2,store_n:2,fps:$f,raw:"SECRET-ROW-BODY-DECOY"}'
    jq -cn --arg f "$FP_OK" '{h:"soleur-inngest-prd",pin_n:1,ssh_n:1,store_n:1,fps:[$f]}'
    jq -cn --arg f "$FP_OK" '{h:"soleur-web-2",pin_n:1,ssh_n:1,store_n:1,fps:[$f]}'
    jq -cn '{h:"some-other-host",pin_n:9,ssh_n:9,store_n:9,fps:["SHA256:zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz"]}'
  } > "$FX/bs-app.jsonl"
}
write_app_rows "[\"$FP_OK\"]"
printf '{"t":"2026-10-20T08:05:00Z","n":1}\n' > "$FX/bs-boot.jsonl"
# The rotate run: a git_data_host_replace job whose apply step and last-step marker both succeeded.
ROT_JOBS='[{"name":"git_data_host_replace","conclusion":"success","steps":[
     {"name":"Rotate precondition — served store measured empty","conclusion":"success"},
     {"name":"Terraform apply (git-data-host -replace) — post-apply backstop","conclusion":"success","completedAt":"2026-10-20T08:04:00Z"},
     {"name":"Rotate completed (d6 marker)","conclusion":"success"}]}]'
RWF='Apply web-platform infra (terraform plan/apply)'
write_run "$ROTATE" "Apply web-platform infra" "2026-10-20T08:00:00Z" "$ROT_JOBS" "$RWF"

# variant <new id> <jq filter over the source run> [source id]: a doctored copy of a run, with its log.
variant() {
  local nid="$1" filter="$2" src="${3:-$FLIP}"
  jq --argjson id "$nid" ".databaseId = \$id | $filter" "$FX/run-$src.json" > "$FX/run-$nid.json"
  cp "$FX/log-$src.txt" "$FX/log-$nid.txt" 2>/dev/null || : > "$FX/log-$nid.txt"
}

# --- the runner -------------------------------------------------------------------------------------------------------
RC=0; OUT=""; ERR=""
BS_OFF=0
run_sut() { # args...  (the arm's extra environment is ARM_ENV, a list of NAME=value words)
  : > "$FX/bs.argv"; : > "$FX/bs.table"; : > "$FX/bs.sql"; : > "$FX/gh.argv"; : > "$FX/curl.argv"; : > "$FX/curl.stdin"
  local -a creds=(BETTERSTACK_QUERY_HOST="syn.betterstackdata.com" BETTERSTACK_QUERY_USERNAME="synuser" BETTERSTACK_QUERY_PASSWORD="$BS_PASS_SYN")
  (( BS_OFF )) && creds=()
  # shellcheck disable=SC2086  # ARM_ENV is a deliberate word list of NAME=value assignments
  OUT="$(env -i PATH="${ARM_PATH:-$BIN:$PATH}" HOME="$WORK" TMPDIR="$WORK" FX="$FX" "${creds[@]}" \
      ${ARM_ENV:-} "$@" 2>"$FX/stderr.txt")"
  RC=$?
  ERR="$(cat "$FX/stderr.txt")"
}
BASE_ARGS=(--flip "$FLIP" --rollback "$ROLLBACK" --exit "$EXITRUN" --rotate "$ROTATE" --level 1)
sut() { run_sut bash "$MUT" "$@"; }
ARM_ENV="SENTRY_ISSUE_RO_TOKEN=$SENTRY_SYN"
reset_env() { ARM_ENV="SENTRY_ISSUE_RO_TOKEN=$SENTRY_SYN"; ARM_PATH=""; BS_OFF=0; }

assert_eq() { # <name> <want> <got>
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1 (want [$2], got [$3])"; fi
}
assert_has() { # <name> <haystack> <needle>
  if [[ "$2" == *"$3"* ]]; then pass "$1"; else fail "$1 (missing [$3])"; fi
}
assert_lacks() { # <name> <haystack> <needle>
  if [[ "$2" != *"$3"* ]]; then pass "$1"; else fail "$1 (found forbidden [$3])"; fi
}
line_of() { grep -m1 -F -- "$1" <<<"$OUT" || true; }

# CONTROL: each verdict-owning helper must be able to REJECT. Drive it with an input that must fail and require its failure
# counter to move; unwind the counters so the exact total stays exact. Reported with printf + exit, never through the helpers.
_c0=$total; _f0=$fails
assert_eq "control" "a" "b" 2>/dev/null
assert_has "control" "abc" "z" 2>/dev/null
assert_lacks "control" "abc" "a" 2>/dev/null
if (( fails != _f0 + 3 || total != _c0 + 3 )); then
  printf 'FATAL: a verdict helper (assert_eq / assert_has / assert_lacks) failed to reject an input that must fail\n' >&2; exit 1
fi
total=$_c0; fails=$_f0

# ===== ARM 1: the happy path fills every machine-collected line ======================================================
sut "${BASE_ARGS[@]}"
HAPPY_OUT="$OUT"; HAPPY_ERR="$ERR"; HAPPY_RC=$RC
assert_eq "happy: exit 0" "0" "$HAPPY_RC"
assert_eq "happy: title line" "git-data flip-then-rollback rehearsal (#8211, CPO condition)" "$(printf '%s\n' "$OUT" | head -1)"
U="https://github.com/jikig-ai/soleur/actions/runs"
assert_eq "happy: flip line (decoy finalizer echo not counted: unwound no)" \
  "flip run:      $U/$FLIP   dispatched 2026-10-20T09:00:00Z   conclusion success   stamp step success   finalizer ran yes (unwound no)" \
  "$(line_of 'flip run:')"
assert_eq "happy: rollback line (decoy probe echo not counted, real line seen)" \
  "rollback run:  $U/$ROLLBACK   dispatched 2026-10-20T09:30:00Z   conclusion success   probe step success   \"STORE probe=probe verdict=ok\" seen" \
  "$(line_of 'rollback run:')"
assert_eq "happy: window minutes from the two flag_write completions" \
  "window:        flag-on from 2026-10-20T09:10:00Z to 2026-10-20T09:40:30Z = 30.5 minutes" "$(line_of 'window:')"
assert_eq "happy: per-host timestamps are step-scoped and BOM-tolerant (a forged line in another step is ignored)" \
  "per-host:      web-1 git_data_store=enabled 2026-10-20T09:12:01Z / disabled 2026-10-20T09:41:11Z;  web-2 git_data_store=enabled 2026-10-20T09:13:02Z / disabled 2026-10-20T09:42:22Z" \
  "$(line_of 'per-host:')"
assert_eq "happy: app path line, other hosts excluded, both web-1 source names summed, Sentry window printed" \
  "app path:      level 1; startup lines after rollback flag-off: pin $FP_OK (web-1 3, web-2 1), ssh_client present (web-1 3, web-2 1), store disabled (web-1 3, web-2 1); Sentry events R1..R6: 0 (erasure 0, pin_fault 0) in 2026-10-20T09:00:00..2026-10-20T10:00:00" \
  "$(line_of 'app path:')"
assert_eq "happy: level 1 without --refs leaves the refs line n/a (no synthetic session ran)" "refs read:     n/a (level 1; no synthetic session ran)" "$(line_of 'refs read:')"
assert_eq "happy: level 1 leaves the level 2 line n/a" "               level 2 only: n/a (level 1)" "$(line_of 'level 2 only')"
assert_eq "happy: exit read (a forged verdict in another step is ignored)" \
  "exit read:     mode=proof run $U/$EXITRUN   dispatched 2026-10-20T10:00:00Z   conclusion success   verdict clear" "$(line_of 'exit read:')"
assert_eq "happy: predecessor line (plan_only false from a stamped d6 verdict, boot_complete from the git-data table)" \
  "predecessor:   rotate run $ROTATE, apply step success, plan_only false, new-server boot_complete 2026-10-20T08:05:00Z; #10166 CLOSED" \
  "$(line_of 'predecessor:')"
assert_has "happy: owner-supplied fields are marked, not invented" "$OUT" "queue check:   <owner:"
assert_has "happy: the not-covered line is carried" "$OUT" "not covered:   real-user replication load"
assert_eq "happy: no UNREAD anywhere" "0" "$(printf '%s\n%s\n' "$OUT" "$ERR" | grep -c 'UNREAD' || true)"

# ===== ARM 2: read-only, confidential, argv-clean, correctly bounded =================================================
GH_VERBS="$(cut -d' ' -f1,2 "$FX/gh.argv" | sort -u | paste -sd, -)"
assert_eq "readonly: gh is only ever asked to view a run or an issue" "issue view,run view" "$GH_VERBS"
sut "${BASE_ARGS[@]}"
SQL_ALL="$(cat "$FX/bs.sql")"
assert_eq "readonly: every Better Stack call is a SELECT" "2" "$(grep -c '^SELECT' "$FX/bs.sql" || true)"
assert_eq "readonly: no write keyword in any SQL" "0" "$(printf '%s' "$SQL_ALL" | grep -ciE '\b(INSERT|ALTER|DROP|TRUNCATE|CREATE|UPDATE|DELETE|OPTIMIZE|GRANT)\b' || true)"
assert_eq "pinned: hot AND archive table of the shared control source for the web-app lines, then of the git-data source for boot_complete" \
  "t520508_soleur_inngest_vector_prd_3_logs|t520508_soleur_inngest_vector_prd_3_s3,t520508_soleur_git_data_prd_logs|t520508_soleur_git_data_prd_s3" "$(paste -sd, "$FX/bs.table")"
# shellcheck disable=SC2016  # the literal $BS_TABLE_S3 token is what the reader substitutes
assert_has "pinned: the archive arm is part of the app-path read" "$SQL_ALL" 's3Cluster(primary, $BS_TABLE_S3) WHERE _row_type = 1'
assert_has "bounded: lower bound is the rollback flag-off write, in ClickHouse form" "$SQL_ALL" "dt >= '2026-10-20 09:40:30'"
assert_has "bounded: upper bound is the exit proof's dispatch" "$SQL_ALL" "dt <= '2026-10-20 10:00:00'"
assert_has "bounded: the web hosts are the closed list (incl. the not-yet-retired web-1 alias)" "$SQL_ALL" "IN ('soleur-web-platform','soleur-inngest-prd','soleur-web-2')"
assert_has "bounded: the state counted is store=disabled" "$SQL_ALL" "git_data_store=disabled"
assert_has "bounded: boot_complete is read for the git-data host only" "$SQL_ALL" "JSONExtractString(raw,'stage') = 'boot_complete' AND JSONExtractString(raw,'host_name') = 'soleur-git-data'"
assert_has "bounded: boot_complete is read from the rotate's apply step to the flip's dispatch" "$SQL_ALL" "dt >= '2026-10-20 08:04:00' AND dt <= '2026-10-20 09:00:00'"
assert_eq "argv: the reader's argv is only the SQL (no credential)" "0" "$(grep -c "$BS_PASS_SYN" "$FX/bs.argv" || true)"
assert_eq "argv: no Sentry bearer on curl's argument list" "0" "$(grep -c "$SENTRY_SYN" "$FX/curl.argv" || true)"
assert_has "argv positive control: the bearer DID travel on curl's stdin config" "$(cat "$FX/curl.stdin")" "Authorization: Bearer $SENTRY_SYN"
CURL_ARGV="$(cat "$FX/curl.argv")"
assert_eq "sentry: three requests (an unfiltered liveness count, then erasure, then pin_fault), each a GET (-G) of the pinned events endpoint" "3" \
  "$(grep -c -- ' -G .*https://jikigai-eu.sentry.io/api/0/organizations/jikigai-eu/events/ --config -$' "$FX/curl.argv" || true)"
assert_eq "sentry: no curl request carries a body-write method" "0" "$(grep -cE -- '(^| )(-X|--request) |--data( |$)|-d ' "$FX/curl.argv" || true)"
assert_has "sentry: pinned project id" "$CURL_ARGV" "project=4511404943671376"
assert_has "sentry: a count aggregate, not rows" "$CURL_ARGV" "field=count()"
assert_has "sentry: the window starts at the flip's dispatch, without a zone suffix" "$CURL_ARGV" "start=2026-10-20T09:00:00 "
assert_has "sentry: the window ends at the exit proof's dispatch" "$CURL_ARGV" "end=2026-10-20T10:00:00 "
assert_has "sentry: the erasure query is the op tag" "$CURL_ARGV" "query=op:git-data-bare-repo-erasure"
assert_has "sentry: the pin_fault query is the tag-presence form" "$CURL_ARGV" "query=has:pin_fault"
assert_has "sentry: the liveness count carries an empty query" "$CURL_ARGV" "query= "
for _secret in "$SENTRY_SYN" "$BS_PASS_SYN" "synuser" "SECRET-ROW-BODY-DECOY"; do
  assert_eq "no leak of [$_secret] to stdout or stderr" "0" "$(printf '%s\n%s\n' "$HAPPY_OUT" "$HAPPY_ERR" | grep -cF -- "$_secret" || true)"
done
for _host in soleur-web-platform soleur-web-2 soleur-git-data soleur-inngest-prd some-other-host; do
  assert_eq "no host name [$_host] in the block" "0" "$(printf '%s\n%s\n' "$HAPPY_OUT" "$HAPPY_ERR" | grep -cF -- "$_host" || true)"
done
ARM_ENV="SENTRY_ISSUE_RO_TOKEN=$SENTRY_SYN SENTRY_HOST=evil.example.org"
sut "${BASE_ARGS[@]}"
assert_eq "sentry: an inherited SENTRY_HOST cannot redirect the bearer" "0" "$(grep -c 'evil.example.org' "$FX/curl.argv" || true)"
reset_env

# ===== ARM 3: a run id that is not the run its slot claims, one conjunct at a time ===================================
variant 2001 '.displayTitle = "git-data rollback"'
variant 2002 '.headBranch = "evil-branch"'
variant 2003 '.event = "push"'
variant 2004 '.workflowName = "totally-unrelated"'
variant 2005 '.status = "in_progress" | .conclusion = ""'
variant 2006 '.jobs = null'
for _v in 2001:title 2002:branch 2003:event 2004:workflow 2005:status 2006:jobs; do
  sut --flip "${_v%%:*}" --rollback "$ROLLBACK" --exit "$EXITRUN" --level 1
  assert_has "identity (${_v##*:}): refused, named on stderr" "$ERR" "UNREAD(run-identity-flip)"
  assert_has "identity (${_v##*:}): the flip line is UNREAD and exit is 3" "$(line_of 'flip run:')|rc=$RC" "UNREAD(flip-run)|rc=3"
done
assert_lacks "identity: nothing from the wrong run is rendered" "$OUT" "2026-10-20T09:00:00Z   conclusion"
assert_has "identity: the rollback leg is still collected" "$(line_of 'rollback run:')" "conclusion success"

# ===== ARM 4: ordering and distinctness tie the ids to ONE rehearsal ================================================
variant 2010 '.createdAt = "2026-10-20T08:30:00Z"' "$EXITRUN"
sut --flip "$FLIP" --rollback "$ROLLBACK" --exit 2010 --level 1
assert_has "order: an exit proof older than the rollback is refused" "$ERR" "UNREAD(run-order-exit)"
variant 2011 '.createdAt = "2026-10-10T09:30:00Z"' "$ROLLBACK"
sut --flip "$FLIP" --rollback 2011 --exit "$EXITRUN" --level 1
assert_has "order: a rollback from the week before the flip is refused" "$ERR" "UNREAD(run-order-rollback)"
variant 2012 '.createdAt = "2026-10-20T09:00:00Z; DROP"' "$EXITRUN"
sut --flip "$FLIP" --rollback "$ROLLBACK" --exit 2012 --level 1
assert_has "order: a malformed createdAt is UNREAD, never interpolated" "$ERR|$OUT" "UNREAD(run-created-exit)"
assert_lacks "order: the injection payload is never printed" "$OUT$ERR" "DROP"
sut --flip "$FLIP" --rollback "$ROLLBACK" --exit "$FLIP"
assert_eq "usage: one run id in two slots exits 64" "64" "$RC"
sut --flip "$FLIP" --rollback "$ROLLBACK" --exit "$EXITRUN" --level 1 --proof-before "$PB"
assert_eq "usage: a pre-deletion proof beside --level 1 exits 64" "64" "$RC"

# ===== ARM 5: a step that did not run is not a step that ran =========================================================
# 5a. skipped steps still carry a completedAt (the job's): not a flag write.
variant 2020 '.jobs[0].steps[0].conclusion = "skipped"'
sut --flip 2020 --rollback "$ROLLBACK" --exit "$EXITRUN" --level 1
assert_has "skipped flip flag_write: the window is UNREAD, not computed from the skipped step's stamp" "$(line_of 'window:')" "UNREAD(window)"
assert_eq "skipped flip flag_write: no Better Stack read is made on the strength of it" "0" "$(wc -c < "$FX/bs.argv" | tr -d ' ')"
assert_has "skipped flip flag_write: the app path is UNREAD" "$(line_of 'app path:')" "UNREAD(app-path)"
variant 2021 '.jobs[0].steps[0].conclusion = "skipped"' "$ROLLBACK"
sut --flip "$FLIP" --rollback 2021 --exit "$EXITRUN" --level 1
assert_has "skipped rollback flag-off (nothing_to_rollback): the window is UNREAD" "$(line_of 'window:')" "UNREAD(window)"
assert_eq "skipped rollback flag-off: no Better Stack read" "0" "$(wc -c < "$FX/bs.argv" | tr -d ' ')"
# 5b. gh's zero time for an unset field.
variant 2022 '.jobs[0].steps[0].completedAt = "0001-01-01T00:00:00Z"'
sut --flip 2022 --rollback "$ROLLBACK" --exit "$EXITRUN" --level 1
assert_has "zero time on the flag_write step: the window is UNREAD" "$(line_of 'window:')" "UNREAD(window)"
assert_eq "zero time: no Better Stack read over all of history" "0" "$(wc -c < "$FX/bs.argv" | tr -d ' ')"
# 5c. the writes out of order.
variant 2023 '.jobs[0].steps[0].completedAt = "2026-10-20T08:00:00Z"' "$ROLLBACK"
sut --flip "$FLIP" --rollback 2023 --exit "$EXITRUN" --level 1
assert_has "a flag-off before the flag-on: the window is UNREAD, not negative" "$(line_of 'window:')" "UNREAD(window)"
# 5d. a renamed step is drift, not "did not run".
variant 2024 '.jobs[0].steps[2].name = "Unwind (renamed)"'
sut --flip 2024 --rollback "$ROLLBACK" --exit "$EXITRUN" --level 1
assert_has "renamed Finalizer step: UNREAD, not 'finalizer ran no'" "$ERR" "UNREAD(step-flip-finalizer)"
variant 2025 '.jobs[0].steps[1].name = "Stamp (renamed)"'
sut --flip 2025 --rollback "$ROLLBACK" --exit "$EXITRUN" --level 1
assert_has "renamed stamp step: UNREAD, not 'stamp step absent'" "$ERR" "UNREAD(step-flip-stamp)"
variant 2026 '.jobs[0].steps[1].name = "Probe (renamed)"' "$ROLLBACK"
sut --flip "$FLIP" --rollback 2026 --exit "$EXITRUN" --level 1
assert_has "renamed probe step: UNREAD" "$ERR" "UNREAD(step-rb-probe)"
variant 2027 '.jobs[0].steps[2].conclusion = "skipped"'
sut --flip 2027 --rollback "$ROLLBACK" --exit "$EXITRUN" --level 1
assert_has "a Finalizer step that was skipped reads 'finalizer ran no'" "$(line_of 'flip run:')" "finalizer ran no"

# ===== ARM 6: the finalizer reading ===================================================================================
variant 2030 '.'
ll "Finalizer — total unwind on an incomplete flip" "2026-10-20T09:27:00.0000000Z" "finalizer: writing GIT_DATA_STORE_ENABLED=false" >> "$FX/log-2030.txt"
sut --flip 2030 --rollback "$ROLLBACK" --exit "$EXITRUN" --level 1
assert_has "a flag-off write that was STARTED but never completed is not 'unwound yes'" "$(line_of 'flip run:')" "finalizer ran yes (unwound STARTED-NOT-COMPLETED)"
ll "Finalizer — total unwind on an incomplete flip" "2026-10-20T09:28:00.0000000Z" "finalizer: unwind complete." >> "$FX/log-2030.txt"
sut --flip 2030 --rollback "$ROLLBACK" --exit "$EXITRUN" --level 1
assert_has "a completed unwind reads 'unwound yes'" "$(line_of 'flip run:')" "finalizer ran yes (unwound yes)"

# ===== ARM 7: the logs ================================================================================================
variant 2031 '.'; : > "$FX/log-2031.txt"
sut --flip 2031 --rollback "$ROLLBACK" --exit "$EXITRUN" --level 1
assert_has "an empty log is UNREAD, not a measured 'unwound no'" "$ERR" "UNREAD(gh-run-log-flip)"
ARM_ENV="SENTRY_ISSUE_RO_TOKEN=$SENTRY_SYN GH_FAIL_LOG_IDS=$ROLLBACK"
sut "${BASE_ARGS[@]}"
assert_has "a log-only failure is UNREAD(gh-run-log-rollback)" "$ERR" "UNREAD(gh-run-log-rollback)"
assert_has "a log-only failure does not discard the flip leg" "$(line_of 'flip run:')" "conclusion success"
reset_env
variant 2032 '.attempt = 2'
sut --flip 2032 --rollback "$ROLLBACK" --exit "$EXITRUN" --level 1
assert_has "a re-run: the log is fetched for the SAME attempt as the jobs JSON" "$(cat "$FX/gh.argv")" "run view 2032 --repo jikig-ai/soleur --attempt 2 --log"
ARM_ENV="SENTRY_ISSUE_RO_TOKEN=$SENTRY_SYN GH_FAIL_IDS=$ROLLBACK"
sut "${BASE_ARGS[@]}"
assert_eq "gh failure: exit 3" "3" "$RC"
assert_has "gh failure: the rollback line is UNREAD" "$(line_of 'rollback run:')" "UNREAD(rollback-run)"
assert_has "gh failure: the window is UNREAD, not guessed" "$(line_of 'window:')" "UNREAD(window)"
assert_has "gh failure: web-2 disabled is UNREAD" "$OUT" "web-2 git_data_store=enabled 2026-10-20T09:13:02Z / disabled UNREAD(web-2-disabled)"
reset_env

# ===== ARM 8: Better Stack =============================================================================================
for _rc in 3:bs-credentials-absent 2:bs-reader-refusal 124:bs-transport 1:bs-reader-exit-1 5:bs-other; do
  ARM_ENV="SENTRY_ISSUE_RO_TOKEN=$SENTRY_SYN BS_STUB_RC=${_rc%%:*}"
  sut "${BASE_ARGS[@]}"
  assert_has "reader rc ${_rc%%:*}: named, never a zero" "$ERR|$(line_of 'app path:' | cut -c1-40)" "UNREAD(${_rc##*:})"
done
assert_has "reader failure: the app path line is UNREAD" "$(line_of 'app path:')" "UNREAD(app-path)"
reset_env
# all-zero window is silence, not a measurement
printf '{"h":"soleur-web-platform","pin_n":0,"ssh_n":0,"store_n":0,"fps":[]}\n{"h":"soleur-web-2","pin_n":0,"ssh_n":0,"store_n":0,"fps":[]}\n' > "$FX/bs-app.jsonl"
sut "${BASE_ARGS[@]}"
assert_eq "silent window: exit 3" "3" "$RC"
assert_has "silent window: named as such" "$ERR" "UNREAD(bs-silent-window)"
# ONE silent host beside a speaking one
{ jq -cn --arg f "$FP_OK" '{h:"soleur-web-2",pin_n:1,ssh_n:1,store_n:1,fps:[$f]}'; } > "$FX/bs-app.jsonl"
sut "${BASE_ARGS[@]}"
assert_has "one silent host: UNREAD(bs-host-silent-web-1)" "$ERR" "UNREAD(bs-host-silent-web-1)"
assert_has "one silent host: the zero is printed beside it, not omitted" "$(line_of 'app path:')" "pin $FP_OK (web-1 0, web-2 1)"
# pin lines absent but the other two present: a MEASURED pin absence, not silence
{
  jq -cn '{h:"soleur-web-platform",pin_n:0,ssh_n:1,store_n:1,fps:[]}'
  jq -cn '{h:"soleur-web-2",pin_n:0,ssh_n:1,store_n:1,fps:[]}'
} > "$FX/bs-app.jsonl"
sut "${BASE_ARGS[@]}"
assert_has "pin absent, ssh and store present: 'pin none' with the counts, exit 0" "$(line_of 'app path:')|rc=$RC" "pin none (web-1 0, web-2 0), ssh_client present (web-1 1, web-2 1), store disabled (web-1 1, web-2 1)"
assert_eq "pin absent measured: exit 0" "0" "$RC"
# a host missing ssh_client / store is MISSING, not 'present'
{
  jq -cn --arg f "$FP_OK" '{h:"soleur-web-platform",pin_n:1,ssh_n:0,store_n:0,fps:[$f]}'
  jq -cn --arg f "$FP_OK" '{h:"soleur-web-2",pin_n:1,ssh_n:1,store_n:1,fps:[$f]}'
} > "$FX/bs-app.jsonl"
sut "${BASE_ARGS[@]}"
assert_has "a zero ssh count is MISSING, not 'present'" "$(line_of 'app path:')" "ssh_client MISSING (web-1 0, web-2 1), store disabled MISSING (web-1 0, web-2 1)"
# fingerprints: shape, and per-host attribution when they differ
write_app_rows "[\"$FP_OK\", \"SHA256:x\\\"; rm -rf /\", \"SHA256:aaaaaaaaaaaaaaaaaaaaaaaaa\"]"
sut "${BASE_ARGS[@]}"
assert_has "fingerprint shape: the well-formed fingerprint is printed" "$(line_of 'app path:')" "pin $FP_OK (web-1 3, web-2 1)"
assert_lacks "fingerprint shape: a malformed one is not" "$OUT" 'rm -rf'
assert_lacks "fingerprint shape: a 25-character one is not" "$OUT" 'SHA256:aaaaaaaaaaaaaaaaaaaaaaaaa'
{
  jq -cn --arg f "$FP_OK" '{h:"soleur-web-platform",pin_n:1,ssh_n:1,store_n:1,fps:[$f]}'
  jq -cn --arg f "$FP_B" '{h:"soleur-web-2",pin_n:1,ssh_n:1,store_n:1,fps:[$f]}'
} > "$FX/bs-app.jsonl"
sut "${BASE_ARGS[@]}"
assert_has "differing fingerprints are attributed per host" "$(line_of 'app path:')" "pin web-1=$FP_OK web-2=$FP_B (web-1 1, web-2 1)"
# a pin count with no parseable fingerprint
{
  jq -cn '{h:"soleur-web-platform",pin_n:1,ssh_n:1,store_n:1,fps:["SHA256:short"]}'
  jq -cn '{h:"soleur-web-2",pin_n:1,ssh_n:1,store_n:1,fps:["SHA256:short"]}'
} > "$FX/bs-app.jsonl"
sut "${BASE_ARGS[@]}"
assert_has "pin lines with no parseable fingerprint: UNREAD(bs-fp-shape)" "$ERR" "UNREAD(bs-fp-shape)"
printf 'this is not json\n' > "$FX/bs-app.jsonl"
sut "${BASE_ARGS[@]}"
assert_has "a non-JSON body: UNREAD(bs-response-shape)" "$ERR" "UNREAD(bs-response-shape)"
write_app_rows "[\"$FP_OK\"]"
printf '{"t":"1970-01-01T00:00:00Z","n":0}\n' > "$FX/bs-boot.jsonl"
sut "${BASE_ARGS[@]}"
assert_eq "no boot_complete: exit 3" "3" "$RC"
assert_has "no boot_complete: UNREAD, not the epoch" "$(line_of 'predecessor:')" "new-server boot_complete UNREAD(boot_complete)"
printf '{"t":"2026-10-20T08:05:00Z","n":1}\n' > "$FX/bs-boot.jsonl"

# ===== ARM 9: Sentry ===================================================================================================
ARM_ENV=""
sut "${BASE_ARGS[@]}"
assert_eq "sentry token absent: exit 3" "3" "$RC"
assert_has "sentry token absent: named" "$ERR" "UNREAD(sentry-token-absent)"
assert_eq "sentry token absent: curl was never invoked" "0" "$(wc -c < "$FX/curl.argv" | tr -d ' ')"
assert_has "sentry token absent: the Sentry field is UNREAD" "$(line_of 'app path:')" "Sentry events R1..R6: UNREAD(sentry)"
ARM_ENV='SENTRY_ISSUE_RO_TOKEN=bad"token'
sut "${BASE_ARGS[@]}"
assert_eq "sentry token shape: exit 3" "3" "$RC"
assert_eq "sentry token shape: no request escaped" "0" "$(wc -c < "$FX/curl.argv" | tr -d ' ')"
assert_has "sentry token shape: the library's value-free marker reaches stderr" "$ERR" "SOLEUR_CREDENTIAL_REFUSED script=git-data-rehearsal-evidence"
assert_has "sentry token shape: named" "$ERR" "UNREAD(sentry-token-refused)"
for _c in 403:sentry-auth 401:sentry-auth 500:sentry-read; do
  ARM_ENV="SENTRY_ISSUE_RO_TOKEN=$SENTRY_SYN CURL_CODE=${_c%%:*}"
  sut "${BASE_ARGS[@]}"
  assert_has "sentry HTTP ${_c%%:*}: named, exit 3" "$ERR|rc=$RC" "UNREAD(${_c##*:})|rc=3"
done
ARM_ENV="SENTRY_ISSUE_RO_TOKEN=$SENTRY_SYN SENTRY_ALL_N=0"
sut "${BASE_ARGS[@]}"
assert_has "sentry silent: a zero with no liveness behind it is UNREAD, not 'zero events'" "$ERR" "UNREAD(sentry-silent-window)"
ARM_ENV="SENTRY_ISSUE_RO_TOKEN=$SENTRY_SYN SENTRY_ERASURE_N=2 SENTRY_PINFAULT_N=1"
sut "${BASE_ARGS[@]}"
assert_has "sentry counts: summed and itemised, with the window" "$(line_of 'app path:')" "Sentry events R1..R6: 3 (erasure 2, pin_fault 1) in 2026-10-20T09:00:00..2026-10-20T10:00:00"
reset_env

# ===== ARM 10: proof verdicts and levels ==================================================================================
sut --flip "$FLIP" --rollback "$ROLLBACK" --exit "$EXITRUN" --proof-before "$PB" --refs "$REFS"
assert_eq "level 2 (inferred from --proof-before): exit 0" "0" "$RC"
assert_eq "level 2: proof before and after" "               level 2 only: proof before deletion store_not_empty, proof after deletion clear" "$(line_of 'level 2 only')"
assert_has "level 2: the level is carried" "$(line_of 'app path:')" "level 2;"
sut --flip "$FLIP" --rollback "$ROLLBACK" --exit "$EXITRUN"
assert_has "level omitted: the owner supplies it" "$(line_of 'app path:')" "level <owner: 1|2>;"
assert_eq "level omitted: the owner placeholder is not UNREAD, exit 0" "0" "$RC"
variant 2040 '.' "$EXITRUN"
{ ll "Host-side proof (access gate)" "2026-10-20T10:01:00.0000000Z" "##[notice]verdict=clear"; ll "Host-side proof (access gate)" "2026-10-20T10:01:01.0000000Z" "##[error]probe=store-empty verdict=store_not_empty"; } > "$FX/log-2040.txt"
sut --flip "$FLIP" --rollback "$ROLLBACK" --exit 2040 --level 1
assert_has "clear AND store_not_empty in one proof: conflict, UNREAD" "$ERR" "UNREAD(exit-verdict-conflict)"
variant 2041 '.conclusion = "failure"' "$EXITRUN"
sut --flip "$FLIP" --rollback "$ROLLBACK" --exit 2041 --level 1
assert_has "a clear verdict inside a red run is not a verdict" "$ERR" "UNREAD(exit-verdict-conclusion)"
variant 2042 '.' "$EXITRUN"
ll "Host-side proof (access gate)" "2026-10-20T10:01:00.0000000Z" "read-only proof started" > "$FX/log-2042.txt"
sut --flip "$FLIP" --rollback "$ROLLBACK" --exit 2042 --level 1
assert_has "no verdict line: UNREAD, not clear" "$(line_of 'exit read:')" "verdict UNREAD(exit-verdict)"
variant 2043 '.' "$EXITRUN"
ll "Host-side proof (access gate)" "2026-10-20T10:01:00.0000000Z" "::notice title=git-data-cutover store::verdict=clear" > "$FX/log-2043.txt"
sut --flip "$FLIP" --rollback "$ROLLBACK" --exit 2043 --level 1
assert_has "the raw ::notice annotation rendering is read too" "$(line_of 'exit read:')" "verdict clear"

# ===== ARM 11: the predecessor =============================================================================================
variant 2050 '.jobs[0].steps[1].conclusion = "skipped" | .jobs[0].steps[2].conclusion = "skipped"' "$ROTATE"
sut --flip "$FLIP" --rollback "$ROLLBACK" --exit "$EXITRUN" --rotate 2050 --level 1
assert_has "rotate not stamped: UNREAD, never 'plan_only false'" "$ERR|$(line_of 'predecessor:')" "UNREAD(rotate-"
assert_lacks "rotate not stamped: no plan_only claim" "$OUT" "plan_only false"
variant 2051 '.workflowName = "git-data cutover"' "$ROTATE"
sut --flip "$FLIP" --rollback "$ROLLBACK" --exit "$EXITRUN" --rotate 2051 --level 1
assert_has "rotate run from another workflow: refused" "$ERR" "UNREAD(run-identity-rotate)"
variant 2052 '.createdAt = "2026-10-20T09:15:00Z"' "$ROTATE"
sut --flip "$FLIP" --rollback "$ROLLBACK" --exit "$EXITRUN" --rotate 2052 --level 1
assert_has "rotate run created after the flip: refused" "$ERR" "UNREAD(run-order-rotate)"
ARM_ENV="SENTRY_ISSUE_RO_TOKEN=$SENTRY_SYN GH_ISSUE_STATE=BOGUS"
sut "${BASE_ARGS[@]}"
assert_has "an unreadable #10166 state is UNREAD" "$ERR" "UNREAD(issue-10166)"
reset_env
sut --flip "$FLIP" --rollback "$ROLLBACK" --exit "$EXITRUN" --level 1
assert_has "no --rotate: the owner supplies the predecessor, not UNREAD" "$(line_of 'predecessor:')" "<owner: pass --rotate <run id>>"

# ===== ARM 12: usage, tools, and the xtrace refusal ======================================================================
sut
assert_eq "usage: no arguments exits 64" "64" "$RC"
sut --flip abc --rollback "$ROLLBACK" --exit "$EXITRUN"
assert_eq "usage: a non-numeric run id exits 64" "64" "$RC"
sut --flip "1$FLIP" --rollback "$ROLLBACK" --exit "$EXITRUN" --rotate abc
assert_eq "usage: a non-numeric --rotate exits 64" "64" "$RC"
sut --flip "$FLIP" --rollback "$ROLLBACK" --exit "$EXITRUN" --level 3
assert_eq "usage: a level other than 1 or 2 exits 64" "64" "$RC"
sut --flip "$FLIP" --rollback "$ROLLBACK" --exit "$EXITRUN" --bogus x
assert_eq "usage: an unknown flag exits 64" "64" "$RC"
sut --flip "$FLIP" --rollback "$ROLLBACK" --exit
assert_eq "usage: a flag with no value exits 64" "64" "$RC"
for _t in bash gh awk timeout date mktemp; do ln -sf "$(command -v "$_t")" "$NOJQ/$_t"; done
ARM_PATH="$NOJQ"
sut "${BASE_ARGS[@]}"
assert_eq "a missing jq is a tool error (64), not a wrong-run-id UNREAD" "64" "$RC"
assert_has "a missing jq is named" "$ERR" "required tool missing: jq"
reset_env
run_sut bash -x "$MUT" "${BASE_ARGS[@]}"
assert_eq "xtrace with both credentials: refused" "78" "$RC"
assert_eq "xtrace: the refusal leaks nothing" "0" "$(printf '%s\n%s\n' "$OUT" "$ERR" | grep -cE "$SENTRY_SYN|$BS_PASS_SYN" || true)"
ARM_ENV=""
run_sut bash -x "$MUT" "${BASE_ARGS[@]}"
assert_eq "xtrace with only the Better Stack password: refused" "78" "$RC"
ARM_ENV="SENTRY_ISSUE_RO_TOKEN=$SENTRY_SYN"; BS_OFF=1
run_sut bash -x "$MUT" "${BASE_ARGS[@]}"
assert_eq "xtrace with only the Sentry token: refused" "78" "$RC"
ARM_ENV=""; BS_OFF=1
run_sut bash -x "$MUT" "${BASE_ARGS[@]}"
assert_eq "xtrace with no credential: tracing stays available (not refused)" "1" "$([[ "$RC" != 78 ]] && echo 1 || echo 0)"
reset_env

# ===== ARM 13: REFS-CONFIRMED is READ from the mode=refs_assert run (#11431), never owner-typed ==========================
L2_ARGS=(--flip "$FLIP" --rollback "$ROLLBACK" --exit "$EXITRUN" --proof-before "$PB")
sut "${L2_ARGS[@]}" --refs "$REFS"
REFS_OUT="$OUT"; REFS_ERR="$ERR"
assert_eq "refs: a green run with one confirmation and one anchored answer line reads REFS-CONFIRMED yes, counts only" \
  "refs read:     mode=refs_assert run $U/$REFS   dispatched 2026-10-20T09:35:00Z   conclusion success   step success   REFS-CONFIRMED yes (repos=1 namespaces=1 refs=2 heads=2)" \
  "$(line_of 'refs read:')"
assert_eq "refs: exit 0 at level 2 with the refs run named" "0" "$RC"
assert_eq "refs: no commit id reaches the block or stderr" "0" "$(printf '%s\n%s\n' "$REFS_OUT" "$REFS_ERR" | grep -cE "$REFS_SHA1|$REFS_SHA2" || true)"
sut "${L2_ARGS[@]}"
assert_has "refs: at level 2 a missing --refs is UNREAD(refs-run), never owner-typed" "$(line_of 'refs read:')|rc=$RC" "UNREAD(refs-run)|rc=3"
sut --flip "$FLIP" --rollback "$ROLLBACK" --exit "$EXITRUN" --refs "$REFS" --level 1
assert_has "refs: optional at level 1 and read when given" "$(line_of 'refs read:')" "REFS-CONFIRMED yes"
sut --flip "$FLIP" --rollback "$ROLLBACK" --exit "$EXITRUN"
assert_has "refs: level unknown and no --refs: the owner is told to pass it, not marked UNREAD" "$(line_of 'refs read:')|rc=$RC" "<owner: pass --refs <run id> for a Level 2 rehearsal>|rc=0"
variant 2140 '.displayTitle = "git-data proof"' "$REFS"
sut "${L2_ARGS[@]}" --refs 2140
assert_has "refs: a run with the wrong title is refused (run-identity-refs)" "$ERR" "UNREAD(run-identity-refs)"
variant 2141 '.createdAt = "2026-10-20T09:20:00Z"' "$REFS"
sut "${L2_ARGS[@]}" --refs 2141
assert_has "refs: a refs run created BEFORE the rollback is refused (run-order-refs)" "$ERR" "UNREAD(run-order-refs)"
variant 2142 '.createdAt = "2026-10-20T09:55:00Z"' "$REFS"
sut "${L2_ARGS[@]}" --refs 2142
assert_has "refs: a refs run created after the pre-deletion proof is refused (the order is rollback, refs, proofs)" "$ERR" "UNREAD(run-order-proofbefore)"
variant 2143 '.jobs[0].steps[0].conclusion = "failure"' "$REFS"
sut "${L2_ARGS[@]}" --refs 2143
assert_has "refs: a step that did not succeed is NOT CONFIRMED even with the log line present" "$(line_of 'refs read:')|rc=$RC" "REFS-CONFIRMED NOT CONFIRMED (confirmed lines 1, answer lines 1): UNREAD(refs-not-confirmed)|rc=3"
variant 2144 '.conclusion = "failure"' "$REFS"
sut "${L2_ARGS[@]}" --refs 2144
assert_has "refs: a log line inside a red run is not a verdict" "$(line_of 'refs read:')|rc=$RC" "REFS-CONFIRMED NOT CONFIRMED (confirmed lines 1, answer lines 1): UNREAD(refs-not-confirmed)|rc=3"
variant 2145 '.' "$REFS"
grep -v 'REFS-CONFIRMED$' "$FX/log-$REFS.txt" > "$FX/log-2145.txt"
sut "${L2_ARGS[@]}" --refs 2145
assert_has "refs: a green run with no REFS-CONFIRMED line in the step (the decoy and the other step's line do not count) is NOT CONFIRMED" "$(line_of 'refs read:')|rc=$RC" "REFS-CONFIRMED NOT CONFIRMED (confirmed lines 0, answer lines 1): UNREAD(refs-not-confirmed)|rc=3"
variant 2146 '.' "$REFS"
{ cat "$FX/log-$REFS.txt"; ll "$REFS_STEP_NAME" "2026-10-20T09:35:33.0000000Z" "[git-data-cutover] REFS-CONFIRMED"; } > "$FX/log-2146.txt"
sut "${L2_ARGS[@]}" --refs 2146
assert_has "refs: two REFS-CONFIRMED lines in the step are NOT CONFIRMED (exactly one)" "$(line_of 'refs read:')|rc=$RC" "REFS-CONFIRMED NOT CONFIRMED (confirmed lines 2, answer lines 1): UNREAD(refs-not-confirmed)|rc=3"
variant 2147 '.' "$REFS"
sed 's/^\(.*REFS_ASSERT ok .*\)$/\10/' "$FX/log-$REFS.txt" > "$FX/log-2147.txt"
sut "${L2_ARGS[@]}" --refs 2147
assert_has "refs: an answer line that is not the anchored shape (a 41-hex id) is NOT CONFIRMED" "$(line_of 'refs read:')|rc=$RC" "REFS-CONFIRMED NOT CONFIRMED (confirmed lines 1, answer lines 1): UNREAD(refs-not-confirmed)|rc=3"
variant 2149 '.' "$REFS"
{ cat "$FX/log-$REFS.txt"; ll "$REFS_STEP_NAME" "2026-10-20T09:35:34.0000000Z" "[git-data-cutover] REFS_ASSERT ok repos=1 namespaces=1 refs=2 heads=2 shas=${REFS_SHA1}"; } > "$FX/log-2149.txt"
sut "${L2_ARGS[@]}" --refs 2149
assert_has "refs: two anchored answer lines in the step are NOT CONFIRMED (exactly one)" "rc=$RC|$(line_of 'refs read:')" "(confirmed lines 1, answer lines 2): UNREAD(refs-not-confirmed)"
variant 2150 '.' "$REFS"
sed 's/^\(.*REFS_ASSERT ok .*shas=\)[0-9a-f]*,[0-9a-f]*$/\1'"${REFS_SHA1}"'0/' "$FX/log-$REFS.txt" > "$FX/log-2150.txt"
sut "${L2_ARGS[@]}" --refs 2150
assert_has "refs: a single 41-hex first id is NOT CONFIRMED (the id length is exact)" "rc=$RC|$(line_of 'refs read:')" "(confirmed lines 1, answer lines 1): UNREAD(refs-not-confirmed)"
variant 2148 '.jobs[0].steps[0].name = "Refs (renamed)"' "$REFS"
sut "${L2_ARGS[@]}" --refs 2148
assert_has "refs: a renamed step is UNREAD, not a plain fact" "$ERR" "UNREAD(step-refs-step)"
sut "${L2_ARGS[@]}" --refs "$FLIP"
assert_eq "refs: one run id in two slots exits 64" "64" "$RC"
ARM_ENV="$ARM_ENV GH_FAIL_IDS=$REFS"
sut "${L2_ARGS[@]}" --refs "$REFS"
assert_has "refs: a refs run that cannot be fetched is UNREAD(gh-run-view-refs)" "$ERR" "UNREAD(gh-run-view-refs)"
reset_env

# ===== the exact assertion count =======================================================================================
# Reported with printf + exit, never through fail() (ADR-193). A bare floor is satisfiable by deleting arms; an exact
# count moves only when this file is edited deliberately.
EXACT=170
if (( total != EXACT )); then
  printf 'FATAL: %d assertions ran, expected exactly %d -- coverage changed; update EXACT deliberately\n' "$total" "$EXACT" >&2
  exit 1
fi
printf '\n%d assertions, %d failed\n' "$total" "$fails"
exit $(( fails > 0 ))
