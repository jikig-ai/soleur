#!/usr/bin/env bash
# Tests for scripts/web-host-reboot.sh (the one reboot write) and scripts/web-host-reboot-evidence.sh (the read-only
# evidence reader), #9372. Both scripts run for real under the production shell against a fake world (a directory of small
# files that curl, terraform, gh, date and sleep shims read and write). A mutation battery then breaks each load-bearing
# check on a COPY of the subject and requires the battery to go red.
# shellcheck disable=SC2319,SC2034
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${DIR}/.." && pwd)"
RSCRIPT="${ROOT}/scripts/web-host-reboot.sh"
ESCRIPT="${ROOT}/scripts/web-host-reboot-evidence.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
REAL_DATE="$(command -v date)"
TOK="tok-SENTINEL-9f3a7c"
SID=169095540
FOOTER='This run reports rows only. It makes no statement about the volume or its encryption; grading belongs to scripts/followthroughs/web2-luks-live-6931.sh.'
# The claim denylist (case-insensitive, whole-token: the neighbours of a hit must not be a letter or a digit, so the plain
# word "unconfirmed" in an outcome message is not a hit on "confirmed").
DENY_RE='(^|[^a-z0-9])(luks-backed|encrypted|reborn|reopen|proof|verified|confirmed|proves|crypto_luks|/dev/mapper|luks=1|escrow=ok)($|[^a-z0-9])'
CUR=479cd3f318da4a5d85068d3382a8723f; CURD=479cd3f3-18da-4a5d-8506-8d3382a8723f
NEW=a1b2c3d4e5f60718293a4b5c6d7e8f90; NEWD=a1b2c3d4-e5f6-0718-293a-4b5c6d7e8f90
OTH=0f0e0d0c0b0a09080706050403020100
SINCE_DEFAULT=600
export LC_ALL=C

command -v jq >/dev/null || { printf 'FAIL jq is required\n'; exit 1; }
command -v python3 >/dev/null || { printf 'FAIL python3 is required\n'; exit 1; }

mkdir -p "$TMP/bin"
# ---- curl shim: Hetzner (token on stdin) and Better Stack (the query script's POST) ------------------------------------------
cat > "$TMP/bin/curl" <<'SH'
#!/usr/bin/env bash
W="${WORLD:?}"
method=GET; body_out=""; url=""; data=""; have_cfg=0
echo "$*" >> "$W/argv.log"
while [[ $# -gt 0 ]]; do
  case "$1" in
    -X) method="$2"; shift 2 ;; -o) body_out="$2"; shift 2 ;; --data|-d) data="$2"; shift 2 ;;
    --config) have_cfg=1; shift 2 ;; -w|--max-time|-H|-u|--url) shift 2 ;; http*) url="$1"; shift ;; *) shift ;;
  esac
done
[[ "$have_cfg" == 1 ]] && cat > "$W/stdin.last"
reply() { printf '%s' "$2" > "${body_out:-/dev/null}"; printf '%s' "$1"; }
case "$url" in
  *betterstackdata.com*)
    echo Q >> "$W/order.log"; printf '%s\n---\n' "$data" >> "$W/sql.log"
    case "$data" in *_BOOT_ID*) kind=boots ;; *SOLEUR_FRESH_BOOT_READY*) kind=ready ;; *luks-monitor*) kind=probe ;; *) kind=other ;; esac
    echo "$kind" >> "$W/queries.log"
    if [[ -f "$W/bsfail.$kind" ]]; then
      n="$(cat "$W/bsfail.$kind")"; mode="$(cat "$W/bsfail_mode.$kind" 2>/dev/null || echo 503)"
      if [[ "$n" -gt 0 ]]; then
        echo $((n - 1)) > "$W/bsfail.$kind"
        if [[ "$mode" == timeout ]]; then exit 28; fi
        printf '{"error":"upstream"}'; exit 22
      fi
    fi
    [[ "$kind" == other ]] && { echo "UNEXPECTED betterstack query" >> "$W/unexpected.log"; exit 22; }
    cat "$W/bs.$kind" 2>/dev/null; exit 0 ;;
esac
path="${url#https://api.hetzner.cloud/v1}"
echo "$method ${path}" >> "$W/calls.log"
case "$method $path" in
  "GET /servers?name=soleur-web-2")
    case "$(cat "$W/servers_mode")" in
      zero) reply 200 '{"servers":[]}' ;;
      two) reply 200 '{"servers":[{"id":1,"name":"soleur-web-2"},{"id":2,"name":"soleur-web-2"}]}' ;;
      http500) reply 500 '{"error":{"code":"boom"}}' ;;
      wrongname) reply 200 "$(jq -cn '{servers:[{id:169095540,name:"someone-else"}]}')" ;;
      *) reply 200 "$(jq -cn --arg id "$(cat "$W/server_id")" --arg c "$(cat "$W/server_created")" \
           '{servers:[{id:(if ($id|test("^[0-9]+$")) then ($id|tonumber) else $id end),name:"soleur-web-2",status:"running",created:$c,volumes:[107059048],rescue_enabled:false,locked:false}]}')" ;;
    esac ;;
  "POST /servers/"*"/actions/reboot")
    echo "REBOOT ${path}" >> "$W/writes.log"
    if grep -q '^anchor_epoch=' "$W/gh_out" 2>/dev/null; then echo yes >> "$W/anchor_at_post"; else echo no >> "$W/anchor_at_post"; fi
    pc="$(cat "$W/post_code" 2>/dev/null || echo 201)"
    if [[ "$pc" == 201 ]]; then
      if [[ -f "$W/post_noid" ]]; then reply 201 '{"action":{"status":"running"}}'; else reply 201 '{"action":{"id":10,"status":"running"}}'; fi
    else reply "$pc" '{"error":{"code":"locked"}}'; fi ;;
  "GET /actions/10")
    reply "$(cat "$W/action_get_code" 2>/dev/null || echo 200)" "$(jq -cn --arg st "$(cat "$W/action_status" 2>/dev/null || echo success)" '{action:{id:10,status:$st,error:{code:"x"}}}')" ;;
  *) echo "UNEXPECTED $method $path" >> "$W/unexpected.log"; reply 599 '{"error":{"code":"unexpected"}}' ;;
esac
SH
cat > "$TMP/bin/terraform" <<'SH'
#!/usr/bin/env bash
W="${WORLD:?}"
case "$1 $2" in
  "state pull")
    [[ -f "$W/state_fail" ]] && exit 1
    jq -cn --argjson w1 "$(cat "$W/state_web1")" --arg w2 "$(cat "$W/state_web2")" '{serial:5,lineage:"L1",resources:[
      {mode:"managed",type:"hcloud_server",name:"web",instances:((if $w1 == 1 then [{index_key:"web-1",attributes:{id:123931471}}] else [] end)
        + (if $w2 == "none" then [] else [{index_key:"web-2",attributes:{id:(if ($w2|test("^[0-9]+$")) then ($w2|tonumber) else $w2 end)}}] end))}]}' ;;
  *) echo "unexpected terraform $*" >> "$W/unexpected.log"; exit 1 ;;
esac
SH
cat > "$TMP/bin/gh" <<'SH'
#!/usr/bin/env bash
W="${WORLD:?}"
echo "$*" >> "$W/gh.log"
[[ -f "$W/approvals_fail" ]] && exit 1
prog=""; args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do [[ "${args[i]}" == --jq ]] && prog="${args[i+1]}"; done
case "$1 $2" in
  "api repos/"*"/approvals") if [[ -n "$prog" ]]; then jq -r "$prog" "$W/approvals"; else cat "$W/approvals"; fi ;;
  *) echo "unexpected gh $*" >> "$W/unexpected.log"; exit 1 ;;
esac
SH
{ printf '#!/usr/bin/env bash\nREAL=%q\n' "$REAL_DATE"; cat <<'SH'
W="${WORLD:-}"
if [[ "${1:-}" == -u && "${2:-}" == +%s && $# -eq 2 ]]; then
  [[ -n "$W" ]] && echo D >> "$W/order.log"
  if [[ -n "$W" && -f "$W/clock" ]]; then cat "$W/clock"; else exec "$REAL" -u +%s; fi
  exit 0
fi
exec "$REAL" "$@"
SH
} > "$TMP/bin/date"
cat > "$TMP/bin/sleep" <<'SH'
#!/usr/bin/env bash
W="${WORLD:-}"
[[ -n "$W" ]] && echo S >> "$W/order.log"
if [[ -n "$W" && -f "$W/clock" && "${1:-}" =~ ^[0-9]+$ ]]; then echo $(( $(cat "$W/clock") + $1 )) > "$W/clock"; fi
exit 0
SH
chmod +x "$TMP/bin/"*

# ---- fixtures built from the real emitted row shapes ---------------------------------------------------------------------
fx_age() { if [[ -n "${FX_BARE:-}" ]]; then printf '%s' "$1"; else printf '"%s"' "$1"; fi; }  # quoted-integer (helper contract) or bare number (measured live)
fx_ready() { # age boot_dashed [arm]
  jq -cn --argjson a "$(fx_age "$1")" --arg m "SOLEUR_FRESH_BOOT_READY ready=1 stage=cloud_init_complete token=1 vector=1 volume=1 luks=1 luks_arm=${3:-opened} escrow=ok boot_id=$2 host=soleur-web-2 reason=none boot_window_s=900" \
    '{ts:"2026-10-06 19:36:25.034666",age_s:$a,message:$m}'
}
fx_probe() { # kind(ok|fail|malformed) age boot_dashed -> the two journal copies of one row
  local kind="$1" age="$2" boot="${3:-}" msg m
  case "$kind" in
    ok) msg="OK: /mnt/data is LUKS-backed (device_type=crypto_LUKS mount_source=/dev/mapper/workspaces escrow=ok header=readable boot_id=${boot})" ;;
    fail) msg="FAIL (header_unreadable): the header could not be read" ;;
    malformed) msg="OK: /mnt/data is LUKS-backed (device_type=crypto_LUKS mount_source" ;;
  esac
  for m in "$msg" "[luks-monitor] $msg"; do
    jq -cn --argjson a "$(fx_age "$age")" --arg m "$m" '{ts:"2026-10-07 00:18:57.117005",age_s:$a,message:$m,host_name:"soleur-web-2",ident:"luks-monitor",unit:"luks-monitor.service"}'
  done
}
fx_boot() { # id first_age newest_age n
  jq -cn --arg id "$1" --argjson f "$(fx_age "$2")" --argjson ne "$(fx_age "$3")" --argjson n "$(fx_age "${4:-100}")" '{bid:$id,n:$n,newest_age_s:$ne,first_age_s:$f}'
}

# ---- the world ---------------------------------------------------------------------------------------------------------
WN=0
world() { # flags...   (builds the reboot AND evidence world; every file is one small fact)
  WN=$((WN + 1)); W="${BATTERY_DIR:-$TMP}/w.${WN}"; rm -rf "$W"; mkdir -p "$W"; export WORLD="$W"
  : > "$W/calls.log"; : > "$W/writes.log"; : > "$W/order.log"; : > "$W/queries.log"; : > "$W/argv.log"
  echo "$SID" > "$W/server_id"; echo ok > "$W/servers_mode"; echo 2026-10-06T19:32:09+00:00 > "$W/server_created"
  echo 1 > "$W/state_web1"; echo "$SID" > "$W/state_web2"; echo absent > "$W/never"
  SINCE="$SINCE_DEFAULT"; FX_BARE=""
  fx_ready 45000 "$CURD" > "$W/bs.ready"
  fx_probe ok 28000 "$CURD" > "$W/bs.probe"
  { fx_boot "$CUR" 45000 20 3000; } > "$W/bs.boots"
  local f
  for f in "$@"; do
    case "$f" in
      server_id=*) echo "${f#*=}" > "$W/server_id" ;;
      created=*) echo "${f#*=}" > "$W/server_created" ;;
      servers=*) echo "${f#*=}" > "$W/servers_mode" ;;
      state_web1=*) echo "${f#*=}" > "$W/state_web1" ;;
      state_web2=*) echo "${f#*=}" > "$W/state_web2" ;;
      state_fail) touch "$W/state_fail" ;;
      never=*) echo "${f#*=}" > "$W/never" ;;
      never_unset) touch "$W/never_unset" ;;
      no_token) touch "$W/no_token" ;;
      post_code=*) echo "${f#*=}" > "$W/post_code" ;;
      post_noid) touch "$W/post_noid" ;;
      action_status=*) echo "${f#*=}" > "$W/action_status" ;;
      action_get_code=*) echo "${f#*=}" > "$W/action_get_code" ;;
      approvals_fail) touch "$W/approvals_fail" ;;
      since=*) SINCE="${f#*=}" ;;
      bare) FX_BARE=1 ;;
      clock) echo 1800000000 > "$W/clock" ;;
    esac
  done
  [[ -f "$W/approvals_fail" ]] || echo '[{"user":{"login":"approver-one"},"state":"approved"}]' > "$W/approvals"
}
# set_rows <ready|probe|boots> <content...>   (replaces one fixture file)
set_rows() { local k="$1"; shift; printf '%s\n' "$@" > "$W/bs.$k"; }
set_boots() { : > "$W/bs.boots"; local b; for b in "$@"; do fx_boot ${b} >> "$W/bs.boots"; done; }   # each arg: "id first newest n"
bsfail() { echo "${2:-99}" > "$W/bsfail.$1"; echo "${3:-503}" > "$W/bsfail_mode.$1"; }
now_in_world() { if [[ -f "$W/clock" ]]; then cat "$W/clock"; else "$REAL_DATE" -u +%s; fi; }
anchor_now() { echo $(( $(now_in_world) - SINCE )); }

# ---- row bookkeeping ---------------------------------------------------------------------------------------------------
deny_hits() { grep -iEo "$DENY_RE" || true; }
check() { # <name> <condition-result 0|1>
  echo x >> "$BATTERY_DIR/checks"
  if [[ "$2" -ne 0 ]]; then printf 'FAILED %s\n' "$1"; fi
}
cond() { if "$@"; then echo 0; else echo 1; fi; }
RBASH=(bash); EBASH=(bash); RENV=(); ENVE=()

# universal checks over one finished run: footer on every path, no claim word, no secret, no unexpected call
common_checks() { # <name> <stdout> <script-kind: r|e>
  local name="$1" o="$2" kind="$3" err hits
  err="$(grep -v -e '^::add-mask::' -e '^+' "$W/stderr" 2>/dev/null || true)"
  [[ "$o" == *"$FOOTER"* ]] || printf 'FAILED %s (the fixed footer is missing from stdout)\n' "$name"
  hits="$(printf '%s\n%s\n' "$o" "$err" | deny_hits | head -3 | tr '\n' ' ')"
  [[ -z "$hits" ]] || printf 'FAILED %s (a denylisted claim word was printed: %s)\n' "$name" "$hits"
  if [[ -s "$W/unexpected.log" ]]; then printf 'FAILED %s (unexpected call: %s)\n' "$name" "$(head -c 160 "$W/unexpected.log")"; fi
  if [[ "$o" == *"$TOK"* || "$(cat "$W/argv.log" 2>/dev/null)" == *"$TOK"* ]]; then printf 'FAILED %s (the token reached stdout or an argv)\n' "$name"; fi
  if [[ "$o$err" == *fixture-pass* || "$o$err" == *fixture-user* ]]; then printf 'FAILED %s (a Better Stack credential was printed)\n' "$name"; fi
  if [[ -f "$W/summary" ]]; then
    hits="$(deny_hits < "$W/summary" | head -3 | tr '\n' ' ')"
    [[ -z "$hits" ]] || printf 'FAILED %s (a denylisted claim word reached the step summary: %s)\n' "$name" "$hits"
  fi
}

# ---- reboot runs -------------------------------------------------------------------------------------------------------
runr() { # <name> <want-rc> <want-substring|-> <args...>
  local name="$1" want="$2" sub="$3"; shift 3
  local o rc=0 e
  echo x >> "$BATTERY_DIR/runs"; echo r >> "$BATTERY_DIR/rruns"
  local -a envv=(PATH="$TMP/bin:/usr/bin:/bin" HOME="$W" WORLD="$W" INFRA_DIR="$W" GITHUB_OUTPUT="$W/gh_out" GITHUB_STEP_SUMMARY="$W/summary"
                 WEB_HOST_REBOOT_ACTION_POLL_S=0 REPO=o/r GH_TOKEN=x)
  [[ -f "$W/no_token" ]] || envv+=(HCLOUD_TOKEN="$TOK")
  [[ -f "$W/never_unset" ]] || envv+=(NEVER_POOLED="$(cat "$W/never")")
  o="$(env -i "${envv[@]}" ${RENV[@]+"${RENV[@]}"} "${RBASH[@]}" "$R_SCRIPT" "$@" 2>"$W/stderr")" || rc=$?
  LASTOUT="$o"; e="$(cat "$W/stderr" 2>/dev/null)"
  common_checks "$name" "$o" r
  if [[ "$rc" -ne "$want" ]]; then printf 'FAILED %s (rc=%s want=%s) %s\n' "$name" "$rc" "$want" "${o:0:240}${e:0:160}"; return; fi
  if [[ "$sub" != "-" && "$o$e" != *"$sub"* ]]; then printf 'FAILED %s (output lacks %q) %s\n' "$name" "$sub" "${o:0:240}"; fi
}
writes() { tr '\n' ' ' < "$W/writes.log"; }
nwrites() { grep -c . "$W/writes.log" 2>/dev/null || true; }
want_nothing_written() { # <name>
  check "$1: the write log is empty" "$([[ "$(nwrites)" == 0 ]]; echo $?)"
  check "$1: no anchor was handed out" "$([[ ! -f "$W/gh_out" ]] || [[ "$(grep -c '^anchor_epoch=' "$W/gh_out")" == 0 ]]; echo $?)"
}
want_no_api_call() { check "$1: no Hetzner call was made" "$([[ ! -s "$W/calls.log" ]]; echo $?)"; }

battery_reboot() {
  R_SCRIPT="$1"; BATTERY_DIR="$(mktemp -d "$TMP/br.XXXXXX")"; : > "$BATTERY_DIR/runs"; : > "$BATTERY_DIR/checks"; : > "$BATTERY_DIR/rruns"
  local CONF="REBOOT-web-2-${SID}" h c
  # ---- the happy path and its must-pass neighbours
  world; runr "reboot: happy path" 0 "reboot request accepted by Hetzner (action 10 success)" reboot web-2 "$CONF"
  check "reboot: exactly one write, to the right id" "$([[ "$(writes)" == "REBOOT /servers/${SID}/actions/reboot " ]]; echo $?)"
  check "reboot: exactly one POST on the wire" "$([[ "$(grep -c '^POST ' "$W/calls.log")" == 1 ]]; echo $?)"
  check "reboot: the anchor was already in GITHUB_OUTPUT when the POST arrived" "$([[ "$(cat "$W/anchor_at_post" 2>/dev/null)" == yes ]]; echo $?)"
  check "reboot: the anchor is a current epoch" "$(a="$(sed -n 's/^anchor_epoch=//p' "$W/gh_out")"; [[ "$a" =~ ^[0-9]{10}$ ]] && (( a > $(now_in_world) - 120 && a <= $(now_in_world) + 5 )); echo $?)"
  check "reboot: the server id is an output" "$([[ "$(sed -n 's/^server_id=//p' "$W/gh_out")" == "$SID" ]]; echo $?)"
  check "reboot: every output is one key=value line" "$([[ "$(grep -vc '^[a-z_]*=[^ ]*$' "$W/gh_out")" == 0 ]]; echo $?)"
  check "reboot: the success sentence says the request was sent and nothing more" "$([[ "$LASTOUT" == *"it does not show that the host restarted or came back"* ]]; echo $?)"
  check "reboot: the output names the server id, the name and the anchor" "$([[ "$LASTOUT" == *"$SID"* && "$LASTOUT" == *soleur-web-2* && "$LASTOUT" == *anchor_epoch=* ]]; echo $?)"
  check "reboot: the token travelled on stdin" "$([[ "$(cat "$W/stdin.last")" == *"$TOK"* ]]; echo $?)"
  check "reboot: stderr carries only the mask line and (when traced) nothing else" "$([[ "$(grep -vc '^::add-mask::' "$W/stderr")" == 0 ]]; echo $?)"
  world "created=2026-10-06T21:32:09+02:00"; runr "reboot: a non-UTC creation time does not matter" 0 "accepted by Hetzner" reboot web-2 "$CONF"
  world "server_id=12345678" "state_web2=12345678"; runr "reboot: an 8-digit id shaped like no live one is accepted when all three agree" 0 "accepted by Hetzner" reboot web-2 REBOOT-web-2-12345678
  # ---- refusal 2: the allow-list
  for h in web-1 web-3 "" "web-2 " WEB-2 "web-2;x" $'web-2\nweb-1'; do
    world; runr "reboot: host '${h//$'\n'/\\n}' is not on the allow-list" 1 "is not on the reboot allow-list" reboot "$h" "REBOOT-${h}-${SID}"
    want_no_api_call "reboot allow-list '${h//$'\n'/\\n}'"; want_nothing_written "reboot allow-list '${h//$'\n'/\\n}'"
  done
  world; runr "reboot: a missing host argument refuses" 1 "is not on the reboot allow-list" reboot
  # ---- refusal 3: the typed confirm
  for c in "REBOOT-web-2-" "REBOOT-web-2-12x" "reboot-web-2-1" "REBOOT-web-1-123931471" "REBOOT-web-2-0123" "REBOOT-web-2-1234567890123" "REBOOT-web-2-1 " "" "REBOOT-web-2-$SID;id"; do
    world; runr "reboot: confirm '${c}' is refused" 1 "confirm must be" reboot web-2 "$c"
    want_no_api_call "reboot confirm '${c}'"; want_nothing_written "reboot confirm '${c}'"
  done
  # ---- refusal 4: the never-pooled evidence
  for c in "" present unreadable "absent " ABSENT; do
    world "never=$c"; runr "reboot: NEVER_POOLED='${c}' refuses before any API call" 1 "no never-pooled evidence" reboot web-2 "$CONF"
    want_no_api_call "reboot never-pooled '${c}'"; want_nothing_written "reboot never-pooled '${c}'"
  done
  world never_unset; runr "reboot: an unset NEVER_POOLED refuses" 1 "no never-pooled evidence" reboot web-2 "$CONF"; want_no_api_call "reboot never-pooled unset"
  # ---- refusal 5: exactly one server by name
  for c in zero two http500 wrongname; do
    world "servers=$c"; runr "reboot: a server lookup of '${c}' refuses" 1 "could not resolve exactly one server" reboot web-2 "$CONF"; want_nothing_written "reboot lookup ${c}"
  done
  # ---- refusal 6: not web-1, numeric
  world "server_id=123931471" "state_web2=123931471"; runr "reboot: the web-1 id is refused even when typed, and even when the state agrees" 1 "has web-1's id" reboot web-2 REBOOT-web-2-123931471
  want_nothing_written "reboot web-1 id"
  world "server_id=12x"; runr "reboot: a non-numeric resolved id is refused" 1 "is not numeric" reboot web-2 "$CONF"; want_nothing_written "reboot non-numeric id"
  # ---- refusal 7: the typed id equals the live id; the message hands the dispatcher the corrected value
  world; runr "reboot: an id off by one digit is refused, and the live id and corrected confirm are printed" 1 "differs from the id typed in confirm" reboot web-2 REBOOT-web-2-169095541
  check "reboot: the refusal prints the corrected confirm" "$([[ "$LASTOUT" == *"REBOOT-web-2-${SID}"* ]]; echo $?)"; want_nothing_written "reboot typed id"
  # ---- refusal 8: the Terraform state agrees, and is the right object
  world "state_web2=169095541"; runr "reboot: a different id in the state is refused (nothing is written before the comparison)" 1 "differs from the id in the Terraform state" reboot web-2 "$CONF"; want_nothing_written "reboot state id differs"
  world "state_web2=none"; runr "reboot: no web-2 id in the state is refused" 1 "differs from the id in the Terraform state" reboot web-2 "$CONF"; want_nothing_written "reboot state id absent"
  world "state_web1=0"; runr "reboot: a state without web-1 is the wrong object and is refused" 1 "wrong state object" reboot web-2 "$CONF"; want_nothing_written "reboot wrong state object"
  world state_fail; runr "reboot: a failing state pull is refused" 1 "could not read the Terraform state" reboot web-2 "$CONF"; want_nothing_written "reboot state pull fails"
  world "state_web2=::error::pwn"; runr "reboot: a hostile state id is refused and never printed" 1 "differs from the id in the Terraform state" reboot web-2 "$CONF"
  check "reboot: the hostile state id is not in the output" "$([[ "$LASTOUT" != *pwn* ]]; echo $?)"; want_nothing_written "reboot hostile state id"
  # ---- refusal 9: the POST
  world post_code=403; runr "reboot: a 403 names the read-only token" 1 "reboot -> 403" reboot web-2 "$CONF"
  check "reboot: a 403 adds the read-only token hint" "$([[ "$LASTOUT" == *"read-only Hetzner token"* ]]; echo $?)"
  check "reboot: the anchor survives a refused POST" "$([[ "$(grep -c '^anchor_epoch=' "$W/gh_out")" == 1 ]]; echo $?)"
  world post_code=422; runr "reboot: a 422 fails with Hetzner's code" 1 "reboot -> 422 (error.code=locked)" reboot web-2 "$CONF"
  world post_code=423; runr "reboot: a 423 fails" 1 "reboot -> 423" reboot web-2 "$CONF"
  world post_noid; runr "reboot: a 201 without an action id fails" 1 "no numeric action id" reboot web-2 "$CONF"
  check "reboot: the anchor survives a POST that returned no action id" "$([[ "$(grep -c '^anchor_epoch=' "$W/gh_out")" == 1 ]]; echo $?)"
  # ---- refusal 10: the action outcome
  world action_status=error; runr "reboot: an action that ends in error is unconfirmed, not success" 1 "reboot request outcome unconfirmed" reboot web-2 "$CONF"
  check "reboot: the unconfirmed message says not to re-dispatch" "$([[ "$LASTOUT" == *"DO NOT re-dispatch"* ]]; echo $?)"
  check "reboot: the unconfirmed message hands over the grade command" "$([[ "$LASTOUT" == *"web-host-reboot-evidence.sh grade --anchor"* ]]; echo $?)"
  check "reboot: the anchor is already out after an unconfirmed action" "$([[ "$(grep -c '^anchor_epoch=' "$W/gh_out")" == 1 ]]; echo $?)"
  check "reboot: an unconfirmed outcome never claims acceptance" "$([[ "$LASTOUT" != *"accepted by Hetzner"* ]]; echo $?)"
  world action_status=running; runr "reboot: an action still running after 24 polls is unconfirmed" 1 "reboot request outcome unconfirmed" reboot web-2 "$CONF"
  check "reboot: exactly 24 polls were made" "$([[ "$(grep -c '^GET /actions/10' "$W/calls.log")" == 24 ]]; echo $?)"
  world action_get_code=500; runr "reboot: an action poll that answers 500 is unconfirmed" 1 "reboot request outcome unconfirmed" reboot web-2 "$CONF"
  # ---- refusal 1: xtrace and the token
  world; RBASH=(bash -x); runr "reboot: a traced run is refused" 78 "refusing to trace" reboot web-2 "$CONF"; RBASH=(bash)
  want_no_api_call "reboot xtrace"
  world no_token; runr "reboot: a missing token refuses" 1 "exported no HCLOUD_TOKEN" reboot web-2 "$CONF"; want_no_api_call "reboot no token"
  # ---- usage
  world; runr "reboot: no verb is a usage error" 2 "usage"
  world; runr "reboot: an unknown verb is a usage error" 2 "usage" frobnicate
  # ---- summary (no Hetzner call; claims only what the run measured)
  world; RENV=(JOB_STATUS=success HOST=web-2 SERVER_ID="$SID" ANCHOR_EPOCH=1800000000 REASON="soak step 1" SHA=abc123 RUN_URL=https://example.invalid/run/1 ACTOR=dispatcher-one RUN_ID=1 STARTED_AT=2026-10-07T08:00:00Z)
  runr "summary: a green job" 0 "approver-one" summary
  check "summary: a green job says the request was sent and nothing more" "$([[ "$(cat "$W/summary")" == *"does not show that the host restarted or came back"* ]]; echo $?)"
  check "summary: the footer is in the step summary" "$([[ "$(cat "$W/summary")" == *"$FOOTER"* ]]; echo $?)"
  check "summary: the anchor and server id are in the step summary" "$([[ "$(cat "$W/summary")" == *1800000000* && "$(cat "$W/summary")" == *"$SID"* ]]; echo $?)"
  check "summary: no Hetzner call is made" "$([[ ! -s "$W/calls.log" ]]; echo $?)"
  world; RENV=(JOB_STATUS=failure HOST=web-2 SERVER_ID="$SID" ANCHOR_EPOCH=1800000000 REASON=x RUN_ID=1)
  runr "summary: a failed job does not claim a sent request as accepted" 0 "did not complete" summary
  check "summary: a failed job with an anchor says do not re-dispatch" "$([[ "$(cat "$W/summary")" == *"do not re-dispatch"* || "$(cat "$W/summary")" == *"DO NOT re-dispatch"* ]]; echo $?)"
  check "summary: a failed job never says accepted" "$([[ "$(cat "$W/summary")" != *"accepted by Hetzner"* ]]; echo $?)"
  world; RENV=(JOB_STATUS=failure HOST=web-2 REASON=x)
  runr "summary: a refused run has no anchor and says nothing was sent" 0 "no anchor" summary
  world; RENV=(JOB_STATUS=success HOST=web-2 SERVER_ID="$SID" ANCHOR_EPOCH=1800000000 REASON=$'x\n::error::boom|y' RUN_ID=1 ACTOR=$'a\n::stop-commands::z')
  runr "summary: free text cannot start a line of its own or break the table" 0 "-" summary
  check "summary: no line of the step summary starts a workflow command" "$([[ "$(grep -c '^::' "$W/summary")" == 0 ]]; echo $?)"
  check "summary: no workflow command line on stdout either" "$([[ "$(printf '%s\n' "$LASTOUT" | grep -c '^::')" == 0 ]]; echo $?)"
  world approvals_fail; RENV=(JOB_STATUS=success HOST=web-2 SERVER_ID="$SID" ANCHOR_EPOCH=1800000000 REASON=x RUN_ID=1)
  runr "summary: an unanswering approvals API is reported, not hidden" 0 "unavailable" summary
  RENV=()
}

# ---- evidence runs -----------------------------------------------------------------------------------------------------
rune() { # <name> <want-rc> <want-substring|-> <args...>
  local name="$1" want="$2" sub="$3"; shift 3
  local o rc=0 e
  echo x >> "$BATTERY_DIR/runs"; echo e >> "$BATTERY_DIR/eruns"
  local -a envv=(PATH="$TMP/bin:/usr/bin:/bin" HOME="$W" WORLD="$W" GITHUB_OUTPUT="$W/gh_out" GITHUB_STEP_SUMMARY="$W/summary")
  [[ -f "$W/no_creds" ]] || envv+=(BETTERSTACK_QUERY_HOST=fixture-connect.betterstackdata.com BETTERSTACK_QUERY_USERNAME=fixture-user BETTERSTACK_QUERY_PASSWORD=fixture-pass)
  o="$(env -i "${envv[@]}" ${ENVE[@]+"${ENVE[@]}"} "${EBASH[@]}" "$E_SCRIPT" "$@" 2>"$W/stderr")" || rc=$?
  LASTOUT="$o"; e="$(cat "$W/stderr" 2>/dev/null)"
  common_checks "$name" "$o" e
  if [[ "$rc" -ne "$want" ]]; then printf 'FAILED %s (rc=%s want=%s) %s\n' "$name" "$rc" "$want" "${o:0:300}${e:0:160}"; return; fi
  if [[ "$sub" != "-" && "$o$e" != *"$sub"* ]]; then printf 'FAILED %s (output lacks %q) %s\n' "$name" "$sub" "${o:0:300}"; fi
}
grade_args() { printf 'grade --anchor %s --window-min 0' "$(anchor_now)"; }
# graded <name> <want-rc> <want-reason> [extra]   (a single read at the world's anchor)
graded() { local name="$1" want="$2" reason="$3"; rune "$name" "$want" "reason=${reason}" $(grade_args); }
no_verdict_misreads() { check "$1: the verdict line is unique" "$([[ "$(printf '%s\n' "$LASTOUT" | grep -c '^verdict: ')" == 1 ]]; echo $?)"; }

battery_evidence() {
  E_SCRIPT="$1"; BATTERY_DIR="$(mktemp -d "$TMP/be.XXXXXX")"; : > "$BATTERY_DIR/runs"; : > "$BATTERY_DIR/checks"; : > "$BATTERY_DIR/eruns"
  local i
  # ---- the verdict table, one fixture each (the old boot is CUR; the request is SINCE seconds old; the new boot is NEW)
  world; set_rows ready "$(fx_ready 100 "$NEWD" formatted)"; set_boots "$CUR 45000 20 3000"
  graded "evidence: a readiness row younger than the request means the instance was re-created" 2 instance_recreated_after_request; no_verdict_misreads "evidence: recreated"
  check "evidence: a re-created instance says so in the next line" "$([[ "$LASTOUT" == *"next:"*"re-created"* ]]; echo $?)"
  world; set_rows ready "$(fx_ready 45000 "$CURD")" "junk row that is not json at all"; graded "evidence: an unparseable readiness body is a read fault, never a verdict" 2 read_fault
  world; set_rows ready "$(fx_ready 100 "$NEWD" | sed 's/ready=1/ready=1 ready=1/')"; set_boots "$CUR 45000 20 3000"
  graded "evidence: a malformed readiness row younger than the request is not a re-creation" 4 request_not_acted_on
  world; graded "evidence: the old boot still shipping and no new boot: the request was not acted on (exit 4)" 4 request_not_acted_on; no_verdict_misreads "evidence: not acted on"
  check "evidence: not-acted-on says nothing is dark" "$([[ "$LASTOUT" == *"nothing is dark"* ]]; echo $?)"
  world; set_boots "$CUR 45000 900 3000"; graded "evidence: the old boot silent and no new boot (exit 4)" 4 host_silent_no_new_boot
  check "evidence: a silent host points at the dark-host path" "$([[ "$LASTOUT" == *"dark-host"* ]]; echo $?)"
  world; set_boots "$CUR 45000 700 3000" "$NEW 300 15 40"; set_rows probe ""; graded "evidence: a new boot and no probe row is the expected pending state (exit 2)" 2 new_boot_seen_probe_pending
  check "evidence: pending gives the daily probe window" "$([[ "$LASTOUT" == *"00:00 to 00:30 UTC"* ]]; echo $?)"
  check "evidence: pending gives the filled-in re-grade command" "$([[ "$LASTOUT" == *"web-host-reboot-evidence.sh grade --anchor $(anchor_now)"* || "$LASTOUT" == *"web-host-reboot-evidence.sh grade --anchor"* ]]; echo $?)"
  check "evidence: pending says not to re-dispatch to force a row" "$([[ "$LASTOUT" == *"do not re-dispatch"* ]]; echo $?)"
  world; set_boots "$CUR 45000 700 3000" "$NEW 300 15 40"; set_rows probe "$(fx_probe ok 28000 "$CURD")"
  graded "evidence: an OK probe row on the OLD boot is not evidence of this request" 2 new_boot_seen_probe_pending
  world; set_boots "$CUR 45000 700 3000" "$NEW 300 15 40"; set_rows probe "$(fx_probe ok 400 "$CURD")"
  graded "evidence: an OK probe row younger than the request but on the OLD boot is still not a PASS" 2 new_boot_seen_probe_pending
  world; set_boots "$CUR 45000 700 3000" "$NEW 300 15 40"; set_rows probe "$(fx_probe ok 100 "$NEWD")"
  rune "evidence: an OK probe row on the new boot is a PASS (row presence only)" 0 "PASS (row presence only)" $(grade_args)
  check "evidence: the PASS reason is the row-presence reason" "$([[ "$LASTOUT" == *"reason=probe_row_on_a_boot_that_began_after_the_request"* ]]; echo $?)"
  check "evidence: the PASS line names the joined boot id without dashes" "$([[ "$LASTOUT" == *"$NEW"* ]]; echo $?)"
  check "evidence: the PASS output says the follow-through is the grader" "$([[ "$LASTOUT" == *"web2-luks-live-6931.sh"* ]]; echo $?)"
  no_verdict_misreads "evidence: PASS"
  check "evidence: GITHUB_OUTPUT carries the verdict and reason" "$([[ "$(sed -n 's/^verdict=//p' "$W/gh_out")" == PASS && "$(sed -n 's/^reason=//p' "$W/gh_out")" == probe_row_on_a_boot_that_began_after_the_request ]]; echo $?)"
  check "evidence: every output is one key=value line" "$([[ "$(grep -vc '^[a-z_]*=[^ ]*$' "$W/gh_out")" == 0 ]]; echo $?)"
  check "evidence: the step summary carries the verdict and the footer" "$([[ "$(cat "$W/summary")" == *"verdict: PASS"* && "$(cat "$W/summary")" == *"$FOOTER"* ]]; echo $?)"
  world bare; set_boots "$CUR 45000 700 3000" "$NEW 300 15 40"; set_rows probe "$(fx_probe ok 100 "${NEWD^^}")"
  rune "evidence: bare-number ages and an uppercase probe boot id still join (the live shape)" 0 "PASS (row presence only)" $(grade_args)
  world; set_boots "$CUR 45000 700 3000" "$NEW 300 15 40"; set_rows probe "$(fx_probe fail 100)"
  graded "evidence: a FAIL row younger than the new boot's first row is a FAIL" 1 probe_fail_row_after_new_boot; no_verdict_misreads "evidence: FAIL"
  check "evidence: a FAIL row names the soak consequence" "$([[ "$LASTOUT" == *"spoil"* ]]; echo $?)"
  world; set_boots "$CUR 45000 700 3000" "$NEW 300 15 40"; set_rows probe "$(fx_probe fail 28000)"
  graded "evidence: a FAIL row older than the new boot's first row is not a FAIL" 2 new_boot_seen_probe_pending
  world; set_boots "$CUR 45000 700 3000" "$NEW 300 15 40"; set_rows probe "$(fx_probe fail 250)"
  graded "evidence: a FAIL row inside the 120 s margin is resolved toward NOT YET" 2 new_boot_seen_probe_pending
  world; set_boots "$CUR 45000 700 3000" "$NEW 300 15 40"; set_rows probe "$(fx_probe malformed 100)"
  graded "evidence: a malformed probe row after the new boot is a FAIL" 1 probe_fail_row_after_new_boot
  world; set_boots "$CUR 45000 700 3000" "$NEW 300 15 40"; set_rows probe "$(fx_probe ok abc "$NEWD")"
  graded "evidence: a probe row with an unparseable age is a read fault, not a verdict" 2 read_fault
  world; set_boots "$CUR 45000 700 3000" "$NEW 300 15 40"; set_rows probe "$(fx_probe ok 100 "$NEWD" | sed 's/soleur-web-2/other-host/')"
  graded "evidence: a probe row of another host is ignored" 2 new_boot_seen_probe_pending
  world since=3000; set_boots "$CUR 45000 3100 3000" "$NEW 2000 900 40"
  graded "evidence: a new boot whose newest row is over 10 minutes old has gone silent (exit 4)" 4 new_boot_seen_then_silent
  check "evidence: a silent new boot points at the dark-host path" "$([[ "$LASTOUT" == *"dark-host"* ]]; echo $?)"
  world since=3000; set_boots "$CUR 45000 3100 3000" "$NEW 2000 900 40"; set_rows probe "$(fx_probe ok 100 "$NEWD")"
  graded "evidence: a PASS is not hidden by a silent boot check (the probe row wins)" 0 probe_row_on_a_boot_that_began_after_the_request
  # hostile and malformed boot ids: dropped, counted, never printed
  world; set_boots "$CUR 45000 700 3000" "$NEW 300 15 40" "::error::pwn 200 10 5" "${NEW^^} 200 10 5" "abcd 200 10 5" "${NEW}00 200 10 5"
  graded "evidence: hostile or malformed journald boot ids are dropped" 2 new_boot_seen_probe_pending
  check "evidence: no hostile id was printed" "$([[ "$LASTOUT" != *pwn* && "$LASTOUT" != *"${NEW^^}"* && "$LASTOUT" != *abcd* && "$LASTOUT" != *"${NEW}00"* ]]; echo $?)"
  check "evidence: the dropped ids are counted" "$([[ "$LASTOUT" == *"dropped_ids=4"* ]]; echo $?)"
  world; set_boots "::error::pwn 200 10 5" "${NEW^^} 200 10 5"; graded "evidence: a boot list with no readable id is a read fault" 2 read_fault
  world; set_rows boots ""; graded "evidence: an empty boot list is a read fault, never a verdict" 2 read_fault
  world; set_rows boots "not json"; graded "evidence: an unparseable boot body is a read fault" 2 read_fault
  # read faults per read, with the old boot in a state that would otherwise be a verdict
  for i in ready probe boots; do
    world; set_boots "$CUR 45000 700 3000" "$NEW 300 15 40"; set_rows probe "$(fx_probe ok 100 "$NEWD")"; bsfail "$i"
    graded "evidence: a 503 on the ${i} read is NOT YET read_fault, never a PASS or FAIL" 2 read_fault
    check "evidence: a ${i} read fault says nothing was measured" "$([[ "$LASTOUT" == *"Nothing was measured"* ]]; echo $?)"
  done
  world; set_boots "$CUR 45000 700 3000" "$NEW 300 15 40"; bsfail boots 99 timeout; graded "evidence: a timeout on the boot read is a read fault" 2 read_fault
  world; set_boots "$CUR 45000 700 3000" "$NEW 300 15 40"; set_rows probe "$(fx_probe fail 100)"; bsfail probe
  graded "evidence: a failed probe read never yields FAIL" 2 read_fault
  # credentials, loading, tracing, arguments
  world; touch "$W/no_creds"; rune "evidence: absent credentials are exit 3 and nothing is queried" 3 "CANNOT ESTABLISH" $(grade_args)
  check "evidence: no query was issued without credentials" "$([[ ! -s "$W/queries.log" ]]; echo $?)"
  for i in BETTERSTACK_QUERY_HOST BETTERSTACK_QUERY_USERNAME BETTERSTACK_QUERY_PASSWORD; do
    world; ENVE=("$i="); rune "evidence: an empty ${i} is exit 3" 3 "$i" $(grade_args); ENVE=()
  done
  world; EBASH=(bash -x); rune "evidence: a traced run is refused" 78 "refusing to trace" $(grade_args); EBASH=(bash)
  world; rune "evidence: grade without --anchor is exit 3" 3 "anchor" grade --window-min 0
  world; rune "evidence: a non-numeric anchor is exit 3" 3 "anchor" grade --anchor 12x --window-min 0
  world; rune "evidence: a future anchor is exit 3" 3 "anchor" grade --anchor $(( $(now_in_world) + 100000 )) --window-min 0
  world; rune "evidence: a non-numeric window is exit 3" 3 "window" grade --anchor "$(anchor_now)" --window-min x
  world; rune "evidence: an unknown flag is a usage error" 64 "usage" grade --anchor "$(anchor_now)" --window-min 0 --frob 1
  world; rune "evidence: an unknown verb is a usage error" 64 "usage" frobnicate
  world; rune "evidence: no verb is a usage error" 64 "usage"
  # the helper must load and must define every function the reader calls
  local sb="$BATTERY_DIR/sb"; mkdir -p "$sb/scripts"; cp -r "$ROOT/scripts/lib" "$ROOT/scripts/betterstack-query.sh" "$sb/scripts/"; cp "$E_SCRIPT" "$sb/scripts/web-host-reboot-evidence.sh"
  sed -i 's/^w2l_fetch_ready() .*/: removed/' "$sb/scripts/lib/web2-luks-rows.sh"
  world; E_SAVE="$E_SCRIPT"; E_SCRIPT="$sb/scripts/web-host-reboot-evidence.sh"
  rune "evidence: a helper that lacks a function the reader calls is exit 3" 3 "CANNOT ESTABLISH" $(grade_args); E_SCRIPT="$E_SAVE"
  # BASH_SOURCE-relative resolution is real: a sandbox helper with another host name is what the sandbox script queries
  local sb2="$BATTERY_DIR/sb2"; mkdir -p "$sb2/scripts"; cp -r "$ROOT/scripts/lib" "$ROOT/scripts/betterstack-query.sh" "$sb2/scripts/"; cp "$E_SCRIPT" "$sb2/scripts/web-host-reboot-evidence.sh"
  sed -i 's/^W2L_HOST_NAME="soleur-web-2"/W2L_HOST_NAME="soleur-web-9-sandbox"/' "$sb2/scripts/lib/web2-luks-rows.sh"
  world; E_SAVE="$E_SCRIPT"; E_SCRIPT="$sb2/scripts/web-host-reboot-evidence.sh"; rune "evidence: (control) a sandbox copy resolves its OWN helper" 4 "-" $(grade_args)
  check "evidence: (control) the sandbox helper's host name reached the query" "$([[ "$(grep -c 'soleur-web-9-sandbox' "$W/sql.log")" -ge 1 ]]; echo $?)"; E_SCRIPT="$E_SAVE"
  # ---- snapshot
  world; rune "evidence: snapshot prints the pre-request context" 0 "pre-request context:" snapshot
  check "evidence: snapshot names the readiness row, the probe row and the newest boot" "$([[ "$LASTOUT" == *"readiness row:"* && "$LASTOUT" == *"probe row:"* && "$LASTOUT" == *"newest boot:"* ]]; echo $?)"
  check "evidence: snapshot prints ids and ages (the old boot)" "$([[ "$LASTOUT" == *"$CUR"* ]]; echo $?)"
  world; bsfail boots; rune "evidence: snapshot with a read fault prints unavailable and still exits 0" 0 "unavailable" snapshot
  world; touch "$W/no_creds"; rune "evidence: snapshot without credentials is exit 3" 3 "CANNOT ESTABLISH" snapshot
  # ---- the deadline is a wall clock, however many iterations that takes; the clock is read before the queries
  world clock; local a; a="$(anchor_now)"; : > "$W/order.log"
  rune "evidence: a 2 minute window with a 30 s poll ends at the deadline with the exit-4 reason" 4 "reason=request_not_acted_on" grade --anchor "$a" --window-min 2 --poll-s 30
  check "evidence: the 30 s poll made 5 iterations" "$([[ "$(printf '%s\n' "$LASTOUT" | grep -c '^iteration ')" == 5 ]]; echo $?)"
  check "evidence: the clock is read before each iteration's queries (no sleep leads straight into a query)" "$([[ "$(tr '\n' ' ' < "$W/order.log")" != *"S Q"* && "$(tr '\n' ' ' < "$W/order.log")" == *"S D Q Q Q"* ]]; echo $?)"
  check "evidence: 3 queries per iteration" "$([[ "$(grep -c . "$W/queries.log")" == 15 ]]; echo $?)"
  world clock; a="$(anchor_now)"
  rune "evidence: the same window with a 60 s poll takes fewer iterations (wall clock, not a count)" 4 "reason=request_not_acted_on" grade --anchor "$a" --window-min 2 --poll-s 60
  check "evidence: the 60 s poll made 3 iterations" "$([[ "$(printf '%s\n' "$LASTOUT" | grep -c '^iteration ')" == 3 ]]; echo $?)"
  world clock; a="$(anchor_now)"; set_boots "$CUR 45000 700 3000" "$NEW 300 15 40"
  rune "evidence: a pending verdict polls to the deadline and ends NOT YET (exit 2)" 2 "reason=new_boot_seen_probe_pending" grade --anchor "$a" --window-min 3 --poll-s 60
  check "evidence: pending polled 4 times in a 3 minute window" "$([[ "$(printf '%s\n' "$LASTOUT" | grep -c '^iteration ')" == 4 ]]; echo $?)"
  world clock; a="$(anchor_now)"; set_boots "$CUR 45000 700 3000" "$NEW 300 15 40"; set_rows probe "$(fx_probe ok 100 "$NEWD")"
  rune "evidence: a PASS ends the poll at once" 0 "PASS (row presence only)" grade --anchor "$a" --window-min 30 --poll-s 60
  check "evidence: the PASS took one iteration" "$([[ "$(printf '%s\n' "$LASTOUT" | grep -c '^iteration ')" == 1 ]]; echo $?)"
  world clock; a="$(anchor_now)"; set_boots "$CUR 45000 700 3000" "$NEW 300 15 40"; set_rows probe "$(fx_probe ok 100 "$NEWD")"; bsfail boots 1
  rune "evidence: a read fault in the first iteration is retried and a later PASS stands" 0 "PASS (row presence only)" grade --anchor "$a" --window-min 30 --poll-s 60
  check "evidence: the retry took two iterations" "$([[ "$(printf '%s\n' "$LASTOUT" | grep -c '^iteration ')" == 2 ]]; echo $?)"
  world clock; a="$(anchor_now)"; set_boots "$CUR 45000 700 3000" "$NEW 300 15 40"; set_rows probe "$(fx_probe fail 100)"
  rune "evidence: a FAIL ends the poll at once" 1 "reason=probe_fail_row_after_new_boot" grade --anchor "$a" --window-min 30 --poll-s 60
  world clock; a="$(anchor_now)"; bsfail ready 99
  rune "evidence: a read fault that never clears ends NOT YET read_fault at the deadline (exit 2)" 2 "reason=read_fault" grade --anchor "$a" --window-min 2 --poll-s 60
}

# ======================================================================================================================
# The real subjects
# ======================================================================================================================
SUM_BEFORE="$(cd "$ROOT" && sha256sum scripts/web-host-reboot.sh scripts/web-host-reboot-evidence.sh scripts/lib/web2-luks-rows.sh scripts/betterstack-query.sh scripts/web2-rebirth.sh 2>/dev/null | sort)"
fails=0; STATIC=0
srow() { # <name> <0|1>   a static row
  STATIC=$((STATIC + 1)); if [[ "$2" -ne 0 ]]; then printf 'FAILED %s\n' "$1"; fails=$((fails + 1)); fi
}
declare -a REAL_OUT=()
battery_reboot "$RSCRIPT" > "$TMP/real_r.out" 2>&1; R_BDIR="$BATTERY_DIR"
battery_evidence "$ESCRIPT" > "$TMP/real_e.out" 2>&1; E_BDIR="$BATTERY_DIR"
cat "$TMP/real_r.out" "$TMP/real_e.out"
red_r="$(grep -c '^FAILED' "$TMP/real_r.out")"; red_e="$(grep -c '^FAILED' "$TMP/real_e.out")"
ran_r="$(( $(grep -c . "$R_BDIR/runs") + $(grep -c . "$R_BDIR/checks") ))"; ran_e="$(( $(grep -c . "$E_BDIR/runs") + $(grep -c . "$E_BDIR/checks") ))"
nrefusal_runs="$(grep -c . "$R_BDIR/rruns")"
printf 'real scripts: reboot %s rows (%s red), evidence %s rows (%s red)\n' "$ran_r" "$red_r" "$ran_e" "$red_e"
fails=$((fails + red_r + red_e))

# ---- static rows: wording, census, parity, tombstone, syntax ----------------------------------------------------------
noncomment() { grep -v '^[[:space:]]*#' "$1" 2>/dev/null | python3 -c 'import sys; f=sys.argv[1]; s=sys.stdin.read(); print(s.replace(f, ""))' "$FOOTER"; }
for f in "$RSCRIPT" "$ESCRIPT"; do
  b="$(basename "$f")"
  srow "static: ${b} exists and parses (bash -n)" "$([[ -f "$f" ]] && bash -n "$f" 2>/dev/null; echo $?)"
  hits="$(noncomment "$f" | deny_hits | head -3 | tr '\n' ' ')"
  srow "static: ${b} carries no denylisted claim word outside comments and the footer constant (${hits})" "$([[ -f "$f" && -z "$hits" ]]; echo $?)"
  srow "static: ${b} carries the footer constant verbatim" "$([[ -f "$f" && "$(grep -cF -- "$FOOTER" "$f")" -ge 1 ]]; echo $?)"
  srow "static: ${b} refuses xtrace" "$([[ -f "$f" && "$(grep -c 'refusing to trace' "$f")" -ge 1 ]]; echo $?)"
  srow "static: ${b} has no shellcheck finding" "$(if command -v shellcheck >/dev/null && [[ -f "$f" ]]; then shellcheck -x "$f" >/dev/null 2>&1; echo $?; elif [[ -f "$f" ]]; then echo 0; else echo 1; fi)"
  srow "static: ${b} has no ssh, doppler write, or token mint verb" "$([[ -f "$f" && "$(noncomment "$f" | grep -ciE '(^|[^a-z])ssh |scp |doppler (secrets|run)|api\.doppler|tokens? (create|mint)')" == 0 ]]; echo $?)"
done
# the denylist scan is itself live: a planted token is caught, and a must-pass wording is not
srow "static: (positive control) the scan catches a planted claim word" "$([[ -n "$(printf 'the volume is Encrypted\n' | deny_hits)" ]]; echo $?)"
srow "static: (positive control) the scan catches a planted mapper path" "$([[ -n "$(printf 'x /dev/mapper/workspaces y\n' | deny_hits)" ]]; echo $?)"
srow "static: (must-pass) PASS (row presence only) and the plain word unconfirmed are not hits" "$([[ -z "$(printf 'PASS (row presence only)\nreboot request outcome unconfirmed\n' | deny_hits)" ]]; echo $?)"
srow "static: (must-pass) the footer wording is not a hit when exempted" "$([[ -z "$(printf '%s\n' "$FOOTER" | python3 -c 'import sys; print(sys.stdin.read().replace(sys.argv[1], ""))' "$FOOTER" | deny_hits)" ]]; echo $?)"
srow "static: the denylist pattern compiles" "$(printf 'x\n' | grep -iEc "$DENY_RE" >/dev/null 2>&1; [[ $? -le 1 ]]; echo $?)"
# G3 census (Guard 3): the writer never names the rows helper or the marker; the reader is on the allow-list and carries no write verb
CENSUS_KEY='workspaces_luks_cutover["'"'"'_]*at\b|w2l_marker_name|web2-luks-rows'
CENSUS_VERB='-X[[:space:]]*(POST|PUT|PATCH|DELETE)\b|--request[=[:space:]][[:space:]]*(POST|PUT|PATCH|DELETE)\b|requests\.(post|put|patch|delete)\b|doppler[^#]*secrets[^#]*\b(set|delete|upload)\b|api\.doppler\.com|\bcurl\b[^#]*[[:space:]](-d|--data[a-z-]*|--json|-T|--upload-file)\b'
srow "static: the census KEY pattern compiles" "$(printf 'x\n' | grep -iEc -e "$CENSUS_KEY" >/dev/null 2>&1; [[ $? -le 1 ]]; echo $?)"
srow "static: the census VERB pattern compiles" "$(printf 'x\n' | grep -iEc -e "$CENSUS_VERB" >/dev/null 2>&1; [[ $? -le 1 ]]; echo $?)"
srow "static: the census still holds the KEY and VERB shapes this suite mirrors" "$([[ "$(grep -c 'w2l_marker_name|web2-luks-rows' "$ROOT/apps/web-platform/infra/workspaces-luks-verify-workflow.test.sh")" -ge 1 && "$(grep -c 'requests\\.(post|put|patch|delete)' "$ROOT/apps/web-platform/infra/workspaces-luks-verify-workflow.test.sh")" -ge 1 ]]; echo $?)"
srow "static: the writer script never names the rows helper or the marker (outside comments)" "$([[ -f "$RSCRIPT" && "$(grep -v '^[[:space:]]*#' "$RSCRIPT" | grep -ciE -e "$CENSUS_KEY")" == 0 ]]; echo $?)"
srow "static: the reader carries no write verb (outside comments)" "$([[ -f "$ESCRIPT" && "$(grep -v '^[[:space:]]*#' "$ESCRIPT" | grep -ciE -e "$CENSUS_VERB")" == 0 ]]; echo $?)"
srow "static: the reader carries no POST word outside comments (a harmless echo reds the census)" "$([[ -f "$ESCRIPT" && "$(grep -v '^[[:space:]]*#' "$ESCRIPT" | grep -cE '\bPOST\b')" == 0 ]]; echo $?)"
srow "static: (must-pass) a verb named only in a comment is not counted" "$([[ "$(printf '# curl -X POST x\nok\n' | grep -v '^[[:space:]]*#' | grep -ciE -e "$CENSUS_VERB")" == 0 ]]; echo $?)"
srow "static: (positive control) the verb scan catches a planted write" "$([[ "$(printf 'curl -X POST x\n' | grep -ciE -e "$CENSUS_VERB")" == 1 ]]; echo $?)"
srow "static: the reader is on the census allow-list (READERS)" "$([[ "$(grep -c '"scripts/web-host-reboot-evidence.sh"' "$ROOT/apps/web-platform/infra/workspaces-luks-verify-workflow.test.sh")" -ge 1 ]]; echo $?)"
srow "static: the writer is NOT on the census allow-list" "$([[ "$(grep -c '"scripts/web-host-reboot.sh"' "$ROOT/apps/web-platform/infra/workspaces-luks-verify-workflow.test.sh")" == 0 ]]; echo $?)"
# the one write site: the census over 'actions/reboot' finds exactly the recorded set (tests excepted)
reboot_set="$(cd "$ROOT" && git ls-files --cached --others --exclude-standard -- scripts .github apps 2>/dev/null | grep -E '\.(sh|yml|py)$' | grep -v '\.test\.' | xargs -r grep -l 'actions/reboot' 2>/dev/null | sort | tr '\n' ' ')"
srow "static: the 'actions/reboot' census finds exactly the recorded set (${reboot_set})" "$([[ "$reboot_set" == "scripts/web-host-reboot.sh scripts/web2-rebirth.sh " ]]; echo $?)"
srow "static: the writer's POST site is unique in the script (one occurrence of the reboot path)" "$([[ -f "$RSCRIPT" && "$(grep -c 'actions/reboot' "$RSCRIPT")" == 1 ]]; echo $?)"
# the copied helper bodies stay equal to the rebirth script's while both exist
py_fn='
import re, sys
src = open(sys.argv[1]).read().split("\n")
name = sys.argv[2]
out = []
for i, l in enumerate(src):
    if re.match(r"^" + re.escape(name) + r"\(\) ", l):
        out.append(l)
        if not re.search(r"\}\s*(#.*)?$", l) or l.rstrip().endswith("{"):
            for m in src[i + 1:]:
                out.append(m)
                if m == "}":
                    break
        break
print(re.sub(r"\s+", " ", " ".join(out)).strip())
'
if [[ -f "$ROOT/scripts/web2-rebirth.sh" ]]; then
  for fn in hapi errcode fail need_token out clean write_hint; do
    a="$(python3 -c "$py_fn" "$RSCRIPT" "$fn" 2>/dev/null)"; b="$(python3 -c "$py_fn" "$ROOT/scripts/web2-rebirth.sh" "$fn")"
    srow "static: parity: ${fn}() equals web2-rebirth.sh's copy" "$([[ -n "$a" && "$a" == "$b" ]]; echo $?)"
  done
fi
# tombstone: the subjects retire together with the two scripts they depend on
leftover="$(cd "$ROOT" && find scripts .github apps/web-platform/infra -maxdepth 2 -name 'web-host-reboot*' 2>/dev/null | sort | tr '\n' ' ')"
if [[ ! -f "$ROOT/scripts/web2-rebirth.sh" || ! -f "$ROOT/scripts/web2-rebirth-never-pooled.sh" ]]; then
  srow "static: TOMBSTONE the rebirth scripts are gone, so every web-host-reboot file must be gone too (${leftover})" "$([[ -z "$leftover" ]]; echo $?)"
else
  srow "static: the tombstone is armed (both rebirth scripts exist, so the subjects stay)" 0
fi
srow "static: the never-pooled reader the workflow depends on exists" "$([[ -f "$ROOT/scripts/web2-rebirth-never-pooled.sh" ]]; echo $?)"

# ---- floors: direct printf and exit, so a mutant of the guard itself is buildable ---------------------------------------
REFUSAL_FLOOR=35
if [[ "$nrefusal_runs" -lt "$REFUSAL_FLOOR" ]]; then printf 'FAILED floor: only %s reboot runs executed (floor %s)\n' "$nrefusal_runs" "$REFUSAL_FLOOR"; fails=$((fails + 1)); fi
ROWS_FLOOR=200
total_rows=$(( ran_r + ran_e + STATIC ))
if [[ "$total_rows" -lt "$ROWS_FLOOR" ]]; then printf 'FAILED floor: only %s rows ran (floor %s)\n' "$total_rows" "$ROWS_FLOOR"; fails=$((fails + 1)); fi
printf 'rows: reboot %s, evidence %s, static %s, total %s (floor %s)\n' "$ran_r" "$ran_e" "$STATIC" "$total_rows" "$ROWS_FLOOR"

[[ "${WHR_NO_MUTATE:-}" == 1 ]] && { [[ "$fails" -eq 0 ]] && exit 0; exit 1; }
# MUTATION_SECTION_BEGIN
# MUTATION_SECTION_END

# Static rows print their own FAILED lines; recount everything printed by this run.
[[ "$fails" -eq 0 ]] && { echo "web-host-reboot: all scenarios and mutations passed"; exit 0; }
echo "web-host-reboot: ${fails} FAILED"; exit 1
