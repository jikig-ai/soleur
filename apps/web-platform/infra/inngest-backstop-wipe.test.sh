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
W=""
for base in "$TMPDIR" /var/tmp "$SCRIPT_DIR"; do
  [ -d "$base" ] || continue
  cand="$(mktemp -d "$base/backstop-wipe-test.XXXXXXXX")" || continue
  head -c 8192 /dev/zero > "$cand/probe" 2>/dev/null
  if dd if="$cand/probe" iflag=direct bs=4096 count=1 of=/dev/null status=none 2>/dev/null; then W="$cand"; break; fi
  rm -rf "$cand"
done
[ -n "$W" ] || { printf 'FIXTURE_UNAVAILABLE: no scratch directory supports O_DIRECT reads\n' >&2; exit 2; }
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
  extract_script \
    | sed -E -e "s/(^|[^\$])\\\$\\{volume_id\\}/\\1$vid/g" \
            -e "s/(^|[^\$])\\\$\\{expected_size_bytes\\}/\\1$size/g" \
            -e "s/(^|[^\$])\\\$\\{nonce\\}/\\1$nonce/g" \
    | sed -e 's/\$\${/${/g' > "$out"
  [ -s "$out" ]
}

RAW="$W/raw.sh"
extract_script > "$RAW"
check "extraction: the script body was recovered from write_files (non-empty, shebang)" \
  bash -c "[ -s '$RAW' ] && head -1 '$RAW' | grep -q '^#!/usr/bin/env bash'"
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
  check "render: shellcheck -S warning is clean on the rendered script" shellcheck -S warning -s bash "$GOOD"
else
  printf 'note - shellcheck not installed; lint row not counted\n'
fi
# The sed render above is the harness's own model of templatefile(). Where terraform is available,
# prove the model against the real thing: the script rendered by terraform must be byte-identical.
if command -v terraform >/dev/null 2>&1 && python3 -I -c "import yaml" >/dev/null 2>&1; then
  TFR="$W/tf-render"; mkdir -p "$TFR"
  ( cd "$TFR" && printf 'jsonencode(templatefile("%s", {volume_id=%s, expected_size_bytes=%s, nonce="%s", betterstack_logs_token="synthTok123"}))\n' \
      "$YML" "$PINNED_ID" "$SIZE_A" "$NONCE" | terraform console 2>/dev/null \
    | python3 -I -c 'import sys,json,yaml; d=yaml.safe_load(json.loads(json.loads(sys.stdin.read().strip()))); sys.stdout.write([f for f in d["write_files"] if f["path"].endswith(".sh")][0]["content"])' > "$TFR/script.sh" )
  check "render: terraform's own templatefile() output is byte-identical to the harness render" cmp -s "$TFR/script.sh" "$GOOD"
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
  ! code_lines "$1" | grep -qE 'wipefs|shred|sgdisk|sfdisk|parted|mkfs|cryptsetup|truncate|dd[[:space:]][^|]*of=|>[[:space:]]*("?\$REAL|/dev/(sd|vd|nvme|disk|loop|mapper|xvd))|tee[[:space:]]+/dev/(sd|vd|nvme|disk|loop|mapper|xvd)'
}
census_no_cmp_l_or_b() { ! code_lines "$1" | grep -qE 'cmp[[:space:]]+(-[a-z]*[lb]|--list|--print-bytes)'; }
census_readback_o_direct() { code_lines "$1" | grep -q 'iflag=direct' && code_lines "$1" | grep -qE 'cmp -n "?\$EXPECTED_SIZE"? - /dev/zero'; }
census_token_not_on_argv() {
  code_lines "$1" | grep -q 'curl -q -K -' && ! code_lines "$1" | grep -qE 'curl[^|]*(Authorization|Bearer|\$TOKEN)'
}
census_no_set_e() { ! code_lines "$1" | grep -qE '^[[:space:]]*set[[:space:]]+-[a-z]*e'; }

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

# ---- template / terraform static rows -------------------------------------------------------------
check_not "yml: no template directive percent-brace anywhere (comments included)" grep -q '%{' "$YML"
check_not "yml: no bare dollar-dollar followed by an identifier/paren/special (bash would read the PID)" \
  grep -qE '\$\$[A-Za-z_(0-9?!#@*-]' "$YML"
check_not "yml: no Doppler token, LUKS key or cryptsetup in any non-comment line (they must never reach this host)" \
  bash -c "grep -vE '^[[:space:]]*#' '$YML' | grep -qiE 'doppler|luks_key|redis_luks|cryptsetup|INNGEST_REDIS'"
check "yml: header is #cloud-config" bash -c "head -1 '$YML' | grep -qx '#cloud-config'"
check "yml: the token file is written 0600 root" \
  bash -c "awk '/^  - path: \/run\/inngest-backstop-wipe\.token\$/{f=1;next} f&&/^  - path: /{f=0} f' '$YML' | grep -qE \"permissions: '0600'\""
check "yml: the script is mode 0700" \
  bash -c "awk '/^  - path: \/usr\/local\/sbin\/inngest-backstop-wipe\.sh\$/{f=1;next} f&&/^  - path: /{f=0} f' '$YML' | grep -qE \"permissions: '0700'\""
check "yml: runcmd runs the script" bash -c "grep -qE '^[[:space:]]*- \[ *bash, */usr/local/sbin/inngest-backstop-wipe\.sh *\]' '$YML'"

yml_keys() { grep -oE '(^|[^$])\$\{[a-z_]+\}' "$YML" | grep -oE '[a-z_]+' | sort -u | tr '\n' ' '; }
tf_keys()  { awk '/templatefile\(.*cloud-init-inngest-backstop-wipe\.yml/{f=1;next} f&&/^[[:space:]]*}\)/{f=0} f' "$TF" | grep -oE '^[[:space:]]*[a-z_]+[[:space:]]*=' | tr -d ' =\t' | sort -u | tr '\n' ' '; }
check "tf: the templatefile map keys equal the yml's interpolation keys exactly ($(yml_keys))" \
  bash -c "[ -n \"\$(printf '%s' '$(tf_keys)')\" ] && [ '$(yml_keys)' = '$(tf_keys)' ]"

tf_code() { grep -vE '^[[:space:]]*#' "$TF"; }
check "tf: server and attachment are both count-gated on inngest_backstop_wipe_enabled" \
  bash -c "[ \"\$(grep -vE '^[[:space:]]*#' '$TF' | grep -c 'count *= *var.inngest_backstop_wipe_enabled ? 1 : 0')\" = 2 ]"
check "tf: server pinned to var.location" bash -c "grep -vE '^[[:space:]]*#' '$TF' | grep -qE '^[[:space:]]*location *= *var\.location'"
check "tf: server uses the existing deny-all firewall" bash -c "grep -vE '^[[:space:]]*#' '$TF' | grep -q 'firewall_ids *= *\[hcloud_firewall.inngest.id\]'"
check "tf: ssh_keys is the existing default key with ignore_changes=[ssh_keys]" \
  bash -c "grep -vE '^[[:space:]]*#' '$TF' | grep -q 'ssh_keys *= *\[hcloud_ssh_key.default.id\]' && grep -vE '^[[:space:]]*#' '$TF' | grep -q 'ignore_changes *= *\[ssh_keys\]'"
check "tf: labels role=inngest-backstop-wipe and ephemeral=true" \
  bash -c "grep -vE '^[[:space:]]*#' '$TF' | grep -q 'role *= *\"inngest-backstop-wipe\"' && grep -vE '^[[:space:]]*#' '$TF' | grep -q 'ephemeral *= *\"true\"'"
check "tf: attachment has automount=false" bash -c "grep -vE '^[[:space:]]*#' '$TF' | grep -qE '^[[:space:]]*automount *= *false'"
check "tf: attachment volume_id comes from the pinned numeric variable" bash -c "grep -vE '^[[:space:]]*#' '$TF' | grep -qE 'volume_id *= *var\.inngest_backstop_volume_id'"
check "tf: the ingest token is the EXISTING variable (no new secret variable)" bash -c "grep -vE '^[[:space:]]*#' '$TF' | grep -q 'betterstack_logs_token *= *var.betterstack_logs_token'"
check_not "tf: the live LUKS volume is never referenced by this file" bash -c "grep -vE '^[[:space:]]*#' '$TF' | grep -qE 'inngest_redis_luks|$LIVE_LUKS_ID'"
check "tf: the user_data is not baked from any Doppler token or LUKS key" \
  bash -c "! grep -vE '^[[:space:]]*#' '$TF' | grep -qiE 'doppler|luks_key|redis_luks_key'"
check "vars: inngest_backstop_wipe_enabled is a bool defaulting to false" \
  bash -c "awk '/^variable \"inngest_backstop_wipe_enabled\"/{f=1} f&&/^}/{f=0} f' '$VARS' | grep -q 'type *= *bool' && awk '/^variable \"inngest_backstop_wipe_enabled\"/{f=1} f&&/^}/{f=0} f' '$VARS' | grep -q 'default *= *false'"
check "vars: inngest_backstop_volume_id is a number defaulting to $PINNED_ID" \
  bash -c "awk '/^variable \"inngest_backstop_volume_id\"/{f=1} f&&/^}/{f=0} f' '$VARS' | grep -q 'type *= *number' && awk '/^variable \"inngest_backstop_volume_id\"/{f=1} f&&/^}/{f=0} f' '$VARS' | grep -qE 'default *= *$PINNED_ID\$'"
check "vars: the volume id variable refuses the live LUKS volume id" \
  bash -c "awk '/^variable \"inngest_backstop_volume_id\"/{f=1} f&&/^}/{f=0} f' '$VARS' | grep -q '$LIVE_LUKS_ID'"
check_not "vars: no new secret variable was added for the wipe (sensitive = true absent in the wipe variable blocks)" \
  bash -c "for v in inngest_backstop_wipe_enabled inngest_backstop_volume_id inngest_backstop_wipe_server_type inngest_backstop_wipe_nonce; do awk -v v=\"\$v\" '\$0 ~ \"^variable \\\"\"v\"\\\"\"{f=1} f&&/^}/{f=0} f' '$VARS'; done | grep -q 'sensitive'"

# ---- fixture machinery ----------------------------------------------------------------------------
# stubs ----------------------------------------------------------------------------------------------
cat > "$W/bin/lsblk" <<'EOF'
#!/bin/sh
echo "lsblk $*" >> "$STUB_DIR/lsblk.log"
dev=""; for a in "$@"; do dev="$a"; done
case "$*" in
  *TYPE,SIZE*) sz="$(stat -L -c %s "$dev")" || exit 1; echo "${LSBLK_TYPE:-disk} $sz" ;;
  *NAME*)      echo "dev0"; [ -n "${FX_CHILD:-}" ] && echo "dev0p1"; exit 0 ;;
esac
exit 0
EOF
cat > "$W/bin/findmnt" <<'EOF'
#!/bin/sh
echo "findmnt $*" >> "$STUB_DIR/findmnt.log"
[ "${FX_MOUNTED:-}" = 1 ] && echo /mnt/stub
exit 0
EOF
cat > "$W/bin/blockdev" <<'EOF'
#!/bin/sh
echo "blockdev $*" >> "$STUB_DIR/blockdev.log"
exit 0
EOF
cat > "$W/bin/sleep" <<'EOF'
#!/bin/sh
echo "sleep $*" >> "$STUB_DIR/sleep.log"
exit 0
EOF
cat > "$W/bin/blkdiscard" <<'EOF'
#!/bin/sh
echo "blkdiscard $*" >> "$STUB_DIR/blkdiscard.log"
dev=""; for a in "$@"; do dev="$a"; done
size="$(stat -L -c %s "$dev")" || exit 1
case "${BD_MODE:-zero}" in
  fail) exit 1 ;;
  noop) exit 0 ;;
  partial)
    truncate -s 0 "$dev" && truncate -s "$size" "$dev" || exit 1
    printf '\001' | dd of="$dev" bs=1 seek=$((size - 1)) conv=notrunc status=none || exit 1 ;;
  *) truncate -s 0 "$dev" && truncate -s "$size" "$dev" || exit 1 ;;
esac
exit 0
EOF
cat > "$W/bin/blkid" <<'EOF'
#!/bin/sh
# Real blkid, except that after a (stub) zero it can be forced to claim a surviving signature.
if [ -n "${BLKID_FORCE_TYPE:-}" ] && [ -s "$STUB_DIR/blkdiscard.log" ]; then echo "$BLKID_FORCE_TYPE"; exit 0; fi
exec "$REAL_BLKID" "$@"
EOF
cat > "$W/bin/curl" <<'EOF'
#!/bin/sh
n=$(( $(cat "$STUB_DIR/curl.n" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$STUB_DIR/curl.n"
printf '%s\n' "$*" >> "$STUB_DIR/curl.argv"
case " $* " in *" -K - "*) cat > "$STUB_DIR/curl.stdin.$n" ;; esac
payload=""; prev=""
for a in "$@"; do [ "$prev" = "-d" ] && payload="$a"; prev="$a"; done
rc="${CURL_RC:-0}"
if [ -n "${CURL_OK_FIRST:-}" ] && [ "$n" -gt "$CURL_OK_FIRST" ]; then rc=7; fi
if [ "$rc" = 0 ]; then printf '%s' "$payload" > "$STUB_DIR/payload.$n.ok"; else printf '%s' "$payload" > "$STUB_DIR/payload.$n.fail"; fi
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
# FX_HOLDER, FX_OTHER, FX_CHILD, FX_NODEV, FX_NOSYSFS, BD_MODE, CURL_RC, CURL_OK_FIRST,
# BLKID_FORCE_TYPE, WAIT_MAX_T, EXP_SIZE (no effect on the script: it is rendered by the caller).
# Results: $W/s/<name>/{rc,out,dev.md5.before,dev.md5.after}.
scenario() {
  local script="$2" d="$W/s/$1"
  local kind="${FX_KIND:-ext4}" size="${FX_SIZE:-$SIZE_A}"
  rm -rf "$d"; mkdir -p "$d/byid" "$d/sys/block/dev0/holders" "$d/sys/block/dev0/slaves" || return 1
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
  [ -n "${FX_NOSYSFS:-}" ] && rm -rf "$d/sys/block/dev0"
  printf '%s' "$TOKEN_VALUE" > "$d/token"
  md5sum < "$dev" > "$d/dev.md5.before"
  (
    cd "$d" || exit 99
    export STUB_DIR="$d" REAL_BLKID FX_CHILD="${FX_CHILD:-}" FX_MOUNTED="${FX_MOUNTED:-}" BD_MODE="${BD_MODE:-zero}" \
           CURL_RC="${CURL_RC:-0}" CURL_OK_FIRST="${CURL_OK_FIRST:-}" BLKID_FORCE_TYPE="${BLKID_FORCE_TYPE:-}"
    export WIPE_T_SEAMS=1 WIPE_T_BYID_DIR="$d/byid" WIPE_T_SYSFS="$d/sys" WIPE_T_TOKEN_FILE="$d/token" \
           WIPE_T_INGEST_URL="https://ingest.invalid/" WIPE_T_LOG_FILE="$d/wipe.log" \
           WIPE_T_WAIT_MAX="${WAIT_MAX_T:-4}" WIPE_T_WAIT_STEP=1
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
  ! rows_of "$n" | grep -q 'result=wiped' || return 1
  [ "$(n_discards "$n")" = 0 ] && dev_unchanged "$n"
}
prop_no_write() { # nothing written at all, no wiped row, non-zero exit
  local n="$1"
  [ "$(rc_of "$n")" != 0 ] || return 1
  [ "$(n_discards "$n")" = 0 ] && dev_unchanged "$n" || return 1
  ! rows_of "$n" | grep -q 'result=wiped'
}
prop_refused_after_write() { # zero/readback/signature failure: a write happened, but no wiped claim
  local n="$1" f
  [ "$(rc_of "$n")" != 0 ] || return 1
  f="$(last_row "$n")"
  [ "$(fld "$f" result)" = refused ] && [ "$(fld "$f" reason)" = "$2" ] || return 1
  ! rows_of "$n" | grep -q 'result=wiped'
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
check "happy: the POST targets https" grep -q 'https://' "$(sdir happy)/curl.argv"

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
check_not "channel dies after the started row -> no wiped row is claimed as delivered" bash -c "cat '$(sdir late_channel)'/payload.*.ok | grep -q 'result=wiped'"

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

# ---- Terraform-side mutation rows (static scans must be able to fail) -------------------------------------
TFM="$W/mut/tf-mutated.tf"
cp "$TF" "$TFM" && b="$(md5sum < "$TFM")" && sed -E -i 's/count *= *var\.inngest_backstop_wipe_enabled \? 1 : 0/count = 1/' "$TFM" && a="$(md5sum < "$TFM")"
check "T1 mutation LANDED: count gate removed from the .tf copy" test "$b" != "$a"
check_not "T1 (count gate removed): the count-gate scan is RED on the mutated copy" \
  bash -c "[ \"\$(grep -vE '^[[:space:]]*#' '$TFM' | grep -c 'count *= *var.inngest_backstop_wipe_enabled ? 1 : 0')\" = 2 ]"

# ---- floor, reported with printf + exit (not through the helper it back-stops) --------------------------
FLOOR=115
printf '\n%s passed, %s failed, %s executed (floor %s)\n' "$passes" "$fails" "$executed" "$FLOOR"
if [ "$executed" -lt "$FLOOR" ]; then
  printf 'FAIL - assertion-count floor: executed %s < %s (a vacuous or truncated run)\n' "$executed" "$FLOOR" >&2
  exit 1
fi
if [ "$fails" -ne 0 ]; then exit 1; fi
exit 0
