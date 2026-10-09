#!/usr/bin/env bash
# #8285 Guard 3 -- the throwaway wipe host's script (cloud-init-inngest-backstop-wipe.yml) and the
# Terraform that gates it (inngest-backstop-wipe.tf).
#
# PROPERTY UNDER TEST. The script zeroes the device ONLY when it is the whole block device that is
# volume 106261946, of exactly the expected byte size, ext4 (never crypto_LUKS), unmounted, with no
# holders, the only Hetzner volume attached; it claims `wiped` ONLY on a full read-back that is all
# zero AND no signature left; it ships its evidence row with the token on curl's stdin; and it
# does not write when the evidence channel is down.
#
# HOW IT IS DRIVEN. No root, no loop device. The script is extracted VERBATIM from the cloud-init
# write_files block, rendered with Terraform's two escapes and nothing else (each substitution is
# asserted to have landed), and run against a REGULAR FILE standing in for the device. The REAL
# blkid, dumpe2fs, dd (O_DIRECT), cmp, readlink and mkfs.ext4 run against that file, so the
# signature, the UUID and the read-back are measured, not simulated. Only the tools that need a real
# block device or the network are PATH stubs: lsblk (TYPE/SIZE/children), findmnt, blockdev,
# blkdiscard (zero / leave-a-byte / no-op / fail modes), curl, sleep. The by-id directory, the sysfs
# root, the token file and the ingest URL are rebound through the script's test seams, which are
# honoured only when WIPE_T_SEAMS=1 and are never set in production.
#
# Conventions this repo's post-mortems made load-bearing:
#   - NEVER pipe into an assertion predicate (pipefail + early grep -q SIGPIPE fails a negative
#     assertion OPEN).
#   - Every setup command is rc-checked; a harness that fails to set up ABORTS.
#   - The instrument self-test and the assertion-count floor are reported with printf + exit, never
#     through the helper they back-stop.
#   - Every mutation asserts it LANDED (md5 before/after) before its verdict counts.
#   - mktemp for every path; scratch under /var/tmp.
export TMPDIR="${TMPDIR:-/var/tmp}"
set -uo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
YML="$SCRIPT_DIR/cloud-init-inngest-backstop-wipe.yml"
TF="$SCRIPT_DIR/inngest-backstop-wipe.tf"
VARS="$SCRIPT_DIR/variables.tf"

passes=0
fails=0
executed=0
pass() { passes=$((passes + 1)); executed=$((executed + 1)); printf 'ok   - %s\n' "$1"; }
fail() { fails=$((fails + 1)); executed=$((executed + 1)); printf 'FAIL - %s\n' "$1" >&2; }
# check <description> <command...> : passes when the command exits 0.
check() { local d="$1"; shift; if "$@"; then pass "$d"; else fail "$d"; fi; }
# check_not <description> <command...> : passes when the command exits non-zero (a property must NOT hold).
check_not() { local d="$1"; shift; if "$@"; then fail "$d"; else pass "$d"; fi; }
# opt_check <description> <command...> : a row that only runs when an OPTIONAL tool (shellcheck,
# terraform + PyYAML) is installed. It must be able to FAIL the run, but it must never move
# `executed`: the FLOOR is the exact count of rows that run on every machine, so a machine without
# the optional tools cannot trip it and a machine with them cannot pad it.
opt_ran=0; opt_fails=0
opt_check() {
  local d="$1"; shift
  opt_ran=$((opt_ran + 1))
  if "$@"; then printf 'ok   - (optional, not counted toward the floor) %s\n' "$d"
  else opt_fails=$((opt_fails + 1)); printf 'FAIL - (optional) %s\n' "$d" >&2; fi
}

# ---- INSTRUMENT SELF-TEST (printf + exit; never through pass/fail) ----------------------------
_p0=$passes; _f0=$fails; _e0=$executed
check "self-test must-pass" true >/dev/null
check "self-test must-fail" false >/dev/null 2>&1
check_not "self-test negated pass" true >/dev/null 2>&1
check_not "self-test negated fail" false >/dev/null
if [ "$passes" -ne $((_p0 + 2)) ] || [ "$fails" -ne $((_f0 + 2)) ] || [ "$executed" -ne $((_e0 + 4)) ]; then
  printf 'FATAL: instrument self-test did not move the counters as expected (pass=%s fail=%s exec=%s)\n' "$passes" "$fails" "$executed" >&2
  exit 2
fi
passes=$_p0; fails=$_f0; executed=0

# ---- tooling and scratch ------------------------------------------------------------------------
for t in blkid dumpe2fs dd cmp readlink mkfs.ext4 truncate stat jq md5sum awk sed curl; do
  command -v "$t" >/dev/null 2>&1 || { printf 'FIXTURE_UNAVAILABLE: %s is required by this suite and is absent\n' "$t" >&2; exit 2; }
done
REAL_BLKID="$(command -v blkid)"

[ -r "$YML" ] || { printf 'FATAL: %s unreadable\n' "$YML" >&2; exit 2; }

# The read-back is O_DIRECT, so the fixture directory must support it (tmpfs does not). Try the
# candidates and ABORT loudly if none does; a silent fallback to buffered reads would test a
# different property.
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

W=""
for base in "$TMPDIR" /var/tmp "$SCRIPT_DIR"; do
  [ -d "$base" ] || continue
  cand="$(mktemp -d "$base/backstop-wipe-test.XXXXXXXX")" || continue
  assert_fixture_dir "$cand"
  head -c 8192 /dev/zero > "$cand/probe" 2>/dev/null
  if dd if="$cand/probe" iflag=direct bs=4096 count=1 of=/dev/null status=none 2>/dev/null; then W="$cand"; break; fi
  rm -rf "$cand"
done
[ -n "$W" ] || { printf 'FIXTURE_UNAVAILABLE: no scratch directory supports O_DIRECT reads\n' >&2; exit 2; }
assert_fixture_dir "$W"
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/bin" "$W/s" "$W/mut" || { printf 'FATAL: scratch setup failed\n' >&2; exit 2; }

PINNED_ID=106261946
LIVE_LUKS_ID=106903269
SIZE_A=16777216          # 16 MiB fixture
SIZE_B=12582912          # 12 MiB: a valid, different size supplied through the size variable
NONCE=37829680169
FIX_UUID=11111111-2222-4333-8444-555555555555
TOKEN_VALUE=synthTokenAbc123XYZ

# ---- extraction and rendering --------------------------------------------------------------------
extract_script() {
  awk '/^  - path: \/usr\/local\/sbin\/inngest-backstop-wipe\.sh$/{f=1;next} f&&(/^  - path: /||/^[a-z]/){f=0} f' "$YML" \
    | sed -e '/^    content: |$/d' -e '/^    owner:/d' -e '/^    permissions:/d' -e 's/^      //' \
    | awk '{l[NR]=$0} END{n=NR; while (n > 0 && l[n] == "") n--; for (i = 1; i <= n; i++) print l[i]}'
}
code_lines() { grep -vE '^[[:space:]]*#' "$1"; }

# render_script <out> <volume_id> <size> <nonce>: Terraform's interpolation, then its `$${` escape.
render_script() {
  local out="$1" vid="$2" size="$3" nonce="$4"
  assert_fixture_dir "$out"
  extract_script \
    | sed -E -e "s/(^|[^\$])\\\$\\{volume_id\\}/\\1$vid/g" \
            -e "s/(^|[^\$])\\\$\\{expected_size_bytes\\}/\\1$size/g" \
            -e "s/(^|[^\$])\\\$\\{nonce\\}/\\1$nonce/g" \
    | sed -e 's/\$\${/${/g' > "$out"
  [ -s "$out" ]
}

RAW="$W/raw.sh"
assert_fixture_dir "$RAW"
extract_script > "$RAW"
check "extraction: the script body was recovered from write_files (non-empty, shebang)" \
  bash -c "[ -s '$RAW' ] && [ \"\$(head -1 '$RAW' | grep -c '^#!/usr/bin/env bash')\" -gt 0 ]"
check "extraction: the raw template is NOT valid-by-accident (it still carries interpolation placeholders)" \
  grep -q '\${volume_id}' "$RAW"

GOOD="$W/good.sh"
render_script "$GOOD" "$PINNED_ID" "$SIZE_A" "$NONCE" || { printf 'FATAL: render failed\n' >&2; exit 2; }
check "render: volume_id landed"          grep -q "^VOLUME_ID='$PINNED_ID'" "$GOOD"
check "render: expected_size_bytes landed" grep -q "^EXPECTED_SIZE='$SIZE_A'" "$GOOD"
check "render: nonce landed"              grep -q "^NONCE='$NONCE'" "$GOOD"
check_not "render: no unresolved interpolation placeholder remains" grep -qE '(^|[^$])\$\{(volume_id|expected_size_bytes|nonce|betterstack_logs_token)\}' "$GOOD"
check "render: the rendered script is valid bash" bash -n "$GOOD"
if command -v shellcheck >/dev/null 2>&1; then
  opt_check "render: shellcheck -S warning is clean on the rendered script" shellcheck -S warning -s bash "$GOOD"
else
  printf 'note - shellcheck not installed; lint row not counted\n'
fi
# The sed render above is the harness's own model of templatefile(). Where terraform is available,
# prove the model against the real thing: the script rendered by terraform must be byte-identical.
if command -v terraform >/dev/null 2>&1 && python3 -I -c "import yaml" >/dev/null 2>&1; then
  TFR="$W/tf-render"; assert_fixture_dir "$TFR"; mkdir -p "$TFR"
  ( cd "$TFR" && printf 'jsonencode(templatefile("%s", {volume_id=%s, expected_size_bytes=%s, nonce="%s", betterstack_logs_token="synthTok123"}))\n' \
      "$YML" "$PINNED_ID" "$SIZE_A" "$NONCE" | terraform console 2>/dev/null \
    | python3 -I -c 'import sys,json,yaml; d=yaml.safe_load(json.loads(json.loads(sys.stdin.read().strip()))); sys.stdout.write([f for f in d["write_files"] if f["path"].endswith(".sh")][0]["content"])' > "$TFR/script.sh" )
  opt_check "render: terraform's own templatefile() output is byte-identical to the harness render" cmp -s "$TFR/script.sh" "$GOOD"
else
  printf 'note - terraform/python3 not installed; templatefile parity row not counted\n'
fi

# ---- static census (all take the script file so the mutation rows can re-run them) -------------
# census_ok <script>: exactly ONE blkdiscard call site; it is inside wipe_device; wipe_device is
# called exactly once, after the first guard_device call; no other write primitive exists.
n_blkdiscard() { code_lines "$1" | grep -c 'blkdiscard'; }
census_single_blkdiscard() { [ "$(n_blkdiscard "$1")" = 1 ]; }
census_blkdiscard_in_wipe_fn() {
  awk '/^wipe_device\(\) *\{/{f=1} f&&/blkdiscard/{c++} f&&/^}/{f=0} END{exit !(c==1)}' "$1"
}
census_wipe_called_once() { [ "$(code_lines "$1" | grep -cE '^[[:space:]]*wipe_device([[:space:]]|$)')" = 1 ]; }
census_guard_before_wipe() {
  local g w
  g="$(grep -nE '^[[:space:]]*guard_device([[:space:]]|$)' "$1" | head -1 | cut -d: -f1)"
  w="$(grep -nE '^[[:space:]]*wipe_device([[:space:]]|$)' "$1" | head -1 | cut -d: -f1)"
  [ -n "$g" ] && [ -n "$w" ] && [ "$g" -lt "$w" ]
}
census_no_other_writers() {
  local c; c="$(code_lines "$1")"
  ! grep -qE 'wipefs|shred|sgdisk|sfdisk|parted|mkfs|cryptsetup|truncate|dd[[:space:]][^|]*of=|>[[:space:]]*("?\$REAL|/dev/(sd|vd|nvme|disk|loop|mapper|xvd))|tee[[:space:]]+/dev/(sd|vd|nvme|disk|loop|mapper|xvd)' <<<"$c"
}
census_no_cmp_l_or_b() { local c; c="$(code_lines "$1")"; ! grep -qE 'cmp[[:space:]]+(-[a-z]*[lb]|--list|--print-bytes)' <<<"$c"; }
census_readback_o_direct() { local c; c="$(code_lines "$1")"; grep -q 'iflag=direct' <<<"$c" && grep -qE 'cmp -n "?\$EXPECTED_SIZE"? - /dev/zero' <<<"$c"; }
census_token_not_on_argv() {
  local c; c="$(code_lines "$1")"
  grep -q 'curl -q -K -' <<<"$c" && ! grep -qE 'curl[^|]*(Authorization|Bearer|\$TOKEN)' <<<"$c"
}
census_no_set_e() { local c; c="$(code_lines "$1")"; ! grep -qE '^[[:space:]]*set[[:space:]]+-[a-z]*e' <<<"$c"; }
# The EXACT zero call: -z (a plain discard does not zero), the whole device, stdin detached.
census_blkdiscard_exact() { local c; c="$(code_lines "$1")"; grep -qxE '[[:space:]]*blkdiscard -z "\$REAL" </dev/null' <<<"$c"; }
# curl must FAIL on an HTTP error status (-f inside the short-flag cluster) and be time-bounded.
census_curl_fail_flag() { local c; c="$(code_lines "$1")"; grep -qE 'curl[^|]* -[a-zA-Z]*f[a-zA-Z]*( |$)' <<<"$c"; }
census_curl_max_time() { local c; c="$(code_lines "$1")"; grep -qE 'curl[^|]*--max-time 15 ' <<<"$c"; }
# guard_device is called exactly twice before the (single) wipe_device call: once for the identity
# decision and once more after the started row, because the started row is a network round trip.
census_reguard_before_wipe() {
  awk '/^[[:space:]]*wipe_device([[:space:]]|$)/{w=1; exit} /^[[:space:]]*guard_device([[:space:]]|$)/{c++} END{exit !(w==1 && c==2)}' "$1"
}
# Production literals: the token path in the script is the path write_files creates, and the ingest
# endpoint is https. The seams may rebind either; these are what production runs.
yml_token_path() { sed -nE 's/^  - path: (\/run\/[^ ]*\.token)$/\1/p' "$YML" | head -1; }
script_literal() { sed -nE "s/^$2=(.*)\$/\\1/p" "$1" | head -1; }
census_token_path_parity() {
  local a b; a="$(script_literal "$1" TOKEN_FILE)"; b="$(yml_token_path)"
  [ -n "$a" ] && [ -n "$b" ] && [ "$a" = "$b" ]
}
census_ingest_https() { local u; u="$(script_literal "$1" INGEST_URL)"; case "$u" in https://?*) return 0 ;; esac; return 1; }
census_post_budget() { grep -qx 'POST_TRIES=3' "$1" && grep -qx 'POST_SLEEP=3' "$1"; }

check "census: exactly ONE blkdiscard call site"                        census_single_blkdiscard "$GOOD"
check "census: that call site is inside wipe_device()"                  census_blkdiscard_in_wipe_fn "$GOOD"
check "census: wipe_device is called exactly once"                      census_wipe_called_once "$GOOD"
check "census: guard_device is called before wipe_device"               census_guard_before_wipe "$GOOD"
check "census: no other primitive can write the device (wipefs/shred/dd of=/mkfs/cryptsetup/truncate)" census_no_other_writers "$GOOD"
check "census: the read-back never prints device bytes (no cmp -l / -b)" census_no_cmp_l_or_b "$GOOD"
check "census: the read-back is O_DIRECT and decided by cmp -n <size> against /dev/zero" census_readback_o_direct "$GOOD"
check "census: the ingest token reaches curl on stdin (-K -), never on argv" census_token_not_on_argv "$GOOD"
check "census: the script has no set -e (a failed probe must reach the refusal rows, not abort silently)" census_no_set_e "$GOOD"
check "census: the pinned volume id is a literal in the script, not only the template input" grep -q "^PINNED_ID=$PINNED_ID\$" "$GOOD"
check "census: the live LUKS volume id never appears in the script" bash -c "! grep -q '$LIVE_LUKS_ID' '$GOOD'"
check "census: the by-id wait is bounded (default WAIT_MAX literal present)" grep -qE '^WAIT_MAX=[0-9]+$' "$GOOD"
check "census: the zero call is EXACTLY blkdiscard -z on the whole device with stdin detached" census_blkdiscard_exact "$GOOD"
check "census: curl fails on an HTTP error status (-f in the short-flag cluster)" census_curl_fail_flag "$GOOD"
check "census: curl is time-bounded (--max-time)" census_curl_max_time "$GOOD"
check "census: guard_device runs TWICE before wipe_device (before and after the started-row round trip)" census_reguard_before_wipe "$GOOD"
check "census: the script's TOKEN_FILE literal equals the write_files token path" census_token_path_parity "$GOOD"
check "census: the production INGEST_URL literal is https" census_ingest_https "$GOOD"
check "census: the production evidence POST budget is 3 tries, 3 s apart (a seam may change it, production may not)" census_post_budget "$GOOD"

# ---- template / terraform static rows -------------------------------------------------------------
check_not "yml: no template directive percent-brace anywhere (comments included)" grep -q '%{' "$YML"
check_not "yml: no bare dollar-dollar followed by an identifier/paren/special (bash would read the PID)" \
  grep -qE '\$\$[A-Za-z_(0-9?!#@*-]' "$YML"
check_not "yml: no Doppler token, LUKS key or cryptsetup in any non-comment line (they must never reach this host)" \
  bash -c "[ \"\$(grep -vE '^[[:space:]]*#' '$YML' | grep -ciE 'doppler|luks_key|redis_luks|cryptsetup|INNGEST_REDIS')\" -gt 0 ]"
check "yml: header is #cloud-config" bash -c "[ \"\$(head -1 '$YML' | grep -cx '#cloud-config')\" -gt 0 ]"
check "yml: the token file is written 0600 root" \
  bash -c "[ \"\$(awk '/^  - path: \/run\/inngest-backstop-wipe\.token\$/{f=1;next} f&&/^  - path: /{f=0} f' '$YML' | grep -cE \"permissions: '0600'\")\" -gt 0 ]"
check "yml: the script is mode 0700" \
  bash -c "[ \"\$(awk '/^  - path: \/usr\/local\/sbin\/inngest-backstop-wipe\.sh\$/{f=1;next} f&&/^  - path: /{f=0} f' '$YML' | grep -cE \"permissions: '0700'\")\" -gt 0 ]"
check "yml: runcmd runs the script" bash -c "grep -qE '^[[:space:]]*- \[ *bash, */usr/local/sbin/inngest-backstop-wipe\.sh *\]' '$YML'"

yml_keys() { grep -oE '(^|[^$])\$\{[a-z_]+\}' "$YML" | grep -oE '[a-z_]+' | sort -u | tr '\n' ' '; }
tf_keys()  { awk '/templatefile\(.*cloud-init-inngest-backstop-wipe\.yml/{f=1;next} f&&/^[[:space:]]*}\)/{f=0} f' "$TF" | grep -oE '^[[:space:]]*[a-z_]+[[:space:]]*=' | tr -d ' =\t' | sort -u | tr '\n' ' '; }
check "tf: the templatefile map keys equal the yml's interpolation keys exactly ($(yml_keys))" \
  bash -c "[ -n \"\$(printf '%s' '$(tf_keys)')\" ] && [ '$(yml_keys)' = '$(tf_keys)' ]"

# Comment- and description-stripped, whitespace-normalised views: a pin matches a whole code line, never
# prose, so a description or comment that quotes a literal cannot satisfy (or break) a row.
tf_norm() { grep -vE '^[[:space:]]*#' "$1" | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//'; }
tf_pin() { local c; c="$(tf_norm "$1")"; grep -qxF -- "$2" <<<"$c"; }
tf_pin_count() { local c; c="$(tf_norm "$1")"; [ "$(grep -cxF -- "$2" <<<"$c")" = "$3" ]; }
vblock() { awk -v v="$2" '$0 ~ "^variable \"" v "\"" {f=1} f&&/^}/{f=0} f' "$1" | grep -vE '^[[:space:]]*(description|#)' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//'; }
vpin() { local b; b="$(vblock "$1" "$2")"; grep -qxF -- "$3" <<<"$b"; }
vpin_vol() { vpin "$1" inngest_backstop_volume_id 'condition = var.inngest_backstop_volume_id == 106261946'; }
tf_server_name() { awk '/^resource "hcloud_server" "inngest_backstop_wipe"/{f=1} f&&/^[[:space:]]*name[[:space:]]*=/{gsub(/^[^"]*"|".*$/,""); print; exit}' "$1"; }
tf_nonce_precond() { tf_pin "$1" 'condition = can(regex("^[0-9]{1,20}$", var.inngest_backstop_wipe_nonce))'; }
tf_server_pin() { tf_pin "$1" 'server_id = hcloud_server.inngest_backstop_wipe[0].id'; }
tf_size_pin() { tf_pin "$1" 'inngest_backstop_wipe_expected_size_bytes = 10 * 1073741824'; }
tf_nonce_entry() { tf_pin "$1" 'nonce = var.inngest_backstop_wipe_nonce'; }
tf_size_entry() { tf_pin "$1" 'expected_size_bytes = local.inngest_backstop_wipe_expected_size_bytes'; }
tf_volume_pins() { tf_pin_count "$1" 'volume_id = var.inngest_backstop_volume_id' 2; }
tf_count_gate() { tf_pin_count "$1" 'count = var.inngest_backstop_wipe_enabled ? 1 : 0' 2; }
TF_SERVER_NAME="$(tf_server_name "$TF")"
[ -n "$TF_SERVER_NAME" ] || { printf 'FATAL: could not read the wipe server name from %s\n' "$TF" >&2; exit 2; }

check "tf: server and attachment are both count-gated on inngest_backstop_wipe_enabled" tf_count_gate "$TF"
check "tf: server pinned to var.location" tf_pin "$TF" 'location = var.location'
check "tf: server uses the existing deny-all firewall" tf_pin "$TF" 'firewall_ids = [hcloud_firewall.inngest.id]'
check "tf: ssh_keys is the existing default key" tf_pin "$TF" 'ssh_keys = [hcloud_ssh_key.default.id]'
check "tf: ignore_changes=[ssh_keys]" tf_pin "$TF" 'ignore_changes = [ssh_keys]'
check "tf: label role=inngest-backstop-wipe" tf_pin "$TF" 'role = "inngest-backstop-wipe"'
check "tf: label ephemeral=true" tf_pin "$TF" 'ephemeral = "true"'
check "tf: attachment has automount=false" tf_pin "$TF" 'automount = false'
check "tf: the server name is the literal the evidence row's host field is pinned to ($TF_SERVER_NAME)" tf_pin "$TF" "name = \"$TF_SERVER_NAME\""
check "tf: the attachment's server_id is the WIPE host (never the live inngest server)" tf_server_pin "$TF"
check "tf: the nonce precondition requires 1-20 digits (empty or non-numeric refuses before any create)" tf_nonce_precond "$TF"
check "tf: the expected size is 10 GiB, a historical literal (not the live volume's variable)" tf_size_pin "$TF"
check "tf: the templatefile nonce entry is the nonce VARIABLE reference" tf_nonce_entry "$TF"
check "tf: the templatefile size entry is the pinned local" tf_size_entry "$TF"
check "tf: volume_id comes from the pinned numeric variable in BOTH the template map and the attachment" tf_volume_pins "$TF"
check "tf: the ingest token is the EXISTING variable (no new secret variable)" tf_pin "$TF" 'betterstack_logs_token = var.betterstack_logs_token'
check_not "tf: the live LUKS volume is never referenced by this file" bash -c "[ \"\$(grep -vE '^[[:space:]]*#' '$TF' | grep -cE 'inngest_redis_luks|$LIVE_LUKS_ID')\" -gt 0 ]"
check "tf: the user_data is not baked from any Doppler token or LUKS key" \
  bash -c "[ \"\$(grep -vE '^[[:space:]]*#' '$TF' | grep -ciE 'doppler|luks_key|redis_luks_key')\" -eq 0 ]"
check "vars: inngest_backstop_wipe_enabled is a bool" vpin "$VARS" inngest_backstop_wipe_enabled 'type = bool'
check "vars: inngest_backstop_wipe_enabled defaults to false" vpin "$VARS" inngest_backstop_wipe_enabled 'default = false'
check "vars: inngest_backstop_volume_id is a number" vpin "$VARS" inngest_backstop_volume_id 'type = number'
check "vars: inngest_backstop_volume_id defaults to $PINNED_ID" vpin "$VARS" inngest_backstop_volume_id "default = $PINNED_ID"
check "vars: the volume id validation is an allow-list of exactly $PINNED_ID (not a deny-list: no other id, the live LUKS id included, passes)" vpin_vol "$VARS"
check "vars: the nonce validation accepts only digits or empty" vpin "$VARS" inngest_backstop_wipe_nonce 'condition = can(regex("^[0-9]{0,20}$", var.inngest_backstop_wipe_nonce))'
check_not "vars: no new secret variable was added for the wipe (sensitive = true absent in the wipe variable blocks)" \
  bash -c "[ \"\$(for v in inngest_backstop_wipe_enabled inngest_backstop_volume_id inngest_backstop_wipe_server_type inngest_backstop_wipe_nonce; do awk -v v=\"\$v\" '\$0 ~ \"^variable \\\"\"v\"\\\"\"{f=1} f&&/^}/{f=0} f' '$VARS'; done | grep -c 'sensitive')\" -gt 0 ]"

# ---- fixture machinery ----------------------------------------------------------------------------
# stubs ----------------------------------------------------------------------------------------------
assert_fixture_dir "$W"
# Every stub that takes the device as an operand FAILS unless that operand is the fixture device
# (FIX_DEV): a script that queried the wrong path (the by-id directory, an unresolved alias) must be
# unable to look healthy.
cat > "$W/bin/lsblk" <<'EOF'
#!/bin/sh
echo "lsblk $*" >> "$STUB_DIR/lsblk.log"
dev=""; for a in "$@"; do dev="$a"; done
[ "$dev" = "$FIX_DEV" ] || { echo "lsblk: unexpected operand $dev" >> "$STUB_DIR/badop.log"; exit 1; }
case "$*" in
  *TYPE,SIZE*) sz="$(stat -L -c %s "$dev")" || exit 1; echo "${LSBLK_TYPE:-disk} $sz" ;;
  *NAME*)      echo "dev0"; [ -n "${FX_CHILD:-}" ] && echo "dev0p1"; exit 0 ;;
esac
exit 0
EOF
cat > "$W/bin/findmnt" <<'EOF'
#!/bin/sh
echo "findmnt $*" >> "$STUB_DIR/findmnt.log"
dev=""; for a in "$@"; do dev="$a"; done
# A wrong operand reads as MOUNTED (and is logged): the script refuses instead of passing.
[ "$dev" = "$FIX_DEV" ] || { echo "findmnt: unexpected operand $dev" >> "$STUB_DIR/badop.log"; echo /mnt/wrong-operand; exit 0; }
{ [ "${FX_MOUNTED:-}" = 1 ] || [ -e "$STUB_DIR/mounted.flag" ]; } && echo /mnt/stub
exit 0
EOF
cat > "$W/bin/blockdev" <<'EOF'
#!/bin/sh
echo "blockdev $*" >> "$STUB_DIR/blockdev.log"
echo "blockdev $*" >> "$STUB_DIR/order.log"
exit 0
EOF
cat > "$W/bin/sleep" <<'EOF'
#!/bin/sh
echo "sleep $*" >> "$STUB_DIR/sleep.log"
exit 0
EOF
cat > "$W/bin/hostname" <<'EOF'
#!/bin/sh
echo "$HOSTNAME_STUB"
EOF
# blkdiscard honours its flags: -z/--zeroout is REQUIRED (a plain discard does not zero), and it
# zeroes only [--offset, --offset+--length) of the device (default: the whole device). Anything else
# is rejected, so a mutated call cannot look like a full zero.
cat > "$W/bin/blkdiscard" <<'EOF'
#!/bin/sh
echo "blkdiscard $*" >> "$STUB_DIR/blkdiscard.log"
echo "blkdiscard $*" >> "$STUB_DIR/order.log"
zeroout=0; off=0; len=""; dev=""
while [ $# -gt 0 ]; do
  case "$1" in
    -z|--zeroout) zeroout=1 ;;
    -o|--offset) shift; off="$1" ;;
    --offset=*) off="${1#*=}" ;;
    -l|--length) shift; len="$1" ;;
    --length=*) len="${1#*=}" ;;
    -*) echo "blkdiscard: stub rejects option $1" >&2; exit 64 ;;
    *) dev="$1" ;;
  esac
  shift
done
[ "$zeroout" = 1 ] || { echo "blkdiscard: stub requires -z (a plain discard does not zero)" >&2; exit 64; }
[ "$dev" = "$FIX_DEV" ] || { echo "blkdiscard: unexpected operand $dev" >> "$STUB_DIR/badop.log"; exit 1; }
size="$(stat -L -c %s "$dev")" || exit 1
[ -n "$len" ] || len=$((size - off))
whole=0; { [ "$off" = 0 ] && [ "$len" = "$size" ]; } && whole=1
case "${BD_MODE:-zero}" in
  fail) exit 1 ;;
  noop) exit 0 ;;
  partial)
    truncate -s 0 "$dev" && truncate -s "$size" "$dev" || exit 1
    printf '\001' | dd of="$dev" bs=1 seek=$((size - 1)) conv=notrunc status=none || exit 1 ;;
  *)
    if [ "$whole" = 1 ]; then truncate -s 0 "$dev" && truncate -s "$size" "$dev" || exit 1
    else dd if=/dev/zero of="$dev" bs=1M oflag=seek_bytes seek="$off" count="$len" iflag=count_bytes conv=notrunc status=none || exit 1; fi ;;
esac
exit 0
EOF
cat > "$W/bin/blkid" <<'EOF'
#!/bin/sh
# Real blkid, except: after a (stub) zero it can be forced to claim a surviving signature
# (BLKID_FORCE_TYPE) or to fail with an arbitrary rc (BLKID_FORCE_RC_AFTER); before any zero it can
# be forced to fail with an arbitrary rc (BLKID_FORCE_RC), the "probe error that is neither found
# nor not-found" case.
if [ -s "$STUB_DIR/blkdiscard.log" ]; then
  if [ -n "${BLKID_FORCE_TYPE:-}" ]; then echo "$BLKID_FORCE_TYPE"; exit 0; fi
  if [ -n "${BLKID_FORCE_RC_AFTER:-}" ]; then exit "$BLKID_FORCE_RC_AFTER"; fi
else
  if [ -n "${BLKID_FORCE_RC:-}" ]; then exit "$BLKID_FORCE_RC"; fi
fi
exec "$REAL_BLKID" "$@"
EOF
# curl models the HTTP layer. CURL_RC is a transport failure. CURL_HTTP=503 is a server that ANSWERS
# with an error status: real curl exits 22 for that ONLY when -f/--fail is in argv (a short cluster
# such as -fsS counts); without it curl exits 0 and the error body would be "delivered".
# LATE_HOLDER / LATE_MOUNT make the device change state right after the FIRST successful POST (the
# started row), the window the second guard_device exists to close.
cat > "$W/bin/curl" <<'EOF'
#!/bin/sh
n=$(( $(cat "$STUB_DIR/curl.n" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$STUB_DIR/curl.n"
printf '%s\n' "$*" >> "$STUB_DIR/curl.argv"
echo "curl $n" >> "$STUB_DIR/order.log"
case " $* " in *" -K - "*) cat > "$STUB_DIR/curl.stdin.$n" ;; esac
payload=""; prev=""
for a in "$@"; do [ "$prev" = "-d" ] && payload="$a"; prev="$a"; done
rc="${CURL_RC:-0}"
if [ -n "${CURL_OK_FIRST:-}" ] && [ "$n" -gt "$CURL_OK_FIRST" ]; then rc=7; fi
if [ "$rc" = 0 ] && [ -n "${CURL_HTTP:-}" ] && [ "$CURL_HTTP" -ge 400 ]; then
  for a in "$@"; do
    case "$a" in
      --fail*) rc=22 ;;
      --*) : ;;
      -*f*) rc=22 ;;
    esac
  done
fi
if [ "$rc" = 0 ]; then printf '%s' "$payload" > "$STUB_DIR/payload.$n.ok"; else printf '%s' "$payload" > "$STUB_DIR/payload.$n.fail"; fi
if [ "$rc" = 0 ] && [ "$n" = 1 ]; then
  if [ -n "${LATE_HOLDER:-}" ]; then : > "$LATE_HOLDER"; fi
  if [ -n "${LATE_MOUNT:-}" ]; then : > "$STUB_DIR/mounted.flag"; fi
fi
exit "$rc"
EOF
chmod +x "$W"/bin/* || { printf 'FATAL: stub chmod failed\n' >&2; exit 2; }

# mkfixture <file> <size>: a real ext4 image with a synthetic payload far from the metadata.
mkfixture() {
  local f="$1" size="$2"
  rm -f "$f"
  truncate -s "$size" "$f" || return 1
  mkfs.ext4 -F -q -U "$FIX_UUID" "$f" || return 1
  printf 'SYNTHETIC-PAYLOAD-0001' | dd of="$f" bs=1 seek=$((size - 4096)) conv=notrunc status=none || return 1
}

# scenario <name> <script>: build the fixture and run the script. Behaviour knobs come from the
# caller's prefix assignments: FX_KIND (ext4|luks|ext2|zero|dirty), FX_SIZE, FX_GROW, FX_MOUNTED,
# FX_HOLDER, FX_SLAVE, FX_NOSLAVES, FX_OTHER, FX_CHILD, FX_NODEV, FX_NOSYSFS, BD_MODE, CURL_RC,
# CURL_HTTP, CURL_OK_FIRST, BLKID_FORCE_TYPE, BLKID_FORCE_RC, BLKID_FORCE_RC_AFTER, LATE_HOLDER_T,
# LATE_MOUNT_T (device changes state after the started row), POST_TRIES_T, NO_SEAMS (the script's
# WIPE_T_* variables set WITHOUT WIPE_T_SEAMS=1), PROD_URL (every seam but the ingest URL),
# WAIT_MAX_T, EXP_SIZE (no effect on the script: it is rendered by the caller).
# Results: $W/s/<name>/{rc,out,dev.md5.before,dev.md5.after}.
scenario() {
  local script="$2" d="$W/s/$1"
  local kind="${FX_KIND:-ext4}" size="${FX_SIZE:-$SIZE_A}"
  assert_fixture_dir "$d"; rm -rf "$d"; mkdir -p "$d/byid" "$d/sys/block/dev0/holders" "$d/sys/block/dev0/slaves" || return 1
  local dev="$d/dev0"
  case "$kind" in
    ext4)  mkfixture "$dev" "$size" || return 1 ;;
    luks)  truncate -s "$size" "$dev" && printf 'LUKS\272\276\000\001' | dd of="$dev" bs=1 conv=notrunc status=none || return 1 ;;
    ext2)  truncate -s "$size" "$dev" && mkfs.ext2 -F -q "$dev" || return 1 ;;
    zero)  truncate -s "$size" "$dev" || return 1 ;;
    dirty) truncate -s "$size" "$dev" && printf 'SYNTHETIC-DAMAGED-0002' | dd of="$dev" bs=1 seek=$((size / 2)) conv=notrunc status=none || return 1 ;;
  esac
  [ -n "${FX_GROW:-}" ] && { truncate -s "$((size + FX_GROW))" "$dev" || return 1; }
  [ -z "${FX_NODEV:-}" ] && ln -s "$dev" "$d/byid/scsi-0HC_Volume_${FX_BYID_ID:-$PINNED_ID}"
  [ -n "${FX_OTHER:-}" ] && { : > "$d/other"; ln -s "$d/other" "$d/byid/scsi-0HC_Volume_$LIVE_LUKS_ID"; }
  [ -n "${FX_HOLDER:-}" ] && : > "$d/sys/block/dev0/holders/dm-0"
  [ -n "${FX_SLAVE:-}" ] && : > "$d/sys/block/dev0/slaves/sda"
  [ -n "${FX_NOSLAVES:-}" ] && rm -rf "$d/sys/block/dev0/slaves"
  [ -n "${FX_NOSYSFS:-}" ] && rm -rf "$d/sys/block/dev0"
  printf '%s' "$TOKEN_VALUE" > "$d/token"
  md5sum < "$dev" > "$d/dev.md5.before"
  local fixdev; fixdev="$(readlink -f "$dev")" || return 1
  (
    cd "$d" || exit 99
    export STUB_DIR="$d" REAL_BLKID FIX_DEV="$fixdev" HOSTNAME_STUB="$TF_SERVER_NAME" \
           FX_CHILD="${FX_CHILD:-}" FX_MOUNTED="${FX_MOUNTED:-}" BD_MODE="${BD_MODE:-zero}" \
           CURL_RC="${CURL_RC:-0}" CURL_HTTP="${CURL_HTTP:-}" CURL_OK_FIRST="${CURL_OK_FIRST:-}" \
           BLKID_FORCE_TYPE="${BLKID_FORCE_TYPE:-}" BLKID_FORCE_RC="${BLKID_FORCE_RC:-}" \
           BLKID_FORCE_RC_AFTER="${BLKID_FORCE_RC_AFTER:-}"
    [ -n "${LATE_HOLDER_T:-}" ] && export LATE_HOLDER="$d/sys/block/dev0/holders/dm-0"
    [ -n "${LATE_MOUNT_T:-}" ] && export LATE_MOUNT=1
    export WIPE_T_SEAMS=1 WIPE_T_BYID_DIR="$d/byid" WIPE_T_SYSFS="$d/sys" WIPE_T_TOKEN_FILE="$d/token" \
           WIPE_T_INGEST_URL="https://ingest.invalid/" WIPE_T_LOG_FILE="$d/wipe.log" \
           WIPE_T_WAIT_MAX="${WAIT_MAX_T:-4}" WIPE_T_WAIT_STEP=1 WIPE_T_POST_TRIES="${POST_TRIES_T:-}"
    [ -n "${PROD_URL:-}" ] && unset WIPE_T_INGEST_URL
    [ -n "${NO_SEAMS:-}" ] && unset WIPE_T_SEAMS
    PATH="$W/bin:$PATH" timeout 120 bash "$script" > "$d/out" 2>&1
    echo $? > "$d/rc"
  )
  [ -s "$d/rc" ] || return 1
  md5sum < "$dev" > "$d/dev.md5.after"
}

# ---- observation helpers --------------------------------------------------------------------------
sdir() { printf '%s/s/%s' "$W" "$1"; }
rc_of() { cat "$(sdir "$1")/rc"; }
n_discards() { local f; f="$(sdir "$1")/blkdiscard.log"; if [ -s "$f" ]; then wc -l < "$f"; else echo 0; fi; }
# rows_of <name>: every DELIVERED row (curl rc 0), in call order.
rows_of() {
  local d i n; d="$(sdir "$1")"; n="$(cat "$d/curl.n" 2>/dev/null || echo 0)"
  for ((i = 1; i <= n; i++)); do
    [ -f "$d/payload.$i.ok" ] && jq -r '.message' "$d/payload.$i.ok"
  done
}
fld() { printf '%s\n' "$1" | tr ' ' '\n' | sed -n "s/^$2=//p" | head -1; }
last_row() { rows_of "$1" | tail -1; }
first_row() { rows_of "$1" | head -1; }
# first_field_is / last_field_is <scenario> <field> <value>: a key=value field of the first/last DELIVERED row.
first_field_is() { [ "$(fld "$(first_row "$1")" "$2")" = "$3" ]; }
last_field_is() { [ "$(fld "$(last_row "$1")" "$2")" = "$3" ]; }
# flush_order <scenario>: the first zero precedes the last buffer flush, which precedes the last POST
# (the wiped claim). Line numbers in the shared order log, read with awk (no pipe into a predicate).
flush_order() {
  local o z f c; o="$(sdir "$1")/order.log"
  [ -s "$o" ] || return 1
  z="$(awk '/^blkdiscard/{print NR; exit}' "$o")"
  f="$(awk '/^blockdev --flushbufs/{n=NR} END{print n}' "$o")"
  c="$(awk '/^curl /{n=NR} END{print n}' "$o")"
  [ -n "$z" ] && [ -n "$f" ] && [ -n "$c" ] && [ "$z" -lt "$f" ] && [ "$f" -lt "$c" ]
}
token_removed() { [ ! -e "$(sdir "$1")/token" ]; }
no_badop() { [ ! -e "$(sdir "$1")/badop.log" ]; }
# payload_pin <scenario>: the LAST delivered POST body has exactly the five fields the evidence funnel
# can pin, with the emitter identity (host = the .tf server name, shipper) and a well-formed dt.
payload_pin() {
  local d n f; d="$(sdir "$1")"; n="$(cat "$d/curl.n" 2>/dev/null || echo 0)"; f=""
  while [ "$n" -ge 1 ]; do [ -f "$d/payload.$n.ok" ] && { f="$d/payload.$n.ok"; break; }; n=$((n - 1)); done
  [ -n "$f" ] || return 1
  jq -e --arg h "$TF_SERVER_NAME" '(keys == ["dt","host","marker","message","shipper"]) and .host == $h and .shipper == "inngest-backstop-wipe" and .marker == "SOLEUR_INNGEST_BACKSTOP_WIPE" and (.dt | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")) and (.message | startswith("SOLEUR_INNGEST_BACKSTOP_WIPE result="))' "$f" >/dev/null
}
# post_target_is_literal <scenario> <script>: the first POST went to the script's own INGEST_URL literal, https.
post_target_is_literal() {
  local d u l; d="$(sdir "$1")"
  u="$(sed -nE 's/.* -X POST ([^ ]+) -H .*/\1/p' "$d/curl.argv" | head -1)"; l="$(script_literal "$2" INGEST_URL)"
  [ -n "$u" ] && [ "$u" = "$l" ] || return 1
  case "$u" in https://?*) return 0 ;; esac
  return 1
}
dev_unchanged() { local d; d="$(sdir "$1")"; [ "$(cat "$d/dev.md5.before")" = "$(cat "$d/dev.md5.after")" ]; }
dev_all_zero() {
  local d size; d="$(sdir "$1")"; size="$(stat -c %s "$d/dev0")"
  head -c "$size" /dev/zero | cmp -s - "$d/dev0"
}

# Properties. Each returns 0 when the property HOLDS, so a mutation row asserts it does NOT.
prop_happy() { # $1 name, $2 expected size, optional $3 expected uuid
  local n="$1" size="$2" r f
  [ "$(rc_of "$n")" = 0 ] || return 1
  [ "$(rows_of "$n" | wc -l)" = 2 ] || return 1
  r="$(first_row "$n")"; [ "$(fld "$r" result)" = started ] || return 1
  [ "$(fld "$r" fs_uuid)" = "$FIX_UUID" ] || return 1
  f="$(last_row "$n")"
  [ "$(fld "$f" result)" = wiped ] && [ "$(fld "$f" readback)" = zero ] && [ "$(fld "$f" sig_after)" = none ] || return 1
  [ "$(fld "$f" nonce)" = "$NONCE" ] && [ "$(fld "$f" volume_id)" = "$PINNED_ID" ] && [ "$(fld "$f" size_bytes)" = "$size" ] || return 1
  [ "$(fld "$f" fs_uuid)" = "$FIX_UUID" ] || return 1
  case "$(fld "$f" last_write)" in 20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]T*Z) ;; *) return 1 ;; esac
  [ "$(n_discards "$n")" = 1 ] || return 1
  dev_all_zero "$n"
}
prop_refused() { # $1 name, $2 reason : refused row names the reason, nothing written, no wiped row
  local n="$1" r f
  [ "$(rc_of "$n")" != 0 ] || return 1
  f="$(last_row "$n")"
  [ "$(fld "$f" result)" = refused ] && [ "$(fld "$f" reason)" = "$2" ] || return 1
  [ "$(fld "$f" nonce)" = "$NONCE" ] || return 1
  ! grep -q 'result=wiped' <<<"$(rows_of "$n")" || return 1
  [ "$(n_discards "$n")" = 0 ] && dev_unchanged "$n"
}
prop_no_write() { # nothing written at all, no wiped row, non-zero exit
  local n="$1"
  [ "$(rc_of "$n")" != 0 ] || return 1
  [ "$(n_discards "$n")" = 0 ] && dev_unchanged "$n" || return 1
  ! grep -q 'result=wiped' <<<"$(rows_of "$n")"
}
prop_refused_after_write() { # zero/readback/signature failure: a write happened, but no wiped claim
  local n="$1" f
  [ "$(rc_of "$n")" != 0 ] || return 1
  f="$(last_row "$n")"
  [ "$(fld "$f" result)" = refused ] && [ "$(fld "$f" reason)" = "$2" ] || return 1
  ! grep -q 'result=wiped' <<<"$(rows_of "$n")"
}

# ---- scenarios: the canonical happy path and every refusal ------------------------------------------
scenario happy "$GOOD" || { printf 'FATAL: happy scenario setup failed\n' >&2; exit 2; }
check "happy: ext4 -> started then wiped, zero read-back, no signature, identity captured, one discard, device all-zero" prop_happy happy "$SIZE_A"
check "happy: a flush follows the zero" bash -c "grep -q -- '--flushbufs' '$(sdir happy)/blockdev.log'"
check "happy: the started row carries no readback claim" bash -c "[ -z \"$(fld "$(first_row happy)" readback)\" ]"
check "happy: the token reached curl on stdin as an Authorization header" \
  grep -qF "header = \"Authorization: Bearer $TOKEN_VALUE\"" "$(sdir happy)/curl.stdin.1"
check_not "happy: the token never appears on curl's argv" grep -q "$TOKEN_VALUE" "$(sdir happy)/curl.argv"
check_not "happy: the token never appears in any posted row or the script log" \
  bash -c "grep -rq '$TOKEN_VALUE' '$(sdir happy)'/payload.* '$(sdir happy)/wipe.log' '$(sdir happy)/out'"
check_not "happy: no device bytes in any output (payload marker absent from out, log, rows)" \
  bash -c "grep -rq 'SYNTHETIC-PAYLOAD' '$(sdir happy)/out' '$(sdir happy)/wipe.log' '$(sdir happy)'/payload.*"
check "happy: blkdiscard, then the buffer flush, then the wiped POST (the claim is shipped only after the flush)" flush_order happy
check "happy: the token file is removed on exit (the EXIT trap)" token_removed happy
check "happy: no stub was ever handed a wrong operand (the script queried exactly the resolved device)" no_badop happy
check "happy: the evidence payload carries exactly dt, host, marker, message, shipper; host is the .tf server name, shipper the emitter pin" payload_pin happy
# The production ingest URL (only the URL seam withheld): the POST goes to the script's own https literal.
PROD_URL=1 scenario prod_url "$GOOD" || { printf 'FATAL: prod_url setup failed\n' >&2; exit 2; }
check "prod-url: with every seam but the URL the run is still the canonical happy path" prop_happy prod_url "$SIZE_A"
check "prod-url: the POST target is the script's INGEST_URL literal, and it is https" post_target_is_literal prod_url "$GOOD"

# Non-canonical must-PASS: a different valid size supplied through the size variable.
RENDER_B="$W/render-b.sh"; render_script "$RENDER_B" "$PINNED_ID" "$SIZE_B" "$NONCE" || exit 2
FX_SIZE=$SIZE_B scenario size_b "$RENDER_B" || { printf 'FATAL: size_b setup failed\n' >&2; exit 2; }
check "must-pass non-canonical: a 12 MiB device with a matching expected size is wiped" prop_happy size_b "$SIZE_B"

# Refusals.
FX_KIND=luks scenario luks "$GOOD" || exit 2
check "refuse: crypto_LUKS -> refused reason=luks_signature, no write, device untouched" prop_refused luks luks_signature
FX_KIND=ext2 scenario ext2 "$GOOD" || exit 2
check "refuse: any other filesystem type -> refused reason=type_not_ext4, no write" prop_refused ext2 type_not_ext4
FX_GROW=1 scenario size_plus1 "$GOOD" || exit 2
check "refuse: size differs by ONE byte -> refused reason=size_mismatch, no write" prop_refused size_plus1 size_mismatch
FX_SIZE=$((SIZE_A - 512)) scenario size_short "$GOOD" || exit 2
check "refuse: smaller device -> refused reason=size_mismatch, no write" prop_refused size_short size_mismatch
LSBLK_TYPE=part scenario not_disk "$GOOD" || exit 2
check "refuse: lsblk reports a partition, not a whole disk -> refused reason=not_whole_disk" prop_refused not_disk not_whole_disk
FX_MOUNTED=1 scenario mounted "$GOOD" || exit 2
check "refuse: mounted -> refused reason=mounted, no write" prop_refused mounted mounted
FX_CHILD=1 scenario child "$GOOD" || exit 2
check "refuse: partitions/children present -> refused reason=has_children, no write" prop_refused child has_children
FX_HOLDER=1 scenario holder "$GOOD" || exit 2
check "refuse: sysfs holder present -> refused reason=has_holders, no write" prop_refused holder has_holders
FX_NOSYSFS=1 scenario nosysfs "$GOOD" || exit 2
check "refuse: sysfs entry absent fails CLOSED -> refused reason=sysfs_absent, no write" prop_refused nosysfs sysfs_absent
FX_OTHER=1 scenario other_vol "$GOOD" || exit 2
check "refuse: the pinned device plus a second attached volume (second member after a compliant first) -> other_volume_attached" prop_refused other_vol other_volume_attached
FX_NODEV=1 scenario absent "$GOOD" || exit 2
check "refuse: device never appears -> bounded wait then refused reason=device_absent" prop_refused absent device_absent
check "wait: the loop is bounded (sleep calls == WAIT_MAX/WAIT_STEP, not unbounded)" \
  bash -c "[ \"\$(wc -l < '$(sdir absent)/sleep.log')\" = 4 ]"
RENDER_ID="$W/render-id.sh"; render_script "$RENDER_ID" "$LIVE_LUKS_ID" "$SIZE_A" "$NONCE" || exit 2
FX_BYID_ID=$LIVE_LUKS_ID scenario wrong_id "$RENDER_ID" || exit 2
check "refuse: the template carries the LIVE LUKS id instead of the pinned id -> refused reason=config_id_mismatch, no write" prop_refused wrong_id config_id_mismatch
RENDER_NONCE="$W/render-nonce.sh"; render_script "$RENDER_NONCE" "$PINNED_ID" "$SIZE_A" "not-a-run-id" || exit 2
scenario bad_nonce "$RENDER_NONCE" || exit 2
check "refuse: a non-numeric nonce is a config error -> no write" prop_no_write bad_nonce

# Evidence channel down: no write.
CURL_RC=7 scenario no_channel "$GOOD" || exit 2
check "no evidence channel (every POST fails) -> NOTHING is written" prop_no_write no_channel
check "no evidence channel -> the POST was retried a bounded number of times (<= 3 per row)" \
  bash -c "[ \"\$(cat '$(sdir no_channel)/curl.n')\" -le 3 ] && [ \"\$(cat '$(sdir no_channel)/curl.n')\" -ge 1 ]"
CURL_OK_FIRST=1 scenario late_channel "$GOOD" || exit 2
check "channel dies after the started row -> exits non-zero (the wipe happened, the claim could not be delivered)" \
  bash -c "[ \"\$(cat '$(sdir late_channel)/rc')\" != 0 ]"
check_not "channel dies after the started row -> no wiped row is claimed as delivered" bash -c "[ \"\$(cat '$(sdir late_channel)'/payload.*.ok | grep -c 'result=wiped')\" -gt 0 ]"

# Zero / read-back / signature failures.
BD_MODE=partial scenario nonzero_tail "$GOOD" || exit 2
check "read-back: a single non-zero byte in the LAST block -> refused reason=readback_nonzero (never wiped)" prop_refused_after_write nonzero_tail readback_nonzero
check "read-back: that refusal row says readback=nonzero" bash -c "[ \"$(fld "$(last_row nonzero_tail)" readback)\" = nonzero ]"
BD_MODE=noop scenario noop_zero "$GOOD" || exit 2
check "read-back: a zero that did nothing (no-op discard) is caught by the read-back -> readback_nonzero" prop_refused_after_write noop_zero readback_nonzero
BD_MODE=fail scenario discard_fails "$GOOD" || exit 2
check "zero failure: blkdiscard rc!=0 -> refused reason=zero_failed" prop_refused_after_write discard_fails zero_failed
BLKID_FORCE_TYPE=ext4 scenario sig_survives "$GOOD" || exit 2
check "signature: blkid still reports a signature after a clean zero -> refused reason=sig_survived (never wiped)" prop_refused_after_write sig_survives sig_survived

# Idempotent re-entry.
FX_KIND=zero scenario blank "$GOOD" || exit 2
prop_blank() {
  local n=blank f
  [ "$(rc_of $n)" = 0 ] || return 1
  f="$(last_row $n)"
  [ "$(fld "$f" result)" = wiped ] && [ "$(fld "$f" prior)" = blank ] && [ "$(fld "$f" readback)" = zero ] && [ "$(fld "$f" sig_after)" = none ] || return 1
  [ "$(fld "$f" nonce)" = "$NONCE" ] && [ "$(fld "$f" size_bytes)" = "$SIZE_A" ] || return 1
  [ "$(n_discards $n)" = 0 ] && dev_unchanged $n
}
check "idempotent: already blank and all-zero at the expected size -> result=wiped prior=blank, NO second zero" prop_blank
FX_KIND=dirty scenario dirty "$GOOD" || exit 2
prop_dirty() {
  local n=dirty f
  [ "$(rc_of $n)" = 0 ] || return 1
  f="$(last_row $n)"
  [ "$(fld "$f" result)" = wiped ] && [ "$(fld "$f" readback)" = zero ] || return 1
  [ -z "$(fld "$f" prior)" ] || return 1
  [ "$(n_discards $n)" = 1 ] && dev_all_zero $n
}
check "idempotent: no signature but NOT all-zero (damaged superblock) -> zeroed again, then wiped" prop_dirty
FX_KIND=zero FX_GROW=1 scenario blank_wrong_size "$GOOD" || exit 2
check "idempotent: the blank shortcut still enforces the size guard -> refused size_mismatch" prop_refused blank_wrong_size size_mismatch


# ---- the re-guard: the device changes state DURING the started-row round trip ------------------------
# The started row is a network round trip. If the device gains a holder or a mount in that window, the
# identity decision made before it is stale; the second guard_device must refuse before the zero.
LATE_HOLDER_T=1 scenario late_holder "$GOOD" || exit 2
check "re-guard: a holder appearing AFTER the started row -> refused reason=has_holders, zero discards, device untouched" prop_refused late_holder has_holders
check "re-guard: and the started row WAS delivered first (the change landed inside the round trip, not before it)" first_field_is late_holder result started
LATE_MOUNT_T=1 scenario late_mount "$GOOD" || exit 2
check "re-guard: a mount appearing AFTER the started row -> refused reason=mounted, zero discards, device untouched" prop_refused late_mount mounted

# ---- HTTP status: an ANSWERING server that says 503 -------------------------------------------------------
CURL_HTTP=503 scenario http503 "$GOOD" || exit 2
check "http: a 503 from the ingest endpoint (curl -f exits 22) is NOT a delivered row -> NOTHING is written" prop_no_write http503
check "http: a 503 is retried like any failed POST (exactly the 3-try production budget)" \
  bash -c "[ \"\$(cat '$(sdir http503)/curl.n')\" = 3 ]"
# The stub models -f faithfully (so the row above can only fail through the script): exit 22 with -f in
# argv, exit 0 without it, whatever the flag cluster.
STUB_SELF="$W/s/stub-self"; assert_fixture_dir "$STUB_SELF"; mkdir -p "$STUB_SELF" || exit 2
curl_stub_rc() { # <CURL_HTTP> <flags...>
  local h="$1"; shift
  ( export STUB_DIR="$STUB_SELF" CURL_HTTP="$h"; sh "$W/bin/curl" "$@" >/dev/null 2>&1; echo $? )
}
check "stub self-test: CURL_HTTP=503 with -fsS exits 22" test "$(curl_stub_rc 503 -q -fsS -X POST x)" = 22
check "stub self-test: CURL_HTTP=503 with --fail exits 22" test "$(curl_stub_rc 503 -q --fail -X POST x)" = 22
check "stub self-test: CURL_HTTP=503 WITHOUT -f exits 0 (the error body would be 'delivered')" test "$(curl_stub_rc 503 -q -sS --max-time 15 -X POST x)" = 0
check "stub self-test: CURL_HTTP=200 with -fsS exits 0" test "$(curl_stub_rc 200 -q -fsS -X POST x)" = 0
lsblk_stub_rc() { ( export STUB_DIR="$STUB_SELF" FIX_DEV=/fixture/dev0; sh "$W/bin/lsblk" -dnbo TYPE,SIZE "$1" >/dev/null 2>&1; echo $? ); }
check "stub self-test: lsblk fails on any operand but the fixture device" test "$(lsblk_stub_rc /somewhere/else)" != 0
findmnt_stub_out() { ( export STUB_DIR="$STUB_SELF" FIX_DEV=/fixture/dev0; sh "$W/bin/findmnt" -rn -S "$1" 2>/dev/null ); }
check "stub self-test: findmnt answers 'mounted' for any operand but the fixture device" test -n "$(findmnt_stub_out /somewhere/else)"
check "stub self-test: findmnt answers nothing for the fixture device when it is not mounted" test -z "$(findmnt_stub_out /fixture/dev0)"
BDS="$W/s/bd-self"; assert_fixture_dir "$BDS"; mkdir -p "$BDS" || exit 2
bd_run() { # <args...>: a fresh random 1 MiB device, the stub run with <args...> <device>; rc in BD_RC
  local f="$BDS/dev"; assert_fixture_dir "$f"
  head -c 1048576 /dev/urandom > "$f" || return 1
  ( export STUB_DIR="$BDS" FIX_DEV="$f"; sh "$W/bin/blkdiscard" "$@" "$f" >/dev/null 2>&1 ); BD_RC=$?
}
bd_prop_no_z() { bd_run || return 1; [ "$BD_RC" != 0 ] && ! cmp -s -n 4096 "$BDS/dev" /dev/zero; }
bd_prop_full() { bd_run -z || return 1; [ "$BD_RC" = 0 ] && cmp -s -n 1048576 "$BDS/dev" /dev/zero; }
bd_prop_range() { # -z -o 4096 -l 8192: exactly bytes [4096, 12288) are zero
  bd_run -z -o 4096 -l 8192 || return 1
  [ "$BD_RC" = 0 ] && cmp -s -i 4096 -n 8192 "$BDS/dev" /dev/zero \
    && ! cmp -s -n 4096 "$BDS/dev" /dev/zero && ! cmp -s -i 12288 -n 4096 "$BDS/dev" /dev/zero
}
bd_prop_len_only() { # -z --length 4096: the first 4096 bytes only
  bd_run -z --length 4096 || return 1
  [ "$BD_RC" = 0 ] && cmp -s -n 4096 "$BDS/dev" /dev/zero && ! cmp -s -i 4096 -n 4096 "$BDS/dev" /dev/zero
}
check "stub self-test: blkdiscard WITHOUT -z is rejected and writes nothing" bd_prop_no_z
check "stub self-test: blkdiscard -z zeroes the whole device" bd_prop_full
check "stub self-test: blkdiscard -z --offset/--length zeroes exactly that range and nothing else" bd_prop_range
check "stub self-test: blkdiscard -z --length alone zeroes only that many leading bytes" bd_prop_len_only

# ---- sysfs: both holders/ and slaves/ are read, and either missing fails closed ----------------------------
FX_SLAVE=1 scenario slave "$GOOD" || exit 2
check "refuse: a sysfs SLAVE present (holders empty) -> refused reason=has_holders, no write" prop_refused slave has_holders
FX_NOSLAVES=1 scenario noslaves "$GOOD" || exit 2
check "refuse: slaves/ absent (holders/ present) fails CLOSED -> refused reason=sysfs_absent, no write" prop_refused noslaves sysfs_absent

# ---- blkid probe errors that are neither found (0) nor not-found (2) -----------------------------------------
BLKID_FORCE_RC=4 scenario blkid_err_pre "$GOOD" || exit 2
check "refuse: blkid fails with rc 4 before the zero -> refused reason=type_not_ext4, no write" prop_refused blkid_err_pre type_not_ext4
check "refuse: that refusal row names the blkid rc" last_field_is blkid_err_pre blkid_rc 4
BLKID_FORCE_RC_AFTER=4 scenario blkid_err_post "$GOOD" || exit 2
check "signature: blkid fails with rc 4 AFTER the zero (cannot prove no signature) -> refused reason=sig_survived, never wiped" prop_refused_after_write blkid_err_post sig_survived
check "signature: that refusal row names the blkid rc" last_field_is blkid_err_post blkid_rc 4

# ---- the blank shortcut must still exit non-zero when its wiped row cannot be delivered ----------------------
FX_KIND=zero CURL_RC=7 scenario blank_no_channel "$GOOD" || exit 2
prop_blank_no_channel() {
  local n=blank_no_channel
  [ "$(rc_of $n)" != 0 ] || return 1
  [ "$(n_discards $n)" = 0 ] && [ -z "$(rows_of $n)" ]
}
check "blank shortcut: the wiped row cannot be delivered -> exits non-zero (a claim nobody received is not a success), no discard, no row delivered" prop_blank_no_channel

# ---- the token file is removed on a REFUSAL exit too ------------------------------------------------------------
check "refuse: the token file is removed on a refusal exit (the EXIT trap, not just the happy path)" token_removed luks

# ---- POST budget: configurable by seam only ----------------------------------------------------------------------
POST_TRIES_T=1 CURL_RC=7 scenario post_tries_1 "$GOOD" || exit 2
check "post budget: the seam WIPE_T_POST_TRIES=1 makes a failing POST a single attempt" bash -c "[ \"\$(cat '$(sdir post_tries_1)/curl.n')\" = 1 ]"
check "post budget: with no seam the production budget is exactly 3 attempts" bash -c "[ \"\$(cat '$(sdir no_channel)/curl.n')\" = 3 ]"

# ---- production defaults: WIPE_T_* without WIPE_T_SEAMS=1 are IGNORED -----------------------------------------------
[ ! -e "/dev/disk/by-id/scsi-0HC_Volume_$PINNED_ID" ] || { printf 'FIXTURE_UNAVAILABLE: this machine has volume %s attached; the no-seams row would not be a fixture\n' "$PINNED_ID" >&2; exit 2; }
NO_SEAMS=1 scenario no_seams "$GOOD" || exit 2
prop_no_seams_of() {
  local n="$1" d; d="$(sdir "$1")"
  [ "$(rc_of $n)" != 0 ] || return 1
  # defaults: WAIT_MAX=300 / WAIT_STEP=2 -> 150 sleeps (the seam would have made it 4), the real by-id
  # directory (so the fixture device is never found), the real token path (so no token, no POST), and
  # the default log file (so the seam log file is never created).
  [ "$(wc -l < "$d/sleep.log")" = 150 ] || return 1
  [ ! -e "$d/curl.n" ] && [ ! -e "$d/wipe.log" ] || return 1
  [ "$(n_discards $n)" = 0 ] && dev_unchanged $n
}
check "production defaults: WIPE_T_* set WITHOUT WIPE_T_SEAMS=1 are ignored (default wait 150 sleeps, no token, no POST, no seam log, nothing written)" prop_no_seams_of no_seams

# ---- harness rows (the suite must not pass vacuously) --------------------------------------------------
# Pointing the by-id seam at nothing: the canonical row must FAIL (not pass), proving the happy row
# measures the fixture and cannot be satisfied by a refusal path.
FX_NODEV=1 scenario empty_seam "$GOOD" || exit 2
check_not "harness: with the by-id seam pointing at an empty directory the happy-path property FAILS" prop_happy empty_seam "$SIZE_A"
check "harness: the same run is a bounded device_absent refusal, not a hang or a pass" prop_refused empty_seam device_absent
# Positive-work floor: the canonical scenarios together must have executed exactly the expected
# number of discards (1 happy + 1 size_b + 1 nonzero_tail + 1 noop + 1 fail + 1 sig + 1 dirty = 7).
total_discards=0
for s in happy size_b nonzero_tail noop_zero discard_fails sig_survives dirty; do total_discards=$((total_discards + $(n_discards "$s"))); done
check "floor: the canonical write scenarios executed exactly 7 discards in total (a vacuous fixture executes none)" test "$total_discards" = 7

# ---- MUTATION PROOF ---------------------------------------------------------------------------------------
# mutate <label> <sed -E expr> : copy GOOD, apply the expression, assert the bytes changed (the mutation
# LANDED), echo the mutated path. A mutation that did not land is a hard failure of that row.
MUT_N=0
mutate() {
  local label="$1" expr="$2" out before after
  MUT_N=$((MUT_N + 1))
  out="$W/mut/m$MUT_N.sh"
  assert_fixture_dir "$out"
  cp "$GOOD" "$out" || return 1
  before="$(md5sum < "$out")"
  sed -E -i "$expr" "$out" || return 1
  after="$(md5sum < "$out")"
  if [ "$before" = "$after" ]; then fail "mutation LANDED: $label (md5 unchanged: $before)"; return 1; fi
  pass "mutation LANDED: $label (md5 $before -> $after)"
  MUT_PATH="$out"
}
# Self-test of the mutation helper: an expression that matches nothing must be REPORTED as not landed.
_p=$passes; _f=$fails
mutate "self-test: no-op expression" 's/THIS-STRING-IS-NOT-IN-THE-SCRIPT-AT-ALL/x/' >/dev/null 2>&1
if [ "$fails" -ne $((_f + 1)) ]; then printf 'FATAL: mutation helper accepted a mutation that did not land\n' >&2; exit 2; fi
passes=$_p; fails=$_f; executed=$((executed - 1))

# M1: delete the read-back decision (it now always says zero).
mutate "M1 read-back decision replaced by true" 's/^[[:space:]]*\[ "\$DD_RC" = 0 \] && \[ "\$CMP_RC" = 0 \]$/  true/' && {
  BD_MODE=partial scenario m1 "$MUT_PATH" || exit 2
  check_not "M1 (read-back deleted): the non-zero-tail row is RED (wiped is claimed over non-zero bytes)" prop_refused_after_write m1 readback_nonzero
}
# M2: replace the zero with a no-op.
mutate "M2 blkdiscard replaced by a no-op" 's/^([[:space:]]*)blkdiscard -z /\1true /' && {
  scenario m2 "$MUT_PATH" || exit 2
  check_not "M2 (zero is a no-op): the happy row is RED" prop_happy m2 "$SIZE_A"
}
# M3: both - the script now claims wiped over untouched data; the device-zero assertion must catch it.
mutate "M3 no-op zero AND read-back deleted" 's/^([[:space:]]*)blkdiscard -z /\1true /;s/^[[:space:]]*\[ "\$DD_RC" = 0 \] && \[ "\$CMP_RC" = 0 \]$/  true/' && {
  scenario m3 "$MUT_PATH" || exit 2
  check_not "M3 (no-op zero + no read-back): the happy row is RED via the device-is-zero check" prop_happy m3 "$SIZE_A"
}
# M4..M8: drop each identity guard; its refusal row must go RED.
mutate "M4 g_type guard dropped" 's/^g_type\(\) \{$/g_type() { return 0/' && {
  FX_KIND=luks scenario m4 "$MUT_PATH" || exit 2
  check_not "M4 (type guard dropped): the crypto_LUKS refusal row is RED" prop_refused m4 luks_signature
  check_not "M4: and the discard actually ran against the LUKS fixture (the guard was the only barrier)" prop_no_write m4
}
mutate "M5 g_size guard dropped" 's/^g_size\(\) \{$/g_size() { return 0/' && {
  FX_GROW=1 scenario m5 "$MUT_PATH" || exit 2
  check_not "M5 (size guard dropped): the one-byte size row is RED" prop_refused m5 size_mismatch
}
mutate "M6 g_mounted guard dropped" 's/^g_mounted\(\) \{$/g_mounted() { return 0/' && {
  FX_MOUNTED=1 scenario m6 "$MUT_PATH" || exit 2
  check_not "M6 (mounted guard dropped): the mounted row is RED" prop_refused m6 mounted
}
mutate "M7 g_holders guard dropped" 's/^g_holders\(\) \{$/g_holders() { return 0/' && {
  FX_HOLDER=1 scenario m7 "$MUT_PATH" || exit 2
  check_not "M7 (holders guard dropped): the holder row is RED" prop_refused m7 has_holders
}
mutate "M8 g_single guard dropped" 's/^g_single\(\) \{$/g_single() { return 0/' && {
  FX_OTHER=1 scenario m8 "$MUT_PATH" || exit 2
  check_not "M8 (second-volume guard dropped): the second-volume row is RED" prop_refused m8 other_volume_attached
}
# M9: the pinned-id comparison dropped.
mutate "M9 pinned-id comparison dropped" 's/^(\[ "\$VOLUME_ID" = "\$PINNED_ID" \]) \|\| /true || /' && {
  # re-render the mutated script with the live id (the mutation was applied to the pinned-id render)
  RENDER_M9="$W/mut/m9-live.sh"
  assert_fixture_dir "$RENDER_M9"
  sed -E 's/^VOLUME_ID='"'$PINNED_ID'"'/VOLUME_ID='"'$LIVE_LUKS_ID'"'/' "$MUT_PATH" > "$RENDER_M9"
  check "M9: the live-id re-render of the mutated script differs from the mutated script" bash -c "! cmp -s '$MUT_PATH' '$RENDER_M9'"
  FX_BYID_ID=$LIVE_LUKS_ID scenario m9 "$RENDER_M9" || exit 2
  check_not "M9 (pinned-id check dropped): the live-LUKS-id row is RED" prop_refused m9 config_id_mismatch
}
# M10: move the wipe above the guard.
mutate "M10 wipe_device called before guard_device" 's/^guard_device$/wipe_device; guard_device/' && {
  FX_KIND=luks scenario m10 "$MUT_PATH" || exit 2
  check_not "M10 (wipe moved above the guard): a refusal fixture shows a write happened (LUKS row RED)" prop_refused m10 luks_signature
  check_not "M10: the ordering census is RED on the mutated script" census_guard_before_wipe "$MUT_PATH"
}
# M11: a second blkdiscard call site.
mutate "M11 second blkdiscard call site appended" 's/^(wipe_device\(\) \{)$/\1 blkdiscard -z "$REAL" <\/dev\/null;/' && {
  check_not "M11 (second call site): the call-site census (exactly 1) is RED" census_single_blkdiscard "$MUT_PATH"
}
# M12: the token on argv.
mutate "M12 token moved onto curl's argv" 's/curl -q -K -/curl -q -K - -H "Authorization: Bearer $TOKEN"/' && {
  scenario m12 "$MUT_PATH" || exit 2
  check_not "M12 (token on argv): the token-not-on-argv census is RED" census_token_not_on_argv "$MUT_PATH"
  check "M12: and the run really put the token on curl's argv (behavioural proof the row can fail)" grep -q "$TOKEN_VALUE" "$(sdir m12)/curl.argv"
}
# M12b: SIGPIPE-proof (deterministic). A token-on-argv curl sits EARLY in a script padded far past the
# 64 KiB pipe buffer, and the legitimate `curl -q -K -` line sits LAST. A predicate that pipes the script
# into `grep -q` then sees the second grep exit on the early bad line while the producer is still
# writing: under pipefail that is 141, and the negated predicate reads it as "no match" and fails OPEN
# (measured 30/30 with the pipe form, 0/30 with the herestring form). The census must stay RED.
mutate "M12b placeholder to reuse the landed-mutation accounting" 's/curl -q -K -/curl -q -K - -H "Authorization: Bearer $TOKEN"/' && {
  _big="$W/mut/m12b-big.sh"
  assert_fixture_dir "$_big"
  { printf '#!/usr/bin/env bash\ncurl -q -H "Authorization: Bearer $TOKEN" x\n'
    _i=0; while [ "$_i" -lt 4000 ]; do printf ': padding line %s to push the script past the pipe buffer padding padding\n' "$_i"; _i=$((_i + 1)); done
    printf 'curl -q -K - x\n'; } > "$_big"
  check "M12b: the padded script really exceeds the 64 KiB pipe buffer" bash -c "[ \"\$(wc -c < '$_big')\" -gt 70000 ]"
  check_not "M12b (token on argv early, legitimate curl last, padded): the census is still RED" census_token_not_on_argv "$_big"
}
# M13: the signature check removed.
mutate "M13 post-zero signature check dropped" 's/^g_sig_after\(\) \{$/g_sig_after() { return 0/' && {
  BLKID_FORCE_TYPE=ext4 scenario m13 "$MUT_PATH" || exit 2
  check_not "M13 (signature check dropped): the surviving-signature row is RED" prop_refused_after_write m13 sig_survived
}
# M14: the started-row gate ignored (write even if the evidence channel is down).
mutate "M14 started-row delivery ignored" 's/\|\| no_evidence_channel$/|| true/' && {
  CURL_RC=7 scenario m14 "$MUT_PATH" || exit 2
  check_not "M14 (started delivery ignored): the no-evidence-channel row is RED (a write happened blind)" prop_no_write m14
}
# M15: cmp -l reintroduced.
mutate "M15 cmp -l reintroduced" 's/cmp -n /cmp -l -n /' && {
  check_not "M15 (cmp -l): the read-back census (no cmp -l/-b) is RED" census_no_cmp_l_or_b "$MUT_PATH"
}
# M16: dd write primitive reintroduced.
mutate "M16 an extra dd of= writer appended" 's/^(wipe_device\(\) \{)$/\1 dd if=\/dev\/zero of="$REAL" bs=4M;/' && {
  check_not "M16 (dd of= writer): the other-writers census is RED" census_no_other_writers "$MUT_PATH"
}

# M17: the zero call loses -z (a plain discard; the stub rejects it, the census pins the exact call).
mutate "M17 blkdiscard loses -z" 's/^([[:space:]]*)blkdiscard -z "\$REAL"/\1blkdiscard "$REAL"/' && {
  scenario m17 "$MUT_PATH" || exit 2
  check_not "M17 (no -z): the happy row is RED" prop_happy m17 "$SIZE_A"
  check_not "M17: the exact-call census is RED" census_blkdiscard_exact "$MUT_PATH"
}
# M18: the zero call is narrowed to the first 4 KiB (a partial zero that would leave the payload).
mutate "M18 blkdiscard narrowed to --length 4096" 's/^([[:space:]]*)blkdiscard -z "\$REAL"/\1blkdiscard -z -o 0 -l 4096 "$REAL"/' && {
  scenario m18 "$MUT_PATH" || exit 2
  check_not "M18 (partial zero): the happy row is RED (the stub zeroed only the range it was given)" prop_happy m18 "$SIZE_A"
  check_not "M18: the exact-call census is RED" census_blkdiscard_exact "$MUT_PATH"
}
# M19: curl loses -f (an HTTP error status would count as delivered).
mutate "M19 curl loses -f" 's/ -fsS / -sS /' && {
  CURL_HTTP=503 scenario m19 "$MUT_PATH" || exit 2
  check_not "M19 (no -f): the 503 row is RED (a 503 is taken for a delivered started row and the zero runs)" prop_no_write m19
  check_not "M19: the curl -f census is RED" census_curl_fail_flag "$MUT_PATH"
}
# M20: curl loses its time bound.
mutate "M20 curl loses --max-time" 's/ --max-time [0-9]+//' && {
  check_not "M20 (no --max-time): the curl time-bound census is RED" census_curl_max_time "$MUT_PATH"
}
mutate "M20b curl --max-time becomes unbounded (0)" 's/--max-time 15 /--max-time 0 /' && {
  check_not "M20b (--max-time 0): the exact time-bound census is RED" census_curl_max_time "$MUT_PATH"
}
# M21: the re-guard after the started row removed.
mutate "M21 re-guard after the started row removed" '/\|\| no_evidence_channel$/{n;s/^guard_device$/true/}' && {
  LATE_HOLDER_T=1 scenario m21 "$MUT_PATH" || exit 2
  check_not "M21 (no re-guard): the late-holder row is RED (the zero ran against a device that gained a holder)" prop_refused m21 has_holders
  LATE_MOUNT_T=1 scenario m21b "$MUT_PATH" || exit 2
  check_not "M21: the late-mount row is RED too" prop_refused m21b mounted
  check_not "M21: the two-guards census is RED" census_reguard_before_wipe "$MUT_PATH"
}
# M22/M23: a probe handed the wrong operand (the by-id DIRECTORY instead of the resolved device).
mutate "M22 findmnt queried with the by-id directory" 's/findmnt -rn -S "\$REAL"/findmnt -rn -S "$BYID_DIR"/' && {
  scenario m22 "$MUT_PATH" || exit 2
  check_not "M22 (findmnt wrong operand): the happy row is RED (the strict stub refuses a wrong operand)" prop_happy m22 "$SIZE_A"
}
mutate "M23 lsblk queried with the by-id directory" 's/lsblk -dnbo TYPE,SIZE "\$REAL"/lsblk -dnbo TYPE,SIZE "$BYID_DIR"/' && {
  scenario m23 "$MUT_PATH" || exit 2
  check_not "M23 (lsblk wrong operand): the happy row is RED" prop_happy m23 "$SIZE_A"
}
# M24a-d: reject-controls for the census predicates (each must be able to go RED).
mutate "M24a a second wipe_device call appended" 's/^(wipe_device \|\| refuse zero_failed.*)$/\1\nwipe_device/' && {
  check_not "M24a (second wipe_device call): census_wipe_called_once is RED" census_wipe_called_once "$MUT_PATH"
}
mutate "M24b the O_DIRECT flag removed from the read-back" 's/ iflag=direct//' && {
  check_not "M24b (buffered read-back): census_readback_o_direct is RED" census_readback_o_direct "$MUT_PATH"
}
mutate "M24c set -e added" 's/^LC_ALL=C; export LC_ALL$/set -e; LC_ALL=C; export LC_ALL/' && {
  check_not "M24c (set -e): census_no_set_e is RED" census_no_set_e "$MUT_PATH"
}
mutate "M24d the blkdiscard moved out of wipe_device" 's/^wipe_device\(\) \{$/wipe_dev_x() {/' && {
  check_not "M24d (call site outside wipe_device): census_blkdiscard_in_wipe_fn is RED" census_blkdiscard_in_wipe_fn "$MUT_PATH"
}
# M25a/b: an unexpected blkid rc is no longer refused.
mutate "M25a g_type accepts an unexpected blkid rc as blank" 's/^( *)\*\) refuse type_not_ext4 "blkid_rc=\$brc" "type=\$t" ;;$/\1*) SIGSTATE=none ;;/' && {
  BLKID_FORCE_RC=4 scenario m25a "$MUT_PATH" || exit 2
  check_not "M25a (unexpected rc taken as blank): the blkid-rc-4 pre-zero row is RED" prop_refused m25a type_not_ext4
}
mutate "M25b g_sig_after accepts any rc" 's/if \[ "\$brc" != 2 \] \|\| \[ -n "\$t" \]; then/if [ -n "$t" ]; then/' && {
  BLKID_FORCE_RC_AFTER=4 scenario m25b "$MUT_PATH" || exit 2
  check_not "M25b (rc ignored after the zero): the blkid-rc-4 post-zero row is RED" prop_refused_after_write m25b sig_survived
}
# M26: the flush moved before the zero.
mutate "M26 flush moved before the zero" 's/^([[:space:]]*)blkdiscard -z "\$REAL" <\/dev\/null$/\1blockdev --flushbufs "$REAL" >\/dev\/null 2>\&1; blkdiscard -z "$REAL" <\/dev\/null/;s/^([[:space:]]*)blockdev --flushbufs "\$REAL" >\/dev\/null 2>&1$/\1:/' && {
  scenario m26 "$MUT_PATH" || exit 2
  check_not "M26 (flush before the zero): the flush-ordering row is RED" flush_order m26
}
# M27: the token-file removal trap deleted.
mutate "M27 token-file removal trap deleted" 's/^trap .rm -f "\$TOKEN_FILE". EXIT$/:/' && {
  scenario m27 "$MUT_PATH" || exit 2
  check_not "M27 (no trap): the token-removed row is RED" token_removed m27
}
# M28: the blank shortcut stops failing when its row cannot be delivered.
mutate "M28 blank-shortcut || exit 1 dropped" 's/^( *emit wiped prior=blank .*) \|\| exit 1$/\1/' && {
  FX_KIND=zero CURL_RC=7 scenario m28 "$MUT_PATH" || exit 2
  check_not "M28 (|| exit 1 dropped): the blank-shortcut undeliverable row is RED (exit 0 over an undelivered claim)" bash -c "[ \"\$(cat '$(sdir m28)/rc')\" != 0 ]"
}
# M29/M30: the slaves/ arms.
mutate "M29 slaves/ no longer scanned" 's/ "\$SYSFS\/block\/\$b\/slaves" -mindepth/ -mindepth/' && {
  FX_SLAVE=1 scenario m29 "$MUT_PATH" || exit 2
  check_not "M29 (slaves ignored): the slave row is RED" prop_refused m29 has_holders
}
mutate "M30 slaves/ absence no longer fails closed" 's/ \|\| \[ ! -d "\$SYSFS\/block\/\$b\/slaves" \]//' && {
  FX_NOSLAVES=1 scenario m30 "$MUT_PATH" || exit 2
  check_not "M30 (slaves/ absence tolerated): the no-slaves row is RED" prop_refused m30 sysfs_absent
}
# M31: the POST-budget seam is not honoured.
mutate "M31 WIPE_T_POST_TRIES seam not honoured" 's/^( *)\[ -n "\$WIPE_T_POST_TRIES" \] && POST_TRIES="\$WIPE_T_POST_TRIES"$/\1:/' && {
  POST_TRIES_T=1 CURL_RC=7 scenario m31 "$MUT_PATH" || exit 2
  check_not "M31 (seam ignored): the single-attempt seam row is RED" bash -c "[ \"\$(cat '$(sdir m31)/curl.n')\" = 1 ]"
}
# M32: the seams honoured without WIPE_T_SEAMS=1 (the production script would obey an environment variable).
mutate "M32 seams honoured unconditionally" 's/^if \[ "\$WIPE_T_SEAMS" = 1 \]; then$/if true; then/' && {
  NO_SEAMS=1 scenario m32 "$MUT_PATH" || exit 2
  check_not "M32 (seams always on): the production-defaults row is RED" prop_no_seams_of m32
}
# M33/M34: the production literals.
mutate "M33 TOKEN_FILE literal diverges from the write_files path" 's|^TOKEN_FILE=/run/inngest-backstop-wipe\.token$|TOKEN_FILE=/run/other.token|' && {
  check_not "M33 (token path drift): the token-path parity census is RED" census_token_path_parity "$MUT_PATH"
}
mutate "M34 INGEST_URL literal is plain http" 's|^INGEST_URL=https://|INGEST_URL=http://|' && {
  check_not "M34 (http ingest): the https census is RED" census_ingest_https "$MUT_PATH"
}
mutate "M34b production POST budget raised" 's/^POST_TRIES=3$/POST_TRIES=30/' && {
  check_not "M34b (budget raised): the production-budget census is RED" census_post_budget "$MUT_PATH"
}
# M35: the emitter pin (shipper) changed -> the payload pin must notice. A blank run is the cheapest scenario.
mutate "M35 shipper field changed" 's/shipper(.{1,6})inngest-backstop-wipe/shipper\1other-emitter/' && {
  FX_KIND=zero scenario m35 "$MUT_PATH" || exit 2
  check_not "M35 (shipper changed): the payload-pin row is RED" payload_pin m35
}

# ---- Terraform-side mutation rows (every static pin must be able to fail) --------------------------------------
# tf_mut <label> <sed -E expr> <predicate>: mutate a COPY of the .tf, assert the mutation landed, and
# require the pin predicate to go RED on the copy.
tf_mut() {
  local label="$1" expr="$2" pred="$3" out b a
  MUT_N=$((MUT_N + 1)); out="$W/mut/tf$MUT_N.tf"
  assert_fixture_dir "$out"
  cp "$TF" "$out" || return 1
  b="$(md5sum < "$out")"; sed -E -i "$expr" "$out" || return 1; a="$(md5sum < "$out")"
  if [ "$b" = "$a" ]; then fail "mutation LANDED: $label (md5 unchanged)"; return 1; fi
  pass "mutation LANDED: $label"
  check_not "$label: the pin is RED on the mutated copy" "$pred" "$out"
}
tf_name_pin() { tf_pin "$1" "name = \"$TF_SERVER_NAME\""; }
tf_mut "T1 count gate removed" 's/count *= *var\.inngest_backstop_wipe_enabled \? 1 : 0/count = 1/' tf_count_gate
tf_mut "T2 attachment server_id repointed at the live inngest server" 's/hcloud_server\.inngest_backstop_wipe\[0\]\.id/hcloud_server.inngest.id/' tf_server_pin
tf_mut "T3 nonce precondition accepts an empty nonce" 's/\{1,20\}/{0,20}/' tf_nonce_precond
tf_mut "T4 expected size changed" 's/10 \* 1073741824/11 * 1073741824/' tf_size_pin
tf_mut "T5 templatefile nonce entry hard-coded" 's/^( *nonce *= *)var\.inngest_backstop_wipe_nonce/\1"1"/' tf_nonce_entry
tf_mut "T6 volume_id no longer the pinned variable" 's/volume_id( *)= var\.inngest_backstop_volume_id/volume_id\1= 106903269/' tf_volume_pins
tf_mut "T7 server name renamed (the evidence host pin would drift)" 's/name( *)= "soleur-inngest-backstop-wipe"/name\1= "soleur-inngest"/' tf_name_pin
tf_mut "T8 templatefile size entry hard-coded" 's/expected_size_bytes( *)= local\.inngest_backstop_wipe_expected_size_bytes/expected_size_bytes\1= 10737418240/' tf_size_entry
# vars_mut <label> <sed -E expr>: the same on a COPY of variables.tf.
vars_mut() {
  local label="$1" expr="$2" out b a
  MUT_N=$((MUT_N + 1)); out="$W/mut/vars$MUT_N.tf"
  assert_fixture_dir "$out"
  cp "$VARS" "$out" || return 1
  b="$(md5sum < "$out")"; sed -E -i "$expr" "$out" || return 1; a="$(md5sum < "$out")"
  if [ "$b" = "$a" ]; then fail "mutation LANDED: $label (md5 unchanged)"; return 1; fi
  pass "mutation LANDED: $label"
  check_not "$label: the pin is RED on the mutated copy" vpin_vol "$out"
}
vars_mut "V1 volume id validation relaxed to any positive id" 's/var\.inngest_backstop_volume_id == 106261946/var.inngest_backstop_volume_id > 0/'
vars_mut "V2 volume id validation back to a deny-list of the live id" 's/var\.inngest_backstop_volume_id == 106261946/var.inngest_backstop_volume_id != 106903269/'
vars_mut "V3 volume id pinned to a different id" 's/== 106261946/== 106261947/'

# ---- floor, reported with printf + exit (not through the helper it back-stops) --------------------------
printf '\n%s passed, %s failed, %s executed\n' "$passes" "$fails" "$executed"
# Conservation: every verdict is counted exactly once. A neutered pass()/fail() that still moved `executed`
# (or the reverse) breaks the equality and is reported here, not through the helpers it back-stops.
if [ "$((passes + fails))" -ne "$executed" ]; then
  printf 'FAIL - accounting: passes %s + fails %s != executed %s (a verdict was discarded or double-counted)\n' "$passes" "$fails" "$executed" >&2
  exit 1
fi
FLOOR=245
if [ "$executed" -lt "$FLOOR" ]; then
  printf 'FAIL - assertion-count floor: executed %s < %s (a vacuous or truncated run)\n' "$executed" "$FLOOR" >&2
  exit 1
fi
# Optional rows (shellcheck, terraform templatefile parity) are outside the floor and outside the
# counted verdicts, but a FAILING optional row still fails the run.
if [ "$opt_ran" -gt 0 ]; then printf '%s optional row(s) ran (not counted toward the floor), %s failed\n' "$opt_ran" "$opt_fails"; fi
if [ "$opt_fails" -ne 0 ]; then exit 1; fi
if [ "$fails" -ne 0 ]; then exit 1; fi
exit 0
