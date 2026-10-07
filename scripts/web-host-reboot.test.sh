#!/usr/bin/env bash
# Tests for scripts/web-host-reboot.sh (the one reboot write) and scripts/web-host-reboot-evidence.sh (the read-only
# evidence reader), #9372. Both scripts run for real under the production shell against a fake world (a directory of small
# files that curl, terraform, gh, date and sleep shims read and write). A mutation battery then breaks each load-bearing
# check on a COPY of the subject and requires the battery to go red.
# shellcheck disable=SC2319,SC2034,SC2046,SC2086,SC2329
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${DIR}/.." && pwd)"
RSCRIPT="${ROOT}/scripts/web-host-reboot.sh"
ESCRIPT="${ROOT}/scripts/web-host-reboot-evidence.sh"
# A fixture directory is refused unless it is a non-empty absolute path (the canonical guard the repo's fixture lints key on).
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
assert_fixture_dir "$ROOT"
TMP="$(mktemp -d)"; assert_fixture_dir "$TMP"; trap 'rm -rf "$TMP"' EXIT
REAL_DATE="$(command -v date)"
TOK="tok-SENTINEL-9f3a7c"
SID=169095540
FOOTER='This run reports rows only. It makes no statement about the volume or its encryption; grading belongs to scripts/followthroughs/web2-luks-live-6931.sh.'
# The claim denylist (case-insensitive, whole-token: the neighbours of a hit must not be a letter or a digit, so the plain
# word "unconfirmed" in an outcome message is not a hit on "confirmed").
DENY_RE='(^|[^a-z0-9])(luks-backed|encrypted|reborn|reopen|proof|verified|confirmed|proves|crypto_luks|/dev/mapper|luks=1|escrow=ok)($|[^a-z0-9])'
CUR=479cd3f318da4a5d85068d3382a8723f; CURD=479cd3f3-18da-4a5d-8506-8d3382a8723f
NEW=a1b2c3d4e5f60718293a4b5c6d7e8f90; NEWD=a1b2c3d4-e5f6-0718-293a-4b5c6d7e8f90
OTH=0f0e0d0c0b0a09080706050403020100; OTHD=0f0e0d0c-0b0a-0908-0706-050403020100
NEW2=00112233445566778899aabbccddeeff; NEW2D=00112233-4455-6677-8899-aabbccddeeff
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
    if [[ "$pc" == 000 ]]; then exit 7   # a transport error: curl exits non-zero and the script's hapi reports 000
    elif [[ "$pc" =~ ^2[0-9][0-9]$ ]]; then   # a 2xx that is not 201 carries a good body too: only the status line can refuse it
      if [[ -f "$W/post_noid" ]]; then reply "$pc" '{"action":{"status":"running"}}'
      elif [[ -f "$W/post_html" ]]; then reply "$pc" '<html><body>502 bad gateway</body></html>'
      else reply "$pc" '{"action":{"id":10,"status":"running"}}'; fi
    else reply "$pc" '{"error":{"code":"locked"}}'; fi ;;
  "GET /actions/10")
    if [[ -f "$W/action_flaky" && "$(cat "$W/action_flaky")" -gt 0 ]]; then echo $(( $(cat "$W/action_flaky") - 1 )) > "$W/action_flaky"; reply 500 '{"error":{"code":"boom"}}'
    elif [[ -f "$W/poll_html" ]]; then reply 200 '<html><body>502 bad gateway</body></html>'
    else reply "$(cat "$W/action_get_code" 2>/dev/null || echo 200)" "$(jq -cn --arg st "$(cat "$W/action_status" 2>/dev/null || echo success)" '{action:{id:10,status:$st,error:{code:"x"}}}')"; fi ;;
  *) echo "UNEXPECTED $method $path" >> "$W/unexpected.log"; reply 599 '{"error":{"code":"unexpected"}}' ;;
esac
SH
cat > "$TMP/bin/terraform" <<'SH'
#!/usr/bin/env bash
W="${WORLD:?}"
case "$1 $2" in
  "state pull")
    # the one integration that only works inside the init'd root: a run from anywhere else is an unexpected call
    if [[ "$(pwd -P)" != "$(cd "$W" && pwd -P)" ]]; then echo "terraform ran outside INFRA_DIR: $(pwd -P)" >> "$W/unexpected.log"; exit 1; fi
    [[ -f "$W/state_fail" ]] && exit 1
    # decoys come FIRST: a selector that loosens mode, type, name or index picks one of them and the id comparison reds
    jq -cn --argjson w1 "$(cat "$W/state_web1")" --arg w2 "$(cat "$W/state_web2")" --arg w1id "$(cat "$W/state_web1id")" --argjson str "$([[ -f "$W/state_str" ]] && echo true || echo false)" '
      def idv($s): if $s == "@null" then null elif ($s|test("^[0-9]+$")) and ($str|not) then ($s|tonumber) else $s end;
      def w1attrs: if $w1id == "@missing" then {} else {id:idv($w1id)} end;
      {serial:5,lineage:"L1",resources:[
      {mode:"managed",type:"hcloud_volume",name:"web",instances:[{index_key:"web-2",attributes:{id:111}},{index_key:"web-1",attributes:{id:112}}]},
      {mode:"data",type:"hcloud_server",name:"web",instances:[{index_key:"web-2",attributes:{id:222}},{index_key:"web-1",attributes:{id:223}}]},
      {mode:"managed",type:"hcloud_server",name:"other",instances:[{index_key:"web-2",attributes:{id:444}},{index_key:"web-1",attributes:{id:445}}]},
      {mode:"managed",type:"hcloud_server",name:"web",instances:((if $w1 == 1 then [{index_key:"web-1",attributes:w1attrs}] else [] end)
        + (if $w2 == "none" then [] else [{index_key:"web-2",attributes:{id:idv($w2)}}] end))}]}' ;;
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
[[ -n "$W" ]] && { echo S >> "$W/order.log"; echo "${1:-}" >> "$W/sleep.log"; }
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
    # OK-shaped, but not green by the grading helper's own test (device, mount source, escrow): never a PASS
    okdev) msg="OK: /mnt/data is LUKS-backed (device_type=ext4 mount_source=/dev/mapper/workspaces escrow=ok header=readable boot_id=${boot})" ;;
    okmnt) msg="OK: /mnt/data is LUKS-backed (device_type=crypto_LUKS mount_source=/dev/sdb1 escrow=ok header=readable boot_id=${boot})" ;;
    okesc) msg="OK: /mnt/data is LUKS-backed (device_type=crypto_LUKS mount_source=/dev/mapper/workspaces escrow=missing header=readable boot_id=${boot})" ;;
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
  WN=$((WN + 1)); W="${BATTERY_DIR:-$TMP}/w.${WN}"; assert_fixture_dir "$W"; rm -rf "$W"; mkdir -p "$W"; export WORLD="$W"
  : > "$W/calls.log"; : > "$W/writes.log"; : > "$W/order.log"; : > "$W/queries.log"; : > "$W/argv.log"; : > "$W/sleep.log"
  echo "$SID" > "$W/server_id"; echo ok > "$W/servers_mode"; echo 2026-10-06T19:32:09+00:00 > "$W/server_created"
  echo 1 > "$W/state_web1"; echo "$SID" > "$W/state_web2"; echo 123931471 > "$W/state_web1id"; echo absent > "$W/never"
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
      state_web1id=*) echo "${f#*=}" > "$W/state_web1id" ;;
      state_str) touch "$W/state_str" ;;
      token=*) printf '%s\n' "${f#*=}" > "$W/token" ;;
      state_fail) touch "$W/state_fail" ;;
      never=*) echo "${f#*=}" > "$W/never" ;;
      never_unset) touch "$W/never_unset" ;;
      no_token) touch "$W/no_token" ;;
      post_code=*) echo "${f#*=}" > "$W/post_code" ;;
      post_noid) touch "$W/post_noid" ;;
      post_html) touch "$W/post_html" ;;
      poll_html) touch "$W/poll_html" ;;
      action_flaky=*) echo "${f#*=}" > "$W/action_flaky" ;;
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
set_rows() { local k="$1"; shift; assert_fixture_dir "$W"; printf '%s\n' "$@" > "$W/bs.$k"; }
set_boots() { assert_fixture_dir "$W"; : > "$W/bs.boots"; local b; for b in "$@"; do fx_boot ${b} >> "$W/bs.boots"; done; }   # each arg: "id first newest n"
bsfail() { assert_fixture_dir "$W"; echo "${2:-99}" > "$W/bsfail.$1"; echo "${3:-503}" > "$W/bsfail_mode.$1"; }
last_anchor() { grep '^anchor_epoch=' "$W/gh_out" 2>/dev/null | tail -n 1; }   # GITHUB_OUTPUT is last-write-wins
now_in_world() { if [[ -f "$W/clock" ]]; then cat "$W/clock"; else "$REAL_DATE" -u +%s; fi; }
anchor_now() { echo $(( $(now_in_world) - SINCE )); }

# ---- row bookkeeping ---------------------------------------------------------------------------------------------------
deny_hits() { grep -iEo "$DENY_RE" || true; }
check() { # <name> <condition-result 0|1>
  assert_fixture_dir "$BATTERY_DIR"; echo x >> "$BATTERY_DIR/checks"
  if [[ "$2" -ne 0 ]]; then printf 'FAILED %s\n' "$1"; fi
}
cond() { if "$@"; then echo 0; else echo 1; fi; }
RBASH=(bash); EBASH=(bash); RENV=(); ENVE=()

# universal checks over one finished run: footer on every path, no claim word, no secret, no unexpected call
common_checks() { # <name> <stdout> <script-kind: r|e>
  local name="$1" o="$2" kind="$3" err hits
  assert_fixture_dir "$BATTERY_DIR"; echo x >> "$BATTERY_DIR/scanned"
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
  assert_fixture_dir "$BATTERY_DIR"; echo x >> "$BATTERY_DIR/runs"; echo r >> "$BATTERY_DIR/rruns"
  local -a envv=(PATH="$TMP/bin:/usr/bin:/bin" HOME="$W" WORLD="$W" INFRA_DIR="$W" GITHUB_OUTPUT="$W/gh_out" GITHUB_STEP_SUMMARY="$W/summary"
                 WEB_HOST_REBOOT_ACTION_POLL_S=0 REPO=o/r GH_TOKEN=x)
  if [[ -f "$W/no_token" ]]; then :; elif [[ -f "$W/token" ]]; then envv+=(HCLOUD_TOKEN="$(cat "$W/token")"); else envv+=(HCLOUD_TOKEN="$TOK"); fi
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
  R_SCRIPT="$1"; BATTERY_DIR="$(mktemp -d "$TMP/br.XXXXXX")"; : > "$BATTERY_DIR/runs"; : > "$BATTERY_DIR/checks"; : > "$BATTERY_DIR/rruns"; : > "$BATTERY_DIR/scanned"
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
  check "reboot: the fixed footer is printed exactly once on a successful run" "$([[ "$(grep -cF -- "$FOOTER" <<<"$LASTOUT")" == 1 ]]; echo $?)"
  check "reboot: the token travelled on stdin" "$([[ "$(cat "$W/stdin.last")" == *"$TOK"* ]]; echo $?)"
  check "reboot: stderr carries only the mask line and (when traced) nothing else" "$([[ "$(grep -vc '^::add-mask::' "$W/stderr")" == 0 ]]; echo $?)"
  world "created=2026-10-06T21:32:09+02:00"; runr "reboot: a non-UTC creation time does not matter" 0 "accepted by Hetzner" reboot web-2 "$CONF"
  world "server_id=123456789012" "state_web2=123456789012"; runr "reboot: a 12-digit id (the upper bound of the confirm pattern) is accepted when all three agree" 0 "accepted by Hetzner" reboot web-2 REBOOT-web-2-123456789012
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
  # a UTF-8 locale reads non-ASCII digits as [0-9] in a bash regex: the script pins LC_ALL=C itself (the digits below are Arabic-Indic and fullwidth)
  loc=""; for c in en_US.utf8 en_US.UTF-8 C.utf8; do
    if (export LC_ALL="$c"; [[ $'٢١' =~ ^[1-9][0-9]{0,11}$ || $'１' =~ ^[1-9][0-9]*$ ]]) 2>/dev/null; then loc="$c"; break; fi
  done
  if [[ -n "$loc" ]]; then
    for c in $'٢١' $'１２' "${SID}"$'٣'; do
      world; RENV=(LC_ALL="$loc"); runr "reboot: a non-ASCII digit in confirm is refused even under ${loc}" 1 "confirm must be" reboot web-2 "REBOOT-web-2-${c}"; RENV=()
      want_no_api_call "reboot non-ASCII confirm"; want_nothing_written "reboot non-ASCII confirm"
    done
  else
    check "reboot: (control) a UTF-8 locale that reads a non-ASCII digit as [0-9] exists here; none does, so the locale rows cannot go red on this host" 0
    echo "note: no UTF-8 locale reading non-ASCII digits as [0-9] on this host; the S5 rows ran as no-ops" >&2
  fi
  # ---- refusal 1 (shape): a token outside the bearer alphabet is refused by name before any curl; its value is never printed
  for c in "tok en" 'tok"x' "tok;x" 'tok$x' $'tok\nheader = "X: y"' "tok&x"; do
    world "token=$c"; runr "reboot: a token of an unusable shape is refused before any call" 1 "unusable shape" reboot web-2 "$CONF"
    want_no_api_call "reboot token shape"; want_nothing_written "reboot token shape"
    check "reboot: the unusable token value was not printed" "$([[ "$LASTOUT" != *"tok en"* && "$LASTOUT" != *'header = "X'* && "$(cat "$W/stderr")" != *"header = "* && "$(cat "$W/stderr")" != *"::add-mask::tok"* ]]; echo $?)"
  done
  for c in "a.b_c~d+e/f=g-h" "0" "Z"; do
    world "token=$c"; runr "reboot: every character of the bearer alphabet is accepted (${c})" 0 "accepted by Hetzner" reboot web-2 "$CONF"
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
  # the state selector: decoys (a volume, a data source, another server resource, each with a web-2 and a web-1 index) come first in the
  # fixture, so a selector that loosens mode, type, name or index picks a decoy and the happy path reds; ids may be strings (the real producer's shape)
  world state_str; runr "reboot: string-typed ids in the state are the same ids" 0 "accepted by Hetzner" reboot web-2 "$CONF"
  world; runr "reboot: number-typed ids in the state are the same ids (decoy resources ahead of the real one)" 0 "accepted by Hetzner" reboot web-2 "$CONF"
  # web-1's own id in the state: the live id must never equal it, whatever the constant says
  world "state_web1id=${SID}"; runr "reboot: a live id equal to the id the state holds for web-1 is refused" 1 "carries the id the Terraform state holds for web-1" reboot web-2 "$CONF"; want_nothing_written "reboot web-1 state id"
  world "state_web1id=${SID}" state_str; runr "reboot: the same, with string-typed ids" 1 "carries the id the Terraform state holds for web-1" reboot web-2 "$CONF"; want_nothing_written "reboot web-1 state id (strings)"
  world "state_web1id=987654321"; runr "reboot: a web-1 id in the state that differs from the live id is fine" 0 "accepted by Hetzner" reboot web-2 "$CONF"
  world "state_web1id=987654321" state_str; runr "reboot: a string-typed numeric web-1 id in the state that differs from the live id is fine" 0 "accepted by Hetzner" reboot web-2 "$CONF"
  # a state that does not GIVE a numeric web-1 id cannot show that the live id is not web-1's: refused by name, nothing rebooted (fail closed)
  world "state_web1id=::error::x"; runr "reboot: a non-numeric string web-1 id in the state is refused" 1 "holds no numeric id for web-1" reboot web-2 "$CONF"; want_nothing_written "reboot web-1 state id non-numeric"
  check "reboot: the hostile web-1 state id is not in the output" "$([[ "$LASTOUT" != *"::error::x"* ]]; echo $?)"
  world "state_web1id=@null"; runr "reboot: a null web-1 id in the state is refused" 1 "holds no numeric id for web-1" reboot web-2 "$CONF"; want_nothing_written "reboot web-1 state id null"
  world "state_web1id=@missing"; runr "reboot: a web-1 instance without an id attribute in the state is refused" 1 "holds no numeric id for web-1" reboot web-2 "$CONF"; want_nothing_written "reboot web-1 state id missing"
  check "reboot: terraform ran inside INFRA_DIR (the shim records a run from any other directory as an unexpected call)" "$([[ ! -s "$W/unexpected.log" ]]; echo $?)"
  # ---- refusal 9: the POST
  world post_code=403; runr "reboot: a 403 names the read-only token" 1 "reboot -> 403" reboot web-2 "$CONF"
  check "reboot: a 403 adds the read-only token hint" "$([[ "$LASTOUT" == *"read-only Hetzner token"* ]]; echo $?)"
  check "reboot: a definite 4xx withdraws the anchor (the last anchor_epoch line is empty)" "$([[ "$(last_anchor)" == "anchor_epoch=" ]]; echo $?)"
  check "reboot: a definite 4xx says none was sent and invites a re-dispatch" "$([[ "$LASTOUT" == *"none was sent"* && "$LASTOUT" == *"re-dispatch"* && "$LASTOUT" != *"DO NOT re-dispatch"* ]]; echo $?)"
  check "reboot: a refused POST leaves the earlier anchor line and the withdrawal (two lines)" "$([[ "$(grep -c '^anchor_epoch=' "$W/gh_out")" == 2 ]]; echo $?)"
  world post_code=422; runr "reboot: a 422 fails with Hetzner's code" 1 "reboot -> 422 (error.code=locked)" reboot web-2 "$CONF"
  check "reboot: a 422 withdraws the anchor" "$([[ "$(last_anchor)" == "anchor_epoch=" ]]; echo $?)"
  world post_code=423; runr "reboot: a 423 fails" 1 "reboot -> 423" reboot web-2 "$CONF"
  world post_code=499; runr "reboot: the top of the 4xx band is definite" 1 "reboot -> 499" reboot web-2 "$CONF"
  check "reboot: a 499 withdraws the anchor" "$([[ "$(last_anchor)" == "anchor_epoch=" ]]; echo $?)"
  # the 4xx boundary: 400, 401 and 429 are definite refusals (anchor withdrawn); 100, 301 and 307 are not (anchor kept)
  for c in 400 401 429; do
    world "post_code=$c"; runr "reboot: a ${c} is a definite 4xx" 1 "reboot -> ${c}" reboot web-2 "$CONF"
    check "reboot: a ${c} withdraws the anchor (the last anchor_epoch line is empty)" "$([[ "$(last_anchor)" == "anchor_epoch=" ]]; echo $?)"
  done
  for c in 100 301 307; do
    world "post_code=$c"; runr "reboot: a ${c} is not a definite 4xx: the request may have been sent" 1 "the request may have been sent" reboot web-2 "$CONF"
    check "reboot: a ${c} keeps the anchor (the last anchor_epoch line is the epoch)" "$([[ "$(last_anchor)" =~ ^anchor_epoch=[0-9]{10}$ ]]; echo $?)"
  done
  for c in 500 502 000 200 202 399; do
    world "post_code=$c"; runr "reboot: a POST answered ${c} may have been sent" 1 "the request may have been sent" reboot web-2 "$CONF"
    check "reboot: a ${c} keeps the anchor (the last anchor_epoch line is the epoch)" "$([[ "$(last_anchor)" =~ ^anchor_epoch=[0-9]{10}$ ]]; echo $?)"
    check "reboot: a ${c} says DO NOT re-dispatch and hands over the grade command" "$([[ "$LASTOUT" == *"DO NOT re-dispatch"* && "$LASTOUT" == *"web-host-reboot-evidence.sh grade --anchor"* ]]; echo $?)"
  done
  world post_noid; runr "reboot: a 201 without an action id fails" 1 "no numeric action id" reboot web-2 "$CONF"
  check "reboot: the anchor survives a POST that returned no action id" "$([[ "$(last_anchor)" =~ ^anchor_epoch=[0-9]{10}$ ]]; echo $?)"
  world post_html; runr "reboot: a 201 whose body is not JSON reaches the named failure, not a bare jq abort" 1 "no numeric action id" reboot web-2 "$CONF"
  check "reboot: a non-JSON 201 body says do not re-dispatch" "$([[ "$LASTOUT" == *"DO NOT re-dispatch"* ]]; echo $?)"
  check "reboot: a non-JSON 201 body keeps the anchor" "$([[ "$(last_anchor)" =~ ^anchor_epoch=[0-9]{10}$ ]]; echo $?)"
  # ---- refusal 10: the action outcome
  world action_status=error; runr "reboot: an action that ends in error is unconfirmed, not success" 1 "reboot request outcome unconfirmed" reboot web-2 "$CONF"
  check "reboot: an action that ends in error stops the polling at once (one poll)" "$([[ "$(grep -c '^GET /actions/10' "$W/calls.log")" == 1 ]]; echo $?)"
  check "reboot: the unconfirmed message says not to re-dispatch" "$([[ "$LASTOUT" == *"DO NOT re-dispatch"* ]]; echo $?)"
  check "reboot: the unconfirmed message hands over the grade command" "$([[ "$LASTOUT" == *"web-host-reboot-evidence.sh grade --anchor"* ]]; echo $?)"
  check "reboot: the anchor is already out after an unconfirmed action" "$([[ "$(grep -c '^anchor_epoch=' "$W/gh_out")" == 1 ]]; echo $?)"
  check "reboot: an unconfirmed outcome never claims acceptance" "$([[ "$LASTOUT" != *"accepted by Hetzner"* ]]; echo $?)"
  world action_status=running; runr "reboot: an action still running after 24 polls is unconfirmed" 1 "reboot request outcome unconfirmed" reboot web-2 "$CONF"
  check "reboot: exactly 24 polls were made" "$([[ "$(grep -c '^GET /actions/10' "$W/calls.log")" == 24 ]]; echo $?)"
  world action_get_code=500; runr "reboot: an action poll that answers 500 is unconfirmed" 1 "reboot request outcome unconfirmed" reboot web-2 "$CONF"
  check "reboot: a 500 poll does not end the loop (all 24 polls were made)" "$([[ "$(grep -c '^GET /actions/10' "$W/calls.log")" == 24 ]]; echo $?)"
  world action_flaky=3; runr "reboot: a few failed polls followed by success is accepted (Hetzner accepted the action)" 0 "accepted by Hetzner" reboot web-2 "$CONF"
  check "reboot: the flaky polls were retried (4 polls)" "$([[ "$(grep -c '^GET /actions/10' "$W/calls.log")" == 4 ]]; echo $?)"
  world action_flaky=23; runr "reboot: success on the 24th poll is accepted" 0 "accepted by Hetzner" reboot web-2 "$CONF"
  world action_flaky=24; runr "reboot: 24 failed polls are unconfirmed" 1 "reboot request outcome unconfirmed" reboot web-2 "$CONF"
  world poll_html; runr "reboot: a poll body that is not JSON is unconfirmed after 24 polls, not a bare jq abort" 1 "reboot request outcome unconfirmed" reboot web-2 "$CONF"
  check "reboot: a non-JSON poll body says do not re-dispatch and keeps the anchor" "$([[ "$LASTOUT" == *"DO NOT re-dispatch"* && "$(last_anchor)" =~ ^anchor_epoch=[0-9]{10}$ ]]; echo $?)"
  check "reboot: a non-JSON poll body was polled 24 times" "$([[ "$(grep -c '^GET /actions/10' "$W/calls.log")" == 24 ]]; echo $?)"
  # the poll interval is a seam: 1-3 digits or the default 5
  RENV=(WEB_HOST_REBOOT_ACTION_POLL_S=7); world action_status=running; runr "reboot: a 1-digit poll interval is honoured" 1 "unconfirmed" reboot web-2 "$CONF"
  check "reboot: every poll sleeps the configured 7 s" "$([[ "$(sort -u "$W/sleep.log" | tr '\n' ' ')" == "7 " && "$(grep -c . "$W/sleep.log")" == 24 ]]; echo $?)"
  RENV=(WEB_HOST_REBOOT_ACTION_POLL_S=120); world action_status=running; runr "reboot: a 3-digit poll interval is honoured" 1 "unconfirmed" reboot web-2 "$CONF"
  check "reboot: a 3-digit interval is used as given" "$([[ "$(sort -u "$W/sleep.log" | tr '\n' ' ')" == "120 " ]]; echo $?)"
  for c in abc "" 1000 "5;x" -1 "1 2" 1.5; do
    RENV=(WEB_HOST_REBOOT_ACTION_POLL_S="$c"); world action_status=running; runr "reboot: a poll interval of '${c}' falls back to 5" 1 "unconfirmed" reboot web-2 "$CONF"
    check "reboot: a poll interval of '${c}' sleeps 5 s, never the raw value" "$([[ "$(sort -u "$W/sleep.log" | tr '\n' ' ')" == "5 " ]]; echo $?)"
  done
  RENV=()
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
  check "summary: the footer is printed exactly once on stdout" "$([[ "$(grep -cF -- "$FOOTER" <<<"$LASTOUT")" == 1 ]]; echo $?)"
  check "summary: the footer is in the step summary" "$([[ "$(cat "$W/summary")" == *"$FOOTER"* ]]; echo $?)"
  check "summary: the anchor and server id are in the step summary" "$([[ "$(cat "$W/summary")" == *1800000000* && "$(cat "$W/summary")" == *"$SID"* ]]; echo $?)"
  check "summary: no Hetzner call is made" "$([[ ! -s "$W/calls.log" ]]; echo $?)"
  world; RENV=(JOB_STATUS=failure HOST=web-2 SERVER_ID="$SID" ANCHOR_EPOCH=1800000000 REASON=x RUN_ID=1)
  runr "summary: a failed job does not claim a sent request as accepted" 0 "did not complete" summary
  check "summary: a failed job with an anchor says do not re-dispatch" "$([[ "$(cat "$W/summary")" == *"do not re-dispatch"* || "$(cat "$W/summary")" == *"DO NOT re-dispatch"* ]]; echo $?)"
  check "summary: a failed job never says accepted" "$([[ "$(cat "$W/summary")" != *"accepted by Hetzner"* ]]; echo $?)"
  world; RENV=(JOB_STATUS=failure HOST=web-2 REASON=x)
  runr "summary: a refused run has no anchor and says nothing was sent" 0 "no anchor" summary
  check "summary: a refused run says no request was sent" "$([[ "$(cat "$W/summary")" == *"no request was sent"* ]]; echo $?)"
  world; RENV=(JOB_STATUS=cancelled HOST=web-2 REASON=x)
  runr "summary: a cancelled run with no anchor does not claim that nothing was sent" 0 "unknown whether a request was sent" summary
  check "summary: a cancelled run never says no request was sent" "$([[ "$(cat "$W/summary")" != *"no request was sent"* && "$(cat "$W/summary")" != *"no anchor was written"* ]]; echo $?)"
  world; RENV=(JOB_STATUS=cancelled HOST=web-2 SERVER_ID="$SID" ANCHOR_EPOCH=1800000000 REASON=x)
  runr "summary: a cancelled run with an anchor hands over the grade command" 0 "unknown whether a request was sent" summary
  check "summary: a cancelled run with an anchor says do not re-dispatch and prints the grade command" "$([[ "$(cat "$W/summary")" == *"do not re-dispatch"* && "$(cat "$W/summary")" == *"grade --anchor 1800000000"* ]]; echo $?)"
  world; RENV=(JOB_STATUS=success HOST=web-2 SERVER_ID="$SID" ANCHOR_EPOCH=1800000000 REASON='a [link](https://e.invalid) **b** <img src=x> `c` ```d')
  runr "summary: the reason is a code span, never live markdown" 0 "-" summary
  want_reason='| reason | `a [link](https://e.invalid) **b** <img src=x> '"'c'"' '"'''d"'` |'
  check "summary: the reason row is one code span with no inner backtick" "$([[ "$(grep '^| reason |' "$W/summary")" == "$want_reason" ]]; echo $?)"
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
sql_for() { awk -v RS='\n---\n' -v pat="$1" 'index($0, pat) { print; exit }' "$W/sql.log"; }   # the recorded query text containing <pat>
no_verdict_misreads() { check "$1: the verdict line is unique" "$([[ "$(printf '%s\n' "$LASTOUT" | grep -c '^verdict: ')" == 1 ]]; echo $?)"; }

battery_evidence() {
  E_SCRIPT="$1"; BATTERY_DIR="$(mktemp -d "$TMP/be.XXXXXX")"; : > "$BATTERY_DIR/runs"; : > "$BATTERY_DIR/checks"; : > "$BATTERY_DIR/eruns"; : > "$BATTERY_DIR/scanned"
  local i
  # ---- the verdict table, one fixture each (the old boot is CUR; the request is SINCE seconds old; the new boot is NEW)
  world; set_rows ready "$(fx_ready 100 "$NEWD" formatted)"; set_boots "$CUR 45000 20 3000"
  graded "evidence: a readiness row younger than the request means the instance was re-created" 5 instance_recreated_after_request; no_verdict_misreads "evidence: recreated"
  check "evidence: a re-created instance says so in the next line" "$([[ "$LASTOUT" == *"next:"*"re-created"* ]]; echo $?)"
  world; set_rows ready "$(fx_ready 45000 "$CURD")" "junk row that is not json at all"; graded "evidence: an unparseable readiness body is a read fault, never a verdict" 5 read_fault
  world; set_rows ready "$(fx_ready 100 "$NEWD" | sed 's/ready=1/ready=1 ready=1/')"; set_boots "$CUR 45000 20 3000"
  graded "evidence: a malformed readiness row younger than the request is not a re-creation" 4 request_not_acted_on
  world; graded "evidence: the old boot still shipping and no new boot: the request was not acted on (exit 4)" 4 request_not_acted_on; no_verdict_misreads "evidence: not acted on"
  check "evidence: not-acted-on says nothing is dark" "$([[ "$LASTOUT" == *"nothing is dark"* ]]; echo $?)"
  world; set_boots "$CUR 45000 900 3000"; graded "evidence: the old boot silent and no new boot (exit 4)" 4 host_silent_no_new_boot
  check "evidence: a silent host points at the dark-host path" "$([[ "$LASTOUT" == *"dark-host"* ]]; echo $?)"
  world; set_boots "$CUR 45000 700 3000" "$NEW 300 15 40"; set_rows probe ""; graded "evidence: a new boot and no probe row is the expected pending state (exit 2)" 2 new_boot_seen_probe_pending
  check "evidence: pending gives the daily probe window" "$([[ "$LASTOUT" == *"00:00 to 00:30 UTC"* ]]; echo $?)"
  check "evidence: pending gives the filled-in re-grade command" "$([[ "$LASTOUT" == *"web-host-reboot-evidence.sh grade --anchor $(anchor_now)"* || "$LASTOUT" == *"web-host-reboot-evidence.sh grade --anchor"* ]]; echo $?)"
  check "evidence: pending says not to re-dispatch to force a row" "$([[ "${LASTOUT,,}" == *"do not re-dispatch"* ]]; echo $?)"
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
  world; set_boots "$CUR 45000 700 3000" "$NEW 300 15 40"; set_rows probe "$(fx_probe ok 28000 "$NEWD")"
  graded "evidence: an OK probe row older than the request is not evidence even on a matching boot id" 2 new_boot_seen_probe_pending
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
  graded "evidence: a probe row with an unparseable age is a read fault, not a verdict" 5 read_fault
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
  world; set_boots "::error::pwn 200 10 5" "${NEW^^} 200 10 5"; graded "evidence: a boot list with no readable id is a read fault" 5 read_fault
  world; set_rows boots ""; graded "evidence: an empty boot list is a read fault, never a verdict" 5 read_fault
  world; set_rows boots "not json"; graded "evidence: an unparseable boot body is a read fault" 5 read_fault
  # read faults per read, with the old boot in a state that would otherwise be a verdict
  for i in ready probe boots; do
    world; set_boots "$CUR 45000 700 3000" "$NEW 300 15 40"; set_rows probe "$(fx_probe ok 100 "$NEWD")"; bsfail "$i"
    graded "evidence: a 503 on the ${i} read is NOT YET read_fault, never a PASS or FAIL" 5 read_fault
    check "evidence: a ${i} read fault says nothing was measured" "$([[ "$LASTOUT" == *"Nothing was measured"* ]]; echo $?)"
  done
  world; set_boots "$CUR 45000 700 3000" "$NEW 300 15 40"; bsfail boots 99 timeout; graded "evidence: a timeout on the boot read is a read fault" 5 read_fault
  world; set_boots "$CUR 45000 700 3000" "$NEW 300 15 40"; set_rows probe "$(fx_probe fail 100)"; bsfail probe
  graded "evidence: a failed probe read never yields FAIL" 5 read_fault
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
  local sb="$BATTERY_DIR/sb"
  assert_fixture_dir "$sb"; assert_fixture_dir "$E_SCRIPT"; assert_fixture_dir "$ROOT"
  mkdir -p "$sb/scripts"; cp -r "$ROOT/scripts/lib" "$ROOT/scripts/betterstack-query.sh" "$sb/scripts/"; cp "$E_SCRIPT" "$sb/scripts/web-host-reboot-evidence.sh"
  sed -i 's/^w2l_fetch_ready() .*/: removed/' "$sb/scripts/lib/web2-luks-rows.sh"
  world; E_SAVE="$E_SCRIPT"; E_SCRIPT="$sb/scripts/web-host-reboot-evidence.sh"
  rune "evidence: a helper that lacks a function the reader calls is exit 3" 3 "CANNOT ESTABLISH" $(grade_args); E_SCRIPT="$E_SAVE"
  # BASH_SOURCE-relative resolution is real: a sandbox helper with another host name is what the sandbox script queries
  local sb2="$BATTERY_DIR/sb2"
  assert_fixture_dir "$sb2"; assert_fixture_dir "$E_SCRIPT"; assert_fixture_dir "$ROOT"
  mkdir -p "$sb2/scripts"; cp -r "$ROOT/scripts/lib" "$ROOT/scripts/betterstack-query.sh" "$sb2/scripts/"; cp "$E_SCRIPT" "$sb2/scripts/web-host-reboot-evidence.sh"
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
  world clock; local a; a="$(anchor_now)"; assert_fixture_dir "$W"; : > "$W/order.log"
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
  rune "evidence: a read fault that never clears ends NOT YET read_fault at the deadline (exit 5, unmeasured)" 5 "reason=read_fault" grade --anchor "$a" --window-min 2 --poll-s 60
  # ======== review round 1: boundary states of the verdict (S8-S13) and the fixtures that pin them (T2) ========
  # S8: the old boot's newest row after the request is not "still shipping" once it is older than SILENT_S (a shutdown row, then silence)
  world since=3000; set_boots "$CUR 45000 2390 3000"
  graded "evidence: an old boot whose newest row is a shutdown row shortly after the request, then silence, is a silent host" 4 host_silent_no_new_boot
  check "evidence: that silent host points at the dark-host path and never says nothing is dark" "$([[ "$LASTOUT" == *"dark-host"* && "$LASTOUT" != *"nothing is dark"* ]]; echo $?)"
  world since=3000; set_boots "$CUR 45000 600 3000"; graded "evidence: an old boot whose newest row is exactly SILENT_S old is still shipping" 4 request_not_acted_on
  world since=3000; set_boots "$CUR 45000 601 3000"; graded "evidence: one second past SILENT_S the old boot is silent" 4 host_silent_no_new_boot
  world since=3000; set_boots "$CUR 45000 20 3000" "$OTH 90000 50000 4000"; graded "evidence: with two old boots the youngest decides (still shipping)" 4 request_not_acted_on
  world since=3000; set_boots "$CUR 45000 900 3000" "$OTH 90000 20 4000"; graded "evidence: with two old boots the youngest decides (silent, though the older one ships)" 4 host_silent_no_new_boot
  # SILENT_S for the new boot, and which of two new boots decides
  world since=3000; set_boots "$CUR 45000 3100 3000" "$NEW 2000 600 40"; set_rows probe ""; graded "evidence: a new boot whose newest row is exactly SILENT_S old has not gone silent" 2 new_boot_seen_probe_pending
  world since=3000; set_boots "$CUR 45000 3100 3000" "$NEW 2000 601 40"; set_rows probe ""; graded "evidence: one second past SILENT_S the new boot is silent" 4 new_boot_seen_then_silent
  world since=3000; set_boots "$CUR 45000 3100 3000" "$NEW 2000 900 40" "$NEW2 1500 15 20"; set_rows probe ""
  graded "evidence: the newest of two new boots is alive: the earlier one going quiet is not a silent host" 2 new_boot_seen_probe_pending
  world since=3000; set_boots "$CUR 45000 3100 3000" "$NEW 2000 15 40" "$NEW2 1500 900 20"; set_rows probe ""
  graded "evidence: the newest of two new boots is silent though the earlier one ships" 4 new_boot_seen_then_silent
  world; set_boots "$CUR 45000 700 3000" "$NEW 300 15 40" "$NEW2 150 10 20"; set_rows probe "$(fx_probe ok 100 "$NEWD")"
  graded "evidence: with two new boots (a reboot loop) a probe row on the EARLIER one is a PASS" 0 probe_row_on_a_boot_that_began_after_the_request
  world; set_boots "$CUR 45000 700 3000" "$NEW 300 15 40" "$NEW2 150 10 20"; set_rows probe "$(fx_probe ok 100 "$NEW2D")"
  graded "evidence: with two new boots a probe row on the LATER one is a PASS" 0 probe_row_on_a_boot_that_began_after_the_request
  world; set_boots "$CUR 45000 700 3000" "$NEW 300 15 40" "$NEW2 150 10 20"; set_rows probe "$(fx_probe ok 100 "$OTHD")"
  graded "evidence: with two new boots a probe row on neither is not a PASS" 2 new_boot_seen_probe_pending
  world; set_boots "$CUR 45000 700 3000"; for i in 1 2 3 4 5 6; do fx_boot "$(printf '%032x' "$((i + 4096))")" "$((300 - i))" 15 40 >> "$W/bs.boots"; done; set_rows probe ""
  graded "evidence: six new boots are all counted and only five are listed" 2 new_boot_seen_probe_pending
  check "evidence: six boots began after the request, five lines list them" "$([[ "$LASTOUT" == *"boots began after the request: 6"* && "$(printf '%s\n' "$LASTOUT" | grep -c '^boot after the request: ')" == 5 ]]; echo $?)"
  # S12: PASS needs the grading helper's own green test on the newest row and no failing row after the new boot began
  for i in okdev okmnt okesc; do
    world; set_boots "$CUR 45000 700 3000" "$NEW 300 15 40"; set_rows probe "$(fx_probe "$i" 100 "$NEWD")"
    graded "evidence: an OK-shaped probe row that is not green by the helper's own test (${i}) after the new boot is a FAIL" 1 probe_row_not_green_after_new_boot; no_verdict_misreads "evidence: not green ${i}"
    check "evidence: a not-green row is never echoed (${i}) and the next line names the triage" "$([[ "$LASTOUT" != *ext4* && "$LASTOUT" != *sdb1* && "$LASTOUT" != *missing* && "$LASTOUT" == *"host-side versus volume-side"* ]]; echo $?)"
  done
  world; set_boots "$CUR 45000 700 3000" "$NEW 300 15 40"; set_rows probe "$(fx_probe okdev 28000 "$NEWD")"
  graded "evidence: a not-green row older than the new boot's first row is not evidence" 2 new_boot_seen_probe_pending
  world; set_boots "$CUR 45000 700 3000" "$NEW 300 15 40"; set_rows probe "$(fx_probe ok 100 "$NEWD")" "$(fx_probe okdev 250 "$NEWD")"
  graded "evidence: a not-green row inside the margin blocks the PASS and is resolved toward NOT YET" 2 new_boot_seen_probe_pending
  world; set_boots "$CUR 45000 700 3000" "$NEW 300 15 40"; set_rows probe "$(fx_probe ok 100 "$NEWD")" "$(fx_probe okdev 300 "$NEWD")"
  graded "evidence: a not-green row exactly as old as the new boot's first row is not after it: PASS" 0 probe_row_on_a_boot_that_began_after_the_request
  world; set_boots "$CUR 45000 700 3000" "$NEW 300 15 40"; set_rows probe "$(fx_probe ok 100 "$NEWD")" "$(fx_probe okdev 299 "$NEWD")"
  graded "evidence: a not-green row one second younger than the new boot's first row blocks the PASS" 2 new_boot_seen_probe_pending
  world; set_boots "$CUR 45000 700 3000" "$NEW 300 15 40"; set_rows probe "$(fx_probe ok 100 "$NEWD")" "$(fx_probe fail 150)"
  graded "evidence: an earlier FAIL row on the new boot is not hidden by a later OK row" 1 probe_fail_row_after_new_boot
  world; set_boots "$CUR 45000 700 3000" "$NEW 300 15 40"; set_rows probe "$(fx_probe ok 100 "$NEWD")" "$(fx_probe fail 28000)"
  graded "evidence: a FAIL row older than the new boot's first row does not block the PASS" 0 probe_row_on_a_boot_that_began_after_the_request
  world; set_boots "$CUR 45000 700 3000" "$NEW 300 15 40"; set_rows probe "$(fx_probe ok 100 "$NEWD")" "$(fx_probe fail 300)"
  graded "evidence: a FAIL row exactly as old as the new boot's first row is not after it: PASS" 0 probe_row_on_a_boot_that_began_after_the_request
  world; set_boots "$CUR 45000 700 3000" "$NEW 300 15 40"; set_rows probe "$(fx_probe ok 100 "$NEWD")" "$(fx_probe fail 299)"
  graded "evidence: a FAIL row one second younger than the new boot's first row blocks the PASS" 2 new_boot_seen_probe_pending
  world; set_boots "$CUR 45000 700 3000" "$NEW 300 15 40"; set_rows probe "$(fx_probe fail 179)"; graded "evidence: the margin boundary: a FAIL row 179 s old is a FAIL (179 + 120 < 300)" 1 probe_fail_row_after_new_boot
  world; set_boots "$CUR 45000 700 3000" "$NEW 300 15 40"; set_rows probe "$(fx_probe fail 180)"; graded "evidence: the margin boundary: a FAIL row 180 s old is NOT YET (180 + 120 is not < 300)" 2 new_boot_seen_probe_pending
  world; set_boots "$CUR 45000 700 3000" "$NEW 300 15 40"; set_rows probe "$(fx_probe ok 100 "$NEWD")" "$(fx_probe fail 100)"
  graded "evidence: an OK row and a FAIL row of equal age on the new boot grade FAIL" 1 probe_fail_row_after_new_boot
  world; set_boots "$CUR 45000 700 3000" "$NEW 300 15 40" "$NEW2 150 10 20"; set_rows probe "$(fx_probe fail 170)"
  graded "evidence: with two new boots a FAIL row is compared with the EARLIEST one's first row (170 + 120 < 300)" 1 probe_fail_row_after_new_boot
  world; set_boots "$CUR 45000 700 3000" "$NEW 300 15 40"; set_rows probe "$(fx_probe ok 100 "$NEWD")"
  rune "evidence: a PASS says what it measured and nothing about the volume" 0 "no probe row after that boot began failed" $(grade_args)
  # S11: exit 5 is unmeasured; exit 2 is only the expected pending state
  world; set_boots "$CUR 45000 700 3000"; bsfail boots; rune "evidence: a read fault prints its exit code next to the verdict" 5 "(exit 5)" $(grade_args)
  check "evidence: the read fault exit code is an output" "$([[ "$(sed -n 's/^exit_code=//p' "$W/gh_out")" == 5 ]]; echo $?)"
  world; set_rows ready "$(fx_ready 100 "$NEWD" formatted)"; rune "evidence: a re-created instance is unmeasured (exit 5) and says so" 5 "Nothing was measured about a reboot" $(grade_args)
  check "evidence: the re-created next line says exit 5, red" "$([[ "$LASTOUT" == *"exit 5, red"* && "$LASTOUT" == *"reason=instance_recreated_after_request (exit 5)"* ]]; echo $?)"
  world; set_boots "$CUR 45000 700 3000" "$NEW 300 15 40"; set_rows probe ""; rune "evidence: the pending state is still exit 2 and never mentions exit 5" 2 "reason=new_boot_seen_probe_pending" $(grade_args)
  check "evidence: pending carries no unmeasured wording" "$([[ "$LASTOUT" != *"exit 5"* && "$LASTOUT" != *"Nothing was measured"* ]]; echo $?)"
  # S13: ids and ages are gated before they are compared: a trailing newline is not a 32-hex id, an unreadable age is not "after the request"
  world; set_boots "$CUR 45000 20 3000"; fx_boot "${NEW}"$'\n' 300 15 40 >> "$W/bs.boots"
  graded "evidence: a journald boot id with a trailing newline is dropped, not read as a new boot" 4 request_not_acted_on
  check "evidence: the newline id is counted as dropped" "$([[ "$LASTOUT" == *"dropped_ids=1"* ]]; echo $?)"
  for i in "$NEW abc 15 40" "$NEW 300 abc 40" "$NEW 300 15 abc"; do
    world; set_boots "$CUR 45000 20 3000" "$i"; graded "evidence: a boot with an unreadable age or count ('${i#* }') is dropped and counted, never a boot after the request" 4 request_not_acted_on
    check "evidence: the unreadable boot is counted as dropped ('${i#* }')" "$([[ "$LASTOUT" == *"dropped_ids=1"* ]]; echo $?)"
  done
  world; set_boots "$CUR 45000 700 3000" "$NEW 300 15 40"; set_rows probe "$(fx_probe ok 100 "${NEWD}"$'\n')"
  graded "evidence: a probe boot id with a trailing newline is no id: it never joins a boot" 2 new_boot_seen_probe_pending
  check "evidence: the newline probe id is printed as none" "$([[ "$LASTOUT" == *"latest probe row: class=ok boot_id=none"* ]]; echo $?)"
  # the readiness row's boot id is gated like its siblings: a uuid with a trailing newline (jq's `$` matches before it) is no id
  world; set_rows ready "$(fx_ready 45000 "${CURD}"$'\n')"; rune "evidence: snapshot with a newline-suffixed readiness boot id prints it as unknown" 0 "readiness row: boot_id=unknown age_s=45000" snapshot
  check "evidence: the newline readiness boot id never reaches the output" "$([[ "$LASTOUT" != *"$CURD"* ]]; echo $?)"
  world; rune "evidence: snapshot with a well-formed readiness boot id prints it" 0 "readiness row: boot_id=${CURD} age_s=45000" snapshot
  # S9: an anchor older than the boot read's reach is refused before anything is read (the clock is fixed, so the bound is exact)
  world clock; now="$(now_in_world)"
  rune "evidence: an anchor exactly at the bound (47 h) is graded" 5 "reason=instance_recreated_after_request" grade --anchor $(( now - 169200 )) --window-min 0
  world clock; rune "evidence: an anchor one second past the bound is refused by name" 3 "anchor_too_old" grade --anchor $(( now - 169201 )) --window-min 0
  check "evidence: a refused old anchor read nothing" "$([[ ! -s "$W/queries.log" ]]; echo $?)"
  world clock; rune "evidence: the window counts toward the bound (60 min at 165600 s old is on it)" 5 "reason=instance_recreated_after_request" grade --anchor $(( now - 165600 )) --window-min 60
  world clock; rune "evidence: the window counts toward the bound (61 min is past it)" 3 "anchor_too_old" grade --anchor $(( now - 165600 )) --window-min 61
  world clock; rune "evidence: anchor 0 is far too old" 3 "anchor_too_old" grade --anchor 0 --window-min 0
  # anchors in the future: 60 s of skew is tolerated, 61 is not
  world clock; rune "evidence: an anchor 60 s in the future is tolerated" 4 "reason=host_silent_no_new_boot" grade --anchor $(( now + 60 )) --window-min 0
  world clock; rune "evidence: an anchor 61 s in the future is refused" 3 "in the future" grade --anchor $(( now + 61 )) --window-min 0
  # S10: leading zeros are refused (no octal reading), and so is a zero poll interval
  world; rune "evidence: an anchor with a leading zero is refused (10 digits, so only the pattern can refuse it)" 3 "no leading zero" grade --anchor 0123456789 --window-min 0
  world; rune "evidence: a window with a leading zero is refused" 3 "no leading zero" grade --anchor "$(anchor_now)" --window-min 08
  world; rune "evidence: a double-zero window is refused" 3 "no leading zero" grade --anchor "$(anchor_now)" --window-min 00
  world; rune "evidence: a poll interval with a leading zero is refused" 3 "no leading zero" grade --anchor "$(anchor_now)" --window-min 0 --poll-s 010
  world; rune "evidence: a zero poll interval is refused" 3 "poll-s" grade --anchor "$(anchor_now)" --window-min 0 --poll-s 0
  world; rune "evidence: a plain zero window is a single read" 4 "reason=request_not_acted_on" grade --anchor "$(anchor_now)" --window-min 0
  # T2: the queries the reader sends carry the host filter, the lookbacks and the limits (the fake backend records the text)
  world; graded "evidence: (queries) a normal read" 4 request_not_acted_on
  sqlb="$(sql_for _BOOT_ID)"; sqlp="$(sql_for luks-monitor)"; sqlr="$(sql_for SOLEUR_FRESH_BOOT_READY)"
  check "evidence: the boots query filters on the host, the 48 h lookback and a non-empty boot id" "$([[ "$sqlb" == *"JSONExtractString(raw,'host_name') = 'soleur-web-2'"* && "$sqlb" == *"INTERVAL 48 HOUR"* && "$sqlb" == *"JSONExtractString(raw,'_BOOT_ID') != ''"* && "$sqlb" == *"LIMIT 50"* ]]; echo $?)"
  check "evidence: the probe query filters on host, identifier and unit, the 48 h lookback and 50 rows" "$([[ "$sqlp" == *"JSONExtractString(raw,'host_name') = 'soleur-web-2'"* && "$sqlp" == *"'luks-monitor'"* && "$sqlp" == *"'luks-monitor.service'"* && "$sqlp" == *"INTERVAL 48 HOUR"* && "$sqlp" == *"LIMIT 50"* ]]; echo $?)"
  check "evidence: the readiness query anchors the marker, filters on the host, the 90 day lookback and 20 rows" "$([[ "$sqlr" == *"startsWith(JSONExtractString(raw,'message'), 'SOLEUR_FRESH_BOOT_READY ')"* && "$sqlr" == *"' host=soleur-web-2 '"* && "$sqlr" == *"INTERVAL 90 DAY"* && "$sqlr" == *"LIMIT 20"* ]]; echo $?)"
  check "evidence: exactly three queries per read" "$([[ "$(grep -c . "$W/queries.log")" == 3 ]]; echo $?)"
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
  srow "static: ${b} has no ssh, doppler write, or token mint verb" "$([[ -f "$f" && "$(noncomment "$f" | grep -ciE '(^|[^a-z])ssh |scp |doppler[^#]*secrets[^#]*(set|delete|upload)|api\.doppler|tokens? (create|mint)')" == 0 ]]; echo $?)"
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
if [[ "$(git -C "$ROOT" rev-parse --show-toplevel 2>/dev/null)" == "$ROOT" ]]; then
  census_files() { git ls-files --cached --others --exclude-standard -- scripts .github apps 2>/dev/null; }
else
  census_files() { find scripts .github apps/web-platform/infra -type f 2>/dev/null; }   # a sandbox copy of this suite is not a git tree
fi
reboot_set="$(cd "$ROOT" && census_files | grep -E '\.(sh|yml|py)$' | grep -v '\.test\.' | xargs -r grep -l 'actions/reboot' 2>/dev/null | sort | tr '\n' ' ')"
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
# hapi() and need_token() DIVERGE from web2-rebirth.sh by design since #9594's sweep: this script sends the bearer header with a process
# substitution (`--config - < <(printf ...)`, not a pipe: a pipe can die of SIGPIPE under pipefail) after a token-shape check, and the
# rebirth script still pipes. The parity row for those two therefore compares the copies with the bearer plumbing and the shape check
# normalised away; every other helper stays byte-equal (whitespace-normalised).
norm_bearer() { python3 -c '
import re, sys
t = re.sub(r"\s*\\(?=\s|$)", " ", sys.stdin.read())   # line continuations
t = re.sub(r"""printf \x27header = "Authorization: Bearer %s"\\n\x27 "\$HCLOUD_TOKEN"\s*\|\s*""", "", t)
t = re.sub(r"""\s*< <\(printf \x27header = "Authorization: Bearer %s"\\n\x27 "\$HCLOUD_TOKEN"\)""", "", t)
t = re.sub(r"""\s*_bearer_ok "\$HCLOUD_TOKEN" \|\| fail "[^"]*"\s*;?""", " ", t)
t = re.sub(r"local -a extra\s+extra=\(\)", "local -a extra=()", t)   # the lint wants a line-start assignment
t = re.sub(r"\s*;\s*", " ", t)
print(re.sub(r"\s+", " ", t).strip())'; }
if [[ -f "$ROOT/scripts/web2-rebirth.sh" ]]; then
  for fn in errcode fail out clean write_hint; do
    a="$(python3 -c "$py_fn" "$RSCRIPT" "$fn" 2>/dev/null)"; b="$(python3 -c "$py_fn" "$ROOT/scripts/web2-rebirth.sh" "$fn")"
    srow "static: parity: ${fn}() equals web2-rebirth.sh's copy" "$([[ -n "$a" && "$a" == "$b" ]]; echo $?)"
  done
  for fn in hapi need_token; do
    a="$(python3 -c "$py_fn" "$RSCRIPT" "$fn" 2>/dev/null | norm_bearer)"; b="$(python3 -c "$py_fn" "$ROOT/scripts/web2-rebirth.sh" "$fn" | norm_bearer)"
    srow "static: parity: ${fn}() equals web2-rebirth.sh's copy with the bearer plumbing normalised (intended divergence, #9594)" "$([[ -n "$a" && "$a" == "$b" ]]; echo $?)"
  done
  # the normaliser is live: it does not hide a real difference (a changed curl flag), and it does reduce this script's hapi to the rebirth's
  a="$(python3 -c "$py_fn" "$RSCRIPT" hapi | sed 's/--max-time 15/--max-time 16/' | norm_bearer)"; b="$(python3 -c "$py_fn" "$ROOT/scripts/web2-rebirth.sh" hapi | norm_bearer)"
  srow "static: (positive control) the bearer normaliser still reports a changed curl flag" "$([[ "$a" != "$b" ]]; echo $?)"
fi
# (functions of a path, shared by the static rows and by the mutation grader's static_red)
bearer_psub_ok() { [[ -f "$1" && "$(grep -v '^[[:space:]]*#' "$1" | grep -c '< <(printf .header = "Authorization: Bearer')" == 1 && "$(grep -v '^[[:space:]]*#' "$1" | grep -cE 'printf .header = "Authorization: Bearer[^)]*\|')" == 0 ]]; }
bearer_guard_ok() { [[ -f "$1" && "$(grep -c "^_bearer_ok() { local LC_ALL=C; case \"\${1:-}\" in ''|\*\[!A-Za-z0-9._~+/=-\]\*) return 1 ;; esac; }\$" "$1")" == 1 && "$(grep -c '^  _bearer_ok "\$HCLOUD_TOKEN" || fail' "$1")" == 1 ]]; }
srow "static: the writer sends the bearer by process substitution, never a pipe (outside comments)" "$(bearer_psub_ok "$RSCRIPT"; echo $?)"
srow "static: the writer carries the canonical token-shape guard _bearer_ok (the one body the repo census compares) and applies it to the token" "$(bearer_guard_ok "$RSCRIPT"; echo $?)"
# S17: the copied literals are pinned to each other (the fixed footer, the grade command, the claim denylist, out()). Each of these is the
# kind of copy that drifts silently: a reworded footer in one place would reach a customer-facing surface unnoticed.
footer_lits() { python3 -c '
import re, sys
for m in re.finditer(r"\x27(This run reports rows only[^\x27]*)\x27", open(sys.argv[1]).read()):
    print(m.group(1))' "$1"; }
for f in "$RSCRIPT" "$ESCRIPT"; do
  b="$(basename "$f")"; lits="$(footer_lits "$f")"
  srow "static: footer parity: ${b} spells the footer at least twice (constant and inline xtrace arm) and every spelling equals this suite's copy" "$([[ "$(grep -c . <<<"$lits")" -ge 2 && -z "$(grep -vxF -- "$FOOTER" <<<"$lits")" ]]; echo $?)"
done
RUNBOOK="$ROOT/knowledge-base/engineering/operations/runbooks/web-host-reboot.md"
srow "static: footer parity: the runbook quotes the same footer sentence" "$([[ -f "$RUNBOOK" && "$(grep -cF -- "\"${FOOTER}\"" "$RUNBOOK")" -ge 1 ]]; echo $?)"
srow "static: (positive control) the footer extractor sees a planted drifted spelling" "$([[ -n "$(printf "x='This run reports rows only. It makes no statement.'\n" > "$TMP/fp.txt"; footer_lits "$TMP/fp.txt" | grep -vxF -- "$FOOTER")" ]]; echo $?)"
shell_const() { sed -n "s/^$2='\\(.*\\)'\$/\\1/p" "$1" | head -1; }
gc="$(shell_const "$RSCRIPT" GRADE_CMD)"; gh="$(shell_const "$ESCRIPT" GRADE_HINT)"
srow "static: grade command parity: the writer's GRADE_CMD is the reader's GRADE_HINT plus ' --anchor' (${gc} / ${gh})" "$([[ -n "$gc" && -n "$gh" && "$gc" == "${gh} --anchor" ]]; echo $?)"
srow "static: the grade command names the reader script that exists" "$([[ "$gh" == "bash scripts/web-host-reboot-evidence.sh grade" && -f "$ROOT/scripts/web-host-reboot-evidence.sh" ]]; echo $?)"
WF_SUITE="$ROOT/apps/web-platform/infra/web-host-reboot-workflow.test.sh"
wf_deny="$(python3 -c '
import re, sys
m = re.search(r"DENY_RE = re.compile\(r\x27(.*?)\x27, re\.I\)", open(sys.argv[1]).read())
print(m.group(1) if m else "")' "$WF_SUITE" 2>/dev/null)"
srow "static: denylist parity: the workflow suite's DENY_RE equals this suite's (the two suites scan the same words)" "$([[ -f "$WF_SUITE" && -n "$wf_deny" && "$wf_deny" == "$DENY_RE" ]]; echo $?)"
srow "static: out() parity: the writer's and the reader's out() are the same function" "$([[ -n "$(python3 -c "$py_fn" "$RSCRIPT" out)" && "$(python3 -c "$py_fn" "$RSCRIPT" out)" == "$(python3 -c "$py_fn" "$ESCRIPT" out)" ]]; echo $?)"

# tombstone: the subjects retire together with the two scripts they depend on
leftover="$(cd "$ROOT" && find scripts .github apps/web-platform/infra -maxdepth 2 -name 'web-host-reboot*' 2>/dev/null | sort | tr '\n' ' ')"
if [[ ! -f "$ROOT/scripts/web2-rebirth.sh" || ! -f "$ROOT/scripts/web2-rebirth-never-pooled.sh" ]]; then
  srow "static: TOMBSTONE the rebirth scripts are gone, so every web-host-reboot file must be gone too (${leftover})" "$([[ -z "$leftover" ]]; echo $?)"
else
  srow "static: the tombstone is armed (both rebirth scripts exist, so the subjects stay)" 0
fi
srow "static: the never-pooled reader the workflow depends on exists" "$([[ -f "$ROOT/scripts/web2-rebirth-never-pooled.sh" ]]; echo $?)"

# ---- floors: direct printf and exit, so a mutant of the guard itself is buildable ---------------------------------------
# the dynamic scan is itself live: a planted claim word in a run's output is reported, and a floor of scanned outputs holds
BATTERY_DIR="$R_BDIR"; world
planted="$(common_checks "planted" "the volume is Encrypted ${FOOTER}" r 2>&1)"
srow "static: (positive control) the dynamic scan reports a planted claim word" "$([[ "$planted" == *"denylisted claim word"* ]]; echo $?)"
planted_ok="$(common_checks "planted-ok" "PASS (row presence only) ${FOOTER}"$'\n'"${FOOTER}" r 2>&1)"
srow "static: (must-pass) the dynamic scan accepts the fixed wording" "$([[ -z "$planted_ok" ]]; echo $?)"
# ---- controls for the instruments themselves (T1): every verdict-owning helper is shown able to reject, and to stay silent on a pass
BATTERY_DIR="$R_BDIR"; world
# (srow's own controls print directly: a row that is reported through srow cannot show that srow works)
ctl="$(STATIC=0; fails=0; srow "planted-srow" 1; echo "fails=${fails} static=${STATIC}")"
if [[ "$ctl" != *"FAILED planted-srow"* || "$ctl" != *"fails=1 static=1"* ]]; then printf 'FAILED static: (positive control) srow reports a failing condition and counts it\n'; fails=$((fails + 1)); fi
ctl="$(STATIC=0; fails=0; srow "planted-ok" 0; echo "fails=${fails} static=${STATIC}")"
if [[ "$ctl" != "fails=0 static=1" ]]; then printf 'FAILED static: (must-pass) srow stays silent on a passing condition\n'; fails=$((fails + 1)); fi
ctl="$(check "planted-check" 1)"; srow "static: (positive control) check reports a failing condition" "$([[ "$ctl" == "FAILED planted-check" ]]; echo $?)"
ctl="$(check "planted-check-ok" 0)"; srow "static: (must-pass) check stays silent on a passing condition" "$([[ -z "$ctl" ]]; echo $?)"
world; ctl="$(runr "planted-rc" 0 - reboot web-2 BAD 2>&1)"
srow "static: (positive control) runr reports a wrong exit code" "$([[ "$ctl" == *"FAILED planted-rc (rc=1 want=0)"* ]]; echo $?)"
world; ctl="$(runr "planted-sub" 1 "text-that-is-not-there" reboot web-2 BAD 2>&1)"
srow "static: (positive control) runr reports a missing substring" "$([[ "$ctl" == *"FAILED planted-sub (output lacks"* ]]; echo $?)"
world; ctl="$(runr "planted-ok" 1 "confirm must be" reboot web-2 BAD 2>&1)"
srow "static: (must-pass) runr is silent when the exit code and the substring match" "$([[ -z "$ctl" ]]; echo $?)"
E_SCRIPT="$ESCRIPT"; world; ctl="$(rune "planted-erc" 0 - 2>&1)"
srow "static: (positive control) rune reports a wrong exit code" "$([[ "$ctl" == *"FAILED planted-erc (rc=64 want=0)"* ]]; echo $?)"
world; ctl="$(rune "planted-esub" 64 "text-that-is-not-there" 2>&1)"
srow "static: (positive control) rune reports a missing substring" "$([[ "$ctl" == *"FAILED planted-esub (output lacks"* ]]; echo $?)"
world; ctl="$(rune "planted-eok" 64 "usage" 2>&1)"
srow "static: (must-pass) rune is silent when the exit code and the substring match" "$([[ -z "$ctl" ]]; echo $?)"
world; echo "REBOOT /servers/1/actions/reboot" > "$W/writes.log"; echo "anchor_epoch=1" > "$W/gh_out"; ctl="$(want_nothing_written "planted-w")"
srow "static: (positive control) want_nothing_written reports a write and an anchor" "$([[ "$ctl" == *"FAILED planted-w: the write log is empty"* && "$ctl" == *"FAILED planted-w: no anchor was handed out"* ]]; echo $?)"
world; ctl="$(want_nothing_written "planted-w-ok")"; srow "static: (must-pass) want_nothing_written is silent on an untouched world" "$([[ -z "$ctl" ]]; echo $?)"
world; echo "GET /servers" > "$W/calls.log"; ctl="$(want_no_api_call "planted-c")"
srow "static: (positive control) want_no_api_call reports a Hetzner call" "$([[ "$ctl" == *"FAILED planted-c: no Hetzner call was made"* ]]; echo $?)"
world; ctl="$(want_no_api_call "planted-c-ok")"; srow "static: (must-pass) want_no_api_call is silent on an untouched world" "$([[ -z "$ctl" ]]; echo $?)"
LASTOUT=$'verdict: a\nverdict: b'; ctl="$(no_verdict_misreads "planted-v")"
srow "static: (positive control) no_verdict_misreads reports two verdict lines" "$([[ "$ctl" == *"FAILED planted-v: the verdict line is unique"* ]]; echo $?)"
LASTOUT=$'verdict: a'; ctl="$(no_verdict_misreads "planted-v-ok")"; srow "static: (must-pass) no_verdict_misreads is silent on one verdict line" "$([[ -z "$ctl" ]]; echo $?)"
miss=""; for t in luks-backed encrypted reborn reopen proof verified confirmed proves crypto_luks /dev/mapper 'luks=1' 'escrow=ok'; do
  [[ -n "$(printf 'x %s y\n' "$t" | deny_hits)" ]] || miss+="${t} "
done
srow "static: (positive control) the claim denylist catches every one of its tokens (missed: ${miss:-none})" "$([[ -z "$miss" ]]; echo $?)"
# the mutant grader's decision is a function, so it is itself under control (and mutated through the suite kind)
mutant_outcome() { # <expect: kill|survive> <red rows after the edit>
  local expect="$1" after="$2" verdict=survived
  [[ "$after" =~ ^[0-9]+$ && "$after" -gt 0 ]] && verdict=killed
  case "${expect}:${verdict}" in kill:killed|survive:survived) echo "ok ${verdict}" ;; *) echo "FAIL ${verdict}" ;; esac
}
srow "static: (grader) an edit that reds rows is a kill" "$([[ "$(mutant_outcome kill 3)" == "ok killed" ]]; echo $?)"
srow "static: (grader) an edit that reds no row is a survivor, and a failure for a normal mutant" "$([[ "$(mutant_outcome kill 0)" == "FAIL survived" ]]; echo $?)"
srow "static: (grader) a non-numeric or empty red count is a survivor, never a kill" "$([[ "$(mutant_outcome kill abc)" == "FAIL survived" && "$(mutant_outcome kill '')" == "FAIL survived" ]]; echo $?)"
srow "static: (grader) the known-survivor canary is ok when it survives" "$([[ "$(mutant_outcome survive 0)" == "ok survived" ]]; echo $?)"
srow "static: (grader) the known-survivor canary fails when it is killed (the grader could not report a survivor)" "$([[ "$(mutant_outcome survive 2)" == "FAIL killed" ]]; echo $?)"

scanned_n="$(( $(grep -c . "$R_BDIR/scanned") + $(grep -c . "$E_BDIR/scanned") ))"
SCAN_FLOOR=219
if [[ "$scanned_n" -lt "$SCAN_FLOOR" ]]; then printf 'FAILED floor: only %s outputs were scanned for claim words (floor %s)\n' "$scanned_n" "$SCAN_FLOOR"; fails=$((fails + 1)); fi
REFUSAL_FLOOR=106
if [[ "$nrefusal_runs" -lt "$REFUSAL_FLOOR" ]]; then printf 'FAILED floor: only %s reboot runs executed (floor %s)\n' "$nrefusal_runs" "$REFUSAL_FLOOR"; fails=$((fails + 1)); fi
ROWS_FLOOR=545
total_rows=$(( ran_r + ran_e + STATIC ))
if [[ "$total_rows" -lt "$ROWS_FLOOR" ]]; then printf 'FAILED floor: only %s rows ran (floor %s)\n' "$total_rows" "$ROWS_FLOOR"; fails=$((fails + 1)); fi
printf 'rows: reboot %s, evidence %s, static %s, total %s (floor %s); reboot runs %s, outputs scanned %s\n' "$ran_r" "$ran_e" "$STATIC" "$total_rows" "$ROWS_FLOOR" "$nrefusal_runs" "$scanned_n"

[[ "${WHR_NO_MUTATE:-}" == 1 ]] && { [[ "$fails" -eq 0 ]] && exit 0; exit 1; }
# MUTATION_SECTION_BEGIN
# ======================================================================================================================
# Mutation battery. Every mutant is an edit to a COPY (a sandbox tree under $TMP that mirrors the repo layout, so the scripts
# resolve their own helper through BASH_SOURCE); the real files are never touched and their hashes are re-checked at the end.
# A mutant is killed when the battery that fits it reports at least one red row. Each battery kind is first run against an
# unmutated sandbox (the CONTROL), so a sandbox that cannot run the battery can never score as a kill.
# ======================================================================================================================
MUT_JOBS="${MUT_JOBS:-6}"; MUT_SEQ=0; MUT_DIR="$TMP/mut"; mkdir -p "$MUT_DIR/defs" "$MUT_DIR/res" "$MUT_DIR/sb"
python3 - "$MUT_DIR/defs" <<'PY'
import json, os, sys
d = sys.argv[1]
R, E, SUITE, CENSUS = "scripts/web-host-reboot.sh", "scripts/web-host-reboot-evidence.sh", "scripts/web-host-reboot.test.sh", "apps/web-platform/infra/workspaces-luks-verify-workflow.test.sh"
ESCR = E
WFSUITE = "apps/web-platform/infra/web-host-reboot-workflow.test.sh"
M = []
def m(name, kind, target, *edits, expect="kill"):
    M.append({"name": name, "kind": kind, "target": target, "edits": [list(e) for e in edits], "expect": expect})
POST_BLOCK = r"""  anchor="$(date -u +%s)"
  out anchor_epoch "$anchor"; out server_id "$sid"
  echo "target: server_id=${sid} name=${name} created=$(clean "$(jq -r '.servers[0].created // "unknown"' "$HBODY")")"
  echo "anchor_epoch=${anchor}"
  code="$(hapi POST "/servers/${sid}/actions/reboot" '{}')"
"""
WEB1_CHK = r"""  web1_sid="$(jq -r '.web1id' <<<"$ident")"
  [[ "$web1_sid" =~ ^[0-9]+$ ]] || fail "reboot: the Terraform state holds no numeric id for web-1, so the live id cannot be shown to differ from web-1's; nothing is rebooted"
  [[ "$web1_sid" != "$sid" ]] || fail "reboot: the server named ${name} carries the id the Terraform state holds for web-1; refusing to reboot the live origin; nothing is rebooted"
"""
STATE_CMP = r"""  [[ "$state_sid" =~ ^[0-9]+$ && "$state_sid" == "$sid" ]] || fail "reboot: the resolved id ${sid} differs from the id in the Terraform state (${state_shown}); nothing is rebooted"
"""
CHECK_201 = r"""  [[ "$code" == 201 ]] || post_failed "$code" "$anchor"
"""
OUT_LINE = r"""  out anchor_epoch "$anchor"; out server_id "$sid"
"""
NO_OUT_BLOCK = r"""  echo "target: server_id=${sid} name=${name} created=$(clean "$(jq -r '.servers[0].created // "unknown"' "$HBODY")")"
  echo "anchor_epoch=${anchor}"
  code="$(hapi POST "/servers/${sid}/actions/reboot" '{}')"
"""
SECOND_POST = """  hapi POST "/servers/${sid}/actions/reboot" '{}' >/dev/null
"""
PASS_OLD = r"""[[ "$v" != PASS ]] || block+="a probe row of the OK class, passing the grading helper's own device, mount and escrow test, was seen on a boot that began after the request, and no probe row after that boot began failed (row presence only)."$'\n'"""
PASS_NEW = r"""[[ "$v" != PASS ]] || block+="the volume is encrypted"$'\n'"""
# ---- Guard 1: the reboot target gate
m("G1.1 the web-1 id refusal is dropped", "r", R, ('[[ "$sid" != "$WEB1_SERVER_ID" ]] || fail', 'true || fail'))
m("G1.2 the typed-id comparison is dropped", "r", R, ('[[ "$sid" == "${confirm##*-}" ]] || fail', 'true || fail'))
m("G1.3 the Terraform-state id comparison is dropped", "r", R, ('[[ "$state_sid" =~ ^[0-9]+$ && "$state_sid" == "$sid" ]] || fail', 'true || fail'))
m("G1.4 the never-pooled requirement is dropped", "r", R, ('[[ "${NEVER_POOLED:-}" == absent ]] || fail', 'true || fail'))
m("G1.5 REORDER: the POST moves above the state-id comparison", "r", R, (STATE_CMP + WEB1_CHK + POST_BLOCK, POST_BLOCK + STATE_CMP + WEB1_CHK))
m("G1.5b REORDER: the POST moves above the web-1 state-id comparison", "r", R, (WEB1_CHK + POST_BLOCK, POST_BLOCK + WEB1_CHK))
m("G1.6 a SECOND POST site after the compliant first", "r", R, (CHECK_201, CHECK_201 + SECOND_POST))
m("G1.7 the guard's own dispatch: half the refusal scenarios are skipped (floor on refusal runs)", "suite", SUITE,
  ("""for h in web-1 web-3 "" "web-2 " WEB-2 "web-2;x" $'web-2\\nweb-1'; do\n    world; runr "reboot: host""", """for h in web-1; do\n    world; runr "reboot: host"""),
  ("""for c in "REBOOT-web-2-" "REBOOT-web-2-12x" "reboot-web-2-1" "REBOOT-web-1-123931471" "REBOOT-web-2-0123" "REBOOT-web-2-1234567890123" "REBOOT-web-2-1 " "" "REBOOT-web-2-$SID;id"; do\n    world; runr "reboot: confirm""", """for c in "REBOOT-web-2-"; do\n    world; runr "reboot: confirm"""),
  ("""for c in "" present unreadable "absent " ABSENT; do\n    world "never=$c"; runr""", """for c in ""; do\n    world "never=$c"; runr"""))
m("G1.8 the allow-list is widened in the script only", "r", R, ('    web-2) name="soleur-web-2" ;;', '    web-2|web-1) name="soleur-web-2" ;;'))
m("G1.9 the anchor is written after the POST instead of before", "r", R, (OUT_LINE + NO_OUT_BLOCK + CHECK_201, NO_OUT_BLOCK + CHECK_201 + OUT_LINE))
m("G1.h(a) harness: the curl shim records no write, so the one-write row must go red", "suite", SUITE, ('    echo "REBOOT ${path}" >> "$W/writes.log"\n', ''))
m("G1.10 a hostile state id is printed before its shape is checked", "r", R, ('  state_shown="absent or not numeric"; [[ "$state_sid" =~ ^[0-9]+$ ]] && state_shown="$state_sid"', '  state_shown="$state_sid"'))
m("G1.11 the wrong-state-object (web-1 in state) check is dropped", "r", R, ("""[[ "$(jq -r '.web1' <<<"$ident")" == 1 ]] || fail""", 'true || fail'))
m("G1.12 the server name equality in the lookup is dropped", "r", R, (""" && "$(jq -r '.servers[0].name' "$HBODY")" == "$name" ]]""", ' ]]'))
m("G1.13 the summary of a failed job reaches the accepted sentence", "r", R, ('    if [[ "$status" == success ]]; then\n      echo "The reboot request was accepted', '    if true; then\n      echo "The reboot request was accepted'))
m("G1.14 the footer is dropped from the reboot script's exit paths", "r", R, ("""[[ -n "$FOOTER_DONE" ]] || printf '%s\\n' "$FOOTER"; }""", ':; }'))
m("G1.15 the xtrace refusal is dropped", "r", R, ("""*x*) printf '[FATAL] refusing to trace: a Hetzner token and Terraform state are in scope\\n' >&2; printf '%s\\n' 'This run reports rows only. It makes no statement about the volume or its encryption; grading belongs to scripts/followthroughs/web2-luks-live-6931.sh.'; exit 78 ;;""", '*x*) : ;;'))
m("G1.16 the token requirement is dropped", "r", R, ('  need_token\n  # 2: the explicit', '  # 2: the explicit'))
m("G1.17 the action poll is cut to 2 attempts", "r", R, ('for _ in $(seq 1 24); do', 'for _ in $(seq 1 2); do'))
# ---- the POST boundary, the poll, the helpers and the summary (review round 1)
m("R.1 a definite 4xx no longer withdraws the anchor", "r", R, ('    out anchor_epoch ""\n', ''))
m("R.2 every non-201 answer withdraws the anchor (a 5xx or a transport error too)", "r", R, ('  if [[ "$code" =~ ^4[0-9][0-9]$ ]]; then', '  if true; then'))
m("R.2b the 4xx band is narrowed to 401-499 (a 400 keeps the anchor)", "r", R, ('  if [[ "$code" =~ ^4[0-9][0-9]$ ]]; then', '  if [[ "$code" =~ ^4(0[1-9]|[1-9][0-9])$ ]]; then'))
m("R.2c the 4xx band is widened to 3xx-4xx (a 301 or 307 withdraws the anchor)", "r", R, ('  if [[ "$code" =~ ^4[0-9][0-9]$ ]]; then', '  if [[ "$code" =~ ^[34][0-9][0-9]$ ]]; then'))
m("R.2d the 4xx band is cut to 400-428 (a 429 keeps the anchor)", "r", R, ('  if [[ "$code" =~ ^4[0-9][0-9]$ ]]; then', '  if [[ "$code" =~ ^4([01][0-9]|2[0-8])$ ]]; then'))
m("R.3 any 2xx is accepted as the POST answer", "r", R, (CHECK_201, '  [[ "$code" =~ ^2[0-9][0-9]$ ]] || post_failed "$code" "$anchor"\n'))
m("R.4 a non-JSON 201 body aborts under set -e instead of reaching the named failure", "r", R, ('"$HBODY" 2>/dev/null)" || action_id=""', '"$HBODY")"'))
m("R.5 a non-JSON poll body aborts under set -e", "r", R, ('2>/dev/null)" || st=unknown', ')"'))
m("R.6 one poll that is not HTTP 200 ends the loop", "r", R, ('    fi   # a poll that is not HTTP 200 is not an answer: retry, and the end is still unconfirmed', '    else break\n    fi'))
m("R.7 an action that ends in error no longer stops the polling", "r", R, ('      [[ "$st" == error ]] && break\n', '      :\n'))
m("R.8 the poll sleep is dropped", "r", R, ('    sleep "$ACTION_POLL_S"\n', ''))
m("R.9 the poll interval is no longer validated", "r", R, ('[[ "$ACTION_POLL_S" =~ ^[0-9]{1,3}$ ]] || ACTION_POLL_S=5', ':'))
m("R.10 the locale pin is dropped (a UTF-8 locale then reads non-ASCII digits as [0-9])", "r", R, ('\nexport LC_ALL=C\n', '\n'))
m("R.11 the confirm id bound is cut to 11 digits", "r", R, ('[1-9][0-9]{0,11}$ ]] || fail', '[1-9][0-9]{0,10}$ ]] || fail'))
m("R.12 the web-1 id the state holds is no longer compared with the live id", "r", R, ("""  [[ "$web1_sid" != "$sid" ]] || fail""", '  true || fail'))
m("R.12b a state without a numeric web-1 id no longer refuses (fail-open)", "r", R, ("""  [[ "$web1_sid" =~ ^[0-9]+$ ]] || fail""", '  true || fail'))
m("R.12c the numeric web-1 id gate is skipped for a non-numeric id instead of refused (the old fail-open form)", "r", R, ("""  [[ "$web1_sid" =~ ^[0-9]+$ ]] || fail "reboot: the Terraform state holds no numeric id for web-1, so the live id cannot be shown to differ from web-1's; nothing is rebooted"
  [[ "$web1_sid" != "$sid" ]] || fail""", """  [[ ! "$web1_sid" =~ ^[0-9]+$ || "$web1_sid" != "$sid" ]] || fail"""))
m("R.13 the state selector no longer pins mode, type and name (a decoy resource is picked)", "r", R, ('.resources[] | select(.mode == "managed" and .type == "hcloud_server" and .name == "web") | .instances[] | select(.index_key == $h)', '.resources[] | .instances[] | select(.index_key == $h)'))
m("R.14 the state selector drops string-typed ids", "r", R, ('select(.index_key == $h) | (.attributes.id | tostring)]', 'select(.index_key == $h) | (.attributes.id | numbers | tostring)]'))
m("R.15 terraform runs outside INFRA_DIR (the cd is dropped)", "r", R, ('(cd "$INFRA_DIR" && terraform state pull', '(terraform state pull'))
m("R.16 the token-shape check is dropped", "r", R, ("""  _bearer_ok "$HCLOUD_TOKEN" || fail "the infra-credentials loader exported an HCLOUD_TOKEN of an unusable shape; nothing is rebooted"\n""", ''))
m("R.17 the bearer goes back to a pipe", "static", R, ("""  code="$(curl --disable --noproxy '*' -sS --max-time 15 --config - -X "$1" "${extra[@]}" -o "$HBODY" -w '%{http_code}' "https://api.hetzner.cloud/v1$2" \\
    < <(printf 'header = "Authorization: Bearer %s"\\n' "$HCLOUD_TOKEN"))" || rc=$?""", """  code="$(printf 'header = "Authorization: Bearer %s"\\n' "$HCLOUD_TOKEN" | curl --disable --noproxy '*' -sS --max-time 15 --config - -X "$1" "${extra[@]}" -o "$HBODY" -w '%{http_code}' "https://api.hetzner.cloud/v1$2")" || rc=$?"""))
m("R.18 a cancelled job is summarised as nothing sent", "r", R, ('    elif [[ "$status" == cancelled ]]; then', '    elif false; then'))
m("R.19 the summary prints the reason as live markdown", "r", R, ('    echo "| reason | \\`${reason_shown}\\` |"', '    echo "| reason | ${reason_shown} |"'))
m("R.20 backticks in the reason are not neutralised", "r", R, ('; reason_shown="${reason_shown//\\`/$sq}"', ''))
m("R.21 the summary prints the footer twice", "r", R, ('  FOOTER_DONE=1\n}', '}'))
# ---- Guard 2: claim-free output
m("G2.1 a claim about the volume is added to the PASS path", "e", E, (PASS_OLD, PASS_NEW))
m("G2.2 PASS is reworded with a claim word", "e", E, ("""PASS) printf 'PASS (row presence only)' ;;""", """PASS) printf 'PASS (verified)' ;;"""))
m("G2.3 a claim word is added to the script (static scan)", "static", R, ('FOOTER_DONE=""\n', 'FOOTER_DONE=""\necho "the volume was verified"\n'))
m("G2.4 the footer is dropped from the NOT YET exit path only", "e", E, ('trap finish EXIT', """trap 'rc=$?; if [[ $rc == 2 ]]; then rm -rf "$tmp"; exit 2; fi; finish' EXIT"""))
m("G2.5 the raw probe row text is echoed", "e", E, ("""  jq -r 'if . == null then "baseline: readiness row none\"""", """  head -c 200 "$tmp/probe.jsonl"; jq -r 'if . == null then "baseline: readiness row none\""""))
m("G2.6 the guard's own dispatch: the dynamic scan runs over zero outputs", "suite", SUITE, ('  local name="$1" o="$2" kind="$3" err hits\n', '  return 0\n  local name="$1" o="$2" kind="$3" err hits\n'))
# ---- Guard 3: reader and writer stay separate
m("G3.1 the writer sources the rows helper", "static", R, ('FOOTER_DONE=""\n', 'FOOTER_DONE=""\nsource "$(dirname "$0")/lib/web2-luks-rows.sh"\n'))
m("G3.2 the reader carries a write verb", "static", E, ('now_epoch() { date -u +%s; }', 'now_epoch() { date -u +%s; }\nprobe_ping() { curl -X POST https://example.invalid; }'))
m("G3.3 the reader is removed from READERS (the new reader becomes unlisted)", "static", CENSUS, ('"scripts/web2-rebirth-ready-poll.sh",\n           "scripts/web-host-reboot-evidence.sh"}', '"scripts/web2-rebirth-ready-poll.sh"}'))
# ---- the verdict, the deadline and the wire
m("E.1 PASS no longer needs the boot to have begun after the request", "e", E, (' and any($after[]; .id == $probe.boot)\n', '\n'))
m("E.2 a FAIL row is no longer compared with the new boot's first row", "e", E, (' and ($probe.bf + $margin) < $earliest_after.first) then', ') then'))
m("E.3 the deadline is an iteration count", "e", E, ('if (( t >= deadline )); then', 'if (( iter >= 3 )); then'))
m("E.4 the format gate on journald boot ids is dropped", "e", E, (' and (.id | test("^[0-9a-f]{32}$")) and ((.id | length) == 32) and .n != null', ' and .n != null'))
m("E.4b the length gate on journald boot ids is dropped (a trailing newline passes the anchored test)", "e", E, (' and ((.id | length) == 32) and .n != null', ' and .n != null'))
m("E.4c the length gate on the readiness boot id is dropped (a trailing newline passes the anchored uuid test)", "e", E, (' {age: .age, boot: (bid | if (length == 36) then . else "unknown" end)} end)', ' {age: .age, boot: bid} end)'))
m("E.5 a junk readiness row counts as evidence", "e", E, ('select(.kind == "row" and (.f.host // "") == $host)', 'select(true)'))
m("E.6 a read fault no longer stops a verdict", "e", E, ('      elif $fault then res("NOT_YET"; "read_fault"; true; 5)\n', ''))
m("E.7 the clock is read after the queries", "e", E, ('    t="$(now_epoch)"\n', '    read_all\n    t="$(now_epoch)"\n'))
m("E.8 PASS no longer needs the probe row to be younger than the request", "e", E, (' and $probe.age < $since and $probe.boot != ""', ' and $probe.boot != ""'))
m("E.9 a silent new boot is never reported", "e", E, ('elif ($newest_after.newest > $silent) then', 'elif false then'))
m("E.10 the old boot's liveness test is inverted", "e", E, ('$before.newest < $since', '$before.newest > $since'))
m("E.11 a re-created instance is never noticed", "e", E, ('if ($ready != null and $ready.age < $since) then', 'if false then'))
m("E.12 the check that the helper defines every function the reader calls is dropped", "e", E, (' || ! declare -F w2l_fetch_ready >/dev/null', ''))
m("E.13 the credential check is dropped", "e", E, ('    [[ -n "${!v:-}" ]] || die3 "${v} is not injected. Nothing was read."', '    :'))
m("E.14 the xtrace refusal is dropped", "e", E, ("""*x*) printf '[FATAL] refusing to trace: Better Stack credentials are in scope\\n' >&2; printf '%s\\n' 'This run reports rows only. It makes no statement about the volume or its encryption; grading belongs to scripts/followthroughs/web2-luks-live-6931.sh.'; exit 78 ;;""", '*x*) : ;;'))
m("E.15 the 120 s margin on a FAIL row is dropped", "e", E, ('($probe.bf + $margin) < $earliest_after.first', '$probe.bf < $earliest_after.first'))
m("E.16 an unparseable probe age is ignored instead of a read fault", "e", E, ("""if [[ "$(jq -r '.fault' <<<"$r")" == true ]]; then""", 'if false; then'))
m("E.17 the dashes are no longer removed from the probe row's boot id", "e", E, (' | gsub("-"; "")', ''))
m("E.18 a future anchor is accepted", "e", E, ('  (( anchor <= now + 60 )) || die3', '  true || die3'))
m("E.19 the old boot's recency bound is dropped (a shutdown row then silence reads as a guest that ignored the request)", "e", E, (' and $before.newest <= $silent)', ')'))
m("E.20 the old boot's recency bound is exclusive at SILENT_S", "e", E, ('$before.newest <= $silent', '$before.newest < $silent'))
m("E.21 the too-old anchor check is dropped", "e", E, ('  (( now - anchor + window * 60 <= ANCHOR_MAX_S )) || die3', '  true || die3'))
m("E.22 the window no longer counts toward the anchor bound", "e", E, ('now - anchor + window * 60 <= ANCHOR_MAX_S', 'now - anchor <= ANCHOR_MAX_S'))
m("E.23 the 1 h margin on the anchor bound is dropped", "e", E, ('ANCHOR_MAX_S=$(( BOOT_LOOKBACK_H * 3600 - 3600 ))', 'ANCHOR_MAX_S=$(( BOOT_LOOKBACK_H * 3600 ))'))
m("E.24 the anchor accepts a leading zero", "e", E, ('=~ ^(0|[1-9][0-9]{0,9})$ ]] || die3', '=~ ^[0-9]{1,10}$ ]] || die3'))
m("E.25 the window accepts a leading zero", "e", E, ('=~ ^(0|[1-9][0-9]{0,3})$ ]] || die3', '=~ ^[0-9]{1,4}$ ]] || die3'))
m("E.26 the poll interval accepts zero and a leading zero", "e", E, ('=~ ^[1-9][0-9]{0,4}$ ]] || die3', '=~ ^[0-9]{1,5}$ ]] || die3'))
m("E.27 a re-created instance exits 2 again", "e", E, ('res("NOT_YET"; "instance_recreated_after_request"; false; 5)', 'res("NOT_YET"; "instance_recreated_after_request"; false; 2)'))
m("E.28 a read fault exits 2 again", "e", E, ('elif $fault then res("NOT_YET"; "read_fault"; true; 5)', 'elif $fault then res("NOT_YET"; "read_fault"; true; 2)'))
m("E.29 PASS no longer needs the grading helper's own green test", "e", E, ('(if ($c | row_green)', '(if true'))
m("E.30 an earlier failing row no longer blocks the PASS", "e", E, (' and ($probe.bf == null or $probe.bf >= $earliest_after.first) and ($probe.bn == null or $probe.bn >= $earliest_after.first)) then', ') then'))
m("E.31 a failing row exactly as old as the new boot's first row blocks the PASS", "e", E, ('$probe.bf >= $earliest_after.first', '$probe.bf > $earliest_after.first'))
m("E.32 a not-green row after the new boot is no longer a FAIL", "e", E, ('''      elif ($probe != null and $probe.bn != null and ($probe.bn + $margin) < $earliest_after.first) then
        res("FAIL"; "probe_row_not_green_after_new_boot"; false; 1)
''', ''))
m("E.33 the margin on a not-green row is dropped", "e", E, ('($probe.bn + $margin) < $earliest_after.first', '$probe.bn < $earliest_after.first'))
m("E.34 the length gate on the probe row's boot id is dropped", "e", E, ('(test("^[0-9a-f]{32}$") and (length == 32))', 'test("^[0-9a-f]{32}$")'))
m("E.35 an unreadable boot age is no longer dropped (both guards)", "e", E, (' and .n != null and .first != null and .newest != null))', '))'), ('($boots.boots | map(select(.first != null and .newest != null))) as $bs', '$boots.boots as $bs'))
m("E.36 the boots query loses its host filter", "e", E, ("  AND JSONExtractString(raw,'host_name') = '${W2L_HOST_NAME}'\n  AND JSONExtractString(raw,'_BOOT_ID') != ''", "  AND JSONExtractString(raw,'_BOOT_ID') != ''"))
m("E.37 the boots lookback is stretched", "e", E, ('WHERE dt > now() - INTERVAL ${BOOT_LOOKBACK_H} HOUR', 'WHERE dt > now() - INTERVAL 480000 HOUR'))
m("E.38 the readiness read asks for one row over one day", "e", E, ('w2l_fetch_ready "$f" 90 20', 'w2l_fetch_ready "$f" 1 1'))
m("E.39 the probe read asks for one row", "e", E, ('PROBE_LIMIT=50\n', 'PROBE_LIMIT=1\n'))
m("E.40 only one boot after the request is listed", "e", E, ('($a | .[:5][] |', '($a | .[:1][] |'))
m("E.41 the youngest old boot no longer decides (the oldest does)", "e", E, ('($bs | map(select(.first >= $since)) | .[0]) as $before', '($bs | map(select(.first >= $since)) | .[-1]) as $before'))
m("E.42 the earliest new boot decides liveness", "e", E, ('| ($after | .[0]) as $newest_after', '| ($after | .[-1]) as $newest_after'))
m("E.43 PASS joins the probe row to the youngest new boot only", "e", E, ('any($after[]; .id == $probe.boot)', '($after[0].id == $probe.boot)'))
m("E.44 the boot list is sorted oldest-first", "e", E, ('boots: ($ok | sort_by(.first))', 'boots: ($ok | sort_by(-.first))'))
m("E.45 the FAIL margin is widened to 190 s", "e", E, ('FAIL_MARGIN_S=120 ', 'FAIL_MARGIN_S=190 '))
m("E.46 the silence bound is widened to 880 s", "e", E, ('SILENT_S=600 ', 'SILENT_S=880 '))
m("E.47 a future anchor is tolerated for a day", "e", E, ('  (( anchor <= now + 60 )) || die3', '  (( anchor <= now + 86400 )) || die3'))
m("E.48 the exit code is no longer printed for exit 5", "e", E, ('[[ "$rc" == 4 || "$rc" == 5 ]]', '[[ "$rc" == 4 ]]'))
# ---- the harness's own instruments (T1): graded through the suite kind (a rerun of this file without the battery)
m("H.1 srow is neutered", "suite", SUITE, ('  STATIC=$((STATIC + 1)); if [[ "$2" -ne 0 ]]; then printf \'FAILED %s\\n\' "$1"; fails=$((fails + 1)); fi', '  STATIC=$((STATIC + 1)); if false; then printf \'FAILED %s\\n\' "$1"; fails=$((fails + 1)); fi'))
m("H.2 runr's exit-code compare is neutered", "suite", SUITE, ('''  if [[ "$rc" -ne "$want" ]]; then printf 'FAILED %s (rc=%s want=%s) %s\\n' "$name" "$rc" "$want" "${o:0:240}${e:0:160}"; return; fi''', '''  if false; then printf 'FAILED %s (rc=%s want=%s) %s\\n' "$name" "$rc" "$want" "${o:0:240}${e:0:160}"; return; fi'''))
m("H.3 runr's substring check is neutered", "suite", SUITE, ('''  if [[ "$sub" != "-" && "$o$e" != *"$sub"* ]]; then printf 'FAILED %s (output lacks %q) %s\\n' "$name" "$sub" "${o:0:240}"; fi
}
writes()''', '''  :
}
writes()'''))
m("H.4 rune's substring check is neutered", "suite", SUITE, ('''  if [[ "$sub" != "-" && "$o$e" != *"$sub"* ]]; then printf 'FAILED %s (output lacks %q) %s\\n' "$name" "$sub" "${o:0:300}"; fi''', '  :'))
m("H.5 want_nothing_written is neutered", "suite", SUITE, ('want_nothing_written() { # <name>\n', 'want_nothing_written() { # <name>\n  return 0\n'))
m("H.6 want_no_api_call is neutered", "suite", SUITE, ('want_no_api_call() { check "$1: no Hetzner call was made" "$([[ ! -s "$W/calls.log" ]]; echo $?)"; }\n', 'want_no_api_call() { return 0; }\n'))
m("H.7 no_verdict_misreads is neutered", "suite", SUITE, ('no_verdict_misreads() { check "$1: the verdict line is unique" "$([[ "$(printf \'%s\\n\' "$LASTOUT" | grep -c \'^verdict: \')" == 1 ]]; echo $?)"; }\n', 'no_verdict_misreads() { return 0; }\n'))
m("H.8 check is neutered", "suite", SUITE, ('  if [[ "$2" -ne 0 ]]; then printf \'FAILED %s\\n\' "$1"; fi\n}\ncond()', '  :\n}\ncond()'))
m("H.9 the denylist loses a token", "suite", SUITE, ("DENY_RE='(^|[^a-z0-9])(luks-backed|encrypted|reborn|reopen|proof|verified|confirmed|proves|crypto_luks|/dev/mapper|luks=1|escrow=ok)($|[^a-z0-9])'\n", "DENY_RE='(^|[^a-z0-9])(luks-backed|encrypted|reborn|proof|verified|confirmed|proves|crypto_luks|/dev/mapper|luks=1|escrow=ok)($|[^a-z0-9])'\n"))
m("H.10 the grader counts every edit as a kill", "suite", SUITE, ('[[ "$after" =~ ^[0-9]+$ && "$after" -gt 0 ]] && verdict=killed\n', '[[ "$after" =~ ^[0-9]+$ && "$after" -ge 0 ]] && verdict=killed\n'))
m("H.11 the grader treats a killed canary as fine", "suite", SUITE, ('kill:killed|survive:survived) echo "ok ${verdict}" ;; *) echo "FAIL ${verdict}" ;; esac\n', 'kill:killed|survive:survived|survive:killed) echo "ok ${verdict}" ;; *) echo "FAIL ${verdict}" ;; esac\n'))
m("F.1 the evidence script's inline xtrace footer drifts from the constant", "suite", ESCR, ("'This run reports rows only. It makes no statement about the volume or its encryption; grading belongs to scripts/followthroughs/web2-luks-live-6931.sh.'; exit 78", "'This run reports rows alone. It makes no statement about the volume or its encryption; grading belongs to scripts/followthroughs/web2-luks-live-6931.sh.'; exit 78"))
m("F.2 the writer's inline xtrace footer drifts from the constant", "suite", R, ("'This run reports rows only. It makes no statement about the volume or its encryption; grading belongs to scripts/followthroughs/web2-luks-live-6931.sh.'; exit 78", "'This run reports rows alone. It makes no statement about the volume or its encryption; grading belongs to scripts/followthroughs/web2-luks-live-6931.sh.'; exit 78"))
m("P.1 the reader's GRADE_HINT drifts from the writer's GRADE_CMD", "suite", E, ("GRADE_HINT='bash scripts/web-host-reboot-evidence.sh grade'", "GRADE_HINT='bash scripts/web-host-reboot-evidence.sh regrade'"))
m("P.2 the workflow suite's DENY_RE copy loses a token", "suite", WFSUITE, ("DENY_RE = re.compile(r'(^|[^a-z0-9])(luks-backed|encrypted|reborn|reopen|", "DENY_RE = re.compile(r'(^|[^a-z0-9])(luks-backed|encrypted|reborn|"))
m("P.3 the writer's out() drifts from the reader's", "suite", R, ("""v="${v//$'\\n'/ }"; [[ -z "${GITHUB_OUTPUT:-}" ]]""", """[[ -z "${GITHUB_OUTPUT:-}" ]]"""))
m("CANARY a comment-only edit must be graded SURVIVED (the grader can report a survivor)", "r", R, ("# --- constants. The allow-list is a case arm below", "# --- constants (canary edit). The allow-list is a case arm below"), expect="survive")
for i, e in enumerate(M, 1):
    json.dump(e, open(os.path.join(d, "%03d.json" % i), "w"))
PY

mk_sandbox() { # <dir>
  local d="$1" f
  assert_fixture_dir "$d"; assert_fixture_dir "$DIR"; assert_fixture_dir "$RSCRIPT"; assert_fixture_dir "$ESCRIPT"
  mkdir -p "$d/scripts" "$d/apps/web-platform/infra"
  cp -r "$ROOT/scripts/lib" "$d/scripts/"
  cp "$ROOT/scripts/betterstack-query.sh" "$RSCRIPT" "$ESCRIPT" "$DIR/web-host-reboot.test.sh" "$d/scripts/"
  for f in web2-rebirth.sh web2-rebirth-never-pooled.sh; do [[ -f "$ROOT/scripts/$f" ]] && cp "$ROOT/scripts/$f" "$d/scripts/"; done
  cp "$ROOT/apps/web-platform/infra/workspaces-luks-verify-workflow.test.sh" "$ROOT/apps/web-platform/infra/web-host-reboot-workflow.test.sh" "$d/apps/web-platform/infra/"
  mkdir -p "$d/knowledge-base/engineering/operations/runbooks"; cp "$ROOT/knowledge-base/engineering/operations/runbooks/web-host-reboot.md" "$d/knowledge-base/engineering/operations/runbooks/"
}
static_red() { # <sandbox> -> the number of static conditions that are red in it
  local sb="$1" n=0 f
  for f in web-host-reboot.sh web-host-reboot-evidence.sh; do [[ -z "$(noncomment "$sb/scripts/$f" | deny_hits)" ]] || n=$((n + 1)); done
  [[ "$(grep -v '^[[:space:]]*#' "$sb/scripts/web-host-reboot.sh" | grep -ciE -e "$CENSUS_KEY")" == 0 ]] || n=$((n + 1))
  [[ "$(grep -v '^[[:space:]]*#' "$sb/scripts/web-host-reboot-evidence.sh" | grep -ciE -e "$CENSUS_VERB")" == 0 ]] || n=$((n + 1))
  [[ "$(grep -v '^[[:space:]]*#' "$sb/scripts/web-host-reboot-evidence.sh" | grep -cE '\bPOST\b')" == 0 ]] || n=$((n + 1))
  [[ "$(grep -c '"scripts/web-host-reboot-evidence.sh"' "$sb/apps/web-platform/infra/workspaces-luks-verify-workflow.test.sh")" -ge 1 ]] || n=$((n + 1))
  bearer_psub_ok "$sb/scripts/web-host-reboot.sh" || n=$((n + 1))
  bearer_guard_ok "$sb/scripts/web-host-reboot.sh" || n=$((n + 1))
  echo "$n"
}
red_count() { # <kind> <sandbox>
  local kind="$1" sb="$2" o rc=0
  case "$kind" in
    r) battery_reboot "$sb/scripts/web-host-reboot.sh" 2>&1 | grep -c '^FAILED' ;;
    e) battery_evidence "$sb/scripts/web-host-reboot-evidence.sh" 2>&1 | grep -c '^FAILED' ;;
    static) static_red "$sb" ;;
    suite) o="$(WHR_NO_MUTATE=1 bash "$sb/scripts/web-host-reboot.test.sh" 2>&1)" || rc=$?; if [[ "$rc" -ne 0 ]]; then grep -c '^FAILED' <<<"$o" || true; else echo 0; fi ;;
  esac
}
# CONTROL FIRST: each battery kind over an unmutated sandbox must be green, or a kill below would mean nothing.
for kind in r e static suite; do
  ( mk_sandbox "$MUT_DIR/sb/control.$kind"; n="$(red_count "$kind" "$MUT_DIR/sb/control.$kind")"; printf '%s' "$n" > "$MUT_DIR/res/control.$kind" ) &
done
wait
for kind in r e static suite; do
  n="$(cat "$MUT_DIR/res/control.$kind" 2>/dev/null || echo missing)"
  if [[ "$n" == 0 ]]; then echo "  ok   control: the unmutated ${kind} sandbox is green"; else echo "  FAIL control: the unmutated ${kind} sandbox has ${n} red rows (a kill would prove nothing)"; fails=$((fails + 1)); fi
done

_mutant_run() { # <idx> <def.json>
  local idx="$1" def="$2" name kind target sb after expect res
  name="$(jq -r '.name' "$def")"; kind="$(jq -r '.kind' "$def")"; target="$(jq -r '.target' "$def")"; expect="$(jq -r '.expect // "kill"' "$def")"
  sb="$MUT_DIR/sb/m.$idx"; mk_sandbox "$sb"
  cp -p "$sb/$target" "$sb/$target.pristine"
  if ! python3 - "$sb/$target" "$def" <<'PY'
import json, sys
p, d = sys.argv[1:3]
s = open(p).read()
for old, new in json.load(open(d))["edits"]:
    if s.count(old) != 1:
        sys.exit(1)
    s = s.replace(old, new)
open(p, "w").write(s)
PY
  then echo "  FAIL mutation '${name}': the edit did not land exactly once" > "$MUT_DIR/res/$idx"; return; fi
  if cmp -s "$sb/$target" "$sb/$target.pristine"; then echo "  FAIL mutation '${name}': the edit changed nothing" > "$MUT_DIR/res/$idx"; return; fi
  case "$target" in *.sh) bash -n "$sb/$target" 2>/dev/null || { echo "  FAIL mutation '${name}': a DEAD mutant (it no longer parses), which would score as a kill" > "$MUT_DIR/res/$idx"; return; } ;; esac
  after="$(red_count "$kind" "$sb")"
  res="$(mutant_outcome "$expect" "$after")"
  case "$res" in
    "ok killed") echo "  ok   mutation killed: ${name} (${after} rows red)" > "$MUT_DIR/res/$idx" ;;
    "ok survived") echo "  ok   canary survived as expected (a no-op edit is reported as a survivor): ${name}" > "$MUT_DIR/res/$idx" ;;
    "FAIL survived") echo "  FAIL mutation SURVIVED: ${name}" > "$MUT_DIR/res/$idx" ;;
    *) echo "  FAIL the known-survivor canary was KILLED (${after} rows red): the grader cannot report a survivor: ${name}" > "$MUT_DIR/res/$idx" ;;
  esac
  rm -rf "$sb"
}
for def in "$MUT_DIR"/defs/*.json; do
  MUT_SEQ=$((MUT_SEQ + 1))
  while [[ "$(jobs -rp | wc -l | tr -d ' ')" -ge "$MUT_JOBS" ]]; do sleep 0.3; done
  _mutant_run "$(basename "$def" .json)" "$def" &
done
wait
for f in "$MUT_DIR"/res/[0-9]*; do cat "$f"; grep -q '^  FAIL' "$f" && fails=$((fails + 1)); done
n_res="$(find "$MUT_DIR/res" -type f -name '[0-9]*' | wc -l | tr -d ' ')"
[[ "$n_res" -eq "$MUT_SEQ" ]] || { echo "  FAIL a mutant did not report ($n_res of ${MUT_SEQ})"; fails=$((fails + 1)); }
# The floor is reported by a direct printf and exit (not through a helper), so a mutant of the guard itself can be built.
MUT_FLOOR=121
if [[ "$MUT_SEQ" -lt "$MUT_FLOOR" ]]; then
  printf '  FAIL mutant floor: only %s mutants ran (floor %s)\n' "$MUT_SEQ" "$MUT_FLOOR"
  exit 1
fi
printf 'mutants: %s ran (floor %s)\n' "$MUT_SEQ" "$MUT_FLOOR"
# The pristine files are untouched: the real subjects, the helper and the rebirth script hash the same as at the start.
SUM_AFTER="$(cd "$ROOT" && sha256sum scripts/web-host-reboot.sh scripts/web-host-reboot-evidence.sh scripts/lib/web2-luks-rows.sh scripts/betterstack-query.sh scripts/web2-rebirth.sh 2>/dev/null | sort)"
if [[ "$SUM_BEFORE" == "$SUM_AFTER" ]]; then echo "  ok   the real files hash the same before and after the battery"; else echo "  FAIL a real file changed during the battery"; fails=$((fails + 1)); fi
# MUTATION_SECTION_END

# Static rows print their own FAILED lines; recount everything printed by this run.
[[ "$fails" -eq 0 ]] && { echo "web-host-reboot: all scenarios and mutations passed"; exit 0; }
echo "web-host-reboot: ${fails} FAILED"; exit 1
