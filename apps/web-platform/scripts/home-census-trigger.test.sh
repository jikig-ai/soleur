#!/usr/bin/env bash
# Tests for home-census-trigger.sh (Ref #10455). Every external command (curl, gh, git, doppler) is a PATH fake that
# accepts EXACTLY the argv the script may legitimately issue and refuses everything else with rc 64 plus an
# UNMODELLED line in the call log, which every case asserts is absent. No network, no secret, no real HOME.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/home-census-trigger.sh"
TMP="$(mktemp -d -t home-census-trigger-test.XXXXXXXX)"
trap 'rm -rf "$TMP"' EXIT
BIN="$TMP/bin"; FIX="$TMP/fix"; REPO="$TMP/repo"
mkdir -p "$BIN" "$FIX" "$REPO/knowledge-base/legal/audits"

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL: %s\n' "$1"; }
check() { # name, condition-as-rc
  if [[ "$2" -eq 0 ]]; then ok; else bad "$1"; fi
}

# Instrument self-test: both counters must move before any case runs (ADR-193), reported without the helper it backstops.
_p=$PASS; _f=$FAIL; ok; bad "instrument self-test" >/dev/null; FAIL_MOVED=$((FAIL - _f)); FAIL=$_f
if [[ "$PASS" -le "$_p" || "$FAIL_MOVED" -lt 1 ]]; then printf 'instrument: a counter did not move\n'; exit 1; fi

SENTINEL="sentinel-token-ABCDEF0123456789"
SHA="$(printf 'a%.0s' {1..40})"
OLD="$(printf 'b%.0s' {1..40})"

# ---- the fakes ----------------------------------------------------------------------------------------------------
cat >"$BIN/doppler" <<'EOF'
#!/usr/bin/env bash
echo "doppler $*" >>"$FIX/calls.log"
[[ "$*" == "secrets get INNGEST_MANUAL_TRIGGER_SECRET -p soleur -c prd --plain" ]] || { echo "UNMODELLED doppler $*" >>"$FIX/calls.log"; exit 64; }
[[ -f "$FIX/doppler.fail" ]] && exit 1
cat "$FIX/token"
EOF
cat >"$BIN/gh" <<'EOF'
#!/usr/bin/env bash
echo "gh $*" >>"$FIX/calls.log"
case "$*" in
  "api repos/jikig-ai/soleur/issues/10455/comments --paginate") cat "$FIX/comments.json" ;;
  "issue comment 10455 -R jikig-ai/soleur --body "*)
    [[ -f "$FIX/gh.fail" ]] && exit 1
    all="$*"; printf '%s\n' "${all#*--body }" >>"$FIX/posted.log" ;;
  *) echo "UNMODELLED gh $*" >>"$FIX/calls.log"; exit 64 ;;
esac
EOF
cat >"$BIN/git" <<'EOF'
#!/usr/bin/env bash
echo "git $*" >>"$FIX/calls.log"
case "$*" in
  "rev-parse --show-toplevel") echo "$REPO_FAKE" ;;
  "fetch --no-tags origin refs/pull/"*"/head") : ;;
  "fetch --no-tags origin main") : ;;
  "rev-parse FETCH_HEAD") cat "$FIX/pr_head" ;;
  "cat-file -e "*) : ;;
  "diff --quiet --no-ext-diff "*) [[ -f "$FIX/paths.differ" ]] && exit 1; : ;;
  *) echo "UNMODELLED git $*" >>"$FIX/calls.log"; exit 64 ;;
esac
EOF
cat >"$BIN/curl" <<'EOF'
#!/usr/bin/env bash
# Records argv and stdin; answers /health and the POST from fixtures. Anything else is unmodelled.
echo "curl $*" >>"$FIX/calls.log"
args=("$@"); out=""; url=""; body=""; cfg=0
for ((i = 0; i < ${#args[@]}; i++)); do
  case "${args[$i]}" in
    -o) out="${args[$((i + 1))]}" ;;
    -d) body="${args[$((i + 1))]}" ;;
    --config) cfg=1 ;;
    https://*) url="${args[$i]}" ;;
  esac
done
case "$url" in
  https://app.soleur.ai/health)
    [[ "${args[*]}" == "--disable --noproxy * --proto =https --max-redirs 0 --max-time 20 -sS https://app.soleur.ai/health" ]] || { echo "UNMODELLED curl $*" >>"$FIX/calls.log"; exit 64; }
    cat "$FIX/health.${HEALTH_CALL_SUFFIX:-json}" 2>/dev/null || cat "$FIX/health.json" ;;
  https://app.soleur.ai/api/internal/home-census)
    [[ "$cfg" == 1 ]] || { echo "UNMODELLED curl (no --config -) $*" >>"$FIX/calls.log"; exit 64; }
    cat >"$FIX/curl.stdin"
    echo "BODY $body" >>"$FIX/calls.log"
    mode="$(jq -r .mode <<<"$body")"
    [[ "$mode" == "real" && -f "$FIX/curl.rc" ]] && exit "$(cat "$FIX/curl.rc")"
    if [[ "$mode" == "dry_run" ]]; then cp "$FIX/dry.json" "$out"; printf '%s' "$(cat "$FIX/dry.code")"
    else echo "REALPOST" >>"$FIX/calls.log"; cp "$FIX/real.json" "$out"; printf '%s' "$(cat "$FIX/real.code")"; fi ;;
  *) echo "UNMODELLED curl $*" >>"$FIX/calls.log"; exit 64 ;;
esac
EOF
chmod +x "$BIN"/*

# ---- fixtures ------------------------------------------------------------------------------------------------------
class_json() {
  jq -nc '[ "history_jsonl","debug","todos","tasks","history_dir","projects","sessions_json","sessions_key","shell_snapshots","account_state","backups","last_cleanup","statsig","file_history","other_under_claude" ]
    | map({class: ., n_entries: "0", n_mode_bits_group_r: "0", n_mode_bits_other_r: "0", n_symlink: "0", errors: "0", absent: true, class_result: "none_counted"})'
}
result_json() { # evidence uptime_bucket
  jq -nc --arg sha "$SHA" --arg ev "$1" --arg ub "$2" --argjson cls "$(class_json)" '{
    schema_version: 1, ok: true, run_id: 1, mode: "real", data_source: "container_home", build_sha: $sha, control: "passed",
    evidence: $ev, uptime_bucket: $ub, sunset_utc: "2026-11-30T00:00:00Z", truncated: false, truncation_reason: "none",
    snapshot: "non_atomic", mode_bits_semantics: "file_mode_only_not_reachability", interpretation: "x",
    claude_config_dir_set: false, outer_wrap_cohorts: "unmeasured", roots: [], roots_distinct: true, roots_note: "none",
    activity_witness: false, trigger_class_nonzero: "false", classes: $cls }'
}
comment() { jq -nc --argjson id "$1" --arg a "$2" --arg b "$3" '{user: {id: $id}, author_association: $a, body: $b}'; }

reset_fix() {
  rm -rf "$FIX"; mkdir -p "$FIX"
  printf '%s' "$SENTINEL" >"$FIX/token"
  jq -nc --arg s "$SHA" '{status: "ok", build_sha: $s}' >"$FIX/health.json"
  result_json mature lt_7d >"$FIX/dry.json"; printf 200 >"$FIX/dry.code"
  result_json mature lt_7d >"$FIX/real.json"; printf 200 >"$FIX/real.code"
  echo "$SHA" >"$FIX/pr_head"
  printf '[%s]\n' "$(comment 54279 MEMBER "home-census C8 DISCHARGED sha=$SHA pr=77")" >"$FIX/comments.json"
  printf 'DISCHARGED sha=%s\n' "$SHA" >"$REPO/knowledge-base/legal/audits/2026-10-31-clo-ruling-10455-census-method.md"
  : >"$FIX/calls.log"
}
set_comments() { printf '[%s]\n' "$(IFS=,; echo "$*")" >"$FIX/comments.json"; }

run() { # args...; sets RC, OUT
  OUT="$(cd "$REPO" && env -i PATH="$BIN:/usr/bin:/bin" HOME="$TMP" FIX="$FIX" REPO_FAKE="$REPO" timeout 30s bash "$SCRIPT" "$@" 2>&1)"; RC=$?
}
calls() { cat "$FIX/calls.log" 2>/dev/null; }
no_unmodelled() { ! calls | grep -q UNMODELLED; }
REAL_ARGS=(--mode real --run-id 1 --discharged-sha "$SHA" --pr 77)

# ---- self-check and static refusals -------------------------------------------------------------------------------
reset_fix
start=$(date +%s%N)
OUT="$(env -i PATH="$BIN:/usr/bin:/bin" FIX="$FIX" timeout 15s bash "$SCRIPT" --self-check 2>&1)"; RC=$?
elapsed=$(( ($(date +%s%N) - start) / 1000000 ))
check "self-check prints the OK token" "$([[ "$OUT" == "HOME_CENSUS_TRIGGER_SELF_CHECK_OK" && $RC -eq 0 ]]; echo $?)"
check "self-check runs in under 1 s" "$([[ $elapsed -lt 1000 ]]; echo $?)"
check "self-check makes no network, doppler, curl, gh or git call" "$([[ ! -s "$FIX/calls.log" ]]; echo $?)"

reset_fix
OUT="$(cd "$REPO" && env -i PATH="$BIN:/usr/bin:/bin" FIX="$FIX" bash -x "$SCRIPT" --mode dry_run --run-id 1 2>/dev/null)"; RC=$?
check "xtrace refusal exits 78" "$([[ $RC -eq 78 ]]; echo $?)"
check "xtrace refusal reads no secret and makes no call" "$([[ ! -s "$FIX/calls.log" ]]; echo $?)"

reset_fix
run --run-id 1;                                   check "--mode is required" "$([[ $RC -eq 2 ]]; echo $?)"
run --mode banana --run-id 1;                      check "--mode is an enum" "$([[ $RC -eq 2 ]]; echo $?)"
for badid in 0 01 abc -1 1234567890 "1;rm"; do
  run --mode dry_run --run-id "$badid";            check "--run-id '$badid' refused" "$([[ $RC -eq 2 ]]; echo $?)"
done
run --mode real --run-id 1 --discharged-sha "$SHA";                          check "--pr required for real" "$([[ $RC -eq 2 ]]; echo $?)"
run --mode real --run-id 1 --pr 77 --discharged-sha "${SHA:0:39}";           check "short sha refused" "$([[ $RC -eq 2 ]]; echo $?)"
run --mode real --run-id 1 --pr 77 --discharged-sha "$(printf 'A%.0s' {1..40})"; check "uppercase sha refused" "$([[ $RC -eq 2 ]]; echo $?)"
run --mode real --run-id 1 --pr "7x" --discharged-sha "$SHA";                check "non-numeric pr refused" "$([[ $RC -eq 2 ]]; echo $?)"
run --mode dry_run --run-id 1 --bogus;                                       check "unknown flag refused" "$([[ $RC -eq 2 ]]; echo $?)"
check "no doppler or curl call for any refused argument" "$(! calls | grep -qE '^(doppler|curl)'; echo $?)"

# ---- credential handling ------------------------------------------------------------------------------------------
reset_fix; printf 'bad"token' >"$FIX/token"
run --mode dry_run --run-id 1
check "token-shape refusal exits 3" "$([[ $RC -eq 3 ]]; echo $?)"
check "token-shape refusal makes zero curl calls" "$(! calls | grep -q '^curl'; echo $?)"
reset_fix; : >"$FIX/token"; run --mode dry_run --run-id 1
check "empty secret exits 3" "$([[ $RC -eq 3 ]]; echo $?)"
reset_fix; touch "$FIX/doppler.fail"; run --mode dry_run --run-id 1
check "doppler failure exits 3 and sends nothing" "$([[ $RC -eq 3 ]] && ! calls | grep -q '^curl'; echo $?)"

# ---- dry_run happy path -------------------------------------------------------------------------------------------
reset_fix; run --mode dry_run --run-id 5
check "dry_run exits 0 and prints the validated body" "$([[ $RC -eq 0 ]] && jq -e '.schema_version == 1' <<<"$OUT" >/dev/null; echo $?)"
check "token is absent from every argv in the call log" "$(! calls | grep -qF "$SENTINEL"; echo $?)"
check "token reached curl on its stdin config channel" "$(grep -qF "Authorization: Bearer $SENTINEL" "$FIX/curl.stdin"; echo $?)"
check "token never appears in the output" "$(! grep -qF "$SENTINEL" <<<"$OUT"; echo $?)"
check "dry_run body built by jq with a numeric run_id and the served sha" "$(calls | grep -q '^BODY {"run_id":5,"mode":"dry_run","expect_build_sha":"'"$SHA"'"}$'; echo $?)"
check "dry_run makes no gh or git call" "$(! calls | grep -qE '^(gh|git) '; echo $?)"
check "no unmodelled argv" "$(no_unmodelled; echo $?)"

# ---- real: happy path ---------------------------------------------------------------------------------------------
reset_fix; run "${REAL_ARGS[@]}"
check "real exits 0 and prints the validated body" "$([[ $RC -eq 0 ]] && jq -e '.ok == true' <<<"$OUT" >/dev/null; echo $?)"
claim_line="$(calls | grep -n '^gh issue comment .*run_id=1 claim' | head -1 | cut -d: -f1)"
post_line="$(calls | grep -n '^REALPOST' | head -1 | cut -d: -f1)"
check "the write-ahead claim is posted BEFORE the real request" "$([[ -n "$claim_line" && -n "$post_line" && "$claim_line" -lt "$post_line" ]]; echo $?)"
check "the public marker is posted after a terminal outcome" "$(grep -qx 'home-census run_id=1 done' "$FIX/posted.log"; echo $?)"
check "every posted comment body matches the constant pattern" "$([[ "$(grep -cvE '^home-census run_id=[0-9]+ (claim|done)$' "$FIX/posted.log")" -eq 0 ]]; echo $?)"
check "the real body is built by jq and carries no accept_young by default" "$(calls | grep '^BODY .*"mode":"real"' | grep -qv accept_young; echo $?)"
check "no unmodelled argv (real path)" "$(no_unmodelled; echo $?)"

# ---- real: governance refusals (each sends nothing) ---------------------------------------------------------------
refused() { # name, expected rc
  check "$1: exit $2" "$([[ $RC -eq $2 ]]; echo $?)"
  check "$1: no real request" "$(! calls | grep -q '^REALPOST'; echo $?)"
  check "$1: no claim posted" "$([[ ! -s "$FIX/posted.log" ]]; echo $?)"
}
reset_fix; set_comments; run "${REAL_ARGS[@]}"; refused "no C8 comment" 8
reset_fix; set_comments "$(comment 99999 NONE "home-census C8 DISCHARGED sha=$SHA pr=77")"; run "${REAL_ARGS[@]}"; refused "C8 comment from an unpinned author is ignored" 8
reset_fix; set_comments "$(comment 54279 NONE "home-census C8 DISCHARGED sha=$SHA pr=77")"; run "${REAL_ARGS[@]}"; refused "C8 comment with the wrong association is ignored" 8
reset_fix; run --mode real --run-id 1 --discharged-sha "$SHA" --pr 78; refused "--pr differs from the C8 comment" 8
reset_fix; run --mode real --run-id 1 --discharged-sha "$OLD" --pr 77; refused "--discharged-sha differs from the C8 comment" 8
reset_fix; : >"$REPO/knowledge-base/legal/audits/2026-10-31-clo-ruling-10455-census-method.md"; run "${REAL_ARGS[@]}"; refused "sha absent from the committed CLO record" 8
reset_fix; echo "$OLD" >"$FIX/pr_head"; run "${REAL_ARGS[@]}"; refused "PR head differs from the discharged sha" 8
reset_fix; touch "$FIX/paths.differ"; run "${REAL_ARGS[@]}"; check "census paths changed after discharge: exit 9" "$([[ $RC -eq 9 ]]; echo $?)"
check "census paths changed after discharge: no real request" "$(! calls | grep -q '^REALPOST'; echo $?)"
reset_fix; result_json young lt_24h >"$FIX/dry.json"; run "${REAL_ARGS[@]}"; refused "young container without the explicit fallback" 8
reset_fix; set_comments "$(comment 54279 MEMBER "home-census C8 DISCHARGED sha=$SHA pr=77")" "$(comment 54279 MEMBER "home-census run_id=1 claim")" "$(comment 54279 MEMBER "home-census run_id=2 claim")"
run --mode real --run-id 3 --discharged-sha "$SHA" --pr 77; refused "two claims already exist" 8
reset_fix; set_comments "$(comment 54279 MEMBER "home-census C8 DISCHARGED sha=$SHA pr=77")" "$(comment 54279 MEMBER "home-census run_id=4 claim")"
run "${REAL_ARGS[@]}"; refused "run_id at or below the last claim" 8
reset_fix; set_comments "$(comment 54279 MEMBER "home-census C8 DISCHARGED sha=$SHA pr=77")" "$(comment 99999 NONE "home-census run_id=1 claim")" "$(comment 99999 NONE "home-census run_id=2 claim")" "$(comment 99999 NONE "home-census run_id=9 claim")"
run "${REAL_ARGS[@]}"; check "forged claim comments from an unpinned author are not counted" "$([[ $RC -eq 0 ]]; echo $?)"
reset_fix; touch "$FIX/gh.fail"; run "${REAL_ARGS[@]}"; check "claim comment failure fails closed (exit 8)" "$([[ $RC -eq 8 ]]; echo $?)"
check "claim comment failure: no real request" "$(! calls | grep -q '^REALPOST'; echo $?)"

# ---- real: --c9-fallback ------------------------------------------------------------------------------------------
reset_fix; result_json young lt_24h >"$FIX/dry.json"; run "${REAL_ARGS[@]}" --c9-fallback
check "--c9-fallback proceeds on a young container" "$([[ $RC -eq 0 ]]; echo $?)"
check "--c9-fallback sends accept_young true" "$(calls | grep '^BODY .*"mode":"real"' | grep -q '"accept_young":true'; echo $?)"

# ---- real: output and error handling ------------------------------------------------------------------------------
reset_fix; printf 403 >"$FIX/real.code"; printf 'RAYID-1234 client 203.0.113.9 canary-body' >"$FIX/real.json"; run "${REAL_ARGS[@]}"
check "a 403 exits 5" "$([[ $RC -eq 5 ]]; echo $?)"
check "a non-2xx body is never printed" "$(! grep -qE 'RAYID|203\.0\.113|canary-body' <<<"$OUT"; echo $?)"
reset_fix; printf 502 >"$FIX/real.code"; printf '<html>RAYID-9</html>' >"$FIX/real.json"; run "${REAL_ARGS[@]}"
check "a 502 exits 6 without printing the body and without a done marker (ambiguous)" "$([[ $RC -eq 6 ]] && ! grep -q RAYID <<<"$OUT" && ! grep -q done "$FIX/posted.log"; echo $?)"
reset_fix; printf 200 >"$FIX/real.code"; jq -nc '{schema_version: 1, ok: true, extra_key: "/home/canary-path", classes: []}' >"$FIX/real.json"; run "${REAL_ARGS[@]}"
check "a 200 body outside the allowlist schema exits 10 and is not printed" "$([[ $RC -eq 10 ]] && ! grep -q canary-path <<<"$OUT"; echo $?)"
reset_fix; printf 28 >"$FIX/curl.rc"; run "${REAL_ARGS[@]}"
check "a timeout after the claim exits 7 and says not to retry" "$([[ $RC -eq 7 ]] && grep -q 'do not retry' <<<"$OUT"; echo $?)"
check "a timeout posts no done marker" "$(! grep -q done "$FIX/posted.log"; echo $?)"
reset_fix; printf 409 >"$FIX/real.code"; printf '{}' >"$FIX/real.json"; run "${REAL_ARGS[@]}"
check "a 409 exits 11 and names only the preflight" "$([[ $RC -eq 11 ]] && ! grep -q -- '--mode real' <<<"$OUT"; echo $?)"
reset_fix; printf 401 >"$FIX/real.code"; printf '{}' >"$FIX/real.json"; run "${REAL_ARGS[@]}"
check "a 401 exits 4" "$([[ $RC -eq 4 ]]; echo $?)"
reset_fix; jq -nc --arg s "$OLD" '{status: "ok", build_sha: $s}' >"$FIX/health.json"
run "${REAL_ARGS[@]}"; check "a served build that is not at the discharged commit exits 9 or refuses" "$([[ $RC -ne 0 ]]; echo $?)"
reset_fix; jq -nc '{status: "ok", build_sha: "dev"}' >"$FIX/health.json"; run "${REAL_ARGS[@]}"
check "a 'dev' build fails closed" "$([[ $RC -eq 9 ]] && ! calls | grep -q '^REALPOST'; echo $?)"

# ---- floors (printf + exit 1, never through the helper they backstop) ----------------------------------------------
if [[ "$PASS" -lt 84 ]]; then printf 'FLOOR: only %d assertions ran (expected at least 84)\n' "$PASS"; exit 1; fi
printf 'home-census-trigger tests: %d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
