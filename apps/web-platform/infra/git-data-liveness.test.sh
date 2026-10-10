#!/usr/bin/env bash
# git-data-liveness.test.sh — Guard 1 for #9438: the git-data HOST pings its own dedicated
# Better Stack heartbeat if and only if every gating local health check passes and a validated URL
# is available, and whenever it withholds it records which check failed.
#
# Three arms:
#   BEHAVIOURAL — the REAL script runs against a scratch PATH of fakes (mountpoint, findmnt, df,
#                 systemctl, curl, doppler, git-data-emit) and a real loopback listener for the
#                 sshd banner. Every fake records its argv, so "the URL is on no argument list"
#                 and "the ping happened" are observations, not inferences.
#   STATIC      — the script, the unit pair, the cloud-init delivery, the module binding and the
#                 Terraform pair, each asserted on comment-stripped text anchored on syntax.
#   MUTATION    — each Guard Contract row is a sed edit of a COPY that must turn a predicate RED,
#                 after the unmutated control held and after the edit was proved to have landed.
#
# Run: bash apps/web-platform/infra/git-data-liveness.test.sh
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$DIR/git-data-liveness.sh"
UNIT="$DIR/git-data-liveness.service"
TIMER="$DIR/git-data-liveness.timer"
CLOUD_INIT="$DIR/cloud-init-git-data.yml"
MODULE_MAIN="$DIR/modules/git-data-userdata/main.tf"
BUDGET="$DIR/git-data-userdata-budget.sh"
GIT_DATA_TF="$DIR/git-data.tf"
LUKS_TEST="$DIR/git-data-luks.test.sh"

passes=0
fails=0
pass() { passes=$((passes + 1)); }
fail() { fails=$((fails + 1)); echo "FAIL: $1" >&2; [ -n "${2:-}" ] && echo "      $2" >&2; }
cases=0
ok() { cases=$((cases + 1)); if [ "$1" -eq 0 ]; then pass; else fail "$2" "${3:-}"; fi; }

for f in "$SCRIPT" "$UNIT" "$TIMER" "$CLOUD_INIT" "$MODULE_MAIN" "$BUDGET" "$GIT_DATA_TF" "$LUKS_TEST"; do
  [ -f "$f" ] || { echo "FAIL: missing $f" >&2; exit 1; }
done
command -v python3 >/dev/null 2>&1 || { echo "FAIL: python3 is required for the loopback banner listeners" >&2; exit 1; }
REAL_SLEEP="$(command -v sleep)"

SCRATCH="$(mktemp -d -t gdliveness.XXXXXXXX)"
# The canonical operand guard, byte-identical to plugins/soleur/test/test-helpers.sh
# (fixture-dir-operand-assert.test.sh compares them and reds on drift).
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
assert_fixture_dir "$SCRATCH"
SRV_PIDS=""
cleanup() {
  assert_fixture_dir "$SCRATCH"
  [ -z "$SRV_PIDS" ] || kill $SRV_PIDS 2>/dev/null
  rm -rf "$SCRATCH"
}
trap cleanup EXIT

strip() { grep -vE '^[[:space:]]*#([^!]|$)' "$1"; }

# --- loopback banner listeners (a real socket: the feeder reads /dev/tcp, not a fake) -----------
cat > "$SCRATCH/srv.py" <<'PY'
import socketserver, sys, time
banner = sys.argv[2].encode().decode('unicode_escape').encode()
class H(socketserver.BaseRequestHandler):
    def handle(self):
        if banner:
            self.request.sendall(banner)
        else:
            time.sleep(30)
class S(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True
s = S(('127.0.0.1', 0), H)
open(sys.argv[1], 'w').write(str(s.server_address[1]))
s.serve_forever()
PY
python3 -I "$SCRATCH/srv.py" "$SCRATCH/port.good" 'SSH-2.0-OpenSSH_9.6\r\n' >/dev/null 2>&1 &
SRV_PIDS="$!"
python3 -I "$SCRATCH/srv.py" "$SCRATCH/port.bad" 'HTTP/1.1 400 Bad Request\r\n' >/dev/null 2>&1 &
SRV_PIDS="$SRV_PIDS $!"
python3 -I "$SCRATCH/srv.py" "$SCRATCH/port.silent" '' >/dev/null 2>&1 &
SRV_PIDS="$SRV_PIDS $!"
_w=0
while [ ! -s "$SCRATCH/port.good" ] || [ ! -s "$SCRATCH/port.bad" ] || [ ! -s "$SCRATCH/port.silent" ]; do
  _w=$((_w + 1)); [ "$_w" -lt 100 ] || { echo "FAIL: banner listeners did not start" >&2; exit 1; }
  "$REAL_SLEEP" 0.1
done
GOOD_PORT="$(cat "$SCRATCH/port.good")"
BAD_PORT="$(cat "$SCRATCH/port.bad")"
SILENT_PORT="$(cat "$SCRATCH/port.silent")"
CLOSED_PORT="$(python3 -I -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')"

# --- the fakes -----------------------------------------------------------------------------------
FAKES="$SCRATCH/fakes"
mkdir -p "$FAKES"
# mountpoint(1): exit 0 mounted, 32 an existing directory that is NOT a mountpoint, 1 an error (a
# missing path). An operand other than the store root is a refusal the suite asserts never happens.
cat > "$FAKES/mountpoint" <<'EOS'
#!/bin/bash
[ "${*: -1}" = "$GDL_FX/store" ] || { echo "mountpoint $*" >> "$GDL_FX/fake.refused"; exit 97; }
exit "$(cat "$GDL_FX/mp_rc" 2>/dev/null || echo 0)"
EOS
cat > "$FAKES/findmnt" <<'EOS'
#!/bin/bash
[ "${*: -1}" = "$GDL_FX/store" ] || { echo "findmnt $*" >> "$GDL_FX/fake.refused"; exit 97; }
[ ! -e "$GDL_FX/findmnt_rc" ] || exit "$(cat "$GDL_FX/findmnt_rc")"
opts=rw,relatime; [ ! -e "$GDL_FX/findmnt_opts" ] || opts="$(cat "$GDL_FX/findmnt_opts")"
if [ -e "$GDL_FX/findmnt_out" ]; then src="$(cat "$GDL_FX/findmnt_out")"; else src=/dev/mapper/git-data; fi
[ -z "$src" ] || while IFS= read -r l; do printf '%s %s\n' "$l" "$opts"; done <<<"$src"
EOS
cat > "$FAKES/df" <<'EOS'
#!/bin/bash
[ ! -e "$GDL_FX/df_broken" ] || exit 1
[ ! -e "$GDL_FX/df_hang" ] || exec "$GDL_REAL_SLEEP" "$(cat "$GDL_FX/df_hang")"
field="" path=""
for a in "$@"; do
  case "$a" in --output=*) field="${a#--output=}" ;; *) path="$a" ;; esac
done
case "$path" in */store) where=store ;; *) where=root ;; esac
f="$GDL_FX/df_${field}_${where}"
if [ -e "$f" ]; then v="$(cat "$f")"
else case "$field/$where" in pcent/root) v=20 ;; *) v=1 ;; esac; fi
[ "$v" != unreadable ] || exit 0
printf 'Use%%\n %s%%\n' "$v"
EOS
# systemctl show -p LoadState -p ActiveState <unit>: a unit that does not exist prints
# LoadState=not-found with ActiveState=inactive and exits 0 (measured), which is why the script
# reads the load state too.
cat > "$FAKES/systemctl" <<'EOS'
#!/bin/bash
[ ! -e "$GDL_FX/systemctl_rc" ] || exit "$(cat "$GDL_FX/systemctl_rc")"
unit="${*: -1}"; unit="${unit%.service}"
case "$unit" in git-data-luks-reopen|git-data-nftables|ssh) : ;; *) echo "systemctl $*" >> "$GDL_FX/fake.refused"; exit 97 ;; esac
f="$GDL_FX/unit_$unit"
if [ -e "$f" ]; then v="$(cat "$f")"; else v=active; fi
[ "$v" != unreadable ] || exit 1
if [ "$v" = not-found ]; then printf 'LoadState=not-found\nActiveState=inactive\n'; exit 0; fi
printf 'LoadState=loaded\nActiveState=%s\n' "$v"
EOS
cat > "$FAKES/find" <<'EOS'
#!/bin/bash
[ "$1" = "$GDL_FX/store" ] || exec /usr/bin/find "$@"
[ "$*" = "$GDL_FX/store -maxdepth 1 -mindepth 1 -print -quit" ] || { echo "find $*" >> "$GDL_FX/fake.refused"; exit 97; }
[ ! -e "$GDL_FX/find_rc" ] || exit "$(cat "$GDL_FX/find_rc")"
exec /usr/bin/find "$@"
EOS
cat > "$FAKES/curl" <<'EOS'
#!/bin/bash
{ printf 'CALL'; for a in "$@"; do printf ' %s' "$a"; done; echo; } >> "$GDL_FX/curl.calls"
for a in "$@"; do
  if [ "$a" = "--config" ]; then cat >> "$GDL_FX/curl.stdin"; echo >> "$GDL_FX/curl.stdin"; break; fi
done
if [ -s "$GDL_FX/curl_seq" ]; then
  rc="$(awk '{print $1}' "$GDL_FX/curl_seq")"
  tail="$(awk '{$1=""; sub(/^ /,""); print}' "$GDL_FX/curl_seq")"
  printf '%s\n' "$tail" > "$GDL_FX/curl_seq"
  exit "$rc"
fi
exit "$(cat "$GDL_FX/curl_rc" 2>/dev/null || echo 0)"
EOS
cat > "$FAKES/doppler" <<'EOS'
#!/bin/bash
printf '%s\n' "$*" >> "$GDL_FX/doppler.calls"
[ ! -e "$GDL_FX/doppler_hang" ] || exec "$GDL_REAL_SLEEP" "$(cat "$GDL_FX/doppler_hang")"
rc="$(cat "$GDL_FX/doppler_rc" 2>/dev/null || echo 0)"
[ "$rc" -eq 0 ] || exit "$rc"
while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do shift; done
shift
if [ -e "$GDL_FX/secret" ]; then export GIT_DATA_HOST_HEARTBEAT_URL; GIT_DATA_HOST_HEARTBEAT_URL="$(cat "$GDL_FX/secret")"; fi
exec "$@"
EOS
cat > "$FAKES/git-data-emit" <<'EOS'
#!/bin/bash
{ for a in "$@"; do printf '%s|' "$a"; done; echo; } >> "$GDL_FX/emit.calls"
[ ! -e "$GDL_FX/emit_hang" ] || exec "$GDL_REAL_SLEEP" "$(cat "$GDL_FX/emit_hang")"
exit "$(cat "$GDL_FX/emit_rc" 2>/dev/null || echo 0)"
EOS
cat > "$FAKES/sleep" <<'EOS'
#!/bin/bash
exit 0
EOS
chmod +x "$FAKES"/*

GOOD_URL="https://uptime.betterstack.com/api/v1/heartbeat/SyntheticLivenessToken0123"
FX=""
RC=0
ELAPSED=0
CFG=""
NOW_T=1000000
SUT="$SCRIPT"

new_fixture() {  # <name>
  FX="$SCRATCH/fx.$1"
  assert_fixture_dir "$FX"
  rm -rf "$FX"
  mkdir -p "$FX/bin" "$FX/run" "$FX/store"
  cp "$FAKES"/* "$FX/bin/"
  printf '%s' "$GOOD_URL" > "$FX/secret"
  CFG=prd_git_data
  NOW_T=1000000
}

run_feeder() {  # [VAR=value ...] — sets RC, ELAPSED; output in $FX/out
  assert_fixture_dir "$FX"
  local t0 t1
  t0=$(date +%s)
  RC=0
  env -i HOME="$FX" PATH=/usr/bin:/bin GDL_FX="$FX" GDL_REAL_SLEEP="$REAL_SLEEP" \
    GIT_DATA_LIVENESS_PATH_PREPEND="$FX/bin" GIT_DATA_LIVENESS_RUN="$FX/run" \
    GIT_DATA_LIVENESS_EMIT="$FX/bin/git-data-emit" GIT_DATA_LIVENESS_ROOT="$FX/store" \
    GIT_DATA_LIVENESS_SSH_PORT="$GOOD_PORT" GIT_DATA_DOPPLER_CONFIG="$CFG" \
    GIT_DATA_LIVENESS_NOW="$NOW_T" "$@" bash "$SUT" > "$FX/out" 2>&1 || RC=$?
  t1=$(date +%s)
  ELAPSED=$((t1 - t0))
}

lines() { if [ -e "$FX/$1" ]; then wc -l < "$FX/$1" | tr -d ' '; else echo 0; fi; }
pings() { lines curl.calls; }
emits() { lines emit.calls; }
last_emit() { tail -n 1 "$FX/emit.calls" 2>/dev/null; }

# =====================================================================================
# BEHAVIOURAL
# =====================================================================================
new_fixture t1; run_feeder
ok "$((RC != 0))" "T1 a healthy tick exits 0 (rc=$RC)"
ok "$(( $(pings) != 1 ))" "T1 a healthy tick sends exactly one ping (got $(pings))"
ok "$(grep -qF "url = \"$GOOD_URL\"" "$FX/curl.stdin"; echo $?)" "T1 the URL travelled on curl's stdin config"
ok "$([ ! -e "$FX/fake.refused" ]; echo $?)" "T1 every fake was called with the operand it models (store root, unit name): none refused"
ok "$(grep -qF 'SOLEUR_GIT_DATA_LIVENESS ok|liveness|info|' <<<"$(last_emit)"; echo $?)" "T1 the first healthy tick emits a liveness info event"
ok "$(grep -qE 'state=ok\|code=ok\|root_pct=20\|config=prd_git_data\|$' <<<"$(last_emit)"; echo $?)" "T1 the event carries state, code, root_pct and config"

# T2: the URL is on no argument list and in no emitted line (ADR-280), with a recorder proof.
argv_absent_row() {
  [ "$(pings)" -ge 1 ] || return 1
  ! grep -qF "$GOOD_URL" "$FX/curl.calls" || return 1
  ! grep -qF "SyntheticLivenessToken0123" "$FX/curl.calls" "$FX/doppler.calls" "$FX/emit.calls" "$FX/out" || return 1
  grep -qF -- '--config -' "$FX/curl.calls"
}
new_fixture t2; run_feeder
ok "$(argv_absent_row; echo $?)" "T2 the URL is on no curl or doppler argv, in no emitted line, and not in the output"
ok "$(grep -qE 'CALL --disable --noproxy \* -fsS -m 10 -o /dev/null --config -$' "$FX/curl.calls"; echo $?)" "T2 curl carries --disable first, --noproxy, -fsS, -m 10 and a stdin config"
ok "$(! grep -qE -- '--retry|[[:space:]]-k([[:space:]]|$)|--insecure' "$FX/curl.calls"; echo $?)" "T2 curl uses no --retry and no -k"
ok "$([ "$(stat -c %a "$FX/run" 2>/dev/null)" = 700 ]; echo $?)" "T2 the run dir is mode 0700"
ok "$([ "$(stat -c %a "$FX/run/url" 2>/dev/null)" = 600 ]; echo $?)" "T2 the URL cache is mode 0600"
ok "$(grep -qF -- '--project soleur --config prd_git_data --only-secrets GIT_DATA_HOST_HEARTBEAT_URL --no-fallback --' "$FX/doppler.calls"; echo $?)" "T2 doppler is called with the scoped config, one secret and no fallback cache"
ok "$(grep -qF -- '/usr/bin/env -u GIT_DATA_LIVENESS_PATH_PREPEND -u GIT_DATA_LIVENESS_EMIT -u GIT_DATA_LIVENESS_ROOT' "$FX/doppler.calls"; echo $?)" "T2 the Doppler child runs with the test seams stripped (only the run dir survives)"

# T3: the gating checks. Each negative is paired with the healthy positive control above.
new_fixture t3a; run_feeder GIT_DATA_LIVENESS_SSH_PORT="$CLOSED_PORT"
ok "$(( $(pings) != 0 ))" "T3a a closed sshd port withholds the ping"
ok "$(grep -qF 'code=ssh_no_banner' <<<"$(last_emit)"; echo $?)" "T3a …and the event names ssh_no_banner"
new_fixture t3b; run_feeder GIT_DATA_LIVENESS_SSH_PORT="$BAD_PORT"
ok "$(( $(pings) != 0 ))" "T3b a listener that answers without an SSH- banner withholds the ping"
ok "$(grep -qF 'code=ssh_no_banner' <<<"$(last_emit)"; echo $?)" "T3b …and names ssh_no_banner"
new_fixture t3c; echo 32 > "$FX/mp_rc"; run_feeder
ok "$(( $(pings) != 0 ))" "T3c an unmounted store withholds the ping"
ok "$(grep -qF 'code=store_unmounted' <<<"$(last_emit)"; echo $?)" "T3c …and names store_unmounted"
ok "$(grep -qE 'code=store_unmounted\|' <<<"$(last_emit)" ; echo $?)" "T3c …and ONLY store_unmounted (the dependent store checks are skipped)"
new_fixture t3d; echo 2 > "$FX/mp_rc"; run_feeder
ok "$(( $(pings) != 0 ))" "T3d an unreadable mountpoint check withholds the ping"
ok "$(grep -qF 'code=unmeasured:mountpoint' <<<"$(last_emit)"; echo $?)" "T3d …and names unmeasured:mountpoint"
new_fixture t3d1; echo 1 > "$FX/mp_rc"; run_feeder
ok "$(grep -qF 'code=unmeasured:mountpoint' <<<"$(last_emit)"; echo $?)" "T3d mountpoint rc 1 (an error such as a missing path) is an unreadable instrument, NOT store_unmounted (rc 32)"
new_fixture t3r1; echo ro,relatime > "$FX/findmnt_opts"; run_feeder
ok "$(( $(pings) != 0 ))" "T3r a store mounted read-only withholds the ping"
ok "$(grep -qF 'code=store_readonly' <<<"$(last_emit)"; echo $?)" "T3r …and names store_readonly"
new_fixture t3r2; echo rw,errors=remount-ro,relatime > "$FX/findmnt_opts"; run_feeder
ok "$(( $(pings) != 1 ))" "T3r an option list that merely CONTAINS ro-looking text but carries rw pings (token match, not substring)"
new_fixture t3r3; echo 5 > "$FX/find_rc"; run_feeder
ok "$(( $(pings) != 0 ))" "T3r a store root whose first entry cannot be read (a device read fails behind a present mount) withholds the ping"
ok "$(grep -qF 'code=store_unreadable' <<<"$(last_emit)"; echo $?)" "T3r …and names store_unreadable"

new_fixture t3e; echo /dev/sda1 > "$FX/findmnt_out"; run_feeder
ok "$(( $(pings) != 0 ))" "T3e a store served from a plaintext device withholds the ping"
ok "$(grep -qF 'code=store_not_mapper' <<<"$(last_emit)"; echo $?)" "T3e …and names store_not_mapper"
new_fixture t3f; : > "$FX/findmnt_out"; run_feeder
ok "$(( $(pings) != 0 ))" "T3f an empty findmnt answer withholds the ping"
ok "$(grep -qF 'code=unmeasured:mount_source' <<<"$(last_emit)"; echo $?)" "T3f …and names unmeasured:mount_source"
new_fixture t3g; printf '/dev/mapper/git-data\n/dev/mapper/git-data\n' > "$FX/findmnt_out"; echo 89 > "$FX/df_pcent_store"; echo 89 > "$FX/df_ipcent_store"; run_feeder
ok "$(( $(pings) != 1 ))" "H3 a healthy host with a multi-line findmnt answer and both thresholds one below pings"

for pair in "89:1" "90:0" "91:0"; do
  v="${pair%%:*}"; want="${pair##*:}"
  new_fixture "t4b$v"; echo "$v" > "$FX/df_pcent_store"; run_feeder
  ok "$(( $(pings) != want ))" "T4 bytes at $v% -> pings=$want (got $(pings))"
  new_fixture "t4i$v"; echo "$v" > "$FX/df_ipcent_store"; run_feeder
  ok "$(( $(pings) != want ))" "T4 inodes at $v% -> pings=$want (got $(pings))"
done
new_fixture t4c; echo 95 > "$FX/df_pcent_store"; run_feeder
ok "$(grep -qF 'code=disk_full' <<<"$(last_emit)"; echo $?)" "T4 bytes over threshold names disk_full"
new_fixture t4d; echo 95 > "$FX/df_ipcent_store"; run_feeder
ok "$(grep -qF 'code=inodes_full' <<<"$(last_emit)"; echo $?)" "T4 inodes over threshold names inodes_full"
new_fixture t4e; echo unreadable > "$FX/df_pcent_store"; run_feeder
ok "$(( $(pings) != 0 ))" "T4 an unreadable bytes measurement withholds the ping"
ok "$(grep -qF 'code=unmeasured:df_bytes' <<<"$(last_emit)"; echo $?)" "T4 …and names unmeasured:df_bytes"
new_fixture t4f; echo unreadable > "$FX/df_ipcent_store"; run_feeder
ok "$(grep -qF 'code=unmeasured:df_inodes' <<<"$(last_emit)"; echo $?)" "T4 an unreadable inode measurement names unmeasured:df_inodes"
new_fixture t4g; echo 99 > "$FX/df_pcent_root"; run_feeder
ok "$(( $(pings) != 1 ))" "T4 root usage at 99% does NOT gate the ping (report-only)"
ok "$(grep -qF 'root_pct=99' <<<"$(last_emit)"; echo $?)" "T4 …and is carried on the event as root_pct=99"
new_fixture t4h; echo unreadable > "$FX/df_pcent_root"; run_feeder
ok "$(( $(pings) != 1 ))" "T4 an unreadable root measurement does not gate the ping either"
ok "$(grep -qF 'root_pct=?' <<<"$(last_emit)"; echo $?)" "T4 …and reports root_pct=?"

new_fixture t5a; echo failed > "$FX/unit_git-data-luks-reopen"; run_feeder
ok "$(( $(pings) != 0 ))" "T5 a failed LUKS reopen unit withholds the ping"
ok "$(grep -qF 'code=unit_failed:git-data-luks-reopen' <<<"$(last_emit)"; echo $?)" "T5 …and names it"
new_fixture t5b; echo failed > "$FX/unit_git-data-nftables"; run_feeder
ok "$(grep -qF 'code=unit_failed:git-data-nftables' <<<"$(last_emit)"; echo $?)" "T5 a failed nftables unit names unit_failed:git-data-nftables"
new_fixture t5c; echo failed > "$FX/unit_git-data-gc"; run_feeder
ok "$(( $(pings) != 1 ))" "T5 a failed maintenance (gc) unit does NOT withhold the ping (the paging policy is the owner's)"
new_fixture t5d; echo 3 > "$FX/systemctl_rc"; run_feeder
ok "$(grep -qF 'code=unmeasured:units' <<<"$(last_emit)"; echo $?)" "T5 an unreadable service manager names unmeasured:units"
ok "$([ "$(grep -o 'unmeasured:units' <<<"$(last_emit)" | grep -c .)" = 2 ]; echo $?)" "T5 …and the code appears ONCE in the code field (and once in its key=value echo of the detail)"
for st in inactive activating deactivating; do
  for u in git-data-luks-reopen git-data-nftables; do
    new_fixture "t5s-$u-$st"; echo "$st" > "$FX/unit_$u"; run_feeder
    ok "$(( $(pings) != 1 ))" "T5 $u reading $st (a timer-driven oneshot between runs) does NOT withhold the ping"
  done
done
new_fixture t5m; echo not-found > "$FX/unit_git-data-nftables"; run_feeder
ok "$(( $(pings) != 0 ))" "T5 a unit that does not EXIST (LoadState=not-found, ActiveState=inactive, rc 0) withholds the ping"
ok "$(grep -qF 'code=unit_missing:git-data-nftables' <<<"$(last_emit)"; echo $?)" "T5 …and names unit_missing, never reading the ghost unit as healthy"
new_fixture t5e; echo inactive > "$FX/unit_ssh"; run_feeder
ok "$(( $(pings) != 1 ))" "T5 an inactive ssh.service on a host whose listener answers is HEALTHY (socket activation)"
new_fixture t5f; echo /dev/sda1 > "$FX/findmnt_out"; echo 95 > "$FX/df_ipcent_store"; echo failed > "$FX/unit_git-data-luks-reopen"; run_feeder
ok "$(grep -qE 'code=store_not_mapper,inodes_full,unit_failed:git-data-luks-reopen\|' <<<"$(last_emit)"; echo $?)" "T5 simultaneous misses are ALL named, in check order"
ok "$(( $(pings) != 0 ))" "T5 …and withhold the ping"

# T6: the URL source.
for badurl in "https://uptime.betterstack.com/api/v1/heartbeat/abc
url = \"https://evil.example/\"" "https://evil.example/api/v1/heartbeat/abc" "http://uptime.betterstack.com/api/v1/heartbeat/abc" \
  "https://uptime.betterstack.com/api/v1/heartbeat/ab\"cd" "https://uptime.betterstack.com/api/v1/heartbeat/" \
  "https://uptime.betterstack.com/api/v1/heartbeat/ab/cd"; do
  new_fixture t6a; printf '%s' "$badurl" > "$FX/secret"; run_feeder
  ok "$(( $(pings) != 0 ))" "T6 a malformed URL never reaches curl ($(printf '%s' "$badurl" | head -c 40 | tr '\n' ' '))"
  ok "$(grep -qF 'state=url_unavailable' <<<"$(last_emit)"; echo $?)" "T6 …and is reported url_unavailable"
done
new_fixture t6b; rm -f "$FX/secret"; echo 1 > "$FX/doppler_rc"; run_feeder
ok "$(( $(pings) != 0 ))" "T6 an absent secret in the production config withholds the ping"
ok "$(grep -qF 'state=url_unavailable' <<<"$(last_emit)"; echo $?)" "T6 …as url_unavailable"
new_fixture t6c; CFG=prd_git_data_rehearsal_abc123; rm -f "$FX/secret"; echo 1 > "$FX/doppler_rc"; run_feeder
ok "$(grep -qF 'state=disarmed' <<<"$(last_emit)"; echo $?)" "T6 the rehearsal config with the secret absent is disarmed, never url_unavailable (exact equality)"
ok "$(( $(pings) != 0 ))" "T6 …and sends no ping"
new_fixture t6d; CFG=prd_git_data_x; rm -f "$FX/secret"; echo 1 > "$FX/doppler_rc"; run_feeder
ok "$(grep -qF 'state=disarmed' <<<"$(last_emit)"; echo $?)" "T6 a config that merely shares the production prefix is disarmed (no prefix match)"
new_fixture t6f; CFG=""; run_feeder
ok "$(( $(pings) != 0 ))" "T6 an UNSET config name (a production host that lost its env file) sends no ping"
ok "$(grep -qF 'state=url_unavailable' <<<"$(last_emit)"; echo $?)" "T6 …and is url_unavailable, never the benign rehearsal label disarmed"
ok "$([ ! -e "$FX/doppler.calls" ]; echo $?)" "T6 …without calling doppler with an invalid config argument"
new_fixture t6g; CFG="BAD CONFIG"; run_feeder
ok "$(grep -qF 'state=url_unavailable' <<<"$(last_emit)"; echo $?)" "T6 a config name outside [a-z0-9_] is treated as unreadable (url_unavailable)"
new_fixture t6h; mkdir -p "$FX/run"; printf 'https://evil.example/x\n' > "$FX/run/url"; run_feeder
ok "$(grep -qF "url = \"$GOOD_URL\"" "$FX/curl.stdin" && ! grep -qF 'evil.example' "$FX/curl.stdin"; echo $?)" "T6 a corrupt cached URL is discarded and re-fetched, never pinged"
new_fixture t6e; : > "$FX/secret"; run_feeder
ok "$(grep -qF 'state=url_unavailable' <<<"$(last_emit)"; echo $?)" "T6 a doppler that exits 0 with an EMPTY secret is an absent secret, not a valid URL"
ok "$(( $(pings) != 0 ))" "T6 …and sends no ping"

# T7: the cache. Empty -> retried every tick; filled -> not re-read; dropped on a ping failure.
new_fixture t7; rm -f "$FX/secret"; echo 1 > "$FX/doppler_rc"
run_feeder; NOW_T=1000060; run_feeder
ok "$(( $(lines doppler.calls) != 2 ))" "T7 an empty cache is re-fetched on EVERY tick (2 ticks, $(lines doppler.calls) fetches)"
printf '%s' "$GOOD_URL" > "$FX/secret"; rm -f "$FX/doppler_rc"; NOW_T=1000120; run_feeder
ok "$(( $(pings) != 1 ))" "T7 once the secret exists the next tick pings, with no second replace"
NOW_T=1000180; run_feeder
ok "$(( $(lines doppler.calls) != 3 ))" "T7 a filled cache is NOT re-read (fetches stay at 3, got $(lines doppler.calls))"
ok "$(( $(pings) != 2 ))" "T7 …and the second healthy tick pings again from the cache"
echo 22 > "$FX/curl_rc"; NOW_T=1000240; run_feeder
ok "$(grep -qF 'state=ping_fail' <<<"$(last_emit)"; echo $?)" "T7 a rejected ping is reported ping_fail, distinct from a host miss"
ok "$([ ! -e "$FX/run/url" ]; echo $?)" "T7 …and drops the cache"
rm -f "$FX/curl_rc"; NOW_T=1000300; run_feeder
ok "$(( $(lines doppler.calls) != 4 ))" "T7 the next tick re-reads the secret (rotation by re-read)"
new_fixture t7d; run_feeder
echo 22 > "$FX/curl_rc"; NOW_T=1000060; run_feeder
ok "$([ -s "$FX/run/url.last" ] && [ ! -e "$FX/run/url" ]; echo $?)" "T7 a rejected URL is kept as the last-good fallback (url.last), not discarded"
rm -f "$FX/curl_rc"; echo 1 > "$FX/doppler_rc"; NOW_T=1000120; run_feeder
ok "$(grep -qF 'state=ok' <<<"$(last_emit)"; echo $?)" "T7 a vendor blip followed by a Doppler outage still pings from the last-good URL (no false page)"
ok "$([ -s "$FX/run/url" ] && [ ! -e "$FX/run/url.last" ]; echo $?)" "T7 …and a last-good URL that worked is promoted back to the cache"
new_fixture t7b; echo "22 0" > "$FX/curl_seq"; run_feeder
ok "$(( $(pings) != 2 ))" "T7 one vendor blip is absorbed by the second attempt (2 curl calls)"
ok "$(grep -qF 'state=ok' <<<"$(last_emit)"; echo $?)" "T7 …and the tick reads ok"
new_fixture t7c; echo 22 > "$FX/curl_rc"; run_feeder
ok "$(( $(pings) != 2 ))" "T7 two failed attempts end the tick at exactly 2 curl calls"

# T8: emission cadence and failure handling.
new_fixture t8; run_feeder
ok "$(( $(emits) != 1 ))" "T8 tick 1 emits the transition"
NOW_T=1000060; run_feeder
ok "$(( $(emits) != 1 ))" "T8 an unchanged healthy tick 60 s later does not emit"
NOW_T=1000601; run_feeder
ok "$(( $(emits) != 2 ))" "T8 the 10-minute state=ok summary emits (proof the feeder is still ticking)"
echo 95 > "$FX/df_ipcent_store"; NOW_T=1000661; run_feeder
ok "$(( $(emits) != 3 ))" "T8 healthy -> miss emits the transition"
NOW_T=1000721; run_feeder
ok "$(( $(emits) != 3 ))" "T8 a persistent miss does not re-emit 60 s later"
NOW_T=1002500; run_feeder
ok "$(( $(emits) != 4 ))" "T8 a persistent miss re-emits after 30 minutes"
rm -f "$FX/df_ipcent_store"; NOW_T=1002560; run_feeder
ok "$(( $(emits) != 5 ))" "T8 degraded -> healthy emits the recovery"
ok "$(( $(pings) != 4 ))" "T8 pings resume on recovery (4 pings over 4 healthy ticks, got $(pings))"
ok "$(grep -qF 'state=ok' <<<"$(last_emit)"; echo $?)" "T8 …and the last event is ok"

new_fixture t8b; run_feeder
NOW_T=1000599; run_feeder
ok "$(( $(emits) != 1 ))" "T8 the ok summary is NOT due at 599 s"
NOW_T=1000600; run_feeder
ok "$(( $(emits) != 2 ))" "T8 the ok summary IS due at exactly 600 s"
new_fixture t8c; echo 95 > "$FX/df_ipcent_store"; run_feeder
NOW_T=1001799; run_feeder
ok "$(( $(emits) != 1 ))" "T8 a persistent miss does NOT re-emit at 1799 s"
NOW_T=1001800; run_feeder
ok "$(( $(emits) != 2 ))" "T8 a persistent miss re-emits at exactly 1800 s"
new_fixture t8d; echo 95 > "$FX/df_ipcent_store"; run_feeder
echo 95 > "$FX/df_pcent_store"; echo 1 > "$FX/df_ipcent_store"; NOW_T=1000060; run_feeder
ok "$(( $(emits) != 2 ))" "T8 a changed CODE within the same state emits at once (disk_full after inodes_full)"
for scen in url_unavailable disarmed ping_fail; do
  new_fixture "t8s-$scen"
  case "$scen" in
    url_unavailable) rm -f "$FX/secret"; echo 1 > "$FX/doppler_rc" ;;
    disarmed) CFG=prd_git_data_rehearsal_abc; rm -f "$FX/secret"; echo 1 > "$FX/doppler_rc" ;;
    ping_fail) echo 22 > "$FX/curl_rc" ;;
  esac
  run_feeder; NOW_T=1000060; run_feeder
  ok "$(( $(emits) != 1 ))" "T8 state $scen is remembered across ticks: no re-emit 60 s later (the read_state allowlist keeps it)"
done
new_fixture t9; echo 1 > "$FX/emit_rc"; run_feeder
ok "$(( RC != 0 ))" "H5 an emit that fails on every call leaves the feeder at exit 0 (rc=$RC)"
ok "$(( $(pings) != 1 ))" "H5 …and the ping was still sent"
NOW_T=1000060; run_feeder
ok "$(( $(emits) != 2 ))" "H5 …and the transition is RETRIED next tick (state was not advanced; $(emits) emit attempts)"
rm -f "$FX/emit_rc"; NOW_T=1000120; run_feeder
ok "$(( $(emits) != 3 ))" "H5 …and once the emit works the event is delivered once"
NOW_T=1000180; run_feeder
ok "$(( $(emits) != 3 ))" "H5 …and is not repeated afterwards"

# T10: bounded steps.
new_fixture t10a; echo 8 > "$FX/doppler_hang"; rm -f "$FX/secret"; run_feeder GIT_DATA_LIVENESS_FETCH_TIMEOUT=2
ok "$(( ELAPSED > 6 ))" "T10 a hung doppler fetch is cut at the bound (2 s seam; took ${ELAPSED}s)"
ok "$(( RC != 0 ))" "T10 …and the feeder still exits 0"
ok "$(( $(pings) != 0 ))" "T10 …with no ping (no URL)"
new_fixture t10b; echo 8 > "$FX/emit_hang"; run_feeder GIT_DATA_LIVENESS_EMIT_TIMEOUT=2
ok "$(( ELAPSED > 6 ))" "T10 a hung emit is cut at the bound (2 s seam; took ${ELAPSED}s)"
ok "$(( $(pings) != 1 ))" "T10 …and the ping decision is unchanged (ping already sent)"
ok "$([ ! -e "$FX/run/state" ]; echo $?)" "T10 …and the state is not advanced for an emit that never returned"

new_fixture t10c; run_feeder GIT_DATA_LIVENESS_SSH_PORT="$SILENT_PORT"
ok "$(( ELAPSED > 9 ))" "T10 a listener that accepts and stays silent is cut at the banner bound (took ${ELAPSED}s)"
ok "$(grep -qF 'code=ssh_no_banner' <<<"$(last_emit)"; echo $?)" "T10 …and names ssh_no_banner"
ok "$(( $(pings) != 0 ))" "T10 …with no ping"
new_fixture t10d; echo 30 > "$FX/df_hang"; run_feeder
ok "$(( ELAPSED > 20 ))" "T10 a hung df (a wedged store) is cut at the instrument bound and recorded, not left to the unit timeout (took ${ELAPSED}s)"
ok "$(grep -qF 'unmeasured:df_bytes' <<<"$(last_emit)"; echo $?)" "T10 …as unmeasured:df_bytes in an emitted event"

# T11: refusal under trace, and a corrupt state file.
new_fixture t11; assert_fixture_dir "$FX"; RC=0
env -i HOME="$FX" PATH=/usr/bin:/bin GDL_FX="$FX" GDL_REAL_SLEEP="$REAL_SLEEP" GIT_DATA_LIVENESS_PATH_PREPEND="$FX/bin" \
  GIT_DATA_LIVENESS_RUN="$FX/run" GIT_DATA_LIVENESS_EMIT="$FX/bin/git-data-emit" GIT_DATA_LIVENESS_ROOT="$FX/store" \
  GIT_DATA_LIVENESS_SSH_PORT="$GOOD_PORT" GIT_DATA_DOPPLER_CONFIG=prd_git_data bash -x "$SCRIPT" > "$FX/out" 2>&1 || RC=$?
ok "$(( RC != 78 ))" "T11 the feeder refuses to run under xtrace (exit 78; rc=$RC)"
ok "$(( $(pings) != 0 ))" "T11 …before any ping"
ok "$(( $(emits) != 0 ))" "T11 …and before any emit"
ok "$(! grep -qF 'SyntheticLivenessToken0123' "$FX/out"; echo $?)" "T11 …and no URL in the trace output"
new_fixture t11b; printf 's=bogus c=$(touch /tmp/x) t=notanumber\n' > "$FX/run/state"; run_feeder
ok "$(( $(pings) != 1 ))" "H4 a corrupt state file does not stop the ping"
ok "$(( $(emits) != 1 ))" "H4 …the state resets and the transition is emitted"
ok "$(grep -qE '^s=ok c=ok t=[0-9]+$' "$FX/run/state"; echo $?)" "H4 …and the state file is rewritten in the valid shape"

new_fixture t11c; printf 's=ok c=ok t=08\n' > "$FX/run/state"; run_feeder
ok "$(( RC != 0 ))" "T11 a leading-zero stamp in the state file (octal-invalid) does not abort the script (rc=$RC)"
ok "$(( $(emits) != 1 ))" "T11 …and the due-check still runs: the stale stamp (read as 8, base 10) makes the summary due, so the event is emitted"
new_fixture t11d; printf 's=ok c=ok t=9999999999\n' > "$FX/run/state"; run_feeder
ok "$(( $(emits) != 1 ))" "T11 a stamp from the future is treated as never-emitted: exactly one emit now, and the state is rewritten with a real stamp"
NOW_T=1000060; run_feeder
ok "$(( $(emits) != 1 ))" "T11 …then no re-emit storm 60 s later (the stale future stamp no longer suppresses OR repeats the cadence)"
NOW_T=1000601; run_feeder
ok "$(( $(emits) != 2 ))" "T11 …and the 10-minute summary is due again 601 s on"

# T12: one run is deterministic about its own cache path and not about the block device.
ok "$([ "$(stat -c %a "$FX/run/state" 2>/dev/null)" = 600 ]; echo $?)" "T12 the state file is mode 0600"
ok "$(! grep -qE '^/(mnt|var)/' "$FX/run/state"; echo $?)" "T12 state lives under the run dir only"

# =====================================================================================
# STATIC — the script, the unit pair
# =====================================================================================
SCRIPT_BODY="$SCRATCH/script.body"; strip "$SCRIPT" > "$SCRIPT_BODY"
UNIT_BODY="$SCRATCH/unit.body"; strip "$UNIT" > "$UNIT_BODY"
TIMER_BODY="$SCRATCH/timer.body"; strip "$TIMER" > "$TIMER_BODY"

n=$(grep -cE '(^|[^[:alnum:]_-])curl[[:space:]]' "$SCRIPT_BODY" || true)
ok "$((n != 1))" "S1 curl has exactly one call site (_ping is the chokepoint; got $n)"
n=$(grep -c 'doppler run --project soleur ' "$SCRIPT" || true)
ok "$((n != 1))" "S2 exactly one 'doppler run --project soleur ' literal in the script, comments included (p_doppler_config_scope is not line-anchored; got $n)"
ok "$(grep -qF 'doppler run --project soleur --config "$GIT_DATA_DOPPLER_CONFIG" --only-secrets GIT_DATA_HOST_HEARTBEAT_URL --no-fallback --' "$SCRIPT_BODY"; echo $?)" "S2 the doppler call uses the exact scoped-config form"
ok "$(grep -qF '[[ $- == *x* ]]' "$SCRIPT_BODY"; echo $?)" "S3 the xtrace refusal is spelled [[ \$- == *x* ]]"
n=$(grep -cF 'set -x' "$SCRIPT" "$UNIT" "$TIMER" | awk -F: '{s+=$2} END{print s+0}')
ok "$((n != 0))" "S3 the literal text 'set -x' appears in no payload (git-data-luks.test.sh A28a greps raw source; got $n)"
n=$(grep -c 'GIT_DATA_REPO_ROOT' "$SCRIPT" "$UNIT" "$TIMER" | awk -F: '{s+=$2} END{print s+0}')
ok "$((n != 0))" "S4 GIT_DATA_REPO_ROOT appears in no payload (it would join the device-census population; got $n)"
ok "$(grep -qE '^readonly DISK_PCT_LIMIT=90$' "$SCRIPT_BODY" && grep -qE '^readonly INODE_PCT_LIMIT=90$' "$SCRIPT_BODY"; echo $?)" "S5 the thresholds are readonly constants at 90"
ok "$(grep -qF 'FETCH_TIMEOUT="$(_num "${GIT_DATA_LIVENESS_FETCH_TIMEOUT:-}" 10)"' "$SCRIPT_BODY" && grep -qF 'EMIT_TIMEOUT="$(_num "${GIT_DATA_LIVENESS_EMIT_TIMEOUT:-}" 20)"' "$SCRIPT_BODY"; echo $?)" "S6 the production bounds are 10 s (fetch) and 20 s (emit)"
tstart=$(sed -n 's/^TimeoutStartSec=\([0-9]*\)$/\1/p' "$UNIT_BODY")
c_banner=$(sed -n 's/^readonly BANNER_TIMEOUT=\([0-9]*\)$/\1/p' "$SCRIPT_BODY")
c_instr=$(sed -n 's/^readonly INSTR_TIMEOUT=\([0-9]*\)$/\1/p' "$SCRIPT_BODY")
c_ping=$(sed -n 's/^readonly PING_TIMEOUT=\([0-9]*\)$/\1/p' "$SCRIPT_BODY")
c_pause=$(sed -n 's/^readonly PING_PAUSE=\([0-9]*\)$/\1/p' "$SCRIPT_BODY")
c_fetch=$(sed -n 's/.*FETCH_TIMEOUT="$(_num "${GIT_DATA_LIVENESS_FETCH_TIMEOUT:-}" \([0-9]*\))".*/\1/p' "$SCRIPT_BODY")
c_emit=$(sed -n 's/.*EMIT_TIMEOUT="$(_num "${GIT_DATA_LIVENESS_EMIT_TIMEOUT:-}" \([0-9]*\))".*/\1/p' "$SCRIPT_BODY")
n_sites=$(grep -E '(^|[^[:alnum:]_])_i [a-z]' "$SCRIPT_BODY" | grep -vc '^_i()' || true)
# Call sites that run more than once: _pct runs for root, bytes and inodes (+2), the unit loop twice (+1).
n_exec=$((n_sites + 3))
path_a=$(( ${c_banner:-99} + ${c_fetch:-99} + 2 * ${c_ping:-99} + ${c_pause:-99} + ${c_emit:-99} ))
path_b=$(( ${c_banner:-99} + n_exec * ${c_instr:-99} + ${c_emit:-99} ))
ok "$(( !( ${tstart:-0} > 0 && path_a <= ${tstart:-0} && path_b <= ${tstart:-0} && ${tstart:-0} < 60 ) ))" "S6 the tick budget derived from the script's own constants holds: healthy path ${path_a} s and hung-instrument path ${path_b} s (${n_exec} instrument runs) fit TimeoutStartSec=${tstart:-?} and stay inside the 60 s tick"
ok "$((n_sites != 5))" "S6 the instrument call sites are exactly the five the budget assumes (mountpoint, findmnt, find, df, systemctl; got $n_sites)"
ok "$(grep -qxF 'readonly OK_SUMMARY_S=600' "$SCRIPT_BODY" && grep -qxF 'readonly MISS_REEMIT_S=1800' "$SCRIPT_BODY" && grep -qxF 'readonly PING_PAUSE=1' "$SCRIPT_BODY" && grep -qxF 'readonly BANNER_TIMEOUT=5' "$SCRIPT_BODY" && grep -qxF 'readonly INSTR_TIMEOUT=3' "$SCRIPT_BODY" && grep -qxF 'readonly PING_TIMEOUT=10' "$SCRIPT_BODY"; echo $?)" "S6 the cadence and bound constants are pinned (10 min summary, 30 min re-emit, 1 s pause, 5 s banner, 3 s instrument, 10 s ping)"
n=$(grep -cE '(^|[^[:alnum:]_/-])(wget|nc|ncat|socat|openssl|python3?)([^[:alnum:]_-]|$)' "$SCRIPT_BODY" || true)
ok "$((n != 0))" "S11 no other network-capable tool appears in the script (curl in _ping is the only sender; got $n)"
n=$(grep -c '/dev/tcp' "$SCRIPT_BODY" || true)
ok "$((n != 1))" "S11 the loopback banner read is the only /dev/tcp use (got $n)"
n=0; for f in "$UNIT" "$TIMER" "$CLOUD_INIT" "$MODULE_MAIN" "$GIT_DATA_TF"; do n=$((n + $(grep -c 'GIT_DATA_LIVENESS_' "$f" || true))); done
ok "$((n != 0))" "S12 no GIT_DATA_LIVENESS_ test seam is named in the unit, timer, cloud-init, module or git-data.tf (a unit edit cannot redirect a check; got $n)"
for u in git-data-luks-reopen git-data-nftables; do
  ok "$(grep -qF "  - path: /etc/systemd/system/$u.service" "$CLOUD_INIT"; echo $?)" "S13 the unit the feeder gates on ($u.service) is written by cloud-init, so a rename cannot leave the gate reading a ghost unit"
  ok "$(grep -qE "for u in (.*[[:space:]])?$u([[:space:]]|;)" "$SCRIPT_BODY"; echo $?)" "S13 …and the feeder's loop names $u"
done
cfg_tf=$(sed -n 's/^[[:space:]]*doppler_config_name[[:space:]]*=[[:space:]]*"\(.*\)"$/\1/p' "$GIT_DATA_TF" | head -n 1)
cfg_res=$(awk '/^resource "doppler_config" "git_data_prd" \{/{f=1} f&&/^[[:space:]]*name[[:space:]]*=/{gsub(/.*= *"|"$/,""); print; exit}' "$DIR/git-data-luks.tf")
cfg_sec=$(awk '/^resource "doppler_secret" "git_data_host_heartbeat_url_prd" \{/{f=1} f&&/^[[:space:]]*config[[:space:]]*=/{gsub(/.*= *"|"$/,""); print; exit}' "$GIT_DATA_TF")
cfg_sh=$(sed -n 's/^readonly PRODUCTION_CONFIG=\(.*\)$/\1/p' "$SCRIPT_BODY")
ok "$([ -n "$cfg_sh" ] && [ "$cfg_sh" = "$cfg_tf" ] && [ "$cfg_sh" = "$cfg_res" ] && [ "$cfg_sh" = "$cfg_sec" ]; echo $?)" "S14 the production config name agrees across the feeder ($cfg_sh), the host's doppler_config_name ($cfg_tf), the config resource ($cfg_res) and the heartbeat secret ($cfg_sec)"
n=$( { grep -rl 'GIT_DATA_HOST_HEARTBEAT_URL' "$DIR/rung2-rehearsal" "$DIR/../../../.github/workflows/git-data-rung2-rehearsal.yml" 2>/dev/null || true; } | grep -c . || true)
ok "$((n != 0))" "S15 the rehearsal root and workflow never name the heartbeat secret (a rehearsal host cannot be given the production URL; got $n)"
ok "$(grep -qxF 'Wants=network-online.target' "$UNIT_BODY"; echo $?)" "U3b the unit also Wants=network-online.target like its siblings"
ok "$(grep -qE '^#!/bin/bash$' "$SCRIPT"; echo $?)" "S7 the script is bash"
ok "$(grep -qE '^readonly PRODUCTION_CONFIG=prd_git_data$' "$SCRIPT_BODY"; echo $?)" "S8 the production config name is one exact constant"
ok "$(grep -qF '[ "$cfg" = "$PRODUCTION_CONFIG" ]' "$SCRIPT_BODY"; echo $?)" "S8 …compared by EXACT equality"
ok "$(grep -qF 'RUN_DIR="${GIT_DATA_LIVENESS_RUN:-/run/git-data-liveness}"' "$SCRIPT_BODY"; echo $?)" "S9 all state lives under /run/git-data-liveness (tmpfs)"
ok "$(grep -qE '^PATH=.*/usr/sbin' "$SCRIPT_BODY"; echo $?)" "S10 the script sets an explicit PATH that includes /usr/sbin"

ok "$(grep -qxF 'Environment=HOME=/root' "$UNIT_BODY"; echo $?)" "U1 the unit sets HOME=/root"
n=$(grep -cE '^(Requires|RequiresMountsFor|BindsTo|Requisite)=' "$UNIT_BODY" || true)
ok "$((n != 0))" "U2 the unit has no Requires/RequiresMountsFor/BindsTo/Requisite (it must observe an unmounted store; got $n)"
ok "$(grep -qxF 'After=network-online.target' "$UNIT_BODY"; echo $?)" "U3 the unit is ordered After=network-online.target"
ok "$(grep -qxF 'EnvironmentFile=-/etc/default/git-data-doppler' "$UNIT_BODY"; echo $?)" "U4 the unit reads the scoped token file"
ok "$(grep -qxF "ExecStart=/bin/sh -c 'exec /usr/local/bin/git-data-liveness.sh'" "$UNIT_BODY"; echo $?)" "U5 ExecStart runs the delivered script by absolute path under /bin/sh (keeps systemd-analyze verify green)"
n=$(grep -c 'RuntimeDirectory' "$UNIT_BODY" || true)
ok "$((n != 0))" "U6 no RuntimeDirectory= (it would wipe the cache on every oneshot exit; got $n)"
ok "$(grep -qxF 'LimitCORE=0' "$UNIT_BODY" && grep -qxF 'UMask=0077' "$UNIT_BODY" && grep -qxF 'TMPDIR=/dev/shm' <(sed 's/^Environment=//' "$UNIT_BODY"); echo $?)" "U7 the unit closes core dumps, sets umask 0077 and a tmpfs TMPDIR"
ok "$(grep -qxF 'OnBootSec=3min' "$TIMER_BODY" && grep -qxF 'OnUnitActiveSec=60s' "$TIMER_BODY" && grep -qxF 'AccuracySec=5s' "$TIMER_BODY"; echo $?)" "U8 the timer is 3 min after boot, then every 60 s, 5 s accuracy"
n=$(grep -c '^Persistent=' "$TIMER_BODY" || true)
ok "$((n != 0))" "U9 the timer sets no Persistent= (inert without OnCalendar=; got $n)"
ok "$(grep -qxF 'WantedBy=timers.target' "$TIMER_BODY"; echo $?)" "U10 the timer installs under timers.target"

# =====================================================================================
# STATIC — delivery: cloud-init, module binding, budget mirror, Terraform pair
# =====================================================================================
CI_BODY="$SCRATCH/ci.body"; strip "$CLOUD_INIT" > "$CI_BODY"
for pair in "script:/usr/local/bin/git-data-liveness.sh:git_data_liveness:0755" \
            "service:/etc/systemd/system/git-data-liveness.service:git_data_liveness_service:0644" \
            "timer:/etc/systemd/system/git-data-liveness.timer:git_data_liveness_timer:0644"; do
  IFS=: read -r label path var mode <<<"$pair"
  ok "$(awk -v p="  - path: $path" -v v="\${indent(6, $var)}" -v m="    permissions: '$mode'" '
    $0==p {f=1; next}
    f && index($0, v) {c=1}
    f && $0==m {if (c) {ok=1}; exit}
    END {exit ok?0:1}' "$CLOUD_INIT"; echo $?)" "D1 cloud-init writes the $label ($path, $mode) from $var"
done
ok "$([ "$(grep -c 'systemctl enable --now git-data-liveness.timer' "$CI_BODY")" = 1 ]; echo $?)" "D2 the timer is armed by exactly one 'systemctl enable --now git-data-liveness.timer' line"
la=$(grep -n 'systemctl enable --now git-data-liveness.timer' "$CI_BODY" | head -1 | cut -d: -f1)
lg=$(grep -n 'systemctl enable --now git-data-gc.timer' "$CI_BODY" | head -1 | cut -d: -f1)
ok "$(( !( ${la:-0} > 0 && ${lg:-0} > 0 && ${la:-0} > ${lg:-0} ) ))" "D3 the liveness arming item comes AFTER the gc_timer item (which is after boot_complete)"
arm_item=$(awk '/STAGE=liveness_timer/{f=1} f{print} f&&/^    fi$/{exit}' "$CI_BODY")
ok "$(grep -qE 'git-data-emit .* info' <<<"$arm_item"; echo $?)" "D4 a failed arm is reported at level info"
ok "$(! grep -qE '(warning|fatal)' <<<"$arm_item"; echo $?)" "D4 …and never at warning or fatal (no new routed stage)"
ok "$(grep -qE '_rc=0' <<<"$arm_item" && grep -qE '"\$\(systemctl enable --now git-data-liveness.timer 2>&1\)" \|\| ' <<<"$arm_item"; echo $?)" "D5 the arm uses the capture-and-if shape"
for pair in "git_data_liveness:git-data-liveness.sh" "git_data_liveness_service:git-data-liveness.service" "git_data_liveness_timer:git-data-liveness.timer"; do
  v="${pair%%:*}"; file="${pair##*:}"
  pat='^[[:space:]]+'"$v"'[[:space:]]+=[[:space:]]+replace\(file\("\$\{path\.module\}/\.\./\.\./'"${file//./\\.}"'"\), local\.git_data_rationale_strip, ""\)$'
  n=$(grep -cE "$pat" "$MODULE_MAIN" || true)
  ok "$((n != 1))" "M1 the module binds $v to $file on one physical line with the rationale strip (got $n)"
done
n=$(grep -c 'git-data-liveness' "$BUDGET" || true)
ok "$((n < 3))" "M2 the budget script mirrors all three payloads (mentions: $n)"
hb=$(awk '/^resource "betteruptime_heartbeat" "git_data_host_prd" \{/{f=1} f{print} f&&/^}/{exit}' "$GIT_DATA_TF")
ok "$(grep -qE 'name[[:space:]]*=[[:space:]]*"soleur-git-data-host-prd"' <<<"$hb"; echo $?)" "T-TF1 the heartbeat is named soleur-git-data-host-prd"
ok "$(grep -qE 'period[[:space:]]*=[[:space:]]*60$' <<<"$hb" && grep -qE 'grace[[:space:]]*=[[:space:]]*300$' <<<"$hb"; echo $?)" "T-TF2 period 60 and grace 300"
ok "$(grep -qE 'paused[[:space:]]*=[[:space:]]*true$' <<<"$hb" && grep -qE 'ignore_changes[[:space:]]*=[[:space:]]*\[paused\]' <<<"$hb"; echo $?)" "T-TF3 born paused, with ignore_changes=[paused]"
ok "$(grep -qE 'push[[:space:]]*=[[:space:]]*false$' <<<"$hb"; echo $?)" "T-TF4 push is false (DC-3)"
ok "$(grep -qE 'email[[:space:]]*=[[:space:]]*true$' <<<"$hb" && grep -qE 'call[[:space:]]*=[[:space:]]*false$' <<<"$hb" && grep -qE 'sms[[:space:]]*=[[:space:]]*false$' <<<"$hb"; echo $?)" "T-TF4 the alert channel is email (true), with call and sms off: the page reaches the owner"
sec=$(awk '/^resource "doppler_secret" "git_data_host_heartbeat_url_prd" \{/{f=1} f{print} f&&/^}/{exit}' "$GIT_DATA_TF")
ok "$(grep -qE 'project[[:space:]]*=[[:space:]]*"soleur"$' <<<"$sec" && grep -qE 'config[[:space:]]*=[[:space:]]*"prd_git_data"$' <<<"$sec"; echo $?)" "T-TF5 the secret's project and config are LITERALS (no doppler_config reference in the closure)"
ok "$(grep -qE 'name[[:space:]]*=[[:space:]]*"GIT_DATA_HOST_HEARTBEAT_URL"$' <<<"$sec" && grep -qE 'value[[:space:]]*=[[:space:]]*betteruptime_heartbeat\.git_data_host_prd\.url$' <<<"$sec" && grep -qE 'visibility[[:space:]]*=[[:space:]]*"masked"$' <<<"$sec"; echo $?)" "T-TF6 the secret holds the heartbeat URL, masked"
ok "$(! grep -qE 'doppler_config\.|hcloud_server\.' <<<"$sec"; echo $?)" "T-TF7 the secret references neither doppler_config nor hcloud_server"
ok "$(grep -qE '"\$\{DIR\}/git-data-liveness.sh"' "$LUKS_TEST"; echo $?)" "T-LK1 the feeder is in git-data-luks.test.sh's doppler config-scope census file list"

# =====================================================================================
# MUTATION — each Guard Contract row is an edit of a COPY that must turn a predicate RED
# =====================================================================================
MUT="$SCRATCH/mut"; mkdir -p "$MUT"
p_healthy() {  # the positive control every script mutant must still pass: a healthy host pings once
  local SUT="$1"
  new_fixture ph; run_feeder; [ "$RC" -eq 0 ] && [ "$(pings)" -eq 1 ]
}
assert_red() {  # <row> <predicate> <file-kind: script|unit|cloud> <sed-expression> [dispatch]
  local row="$1" pred="$2" kind="$3" expr="$4" gate="${5:-healthy}" src dst
  assert_fixture_dir "$MUT"
  case "$kind" in script) src="$SCRIPT" ;; unit) src="$UNIT" ;; cloud) src="$CLOUD_INIT" ;; esac
  dst="$MUT/$row.$kind"
  # The unmutated control must HOLD first: a red baseline voids every row.
  if ! "$pred" "$src"; then fail "M-$row control: the predicate does not hold on the unmutated file"; cases=$((cases + 1)); return; fi
  sed -E "$expr" "$src" > "$dst"
  chmod +x "$dst"
  if cmp -s "$src" "$dst"; then fail "M-$row the mutation did NOT land"; cases=$((cases + 1)); return; fi
  if [ "$kind" = script ] && [ "$gate" = healthy ]; then
    # A mutant that no longer parses, or no longer pings a healthy host, would turn EVERY row RED
    # for the wrong reason, so the row must prove the mutant is a working feeder first. Only the
    # dispatch row (main never invoked) is allowed to lose the healthy ping: that IS its defect.
    if ! bash -n "$dst" 2>/dev/null || ! p_healthy "$dst"; then
      fail "M-$row the mutant is not a working feeder on a healthy host, so RED would prove nothing"; cases=$((cases + 1)); return
    fi
  fi
  ok "$("$pred" "$dst" >/dev/null 2>&1; echo $(( $? == 0 )))" "M-$row the predicate turns RED under the mutation"
}

p_inodes() {  # 1: a full inode table must not ping
  local SUT="$1"
  new_fixture p1a; run_feeder; [ "$(pings)" -eq 1 ] || return 1
  new_fixture p1b; echo 95 > "$FX/df_ipcent_store"; run_feeder; [ "$(pings)" -eq 0 ]
}
p_unconditional() {  # 2/5: store unmounted must not ping, healthy must
  local SUT="$1"
  new_fixture p2a; run_feeder; [ "$(pings)" -eq 1 ] || return 1
  new_fixture p2b; echo 32 > "$FX/mp_rc"; run_feeder; [ "$(pings)" -eq 0 ]
}
p_second_miss() {  # 3: a second failing condition after a compliant first is still reported
  local SUT="$1"
  new_fixture p3; echo failed > "$FX/unit_git-data-luks-reopen"; run_feeder
  [ "$(pings)" -eq 0 ] && grep -qF 'unit_failed:git-data-luks-reopen' <<<"$(last_emit)"
}
p_boundary() {  # 4: exactly at the threshold is a miss
  local SUT="$1"
  new_fixture p4a; echo 89 > "$FX/df_pcent_store"; run_feeder; [ "$(pings)" -eq 1 ] || return 1
  new_fixture p4b; echo 90 > "$FX/df_pcent_store"; run_feeder; [ "$(pings)" -eq 0 ]
}
p_argv() {  # 6: URL on stdin, never on argv
  local SUT="$1"
  new_fixture p6; run_feeder; argv_absent_row
}
p_shape() {  # 7: a URL with an embedded newline never reaches curl
  local SUT="$1"
  new_fixture p7a; run_feeder; [ "$(pings)" -eq 1 ] || return 1
  new_fixture p7b; printf '%s\nurl = "https://evil.example/"' "$GOOD_URL" > "$FX/secret"; run_feeder; [ "$(pings)" -eq 0 ]
}
p_df_unmeasured() {  # 8: an unreadable df is never read as healthy
  local SUT="$1"
  new_fixture p8a; run_feeder; [ "$(pings)" -eq 1 ] || return 1
  new_fixture p8b; echo unreadable > "$FX/df_pcent_store"; run_feeder; [ "$(pings)" -eq 0 ]
}
p_config_exact() {  # 9: a prefix-sharing config is disarmed, not production
  local SUT="$1"
  new_fixture p9; CFG=prd_git_data_rehearsal_abc; rm -f "$FX/secret"; echo 1 > "$FX/doppler_rc"; run_feeder
  grep -qF 'state=disarmed' <<<"$(last_emit)"
}
p_fetch_bound() {  # 12a: a hung fetch is bounded
  local SUT="$1"
  new_fixture p12a; echo 8 > "$FX/doppler_hang"; rm -f "$FX/secret"; run_feeder GIT_DATA_LIVENESS_FETCH_TIMEOUT=2
  [ "$ELAPSED" -le 6 ]
}
p_emit_bound() {  # 12b: a hung emit is bounded
  local SUT="$1"
  new_fixture p12b; echo 8 > "$FX/emit_hang"; run_feeder GIT_DATA_LIVENESS_EMIT_TIMEOUT=2
  [ "$ELAPSED" -le 6 ]
}
p_banner() {  # 15: a socket-activated host (ssh.service inactive, listener answering) is healthy
  local SUT="$1"
  new_fixture p15; echo inactive > "$FX/unit_ssh"; run_feeder; [ "$(pings)" -eq 1 ]
}
p_root_report_only() {  # 16: root usage is report-only
  local SUT="$1"
  new_fixture p16; echo 99 > "$FX/df_pcent_root"; run_feeder
  [ "$(pings)" -eq 1 ] && grep -qF 'root_pct=99' <<<"$(last_emit)"
}
p_emit_retry() {  # 17: a failed emit is retried next tick
  local SUT="$1"
  new_fixture p17; echo 1 > "$FX/emit_rc"; run_feeder; NOW_T=1000060; run_feeder
  [ "$(emits)" -eq 2 ]
}
p_script_config_literal() {  # 18: the doppler call keeps the exact --config "$GIT_DATA_DOPPLER_CONFIG" form
  grep -qF -- '--config "$GIT_DATA_DOPPLER_CONFIG" ' "$1"
}
p_unit_no_requires() { ! grep -qE '^(Requires|RequiresMountsFor|BindsTo|Requisite)=' <<<"$(strip "$1")"; }
p_unit_home() { grep -qxF 'Environment=HOME=/root' <<<"$(strip "$1")"; }
p_arm_line() { grep -qF 'systemctl enable --now git-data-liveness.timer' <<<"$(strip "$1")"; }
p_service_name() {
  local f="$1"
  grep -qF -- '  - path: /etc/systemd/system/git-data-liveness.service' "$f" \
    && grep -qF -- '  - path: /etc/systemd/system/git-data-liveness.timer' "$f"
}

assert_red 1  p_inodes script        's/\[ "\$v" -ge "\$INODE_PCT_LIMIT" \] && miss inodes_full/:/'
assert_red 2  p_unconditional script 's/if \[ "\$\{#MISSES\[@\]\}" -gt 0 \]; then/if false; then/'
assert_red 3  p_second_miss script   's@\*/failed\) miss "unit_failed:\$u" ;;@*/failed) : ;;@'
assert_red 4  p_boundary script      's/"\$v" -ge "\$DISK_PCT_LIMIT"/"$v" -gt "$DISK_PCT_LIMIT"/'
assert_red 5  p_unconditional script 's/^main$/:/' dispatch
assert_red 6  p_argv script          's/--config - 2>\/dev\/null < <\(printf .url = "%s"\\n. "\$URL"\)/"$URL" 2>\/dev\/null/'
assert_red 7  p_shape script         's/^_url_ok\(\) \{$/_url_ok() { return 0; }\n_url_ok_orig() {/'
assert_red 8  p_df_unmeasured script 's/miss unmeasured:df_bytes/:/'
assert_red 9  p_config_exact script  's/\[ "\$cfg" = "\$PRODUCTION_CONFIG" \]/[[ "$cfg" == "$PRODUCTION_CONFIG"* ]]/'
assert_red 10 p_arm_line cloud       's/systemctl enable --now git-data-liveness\.timer/systemctl enable --now git-data-gc.timer/'
assert_red 11 p_service_name cloud   's#/etc/systemd/system/git-data-liveness\.service#/etc/systemd/system/git-data-liveness-x.service#'
assert_red 12a p_fetch_bound script  's/timeout "\$FETCH_TIMEOUT" doppler/doppler/'
assert_red 12b p_emit_bound script   's/timeout "\$EMIT_TIMEOUT" "\$EMIT"/"$EMIT"/'
assert_red 13 p_unit_no_requires unit 's/^After=network-online.target$/After=network-online.target\nRequiresMountsFor=\/mnt\/git-data/'
assert_red 14 p_unit_home unit       's/^Environment=HOME=\/root$/Environment=HOME=\/tmp/'
assert_red 15 p_banner script        's@^  _banner \|\| miss ssh_no_banner$@  [ "$(_unit_state ssh.service)" = loaded/active ] || miss ssh_no_banner@'
assert_red 16 p_root_report_only script 's/^(  root_pct="\$\(_pct pcent \/\)" \|\| root_pct="\?")$/\1\n  [ "${root_pct}" -ge 90 ] 2>\/dev\/null \&\& miss root_full/'
assert_red 17 p_emit_retry script    's/"config=\$cfg" >\/dev\/null 2>&1; then/"config=$cfg" >\/dev\/null 2>\&1 || :; then/'
assert_red 18 p_script_config_literal script 's/--config "\$GIT_DATA_DOPPLER_CONFIG" /--config prd_git_data /'

p_unmounted_real_rc() {  # 19: mountpoint's real "not a mountpoint" status is 32
  local SUT="$1"
  new_fixture p19; echo 32 > "$FX/mp_rc"; run_feeder
  [ "$(pings)" -eq 0 ] && grep -qF 'code=store_unmounted' <<<"$(last_emit)"
}
p_readonly() {  # 20: a read-only mount withholds the ping
  local SUT="$1"
  new_fixture p20a; run_feeder; [ "$(pings)" -eq 1 ] || return 1
  new_fixture p20b; echo ro,relatime > "$FX/findmnt_opts"; run_feeder; [ "$(pings)" -eq 0 ]
}
p_unit_missing() {  # 21: a unit that does not exist is not read as healthy
  local SUT="$1"
  new_fixture p21; echo not-found > "$FX/unit_git-data-luks-reopen"; run_feeder; [ "$(pings)" -eq 0 ]
}
p_state_octal() {  # 22: a leading-zero stamp must not abort the script
  local SUT="$1"
  new_fixture p22; printf 's=ok c=ok t=08\n' > "$FX/run/state"; run_feeder; [ "$RC" -eq 0 ] && [ "$(pings)" -eq 1 ] && [ "$(emits)" -eq 1 ]
}
p_last_good() {  # 23: a vendor blip then a Doppler outage still pings from the last-good URL
  local SUT="$1"
  new_fixture p23; run_feeder
  echo 22 > "$FX/curl_rc"; NOW_T=1000060; run_feeder
  rm -f "$FX/curl_rc"; echo 1 > "$FX/doppler_rc"; NOW_T=1000120; run_feeder
  grep -qF 'state=ok' <<<"$(last_emit)"
}
p_store_read() {  # 24: an unreadable store root withholds the ping
  local SUT="$1"
  new_fixture p24a; run_feeder; [ "$(pings)" -eq 1 ] || return 1
  new_fixture p24b; echo 5 > "$FX/find_rc"; run_feeder; [ "$(pings)" -eq 0 ]
}
p_instr_bound() {  # 25: a hung instrument is cut and recorded
  local SUT="$1"
  new_fixture p25; echo 8 > "$FX/df_hang"; run_feeder
  [ "$ELAPSED" -le 20 ] && grep -qF 'unmeasured:df_bytes' <<<"$(last_emit)"
}
assert_red 19 p_unmounted_real_rc script 's@^    32\) miss store_unmounted ;;$@    1) miss store_unmounted ;;@'
assert_red 20 p_readonly script          's@case ",\$opts," in \*,rw,\*\) : ;; \*\) miss store_readonly ;; esac@:@'
assert_red 21 p_unit_missing script      's@not-found/\*\|masked/\*\|error/\*\)@masked/*|error/*)@'
assert_red 22 p_state_octal script       's@LAST_TS=\$\(\(10#\$v\)\)@LAST_TS=$v@'
assert_red 23 p_last_good script         's@\[ -s "\$\{RUN_DIR:\?\}/url\.last" \]@false@'
assert_red 24 p_store_read script        's@^      _i find "\$STORE_ROOT" -maxdepth 1 -mindepth 1 -print -quit >/dev/null 2>&1 \|\| miss store_unreadable$@      :@'
assert_red 25 p_instr_bound script       's#^_i\(\) \{ timeout "\$INSTR_TIMEOUT" "\$@"; \}$#_i() { "$@"; }#'

# Harness rows: the suite's own instruments must notice a broken instrument.
new_fixture h1; cp "$FAKES/curl" "$SCRATCH/curl.orig"
printf '#!/bin/bash\ncat >/dev/null\nexit 0\n' > "$FX/bin/curl"; chmod +x "$FX/bin/curl"
run_feeder
ok "$(argv_absent_row >/dev/null 2>&1; echo $(( $? == 0 )))" "H1 a curl fake that records nothing makes the argv-absence row RED"
new_fixture h2; : > "$FX/df_broken"; run_feeder
ok "$(( $(pings) != 0 ))" "H2 a df fake that fails everywhere makes the healthy row RED (no ping, so the healthy expectation of 1 fails)"

# =====================================================================================
# Instrument self-test + floor
# =====================================================================================
_can_p0=$passes; _can_f0=$fails; _can_c0=$cases
pass
fail "CANARY — instrument self-test, not a real failure" 2>/dev/null
ok 0 "CANARY ok(0) must count a pass"
ok 1 "CANARY — ok(1) must count a failure, not a real failure" 2>/dev/null
if [ "$passes" -ne $((_can_p0 + 2)) ] || [ "$fails" -ne $((_can_f0 + 2)) ] || [ "$cases" -ne $((_can_c0 + 2)) ]; then
  echo "FAIL CANARY: pass()/fail()/ok() did not each move their counters (passes=$passes fails=$fails cases=$cases)" >&2
  exit 1
fi
passes=$_can_p0; fails=$_can_f0; cases=$_can_c0

MIN_ASSERTIONS=234
total=$((passes + fails))
if [ "$cases" -lt "$MIN_ASSERTIONS" ]; then
  printf 'FAIL: ran only %s assertion call sites (floor %s) — suite did not execute fully\n' "$cases" "$MIN_ASSERTIONS" >&2
  exit 1
fi
if [ "$cases" -ne "$total" ]; then
  printf 'FAIL: call sites (%s) and verdicts (%s) disagree — an ok() reached neither pass nor fail\n' "$cases" "$total" >&2
  exit 1
fi
echo "git-data-liveness: ${passes} passed, ${fails} failed (${total} assertions)"
exit $(( fails > 0 ))
