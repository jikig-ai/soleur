# shellcheck shell=bash
# SOURCED FRAGMENT of tests/scripts/test-argv-bearer-sweep.sh -- NOT independently runnable.
# ---- rows 13 to 15: apply-deploy-pipeline-fix (library; the step reads its credentials through doppler, stubbed by secret NAME) ----
S4_DPF=".github/workflows/apply-deploy-pipeline-fix.yml"
S4_CWD="$REPO_ROOT/apps/web-platform/infra"     # the steps carry `working-directory: ${{ env.INFRA_DIR }}`
s4_body "$REPO_ROOT/$S4_DPF" "pre_frame" "$S4/b-r13.sh"
s4_body "$REPO_ROOT/$S4_DPF" "Verify webhook is alive post-apply" "$S4/b-r14.sh"
s4_body "$REPO_ROOT/$S4_DPF" "webhook_liveness" "$S4/b-r15.sh"
# row 13: pre_frame "degrades loudly, never blocks": a refusal records PRE_FRAME_STATUS=secret_unavailable (the existing "credential unusable" class)
S4_BASE=("${S4_DOP_BASE[@]}" SHIM_STATUS_BODY='{"start_ts":1700000123}')
s4_run r13-ok "$S4/b-r13.sh" "$S4/real" "${S4_BASE[@]}"
if [[ "$S4_RC" == 0 && "$(s4_ncalls)" == 1 && "$(s4_markers)" == 0 ]] && s4_calls_ok 3 && s4_wh_ok "$S4/bodies/empty" 1 && s4_genv_has 'PRE_FRAME_STATUS=ok' && s4_genv_has 'PRE_APPLY_FRAME_START_TS=1700000123'; then
  row "S4 row 13 pre_frame: a well-formed run reads the frame through the digest over the empty body and the pair on stdin and records PRE_FRAME_STATUS=ok" ok
else row "S4 row 13 pre_frame: well-formed run" fail "rc=$S4_RC calls=$(s4_ncalls)"; fi
s4_v_r13() { [[ "$S4_RC" == 0 ]] && s4_genv_has 'PRE_FRAME_STATUS=secret_unavailable' && ! grep -qE '^PRE_FRAME_STATUS=(unreachable|malformed|http404|ok|error)$' "$S4_ROW/genv" || return 1
  case "$1:$2" in
    D_CF_*) [[ "$(s4_markers)" == 1 ]] ;;
    *) [[ "$(s4_markers)" == 0 ]] ;;
  esac; }
s4_sweep r13 "$S4/b-r13.sh" "$S4/real" s4_v_r13 "D_CF_ACCESS_CLIENT_ID D_CF_ACCESS_CLIENT_SECRET" "D_WEBHOOK_DEPLOY_SECRET"
s4_sweep_row "S4 row 13 pre_frame: an empty, unset or hostile credential records PRE_FRAME_STATUS=secret_unavailable (never unreachable), exits 0, makes zero requests; the Cloudflare pair prints the marker once, the key arm keeps its own warning"
s4_nopy_row "S4 row 13 pre_frame (library HMAC site): python3 absent records secret_unavailable, exits 0, makes zero requests (the apply is never blocked)" "$S4/b-r13.sh" s4_v_r13
S4_SHIM="$S4/shimreal"; s4_run r13-transport "$S4/b-r13.sh" "$S4/real" "${S4_BASE[@]}"; S4_SHIM="$S4/shim"
if [[ "$S4_RC" == 0 && "$(s4_markers)" == 0 ]] && s4_genv_has 'PRE_FRAME_STATUS=unreachable'; then row "S4 row 13 pre_frame: a REAL transport failure still records PRE_FRAME_STATUS=unreachable (the old class for a request that was sent and failed)" ok
else row "S4 row 13 pre_frame: transport failure" fail "rc=$S4_RC env=$(tr '\n' ' ' < "$S4_ROW/genv")"; fi
# row 14: Verify webhook is alive post-apply: a refusal is the step's old red (three attempts, then the ::error::), marker visible per attempt
S4_BASE=("${S4_DOP_BASE[@]}" SHIM_STATUS_BODY='{"start_ts":1700000123}')
s4_run r14-ok "$S4/b-r14.sh" "$S4/real" "${S4_BASE[@]}"
if [[ "$S4_RC" == 0 && "$(s4_ncalls)" == 1 ]] && s4_calls_ok 3 && s4_wh_ok "$S4/bodies/empty" 1 && s4_said 'Webhook is alive (HTTP 200 on attempt 1)'; then row "S4 row 14 post-apply liveness: a well-formed run is alive on the first attempt through the digest and the pair on stdin" ok
else row "S4 row 14 post-apply liveness: well-formed run" fail "rc=$S4_RC calls=$(s4_ncalls)"; fi
s4_run r14-empty "$S4/b-r14.sh" "$S4/real" "${S4_BASE[@]}" D_WEBHOOK_DEPLOY_SECRET=
if [[ "$S4_RC" != 0 && "$(s4_ncalls)" == 0 && "$(s4_markers)" == 3 ]] && s4_said '::error::Webhook did not respond with HTTP 200 after 3 attempts'; then row "S4 row 14 post-apply liveness: an empty key is the old red (the 3-attempt ::error::) with the marker per attempt and zero requests" ok
else row "S4 row 14 post-apply liveness: empty key" fail "rc=$S4_RC calls=$(s4_ncalls) markers=$(s4_markers)"; fi
# row 15: webhook_liveness, CF pair only: today 401/403 -> probe_error (OUR credential), anything else -> `down` ("the re-push bricked the only no-SSH channel")
S4_BASE=(D_CF_ACCESS_CLIENT_ID="$S4_CFID" D_CF_ACCESS_CLIENT_SECRET="$S4_CFSEC" SHIM_PROFILE=webhook)
s4_run r15-ok "$S4/b-r15.sh" "$S4/real" "${S4_BASE[@]}"
if [[ "$S4_RC" == 0 && "$(s4_ncalls)" == 1 && "$(s4_stdin_line 1 1)" == "header = \"CF-Access-Client-Id: $S4_CFID\"" && "$(s4_stdin_line 1 2)" == "header = \"CF-Access-Client-Secret: $S4_CFSEC\"" ]] && s4_calls_ok 2 \
   && ! s4_argv_has "$S4_CFID" && ! s4_argv_has "$S4_CFSEC" && s4_gho_has 'listener_state=up'; then
  row "S4 row 15 webhook_liveness: a well-formed run sends the Cloudflare pair ONLY (two stdin headers, none on argv) and records listener_state=up" ok
else row "S4 row 15 webhook_liveness: well-formed run" fail "rc=$S4_RC calls=$(s4_ncalls)"; fi
s4_run r15-403 "$S4/b-r15.sh" "$S4/real" "${S4_BASE[@]}" SHIM_CODE=403
[[ "$S4_RC" != 0 && "$(s4_ncalls)" == 1 ]] && s4_gho_has 'listener_state=probe_error' && row "S4 row 15 webhook_liveness: a 403 from Cloudflare Access stays listener_state=probe_error (the old class)" ok || row "S4 row 15 webhook_liveness: 403" fail "rc=$S4_RC"
S4_SHIM="$S4/shimreal"; s4_run r15-transport "$S4/b-r15.sh" "$S4/real" "${S4_BASE[@]}"; S4_SHIM="$S4/shim"
[[ "$S4_RC" != 0 && "$(s4_markers)" == 0 ]] && s4_gho_has 'listener_state=down' && row "S4 row 15 webhook_liveness: a REAL transport failure is still listener_state=down (a request that was sent and got nothing), no marker" ok || row "S4 row 15 webhook_liveness: transport failure" fail "rc=$S4_RC"
s4_v_r15() { [[ "$S4_RC" != 0 ]] && s4_gho_has 'listener_state=probe_error' && ! grep -qE '^listener_state=(down|up)$' "$S4_ROW/gho" && ! s4_said 'bricked the only no-SSH remediation channel' || return 1
  case "$2" in hostile-*) [[ "$(s4_markers)" == 1 ]] ;; *) [[ "$(s4_markers)" == 0 ]] ;; esac; }
s4_sweep r15 "$S4/b-r15.sh" "$S4/real" s4_v_r15 "D_CF_ACCESS_CLIENT_ID D_CF_ACCESS_CLIENT_SECRET" ""
s4_sweep_row "S4 row 15 webhook_liveness: an empty, unset or hostile Cloudflare credential records listener_state=probe_error (NEVER down: no 'bricked the only no-SSH channel' claim), exits 1, makes zero requests; a hostile one prints the marker once"

# ---- row 18: the scheduled-inngest-health probe (library + pre-guard): a refusal is `secret_unset`, which files the liveness-probe issue and restarts NOTHING ----
S4_SIH=".github/workflows/scheduled-inngest-health.yml"
s4_body "$REPO_ROOT/$S4_SIH" "probe" "$S4/b-r18.sh"
S4_LIVE_OK='{"functions":[{"name":"synthetic-fn"}],"durability_state":"durable"}'
S4_BASE=("${S4_WH_BASE[@]}" SHIM_LIVE_BODY="$S4_LIVE_OK")
s4_run r18-ok "$S4/b-r18.sh" "$S4/real" "${S4_BASE[@]}"
if [[ "$S4_RC" == 0 && "$(s4_ncalls)" == 1 && "$(s4_markers)" == 0 ]] && s4_calls_ok 3 && s4_wh_ok "$S4/bodies/empty" 1 && s4_gho_has 'failure_mode=' && s4_gho_has 'durability_state=durable'; then
  row "S4 row 18 inngest-health probe: a well-formed run reads the liveness hook through the digest and the pair on stdin and records NO failure_mode" ok
else row "S4 row 18 inngest-health probe: well-formed run" fail "rc=$S4_RC calls=$(s4_ncalls) gho=$(tr '\n' ' ' < "$S4_ROW/gho")"; fi
s4_v_r18() { [[ "$S4_RC" == 0 ]] && s4_gho_has 'failure_mode=secret_unset' && ! grep -qE '^failure_mode=(inngest_down|inngest_unhealthy|probe_unavailable|functions_query_degraded)$' "$S4_ROW/gho" || return 1
  case "$2" in hostile-*|absent) [[ "$(s4_markers)" -ge 1 ]] ;; *) [[ "$(s4_markers)" == 0 ]] ;; esac; }
s4_sweep r18 "$S4/b-r18.sh" "$S4/real" s4_v_r18 "CF_ACCESS_CLIENT_ID CF_ACCESS_CLIENT_SECRET" "WEBHOOK_SECRET"
s4_sweep_row "S4 row 18 inngest-health probe: an empty, unset or hostile credential records failure_mode=secret_unset (liveness-probe class, NO restart verdict, never inngest_down), exits 0, makes zero requests"
s4_nopy_row "S4 row 18 inngest-health probe (library HMAC site): python3 absent records secret_unset with the marker and zero requests (the restart path is never reached)" "$S4/b-r18.sh" s4_v_r18
S4_SHIM="$S4/shimreal"; s4_run r18-transport "$S4/b-r18.sh" "$S4/real" "${S4_BASE[@]}"; S4_SHIM="$S4/shim"
if [[ "$S4_RC" == 0 && "$(s4_markers)" == 0 ]] && s4_gho_has 'failure_mode=probe_unavailable'; then row "S4 row 18 inngest-health probe: a REAL transport failure keeps the old class (probe_unavailable after 3 attempts), no marker" ok
else row "S4 row 18 inngest-health probe: transport failure" fail "rc=$S4_RC gho=$(tr '\n' ' ' < "$S4_ROW/gho")"; fi
S4_CWD=""

# ---- row 21: infra-config-verify.sh (INLINE + pre-guard): a refused credential must NOT print the "webhook listener being DOWN" sentence ----
S4_ICV="$REPO_ROOT/apps/web-platform/infra/infra-config-verify.sh"
S4_FLAGS=(--noprofile --norc); S4_CWD="$REPO_ROOT/apps/web-platform/infra"
S4_BASE=("${S4_DOP_BASE[@]}" VERIFY_PASS=1 INFRA_CONFIG_STATUS_RESPONSE=@ROW@/rt/status.txt SHIM_STATUS_BODY='{"exit_code":0,"reason":"success","start_ts":1700000123}')
s4_run r21-ok "$S4_ICV" "$S4/real" "${S4_BASE[@]}"
if [[ "$(s4_ncalls)" -ge 1 && "$(s4_markers)" == 0 ]] && s4_calls_ok 3 && s4_wh_ok "$S4/bodies/empty" 1 && ! s4_said 'webhook listener being DOWN'; then
  row "S4 row 21 infra-config-verify (inline): a well-formed poll sends the digest over the empty body and the pair as three stdin directives, none on argv, and makes no refusal" ok
else row "S4 row 21 infra-config-verify (inline): well-formed run" fail "rc=$S4_RC calls=$(s4_ncalls) markers=$(s4_markers)"; fi
s4_v_r21() { ! s4_said 'webhook listener being DOWN' && ! s4_said 'UNREACHABLE (HTTP' || return 1
  if [[ "$2" == unset ]]; then [[ "$S4_RC" != 0 ]]   # the doppler read aborts the script before any guard: unchanged behaviour, no request
  else [[ "$S4_RC" == 1 && "$(s4_markers)" == 1 ]] && s4_said 'this says nothing about the listener'; fi; }
s4_sweep r21 "$S4_ICV" "$S4/real" s4_v_r21 "D_CF_ACCESS_CLIENT_ID D_CF_ACCESS_CLIENT_SECRET" "D_WEBHOOK_DEPLOY_SECRET"
s4_sweep_row "S4 row 21 infra-config-verify: an empty or hostile credential exits 1 with its OWN message ('this says nothing about the listener') and the marker once, zero requests, never the 'listener being DOWN' sentence; an unset one aborts before any guard"
s4_nopy_row "S4 row 21 infra-config-verify (inline HMAC site): python3 absent is the same own-message exit 1 with the marker and zero requests, never the DOWN sentence" "$S4_ICV" s4_v_r21
S4_SHIM="$S4/shimreal"; s4_run r21-transport "$S4_ICV" "$S4/real" "${S4_BASE[@]}"; S4_SHIM="$S4/shim"
if [[ "$S4_RC" == 1 && "$(s4_markers)" == 0 ]] && s4_said 'did not respond with HTTP 200 after 3 attempts'; then row "S4 row 21 infra-config-verify: a REAL transport failure keeps the old verdict (3 attempts, the 000000 quirk lands in the generic non-200 arm), no marker" ok
else row "S4 row 21 infra-config-verify: transport failure" fail "rc=$S4_RC markers=$(s4_markers)"; fi
S4_FLAGS=(--noprofile --norc -e); S4_CWD=""

# ---- row 22: github-app-key-status.sh (library): a refusal reaches the EXISTING exit-6 arm (curl_rc=2) with the marker visible ----
S4_GAK="$REPO_ROOT/apps/web-platform/scripts/github-app-key-status.sh"
S4_FLAGS=(--noprofile --norc)
S4_GAK_BODY='{"github_app_key_source":"doppler","github_app_key_fetch":"ok","github_app_key_probe":"accepted","component":"web-platform","tag":"v1.2.3","exit_code":0,"reason":"success","end_ts":1700000200,"host_id":"web-1"}'
S4_BASE=(WEBHOOK_DEPLOY_SECRET="$S4_KEY" CF_ACCESS_CLIENT_ID="$S4_CFID" CF_ACCESS_CLIENT_SECRET="$S4_CFSEC" SHIM_PROFILE=webhook SHIM_STATUS_BODY="$S4_GAK_BODY")
s4_run r22-ok "$S4_GAK" "$S4/real" "${S4_BASE[@]}"
if [[ "$S4_RC" == 0 && "$(s4_ncalls)" == 1 ]] && s4_calls_ok 3 && s4_wh_ok "$S4/bodies/empty" 1 && s4_said 'github_app_key_source=doppler' && s4_said 'host_id=web-1'; then
  row "S4 row 22 github-app-key-status: a well-formed run prints the key-source lines (exit 0) through the digest and the pair on stdin, none on argv" ok
else row "S4 row 22 github-app-key-status: well-formed run" fail "rc=$S4_RC calls=$(s4_ncalls)"; fi
s4_v_r22() { case "$1:$2" in
    WEBHOOK_DEPLOY_SECRET:*|*:empty|*:unset) [[ "$S4_RC" == 3 && "$(s4_markers)" == 0 ]] && s4_said 'missing ' ;;   # credentials not injected: the existing exit 3
    *) [[ "$S4_RC" == 6 && "$(s4_markers)" == 1 ]] && s4_said 'deploy-status read failed: http_code= curl_rc=2' ;;
  esac; }
s4_sweep r22 "$S4_GAK" "$S4/real" s4_v_r22 "CF_ACCESS_CLIENT_ID CF_ACCESS_CLIENT_SECRET" "WEBHOOK_DEPLOY_SECRET"
s4_sweep_row "S4 row 22 github-app-key-status: an empty or unset credential keeps exit 3; a hostile one reaches the existing exit-6 arm with curl_rc=2, the marker once, zero requests and the canary absent"
s4_v_r22_nopy() { [[ "$S4_RC" == 6 && "$(s4_markers)" == 1 ]] && s4_said 'curl_rc=2'; }
s4_nopy_row "S4 row 22 github-app-key-status (library HMAC site): python3 absent reaches exit 6 (curl_rc=2) with the marker and zero requests" "$S4_GAK" s4_v_r22_nopy
S4_FLAGS=(--noprofile --norc -e)

# ---- row 20: push-infra-config.sh (library, found by BASH_SOURCE). A script, not a workflow step, and no existing suite executes it: the REAL
# script runs here under the recording curl with INFRA_DIR at the real apps/web-platform/infra ----
S4_PIC="$REPO_ROOT/apps/web-platform/infra/push-infra-config.sh"
S4_FLAGS=(--noprofile --norc)
S4_PIC_BASE=(WEBHOOK_SECRET="$S4_KEY" CF_ACCESS_ID="$S4_CFID" CF_ACCESS_SECRET="$S4_CFSEC" APP_DOMAIN_BASE=example.invalid INFRA_DIR="$REPO_ROOT/apps/web-platform/infra" HOOKS_JSON_B64=e30= SOLEUR_DOPPLER_TOKEN_B64=eA== SHIM_PROFILE=webhook)
S4_BASE=("${S4_PIC_BASE[@]}")
s4_run r20-ok "$S4_PIC" "$S4/real" "${S4_BASE[@]}"
if [[ "$S4_RC" == 0 && "$(s4_ncalls)" == 1 && "$(s4_markers)" == 0 ]] && s4_calls_ok 3 && s4_wh_ok "$S4_ROW/calls/1.body" 1 && s4_said 'infra-config push succeeded (HTTP 202)' \
   && grep -qF '"ci_deploy_sh_b64"' "$S4_ROW/calls/1.body"; then
  row "S4 row 20 push-infra-config: the REAL script signs the payload FILE bytes (independent openssl digest over the recorded body), sends the digest and the pair as three stdin headers in no argv, and a 202 prints 'infra-config push succeeded (HTTP 202)'" ok
else row "S4 row 20 push-infra-config: well-formed run" fail "rc=$S4_RC calls=$(s4_ncalls) markers=$(s4_markers)"; fi
s4_v_r20() { [[ "$S4_RC" != 0 ]] && ! s4_said 'infra-config push succeeded' || return 1
  case "$2" in hostile-*) [[ "$(s4_markers)" == 1 ]] ;; *) [[ "$(s4_markers)" == 0 ]] && s4_said "required env var $1 is missing or empty" ;; esac; }
s4_v_r20_nopy() { [[ "$S4_RC" != 0 && "$(s4_markers)" == 1 ]] && ! s4_said 'infra-config push succeeded'; }
s4_sweep r20 "$S4_PIC" "$S4/real" s4_v_r20 "CF_ACCESS_ID CF_ACCESS_SECRET" "WEBHOOK_SECRET"
s4_sweep_row "S4 row 20 push-infra-config: an empty or unset credential or key keeps the script's own required-variable error, a hostile Cloudflare value is refused with ONE marker; every one exits non-zero with ZERO requests and the canary absent (no partial delivery to web-1)"
s4_nopy_row "S4 row 20 push-infra-config (library HMAC site): python3 absent exits non-zero with the marker and ZERO requests, never a mute abort and never a push" "$S4_PIC" s4_v_r20_nopy
S4_PUSH_BAD=""
for pc in 401 403 404 500; do
  s4_run "r20-$pc" "$S4_PIC" "$S4/real" "${S4_BASE[@]}" SHIM_POST_CODE="$pc"
  [[ "$S4_RC" != 0 && "$(s4_ncalls)" == 1 ]] && ! s4_said 'infra-config push succeeded' && s4_said "webhook returned HTTP $pc (expected 202)" || S4_PUSH_BAD+=" $pc"
done
[[ -z "$S4_PUSH_BAD" ]] && row "S4 row 20 push-infra-config: a 401, 403, 404 or 500 from the webhook is never a pass (non-zero, no 'succeeded' line)" ok || row "S4 row 20 push-infra-config: a non-202 maps to a pass" fail "codes:$S4_PUSH_BAD"
S4_SHIM="$S4/shimreal"; s4_run r20-transport "$S4_PIC" "$S4/real" "${S4_BASE[@]}"; S4_SHIM="$S4/shim"
[[ "$S4_RC" != 0 && "$(s4_markers)" == 0 ]] && ! s4_said 'infra-config push succeeded' && row "S4 row 20 push-infra-config: a REAL transport failure still exits non-zero and is not a refusal (no marker)" ok || row "S4 row 20 push-infra-config: transport failure" fail "rc=$S4_RC markers=$(s4_markers)"
S4_FLAGS=(--noprofile --norc -e)

# ---- row 24: bump-inngest-bootstrap-pin.sh: the token left the push URL for a per-command environment header. A refused token dies at `args` with the
# marker BEFORE any git network call. The real script runs against an empty fixture repo with a recording git and fail-closed gh / crane ----
S4_BUMP="$REPO_ROOT/.github/scripts/bump-inngest-bootstrap-pin.sh"
S4_BB="$S4/bumpbin"; assert_fixture_dir "$S4_BB"; mkdir -p "$S4_BB"
REAL_GIT="$(type -P git)"
printf '#!%s\nprintf "%%s\\n" "$*" >> "${CALLS_DIR:?}/git.log"\nexec "%s" "$@"\n' "$BASH_BIN" "$REAL_GIT" > "$S4_BB/git"
for t in gh crane; do printf '#!%s\nprintf "%%s\\n" "%s" >> "${CALLS_DIR:?}/unexpected"\nexit 97\n' "$BASH_BIN" "$t" > "$S4_BB/$t"; done
chmod +x "$S4_BB/git" "$S4_BB/gh" "$S4_BB/crane"
S4_BREPO="$S4/bump-repo"; assert_fixture_dir "$S4_BREPO"; mkdir -p "$S4_BREPO"
env -i PATH="$S4/real:$(dirname "$REAL_GIT")" HOME="$S4" "$REAL_GIT" init -q "$S4_BREPO" || fatal "S4 row 24: could not initialise the fixture repo"
S4_GHS="ghs""_$(od -An -N20 -tx1 /dev/urandom | tr -d ' \n')"
S4_ARGS=(--signed-tag v1.2.3 --signed-digest "sha256:${S4_HEX64}" --signed-commit "$(od -An -N20 -tx1 /dev/urandom | tr -d ' \n')")
S4_FLAGS=(--noprofile --norc)
S4_BUMP_BASE=(BUMP_REPO_DIR="$S4_BREPO" GITHUB_REPOSITORY=jikig-ai/soleur)
s4_bump_net() { ! grep -qE '(^| )(ls-remote|push)( |$)' "$S4_ROW/calls/git.log" 2>/dev/null; }
S4_SHIM="$S4_BB"
S4_BUMP_BAD=""
for st in empty unset hostile-quote hostile-newline; do
  e=(); case "$st" in empty) e=(GH_TOKEN=) ;; unset) e=() ;; hostile-quote) e=("GH_TOKEN=${S4_CANARY}\"x") ;; hostile-newline) e=("GH_TOKEN=${S4_CANARY}"$'\n'"x") ;; esac
  s4_run "r24-$st" "$S4_BUMP" "$S4/real" "${S4_BUMP_BASE[@]}" ${e[@]+"${e[@]}"}
  { [[ "$S4_RC" == 1 && "$(s4_markers)" == 1 ]] && grep -qx 'result=error' "$S4_ROW/stdout" && s4_said '::error::args: GH_TOKEN' && s4_bump_net && [[ ! -e "$S4_ROW/calls/unexpected" ]] && s4_canary_clean; } || S4_BUMP_BAD+=" $st(rc=$S4_RC markers=$(s4_markers))"
done
[[ -z "$S4_BUMP_BAD" ]] && row "S4 row 24 bump-inngest-bootstrap-pin: an empty, unset or hostile GH_TOKEN dies at 'args' (exit 1, result=error) with the marker ONCE, no git ls-remote or push, no gh or crane call and the canary absent" ok || row "S4 row 24 bump-inngest-bootstrap-pin: a refused token" fail "$S4_BUMP_BAD"
s4_run r24-ok "$S4_BUMP" "$S4/real" "${S4_BUMP_BASE[@]}" GH_TOKEN="$S4_GHS"
if [[ "$(s4_markers)" == 0 ]] && ! s4_said 'GH_TOKEN (soleur-infra installation token) is required' && ! grep -qF -- "$S4_GHS" "$S4_ROW/calls/git.log" 2>/dev/null && ! grep -qF -- "$S4_GHS" < <(cat "$S4_ROW/stdout" "$S4_ROW/stderr"); then
  row "S4 row 24 bump-inngest-bootstrap-pin: a well-formed ghs_ token passes the shape guard (no marker, no token message) and appears in no recorded git argument and no output" ok
else row "S4 row 24 bump-inngest-bootstrap-pin: well-formed token" fail "rc=$S4_RC markers=$(s4_markers)"; fi
S4_SHIM="$S4/shim"; S4_ARGS=(); S4_FLAGS=(--noprofile --norc -e)

# ---- rows 19, 6, 3, 5, 16, 17: the census rows that had NO executed row (review F2). Until now a refusal at these sites was judged only by static
# pins (the parity audit, the `_bearer_ok` byte pin, replay), which cannot see a VERDICT-CLASS change: `|| HTTP_CODE=000` on the deploy-inngest-image
# trigger, the mint exchange swallowed with `|| true`, or the Hetzner guard neutered to `if false` all left the battery green. The REAL step bodies run
# here under the recording shims, each credential empty, unset and hostile, and every mutant above is a CONTROL row that the same verdict function must
# judge RED. Not executed, with the reason: the redeploy POST of row 16 alone (it shares every credential with the baseline read in front of it, so a
# refusal cannot reach the POST on its own: the baseline read's refusal row covers the class, and the well-formed run proves the POST's digest and pair).
S4_HZ="$(head -c 96 /dev/urandom | base64 -w0 | tr -d '+/=' | head -c 64)"
S4_BOOT="synth-boot-$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')"
S4_SSHREC="$S4/sshrec"
cat > "$S4_SSHREC" <<'S4SSH'
#!/usr/bin/env bash
# The recording ssh behind ${WEB_HOST_SSH}: logs every invocation's arguments, answers the bundle-dir probe, swallows stdin.
printf '%s\n' "$*" >> "${CALLS_DIR:?}/ssh.log"
case "$*" in *"mktemp -d"*) printf '/var/lib/workspaces-luks/wl-cutover.AbCd12\n' ;; *) cat > /dev/null ;; esac
exit "${SSH_RC:-0}"
S4SSH
sed -i "1s|.*|#!${BASH_BIN}|" "$S4_SSHREC"; chmod +x "$S4_SSHREC"
s4_ssh_calls() { if [[ -s "$S4_ROW/calls/ssh.log" ]]; then grep -c . "$S4_ROW/calls/ssh.log"; else echo 0; fi; }
# s4_creds_clean <var>...: none of the named values appears on any recorded argv (curl, python3, openssl) nor in the ssh log.
s4_creds_clean() { local v; for v in "$@"; do s4_nowhere_on_argv "$v" && ! grep -qaF -- "$v" "$S4_ROW/calls/ssh.log" 2>/dev/null || return 1; done; }

# ---- row 19: workspaces-luks-cutover "Run workspaces-luks cutover": the Hetzner volume lookup (INLINE wrapper; the step may execute no repo script).
# DATA-DESTRUCTIVE PRECONDITION: the lookup decides which device the real arm luksFormats. A refused token must abort BEFORE any ssh call and any device write:
# zero requests, zero ssh invocations, no REMOTE_DIR, exit 1 (the step runs `set +e`, so the abort is the explicit `exit 1`).
S4_LUKS=".github/workflows/workspaces-luks-cutover.yml"
s4_body "$REPO_ROOT/$S4_LUKS" "Run workspaces-luks cutover" "$S4/b-r19.sh"
S4_LUKS_BASE=(DOPPLER_TOKEN=synth-doppler-token WORKSPACES_LUKS_BOOT_TOKEN="$S4_BOOT" DRY_RUN=1 ROLLBACK=0 ROLLBACK_ACK_LUKS_WRITES=0 CLEAN_STRAY=0 WEB_HOST=10.0.1.10
  WEB_HOST_SSH="$S4_SSHREC" INFRA_DIR=apps/web-platform/infra SHIM_PROFILE=generic 'SHIM_BODY={"volumes":[{"id":4242}]}')
s4_luks_ok_run() { # <label> <body> <NAME=value>...: a well-formed run of the (possibly mutated) step
  local l="$1" b="$2"; shift 2; s4_run "$l" "$b" "$S4/real" "${S4_LUKS_BASE[@]}" "$@"; }
s4_luks_ok_run r19-ok "$S4/b-r19.sh" D_HCLOUD_TOKEN_READONLY="$S4_HZ"
if [[ "$S4_RC" == 0 && "$(s4_ncalls)" == 1 && "$(s4_markers)" == 0 && "$(s4_ssh_calls)" == 3 && "$(s4_stdin_line 1 1)" == "header = \"Authorization: Bearer $S4_HZ\"" ]] && s4_calls_ok 1 \
   && s4_creds_clean "$S4_HZ" "$S4_BOOT" && s4_genv_has 'REMOTE_DIR=/var/lib/workspaces-luks/wl-cutover.AbCd12' && grep -qF 'volumes?name=soleur-web-platform-data-luks' "$S4_ROW/calls/1.argv"; then
  row "S4 row 19 luks Hetzner read (inline): a well-formed run reads the volume with the read-only token as the ONLY stdin header, the token and the boot token are on no curl, python3, openssl or ssh argument, and the delivery follows (3 ssh calls)" ok
else row "S4 row 19 luks Hetzner read (inline): well-formed run" fail "rc=$S4_RC calls=$(s4_ncalls) ssh=$(s4_ssh_calls) markers=$(s4_markers)"; fi
# (#9927 item 8b) NO fallback arm. Until ADR-241 O10 an unset or empty read-only name read the read/write name; O5 and O10
# are done, so the read-only name is the only one read. With it unset and a VALID read/write token present, the step must
# REFUSE like any unusable token, and the read/write value must reach no request and no ssh invocation.
s4_run r19-no-fallback "$S4/b-r19.sh" "$S4/real" "${S4_LUKS_BASE[@]}" D_HCLOUD_TOKEN="$S4_HZ"
[[ "$S4_RC" == 1 && "$(s4_ncalls)" == 0 && "$(s4_ssh_calls)" == 0 && "$(s4_markers)" == 1 ]] && s4_said 'reason=readonly_absent' && s4_creds_clean "$S4_HZ" \
  && row "S4 row 19 luks Hetzner read (inline): with the read-only name unset a valid read/write token is NOT used (named readonly_absent refusal, zero requests, zero ssh)" ok || row "S4 row 19 luks Hetzner read (inline): no-fallback arm" fail "rc=$S4_RC calls=$(s4_ncalls) ssh=$(s4_ssh_calls) markers=$(s4_markers)"
s4_v_r19() { # a refusal: exit 1 with the step's own sentence and ONE marker, zero requests, ZERO ssh calls, no bundle dir, nothing delivered
  [[ "$S4_RC" == 1 && "$(s4_markers)" == 1 && "$(s4_ncalls)" == 0 && "$(s4_ssh_calls)" == 0 ]] && s4_said 'workspaces-luks-cutover: HCLOUD_TOKEN unusable' \
    && s4_said 'no request was made and nothing was delivered to web-1' && ! s4_said 'refusing to guess' && ! grep -q '^REMOTE_DIR=' "$S4_ROW/genv" && [[ ! -e "$S4_ROW/calls/ssh.log" ]]
}
S4_BASE=("${S4_LUKS_BASE[@]}")
s4_sweep r19 "$S4/b-r19.sh" "$S4/real" s4_v_r19 "D_HCLOUD_TOKEN_READONLY" ""
s4_sweep_row "S4 row 19 luks Hetzner read (inline, data-destructive precondition): an empty, unset or hostile read-only token (the fallback unavailable) aborts the step with exit 1, ONE marker, ZERO requests and ZERO ssh invocations, before the device is resolved or anything is delivered"
S4_BASE=("${S4_LUKS_BASE[@]}" D_HCLOUD_TOKEN="$S4_HZ")
s4_sweep r19fb "$S4/b-r19.sh" "$S4/real" s4_v_r19 "D_HCLOUD_TOKEN" ""
s4_sweep_row "S4 row 19 luks Hetzner read (inline): an empty, unset or hostile read/write token beside an unset read-only name is refused the same way, with zero requests and zero ssh invocations (the read/write name is never read)"
# CROSS (ADR-241 O10). NOTE, 2026-10-22: since #9927 item 8b the luks lookup, the loader's legacy arm and the PR-plan step no longer fall back to the
# read/write token at all; the rows below keep proving the stronger claim for any fallback that is ever reintroduced. The fallback happens ONLY when the read-only token is EMPTY or unreadable, never because it is MALFORMED. A refused read-only token
# beside a VALID read/write token must still ABORT (no request, no ssh), or a refused read-only credential would be silently upgraded to the write-capable one on a data-destructive
# path (the two sweeps above each leave the other name unset, so an `_bearer_ok "$RO" || HCLOUD_TOKEN=$RW` implementation is green in both).
S4_X19_BAD=""
for xv in "hostile-quote:${S4_CANARY}\"x" $'hostile-newline:'"${S4_CANARY}"$'\n'"url = \"http://127.0.0.1:9/\"" "space:${S4_HZ:0:6} ${S4_HZ:6}"; do
  s4_run "r19x-${xv%%:*}" "$S4/b-r19.sh" "$S4/real" "${S4_LUKS_BASE[@]}" "D_HCLOUD_TOKEN_READONLY=${xv#*:}" "D_HCLOUD_TOKEN=$S4_HZ"; S4_REFUSAL_RUNS=$((S4_REFUSAL_RUNS + 1))
  { s4_v_r19 && s4_canary_clean && s4_creds_clean "$S4_HZ"; } || S4_X19_BAD+=" [${xv%%:*} rc=$S4_RC calls=$(s4_ncalls) ssh=$(s4_ssh_calls) markers=$(s4_markers)]"
done
[[ -z "$S4_X19_BAD" ]] && row "S4 row 19 luks Hetzner read (inline, data-destructive precondition): a MALFORMED read-only token beside a VALID read/write token aborts the step (exit 1, ONE marker, ZERO requests, ZERO ssh); the read/write token is never used because the read-only one was refused (3 shapes)" ok || row "S4 row 19 luks Hetzner read (inline): a malformed read-only token fell back to the read/write token" fail "$S4_X19_BAD"
S4_XF_BUILT=0; s4_body_try "$REPO_ROOT/$S4_LUKS" "Run workspaces-luks cutover" "$S4/b-r19-xfall.sh" 'if ! _bearer_ok "$HCLOUD_TOKEN"; then' \
  'if ! _bearer_ok "$HCLOUD_TOKEN" && { HCLOUD_TOKEN="$(doppler secrets get HCLOUD_TOKEN --plain -p soleur -c prd_terraform)"; ! _bearer_ok "$HCLOUD_TOKEN"; }; then' && S4_XF_BUILT=1
if [[ "$S4_XF_BUILT" == 1 ]]; then s4_luks_ok_run ctl-r19-xfall "$S4/b-r19-xfall.sh" "D_HCLOUD_TOKEN_READONLY=${S4_CANARY}\"x" "D_HCLOUD_TOKEN=$S4_HZ"; fi
if [[ "$S4_XF_BUILT" == 1 && "$(s4_ncalls)" == 1 ]] && ! s4_v_r19; then row "S4 row 19 luks Hetzner read control: a step that falls back to the read/write token when the read-only one is MALFORMED makes the request with the write-capable token and is judged RED by the cross row's verdict" ok
else row "S4 row 19 luks Hetzner read control: the malformed-falls-back mutant is not judged red" fail "built=$S4_XF_BUILT calls=$(s4_ncalls) (untested: the step no longer contains the line the control mutates)"; fi
# CONTROLS (mutants): the verdict must judge each RED. `if false` is the neutered guard (measured surviving in BOTH the sweep and the luks suite before this row).
S4_NG_CALLS=0; S4_NG_V=untested; S4_NG_ARGV=untested
if s4_body_try "$REPO_ROOT/$S4_LUKS" "Run workspaces-luks cutover" "$S4/b-r19-noguard.sh" 'if ! _bearer_ok "$HCLOUD_TOKEN"; then' 'if false; then' \
   && s4_body_try "$REPO_ROOT/$S4_LUKS" "Run workspaces-luks cutover" "$S4/b-r19-argv.sh" '--max-time 15 --config - \' '--max-time 15 -H "Authorization: Bearer $HCLOUD_TOKEN" \'; then
  s4_luks_ok_run ctl-r19-noguard "$S4/b-r19-noguard.sh" "D_HCLOUD_TOKEN_READONLY=${S4_CANARY}"$'\n'"url = \"http://127.0.0.1:9/\""
  S4_NG_CALLS="$(s4_ncalls)"; if s4_v_r19; then S4_NG_V=green; else S4_NG_V=red; fi
  s4_luks_ok_run ctl-r19-argv "$S4/b-r19-argv.sh" D_HCLOUD_TOKEN_READONLY="$S4_HZ"
  if s4_argv_has "$S4_HZ" && ! s4_calls_ok 1 && ! s4_nowhere_on_argv "$S4_HZ"; then S4_NG_ARGV=red; else S4_NG_ARGV=green; fi
fi
if [[ "$S4_NG_CALLS" -ge 1 && "$S4_NG_V" == red && "$S4_NG_ARGV" == red ]]; then
  row "S4 row 19 luks Hetzner read control: a step whose guard is neutered ('if false') sends a hostile token (a request is made, so the refusal verdict is RED), and one that puts the token back on curl's argument list (-H) is judged RED by the stdin and argv predicates" ok
else row "S4 row 19 luks Hetzner read control: a mutant of the Hetzner guard or channel is not judged red" fail "noguard-calls=$S4_NG_CALLS verdict=$S4_NG_V argv-verdict=$S4_NG_ARGV (untested: the step no longer contains the line a control mutates)"; fi

# ---- row 6: mint-infra-app-token composite: the JWT exchange and the revoke. The JWT is minted inside the step from a synthetic RSA key (generated here), so no
# input makes the real guard refuse it: the refusal is SIMULATED by a copy of the library whose bc_curl refuses (the shape the real chokepoint returns) and the
# row asserts what the step does with it: a RED step naming the exchange, never an empty-response "returned no token" class and never a swallowed failure.
S4_MINT=".github/actions/mint-infra-app-token/action.yml"
S4_PEM="$("$REAL_OSSL" genrsa 2048 2>/dev/null)"; [[ "$S4_PEM" == *"PRIVATE KEY"* ]] || fatal "S4 row 6: could not generate a synthetic RSA key"
s4_body "$REPO_ROOT/$S4_MINT" "Mint installation token" "$S4/b-r6.sh"
S4_MINT_WS="$S4/ws-mintrefuse"; assert_fixture_dir "$S4_MINT_WS"; mkdir -p "$S4_MINT_WS/scripts/lib"
{ cat "$REPO_ROOT/scripts/lib/bearer-curl.sh"; printf '%s\n' 'bc_curl() { echo "bc_curl: JWT unusable" >&2; echo "SOLEUR_CREDENTIAL_REFUSED script=$1 reason=token_shape" >&2; return 2; }'; } > "$S4_MINT_WS/scripts/lib/bearer-curl.sh"
S4_MINT_RESP="{\"token\":\"${S4_GHS}\",\"permissions\":{\"actions\":\"write\",\"metadata\":\"read\"},\"repository_selection\":\"selected\",\"repositories\":[{\"name\":\"soleur\"}]}"
S4_MINT_BASE=(DOPPLER_TOKEN=synth-doppler-token DOPPLER_SOURCE=soleur-infra-app INSTALLATION_ID=166065653 'SCOPE_PERMISSIONS={"actions":"write"}' SCOPE_REPOSITORIES=soleur
  D_GITHUB_INFRA_APP_ID=123456 "D_GITHUB_INFRA_APP_PRIVATE_KEY=$S4_PEM" SHIM_PROFILE=generic SHIM_CODE=201)
s4_run r6-ok "$S4/b-r6.sh" "$S4/real" "${S4_MINT_BASE[@]}" "SHIM_BODY=$S4_MINT_RESP"
S4_JWT_LINE="$(s4_stdin_line 1 1)"; S4_JWT_V="${S4_JWT_LINE#header = \"Authorization: Bearer }"; S4_JWT_V="${S4_JWT_V%\"}"
if [[ "$S4_RC" == 0 && "$(s4_ncalls)" == 1 && "$(s4_markers)" == 0 ]] && s4_calls_ok 1 && [[ "$S4_JWT_V" =~ ^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$ ]] && s4_nowhere_on_argv "$S4_JWT_V" \
   && s4_gho_has "token=$S4_GHS" && [[ "$(jq -c . "$S4_ROW/calls/1.body")" == '{"repositories":["soleur"],"permissions":{"actions":"write"}}' ]]; then
  row "S4 row 6 mint exchange: a well-formed run sends the App JWT as the ONLY stdin header (none on a curl, python3 or openssl argument), the scoped body as the request body, and emits the installation token" ok
else row "S4 row 6 mint exchange: well-formed run" fail "rc=$S4_RC calls=$(s4_ncalls) markers=$(s4_markers)"; fi
s4_v_r6() { [[ "$S4_RC" != 0 && "$(s4_ncalls)" == 0 && "$(s4_markers)" == 1 ]] && s4_said 'the installation-token exchange did not complete (curl rc=2' && ! s4_said 'returned no token' && ! grep -q '^token=' "$S4_ROW/gho"; }
s4_run r6-refused "$S4/b-r6.sh" "$S4/real" "${S4_MINT_BASE[@]}" "SHIM_BODY=$S4_MINT_RESP" GITHUB_WORKSPACE="$S4_MINT_WS"; S4_REFUSAL_RUNS=$((S4_REFUSAL_RUNS + 1))
if s4_v_r6 && s4_canary_clean; then row "S4 row 6 mint exchange: a refused JWT (simulated at the library chokepoint: rc 2 and the marker) is a RED step that names the exchange (curl rc=2), with zero requests, no token output and the error text VISIBLE (neither swallowed nor read as 'returned no token')" ok
else row "S4 row 6 mint exchange: refused JWT" fail "rc=$S4_RC calls=$(s4_ncalls) markers=$(s4_markers)"; fi
S4_SW_BUILT=0; s4_body_try "$REPO_ROOT/$S4_MINT" "Mint installation token" "$S4/b-r6-swallow.sh" '|| curl_rc=$?' '|| true' && S4_SW_BUILT=1
if [[ "$S4_SW_BUILT" == 1 ]]; then s4_run ctl-r6-swallow "$S4/b-r6-swallow.sh" "$S4/real" "${S4_MINT_BASE[@]}" "SHIM_BODY=$S4_MINT_RESP" GITHUB_WORKSPACE="$S4_MINT_WS"; fi
if [[ "$S4_SW_BUILT" == 1 ]] && ! s4_v_r6 && [[ "$S4_RC" != 0 ]] && s4_said 'returned no token'; then row "S4 row 6 mint exchange control: swallowing the exchange (|| true) is judged RED (the refusal degrades to the 'returned no token' class)" ok
else row "S4 row 6 mint exchange control: a swallowed exchange is not judged red" fail "built=$S4_SW_BUILT rc=$S4_RC"; fi
# The revoke inside the step: a token whose grant differs from the request was ISSUED, so it is revoked with the same stdin channel (best effort) before the step fails.
S4_MINT_WRONG="{\"token\":\"${S4_GHS}\",\"permissions\":{\"contents\":\"write\",\"metadata\":\"read\"},\"repository_selection\":\"selected\",\"repositories\":[{\"name\":\"soleur\"}]}"
s4_run r6-revoke "$S4/b-r6.sh" "$S4/real" "${S4_MINT_BASE[@]}" "SHIM_BODY=$S4_MINT_WRONG"
if [[ "$S4_RC" != 0 && "$(s4_ncalls)" == 2 && "$(s4_stdin_line 2 1)" == "header = \"Authorization: Bearer $S4_GHS\"" && "$(s4_markers)" == 0 ]] && s4_calls_ok 1 && s4_argv_has DELETE && s4_nowhere_on_argv "$S4_GHS" \
   && s4_said 'differ from the requested' && ! grep -q '^token=' "$S4_ROW/gho"; then
  row "S4 row 6 mint revoke: a grant that differs from the request fails the step AFTER revoking the issued token, which rides the stdin channel only (none on any argv), and no token is emitted" ok
else row "S4 row 6 mint revoke: revoke path" fail "rc=$S4_RC calls=$(s4_ncalls)"; fi

# ---- row 5: apply-github-infra "Revoke the soleur-infra token" (best effort: a refusal is a WARNING and the step ends 0) ----
S4_AGI=".github/workflows/apply-github-infra.yml"
s4_body "$REPO_ROOT/$S4_AGI" "Revoke the soleur-infra token" "$S4/b-r5.sh"
S4_BASE=(REVOKE_TOKEN="$S4_GHS" SHIM_PROFILE=generic SHIM_CODE=204)
s4_run r5-ok "$S4/b-r5.sh" "$S4/real" "${S4_BASE[@]}"
if [[ "$S4_RC" == 0 && "$(s4_ncalls)" == 1 && "$(s4_markers)" == 0 && "$(s4_stdin_line 1 1)" == "header = \"Authorization: Bearer $S4_GHS\"" ]] && s4_calls_ok 1 && s4_nowhere_on_argv "$S4_GHS" && s4_argv_has DELETE && ! s4_said '::warning'; then
  row "S4 row 5 apply-github-infra revoke: a well-formed run sends the installation token as the only stdin header (none on argv) and a 204 raises no warning" ok
else row "S4 row 5 apply-github-infra revoke: well-formed run" fail "rc=$S4_RC calls=$(s4_ncalls)"; fi
s4_run r5-404 "$S4/b-r5.sh" "$S4/real" "${S4_BASE[@]}" SHIM_CODE=404
[[ "$S4_RC" == 0 && "$(s4_ncalls)" == 1 ]] && s4_said 'revoking the soleur-infra token returned HTTP 404' && row "S4 row 5 apply-github-infra revoke: a non-204 answer is the old warning (exit 0)" ok || row "S4 row 5 apply-github-infra revoke: non-204" fail "rc=$S4_RC"
s4_v_r5() { [[ "$S4_RC" == 0 && "$(s4_markers)" == 1 ]] && s4_said '::warning title=app-token-revoke::revoking the soleur-infra token returned HTTP 000' && ! s4_said 'revoking the soleur-infra token returned HTTP 204'; }
s4_sweep r5 "$S4/b-r5.sh" "$S4/real" s4_v_r5 "REVOKE_TOKEN" ""
s4_sweep_row "S4 row 5 apply-github-infra revoke (best effort): an empty, unset or hostile token reads as the old failed-revoke WARNING (HTTP 000, exit 0, never a failed job) with the marker once, zero requests and the canary absent"
s4_mutant_red "S4 row 5 apply-github-infra revoke control: a refusal swallowed into the SUCCESS code (|| code=204: the failed revoke raises no warning) is judged RED" "$REPO_ROOT/$S4_AGI" "Revoke the soleur-infra token" r5-swallow204 '|| code=000' '|| code=204' s4_v_r5 "REVOKE_TOKEN=${S4_CANARY}\"x"
s4_mutant_red "S4 row 5 apply-github-infra revoke control: a refusal swallowed into an EMPTY code (|| true: the warning no longer reads HTTP 000) is judged RED" "$REPO_ROOT/$S4_AGI" "Revoke the soleur-infra token" r5-swallowtrue '|| code=000' '|| true' s4_v_r5 "REVOKE_TOKEN=${S4_CANARY}\"x"
s4_run r5-nolib "$S4/b-r5.sh" "$S4/real" "${S4_BASE[@]}" GITHUB_WORKSPACE="$S4_EMPTYWS"
[[ "$S4_RC" == 0 && "$(s4_ncalls)" == 0 ]] && s4_said 'could not be loaded from the job checkout' && row "S4 row 5 apply-github-infra revoke: a checkout without the library warns and ends 0 (best effort), with zero requests and no argv fallback" ok || row "S4 row 5 apply-github-infra revoke: library absent" fail "rc=$S4_RC calls=$(s4_ncalls)"

# ---- row 3: deploy-inngest-image (INLINE wrapper; a dispatch-only job with no checkout). The trigger: a refusal is a RED step at the assignment (rc 2 under
# set -e), NOT the `Deploy webhook rejected (HTTP 000)` sentence, which would assert a cause nobody measured. The verify poll: the swallowed refusal ends in the
# poll's own timeout red, one marker per attempt. ----
S4_DII=".github/workflows/deploy-inngest-image.yml"
s4_body "$REPO_ROOT/$S4_DII" "Trigger deploy via webhook" "$S4/b-r3t.sh"
s4_body "$REPO_ROOT/$S4_DII" "Verify deploy completion" "$S4/b-r3v.sh" 'MAX_POLLS=120' 'MAX_POLLS=3'
S4_BASE=("${S4_WH_BASE[@]}" TAG=v1.2.3)
s4_run r3t-ok "$S4/b-r3t.sh" "$S4/real" "${S4_BASE[@]}"
if [[ "$S4_RC" == 0 && "$(s4_ncalls)" == 1 && "$(s4_markers)" == 0 ]] && s4_calls_ok 3 && s4_wh_ok "$S4_ROW/calls/1.body" 1 && s4_said 'initiated (HTTP 202)' && grep -q '^TRIGGER_TS=' "$S4_ROW/genv" \
   && grep -qF 'deploy inngest ghcr.io/jikig-ai/soleur-inngest-bootstrap v1.2.3' "$S4_ROW/calls/1.body"; then
  row "S4 row 3 deploy-inngest-image trigger (inline): a well-formed run signs the body it sends (independent digest over the recorded bytes), carries the pair on stdin, none on any argv, and records TRIGGER_TS" ok
else row "S4 row 3 deploy-inngest-image trigger (inline): well-formed run" fail "rc=$S4_RC calls=$(s4_ncalls) markers=$(s4_markers)"; fi
s4_v_r3t() { [[ "$S4_RC" != 0 && "$(s4_markers)" == 1 ]] && ! s4_said 'Deploy webhook rejected' && ! s4_said 'initiated (HTTP' && ! grep -q '^TRIGGER_TS=' "$S4_ROW/genv" \
  && s4_failmsg Deploy 2 && [[ "$S4_RC" == 2 ]]; }
s4_sweep r3t "$S4/b-r3t.sh" "$S4/real" s4_v_r3t "CF_ACCESS_CLIENT_ID CF_ACCESS_CLIENT_SECRET" "WEBHOOK_SECRET"
s4_sweep_row "S4 row 3 deploy-inngest-image trigger (inline, red class): an empty, unset or hostile credential is a RED step with ONE marker and zero requests, never the 'Deploy webhook rejected (HTTP 000)' sentence, with no TRIGGER_TS written and the canary absent"
s4_nopy_row "S4 row 3 deploy-inngest-image trigger (inline HMAC site): python3 absent is RED with the marker and zero requests, never the 'rejected (HTTP 000)' sentence" "$S4/b-r3t.sh" s4_v_r3t
S4_SHIM="$S4/shimreal"; s4_run r3t-transport "$S4/b-r3t.sh" "$S4/real" "${S4_BASE[@]}"; S4_SHIM="$S4/shim"
if [[ "$S4_RC" != 0 && "$(s4_markers)" == 0 ]] && ! s4_said 'initiated (HTTP' && s4_failmsg Deploy 7 && [[ "$S4_RC" == 7 ]]; then row "S4 row 3 deploy-inngest-image trigger: a REAL transport failure (closed port) is still RED and is not a refusal (no marker; the one failure line names rc=7 and the process exits with that code)" ok
else row "S4 row 3 deploy-inngest-image trigger: transport failure" fail "rc=$S4_RC markers=$(s4_markers)"; fi
S4_H0_BUILT=0; s4_body_try "$REPO_ROOT/$S4_DII" "Trigger deploy via webhook" "$S4/b-r3t-http000.sh" '"https://deploy.soleur.ai/hooks/deploy")' '"https://deploy.soleur.ai/hooks/deploy") || HTTP_CODE=000' && S4_H0_BUILT=1
if [[ "$S4_H0_BUILT" == 1 ]]; then s4_run ctl-r3t-http000 "$S4/b-r3t-http000.sh" "$S4/real" "${S4_BASE[@]}" "CF_ACCESS_CLIENT_ID=${S4_CANARY}\"x"; fi
if [[ "$S4_H0_BUILT" == 1 ]] && ! s4_v_r3t && s4_said 'Deploy webhook rejected (HTTP 000)'; then row "S4 row 3 deploy-inngest-image trigger control: mapping the refusal to HTTP_CODE=000 (|| HTTP_CODE=000) is judged RED (it prints the asserted-cause 'rejected (HTTP 000)' sentence)" ok
else row "S4 row 3 deploy-inngest-image trigger control: the HTTP_CODE=000 mutant is not judged red" fail "built=$S4_H0_BUILT rc=$S4_RC"; fi
# the verify poll (3 polls here): the swallowed refusal is the poll's OWN terminal red, one marker per attempt
s4_frame_dii="{\"component\":\"inngest\",\"exit_code\":0,\"reason\":\"success\",\"start_ts\":$((S4_NOW + 5))}"
S4_BASE=("${S4_WH_BASE[@]}" TAG=v1.2.3 TRIGGER_TS="$S4_NOW" "SHIM_STATUS_BODY=$s4_frame_dii")
s4_run r3v-ok "$S4/b-r3v.sh" "$S4/real" "${S4_BASE[@]}"
if [[ "$S4_RC" == 0 && "$(s4_ncalls)" == 1 && "$(s4_markers)" == 0 ]] && s4_calls_ok 3 && s4_wh_ok "$S4/bodies/empty" 1 && s4_said 'Inngest deploy v1.2.3 completed (reason=success)'; then
  row "S4 row 3 deploy-inngest-image verify (inline): a well-formed poll carries the digest over the empty body and the pair on stdin and reads this run's success frame" ok
else row "S4 row 3 deploy-inngest-image verify (inline): well-formed run" fail "rc=$S4_RC calls=$(s4_ncalls) markers=$(s4_markers)"; fi
s4_v_r3v() { [[ "$S4_RC" != 0 && "$(s4_markers)" == 3 ]] && s4_said '::error::Deploy verify timed out after 15s' && ! s4_said 'completed (reason'; }
s4_sweep r3v "$S4/b-r3v.sh" "$S4/real" s4_v_r3v "CF_ACCESS_CLIENT_ID CF_ACCESS_CLIENT_SECRET" "WEBHOOK_SECRET"
s4_sweep_row "S4 row 3 deploy-inngest-image verify (inline): an empty, unset or hostile credential is the poll's old terminal RED (timed out) with ONE marker per attempt (3 here), zero requests and the canary absent"
s4_nopy_row "S4 row 3 deploy-inngest-image verify (inline HMAC site): python3 absent reaches the same terminal red with the marker per attempt" "$S4/b-r3v.sh" s4_v_r3v
S4_FABRICATE=">/dev/null || printf '%s' '{\"exit_code\":0,\"component\":\"inngest\",\"reason\":\"success\",\"start_ts\":9999999999}' > /tmp/status-body"
s4_mutant_red "S4 row 3 deploy-inngest-image verify control: a refused status read swallowed into a fabricated SUCCESS frame (|| printf ... > status-body instead of || true) is judged RED (the step would report a deploy that was never checked)" "$REPO_ROOT/$S4_DII" "Verify deploy completion" r3v-fabricate '>/dev/null || true' "$S4_FABRICATE" s4_v_r3v "CF_ACCESS_CLIENT_ID=${S4_CANARY}\"x"

# ---- the inline sites' call-site TRIM (ADR-280, decision 7 for the inline form). Each inline-using step runs ONE line before the pinned guard that trims LEADING and TRAILING ASCII
# whitespace (space, tab, CR, LF, VT, FF; byte classes written out, never `[[:space:]]`, so the judgement does not follow the runner's locale) of the Cloudflare Access id and
# secret (the two email steps: of RESEND_API_KEY). The HMAC key is never trimmed. A stored value with a trailing newline or space is the commonest storage accident, and the old
# argv form tolerated a leading blank too (curl sent it and the edge discards leading whitespace of a field value). The loop's text is the CANONICAL spelling below; what the
# battery asserts about it is (a) a DERIVED population row (every step that defines the inline `_bearer_ok() {` and declares a GitHub `secrets.` value for one of the three names
# carries exactly that loop for exactly those names BEFORE the definition, and the eight hand-listed executed steps are that population), and (b) executed rows that DISCRIMINATE the
# shape: leading and trailing mixed whitespace trimmed and the clean value sent; interior space or LF refused (strip-all would send a different credential); an interior control
# byte, all-whitespace and U+2003 (leading, trailing, under a UTF-8 locale so a `[[:space:]]` implementation is seen) refused; the HMAC key untrimmed.
IFS= read -r -d '' s4_trim_py <<'PY' || true
import sys
WS = r"""$' \t\r\n\v\f'"""
kind, names = sys.argv[1], sys.argv[2]
lead = '_t="${_t#"${_t%%[!' + WS + ']*}"}"; '
trail = '_t="${_t%"${_t##*[!' + WS + ']}"}"; '
llead = '_t="${_t#"${_t%%[![:space:]]*}"}"; '
ltrail = '_t="${_t%"${_t##*[![:space:]]}"}"; '
body = {"canon": lead + trail, "lead": lead, "trail": trail, "locale": llead + ltrail,
        "stripall": '_t="${_t//[' + WS + ']/}"; ', "remove": ""}[kind]
print('for _v in ' + names + '; do _t="${!_v:-}"; ' + body + 'printf -v "$_v" \'%s\' "$_t"; done')
PY
# The derived population: workflow steps whose run body defines the inline `_bearer_ok() {` and whose effective env (workflow, job, step) declares a `secrets.` value for one of the
# three names. scan <root> prints "<file>\t<job>\t<step name>\t<step id>\t<names>\t<ok|BAD>" (ok: exactly one `for _v in` line precedes the definition and it IS the canonical loop for
# exactly those names); cover <root> <covered-file> prints UNCOVERED <file> <step> for a derived step no executed row names and STALE <entry> for an executed entry that is not derived.
IFS= read -r -d '' s4_b7_py <<'PY' || true
import sys, os, re, glob, subprocess, yaml
mode, root = sys.argv[1], sys.argv[2]
TV = ["CF_ACCESS_CLIENT_ID", "CF_ACCESS_CLIENT_SECRET", "RESEND_API_KEY"]
trim_py = os.environ["S4_TRIM_PY"]
def canon(names):
    return subprocess.run([sys.executable, "-I", "-c", trim_py, "canon", names], capture_output=True, text=True, check=True).stdout.strip()
rows = []
for path in sorted(glob.glob(os.path.join(root, ".github", "workflows", "*.yml"))):
    rel = os.path.relpath(path, root)
    d = yaml.safe_load(open(path))
    if not isinstance(d, dict): continue
    wenv = d.get("env") if isinstance(d.get("env"), dict) else {}
    for jid, j in (d.get("jobs") or {}).items():
        if not isinstance(j, dict): continue
        jenv = j.get("env") if isinstance(j.get("env"), dict) else {}
        for idx, s in enumerate(j.get("steps") or []):
            if not isinstance(s, dict) or not isinstance(s.get("run"), str): continue
            lines = [l.strip() for l in s["run"].split("\n")]
            di = next((i for i, l in enumerate(lines) if l.startswith("_bearer_ok() {")), None)
            if di is None: continue
            env = {}
            for e in (wenv, jenv, s.get("env") if isinstance(s.get("env"), dict) else {}): env.update(e)
            vs = [v for v in TV if "secrets." in str(env.get(v, ""))]
            if not vs: continue
            loops = [l for l in lines[:di] if l.startswith("for _v in ")]
            ok = loops == [canon(" ".join(vs))]
            rows.append((rel, jid, str(s.get("name") or ""), str(s.get("id") or ""), ",".join(vs), "ok" if ok else "BAD"))
if mode == "scan":
    for r in rows: print("\t".join(r))
else:
    cov = [l.rstrip("\n") for l in open(sys.argv[3]) if l.strip()]
    used = set()
    for rel, jid, name, sid, vs, st in rows:
        hit = [c for c in cov if c.split("|", 1)[0] == rel and (name.startswith(c.split("|", 1)[1]) or (sid and sid == c.split("|", 1)[1]))]
        used.update(hit)
        if not hit: print("UNCOVERED %s %s" % (rel, name or sid))
    for c in cov:
        if c not in used: print("STALE %s" % c)
PY
export S4_TRIM_PY="$s4_trim_py"
S4_B7_COVERED="$S4/b7-covered.txt"; : > "$S4_B7_COVERED"
S4_U2003=$'\xe2\x80\x83'
# The UTF-8 instrument: a `[[:space:]]` implementation only differs from the byte class under a UTF-8 locale, so the U+2003 rows run the step with LC_ALL=C.UTF-8 and need a bash
# that classifies U+2003 as space there (a locale-less host would let the locale-class mutant pass every row).
printf '%s\n' '[[ $'"'"'\xe2\x80\x83'"'"' == [[:space:]] ]] && echo yes' > "$S4/utf8probe.sh"
S4_UTF8_OK=0; [[ "$(env -i LC_ALL=C.UTF-8 "$BASH_BIN" --noprofile --norc "$S4/utf8probe.sh" 2>/dev/null)" == yes ]] && S4_UTF8_OK=1
[[ "$(env -i LC_ALL=C "$BASH_BIN" --noprofile --norc "$S4/utf8probe.sh" 2>/dev/null)" != yes ]] || S4_UTF8_OK=0   # the C locale must NOT classify it (the byte class and [[:space:]] must differ somewhere)
S4_B7_N=0; S4_B7_BAD=""
S4_B7_ID_MIX=$' \t'"${S4_CFID}"$' \t\r\n\v\f'; S4_B7_SEC_MIX=$'\r\n'"${S4_CFSEC}"$' '
S4_B7_ID_SP="${S4_CFID:0:8} ${S4_CFID:8}"; S4_B7_SEC_SP="${S4_CFSEC:0:8} ${S4_CFSEC:8}"; S4_B7_SEC_LF="${S4_CFSEC:0:8}"$'\n'"${S4_CFSEC:8}"
S4_B7_ID_X="${S4_CFID:0:8}"$'\001'"${S4_CFID:8}"; S4_B7_SEC_X="${S4_CFSEC:0:8}"$'\001'"${S4_CFSEC:8}"
S4_B7_KEY_NL="${S4_KEY}"$'\n'
S4_B7_SCEN_WH="trim interior-space interior-lf ctlbyte allws u2003 key"
S4_B7_SCEN_RS="trim interior-space ctlbyte allws u2003"
# s4_b7_refused <label> <body> <said> <mode> <NAME=value>...: the run makes ZERO requests, prints the marker, and does not reach the arm's success.
s4_b7_refused() {
  local l="$1" b="$2" s="$3" m="$4"; shift 4
  s4_run "$l" "$b" "$S4/real" "$@"; S4_REFUSAL_RUNS=$((S4_REFUSAL_RUNS + 1))
  [[ "$(s4_ncalls)" == 0 && "$(s4_markers)" -ge 1 ]] || return 1
  if [[ "$m" == resend-gho ]]; then ! s4_gho_has 'delivered=1'; elif [[ -n "$s" ]]; then ! s4_said "$s"; fi
}
# s4_b7_bad <tag> <body> <mode wh-post|wh-empty|resend-hdr|resend-gho> <said> "<scenarios>" <NAME=value>...: sets S4_B7_BAD to the NAMED scenarios that failed (empty = all held).
s4_b7_bad() {
  local tag="$1" body="$2" mode="$3" said="$4" scen="$5" sc f want got v; shift 5
  local -a base=("$@")
  S4_B7_BAD=""
  for sc in $scen; do
    case "$mode:$sc" in
      wh-*:trim)
        s4_run "b7-$tag-trim" "$body" "$S4/real" "${base[@]}" "CF_ACCESS_CLIENT_ID=$S4_B7_ID_MIX" "CF_ACCESS_CLIENT_SECRET=$S4_B7_SEC_MIX"
        f="$S4/bodies/empty"; [[ "$mode" == wh-post ]] && f="$S4_ROW/calls/1.body"
        { [[ "$S4_RC" == 0 && "$(s4_ncalls)" == 1 && "$(s4_markers)" == 0 ]] && s4_calls_ok 3 && s4_wh_ok "$f" 1 && s4_said "$said"; } || S4_B7_BAD+=" trim(rc=$S4_RC calls=$(s4_ncalls) markers=$(s4_markers))" ;;
      wh-*:interior-space)
        for v in "CF_ACCESS_CLIENT_ID=$S4_B7_ID_SP" "CF_ACCESS_CLIENT_SECRET=$S4_B7_SEC_SP"; do
          s4_b7_refused "b7-$tag-ctl-space" "$body" "$said" "$mode" "${base[@]}" "$v" || S4_B7_BAD+=" interior-space-${v%%=*}(calls=$(s4_ncalls) markers=$(s4_markers))"
        done ;;
      wh-*:interior-lf)
        s4_b7_refused "b7-$tag-ctl-lf" "$body" "$said" "$mode" "${base[@]}" "CF_ACCESS_CLIENT_SECRET=$S4_B7_SEC_LF" || S4_B7_BAD+=" interior-lf(calls=$(s4_ncalls) markers=$(s4_markers))" ;;
      wh-*:ctlbyte)
        for v in "CF_ACCESS_CLIENT_ID=$S4_B7_ID_X" "CF_ACCESS_CLIENT_SECRET=$S4_B7_SEC_X"; do
          s4_b7_refused "b7-$tag-ctlbyte" "$body" "$said" "$mode" "${base[@]}" "$v" || S4_B7_BAD+=" ctlbyte-${v%%=*}(calls=$(s4_ncalls) markers=$(s4_markers))"
        done ;;
      wh-*:allws)
        for v in "CF_ACCESS_CLIENT_ID=$S4_B7_ID_MIX_ALL" "CF_ACCESS_CLIENT_SECRET=$S4_B7_ID_MIX_ALL"; do
          s4_b7_refused "b7-$tag-ctl-allws" "$body" "$said" "$mode" "${base[@]}" "$v" || S4_B7_BAD+=" allws-${v%%=*}(calls=$(s4_ncalls) markers=$(s4_markers))"
        done ;;
      wh-*:u2003)
        if [[ "$S4_UTF8_OK" != 1 ]]; then S4_B7_BAD+=" u2003(no UTF-8 locale on this host: the [[:space:]] mutant would pass)"; continue; fi
        s4_b7_refused "b7-$tag-ctl-u2003t" "$body" "$said" "$mode" "${base[@]}" LC_ALL=C.UTF-8 "CF_ACCESS_CLIENT_ID=${S4_CFID}${S4_U2003}" || S4_B7_BAD+=" u2003-trailing(calls=$(s4_ncalls) markers=$(s4_markers))"
        s4_b7_refused "b7-$tag-ctl-u2003l" "$body" "$said" "$mode" "${base[@]}" LC_ALL=C.UTF-8 "CF_ACCESS_CLIENT_SECRET=${S4_U2003}${S4_CFSEC}" || S4_B7_BAD+=" u2003-leading(calls=$(s4_ncalls) markers=$(s4_markers))" ;;
      wh-*:key)
        s4_run "b7-$tag-key" "$body" "$S4/real" "${base[@]}" "WEBHOOK_SECRET=$S4_B7_KEY_NL"
        f="$S4/bodies/empty"; [[ "$mode" == wh-post ]] && f="$S4_ROW/calls/1.body"
        want="$(s4_oracle "$S4_B7_KEY_NL" "$f")"; got="$(s4_oracle "$S4_KEY" "$f")"
        { [[ "$(s4_ncalls)" == 1 && "$(s4_markers)" == 0 && -n "$want" && "$want" != "$got" && "$(s4_stdin_line 1 1)" == "header = \"X-Signature-256: sha256=$want\"" ]] && s4_nowhere_on_argv "$want"; } || S4_B7_BAD+=" key-not-trimmed(calls=$(s4_ncalls) markers=$(s4_markers))" ;;
      resend-*:trim)
        s4_run "b7-$tag-trim" "$body" "$S4/real" "${base[@]}" "RESEND_API_KEY=${S4_B7_RS_MIX}"
        { [[ "$S4_RC" == 0 && "$(s4_ncalls)" == 1 && "$(s4_markers)" == 0 && "$(s4_stdin_line 1 1)" == "header = \"Authorization: Bearer $S4_RESEND\"" ]] && s4_calls_ok 1 && s4_nowhere_on_argv "$S4_RESEND"; } || S4_B7_BAD+=" trim(rc=$S4_RC calls=$(s4_ncalls) markers=$(s4_markers))"
        if [[ "$mode" == resend-gho ]]; then s4_gho_has 'delivered=1' || S4_B7_BAD+=" not-delivered"; else s4_said "$said" || S4_B7_BAD+=" no-success-line"; fi ;;
      resend-*:interior-space)
        s4_b7_refused "b7-$tag-ctl-space" "$body" "$said" "$mode" "${base[@]}" "RESEND_API_KEY=${S4_RESEND:0:6} ${S4_RESEND:6}" || S4_B7_BAD+=" interior-space(calls=$(s4_ncalls) markers=$(s4_markers))" ;;
      resend-*:ctlbyte)
        s4_b7_refused "b7-$tag-ctlbyte" "$body" "$said" "$mode" "${base[@]}" "RESEND_API_KEY=${S4_RESEND:0:6}"$'\001'"${S4_RESEND:6}" || S4_B7_BAD+=" ctlbyte(calls=$(s4_ncalls) markers=$(s4_markers))" ;;
      resend-*:allws)
        s4_b7_refused "b7-$tag-ctl-allws" "$body" "$said" "$mode" "${base[@]}" "RESEND_API_KEY=$S4_B7_ID_MIX_ALL" || S4_B7_BAD+=" allws(calls=$(s4_ncalls) markers=$(s4_markers))" ;;
      resend-*:u2003)
        if [[ "$S4_UTF8_OK" != 1 ]]; then S4_B7_BAD+=" u2003(no UTF-8 locale on this host: the [[:space:]] mutant would pass)"; continue; fi
        s4_b7_refused "b7-$tag-ctl-u2003t" "$body" "$said" "$mode" "${base[@]}" LC_ALL=C.UTF-8 "RESEND_API_KEY=${S4_RESEND}${S4_U2003}" || S4_B7_BAD+=" u2003-trailing(calls=$(s4_ncalls) markers=$(s4_markers))"
        s4_b7_refused "b7-$tag-ctl-u2003l" "$body" "$said" "$mode" "${base[@]}" LC_ALL=C.UTF-8 "RESEND_API_KEY=${S4_U2003}${S4_RESEND}" || S4_B7_BAD+=" u2003-leading(calls=$(s4_ncalls) markers=$(s4_markers))" ;;
      *) S4_B7_BAD+=" unknown-scenario($mode:$sc)" ;;
    esac
  done
}
S4_B7_ID_MIX_ALL=$' \t\r\n\v\f'
S4_B7_RS_MIX=$'\t '"${S4_RESEND}"$' \r\n'
s4_b7_step() { # <tag> <body> <mode> <said> <NAME=value>...: one of the eight executed inline steps, every scenario
  local tag="$1" body="$2" mode="$3" said="$4" scen="$S4_B7_SCEN_WH"; shift 4
  [[ "$mode" == resend-* ]] && scen="$S4_B7_SCEN_RS"
  S4_B7_N=$((S4_B7_N + 1)); printf '%s\n' "${S4_BODY_SRC[$body]:-unbuilt|$body}" >> "$S4_B7_COVERED"
  s4_b7_bad "$tag" "$body" "$mode" "$said" "$scen" "$@"
  if [[ -z "$S4_B7_BAD" ]]; then row "S4 inline trim $tag: leading and trailing ASCII whitespace (space, tab, CR, LF, VT, FF) of the stored credential is trimmed at the call site and the clean value is what is sent; interior space or LF, an interior control byte, all-whitespace and U+2003 (leading and trailing, under a UTF-8 locale) are still refused$([[ "$mode" == wh-* ]] && echo ", and the HMAC key is NOT trimmed (it signs as the exact key it was given)")" ok
  else row "S4 inline trim $tag: the call-site trim, an interior/non-ASCII refusal or the untrimmed key" fail "$S4_B7_BAD"; fi
}
S4_B7_REL=("${S4_WH_BASE[@]}" "${S4_REL_ENV[@]}")
mapfile -t S4_PEER_JOBENV < <(s4_jobenv "$REPO_ROOT/$S4_WFR" verify-peer-deploy)
S4_B7_PEERREL=("${S4_WH_BASE[@]}" "${S4_PEER_JOBENV[@]}" VERSION=1.2.3)
S4_B7_BASE_DEPLOY=("${S4_B7_REL[@]}" WEB_HOST_PRIVATE_IPS=10.0.1.10,10.0.1.11)
S4_B7_BASE_FAILMAIL=(MIRROR_VERIFIED=true RUN_URL=https://example.invalid/run VERSION=1.2.3 SHIM_PROFILE=generic)
s4_b7_step release-lock-probe "$S4/b-r8.sh" wh-empty 'Pre-rerun probe: no in-flight deploy (exit_code=0)' "${S4_WH_BASE[@]}" "${S4_REL_JOBENV[@]}" 'SHIM_STATUS_BODY={"exit_code":0}'
s4_b7_step release-deploy "$S4/b-r9.sh" wh-post 'Deploy initiated (HTTP 202)' "${S4_B7_BASE_DEPLOY[@]}"
s4_b7_step release-verify "$S4/b-r10.sh" wh-empty 'ci-deploy.sh completed successfully for v1.2.3' "${S4_B7_REL[@]}" STATUS_POLL_MAX_ATTEMPTS=3 STATUS_POLL_INTERVAL_S=0 'SHIM_STATUS_BODY={"exit_code":0,"reason":"ok","tag":"v1.2.3"}'
s4_b7_step release-peer-verify "$S4/b-r10p.sh" wh-empty 'All expected peers reported v1.2.3 deploy completion' "${S4_B7_PEERREL[@]}" STATUS_POLL_MAX_ATTEMPTS=3 STATUS_POLL_INTERVAL_S=0 'SHIM_STATUS_BODY={"exit_code":0,"reason":"ok","tag":"v1.2.3","peers":{"10.0.1.11":{"exit_code":0,"reason":"ok","tag":"v1.2.3"}}}'
s4_b7_step release-deploy-failed-email "$S4/b-r11.sh" resend-hdr 'Deploy-failure email sent to ops@jikigai.com (HTTP 200)' "${S4_B7_BASE_FAILMAIL[@]}"
s4_b7_step release-outcome-email "$S4/b-r12.sh" resend-gho '' CLASSIFIER=failure FAILED=live-verify 'FAILED_HTML=<li>live-verify</li>' R_DEPLOY=failure TAG=v1.2.3 VERSION=1.2.3 RUN_URL=https://example.invalid/run SHIM_PROFILE=generic
s4_b7_step deploy-inngest-trigger "$S4/b-r3t.sh" wh-post 'initiated (HTTP 202)' "${S4_WH_BASE[@]}" TAG=v1.2.3
s4_b7_step deploy-inngest-verify "$S4/b-r3v.sh" wh-empty 'Inngest deploy v1.2.3 completed (reason=success)' "${S4_WH_BASE[@]}" TAG=v1.2.3 TRIGGER_TS="$S4_NOW" "SHIM_STATUS_BODY=$s4_frame_dii"

# POPULATION: the executed steps above ARE the derived population (no hand list can drift from the YAML), the count is held to a floor, and the derivation is fed a must-FAIL
# fixture (a step that defines the inline guard and declares the secret but has no trim loop, one whose loop comes after the definition, one that trims the wrong names, a job-level
# secret) and must-PASS controls (a canonical step; steps outside the population: a definer without a secret, a secret without a definer).
S4_B7_DERIVED="$(cd "$REPO_ROOT" && python3 -I -c "$s4_b7_py" scan "$REPO_ROOT")"
S4_B7_DERIVED_N="$(grep -c . <<<"$S4_B7_DERIVED" || true)"; S4_B7_BADN="$(grep -c $'\tBAD$' <<<"$S4_B7_DERIVED" || true)"
S4_B7_COVER="$(cd "$REPO_ROOT" && python3 -I -c "$s4_b7_py" cover "$REPO_ROOT" "$S4_B7_COVERED")"
S4_B7_FLOOR=8
if [[ "$S4_B7_BADN" == 0 && -z "$S4_B7_COVER" && "$S4_B7_DERIVED_N" == "$S4_B7_N" && "$S4_B7_DERIVED_N" -ge "$S4_B7_FLOOR" ]]; then
  row "S4 inline trim population: every workflow step that defines the inline _bearer_ok and declares a secrets.* value for CF_ACCESS_CLIENT_ID, CF_ACCESS_CLIENT_SECRET or RESEND_API_KEY carries exactly the canonical trim loop for exactly those names before the definition, and the $S4_B7_N executed rows are exactly that derived population ($S4_B7_DERIVED_N steps; floor $S4_B7_FLOOR)" ok
else row "S4 inline trim population: a derived step lacks the canonical trim, no executed row covers it, or the population is below its floor" fail "bad=$S4_B7_BADN derived=$S4_B7_DERIVED_N executed=$S4_B7_N floor=$S4_B7_FLOOR cover='${S4_B7_COVER//$'\n'/;}' bad-steps='$(grep $'\tBAD$' <<<"$S4_B7_DERIVED" | cut -f1,3 | tr '\t\n' ': ;')'"; fi
S4_B7F="$S4/b7fix"; assert_fixture_dir "$S4_B7F"
s4_b7_fix() { # <name> <env block> <run-body prelude> : writes <name>/.github/workflows/w.yml
  local t="$S4_B7F/$1"; assert_fixture_dir "$t"; mkdir -p "$t/.github/workflows"
  { printf '%s\n' 'name: fixture' 'on: push' "$3" 'jobs:' '  j:' '    runs-on: ubuntu-latest'
    printf '%s\n' "$4" '    steps:' '      - name: fixture step'; printf '%s\n' "$2"; printf '%s\n' '        run: |' "$5" '          _bearer_ok() { :; }'; } > "$t/.github/workflows/w.yml"
  printf '%s' "$t"
}
S4_B7_CANON2="$(python3 -I -c "$s4_trim_py" canon 'CF_ACCESS_CLIENT_ID CF_ACCESS_CLIENT_SECRET')"
S4_B7_ENV2=$'        env:\n          CF_ACCESS_CLIENT_ID: ${{ secrets.CF_ACCESS_CLIENT_ID }}\n          CF_ACCESS_CLIENT_SECRET: ${{ secrets.CF_ACCESS_CLIENT_SECRET }}'
S4_B7_F_OK="$(s4_b7_fix ok "$S4_B7_ENV2" '' '' "          $S4_B7_CANON2")"
S4_B7_F_NOLOOP="$(s4_b7_fix noloop "$S4_B7_ENV2" '' '' '          echo hi')"
S4_B7_F_WRONG="$(s4_b7_fix wrongnames "$S4_B7_ENV2" '' '' "          $(python3 -I -c "$s4_trim_py" canon 'CF_ACCESS_CLIENT_ID')")"
S4_B7_F_REMOVED="$(s4_b7_fix removed "$S4_B7_ENV2" '' '' "          $(python3 -I -c "$s4_trim_py" remove 'CF_ACCESS_CLIENT_ID CF_ACCESS_CLIENT_SECRET')")"
S4_B7_F_JOB="$(s4_b7_fix jobenv $'        env:\n          X: y' '' $'    env:\n      CF_ACCESS_CLIENT_ID: ${{ secrets.A }}' '          echo hi')"
S4_B7_F_NOSECRET="$(s4_b7_fix nosecret $'        env:\n          CF_ACCESS_CLIENT_ID: ${{ vars.CF_ACCESS_CLIENT_ID }}' '' '' '          echo hi')"
s4_b7_after() {
  local t="$S4_B7F/after"
  assert_fixture_dir "$t"
  mkdir -p "$t/.github/workflows"
  {
    printf '%s\n' 'name: fixture' 'on: push' 'jobs:' '  j:' '    runs-on: ubuntu-latest' '    steps:' '      - name: fixture step'
    printf '%s\n' "$S4_B7_ENV2"
    printf '%s\n' '        run: |' '          _bearer_ok() { :; }' "          $S4_B7_CANON2"
  } > "$t/.github/workflows/w.yml"
  printf '%s' "$t"
}
S4_B7_F_AFTER="$(s4_b7_after)"
s4_b7_status() { python3 -I -c "$s4_b7_py" scan "$1" | cut -f6 | paste -sd,; }
S4_B7_FX_BAD=""
[[ "$(s4_b7_status "$S4_B7_F_OK")" == ok ]] || S4_B7_FX_BAD+=" ok-fixture($(s4_b7_status "$S4_B7_F_OK"))"
for fx in NOLOOP WRONG REMOVED JOB AFTER; do
  fxv="S4_B7_F_$fx"; fxd="${!fxv}"; [[ "$(s4_b7_status "$fxd")" == BAD ]] || S4_B7_FX_BAD+=" $fx($(s4_b7_status "$fxd"))"
done
[[ -z "$(s4_b7_status "$S4_B7_F_NOSECRET")" ]] || S4_B7_FX_BAD+=" nosecret-in-population"
if [[ -z "$S4_B7_FX_BAD" ]]; then row "S4 inline trim population control: the derivation passes a canonical step and reports a step with the guard and the secret but no trim loop, a loop for the wrong names, a removed (no-op) loop, a loop after the definition, and a job-level secret as BAD, and leaves a definer without a secret out of the population" ok
else row "S4 inline trim population control: the derivation is blind to a missing, misplaced or mis-named trim" fail "$S4_B7_FX_BAD"; fi
# MUTANTS of the loop, each built from the REAL step (a line that no longer matches fails its own row, never the battery) and judged by the very predicate above: each must go RED on
# a NAMED scenario and stay green on the ones it still satisfies (a trim that handles only one end, one that strips interior whitespace too, one that follows the runner locale, and
# the loop applied to the HMAC key).
s4_b7_mut() { # <kind> "<scenarios>" "<must be red>" "<must stay green>" [key]
  local kind="$1" scen="$2" red="$3" green="$4" key="${5:-}" wvars='CF_ACCESS_CLIENT_ID CF_ACCESS_CLIENT_SECRET' tok miss="" canon mut
  canon="$(python3 -I -c "$s4_trim_py" canon "$wvars")"
  if [[ -n "$key" ]]; then mut="$(python3 -I -c "$s4_trim_py" canon "$wvars WEBHOOK_SECRET")"; else mut="$(python3 -I -c "$s4_trim_py" "$kind" "$wvars")"; fi
  if s4_body_try "$REPO_ROOT/$S4_WFR" "Deploy via webhook" "$S4/b-ctl-b7-$kind.sh" "$canon" "$mut"; then
    s4_b7_bad "ctl-$kind-wh" "$S4/b-ctl-b7-$kind.sh" wh-post 'Deploy initiated (HTTP 202)' "$scen" "${S4_B7_BASE_DEPLOY[@]}"
    for tok in $red; do [[ "$S4_B7_BAD" == *"$tok"* ]] || miss+=" wh:$tok-not-red"; done
    for tok in $green; do [[ "$S4_B7_BAD" != *"$tok"* ]] || miss+=" wh:$tok-red"; done
  else miss+=" not-built(wh)"; fi
  if [[ -z "$key" ]]; then
    canon="$(python3 -I -c "$s4_trim_py" canon RESEND_API_KEY)"; mut="$(python3 -I -c "$s4_trim_py" "$kind" RESEND_API_KEY)"
    if s4_body_try "$REPO_ROOT/$S4_WFR" "Email notification (deploy FAILED)" "$S4/b-ctl-b7-$kind-rs.sh" "$canon" "$mut"; then
      s4_b7_bad "ctl-$kind-rs" "$S4/b-ctl-b7-$kind-rs.sh" resend-hdr 'Deploy-failure email sent to ops@jikigai.com (HTTP 200)' "$scen" "${S4_B7_BASE_FAILMAIL[@]}"
      for tok in $red; do [[ "$S4_B7_BAD" == *"$tok"* ]] || miss+=" resend:$tok-not-red"; done
      for tok in $green; do [[ "$S4_B7_BAD" != *"$tok"* ]] || miss+=" resend:$tok-red"; done
    else miss+=" not-built(resend)"; fi
  fi
  S4_B7_MISS="$miss"
}
s4_b7_mut_row() { # <description> <kind> ...
  local d="$1"; shift; s4_b7_mut "$@"
  if [[ -z "$S4_B7_MISS" ]]; then row "S4 inline trim control: $d" ok; else row "S4 inline trim control: $d" fail "$S4_B7_MISS"; fi
}
s4_b7_mut_row "removing the trim loop (a no-op loop) is RED on the trim scenario at a CF step and a Resend step" remove "trim" "trim" ""
s4_b7_mut_row "a trailing-only trim is RED on the trim scenario (a leading blank is refused) at both step forms" trail "trim" "trim" ""
s4_b7_mut_row "a leading-only trim is RED on the trim scenario (a trailing newline is refused) at both step forms" lead "trim" "trim" ""
s4_b7_mut_row "a strip-all-whitespace trim is RED on the interior-space scenario (it would send a different credential) and still trims" stripall "trim interior-space" "interior-space" "trim"
s4_b7_mut_row "a locale-class ([[:space:]]) trim is RED on the U+2003 scenario under a UTF-8 locale and still trims ASCII" locale "trim u2003" "u2003" "trim"
s4_b7_mut_row "applying the loop to the HMAC key as well is RED on the key scenario (the key must sign exactly as given)" key "key" "key-not-trimmed" "" key

# ---- rows 16 and 17: apply-deploy-pipeline-fix. Row 16 "Redeploy to load applied profile" (library; the baseline read, the settle re-read, the POST and the poll
# share one credential set) and row 17 "Verify journald_storage" (three attempts). Both read their credentials through doppler (stubbed by secret NAME). ----
S4_CWD="$REPO_ROOT/apps/web-platform/infra"
s4_body "$REPO_ROOT/$S4_DPF" "Redeploy to load applied profile" "$S4/b-r16.sh"
s4_body "$REPO_ROOT/$S4_DPF" "Verify journald_storage" "$S4/b-r17.sh"
S4_SECCOMP_SHA="$(sha256sum "$REPO_ROOT/apps/web-platform/infra/seccomp-bwrap.json" | cut -d' ' -f1)"
s4_seccomp_frame() { # <loaded_matches> <start_ts> [extra json members]
  printf '{"seccomp_profile_host_present":true,"seccomp_profile_host_sha256":"%s","seccomp_profile_loaded_matches_host":%s,"tag":"v1.2.3","component":"web-platform","reason":"ok","exit_code":0,"start_ts":%s%s}' "$S4_SECCOMP_SHA" "$1" "$2" "${3:-}"; }
# the fast path: the container already enforces the committed profile, so the step makes ONE signed read and ends 0
S4_BASE=("${S4_DOP_BASE[@]}" "SHIM_STATUS_BODY=$(s4_seccomp_frame true 1700000123)")
s4_run r16-fast "$S4/b-r16.sh" "$S4/real" "${S4_BASE[@]}"
if [[ "$S4_RC" == 0 && "$(s4_ncalls)" == 1 && "$(s4_markers)" == 0 ]] && s4_calls_ok 3 && s4_wh_ok "$S4/bodies/empty" 1 && s4_said 'already enforcing the committed profile'; then
  row "S4 row 16 redeploy (fast path): a well-formed baseline read carries the digest over the empty body and the pair on stdin and finds the profile already enforced" ok
else row "S4 row 16 redeploy (fast path): well-formed run" fail "rc=$S4_RC calls=$(s4_ncalls) markers=$(s4_markers)"; fi
# the full path: stale baseline, settle re-read, /health, the signed POST, one poll that sees OUR terminal frame, the final state check
S4_BASE=("${S4_DOP_BASE[@]}" "SHIM_STATUS_BODY=$(s4_seccomp_frame false 1700000123)" "SHIM_STATUS_BODY_POST=$(s4_seccomp_frame true 1700000200 ',"sandbox_canary":{"verdict":"pass"}')" 'SHIM_HEALTH_BODY={"version":"1.2.3"}')
s4_run r16-full "$S4/b-r16.sh" "$S4/real" "${S4_BASE[@]}"
S4_R16_OK=1; for ci in 1 2 5; do s4_wh_ok "$S4/bodies/empty" "$ci" || S4_R16_OK=0; done; s4_wh_ok "$S4_ROW/calls/4.body" 4 || S4_R16_OK=0
if [[ "$S4_RC" == 0 && "$(s4_ncalls)" == 5 && "$S4_R16_OK" == 1 && "$(s4_markers)" == 0 ]] && grep -qF 'deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.2.3' "$S4_ROW/calls/4.body" \
   && s4_said 'Redeploy initiated (HTTP 202)' && s4_said 'STATE invariant holds'; then
  row "S4 row 16 redeploy (full path): the stale baseline, the settle re-read, the signed POST (independent digest over the recorded payload) and the poll make 4 signed requests, each with the pair on stdin and nothing on any argv, and the committed profile is confirmed live" ok
else row "S4 row 16 redeploy (full path): well-formed run" fail "rc=$S4_RC calls=$(s4_ncalls) signed-ok=$S4_R16_OK markers=$(s4_markers)"; fi
s4_v_r16() { [[ "$S4_RC" != 0 ]] || return 1
  case "$2" in
    unset) ! s4_said 'Redeploy initiated' ;;   # a doppler read aborts the step before any guard: the old behaviour, no request
    *) s4_said '::error::Cannot read /hooks/deploy-status (HTTP 000)' && ! s4_said 'Redeploy webhook rejected' && ! s4_said 'Redeploy initiated' && [[ "$(s4_markers)" == 1 ]] ;;
  esac; }
S4_BASE=("${S4_DOP_BASE[@]}" "SHIM_STATUS_BODY=$(s4_seccomp_frame false 1700000123)" "SHIM_STATUS_BODY_POST=$(s4_seccomp_frame true 1700000200)" 'SHIM_HEALTH_BODY={"version":"1.2.3"}')
s4_sweep r16 "$S4/b-r16.sh" "$S4/real" s4_v_r16 "D_CF_ACCESS_CLIENT_ID D_CF_ACCESS_CLIENT_SECRET" "D_WEBHOOK_DEPLOY_SECRET"
s4_sweep_row "S4 row 16 redeploy: an empty or hostile credential is the baseline read's old red ('Cannot read /hooks/deploy-status (HTTP 000) — refusing to assert loaded profile blind', exit 1) with ONE marker and zero requests, never 'Redeploy webhook rejected' (an unset one aborts at the doppler read as before)"
s4_v_r16_nopy() { [[ "$S4_RC" != 0 && "$(s4_markers)" == 1 ]] && s4_said 'Cannot read /hooks/deploy-status (HTTP 000)' && ! s4_said 'Redeploy initiated'; }
s4_nopy_row "S4 row 16 redeploy (library HMAC site): python3 absent is the same baseline-read red with the marker and zero requests, never a redeploy" "$S4/b-r16.sh" s4_v_r16_nopy
s4_mutant_red "S4 row 16 redeploy control: a refused baseline read swallowed into HTTP 200 (|| echo \"200\" instead of || echo \"000\") is judged RED (the step would go on to assert a loaded profile it never read)" "$REPO_ROOT/$S4_DPF" "Redeploy to load applied profile" r16-swallow200 '"$STATUS_URL" || echo "000"' '"$STATUS_URL" || echo "200"' s4_v_r16 "D_CF_ACCESS_CLIENT_ID=${S4_CANARY}\"x"
S4_BASE=("${S4_DOP_BASE[@]}" 'SHIM_STATUS_BODY={"journald_storage":{"persistent":true}}')
s4_run r17-ok "$S4/b-r17.sh" "$S4/real" "${S4_BASE[@]}"
if [[ "$S4_RC" == 0 && "$(s4_ncalls)" == 1 && "$(s4_markers)" == 0 ]] && s4_calls_ok 3 && s4_wh_ok "$S4/bodies/empty" 1 && s4_said 'journald_storage.persistent == true (attempt 1)'; then
  row "S4 row 17 journald_storage probe: a well-formed run reads the field through the digest over the empty body and the pair on stdin, and passes on the first attempt" ok
else row "S4 row 17 journald_storage probe: well-formed run" fail "rc=$S4_RC calls=$(s4_ncalls)"; fi
s4_v_r17() { [[ "$S4_RC" != 0 ]] || return 1
  case "$2" in
    unset) ! s4_said 'persistent == true' ;;
    *) [[ "$(s4_markers)" == 3 ]] && s4_said "::error::/hooks/deploy-status .journald_storage.persistent is '', expected 'true'" && ! s4_said 'persistent == true' ;;
  esac; }
s4_sweep r17 "$S4/b-r17.sh" "$S4/real" s4_v_r17 "D_CF_ACCESS_CLIENT_ID D_CF_ACCESS_CLIENT_SECRET" "D_WEBHOOK_DEPLOY_SECRET"
s4_sweep_row "S4 row 17 journald_storage probe: an empty or hostile credential is the step's old terminal red (three attempts, then the ::error:: naming an empty field) with ONE marker per attempt and zero requests (an unset one aborts at the doppler read as before)"
s4_v_r17_nopy() { [[ "$S4_RC" != 0 && "$(s4_markers)" == 3 ]] && ! s4_said 'persistent == true'; }
s4_nopy_row "S4 row 17 journald_storage probe (library HMAC site): python3 absent reaches the same terminal red with the marker per attempt" "$S4/b-r17.sh" s4_v_r17_nopy
s4_mutant_red "S4 row 17 journald_storage probe control: a refused read swallowed into HTTP 200 (|| echo \"200\" instead of || echo \"000\") is judged RED (the probe would read a field out of a response nobody received)" "$REPO_ROOT/$S4_DPF" "Verify journald_storage" r17-swallow200 '/hooks/deploy-status" || echo "000")' '/hooks/deploy-status" || echo "200")' s4_v_r17 "D_CF_ACCESS_CLIENT_ID=${S4_CANARY}\"x"
S4_CWD=""

# ---- the realistic credential shapes MUST PASS (the guard's alphabet is judged against what the vendors actually issue) ----
S4_JWT="$(printf '{"alg":"RS256","typ":"JWT"}' | base64 -w0 | tr '+/' '-_' | tr -d '=').$(printf '{"iss":"123456","iat":1700000000,"exp":1700000600}' | base64 -w0 | tr '+/' '-_' | tr -d '=').$(head -c 48 /dev/urandom | base64 -w0 | tr '+/' '-_' | tr -d '=')"
printf '%s\n' 'source "${GITHUB_WORKSPACE:?}/scripts/lib/bearer-curl.sh" || exit 1' \
  'bc_curl s4-shapes "Authorization:Bearer :TOK" -- -sS --max-time 5 https://example.invalid/x' > "$S4/shape-lib.sh"
printf '%s\n' "$BEARER_FN" '_bearer_ok "${TOK:-}" || exit 1' "( LC_ALL=C; case \"\${TOK:-}\" in ${S4_PAT}) exit 1 ;; esac ) || exit 1" > "$S4/shape-inline.sh"
S4_SHAPE_BAD=""
for shape in "sig64:$S4_HEX64" "cfid:$S4_CFID" "sbp:$S4_SBP" "jwt:$S4_JWT" "ghs:$S4_GHS" "hetzner:$S4_HZ" "resend:$S4_RESEND"; do
  sname="${shape%%:*}"; sval="${shape#*:}"
  s4_run "shape-$sname" "$S4/shape-lib.sh" "$S4/real" TOK="$sval"
  { [[ "$S4_RC" == 0 && "$(s4_ncalls)" == 1 && "$(s4_stdin_line 1 1)" == "header = \"Authorization: Bearer $sval\"" ]] && s4_calls_ok 1 && ! s4_argv_has "$sval"; } || S4_SHAPE_BAD+=" $sname(library rc=$S4_RC)"
  s4_run "shape-$sname-inline" "$S4/shape-inline.sh" "$S4/real" TOK="$sval"
  [[ "$S4_RC" == 0 ]] || S4_SHAPE_BAD+=" $sname(inline rc=$S4_RC)"
done
[[ -z "$S4_SHAPE_BAD" ]] && row "S4 must-PASS shapes: a 64-hex signature, a <hex>.access Cloudflare id, a Supabase sbp_ token, a JWT with dots, a ghs_ installation token, a Hetzner token and a Resend re_ key are ALL accepted by the library (and arrive on stdin only), by the inline _bearer_ok and by infra-config-verify's case pattern" ok || row "S4 must-PASS shapes: a realistic credential is refused" fail "$S4_SHAPE_BAD"

# ---- the replay (binding lesson 3): every converted call's non-credential argument list passes the library's own `_bc_tail_ok` ----
# STATIC: each `bc_curl` statement of the nine library-user files is evaluated with `bc_curl` overridden to hand its argument list (after `--`) to the real
# `_bc_tail_ok` (a statement that does not parse, or a refusal, is a failure). DYNAMIC: every call the well-formed runs above recorded (the real bodies:
# the SQL payload, the Resend HTML, the push payload path) is replayed the same way.
s4_replay_py='
import sys, yaml, re, os
out = sys.argv[1]; n = 0
for f in sys.argv[2:]:
    if f.endswith((".yml", ".yaml")):
        d = yaml.safe_load(open(f)); steps = []
        if isinstance(d.get("runs"), dict): steps = d["runs"].get("steps") or []
        else:
            for j in (d.get("jobs") or {}).values(): steps += (j.get("steps") or []) if isinstance(j, dict) else []
        texts = [s["run"] for s in steps if isinstance(s, dict) and isinstance(s.get("run"), str)]
    else:
        texts = [open(f).read()]
    for t in texts:
        lines = t.split("\n"); i = 0
        while i < len(lines):
            l = lines[i]
            if re.search(r"(^|[^_A-Za-z])bc_curl [A-Za-z]", l) and not l.lstrip().startswith("#"):
                j = i; buf = l
                while buf.endswith("\\") and j + 1 < len(lines):
                    j += 1; buf = buf[:-1] + " " + lines[j].strip()
                n += 1
                # the failure handler of a trigger opens a brace block on the last line of the call (the text after the closing paren); the call itself ends before it
                buf = re.sub(r"\s*\|\| \{ rc=\$\?\s*$", "", buf)
                open(os.path.join(out, "%03d.stm" % n), "w").write(buf.strip() + "\n"); i = j
            i += 1
print(n)
'
S4_RP="$S4/replay"; assert_fixture_dir "$S4_RP"; mkdir -p "$S4_RP"
S4_REPLAY_FILES=".github/actions/dispatch-web-redeploy/track.sh .github/actions/mint-infra-app-token/action.yml .github/workflows/apply-deploy-pipeline-fix.yml .github/workflows/apply-github-infra.yml .github/workflows/apply-inngest-rls.yml .github/workflows/restart-inngest-server.yml .github/workflows/scheduled-inngest-health.yml apps/web-platform/infra/push-infra-config.sh apps/web-platform/scripts/github-app-key-status.sh scripts/key-rotate.sh"
S4_RP_N="$(cd "$REPO_ROOT" && python3 -I -c "$s4_replay_py" "$S4_RP" $S4_REPLAY_FILES)"
S4_RP_OK=0; S4_RP_BAD=""
for stm in "$S4_RP"/*.stm; do
  [[ -e "$stm" ]] || continue
  { printf 'source "%s/scripts/lib/bearer-curl.sh"\n' "$REPO_ROOT"
    printf '%s\n' 'bc_curl() { shift; while [[ $# -gt 0 && "$1" != -- ]]; do shift; done; shift; if _bc_tail_ok "$@" 2>/dev/null; then echo OK >&2; else echo REFUSED >&2; fi; }'
    cat "$stm"; } > "$stm.sh"
  ( cd "$S4_RP" && env -i PATH="$S4/real" "$BASH_BIN" --noprofile --norc "$stm.sh" > /dev/null 2> "$stm.out" < /dev/null )
  res="$(grep -cx OK "$stm.out" || true)"; [[ "$(grep -c REFUSED "$stm.out" || true)" == 0 ]] || res=0
  [[ "$res" -ge 1 ]] && S4_RP_OK=$((S4_RP_OK + 1)) || S4_RP_BAD+=" $(basename "$stm")"
done
# BOTH operands are literals on the lines IMMEDIATELY above the `if`: 26 bc_curl statements in the ten files.
S4_REPLAY_FLOOR=26
if [[ -z "$S4_RP_BAD" && "$S4_RP_OK" == "$S4_RP_N" && "$S4_RP_OK" -ge "$S4_REPLAY_FLOOR" ]]; then row "S4 replay (static): all $S4_RP_OK converted bc_curl statements hand an argument list the library's own _bc_tail_ok accepts (zero refusals; anti-vacuity floor $S4_REPLAY_FLOOR)" ok
else row "S4 replay (static): a converted call's argument list is refused or does not parse" fail "ok=$S4_RP_OK of $S4_RP_N bad:$S4_RP_BAD"; fi
s4_tail_probe() { # <argv file>: the recorded call minus the library's own prefix and the config channel, judged by _bc_tail_ok
  local -a av tail_=(); local i
  mapfile -d '' av < "$1"
  for ((i = 0; i < ${#av[@]}; i++)); do
    if [[ "${av[i]}" == --config && "${av[i+1]:-}" == - ]]; then i=$((i + 1)); continue; fi
    tail_+=("${av[i]}")
  done
  tail_=("${tail_[@]:3}")
  env -i PATH="$S4/real" "$BASH_BIN" --noprofile --norc -c 'source "$1/scripts/lib/bearer-curl.sh"; shift; _bc_tail_ok "$@"' _ "$REPO_ROOT" "${tail_[@]}" > /dev/null 2>&1
}
S4_DYN_N=0; S4_DYN_BAD=""
for rd in "$S4"/rows/*; do
  case "$(basename "$rd")" in *empty*|*unset*|*hostile*|*nopy*|*transport*|*nolib*|*visible*|*shape*|*ctl*) continue ;; esac
  for af in "$rd"/calls/*.argv; do
    [[ -e "$af" ]] || continue
    S4_DYN_N=$((S4_DYN_N + 1)); s4_tail_probe "$af" || S4_DYN_BAD+=" $(basename "$rd")/$(basename "$af")"
  done
done
# the dynamic replay also needs a floor and a control: a body that reads stdin MUST be refused by the very probe
printf '%s\0' --disable --noproxy '*' -sS --data-binary @- https://example.invalid/x --config - > "$S4/ctl-replay.argv"
S4_DYN_FLOOR=61
if [[ -z "$S4_DYN_BAD" && "$S4_DYN_N" -ge "$S4_DYN_FLOOR" ]] && ! s4_tail_probe "$S4/ctl-replay.argv"; then
  row "S4 replay (dynamic): all $S4_DYN_N calls the well-formed runs recorded (real SQL, Resend, payload-path and header arguments) pass _bc_tail_ok, and the probe refuses a body read from stdin (control); anti-vacuity floor $S4_DYN_FLOOR" ok
else row "S4 replay (dynamic): a recorded call is refused, the population is below its floor, or the probe is blind" fail "n=$S4_DYN_N bad:$S4_DYN_BAD"; fi
# The extracted steps' environment is the YAML's own (review F1). s4_run injects a NAME=value into a step extracted from a workflow only when the workflow-level env,
# the job-level env, the step's env or an earlier `echo NAME=... >> $GITHUB_ENV` DECLARES NAME, so deleting a credential's `env:` declaration from a converted step makes
# its well-formed row RED. CONTROL: the restart trigger run with a declaration list that lacks CF_ACCESS_CLIENT_ID sees the id UNSET (zero requests, refused, logged as dropped).
grep -vxF CF_ACCESS_CLIENT_ID "$S4/b-r1.sh.decl" > "$S4/b-r1x.sh.decl"; cp "$S4/b-r1.sh" "$S4/b-r1x.sh"
S4_DECL_N="$(grep -c . "$S4/b-r1.sh.decl")"; S4_DECL_NX="$(grep -c . "$S4/b-r1x.sh.decl")"
s4_run ctl-r1-undeclared "$S4/b-r1x.sh" "$S4/real" "${S4_WH_BASE[@]}"
if [[ "$S4_DECL_N" == "$((S4_DECL_NX + 1))" && "$S4_RC" != 0 && "$(s4_ncalls)" == 0 && "$(s4_markers)" == 1 ]] && grep -qxF 'ctl-r1-undeclared CF_ACCESS_CLIENT_ID' "$S4/dropped.log"; then
  row "S4 step env control: a step whose YAML does not declare a credential sees it UNSET (the harness injects only declared names): the restart trigger without CF_ACCESS_CLIENT_ID makes zero requests, refuses with the marker and the drop is logged" ok
else row "S4 step env control: an undeclared credential is still injected" fail "rc=$S4_RC calls=$(s4_ncalls) decl=$S4_DECL_N/$S4_DECL_NX"; fi
# SCOPE of the derivation (the control above proves the FILTER drops, not that the derivation is scoped to ONE step): a fixture workflow whose step A is judged against a decl that
# holds the workflow env, ITS job's env and its own env, and not a sibling step's env nor another job's env. Two MUTANT derivations (union of every step's env in the job; union of
# every job's env) must be judged red by the same predicate, so over-broad derivation (which would let a row inject a name its own step never declares) cannot pass silently.
S4_DF="$S4/declfix"; assert_fixture_dir "$S4_DF"; mkdir -p "$S4_DF"
printf '%s\n' 'name: x' 'env:' '  WF_LEVEL: a' 'jobs:' '  j1:' '    env:' '      JOB_LEVEL: b' '    steps:' '      - name: step A' '        env:' '          ONLY_A: "1"' \
  '        run: |' '          echo a' '      - name: step B' '        env:' '          ONLY_B: "2"' '        run: |' '          echo b' \
  '  j2:' '    env:' '      OTHER_JOB: c' '    steps:' '      - name: step C' '        run: |' '          echo c' > "$S4_DF/w.yml"
s4_decl_with() { python3 -I -c "$1" "$S4_DF/w.yml" "step A"; }
s4_decl_scope_bad() { # <decl text>: names the scope clauses the derivation breaks
  local d="$1" b="" n
  for n in WF_LEVEL JOB_LEVEL ONLY_A; do grep -qxF "$n" <<<"$d" || b+=" missing-$n"; done
  for n in ONLY_B OTHER_JOB; do ! grep -qxF "$n" <<<"$d" || b+=" leaked-$n"; done
  printf '%s' "$b"
}
S4_DM_STEP="${s4_decl_py/add(s.get(\"env\"))/for o in steps: add(o.get(\"env\"))}"
S4_DM_JOB="${s4_decl_py/if job: add(job.get(\"env\"))/for jj in d[\"jobs\"].values(): add(jj.get(\"env\"))}"
S4_DS_REAL="$(s4_decl_scope_bad "$(s4_decl_with "$s4_decl_py")")"
S4_DS_STEP="$(s4_decl_scope_bad "$(s4_decl_with "$S4_DM_STEP")")"; S4_DS_JOB="$(s4_decl_scope_bad "$(s4_decl_with "$S4_DM_JOB")")"
if [[ -z "$S4_DS_REAL" && "$S4_DM_STEP" != "$s4_decl_py" && "$S4_DM_JOB" != "$s4_decl_py" && "$S4_DS_STEP" == *leaked-ONLY_B* && "$S4_DS_JOB" == *leaked-OTHER_JOB* ]]; then
  row "S4 step env scope control: the derivation gives a step the workflow env, its own job's env and its own env only; a union of the job's step envs and a union of every job's env are each judged RED (a sibling step's or another job's name leaks)" ok
else row "S4 step env scope control: the derivation is not scoped to one step, or a mutated derivation is not judged red" fail "real='$S4_DS_REAL' stepunion='$S4_DS_STEP' jobunion='$S4_DS_JOB' landed=$([[ "$S4_DM_STEP" != "$s4_decl_py" && "$S4_DM_JOB" != "$s4_decl_py" ]] && echo yes || echo NO)"; fi
# The population of drops: no real row had a NAME dropped, i.e. every name this stage injects into an extracted step is declared by it. Only the ONE control above that
# deliberately removes a declaration is exempt (a blanket `ctl-` exemption would let a control with a typo'd name be dropped and pass for the wrong reason). The claim covers the
# runs of steps extracted from a workflow (those with a .decl); the script rows are not under this regime.
# BOTH operands are literals on the lines IMMEDIATELY above the `if`: 0 drops across the 358 run directories of the stage (the realized count).
S4_DROP_N="$(grep -vc '^ctl-r1-undeclared ' "$S4/dropped.log" || true)"
S4_STEPRUNS="$(find "$S4/rows" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
S4_DROP_WANT=0
S4_STEPRUN_FLOOR=358
if [[ "$S4_DROP_N" == "$S4_DROP_WANT" && "$S4_STEPRUNS" -ge "$S4_STEPRUN_FLOOR" ]]; then row "S4 step env: every variable the stage injects into a step extracted from a workflow is declared by that step, its job or its workflow (0 of $S4_STEPRUNS runs had a name dropped; floor $S4_STEPRUN_FLOOR runs)" ok
else row "S4 step env: the harness injected a variable its step does not declare, or the run population is below its floor" fail "dropped='$(grep -v '^ctl-r1-undeclared ' "$S4/dropped.log" | sort -u | tr '\n' ' ')' runs=$S4_STEPRUNS floor=$S4_STEPRUN_FLOOR"; fi
# The negative canary, as one population: the planted canary was searched for in EVERY captured stream (stdout, stderr, GITHUB_OUTPUT, GITHUB_ENV, the step
# summary, every recorded argv and stdin and every file a step wrote) of every hostile or refused run above; a run that leaks fails its own row, and this row
# proves the sweep was not vacuous. BOTH operands are literals on the lines IMMEDIATELY above the `if`.
S4_CANARY_FLOOR=257
if [[ "$S4_REFUSAL_RUNS" -ge "$S4_CANARY_FLOOR" ]]; then row "S4 negative canary: $S4_REFUSAL_RUNS refusal runs searched for the planted canary in every captured stream (anti-vacuity floor $S4_CANARY_FLOOR)" ok
else row "S4 negative canary: the refusal population is below its anti-vacuity floor" fail "runs=$S4_REFUSAL_RUNS floor=$S4_CANARY_FLOOR"; fi
echo "=== stage S4: Guard 2 rows 13 to 24, shapes and replay done ==="

