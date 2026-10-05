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
  "GET /servers/123931471") reply 200 '{"server":{"id":123931471,"name":"soleur-web-platform","volumes":[106443278]}}' ;;
  "GET /servers?name=soleur-web-2")
    if [[ -f "$W/server_absent" ]]; then reply 200 '{"servers":[]}'
    else reply 200 "$(jq -cn --arg id "$(cat "$W/server_id")" --argjson v "[$(cat "$W/server_vols")]" '{servers:[{id:($id|tonumber),name:"soleur-web-2",volumes:$v}]}')"; fi ;;
  "GET /volumes/106466179")
    if [[ -f "$W/pin_gone" ]]; then reply 404 '{"error":{"code":"not_found"}}'
    else reply 200 "$(vol_json 106466179 "$(cat "$W/pin_name")" "$(cat "$W/pin_format")" "$(cat "$W/pin_server")" "$(cat "$W/pin_app")")"; fi ;;
  "GET /volumes?name=soleur-web-platform-data-web-2")
    ids=""; [[ -f "$W/pin_gone" ]] || ids="106466179"
    for x in $(cat "$W/other_named" 2>/dev/null); do ids="$ids $x"; done
    reply 200 "$(printf '%s\n' $ids | jq -Rn '[inputs | select(length>0) | {id: tonumber}] | {volumes: .}')" ;;
  "POST /volumes/106466179/actions/detach") echo none > "$W/pin_server"; echo "DETACH" >> "$W/writes.log"; reply 201 '{"action":{"id":9,"status":"running"}}' ;;
  "GET /actions/9") reply 200 '{"action":{"id":9,"status":"success"}}' ;;
  "GET /actions/10") reply 200 '{"action":{"id":10,"status":"success"}}' ;;
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
  "api repos/"*) st="$(cat "$W/wf_state" 2>/dev/null || echo disabled_manually)"; printf '{"state":"%s"}' "$st" ;;
  "run list") printf '[]' ;;
  *) echo "unexpected gh $*" >> "$W/unexpected.log"; exit 1 ;;
esac
SH
chmod +x "$TMP/bin/"*

# world <scenario flags...> — build the fake world. Defaults: the FIRST dispatch (pin attached to web-2, in state).
world() {
  W="$TMP/world.$RANDOM"; rm -rf "$W"; mkdir -p "$W"; export WORLD="$W"
  echo "$SID" > "$W/server_id"; echo "$PIN" > "$W/server_vols"; echo "$SID" > "$W/pin_server"
  echo soleur-web-platform-data-web-2 > "$W/pin_name"; echo ext4 > "$W/pin_format"; echo soleur-web-platform > "$W/pin_app"
  : > "$W/calls.log"; : > "$W/writes.log"
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
  echo x >> "$TMP/runs"
  o="$(env PATH="$TMP/bin:/usr/bin:/bin" WORLD="$WORLD" HCLOUD_TOKEN=tok REPO=o/r GH_TOKEN=x INFRA_DIR="$TMP" GITHUB_OUTPUT="$WORLD/gh_out" GITHUB_STEP_SUMMARY="$WORLD/summary" \
        WEB2_REBIRTH_POLL_INTERVAL_S=0 WEB2_REBIRTH_ACTION_POLL_S=0 WEB2_REBIRTH_POLL_ATTEMPTS=2 \
        BETTERSTACK_QUERY_HOST=fixture-connect.betterstackdata.com BETTERSTACK_QUERY_USERNAME=u BETTERSTACK_QUERY_PASSWORD=p ${EXTRA_ENV:-} \
        bash "$SCRIPT_UNDER_TEST" "$@" 2>&1)" || rc=$?
  LASTOUT="$o"
  if [[ "$rc" -ne "$want" ]]; then printf 'FAILED %s (rc=%s want=%s) %s\n' "$name" "$rc" "$want" "${o:0:240}"; return; fi
  if [[ "$sub" != "-" && "$o" != *"$sub"* ]]; then printf 'FAILED %s (output lacks %q) %s\n' "$name" "$sub" "${o:0:240}"; fi
}
verdict_of() { sed -n 's/^verdict=//p' "$WORLD/gh_out" | tail -1; }
writes() { tr '\n' ' ' < "$WORLD/writes.log"; }
check() { # <name> <condition-result 0|1>
  if [[ "$2" -ne 0 ]]; then printf 'FAILED %s\n' "$1"; fi
}

battery() {
  SCRIPT_UNDER_TEST="$1"; local n=0
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
  world pin_gone state_vol=$NEWV other_named=$NEWV web2_vols=$NEWV; run "classify: already reborn refuses" 1 "already_reborn" classify no
  world pin_format=none; run "classify: a formatted pinned volume refuses" 1 "not_the_empty_plaintext_one" classify no
  world pin_server=999; run "classify: pinned volume attached elsewhere refuses" 1 "attached_elsewhere" classify no
  world other_named=$NEWV; run "classify: two volumes with the name refuse" 1 "duplicate_volume_name" classify no
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
  # ---- reboot ----
  world pin_gone state_vol_none; run "reboot: re-resolves by name and issues the reboot" 0 "reboot issued" reboot
  check "reboot: the write names web-2's id" "$([[ "$(writes)" == "REBOOT /servers/$SID/actions/reboot " ]]; echo $?)"
  world; echo "$W1" > "$WORLD/server_id"; run "reboot: refuses web-1's id" 1 "web-1's id" reboot
  check "reboot: nothing was rebooted" "$([[ -z "$(writes)" ]]; echo $?)"
  world; echo 4242 > "$WORLD/server_id"; run "reboot: refuses an id that differs from the post-apply state" 1 "differs from the id in the post-apply state" reboot
  # ---- flip precondition ----
  world; run "flip: plan_only reports PENDING and exits 0" 0 "PENDING" flip-precondition no
  world; run "flip: apply refuses while the exemption is not flipped" 1 "NOT met" flip-precondition yes
  # ---- ready-poll ----
  world; now="$(date -u +%s)"
  rdy_row() { jq -cn --arg age "$1" --arg arm "$2" --arg esc "$3" --arg boot "$4" '{ts:"2026-10-06 04:00:00",age_s:$age,message:("SOLEUR_FRESH_BOOT_READY ready=1 stage=cloud_init_complete token=1 vector=1 volume=1 luks=1 luks_arm=" + $arm + " escrow=" + $esc + " boot_id=" + $boot + " host=soleur-web-2 reason=none boot_window_s=900")}'; }
  rdy_row 60 formatted ok 11111111-2222-3333-4444-555555555555 > "$WORLD/bs_body"
  run "ready: a fresh formatted ok row passes" 0 "luks_arm=formatted" ready-poll "$((now - 600))"
  rdy_row 60 formatted ok 11111111-2222-3333-4444-555555555555 > "$WORLD/bs_body"
  run "ready: a row OLDER than the run anchor is not this birth (times out)" 1 "no fresh GREEN readiness row" ready-poll "$((now - 30))"
  rdy_row 60 noop ok 11111111-2222-3333-4444-555555555555 > "$WORLD/bs_body"
  run "ready: luks_arm other than formatted is refused" 1 "not formatted" ready-poll "$((now - 600))"
  rdy_row 60 formatted missing 11111111-2222-3333-4444-555555555555 > "$WORLD/bs_body"
  run "ready: escrow missing is RED" 1 "readiness row is RED" ready-poll "$((now - 600))"
  : > "$WORLD/bs_body"; run "ready: no rows at all times out" 1 "no fresh GREEN readiness row" ready-poll "$((now - 600))"
  # ---- summary ----
  world; EXTRA_ENV="VERDICT=proceed" run "summary: prints the closing claim guard" 0 "-" summary
  check "summary: claims nothing before the reboot proof" "$(grep -q 'Nothing is claimed until the graded reboot proof' "$WORLD/summary"; echo $?)"
  # ---- structural ----
  check "no unexpected API call in any row" "$(! ls "$TMP"/world.*/unexpected.log >/dev/null 2>&1; echo $?)"
  n=$((n + 1))
  printf 'RAN %s\n' "$(wc -l < "$TMP/runs" | tr -d ' ')"
}

fails=0
report="$(battery "$SCRIPT" 2>&1)"
while IFS= read -r line; do
  case "$line" in FAILED*) fails=$((fails + 1)); printf '  FAIL %s\n' "${line#FAILED }" ;; RAN*) ran="${line#RAN }" ;; *) [[ -z "$line" ]] || printf '       %s\n' "$line" ;; esac
done <<<"$report"
ran="${ran:-0}"
printf 'real script: %s world scenarios, %s failed\n' "$ran" "$fails"
[[ "$ran" -ge 40 ]] || { echo "  FAIL scenario floor: ran ${ran} < 40"; fails=$((fails + 1)); }

mutate() { # <name> <old> <new> [file under scripts/ to mutate, default web2-rebirth.sh]
  local name="$1" old="$2" new="$3" target="${4:-web2-rebirth.sh}" copy after
  rm -rf "$TMP/mut"; mkdir -p "$TMP/mut/scripts" "$TMP/mut/tests/scripts/lib" "$TMP/mut/tests/scripts/fixtures" "$TMP/mut/.github/workflows"
  copy="$TMP/mut/scripts/$target"
  cp "$SCRIPT" "$TMP/mut/scripts/web2-rebirth.sh"; cp "$ROOT/scripts/web2-rebirth-ready-poll.sh" "$TMP/mut/scripts/"; cp -r "$ROOT/scripts/lib" "$ROOT/scripts/betterstack-query.sh" "$TMP/mut/scripts/"
  cp "$ROOT/tests/scripts/lib/web2-rebirth-classify.sh" "$ROOT/tests/scripts/lib/destroy-guard-filter-web-platform.jq" "$TMP/mut/tests/scripts/lib/"
  cp -r "$ROOT/tests/scripts/fixtures/web-host-rebirth" "$TMP/mut/tests/scripts/fixtures/"
  if ! python3 - "$copy" "$old" "$new" <<'PY'
import sys
p, old, new = sys.argv[1:4]
s = open(p).read()
if s.count(old) != 1:
    sys.exit(1)
open(p, "w").write(s.replace(old, new))
PY
  then echo "  FAIL mutation '${name}': the edit did not land exactly once"; fails=$((fails + 1)); return; fi
  after="$(battery "$TMP/mut/scripts/web2-rebirth.sh" 2>&1 | grep -c '^FAILED')"
  if [[ "$after" -gt 0 ]]; then echo "  ok   mutation killed: ${name} (${after} rows red)"; else echo "  FAIL mutation SURVIVED: ${name}"; fails=$((fails + 1)); fi
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
mutate "ready: the formatted-arm requirement is dropped" '[[ "$row_arm" == formatted ]] || fail' 'true || fail' web2-rebirth-ready-poll.sh
mutate "classify: the pause is forced real" '[[ "$apply" == yes ]] && { pause_real && pause=yes || pause=no; }' 'pause=yes'
mutate "classify: the web-1-in-state sanity check is dropped" '[[ "$(jq -r '"'"'.web1'"'"' <<<"$ident")" == 1 ]] || fail' 'true || fail'

[[ "$fails" -eq 0 ]] && { echo "web2-rebirth: all scenarios and mutations passed"; exit 0; }
echo "web2-rebirth: ${fails} FAILED"; exit 1
