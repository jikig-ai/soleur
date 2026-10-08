#!/usr/bin/env bash
# Tests for scripts/web2-rebirth.sh (#9372): the stateful steps of the single-use web-2 volume rebirth, run against a
# shellcheck disable=SC2319,SC2034
# fake Hetzner API / Terraform / gh / Better Stack ("the world", a directory of small files the shims read and write).
# Every row drives the REAL script under the production shell; a mutation battery then removes each load-bearing
# check from a COPY and requires the battery to go red.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${DIR}/.." && pwd)"
SCRIPT="${ROOT}/scripts/web2-rebirth.sh"
EXTRA_ARR=()
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

PIN=106466179; SID=1001; W1=123931471; NEWV=777

mkdir -p "$TMP/bin"
# ---- curl shim: a tiny fake of the Hetzner API and the Better Stack query endpoint --------------------------------------
cat > "$TMP/bin/curl" <<'SH'
#!/usr/bin/env bash
# args: -sS ... --config - -X METHOD [--data D] -o FILE -w FMT URL        (the token arrives on stdin)
W="${WORLD:?}"
method=GET; body_out=""; url=""; data=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -X) method="$2"; shift 2 ;; -o) body_out="$2"; shift 2 ;; --data) data="$2"; shift 2 ;;
    -w|--max-time|-H|--config|-u|--url) shift 2 ;; http*) url="$1"; shift ;; *) shift ;;
  esac
done
case "$*" in *"--config -"*) cat > "$W/stdin.last" 2>/dev/null || true ;; esac
echo "$method ${url}" >> "$W/calls.log"
reply() { printf '%s' "$2" > "${body_out:-/dev/null}"; printf '%s' "$1"; }
case "$url" in
  *betterstackdata.com*) [[ -n "$body_out" ]] && cat "$W/bs_body" > "$body_out" || cat "$W/bs_body"; exit 0 ;;
esac
path="${url#https://api.hetzner.cloud/v1}"
vol_json() { jq -cn --arg id "$1" --arg name "$2" --arg fmt "$3" --arg srv "$4" --arg app "${5:-soleur-web-platform}" '{volume:{id:($id|tonumber),name:$name,format:(if $fmt=="none" then null else $fmt end),server:(if $srv=="none" then null else ($srv|tonumber) end),labels:{app:$app}}}'; }
case "$method $path" in
  "GET /servers/123931471")
    case "$(cat "$W/web1_mode" 2>/dev/null || echo ok)" in
      404) reply 404 '{"error":{"code":"not_found"}}' ;;
      rename) reply 200 '{"server":{"id":123931471,"name":"someone-else","volumes":[106443278]}}' ;;
      novol) reply 200 '{"server":{"id":123931471,"name":"soleur-web-platform","volumes":[]}}' ;;
      *) reply 200 '{"server":{"id":123931471,"name":"soleur-web-platform","volumes":[106443278]}}' ;;
    esac ;;
  "GET /servers?name=soleur-web-2")
    if [[ -f "$W/server_absent" ]]; then reply 200 '{"servers":[]}'
    else reply 200 "$(jq -cn --arg id "$(cat "$W/server_id")" --arg c "$(cat "$W/server_created")" --argjson v "[$(cat "$W/server_vols")]" '{servers:[{id:($id|tonumber),name:"soleur-web-2",created:$c,volumes:$v}]}')"; fi ;;
  "GET /volumes/106466179")
    if [[ -f "$W/pin_code" ]]; then reply "$(cat "$W/pin_code")" '{"error":{"code":"boom"}}'
    elif [[ -f "$W/pin_gone" ]]; then reply 404 '{"error":{"code":"not_found"}}'
    else reply 200 "$(vol_json 106466179 "$(cat "$W/pin_name")" "$(cat "$W/pin_format")" "$(cat "$W/pin_server")" "$(cat "$W/pin_app")")"; fi ;;
  "GET /volumes?name=soleur-web-platform-data-web-2")
    ids=""; [[ -f "$W/pin_gone" ]] || ids="106466179"
    for x in $(cat "$W/other_named" 2>/dev/null); do ids="$ids $x"; done
    reply 200 "$(printf '%s\n' $ids | jq -Rn '[inputs | select(length>0) | {id: tonumber}] | {volumes: .}')" ;;
  "POST /volumes/106466179/actions/detach")
    if [[ -f "$W/detach_code" ]]; then reply "$(cat "$W/detach_code")" '{"error":{"code":"locked"}}'
    else echo none > "$W/pin_server"; echo "DETACH" >> "$W/writes.log"; reply 201 '{"action":{"id":9,"status":"running"}}'; fi ;;
  "GET /actions/9"|"GET /actions/10") id="${path##*/}"; reply 200 "$(jq -cn --argjson id "$id" --arg st "$(cat "$W/action_status" 2>/dev/null || echo success)" '{action:{id:$id,status:$st,error:{code:"x"}}}')" ;;
  "DELETE /volumes/106466179")
    echo "DELETE-VOLUME" >> "$W/writes.log"
    case "$(cat "$W/delete_code" 2>/dev/null || echo 204)" in
      204) touch "$W/pin_gone"; reply 204 "" ;; 404) reply 404 '{"error":{"code":"not_found"}}' ;; *) reply "$(cat "$W/delete_code")" '{"error":{"code":"locked"}}' ;;
    esac ;;
  "POST /servers/"*"/actions/reboot") echo "REBOOT ${path}" >> "$W/writes.log"; reply 201 '{"action":{"id":10,"status":"running"}}' ;;
  *) echo "UNEXPECTED $method $path" >> "$W/unexpected.log"; reply 599 '{"error":{"code":"unexpected"}}' ;;
esac
SH
# ---- terraform shim: state pull / list / rm over the world's state files -----------------------------------------------
cat > "$TMP/bin/terraform" <<'SH'
#!/usr/bin/env bash
W="${WORLD:?}"
case "$1 $2" in
  "state pull") cat "$W/state.json" ;;
  "state list") jq -r '.addrs[]' "$W/state.json" 2>/dev/null | sort ;;
  "state rm")
    shift 2; echo "STATE-RM $*" >> "$W/writes.log"
    bump=1; [[ -f "$W/state_no_bump" ]] && bump=0
    jq -c --argjson bump "$bump" --argjson rm "$(printf '%s\n' "$@" | jq -Rn '[inputs]')" '.addrs |= map(select(. as $a | $rm | index($a) | not)) | .serial += $bump
      | if ($rm | index("hcloud_volume.workspaces[\"web-2\"]")) then .vol="none" else . end
      | if ($rm | index("hcloud_volume_attachment.workspaces[\"web-2\"]")) then .att="none" else . end' "$W/state.json" > "$W/state.new"
    [[ -f "$W/state_lineage_change" ]] && jq -c '.lineage="other"' "$W/state.new" > "$W/state.new2" && mv "$W/state.new2" "$W/state.new"
    mv "$W/state.new" "$W/state.json" ;;
  *) echo "unexpected terraform $*" >> "$W/unexpected.log"; exit 1 ;;
esac
SH
# `terraform state pull` must emit a REAL tfstate shape: the script selects resources by type/name, so the shim renders it.
cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
W="${WORLD:?}"
case "$1 $2" in
  "api repos/"*)
    wf="${2##*/}"; st="$(cat "$W/wf_state.$wf" 2>/dev/null || cat "$W/wf_state" 2>/dev/null || echo disabled_manually)"
    case "$2" in *"/approvals") printf '[{"user":{"login":"approver-one"},"state":"approved"}]'; exit 0 ;; esac
    printf '{"state":"%s"}' "$st" ;;
  "run list") if [[ -f "$W/busy" ]]; then printf '[{"status":"in_progress"}]'; else printf '[]'; fi ;;
  *) echo "unexpected gh $*" >> "$W/unexpected.log"; exit 1 ;;
esac
SH
chmod +x "$TMP/bin/"*

# world <scenario flags...> — build the fake world. Defaults: the FIRST dispatch (pin attached to web-2, in state).
world() {
  W="${BATTERY_DIR:-$TMP}/world.$RANDOM"; rm -rf "$W"; mkdir -p "$W"; export WORLD="$W"
  echo "$SID" > "$W/server_id"; echo "$PIN" > "$W/server_vols"; echo "$SID" > "$W/pin_server"
  echo soleur-web-platform-data-web-2 > "$W/pin_name"; echo ext4 > "$W/pin_format"; echo soleur-web-platform > "$W/pin_app"
  : > "$W/calls.log"; : > "$W/writes.log"
  date -u -d '@'"$(( $(date -u +%s) - 7200 ))" +%Y-%m-%dT%H:%M:%S+00:00 > "$W/server_created"
  local svol="$PIN" satt="$PIN" ssrv="$SID" web1=1 f
  for f in "$@"; do
    case "$f" in
      detached) echo none > "$W/pin_server"; echo "" > "$W/server_vols"; satt=none ;;
      pin_gone) touch "$W/pin_gone"; echo "" > "$W/server_vols" ;;
      state_vol_none) svol=none; satt=none ;;
      server_absent) touch "$W/server_absent"; ssrv=none; echo "" > "$W/server_vols" ;;
      other_named=*) echo "${f#*=}" > "$W/other_named" ;;
      state_vol=*) svol="${f#*=}" ;;
      web2_vols=*) echo "${f#*=}" > "$W/server_vols" ;;
      pin_format=*) echo "${f#*=}" > "$W/pin_format" ;;
      pin_server=*) echo "${f#*=}" > "$W/pin_server" ;;
      delete_code=*) echo "${f#*=}" > "$W/delete_code" ;;
      wf_state=*) echo "${f#*=}" > "$W/wf_state" ;;
      wf_deploy_state=*) echo "${f#*=}" > "$W/wf_state.apply-deploy-pipeline-fix.yml" ;;
      busy) touch "$W/busy" ;;
      server_created_empty) : > "$W/server_created" ;;
      pin_name=*) printf '%b\n' "${f#*=}" > "$W/pin_name" ;;
      web1_mode=*) echo "${f#*=}" > "$W/web1_mode" ;;
      server_age=*) date -u -d '@'"$(( $(date -u +%s) - ${f#*=} ))" +%Y-%m-%dT%H:%M:%S+00:00 > "$W/server_created" ;;
      pin_code=*) echo "${f#*=}" > "$W/pin_code" ;;
      detach_code=*) echo "${f#*=}" > "$W/detach_code" ;;
      action_status=*) echo "${f#*=}" > "$W/action_status" ;;
      att=*) satt="${f#*=}" ;;
      state_server_none) ssrv=none ;;
      no_bump) touch "$W/state_no_bump" ;;
      lineage_change) touch "$W/state_lineage_change" ;;
      no_web1) web1=0 ;;
    esac
  done
  jq -cn --argjson web1 "$web1" --arg vol "$svol" --arg att "$satt" --arg srv "$ssrv" '{serial: 5, lineage: "L1", web1: $web1, vol: $vol, att: $att, server: $srv, addrs: ([
      "hcloud_server.web[\"web-1\"]", "hcloud_volume.workspaces_luks", "hcloud_firewall_attachment.web"]
      + (if $vol != "none" then ["hcloud_volume.workspaces[\"web-2\"]"] else [] end)
      + (if $att != "none" then ["hcloud_volume_attachment.workspaces[\"web-2\"]"] else [] end)
      + (if $srv != "none" then ["hcloud_server.web[\"web-2\"]"] else [] end))}' > "$W/state.json"
}
# The real tfstate shape is derived from the world file by a wrapper so `terraform state pull | jq STATE_JQ` selects it.
cat > "$TMP/bin/terraform.real" <<'SH'
SH
rm -f "$TMP/bin/terraform.real"
# render: replace `state pull` output with a tfstate document built from the world's flat summary.
python3 - "$TMP/bin/terraform" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
s = s.replace('"state pull") cat "$W/state.json" ;;', '''"state pull") jq -c '{serial: .serial, lineage: .lineage, resources: ([
      (if .vol != "none" then {mode:"managed",type:"hcloud_volume",name:"workspaces",instances:[{index_key:"web-2",attributes:{id:(.vol|tonumber)}}]} else empty end),
      (if .att != "none" then {mode:"managed",type:"hcloud_volume_attachment",name:"workspaces",instances:[{index_key:"web-2",attributes:{volume_id:(.att|tonumber)}}]} else empty end),
      {mode:"managed",type:"hcloud_server",name:"web",instances: ((if .web1 == 1 then [{index_key:"web-1",attributes:{id:123931471}}] else [] end) + (if .server != "none" then [{index_key:"web-2",attributes:{id:(.server|tonumber)}}] else [] end))}
    ])}' "$W/state.json" ;;''')
open(p, "w").write(s)
PY

run() { # <name> <want-rc> <want-substring|-> <cmd...>   (env from the caller: WORLD, VERDICT, ...)
  local name="$1" want="$2" sub="$3"; shift 3
  local o rc=0
  echo x >> "$BATTERY_DIR/runs"
  o="$(env PATH="$TMP/bin:/usr/bin:/bin" WORLD="$WORLD" HCLOUD_TOKEN=tok REPO=o/r GH_TOKEN=x INFRA_DIR="$TMP" GITHUB_OUTPUT="$WORLD/gh_out" GITHUB_STEP_SUMMARY="$WORLD/summary" \
        WEB2_REBIRTH_POLL_INTERVAL_S=0 WEB2_REBIRTH_ACTION_POLL_S=0 WEB2_REBIRTH_POLL_ATTEMPTS=2 \
        BETTERSTACK_QUERY_HOST=fixture-connect.betterstackdata.com BETTERSTACK_QUERY_USERNAME=u BETTERSTACK_QUERY_PASSWORD=p \
        APPLY=yes EMPTINESS="PASS hours=168" NEVER_POOLED=absent PRE_PLAN=graded FLIP=met ${EXTRA_ENV:-} ${EXTRA_ARR[@]+"${EXTRA_ARR[@]}"} \
        bash "$SCRIPT_UNDER_TEST" "$@" 2>&1)" || rc=$?
  LASTOUT="$o"
  if [[ "$rc" -ne "$want" ]]; then printf 'FAILED %s (rc=%s want=%s) %s\n' "$name" "$rc" "$want" "${o:0:240}"; return; fi
  if [[ "$sub" != "-" && "$o" != *"$sub"* ]]; then printf 'FAILED %s (output lacks %q) %s\n' "$name" "$sub" "${o:0:240}"; fi
}
verdict_of() { sed -n 's/^verdict=//p' "$WORLD/gh_out" | tail -1; }
writes() { tr '\n' ' ' < "$WORLD/writes.log"; }
check() { # <name> <condition-result 0|1>
  echo x >> "$BATTERY_DIR/checks"
  if [[ "$2" -ne 0 ]]; then printf 'FAILED %s\n' "$1"; fi
}

battery() {
  # Every battery works in its OWN directory: concurrent mutant batteries share $TMP, and a world, a runs counter or an unexpected.log
  # from another battery must never be attributed to this one.
  SCRIPT_UNDER_TEST="$1"; local n=0; BATTERY_DIR="$(mktemp -d "$TMP/b.XXXXXX")"; : > "$BATTERY_DIR/runs"; : > "$BATTERY_DIR/checks"
  # ---- classify ----
  world; run "classify: first dispatch proceeds" 0 "verdict: proceed" classify no; check "classify wrote verdict output" "$([[ "$(verdict_of)" == proceed ]]; echo $?)"
  world; run "classify: apply with a real pause proceeds" 0 "verdict: proceed" classify yes
  world wf_state=active; run "classify: apply with the pause NOT real refuses" 1 "push_apply_pause_not_real" classify yes
  world wf_state=active; run "classify: plan_only does not need the pause" 0 "verdict: proceed" classify no
  world detached; run "classify: detach done" 0 "heal:detach_done" classify no
  world pin_gone; run "classify: delete done" 0 "heal:delete_done" classify no
  world pin_gone state_vol_none; run "classify: state rm done" 0 "heal:state_rm_done" classify no
  world pin_gone state_vol_none server_absent; run "classify: apply midway" 0 "heal:apply_midway" classify no
  world pin_gone state_vol_none other_named=$NEWV; run "classify: orphan raw volume refuses" 1 "orphan_raw_volume" classify no
  world pin_gone state_vol=$NEWV other_named=$NEWV web2_vols=$NEWV; run "classify: a rebirth that already ran within 72 h resumes (nothing is replaced)" 0 "verdict: resume:post_apply" classify no
  check "classify: the resume verdict is exported" "$([[ "$(verdict_of)" == resume:post_apply ]]; echo $?)"
  world pin_gone state_vol=$NEWV other_named=$NEWV web2_vols=$NEWV server_age=400000; run "classify: a rebirth older than 72 h refuses (single use)" 1 "already_reborn" classify no
  world pin_gone state_vol_none state_server_none; run "classify: an orphan server (Hetzner has web-2, state does not) refuses" 1 "orphan_server" classify no
  world pin_code=500; run "classify: a 5xx on the pinned volume is neither present nor gone (nothing is written)" 1 "neither present nor gone" classify no
  world web1_mode=404; run "classify: presence proof: web-1 answering 404 means this token cannot see the project" 1 "presence proof" classify no
  world web1_mode=rename; run "classify: presence proof: a server with another name is not web-1" 1 "presence proof" classify no
  world web1_mode=novol; run "classify: presence proof: web-1 without the live LUKS volume" 1 "does not hold the live LUKS volume" classify no
  world wf_deploy_state=active; run "classify: apply with ONE push-apply workflow still active refuses" 1 "push_apply_pause_not_real" classify yes
  world busy; run "classify: apply with a queued or running push-apply run refuses" 1 "push_apply_pause_not_real" classify yes
  world; run "classify: the pinned volume description is exported for the summary" 0 "pinned volume: id=106466179" classify no
  world pin_format=none; run "classify: a formatted pinned volume refuses" 1 "not_the_empty_plaintext_one" classify no
  world pin_server=999; run "classify: pinned volume attached elsewhere refuses" 1 "attached_elsewhere" classify no
  world other_named=$NEWV; run "classify: two volumes with the name refuse" 1 "duplicate_volume_name" classify no
  world pin_gone state_vol=$NEWV other_named=$NEWV web2_vols=$NEWV server_created_empty; run "classify: a server with NO creation time never resumes (an empty date reads as midnight today)" 1 "already_reborn" classify no
  world pin_name='x\nverdict=heal:detach_done'; run "classify: a volume name with a newline cannot inject a second verdict output line" 1 "not_the_empty_plaintext_one" classify no
  check "classify: exactly ONE verdict= output line" "$([[ "$(grep -c '^verdict=' "$WORLD/gh_out")" == 1 ]]; echo $?)"
  check "classify: every output is a single line (no continuation of the injected text)" "$([[ "$(grep -vc '^[a-z_0-9]*=' "$WORLD/gh_out")" == 0 ]]; echo $?)"
  # ---- delete-volume ----
  world; VERDICT=proceed EXTRA_ENV="VERDICT=proceed" run "delete: detach then delete, then 404 proven" 0 "is gone" delete-volume
  check "delete: write order is DETACH then DELETE-VOLUME" "$([[ "$(writes)" == "DETACH DELETE-VOLUME " ]]; echo $?)"
  check "delete: no request ever names another volume id" "$(! grep -E '/volumes/[0-9]+' "$WORLD/calls.log" | grep -vq "/volumes/$PIN"; echo $?)"
  world detached; EXTRA_ENV="VERDICT=heal:detach_done" run "delete: detach-done window skips the detach" 0 "is gone" delete-volume
  check "delete: no second detach" "$([[ "$(writes)" == "DELETE-VOLUME " ]]; echo $?)"
  world pin_gone; EXTRA_ENV="VERDICT=heal:delete_done" run "delete: later windows skip" 0 "skipped" delete-volume
  check "delete: skipped window wrote nothing" "$([[ -z "$(writes)" ]]; echo $?)"
  world; EXTRA_ENV="VERDICT=refuse:x" run "delete: a refuse verdict is refused" 1 "refused in state" delete-volume
  world pin_format=none; EXTRA_ENV="VERDICT=proceed" run "delete: re-asserts ext4 even when the verdict says proceed" 1 "not the empty plaintext" delete-volume
  check "delete: nothing was written after the failed re-assert" "$([[ -z "$(writes)" ]]; echo $?)"
  world pin_server=999; EXTRA_ENV="VERDICT=proceed" run "delete: re-asserts the attached server" 1 "not the server named" delete-volume
  world delete_code=404; EXTRA_ENV="VERDICT=proceed" run "delete: a 404 on DELETE is an idempotent success only if the pin then 404s" 1 "still answers" delete-volume
  world delete_code=423; EXTRA_ENV="VERDICT=proceed" run "delete: a locked volume fails" 1 "DELETE /volumes" delete-volume
  world detach_code=500; EXTRA_ENV="VERDICT=proceed" run "delete: a failed detach stops before the DELETE" 1 "detach -> 500" delete-volume
  check "delete: nothing was deleted after a failed detach" "$([[ "$(writes)" != *DELETE-VOLUME* ]]; echo $?)"
  world action_status=error; EXTRA_ENV="VERDICT=proceed" run "delete: a failed detach action stops before the DELETE" 1 "failed" delete-volume
  check "delete: nothing was deleted after a failed detach action" "$([[ "$(writes)" != *DELETE-VOLUME* ]]; echo $?)"
  world action_status=running; EXTRA_ENV="VERDICT=proceed" run "delete: a detach action that never finishes stops before the DELETE" 1 "did not finish in time" delete-volume
  world other_named=888; EXTRA_ENV="VERDICT=proceed" run "delete: a volume still carrying the name after the delete fails" 1 "still exists after the delete" delete-volume
  world; EXTRA_ENV="VERDICT=proceed APPLY=no" run "delete: plan_only (APPLY=no) refuses before any call" 1 "not an apply dispatch" delete-volume
  check "delete: APPLY=no made no Hetzner call" "$([[ ! -s "$WORLD/calls.log" ]]; echo $?)"
  world; EXTRA_ENV="VERDICT=proceed EMPTINESS=" run "delete: an empty emptiness proof (skipped step) refuses" 1 "no PASS emptiness verdict" delete-volume
  world; EXTRA_ENV="VERDICT=proceed EMPTINESS=RED-reason=not_empty" run "delete: a RED emptiness verdict refuses" 1 "no PASS emptiness verdict" delete-volume
  world; EXTRA_ENV="VERDICT=proceed NEVER_POOLED=" run "delete: an empty never-pooled proof refuses" 1 "no never-pooled proof" delete-volume
  world; EXTRA_ENV="VERDICT=proceed PRE_PLAN=" run "delete: an ungraded pre plan refuses" 1 "pre plan was not graded" delete-volume
  check "delete: no write after any refused evidence row" "$([[ -z "$(writes)" ]]; echo $?)"
  world web1_mode=404; EXTRA_ENV="VERDICT=proceed" run "delete: presence proof failing refuses before the DELETE" 1 "presence proof" delete-volume
  check "delete: no write after a failed presence proof" "$([[ -z "$(writes)" ]]; echo $?)"
  world pin_server=$W1 web2_vols=none; EXTRA_ENV="VERDICT=proceed" run "delete: a volume attached to web-1's id is refused" 1 "not the server named" delete-volume
  world delete_code=403; EXTRA_ENV="VERDICT=proceed" run "delete: a 403 on a write names the token tier" 1 "read-only Hetzner token" delete-volume
  world pin_gone; EXTRA_ENV="VERDICT=resume:post_apply" run "delete: a resume verdict never deletes" 0 "skipped" delete-volume
  world; EXTRA_ENV="VERDICT=proceed FLIP=" run "delete: a flip precondition not reported MET refuses" 1 "flip precondition was not reported MET" delete-volume
  check "delete: no write after a missing flip proof" "$([[ -z "$(writes)" ]]; echo $?)"
  world; EXTRA_ENV="VERDICT=proceed FLIP=pending" run "delete: a PENDING flip precondition refuses" 1 "flip precondition was not reported MET" delete-volume
  # ---- state-rm ----
  world pin_gone; EXTRA_ENV="VERDICT=heal:delete_done" run "state-rm: forgets exactly the pinned addresses (serial +1)" 0 "serial 5 -> 6" state-rm
  check "state-rm: one state write naming both addresses" "$([[ "$(writes)" == *'STATE-RM hcloud_volume.workspaces["web-2"] hcloud_volume_attachment.workspaces["web-2"]'* ]]; echo $?)"
  world; EXTRA_ENV="VERDICT=proceed" run "state-rm: refuses while the pin still exists in Hetzner" 1 "not gone" state-rm
  check "state-rm: nothing was written" "$([[ -z "$(writes)" ]]; echo $?)"
  world pin_gone state_vol=888; EXTRA_ENV="VERDICT=heal:delete_done" run "state-rm: refuses a state id that is not the pin" 1 "not the pin" state-rm
  world pin_gone state_vol=888; EXTRA_ENV="VERDICT=heal:delete_done" run "state-rm: a foreign state id writes nothing (the pin is checked BEFORE the write)" 1 "not the pin" state-rm
  check "state-rm: no STATE-RM write for a foreign id" "$([[ -z "$(writes)" ]]; echo $?)"
  world no_web1; run "classify: a state without web-1 is the wrong state object" 1 "not in this state" classify no
  world pin_gone no_bump; EXTRA_ENV="VERDICT=heal:delete_done" run "state-rm: refuses a serial that did not move by one" 1 "exactly one state write" state-rm
  world pin_gone lineage_change; EXTRA_ENV="VERDICT=heal:delete_done" run "state-rm: refuses a changed lineage" 1 "exactly one state write" state-rm
  world pin_gone state_vol_none; EXTRA_ENV="VERDICT=heal:state_rm_done" run "state-rm: a clean state skips" 0 "skipped" state-rm
  world pin_gone state_vol=$NEWV; EXTRA_ENV="VERDICT=resume:post_apply" run "state-rm: a resume verdict never forgets anything" 0 "skipped" state-rm
  world pin_gone; EXTRA_ENV="VERDICT=heal:delete_done APPLY=no" run "state-rm: plan_only (APPLY=no) refuses" 1 "not an apply dispatch" state-rm
  check "state-rm: APPLY=no wrote nothing" "$([[ -z "$(writes)" ]]; echo $?)"
  world pin_gone att=888; EXTRA_ENV="VERDICT=heal:delete_done" run "state-rm: an attachment whose volume_id is not the pin refuses before any write" 1 "attachment volume_id" state-rm
  check "state-rm: no STATE-RM write for a foreign attachment id" "$([[ -z "$(writes)" ]]; echo $?)"
  world pin_gone web1_mode=404; EXTRA_ENV="VERDICT=heal:delete_done" run "state-rm: presence proof failing refuses" 1 "presence proof" state-rm
  world pin_gone no_web1; EXTRA_ENV="VERDICT=heal:delete_done" run "state-rm: a state without web-1 vanishes web-1 from the check" 1 "web-1" state-rm
  # ---- reboot ----
  world pin_gone state_vol_none; run "reboot: re-resolves by name and issues the reboot" 0 "reboot issued" reboot
  check "reboot: the write names web-2's id" "$([[ "$(writes)" == "REBOOT /servers/$SID/actions/reboot " ]]; echo $?)"
  world; echo "$W1" > "$WORLD/server_id"; run "reboot: refuses web-1's id" 1 "web-1's id" reboot
  check "reboot: nothing was rebooted" "$([[ -z "$(writes)" ]]; echo $?)"
  world; echo 4242 > "$WORLD/server_id"; run "reboot: refuses an id that differs from the post-apply state" 1 "differs from the id in the post-apply state" reboot
  world; EXTRA_ENV="APPLY=no" run "reboot: plan_only (APPLY=no) refuses before any call" 1 "not an apply dispatch" reboot
  world; EXTRA_ENV="NEVER_POOLED=" run "reboot: no never-pooled proof (marker present or step skipped) refuses before any call" 1 "no never-pooled proof" reboot
  check "reboot: nothing was rebooted without the never-pooled proof" "$([[ -z "$(writes)" ]]; echo $?)"
  check "reboot: APPLY=no made no write" "$([[ -z "$(writes)" ]]; echo $?)"
  world action_status=running; run "reboot: an action that never finishes fails" 1 "did not finish in time" reboot
  # ---- flip precondition: driven in a SANDBOX tree so the verdict never depends on what the repo's own retirement state is ----
  flip_case() { # <name> <want-rc> <want-substring> <apply yes|no> <filter: real|one|two|zero|garbage> <escrow workflow: present|absent>
    local sb="$TMP/flip.$RANDOM" saved="$SCRIPT_UNDER_TEST"
    mkdir -p "$sb/scripts" "$sb/tests/scripts/lib" "$sb/tests/scripts/fixtures/web-host-rebirth" "$sb/.github/workflows"
    cp "$saved" "$sb/scripts/web2-rebirth.sh"; cp "$ROOT/tests/scripts/lib/web2-rebirth-classify.sh" "$sb/tests/scripts/lib/"
    cp "$ROOT/tests/scripts/fixtures/web-host-rebirth/passphrase-create-password-only.json" "$sb/tests/scripts/fixtures/web-host-rebirth/"
    case "$5" in
      real) cp "$ROOT/tests/scripts/lib/destroy-guard-filter-web-platform.jq" "$sb/tests/scripts/lib/" ;;
      one) printf '{"luks_passphrase_rotations": 1}\n' > "$sb/tests/scripts/lib/destroy-guard-filter-web-platform.jq" ;;
      two) printf '{"luks_passphrase_rotations": 2}\n' > "$sb/tests/scripts/lib/destroy-guard-filter-web-platform.jq" ;;
      zero) printf '{"luks_passphrase_rotations": 0}\n' > "$sb/tests/scripts/lib/destroy-guard-filter-web-platform.jq" ;;
      garbage) printf '"not an object"\n' > "$sb/tests/scripts/lib/destroy-guard-filter-web-platform.jq" ;;
    esac
    [[ "$6" == present ]] && : > "$sb/.github/workflows/apply-web-escrow-create.yml"
    world; SCRIPT_UNDER_TEST="$sb/scripts/web2-rebirth.sh" run "$1" "$2" "$3" flip-precondition "$4"
    SCRIPT_UNDER_TEST="$saved"
  }
  flip_case "flip: the real filter (reads 1: a create of the web-class passphrase counts) and the escrow workflow present: plan_only reports PENDING, rc 0" 0 "PENDING" no real present
  flip_case "flip: the real filter and the escrow workflow present again: an apply run refuses (a regression, not a step)" 1 "NOT met" yes real present
  flip_case "flip: the real filter and the escrow workflow absent: MET, rc 0 on an apply run" 0 "flip precondition: MET" yes real absent
  flip_case "flip: create counted (rotations 1) and the escrow workflow RETIRED: MET, rc 0 on an apply run" 0 "flip precondition: MET" yes one absent
  flip_case "flip: a filter counting 2 is not the shipped design (the key copy is counted too): an apply run refuses" 1 "NOT met" yes two absent
  flip_case "flip: create counted but the escrow workflow still present: an apply run refuses" 1 "NOT met" yes one present
  flip_case "flip: workflow retired but a create not counted (rotations 0): an apply run refuses" 1 "NOT met" yes zero absent
  flip_case "flip: plan_only with only one condition met reports PENDING, rc 0" 0 "PENDING" no one present
  flip_case "flip: an unevaluable filter is a refusal, never a pass" 1 "could not be evaluated" yes garbage absent
  # The REAL repository tree, not a sandbox: the real script, the real jq filter, the real fixture and the real file system. Every other
  # row stubs one of the four, so none of them proves the shipped tree reads MET. Pre-merge this reads MET once the closing change is in.
  world; run "flip: the REAL repository tree reads MET on an apply run (real filter over the tracked fixture, real workflow directory)" 0 "flip precondition: MET" flip-precondition yes
  # ---- ready-poll (the anchor is web-2's own Hetzner creation time) ----
  rdy_row() { jq -cn --arg age "$1" --arg arm "$2" --arg esc "$3" --arg boot "$4" '{ts:"2026-10-06 04:00:00",age_s:$age,message:("SOLEUR_FRESH_BOOT_READY ready=1 stage=cloud_init_complete token=1 vector=1 volume=1 luks=1 luks_arm=" + $arm + " escrow=" + $esc + " boot_id=" + $boot + " host=soleur-web-2 reason=none boot_window_s=900")}'; }
  world server_age=600; rdy_row 60 formatted ok 11111111-2222-3333-4444-555555555555 > "$WORLD/bs_body"
  run "ready: a row newer than the server's creation passes" 0 "luks_arm=formatted" ready-poll
  world server_age=30; rdy_row 60 formatted ok 11111111-2222-3333-4444-555555555555 > "$WORLD/bs_body"
  run "ready: a row OLDER than the server's creation is not this birth (times out)" 1 "no fresh GREEN readiness row" ready-poll
  world server_age=600; rdy_row 60 noop ok 11111111-2222-3333-4444-555555555555 > "$WORLD/bs_body"
  run "ready: luks_arm other than formatted is refused" 1 "not formatted" ready-poll
  world server_age=600; rdy_row 60 formatted missing 11111111-2222-3333-4444-555555555555 > "$WORLD/bs_body"
  run "ready: escrow missing is RED" 1 "readiness row is RED" ready-poll
  world server_age=600; : > "$WORLD/bs_body"; run "ready: no rows at all times out" 1 "no fresh GREEN readiness row" ready-poll
  world server_absent; run "ready: no server named web-2 refuses before any Better Stack read" 1 "could not resolve exactly one server" ready-poll
  world server_created_empty; run "ready: an unreadable creation time refuses (the anchor never falls back to 0)" 1 "creation time is unreadable" ready-poll
  # ---- summary: it claims only what THIS run measured ----
  world; EXTRA_ENV="MODE=plan_only JOB_STATUS=success VERDICT=proceed REASON=because SHA=abc123" run "summary: a plan_only run" 0 "plan_only: no write of any kind occurred" summary
  check "summary: plan_only prints the reason and the commit" "$([[ "$LASTOUT" == *because* && "$LASTOUT" == *abc123* ]]; echo $?)"
  check "summary: plan_only never claims a rebirth or prints the follow-through" "$([[ "$LASTOUT" != *provisioned* && "$LASTOUT" != *Follow-through* ]]; echo $?)"
  world; EXTRA_ENV="MODE=apply JOB_STATUS=failure VERDICT=proceed" run "summary: a failed apply run" 0 "did not complete" summary
  check "summary: a failed run does not claim provisioning or the follow-through" "$([[ "$LASTOUT" != *provisioned* && "$LASTOUT" != *Follow-through* ]]; echo $?)"
  world; EXTRA_ENV="MODE=apply JOB_STATUS=success VERDICT=proceed RUN_ID=77 EMPTINESS=PASS-x" run "summary: a successful apply run" 0 "Nothing is claimed until the #6931 grader reports PASS" summary
  check "summary: success prints the reborn host, the approver and the update-not-enrol instruction" "$([[ "$LASTOUT" == *"server_id=1001"* && "$LASTOUT" == *approver-one* && "$LASTOUT" == *"already enrolled"* ]]; echo $?)"
  check "summary: the step summary file received the same text" "$(grep -q 'Nothing is claimed until the #6931 grader reports PASS' "$WORLD/summary"; echo $?)"
  check "summary: success states the rule without a reboot and not the old boot_id proof" "$([[ "$LASTOUT" == *"no reboot is required"* && "$LASTOUT" == *"luks_arm formatted|opened"* && "$LASTOUT" != *"boot_id other than"* ]]; echo $?)"
  world; EXTRA_ENV="MODE=apply JOB_STATUS=success VERDICT=resume:post_apply RUN_ID=77" run "summary: a RESUME run says nothing was replaced" 0 "This was a RESUME" summary
  local want_earliest; want_earliest="$(date -u -d "@$(( $(date -u +%s) - 7200 + 259200 ))" +%Y-%m-%d)"
  check "summary: a resume run does not claim the rebirth applied, and the follow-through date is the server's creation + 3 days" "$([[ "$LASTOUT" != *"The rebirth applied"* && "$LASTOUT" == *"to ${want_earliest} (rebirth + 3 days)"* ]]; echo $?)"
  world; EXTRA_ARR=("MODE=plan_only" "JOB_STATUS=success" "VERDICT=proceed" "REASON=$(printf 'x\n::error::forged | row')")
  run "summary: free text cannot start a workflow command or break the table" 0 "plan_only" summary
  EXTRA_ARR=()
  check "summary: no output line starts with ::" "$([[ "$(grep -c '^::' <<<"$LASTOUT")" == 0 && "$LASTOUT" != *"| row"* ]]; echo $?)"
  # ---- structural ----
  # the dispatcher's verbs are exactly this set (a new verb must be classified here, in the same edit), and EVERY function that writes
  # (a Hetzner POST/DELETE, a state rm) calls require_apply before it does
  local verbs; verbs="$(sed -nE 's/^  ([a-z-]+)\) .*cmd_[a-z_]+.*;;$/\1/p' "$SCRIPT_UNDER_TEST" | LC_ALL=C sort | tr '\n' ' ')"
  check "the dispatcher serves exactly the known verbs (got: ${verbs})" "$([[ "$verbs" == "classify delete-volume flip-precondition ready-poll reboot state-rm summary " ]]; echo $?)"
  check "the readiness reader looks back 4 days (a 72 h-old resume must still find the once-per-instance row)" "$(grep -q 'w2l_fetch_ready "$tmp/ready.jsonl" 4 20' "$(dirname "$SCRIPT_UNDER_TEST")/web2-rebirth-ready-poll.sh"; echo $?)"
  local unguarded; unguarded="$(awk '/^[a-z_0-9]+\(\) \{/{name=$1; has=0; writes=0} /require_apply/{has=1} /hapi (POST|DELETE)|terraform state rm/{ if(!has) bad[name]=1 } END{for(k in bad) printf "%s ", k}' "$SCRIPT_UNDER_TEST")"
  check "every function that writes calls require_apply first (unguarded: ${unguarded})" "$([[ -z "$unguarded" ]]; echo $?)"

  check "no unexpected API call in any row of THIS battery" "$(! ls "$BATTERY_DIR"/world.*/unexpected.log >/dev/null 2>&1; echo $?)"
  n=$((n + 1))
  printf 'RAN %s\n' "$(( $(wc -l < "$BATTERY_DIR/runs") + $(wc -l < "$BATTERY_DIR/checks") ))"
}

fails=0
report="$(battery "$SCRIPT" 2>&1)"
while IFS= read -r line; do
  case "$line" in FAILED*) fails=$((fails + 1)); printf '  FAIL %s\n' "${line#FAILED }" ;; RAN*) ran="${line#RAN }" ;; *) [[ -z "$line" ]] || printf '       %s\n' "$line" ;; esac
done <<<"$report"
ran="${ran:-0}"
printf 'real script: %s world scenarios, %s failed\n' "$ran" "$fails"
# Floor = the exact count: the 120 this suite ran on main plus the 3 rows the closing change added (a real-tree MET row, a
# sandbox "real filter, escrow workflow absent" row and the exactly-1 refusal row), so deleting either one reds instead of hiding in slack.
[[ "$ran" -ge 123 ]] || { echo "  FAIL scenario floor: ran ${ran} < 123"; fails=$((fails + 1)); }

# Mutants are independent (each works in its own sandbox tree and fake worlds), so up to MUT_JOBS run at once; every mutant writes
# its verdict line to its own file and the lines are counted once all have finished.
MUT_JOBS="${MUT_JOBS:-6}"; MUT_SEQ=0; mkdir -p "$TMP/mres"
_mutate_run() { # <idx> <name> <old> <new> [file]
  local idx="$1" name="$2" old="$3" new="$4" target="${5:-web2-rebirth.sh}" copy after mdir="$TMP/mut.$BASHPID"
  mkdir -p "$mdir/scripts" "$mdir/tests/scripts/lib" "$mdir/tests/scripts/fixtures" "$mdir/.github/workflows"
  copy="$mdir/scripts/$target"
  cp "$SCRIPT" "$mdir/scripts/web2-rebirth.sh"; cp "$ROOT/scripts/web2-rebirth-ready-poll.sh" "$mdir/scripts/"; cp -r "$ROOT/scripts/lib" "$ROOT/scripts/betterstack-query.sh" "$mdir/scripts/"
  cp "$ROOT/tests/scripts/lib/web2-rebirth-classify.sh" "$ROOT/tests/scripts/lib/destroy-guard-filter-web-platform.jq" "$mdir/tests/scripts/lib/"
  cp -r "$ROOT/tests/scripts/fixtures/web-host-rebirth" "$mdir/tests/scripts/fixtures/"
  if ! python3 - "$copy" "$old" "$new" <<'PY'
import sys
p, old, new = sys.argv[1:4]
s = open(p).read()
if s.count(old) != 1:
    sys.exit(1)
open(p, "w").write(s.replace(old, new))
PY
  then echo "  FAIL mutation '${name}': the edit did not land exactly once" > "$TMP/mres/$idx"; return; fi
  after="$(battery "$mdir/scripts/web2-rebirth.sh" 2>&1 | grep -c '^FAILED')"
  if [[ "$after" -gt 0 ]]; then echo "  ok   mutation killed: ${name} (${after} rows red)" > "$TMP/mres/$idx"; else echo "  FAIL mutation SURVIVED: ${name}" > "$TMP/mres/$idx"; fi
  rm -rf "$mdir"
}
mutate() { # <name> <old> <new> [file under scripts/ to mutate, default web2-rebirth.sh]
  MUT_SEQ=$((MUT_SEQ + 1))
  while [[ "$(jobs -rp | wc -l | tr -d ' ')" -ge "$MUT_JOBS" ]]; do sleep 0.3; done
  _mutate_run "$MUT_SEQ" "$@" &
}
mutate "delete: the ext4/name re-assert is dropped" '.volume.format == "ext4" and .volume.name == $n and .volume.labels == {app: $a}' 'true'
mutate "delete: the stage guard is dropped" 'if ! stage_allowed "$v" proceed heal:detach_done; then' 'if false; then'
mutate "delete: the 404-after-delete proof is dropped" '[[ "$code" == 404 ]] || fail "volume ${PINNED_VOLUME_ID} still answers ${code} after the delete"' ':'
mutate "delete: the attached-server re-assert is dropped" '|| fail "re-assert: volume ${PINNED_VOLUME_ID} is attached to ${attached}, which is not the server named ${WEB2_NAME}"' '|| true'
mutate "state-rm: the gone-in-Hetzner proof is dropped" '[[ "$code" == 404 ]] || fail "state-rm: volume ${PINNED_VOLUME_ID} answers ${code}, not 404: it is not gone, nothing is forgotten"' ':'
mutate "state-rm: the state-id pin is dropped" '[[ "$vol" == "$PINNED_VOLUME_ID" ]] || fail' 'true || fail'
mutate "state-rm: the serial/lineage check is dropped" '|| fail "state-rm: the removal was not exactly one state write of the pinned address"' '|| true'
mutate "reboot: web-1 refusal is dropped" '[[ "$sid" != "$WEB1_SERVER_ID" ]] || fail "reboot:' 'true || fail "reboot:'
mutate "reboot: the post-apply state id comparison is dropped" '[[ "$state_sid" == "$sid" ]] || fail' 'true || fail'
mutate "flip: the apply refusal is dropped" 'if [[ "$apply" == yes ]]; then
    fail "flip precondition NOT met' 'if false; then
    fail "flip precondition NOT met'
mutate "ready: the run-anchor freshness is dropped" 'if [[ "$age" =~ ^[0-9]+$ ]] && (( age < now - anchor )); then
        [[ "$row_arm" == formatted ]]' 'if true; then
        [[ "$row_arm" == formatted ]]' web2-rebirth-ready-poll.sh
mutate "ready: the lookback is shortened to 1 day" 'w2l_fetch_ready "$tmp/ready.jsonl" 4 20' 'w2l_fetch_ready "$tmp/ready.jsonl" 1 20' web2-rebirth-ready-poll.sh
mutate "ready: the formatted-arm requirement is dropped" '[[ "$row_arm" == formatted ]] || fail' 'true || fail' web2-rebirth-ready-poll.sh
mutate "classify: the pause is forced real" '[[ "$apply" == yes ]] && { pause_real && pause=yes || pause=no; }' 'pause=yes'
mutate "classify: the web-1-in-state sanity check is dropped" '[[ "$(jq -r '"'"'.web1'"'"' <<<"$ident")" == 1 ]] || fail' 'true || fail'

mutate "delete: require_apply dropped (plan_only could delete)" '  require_apply delete-volume
' ''
mutate "state-rm: require_apply dropped" '  require_apply state-rm
' ''
mutate "reboot: require_apply dropped" '  require_apply reboot
' ''
mutate "delete: the emptiness proof requirement is dropped" '  case "${EMPTINESS:-}" in PASS*) : ;; *) fail "delete-volume refused: no PASS emptiness verdict from the evidence step (got '"'"'${EMPTINESS:-}'"'"'); nothing is deleted" ;; esac
' ''
mutate "delete: the never-pooled proof requirement is dropped" '  [[ "${NEVER_POOLED:-}" == absent ]] || fail "delete-volume refused: no never-pooled proof (got '"'"'${NEVER_POOLED:-}'"'"'); nothing is deleted"
' ''
mutate "delete: the pre-plan-graded requirement is dropped" '  [[ "${PRE_PLAN:-}" == graded ]] || fail "delete-volume refused: the pre plan was not graded (got '"'"'${PRE_PLAN:-}'"'"'); nothing is deleted"
' ''
mutate "delete: the presence proof is dropped" '  presence_proof
  code="$(hapi GET "/volumes/${PINNED_VOLUME_ID}")"
  [[ "$code" == 200 ]] || fail "re-assert' '  code="$(hapi GET "/volumes/${PINNED_VOLUME_ID}")"
  [[ "$code" == 200 ]] || fail "re-assert'
mutate "state-rm: the presence proof is dropped" '  presence_proof
  code="$(hapi GET "/volumes/${PINNED_VOLUME_ID}")"
  [[ "$code" == 404 ]]' '  code="$(hapi GET "/volumes/${PINNED_VOLUME_ID}")"
  [[ "$code" == 404 ]]'
mutate "classify: the presence proof is dropped" '  need_token; presence_proof
  local apply' '  need_token
  local apply'
mutate "classify: only one push-apply workflow is checked" '  for wf in apply-web-platform-infra.yml apply-deploy-pipeline-fix.yml; do' '  for wf in apply-web-platform-infra.yml; do'
mutate "classify: a busy push-apply run is ignored" '    [[ "$busy" == 0 ]] || return 1' '    true'
mutate "delete: a failed detach is ignored" '    [[ "$code" == 201 ]] || fail "detach -> ${code}' '    true || fail "detach -> ${code}'
mutate "delete: a failed detach action is ignored" '      [[ "$st" == error ]] && fail "detach action' '      false && fail "detach action'
mutate "delete: an unfinished detach action is ignored" '    [[ "$st" == success ]] || fail "detach action ${action_id} did not finish in time"' '    true || fail "detach action ${action_id} did not finish in time"'
mutate "delete: the empty-name-lookup proof is dropped" '  [[ "$code" == 200 && "$(jq -r '"'"'.volumes | length'"'"' "$HBODY")" == 0 ]] || fail "a volume named' '  true || fail "a volume named'
mutate "classify: a 5xx on the pinned volume is accepted" 'fail "GET /volumes/${PINNED_VOLUME_ID} -> ${code} (error.code=$(errcode)): neither present nor gone; nothing is written"' 'true'
mutate "delete: the flip proof requirement is dropped" '  [[ "${FLIP:-}" == met ]] || fail "delete-volume refused: the flip precondition was not reported MET by its step (got '"'"'${FLIP:-}'"'"'); nothing is deleted"
' ''
mutate "reboot: the never-pooled proof requirement is dropped" '  [[ "${NEVER_POOLED:-}" == absent ]] || fail "reboot refused: no never-pooled proof (got '"'"'${NEVER_POOLED:-}'"'"'); nothing is rebooted"
' ''
mutate "classify: an absent creation time reads as an age" '       if [[ -n "$created" ]] && created_epoch=' '       if created_epoch='
mutate "ready: an unreadable creation time is accepted" '|| fail "ready-poll: the server'"'"'s creation time is unreadable' '|| true # ready-poll: the server'"'"'s creation time is unreadable'
mutate "output: newlines in a value are no longer stripped" 'local v="${2//$'"'"'\r'"'"'/ }"; v="${v//$'"'"'\n'"'"'/ }";' 'local v="$2";'
mutate "summary: the resume sentence is dropped" '          echo "**This was a RESUME:** nothing' '          echo "**This was not a resume:** nothing'
mutate "flip: the rotations==1 requirement is dropped" '  [[ "$n" -eq 1 ]] || ok=no' ':'
mutate "flip: the escrow-workflow-absent requirement is dropped" '  [[ ! -e "${_ROOT}/.github/workflows/apply-web-escrow-create.yml" ]] || absent=no' ':'
mutate "reboot: an unfinished reboot action is ignored" '  fail "reboot action ${action_id} did not finish in time"' '  true'
mutate "ready: the anchor is not the server creation time" '  exec bash "${_ROOT}/scripts/web2-rebirth-ready-poll.sh" "$created_epoch"' '  exec bash "${_ROOT}/scripts/web2-rebirth-ready-poll.sh" 0'
mutate "classify: web2_age_s is not handed to the classifier" ' web2_age_s="$WEB2_AGE_S")"' ')"'
mutate "summary: a plan_only run reaches the success claim" '      plan_only:*) echo' '      plan_only:never) echo'
mutate "summary: a failed run reaches the success claim" '      apply:success)' '      apply:*)'

wait
# One verdict line per mutant: count them against the number launched (a mutant that never wrote its line is a failure).
for f in "$TMP"/mres/*; do cat "$f"; grep -q '^  FAIL' "$f" && fails=$((fails + 1)); done
[[ "$(find "$TMP/mres" -type f | wc -l | tr -d ' ')" -eq "$MUT_SEQ" ]] || { echo "  FAIL a mutant did not report ($(find "$TMP/mres" -type f | wc -l | tr -d ' ') of ${MUT_SEQ})"; fails=$((fails + 1)); }
[[ "$fails" -eq 0 ]] && { echo "web2-rebirth: all scenarios and mutations passed"; exit 0; }
echo "web2-rebirth: ${fails} FAILED"; exit 1
