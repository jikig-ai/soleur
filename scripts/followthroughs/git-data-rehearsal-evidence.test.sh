#!/usr/bin/env bash
# Companion suite for scripts/followthroughs/git-data-rehearsal-evidence.sh (#8211, T2 build 2).
#
# Registered EXPLICITLY in scripts/test-all.sh: scripts/followthroughs/ matches no SUITE_GLOBS entry, so an
# unregistered .test.sh is an orphan that gates nothing while looking exactly like coverage.
#
# OFFLINE BY CONSTRUCTION. The collector is copied into a synthesized tree beside a STUB scripts/betterstack-query.sh,
# the real scripts/lib/{bearer-curl,betterstack-sources,git-data-rotate-stamp}.sh, and `gh` / `curl` shims first on PATH.
# No network, no Doppler, no credential: the "credentials" below are synthetic strings, and a positive control proves
# the Sentry one travelled on curl's stdin config (so "no secret in argv" cannot pass for lack of a request).
#
# WHAT THIS PINS, in the order a reviewer would ask:
#   * the section 5 block is filled from the fixtures, line by line, and a decoy (the step source that `run:` echoes at
#     the head of a log group) is NOT counted as a log line;
#   * the collector is read-only: every gh call is `run view` / `issue view`, every SQL is a SELECT, every curl is a GET;
#   * no secret, no row body, no host name and no malformed fingerprint reaches stdout or stderr;
#   * a read that did not run reads UNREAD(<token>) with exit 3, never a printed zero (a wrong run id, a gh failure,
#     Better Stack credentials not injected, an all-zero silent window, an absent or refused Sentry token).
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SUT="$HERE/git-data-rehearsal-evidence.sh"

[[ -f "$SUT" ]] || { echo "FATAL: SUT not found at $SUT" >&2; exit 1; }
[[ -x "$SUT" ]] || { echo "FATAL: SUT not executable at $SUT" >&2; exit 1; }
for _lib in bearer-curl.sh betterstack-sources.sh git-data-rotate-stamp.sh; do
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
assert_fixture_dir "$FX"
assert_fixture_dir "$TREE"
assert_fixture_dir "$BIN"
mkdir -p "$FX" "$BIN" "$TREE/scripts/followthroughs" "$TREE/scripts/lib"

# --- the synthesized tree ---------------------------------------------------------------------------------------------
cp "$SUT" "$TREE/scripts/followthroughs/git-data-rehearsal-evidence.sh"
chmod +x "$TREE/scripts/followthroughs/git-data-rehearsal-evidence.sh"
for _lib in bearer-curl.sh betterstack-sources.sh git-data-rotate-stamp.sh; do
  cp "$ROOT/scripts/lib/$_lib" "$TREE/scripts/lib/$_lib"
done
MUT="$TREE/scripts/followthroughs/git-data-rehearsal-evidence.sh"

# Synthetic credentials. They are recognisable so a leak is unambiguous, and shaped to pass the real token guards.
SENTRY_SYN="synsentrytoken0123456789abcdef"
BS_PASS_SYN="synbspassword0123456789abcdef"

cat > "$TREE/scripts/betterstack-query.sh" <<'STUB'
#!/usr/bin/env bash
# Stub reader: records its argv, its pinned table and the SQL; answers from $FX by query shape.
printf '%s\n' "$*" >> "$FX/bs.argv"
printf '%s\n' "${BS_TABLE:-unset}" >> "$FX/bs.table"
printf '%s\n----\n' "$1" >> "$FX/bs.sql"
[[ -n "${BS_STUB_RC:-}" ]] && exit "$BS_STUB_RC"
case "$1" in
  *"AS pin_n"*) cat "$FX/bs-app.jsonl" ;;
  *boot_complete*) cat "$FX/bs-boot.jsonl" ;;
  *) exit 99 ;;
esac
STUB
chmod +x "$TREE/scripts/betterstack-query.sh"

cat > "$BIN/gh" <<'GH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FX/gh.argv"
case "$1 $2" in
  "run view")
    id="$3"
    for f in ${GH_FAIL_IDS:-}; do [[ "$f" == "$id" ]] && exit 1; done
    if [[ " $* " == *" --log "* ]]; then cat "$FX/log-$id.txt" || exit 1; else cat "$FX/run-$id.json" || exit 1; fi ;;
  "issue view") printf '%s\n' "${GH_ISSUE_STATE:-CLOSED}" ;;
  *) exit 99 ;;
esac
GH
chmod +x "$BIN/gh"

cat > "$BIN/curl" <<'CURL'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FX/curl.argv"
cat >> "$FX/curl.stdin"
out=""; q=""; args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  case "${args[i]}" in
    -o) out="${args[i+1]}" ;;
    --data-urlencode) v="${args[i+1]}"; case "$v" in query=*) q="${v#query=}" ;; esac ;;
  esac
done
case "$q" in
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
WFNAME='git-data cutover (#5274 / ADR-220 / ADR-239)'

# write_run <id> <title> <createdAt> <jobs-json>
write_run() {
  jq -n --argjson id "$1" --arg t "$2" --arg c "$3" --arg w "$WFNAME" --argjson jobs "$4" \
    '{databaseId: $id, workflowName: $w, displayTitle: $t, headBranch: "main", event: "workflow_dispatch",
      status: "completed", conclusion: "success", createdAt: $c, updatedAt: $c, jobs: $jobs}' > "$FX/run-$1.json"
}
FLIP_JOBS='[{"name":"cutover","steps":[
  {"name":"Write GIT_DATA_STORE_ENABLED (via the #8573 seam)","conclusion":"success","completedAt":"2026-10-20T09:10:00Z"},
  {"name":"Write GIT_DATA_LUKS_CUTOVER_AT (last — proven cutover only)","conclusion":"success","completedAt":"2026-10-20T09:25:00Z"},
  {"name":"Finalizer — total unwind on an incomplete flip","conclusion":"success","completedAt":"2026-10-20T09:26:00Z"}]}]'
RB_JOBS='[{"name":"cutover","steps":[
  {"name":"Write GIT_DATA_STORE_ENABLED (via the #8573 seam)","conclusion":"success","completedAt":"2026-10-20T09:40:30Z"},
  {"name":"Positive replication probe","conclusion":"success","completedAt":"2026-10-20T09:45:00Z"},
  {"name":"Finalizer — total unwind on an incomplete flip","conclusion":"success","completedAt":"2026-10-20T09:46:00Z"}]}]'
write_run "$FLIP" "git-data flip" "2026-10-20T09:00:00Z" "$FLIP_JOBS"
write_run "$ROLLBACK" "git-data rollback" "2026-10-20T09:30:00Z" "$RB_JOBS"
write_run "$EXITRUN" "git-data proof" "2026-10-20T10:00:00Z" '[]'
write_run "$PB" "git-data proof" "2026-10-20T09:50:00Z" '[]'

# A log line is `<job>\t<step>\t<timestamp> <message>`. The DECOY lines are the step source `run:` echoes at the head of a
# group: the same words, but after `echo "`, so they must never count.
# shellcheck disable=SC2016  # the decoy lines are literal step source: nothing may expand
ll() { printf 'cutover\t%s\t%s %s\n' "$1" "$2" "$3"; }
# shellcheck disable=SC2016  # literal step source again
{
  ll "Per-host git_data_store= assertion" "2026-10-20T09:11:00.0000000Z" '      echo "host $leg: git_data_store=${EXPECTED} observed (attempt $i)"'
  ll "Per-host git_data_store= assertion" "2026-10-20T09:12:01.1234567Z" "host web-1: git_data_store=enabled observed (attempt 1)"
  ll "Per-host git_data_store= assertion" "2026-10-20T09:13:02.7654321Z" "host web-2: git_data_store=enabled observed (attempt 2)"
  ll "Finalizer — total unwind on an incomplete flip" "2026-10-20T09:26:00.0000000Z" '          echo "finalizer: unwind complete."'
  ll "Finalizer — total unwind on an incomplete flip" "2026-10-20T09:26:01.0000000Z" "finalizer: flip concluded — nothing to unwind."
} > "$FX/log-$FLIP.txt"
# shellcheck disable=SC2016  # literal step source again
{
  ll "Per-host git_data_store= assertion" "2026-10-20T09:41:11.0000000Z" "host web-1: git_data_store=disabled observed (attempt 1)"
  ll "Per-host git_data_store= assertion" "2026-10-20T09:42:22.0000000Z" "host web-2: git_data_store=disabled observed (attempt 1)"
  ll "Positive replication probe" "2026-10-20T09:44:00.0000000Z" '        log "STORE probe=probe verdict=ok"'
  ll "Positive replication probe" "2026-10-20T09:44:30.0000000Z" "[git-data-cutover] STORE probe=probe verdict=ok"
} > "$FX/log-$ROLLBACK.txt"
# shellcheck disable=SC2016  # literal step source again
{
  ll "Host-side proof" "2026-10-20T10:01:00.0000000Z" '      echo "::notice title=git-data-cutover store::verdict=clear"'
  ll "Host-side proof" "2026-10-20T10:01:30.0000000Z" "##[notice]verdict=clear"
} > "$FX/log-$EXITRUN.txt"
{
  ll "Host-side proof" "2026-10-20T09:51:00.0000000Z" "##[error]probe=store-empty verdict=store_not_empty"
} > "$FX/log-$PB.txt"

FP_OK="SHA256:abcdefghijklmnopqrstuvwxyz0123456789ABCDEFG"
write_app_rows() { # <extra fps json array for web-1>
  {
    jq -cn --argjson f "$1" '{h:"soleur-web-platform",pin_n:2,ssh_n:2,store_n:2,fps:$f,raw:"SECRET-ROW-BODY-DECOY"}'
    jq -cn --arg f "$FP_OK" '{h:"soleur-web-2",pin_n:1,ssh_n:1,store_n:1,fps:[$f]}'
    jq -cn '{h:"some-other-host",pin_n:9,ssh_n:9,store_n:9,fps:["SHA256:zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz"]}'
  } > "$FX/bs-app.jsonl"
}
write_app_rows "[\"$FP_OK\"]"
printf '{"t":"2026-10-20T08:05:00Z","n":1}\n' > "$FX/bs-boot.jsonl"
# The rotate run: a git_data_host_replace job whose apply step and last-step marker both succeeded.
write_run "$ROTATE" "git-data-host-rotate" "2026-10-20T08:00:00Z" \
  '[{"name":"git_data_host_replace","conclusion":"success","steps":[
     {"name":"Rotate precondition — served store measured empty","conclusion":"success"},
     {"name":"Terraform apply (git-data-host -replace) — post-apply backstop","conclusion":"success"},
     {"name":"Rotate completed (d6 marker)","conclusion":"success"}]}]'

# --- the runner -------------------------------------------------------------------------------------------------------
RC=0; OUT=""; ERR=""
run_sut() { # args...  (environment of the arm is set by the caller via `env`-style prefix variables below)
  : > "$FX/bs.argv"; : > "$FX/bs.table"; : > "$FX/bs.sql"; : > "$FX/gh.argv"; : > "$FX/curl.argv"; : > "$FX/curl.stdin"
  # shellcheck disable=SC2086  # ARM_ENV is a deliberate word list of NAME=value assignments
  OUT="$(env -i PATH="$BIN:$PATH" HOME="$WORK" TMPDIR="$WORK" FX="$FX" \
      BETTERSTACK_QUERY_HOST="syn.betterstackdata.com" BETTERSTACK_QUERY_USERNAME="synuser" BETTERSTACK_QUERY_PASSWORD="$BS_PASS_SYN" \
      ${ARM_ENV:-} "$@" 2>"$FX/stderr.txt")"
  RC=$?
  ERR="$(cat "$FX/stderr.txt")"
}
BASE_ARGS=(--flip "$FLIP" --rollback "$ROLLBACK" --exit "$EXITRUN" --rotate "$ROTATE" --level 1)
sut() { run_sut bash "$MUT" "$@"; }
ARM_ENV="SENTRY_ISSUE_RO_TOKEN=$SENTRY_SYN"

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
assert_eq "happy: per-host timestamps come from the readback log lines, truncated to seconds" \
  "per-host:      web-1 git_data_store=enabled 2026-10-20T09:12:01Z / disabled 2026-10-20T09:41:11Z;  web-2 git_data_store=enabled 2026-10-20T09:13:02Z / disabled 2026-10-20T09:42:22Z" \
  "$(line_of 'per-host:')"
assert_eq "happy: app path line, other hosts excluded, counts summed per label, Sentry zero measured" \
  "app path:      level 1; startup lines after rollback flag-off: pin $FP_OK (web-1 2, web-2 1), ssh_client present (web-1 2, web-2 1), store disabled (web-1 2, web-2 1); Sentry events R1..R6: 0 (erasure 0, pin_fault 0)" \
  "$(line_of 'app path:')"
assert_eq "happy: level 1 leaves the level 2 line n/a" "               level 2 only: n/a (level 1)" "$(line_of 'level 2 only')"
assert_eq "happy: exit read" "exit read:     mode=proof run $U/$EXITRUN verdict clear" "$(line_of 'exit read:')"
assert_eq "happy: predecessor line (plan_only false from a stamped d6 verdict, boot_complete from the git-data table)" \
  "predecessor:   rotate run $ROTATE, apply step success, plan_only false, new-server boot_complete 2026-10-20T08:05:00Z; #10166 CLOSED" \
  "$(line_of 'predecessor:')"
assert_has "happy: owner-supplied fields are marked, not invented" "$OUT" "queue check:   <owner:"
assert_has "happy: the not-covered line is carried" "$OUT" "not covered:   real-user replication load"
assert_eq "happy: no UNREAD anywhere" "0" "$(printf '%s\n%s\n' "$OUT" "$ERR" | grep -c 'UNREAD' || true)"

# ===== ARM 2: read-only, confidential, argv-clean =====================================================================
GH_VERBS="$(cut -d' ' -f1,2 "$FX/gh.argv" | sort -u | paste -sd, -)"
assert_eq "readonly: gh is only ever asked to view a run or an issue" "issue view,run view" "$GH_VERBS"
sut "${BASE_ARGS[@]}"
SQL_ALL="$(cat "$FX/bs.sql")"
assert_eq "readonly: every Better Stack call is a SELECT" "2" "$(grep -c '^SELECT' "$FX/bs.sql" || true)"
assert_eq "readonly: no write keyword in any SQL" "0" "$(printf '%s' "$SQL_ALL" | grep -ciE '\b(INSERT|ALTER|DROP|TRUNCATE|CREATE|UPDATE|DELETE|OPTIMIZE|GRANT)\b' || true)"
assert_eq "pinned: the web-app lines are read from the shared control table, then the git-data table for boot_complete" \
  "t520508_soleur_inngest_vector_prd_3_logs,t520508_soleur_git_data_prd_logs" "$(paste -sd, "$FX/bs.table")"
# shellcheck disable=SC2016  # the literal $BS_TABLE_S3 token is what the reader substitutes
assert_has "pinned: the archive arm is part of the app-path read" "$SQL_ALL" 's3Cluster(primary, $BS_TABLE_S3)'
assert_eq "argv: the reader's argv is only the SQL (no credential)" "0" "$(grep -c "$BS_PASS_SYN" "$FX/bs.argv" || true)"
assert_eq "argv: no Sentry bearer on curl's argument list" "0" "$(grep -c "$SENTRY_SYN" "$FX/curl.argv" || true)"
assert_has "argv positive control: the bearer DID travel on curl's stdin config" "$(cat "$FX/curl.stdin")" "Authorization: Bearer $SENTRY_SYN"
assert_eq "readonly: both Sentry requests are GETs of the pinned org events endpoint" "2" \
  "$(grep -c 'https://jikigai-eu.sentry.io/api/0/organizations/jikigai-eu/events/' "$FX/curl.argv" || true)"
assert_eq "readonly: no curl request carries a body-write method" "0" "$(grep -cE -- '(^| )(-X|--request) |--data( |$)|-d ' "$FX/curl.argv" || true)"
assert_has "sentry: the window starts at the flip's dispatch, without a zone suffix" "$(cat "$FX/curl.argv")" "start=2026-10-20T09:00:00 "
assert_has "sentry: the pin_fault query is the tag-presence form" "$(cat "$FX/curl.argv")" "query=has:pin_fault"
for _secret in "$SENTRY_SYN" "$BS_PASS_SYN" "synuser" "SECRET-ROW-BODY-DECOY"; do
  assert_eq "no leak of [$_secret] to stdout or stderr" "0" "$(printf '%s\n%s\n' "$HAPPY_OUT" "$HAPPY_ERR" | grep -cF -- "$_secret" || true)"
done
for _host in soleur-web-platform soleur-web-2 soleur-git-data soleur-inngest-prd some-other-host; do
  assert_eq "no host name [$_host] in the block" "0" "$(printf '%s\n%s\n' "$HAPPY_OUT" "$HAPPY_ERR" | grep -cF -- "$_host" || true)"
done

# ===== ARM 3: a read that did not run is UNREAD, never a zero =========================================================
# 3a. a run id that is not the run its slot claims: refused, and nothing from that run is rendered.
write_run 2001 "git-data rollback" "2026-10-20T09:00:00Z" "$FLIP_JOBS"
sut --flip 2001 --rollback "$ROLLBACK" --exit "$EXITRUN" --level 1
assert_eq "identity: a rollback run in the flip slot exits 3" "3" "$RC"
assert_has "identity: the flip line reads UNREAD(flip-run)" "$(line_of 'flip run:')" "UNREAD(flip-run)"
assert_has "identity: the refusal is named on stderr" "$ERR" "UNREAD(run-identity-flip)"
assert_lacks "identity: nothing from the wrong run is rendered" "$OUT" "2026-10-20T09:00:00Z   conclusion"
assert_has "identity: the rollback leg is still collected" "$(line_of 'rollback run:')" "conclusion success"

# 3b. gh fails for one run.
ARM_ENV="SENTRY_ISSUE_RO_TOKEN=$SENTRY_SYN GH_FAIL_IDS=$ROLLBACK"
sut "${BASE_ARGS[@]}"
assert_eq "gh failure: exit 3" "3" "$RC"
assert_has "gh failure: the rollback line is UNREAD" "$(line_of 'rollback run:')" "UNREAD(rollback-run)"
assert_has "gh failure: the window is UNREAD, not guessed" "$(line_of 'window:')" "UNREAD(window)"
assert_has "gh failure: web-2 disabled is UNREAD" "$OUT" "web-2 git_data_store=enabled 2026-10-20T09:13:02Z / disabled UNREAD(web-2-disabled)"
ARM_ENV="SENTRY_ISSUE_RO_TOKEN=$SENTRY_SYN"

# 3c. Better Stack credentials not injected (the reader's exit 3).
ARM_ENV="SENTRY_ISSUE_RO_TOKEN=$SENTRY_SYN BS_STUB_RC=3"
sut "${BASE_ARGS[@]}"
assert_eq "bs creds: exit 3" "3" "$RC"
assert_has "bs creds: the token names the cause" "$ERR" "UNREAD(bs-credentials-not-injected)"
assert_has "bs creds: the app path line is UNREAD" "$(line_of 'app path:')" "UNREAD(app-path)"
assert_lacks "bs creds: no zero count is printed for a read that did not run" "$OUT" "startup lines"
ARM_ENV="SENTRY_ISSUE_RO_TOKEN=$SENTRY_SYN"

# 3d. an all-zero window is silence, not a measurement.
printf '{"h":"soleur-web-platform","pin_n":0,"ssh_n":0,"store_n":0,"fps":[]}\n{"h":"soleur-web-2","pin_n":0,"ssh_n":0,"store_n":0,"fps":[]}\n' > "$FX/bs-app.jsonl"
sut "${BASE_ARGS[@]}"
assert_eq "silent window: exit 3" "3" "$RC"
assert_has "silent window: named as such" "$ERR" "UNREAD(bs-silent-window)"
write_app_rows "[\"$FP_OK\"]"

# 3e. a malformed fingerprint is dropped, not printed.
write_app_rows "[\"$FP_OK\", \"SHA256:x\\\"; rm -rf /\"]"
sut "${BASE_ARGS[@]}"
assert_has "fingerprint shape: the well-formed fingerprint is printed" "$(line_of 'app path:')" "pin $FP_OK (web-1 2, web-2 1)"
assert_lacks "fingerprint shape: the malformed one is not" "$OUT" 'rm -rf'
write_app_rows "[\"$FP_OK\"]"

# 3f. Sentry token absent: no request is made, and the counts are UNREAD.
ARM_ENV=""
sut "${BASE_ARGS[@]}"
assert_eq "sentry token absent: exit 3" "3" "$RC"
assert_has "sentry token absent: named" "$ERR" "UNREAD(sentry-token-absent)"
assert_eq "sentry token absent: curl was never invoked" "0" "$(wc -c < "$FX/curl.argv" | tr -d ' ')"
assert_has "sentry token absent: the Sentry field is UNREAD" "$(line_of 'app path:')" "Sentry events R1..R6: UNREAD(sentry)"
ARM_ENV="SENTRY_ISSUE_RO_TOKEN=$SENTRY_SYN"

# 3g. a malformed token is refused by the shared library before any request, with the library's marker.
ARM_ENV='SENTRY_ISSUE_RO_TOKEN=bad"token'
sut "${BASE_ARGS[@]}"
assert_eq "sentry token shape: exit 3" "3" "$RC"
assert_eq "sentry token shape: no request escaped" "0" "$(wc -c < "$FX/curl.argv" | tr -d ' ')"
assert_has "sentry token shape: the library's value-free marker reaches stderr" "$ERR" "SOLEUR_CREDENTIAL_REFUSED script=git-data-rehearsal-evidence"
ARM_ENV="SENTRY_ISSUE_RO_TOKEN=$SENTRY_SYN"

# 3h. Sentry answers 403.
ARM_ENV="SENTRY_ISSUE_RO_TOKEN=$SENTRY_SYN CURL_CODE=403"
sut "${BASE_ARGS[@]}"
assert_eq "sentry 403: exit 3" "3" "$RC"
assert_has "sentry 403: named" "$ERR" "UNREAD(sentry-read)"
ARM_ENV="SENTRY_ISSUE_RO_TOKEN=$SENTRY_SYN"

# 3i. a flip with no flag_write step (a resume arm): the window is UNREAD.
write_run 2002 "git-data flip" "2026-10-20T09:00:00Z" '[{"name":"cutover","steps":[{"name":"Write GIT_DATA_LUKS_CUTOVER_AT (last — proven cutover only)","conclusion":"success"}]}]'
cp "$FX/log-$FLIP.txt" "$FX/log-2002.txt"
sut --flip 2002 --rollback "$ROLLBACK" --exit "$EXITRUN" --level 1
assert_has "no flag_write: the window is UNREAD" "$(line_of 'window:')" "UNREAD(window)"
assert_has "no flag_write: the flip line itself is still read" "$(line_of 'flip run:')" "stamp step success"

# ===== ARM 4: values that change with the run ==========================================================================
sut "${BASE_ARGS[@]}"
ARM_ENV="SENTRY_ISSUE_RO_TOKEN=$SENTRY_SYN SENTRY_ERASURE_N=2 SENTRY_PINFAULT_N=1"
sut "${BASE_ARGS[@]}"
assert_has "sentry counts: summed and itemised" "$(line_of 'app path:')" "Sentry events R1..R6: 3 (erasure 2, pin_fault 1)"
ARM_ENV="SENTRY_ISSUE_RO_TOKEN=$SENTRY_SYN"

# a flip whose finalizer really unwound.
cp "$FX/log-$FLIP.txt" "$FX/log-2003.txt"
ll "Finalizer — total unwind on an incomplete flip" "2026-10-20T09:27:00.0000000Z" "finalizer: unwind complete." >> "$FX/log-2003.txt"
write_run 2003 "git-data flip" "2026-10-20T09:00:00Z" "$FLIP_JOBS"
sut --flip 2003 --rollback "$ROLLBACK" --exit "$EXITRUN" --level 1
assert_has "finalizer: a real unwind line reads unwound yes" "$(line_of 'flip run:')" "finalizer ran yes (unwound yes)"

# level 2: the pre-deletion proof is store_not_empty, the exit read is clear.
sut --flip "$FLIP" --rollback "$ROLLBACK" --exit "$EXITRUN" --proof-before "$PB" --level 2
assert_eq "level 2: exit 0" "0" "$RC"
assert_eq "level 2: proof before and after" "               level 2 only: proof before deletion store_not_empty, proof after deletion clear" "$(line_of 'level 2 only')"
assert_has "level 2: the level is carried" "$(line_of 'app path:')" "level 2;"
sut --flip "$FLIP" --rollback "$ROLLBACK" --exit "$EXITRUN"
assert_has "level omitted: the owner supplies it" "$(line_of 'app path:')" "level <owner: 1|2>;"

# a proof run whose log carries no verdict is UNREAD, not "clear".
write_run 2004 "git-data proof" "2026-10-20T10:00:00Z" '[]'
ll "Host-side proof" "2026-10-20T10:01:00.0000000Z" "read-only proof started" > "$FX/log-2004.txt"
sut --flip "$FLIP" --rollback "$ROLLBACK" --exit 2004 --level 1
assert_eq "no verdict line: exit 3" "3" "$RC"
assert_has "no verdict line: UNREAD, not clear" "$(line_of 'exit read:')" "verdict UNREAD(exit-verdict)"

# a rotate run that is not stamped never claims plan_only false.
write_run 2005 "git-data-host-rotate" "2026-10-20T08:00:00Z" '[{"name":"git_data_host_replace","conclusion":"success","steps":[{"name":"Terraform apply (git-data-host -replace) — post-apply backstop","conclusion":"skipped"}]}]'
sut --flip "$FLIP" --rollback "$ROLLBACK" --exit "$EXITRUN" --rotate 2005 --level 1
assert_has "rotate not stamped: plan_only is not asserted false" "$(line_of 'predecessor:')" "plan_only not established (verdict skip)"

# no boot_complete after the rotate: UNREAD.
printf '{"t":"1970-01-01T00:00:00Z","n":0}\n' > "$FX/bs-boot.jsonl"
sut "${BASE_ARGS[@]}"
assert_eq "no boot_complete: exit 3" "3" "$RC"
assert_has "no boot_complete: UNREAD, not the epoch" "$(line_of 'predecessor:')" "new-server boot_complete UNREAD(boot_complete)"
printf '{"t":"2026-10-20T08:05:00Z","n":1}\n' > "$FX/bs-boot.jsonl"

# ===== ARM 5: usage and the xtrace refusal =============================================================================
sut
assert_eq "usage: no arguments exits 64" "64" "$RC"
sut --flip abc --rollback "$ROLLBACK" --exit "$EXITRUN"
assert_eq "usage: a non-numeric run id exits 64" "64" "$RC"
sut --flip "$FLIP" --rollback "$ROLLBACK" --exit "$EXITRUN" --level 3
assert_eq "usage: a level other than 1 or 2 exits 64" "64" "$RC"
sut --flip "$FLIP" --rollback "$ROLLBACK" --exit "$EXITRUN" --bogus x
assert_eq "usage: an unknown flag exits 64" "64" "$RC"
sut --flip "$FLIP" --rollback "$ROLLBACK" --exit
assert_eq "usage: a flag with no value exits 64" "64" "$RC"
run_sut bash -x "$MUT" "${BASE_ARGS[@]}"
assert_eq "xtrace: refused with a live credential" "78" "$RC"
assert_eq "xtrace: the refusal leaks nothing" "0" "$(printf '%s\n%s\n' "$OUT" "$ERR" | grep -cE "$SENTRY_SYN|$BS_PASS_SYN" || true)"

# ===== the exact assertion count =======================================================================================
# Reported with printf + exit, never through fail() (ADR-193). A bare floor is satisfiable by deleting arms; an exact
# count moves only when this file is edited deliberately.
EXACT=80
if (( total != EXACT )); then
  printf 'FATAL: %d assertions ran, expected exactly %d -- coverage changed; update EXACT deliberately\n' "$total" "$EXACT" >&2
  exit 1
fi
printf '\n%d assertions, %d failed\n' "$total" "$fails"
exit $(( fails > 0 ))
