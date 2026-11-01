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
INTERP="counted in this container's writable layer at the run; not a statement about earlier containers, other hosts, or any time before or after the run"
SHA="$(printf 'a%.0s' {1..40})"        # the discharged commit (a PR commit that is squashed away)
SRV="$(printf 'c%.0s' {1..40})"        # the served build (the squash commit): a DIFFERENT sha, as in production
TOP_REAL="$(cd "$HERE/../../.." && pwd)"
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
  "api repos/jikig-ai/soleur/issues/10455/comments --paginate")
    # gh.lag: the first read after a claim was posted does not list it yet (eventual consistency)
    if [[ -f "$FIX/gh.lag" && -s "$FIX/posted.log" && ! -f "$FIX/lag.done" ]]; then touch "$FIX/lag.done"; jq '.[:-1]' "$FIX/comments.json"; else cat "$FIX/comments.json"; fi ;;
  "issue comment 10455 -R jikig-ai/soleur --body "*)
    [[ -f "$FIX/gh.fail" ]] && exit 1
    all="$*"; body="${all#*--body }"
    printf '%s\n' "$body" >>"$FIX/posted.log"
    # a posted comment becomes visible to later reads unless the posting account is not the pinned one
    if [[ ! -f "$FIX/gh.noread" ]]; then
      jq --arg b "$body" '. + [{user: {id: 54279}, author_association: "MEMBER", body: $b}]' "$FIX/comments.json" >"$FIX/c.tmp" && mv "$FIX/c.tmp" "$FIX/comments.json"
    fi ;;
  *) echo "UNMODELLED gh $*" >>"$FIX/calls.log"; exit 64 ;;
esac
EOF
cat >"$BIN/git" <<'EOF'
#!/usr/bin/env bash
echo "git $*" >>"$FIX/calls.log"
echo "gitcwd $PWD" >>"$FIX/calls.log"
DIS="$(cat "$FIX/dis")"; SERVED="$(cat "$FIX/served")"
CLO=knowledge-base/legal/audits/2026-10-31-clo-ruling-10455-census-method.md
SCRIPT=apps/web-platform/scripts/home-census-trigger.sh
BOUND=":(glob)apps/web-platform/server/home-census* apps/web-platform/app/api/internal/home-census apps/web-platform/lib/internal-auth.ts apps/web-platform/server/sentry-scrub.ts apps/web-platform/sentry.server.config.ts $SCRIPT"
case "$*" in
  "rev-parse --show-toplevel") echo "$TOP_FAKE" ;;
  "cat-file -e ${SERVED}^{commit}") [[ -f "$FIX/no.served" ]] && exit 1; : ;;
  "cat-file -e ${DIS}^{commit}") [[ -f "$FIX/no.discharged" ]] && exit 1; : ;;
  "fetch --no-tags origin refs/pull/"*"/head"|"fetch --no-tags origin main") : ;;
  "show ${SERVED}:${CLO}") [[ -f "$FIX/no.clo" ]] && exit 128; cat "$REPO_FAKE/$CLO" ;;
  "ls-tree -r --name-only ${SERVED} -- $BOUND") [[ -f "$FIX/no.tree" ]] && exit 0; echo "$SCRIPT" ;;
  "diff --quiet --no-ext-diff $DIS $SERVED -- $BOUND") [[ -f "$FIX/paths.differ" ]] && exit 1; : ;;
  "diff --quiet --no-ext-diff $DIS -- $SCRIPT") [[ -f "$FIX/script.differs" ]] && exit 1; : ;;
  "diff --stat $DIS $SERVED -- apps/web-platform/infra/vector.toml apps/web-platform/lib/routes.ts") [[ -f "$FIX/vector.changed" ]] && echo " apps/web-platform/infra/vector.toml | 2 +-"; : ;;
  "status --porcelain -- $SCRIPT") [[ -f "$FIX/script.dirty" ]] && echo " M $SCRIPT"; : ;;
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
    n=$(( $(cat "$FIX/health.n" 2>/dev/null || echo 0) + 1 )); echo "$n" >"$FIX/health.n"
    if [[ "$n" -ge 2 && -f "$FIX/health.after.json" ]]; then cat "$FIX/health.after.json"; else cat "$FIX/health.json"; fi ;;
  https://app.soleur.ai/api/internal/home-census)
    want="--disable --noproxy * --proto =https --max-redirs 0 --max-time 60 -sS -o $out -w %{http_code} -X POST https://app.soleur.ai/api/internal/home-census -H content-type: application/json -d $body --config -"
    [[ "$*" == "$want" && "$cfg" == 1 ]] || { echo "UNMODELLED curl (POST argv) $*" >>"$FIX/calls.log"; exit 64; }
    cat >"$FIX/curl.stdin"
    echo "BODY $body" >>"$FIX/calls.log"
    mode="$(jq -r .mode <<<"$body")"
    [[ "$mode" == "dry_run" && -f "$FIX/dry.rc" ]] && exit "$(cat "$FIX/dry.rc")"
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
  jq -nc --arg interp "$INTERP" --arg sha "$SRV" --arg ev "$1" --arg ub "$2" --argjson cls "$(class_json)" '{
    schema_version: 1, ok: true, run_id: 1, mode: "real", data_source: "container_home", build_sha: $sha, control: "passed",
    evidence: $ev, uptime_bucket: $ub, sunset_utc: "2026-11-30T00:00:00Z", truncated: false, truncation_reason: "none",
    snapshot: "non_atomic", mode_bits_semantics: "file_mode_only_not_reachability", interpretation: $interp,
    claude_config_dir_set: false, outer_wrap_cohorts: "unmeasured", roots: [], roots_distinct: true, roots_note: "none",
    activity_witness: false, trigger_class_nonzero: "false", classes: $cls }'
}
comment() { jq -nc --argjson id "$1" --arg a "$2" --arg b "$3" '{user: {id: $id}, author_association: $a, body: $b}'; }

reset_fix() {
  rm -rf "$FIX"; mkdir -p "$FIX"
  printf '%s' "$SENTINEL" >"$FIX/token"
  jq -nc --arg s "$SRV" '{status: "ok", build_sha: $s}' >"$FIX/health.json"
  result_json mature lt_7d >"$FIX/dry.json"; printf 200 >"$FIX/dry.code"
  result_json mature lt_7d >"$FIX/real.json"; printf 200 >"$FIX/real.code"
  echo "$SHA" >"$FIX/dis"; echo "$SRV" >"$FIX/served"
  printf '[%s]\n' "$(comment 54279 MEMBER "home-census C8 DISCHARGED sha=$SHA pr=77")" >"$FIX/comments.json"
  printf 'DISCHARGED sha=%s\n' "$SHA" >"$REPO/knowledge-base/legal/audits/2026-10-31-clo-ruling-10455-census-method.md"
  : >"$FIX/calls.log"
}
set_comments() { printf '[%s]\n' "$(IFS=,; echo "$*")" >"$FIX/comments.json"; }

run() { # args...; sets RC, STDOUT (data channel), ERR, and OUT (both, stdout first)
  STDOUT="$(cd "$REPO" && env -i PATH="$BIN:/usr/bin:/bin" HOME="$TMP" FIX="$FIX" REPO_FAKE="$REPO" TOP_FAKE="$TOP_REAL" HOME_CENSUS_READBACK_SLEEP=0 timeout 30s bash "${RUN_SCRIPT:-$SCRIPT}" "$@" 2>"$TMP/stderr.txt")"; RC=$?
  ERR="$(cat "$TMP/stderr.txt")"; OUT="${STDOUT}${STDOUT:+$'\n'}${ERR}"
}
calls() { cat "$FIX/calls.log" 2>/dev/null; }
no_unmodelled() { ! grep -q UNMODELLED < <(calls); }
REAL_ARGS=(--mode real --run-id 1 --discharged-sha "$SHA" --pr 77)

# ---- self-check and static refusals -------------------------------------------------------------------------------
reset_fix
OUT="$(env -i PATH="$BIN:/usr/bin:/bin" FIX="$FIX" timeout 15s bash "$SCRIPT" --self-check 2>&1)"; RC=$?
check "self-check prints the OK token" "$([[ "$OUT" == "HOME_CENSUS_TRIGGER_SELF_CHECK_OK" && $RC -eq 0 ]]; echo $?)"
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
check "no doppler or curl call for any refused argument" "$(! grep -qE '^(doppler|curl)' < <(calls); echo $?)"

# ---- credential handling ------------------------------------------------------------------------------------------
reset_fix; printf 'bad"token' >"$FIX/token"
run --mode dry_run --run-id 1
check "token-shape refusal exits 3" "$([[ $RC -eq 3 ]]; echo $?)"
check "token-shape refusal makes zero curl calls" "$(! grep -q '^curl' < <(calls); echo $?)"
reset_fix; : >"$FIX/token"; run --mode dry_run --run-id 1
check "empty secret exits 3" "$([[ $RC -eq 3 ]]; echo $?)"
reset_fix; touch "$FIX/doppler.fail"; run --mode dry_run --run-id 1
check "doppler failure exits 3 and sends nothing" "$([[ $RC -eq 3 ]] && ! grep -q '^curl' < <(calls); echo $?)"

# ---- dry_run happy path -------------------------------------------------------------------------------------------
reset_fix; run --mode dry_run --run-id 5
check "dry_run exits 0 and prints the validated body on stdout" "$([[ $RC -eq 0 ]] && jq -e '.schema_version == 1' <<<"$STDOUT" >/dev/null && [[ -z "$ERR" ]]; echo $?)"
check "token is absent from every argv in the call log" "$(! grep -qF "$SENTINEL" < <(calls); echo $?)"
check "token reached curl on its stdin config channel" "$(grep -qF "Authorization: Bearer $SENTINEL" "$FIX/curl.stdin"; echo $?)"
check "token never appears in the output" "$(! grep -qF "$SENTINEL" <<<"$OUT"; echo $?)"
check "dry_run body built by jq with a numeric run_id and the served sha" "$(grep -q '^BODY {"run_id":5,"mode":"dry_run","expect_build_sha":"'"$SRV"'"}$' < <(calls); echo $?)"
check "dry_run makes no gh or git call" "$(! grep -qE '^(gh|git) ' < <(calls); echo $?)"
check "no unmodelled argv" "$(no_unmodelled; echo $?)"

# ---- real: happy path ---------------------------------------------------------------------------------------------
reset_fix; run "${REAL_ARGS[@]}"
check "real exits 0 and prints exactly the validated body on stdout" "$([[ $RC -eq 0 ]] && jq -e '.ok == true and .mode == "real"' <<<"$STDOUT" >/dev/null && [[ "$(wc -l <<<"$STDOUT")" -eq 1 ]]; echo $?)"
check "the bound-path diff and the served/discharged refs are the two DIFFERENT shas" "$(grep -q "^git diff --quiet --no-ext-diff $SHA $SRV -- " < <(calls); echo $?)"
check "the CLO record is read from the SERVED commit" "$(grep -q "^git show $SRV:knowledge-base/legal/audits/" < <(calls); echo $?)"
check "every git diff/status/ls-tree check ran from the repository root" "$(! grep -A1 -E '^git (diff|status|ls-tree)' < <(calls) | grep '^gitcwd' | grep -cv "^gitcwd $TOP_REAL\$" >/dev/null; echo $?)"
check "expect_build_sha sent is the SERVED sha" "$(grep '^BODY .*"mode":"real"' < <(calls) | grep -c "\"expect_build_sha\":\"$SRV\"" >/dev/null; echo $?)"
claim_line="$(calls | grep -n '^gh issue comment .*run_id=1 claim' | head -1 | cut -d: -f1)"
post_line="$(calls | grep -n '^REALPOST' | head -1 | cut -d: -f1)"
check "the write-ahead claim is posted BEFORE the real request" "$([[ -n "$claim_line" && -n "$post_line" && "$claim_line" -lt "$post_line" ]]; echo $?)"
check "the public marker is posted after a terminal outcome" "$(grep -qx 'home-census run_id=1 done' "$FIX/posted.log"; echo $?)"
check "every posted comment body matches the constant pattern" "$([[ "$(grep -cvE '^home-census run_id=[0-9]+ (claim|done)$' "$FIX/posted.log")" -eq 0 ]]; echo $?)"
check "the real body is built by jq and carries no accept_young by default" "$(grep '^BODY .*"mode":"real"' < <(calls) | grep -cv accept_young >/dev/null; echo $?)"
check "no unmodelled argv (real path)" "$(no_unmodelled; echo $?)"

# ---- real: governance refusals (each sends nothing) ---------------------------------------------------------------
refused() { # name, expected rc
  check "$1: exit $2" "$([[ $RC -eq $2 ]]; echo $?)"
  check "$1: no real request" "$(! grep -q '^REALPOST' < <(calls); echo $?)"
  check "$1: no claim posted" "$([[ ! -s "$FIX/posted.log" ]]; echo $?)"
  check "$1: nothing on stdout (the data channel)" "$([[ -z "$STDOUT" ]]; echo $?)"
}
reset_fix; set_comments; run "${REAL_ARGS[@]}"; refused "no C8 comment" 8
reset_fix; set_comments "$(comment 99999 NONE "home-census C8 DISCHARGED sha=$SHA pr=77")"; run "${REAL_ARGS[@]}"; refused "C8 comment from an unpinned author is ignored" 8
reset_fix; set_comments "$(comment 54279 NONE "home-census C8 DISCHARGED sha=$SHA pr=77")"; run "${REAL_ARGS[@]}"; refused "C8 comment with the wrong association is ignored" 8
reset_fix; run --mode real --run-id 1 --discharged-sha "$SHA" --pr 78; refused "--pr differs from the C8 comment" 8
reset_fix; run --mode real --run-id 1 --discharged-sha "$OLD" --pr 77; refused "--discharged-sha differs from the C8 comment" 8
reset_fix; : >"$REPO/knowledge-base/legal/audits/2026-10-31-clo-ruling-10455-census-method.md"; run "${REAL_ARGS[@]}"; refused "sha absent from the committed CLO record" 8
reset_fix; printf 'prose mentions DISCHARGED sha=%s in a sentence\n' "$SHA" >"$REPO/knowledge-base/legal/audits/2026-10-31-clo-ruling-10455-census-method.md"; run "${REAL_ARGS[@]}"; refused "the sha only inside prose of the CLO record (the line must stand alone)" 8
reset_fix; touch "$FIX/no.served"; run "${REAL_ARGS[@]}"; check "an unavailable served commit exits 9" "$([[ $RC -eq 9 ]]; echo $?)"
reset_fix; touch "$FIX/no.discharged"; run "${REAL_ARGS[@]}"; refused "an unavailable discharged commit" 8
reset_fix; touch "$FIX/no.clo"; run "${REAL_ARGS[@]}"; refused "the CLO record missing from the served build" 8
reset_fix; touch "$FIX/no.tree"; run "${REAL_ARGS[@]}"; check "bound paths that match no file of the served build exit 9 (the diff would be vacuous)" "$([[ $RC -eq 9 ]] && ! grep -q '^REALPOST' < <(calls); echo $?)"
reset_fix; cp "$SCRIPT" "$TMP/copy.sh"; RUN_SCRIPT="$TMP/copy.sh" run "${REAL_ARGS[@]}"; refused "a copy of the script outside the checkout" 8
reset_fix; touch "$FIX/gh.lag"; run "${REAL_ARGS[@]}"; check "a claim that appears only on the second read is accepted" "$([[ $RC -eq 0 ]]; echo $?)"
reset_fix; printf 200 >"$FIX/real.code"; result_json mature lt_7d | jq '.mode = "dry_run" | .data_source = "synthetic"' >"$FIX/real.json"; run "${REAL_ARGS[@]}"
check "a dry_run-shaped 200 is not recorded as the real run (exit 10)" "$([[ $RC -eq 10 ]] && [[ -z "$STDOUT" ]]; echo $?)"
reset_fix; { printf '{"leak":"/home/canary-path"}\n'; cat "$FIX/real.json"; } >"$FIX/t" && mv "$FIX/t" "$FIX/real.json"; run "${REAL_ARGS[@]}"
check "a multi-document 200 body is refused and nothing is printed (exit 10)" "$([[ $RC -eq 10 ]] && ! grep -q canary-path <<<"$OUT"; echo $?)"
reset_fix; printf '{"a":1}\n' >>"$FIX/dry.json"; run --mode dry_run --run-id 1
check "a multi-document dry_run body is refused (exit 10)" "$([[ $RC -eq 10 ]] && [[ -z "$STDOUT" ]]; echo $?)"
reset_fix; printf 503 >"$FIX/real.code"; jq -nc --arg i "$INTERP" '{schema_version: 1, ok: false, error_class: "control_failed", interpretation: $i}' >"$FIX/real.json"; run "${REAL_ARGS[@]}"
check "a 503 with the exact failure shape is a definitive refusal (exit 11, error_class printed, done marker posted)" "$([[ $RC -eq 11 ]] && grep -q 'error_class=control_failed' <<<"$OUT" && grep -qx 'home-census run_id=1 done' "$FIX/posted.log"; echo $?)"
reset_fix; printf 503 >"$FIX/real.code"; printf '<html>proxy RAYID</html>' >"$FIX/real.json"; run "${REAL_ARGS[@]}"
check "a 503 proxy page is ambiguous (exit 6, do not retry, no done marker, body not printed)" "$([[ $RC -eq 6 ]] && grep -q 'do not retry' <<<"$OUT" && ! grep -q done "$FIX/posted.log" && ! grep -q RAYID <<<"$OUT"; echo $?)"
reset_fix; printf 429 >"$FIX/real.code"; jq -nc --arg i "$INTERP" '{schema_version: 1, ok: false, error_class: "rate_limited", interpretation: $i}' >"$FIX/real.json"; run "${REAL_ARGS[@]}"
check "a 429 is a refusal (exit 11, error_class printed)" "$([[ $RC -eq 11 ]] && grep -q 'error_class=rate_limited' <<<"$OUT"; echo $?)"
reset_fix; printf 409 >"$FIX/real.code"; jq -nc '{schema_version: 1, ok: false, error_class: "busy", interpretation: "tampered"}' >"$FIX/real.json"; run "${REAL_ARGS[@]}"
check "a failure body with the wrong interpretation prints no error_class" "$([[ $RC -eq 11 ]] && ! grep -q 'error_class=' <<<"$OUT"; echo $?)"
reset_fix; touch "$FIX/script.differs"; run "${REAL_ARGS[@]}"; refused "the trigger script differs from the discharged commit" 8
reset_fix; touch "$FIX/script.dirty"; run "${REAL_ARGS[@]}"; refused "the trigger script has uncommitted changes" 8
reset_fix; touch "$FIX/vector.changed"; run "${REAL_ARGS[@]}"
check "a changed vector.toml is shown, not blocking" "$([[ $RC -eq 0 ]] && grep -q 'vector.toml | 2' <<<"$OUT"; echo $?)"
reset_fix; set_comments "$(comment 99999 OWNER "home-census C8 DISCHARGED sha=$SHA pr=77")"; run "${REAL_ARGS[@]}"; refused "an OWNER-association comment from an unpinned id is ignored" 8
reset_fix; set_comments "$(comment 54279 MEMBER "note
home-census C8 DISCHARGED sha=$SHA pr=77")"; run "${REAL_ARGS[@]}"; refused "a DISCHARGED line inside a multi-line comment is not a discharge" 8
reset_fix; set_comments "$(comment 54279 MEMBER "home-census C8 DISCHARGED sha=$SHA pr=77")" "$(comment 54279 MEMBER "quoted:
home-census run_id=1 claim
home-census run_id=2 claim")"
run "${REAL_ARGS[@]}"; check "claim lines quoted inside a multi-line comment are not counted" "$([[ $RC -eq 0 ]]; echo $?)"
reset_fix; touch "$FIX/gh.noread"; run "${REAL_ARGS[@]}"; check "a claim that is not visible as a pinned-author comment fails closed (exit 8)" "$([[ $RC -eq 8 ]]; echo $?)"
check "an invisible claim: no real request" "$(! grep -q '^REALPOST' < <(calls); echo $?)"
reset_fix; touch "$FIX/paths.differ"; run "${REAL_ARGS[@]}"; check "census paths changed after discharge: exit 9" "$([[ $RC -eq 9 ]]; echo $?)"
check "census paths changed after discharge: no real request" "$(! grep -q '^REALPOST' < <(calls); echo $?)"
reset_fix; result_json young lt_24h >"$FIX/dry.json"; run "${REAL_ARGS[@]}"; refused "young container without the explicit fallback" 8
reset_fix; set_comments "$(comment 54279 MEMBER "home-census C8 DISCHARGED sha=$SHA pr=77")" "$(comment 54279 MEMBER "home-census run_id=1 claim")" "$(comment 54279 MEMBER "home-census run_id=2 claim")"
run --mode real --run-id 3 --discharged-sha "$SHA" --pr 77; refused "two claims already exist" 8
reset_fix; set_comments "$(comment 54279 MEMBER "home-census C8 DISCHARGED sha=$SHA pr=77")" "$(comment 54279 MEMBER "home-census run_id=4 claim")"
run "${REAL_ARGS[@]}"; refused "run_id at or below the last claim" 8
reset_fix; set_comments "$(comment 54279 MEMBER "home-census C8 DISCHARGED sha=$SHA pr=77")" "$(comment 99999 NONE "home-census run_id=1 claim")" "$(comment 99999 NONE "home-census run_id=2 claim")" "$(comment 99999 NONE "home-census run_id=9 claim")"
run "${REAL_ARGS[@]}"; check "forged claim comments from an unpinned author are not counted" "$([[ $RC -eq 0 ]]; echo $?)"
reset_fix; touch "$FIX/gh.fail"; run "${REAL_ARGS[@]}"; check "claim comment failure fails closed (exit 8)" "$([[ $RC -eq 8 ]]; echo $?)"
check "claim comment failure: no real request" "$(! grep -q '^REALPOST' < <(calls); echo $?)"

reset_fix; set_comments "$(comment 54279 MEMBER "home-census C8 DISCHARGED sha=$SHA pr=77")" "$(comment 54279 MEMBER "home-census run_id=1 claim")"
run "${REAL_ARGS[@]}"; refused "run_id equal to the last claim is refused (not only below it)" 8
reset_fix; set_comments "$(comment 54279 MEMBER "home-census C8 DISCHARGED sha=$SHA pr=77")" "$(comment 54279 MEMBER "home-census C8 DISCHARGED sha=$OLD pr=77")"
run "${REAL_ARGS[@]}"; refused "the LAST pinned DISCHARGED comment wins (a later discharge of another sha supersedes)" 8

# ---- real: --c9-fallback ------------------------------------------------------------------------------------------
reset_fix; result_json young lt_24h >"$FIX/dry.json"; run "${REAL_ARGS[@]}" --c9-fallback
check "--c9-fallback proceeds on a young container" "$([[ $RC -eq 0 ]]; echo $?)"
check "--c9-fallback sends accept_young true" "$(grep '^BODY .*"mode":"real"' < <(calls) | grep -c '"accept_young":true' >/dev/null; echo $?)"

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
# error_class is printed ONLY for the exact closed failure shape
reset_fix; printf 409 >"$FIX/real.code"; jq -nc --arg i "$INTERP" '{schema_version: 1, ok: false, error_class: "build_mismatch", interpretation: $i}' >"$FIX/real.json"; run "${REAL_ARGS[@]}"
check "a 409 with the exact failure shape prints its error_class" "$([[ $RC -eq 11 ]] && grep -q 'error_class=build_mismatch' <<<"$OUT"; echo $?)"
reset_fix; printf 409 >"$FIX/real.code"; jq -nc --arg i "$INTERP" '{schema_version: 1, ok: false, error_class: "build_mismatch", interpretation: $i, extra: "/home/canary"}' >"$FIX/real.json"; run "${REAL_ARGS[@]}"
check "a 409 body with an extra key prints no error_class and no body" "$([[ $RC -eq 11 ]] && ! grep -q 'error_class=' <<<"$OUT" && ! grep -q canary <<<"$OUT"; echo $?)"
reset_fix; printf 410 >"$FIX/dry.code"; jq -nc --arg i "$INTERP" '{schema_version: 1, ok: false, error_class: "sunset", interpretation: $i}' >"$FIX/dry.json"; run --mode dry_run --run-id 1
check "dry_run after the sunset exits 11 and names the sunset" "$([[ $RC -eq 11 ]] && grep -q 'error_class=sunset' <<<"$OUT"; echo $?)"
reset_fix; printf 401 >"$FIX/dry.code"; printf '{}' >"$FIX/dry.json"; run --mode dry_run --run-id 1
check "dry_run 401 exits 4 (the real-path mapping)" "$([[ $RC -eq 4 ]]; echo $?)"
reset_fix; printf 502 >"$FIX/dry.code"; printf '<html>RAYID</html>' >"$FIX/dry.json"; run --mode dry_run --run-id 1
check "dry_run 502 exits 6 and says it is safe to retry, without printing the body" "$([[ $RC -eq 6 ]] && grep -q 'safe to retry' <<<"$OUT" && ! grep -q RAYID <<<"$OUT"; echo $?)"
reset_fix; printf 28 >"$FIX/dry.rc"; run --mode dry_run --run-id 1
check "dry_run curl failure exits 12 (no scan ran, safe to retry)" "$([[ $RC -eq 12 ]] && grep -q 'safe to retry' <<<"$OUT"; echo $?)"
reset_fix; jq '.classes[0].extra = "x"' "$FIX/dry.json" >"$FIX/t" && mv "$FIX/t" "$FIX/dry.json"; run --mode dry_run --run-id 1
check "a dry_run 2xx body that fails the schema exits 10 and is not printed" "$([[ $RC -eq 10 ]] && ! grep -q '"extra"' <<<"$OUT"; echo $?)"
# single-defect fixtures: each schema rule on its own
BAD='/home/canary-path'
for m in \
  '.extra_key = "x"' 'del(.control)' '.interpretation = "'"$BAD"'"' '.classes[3].n_symlink = "'"$BAD"'"' '.classes[3].n_mode_bits_group_r = "7"' \
  '.classes[0].class_result = "clean"' '.classes[0].class = "'"$BAD"'"' '.classes |= reverse' '.roots = [{label: "'"$BAD"'", root_present: true, root_listable: true}]' \
  '.build_sha = "'"$BAD"'"' '.mode = "'"$BAD"'"' '.trigger_class_nonzero = "maybe"' '.run_id = 1.5' '.ok = false' '.schema_version = 2' '.sunset_utc = "'"$BAD"'"' \
  '.snapshot = "x"' '.mode_bits_semantics = "x"' '.outer_wrap_cohorts = "x"' '.truncated = "yes"' '.data_source = "root"' '.control = "ok"' '.evidence = "old"' \
  '.roots_distinct = 1' '.activity_witness = "no"' '.classes[2].absent = "no"' '.claude_config_dir_set = "x"' '.classes[1].errors = "7"' '.truncation_reason = "depth_cap"' '.roots_note = "x"' \
  '.roots = [{label: "root", root_present: "yes", root_listable: true}]' '.roots = [{label: "root", root_present: true}]' '.uptime_bucket = "lt_2h"' '.sunset_utc = "2026-11-30T00:00:00Z\n"'; do
  reset_fix; jq "$m" "$FIX/real.json" >"$FIX/t" && mv "$FIX/t" "$FIX/real.json"; run "${REAL_ARGS[@]}"
  check "schema rule '$m': exit 10 and nothing printed" "$([[ $RC -eq 10 ]] && ! grep -q 'canary-path' <<<"$OUT" && ! grep -q '"schema_version"' <<<"$OUT"; echo $?)"
done
reset_fix; jq -nc --arg s "$OLD" '{status: "ok", build_sha: $s}' >"$FIX/health.after.json"; run "${REAL_ARGS[@]}"
check "a build that changes during the call exits 10 and the body is not printed" "$([[ $RC -eq 10 ]] && ! grep -q '"schema_version"' <<<"$OUT"; echo $?)"
reset_fix; jq -nc '{status: "ok", build_sha: "dev"}' >"$FIX/health.json"; run "${REAL_ARGS[@]}"
check "a 'dev' build fails closed" "$([[ $RC -eq 9 ]] && ! grep -q '^REALPOST' < <(calls); echo $?)"

# ---- floors (printf + exit 1, never through the helper they backstop) ----------------------------------------------
if [[ "$PASS" -lt 188 ]]; then
  printf 'FLOOR: only %d assertions ran (expected at least 188)\n' "$PASS"
  exit 1
fi
printf 'home-census-trigger tests: %d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
