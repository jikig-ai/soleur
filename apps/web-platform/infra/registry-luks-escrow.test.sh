#!/usr/bin/env bash
# Guard 5 (#8408 (c)): the registry escrow result is honest and keyless.
#
# PROPERTY. store_escrow=ok is written only when `cryptsetup luksOpen --test-passphrase` exited 0
# with the Doppler-held key, against the device backing /var/lib/zot, after the header and memory
# pre-checks passed. The key never leaves the process: not in the state file, not on stdout or
# stderr, not in any argv.
#
# ASSEMBLY. The producer (registry-luks-escrow.sh, run by its cron line and a backgrounded runcmd
# call), the one channel (the state file) and the one consumer (the heartbeat reader, whose cases
# live in zot-disk-heartbeat-redaction.test.sh). This suite extracts the producer from the
# template, renders it the way templatefile does, re-roots its literal paths with sed (the same
# render-time seam the heartbeat suite uses -- there is no runtime env override), and drives it
# against PATH stubs for findmnt and cryptsetup. The memory-retry `sleep 300` and the
# /proc/self/oom_score_adj write are re-rooted the same way, so the suite neither waits nor needs root.
#
# Needs only bash, awk, sed and coreutils. No terraform, docker, cryptsetup, network or root.

export TMPDIR="${TMPDIR:-/var/tmp}"
set -uo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CI_YML="$SCRIPT_DIR/cloud-init-registry.yml"
TMP="$(mktemp -d "${TMPDIR}/luks-escrow.XXXXXXXX")" || { printf 'FATAL: mktemp failed\n' >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

passes=0
fails=0
cases=0
check() { # <name> <condition>
  cases=$((cases + 1))
  if eval "$2" >/dev/null 2>&1; then passes=$((passes + 1)); printf 'ok   - %s\n' "$1"
  else fails=$((fails + 1)); printf 'FAIL - %s\n' "$1" >&2; fi
}
check "self-test pass arm" "true"; check "self-test fail arm (this FAIL line is EXPECTED)" "false"
if [ "$passes" -ne 1 ] || [ "$fails" -ne 1 ] || [ "$cases" -ne 2 ]; then
  printf 'FATAL: instrument self-test: check() did not record one pass and one fail.\n' >&2
  exit 2
fi
passes=0; fails=0; cases=0

# --- Extract + render ------------------------------------------------------------------------
RAW="$TMP/escrow.raw.sh"
awk -v want="  - path: /usr/local/bin/registry-luks-escrow.sh" '
  $0 == want { found = 1; next }
  found && /^    content: \|$/ { incontent = 1; next }
  incontent {
    if ($0 ~ /^      /) { print substr($0, 7); next }
    if ($0 ~ /^[[:space:]]*$/) { print ""; next }
    exit
  }' "$CI_YML" > "$RAW"
check "escrow script extracted from the template (non-empty, has a shebang)" "head -1 '$RAW' | grep -q '^#!'"
ES="$TMP/escrow.sh"
sed -E '/^[[:blank:]]*#([[:blank:]].*)?$/d' "$RAW" | sed 's|[$][$][{]|${|g' > "$ES"
check "the rendered script is valid bash" "bash -n '$ES'"
check "the render left no single-dollar TF interpolation" "! grep -qE '(^|[^$])[$][{][a-z_]+[}]' '$RAW'"
# Render-time seams: the literal PATH, /proc/meminfo and the state dir.
BIN="$TMP/bin"; mkdir -p "$BIN"
check "the shipped script carries the literal trusted PATH" \
  "grep -qxF 'PATH=\"/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\"' '$ES'"
sed -i "s|^PATH=.*|PATH=\"$BIN:\$PATH\"|" "$ES"
check "the shipped script has exactly ONE retry sleep, of 300 s, and ONE oom_score_adj write of 1000" \
  "[ \"\$(grep -c 'sleep 300' '$ES')\" -eq 1 ] && [ \"\$(grep -cF \"printf '1000\\\\n' > /proc/self/oom_score_adj\" '$ES')\" -eq 1 ]"
sed -i "s|/proc/meminfo|$TMP/meminfo|g; s|/var/lib/soleur-registry|$TMP/state|g" "$ES"
# The retry sleep becomes a stub that records itself and can change memory between samples.
sed -i "s|sleep 300|fake_sleep 300|; s|/proc/self/oom_score_adj|$TMP/oom|g" "$ES"
check "the five seams landed" \
  "grep -qF 'PATH=\"$BIN:' '$ES' && grep -qF '$TMP/meminfo' '$ES' && grep -qF 'STATE_DIR=$TMP/state' '$ES' && grep -qF 'fake_sleep 300' '$ES' && grep -qF '> $TMP/oom' '$ES'"

# --- Stubs -----------------------------------------------------------------------------------
# Every stub records its argv to $CALLS, which the key canary reads: the key must never be an
# argument. cryptsetup reads stdin only for luksOpen, and records what it read to $KEYSEEN so the
# suite can prove the key arrived through the pipe.
cat > "$BIN/findmnt" <<'EOS'
#!/usr/bin/env bash
echo "findmnt $*" >> "$CALLS"
[ "$*" = "-no SOURCE /var/lib/zot" ] || { echo "findmnt stub: unexpected argv: $*" >&2; exit 64; }
printf '%s\n' "${STUB_SRC-/dev/mapper/registry}"
EOS
cat > "$BIN/cryptsetup" <<'EOS'
#!/usr/bin/env bash
echo "cryptsetup $*" >> "$CALLS"
case "$1" in
  status)
    [ "$2" = registry ] || { echo "cryptsetup stub: status of $2" >&2; exit 64; }
    [ "${STUB_STATUS_RC:-0}" -eq 0 ] || exit "$STUB_STATUS_RC"
    printf '/dev/mapper/registry is active.\n  type:    LUKS2\n  device:  %s\n' "${STUB_DEV-/dev/sdb}" ;;
  luksUUID)
    [ "$2" = /dev/sdb ] || { echo "cryptsetup stub: luksUUID of $2" >&2; exit 64; }
    u="${STUB_UUID-0f1e2d3c-4b5a-6978-8796-a5b4c3d2e1f0}"
    [ -n "$u" ] && printf '%s\n' "$u"
    exit "${STUB_UUID_RC:-0}" ;;
  luksDump)
    [ "$2" = /dev/sdb ] || { echo "cryptsetup stub: luksDump of $2" >&2; exit 64; }
    [ "${STUB_LD_RC:-0}" -eq 0 ] || exit "$STUB_LD_RC"
    printf 'LUKS header information\nKeyslots:\n  0: luks2\n\tPBKDF:      argon2id\n\tMemory:     %s\n' "${STUB_PBKDF_KIB:-1048576}"
    # A second keyslot with a different cost: the pre-check must take the LARGEST, not the first.
    [ -n "${STUB_PBKDF2_KIB:-}" ] && printf '  1: luks2\n\tPBKDF:      argon2id\n\tMemory:     %s\n' "$STUB_PBKDF2_KIB"
    exit 0 ;;
  luksOpen)
    [ "$*" = "luksOpen --test-passphrase --key-file - /dev/sdb" ] || { echo "cryptsetup stub: luksOpen argv: $*" >&2; exit 64; }
    cat > "$KEYSEEN"
    exit "${STUB_OPEN_RC:-0}" ;;
  *) echo "cryptsetup stub: unexpected subcommand $1" >&2; exit 64 ;;
esac
EOS
# fake_sleep: records each retry wait; with STUB_MEM_AFTER set, memory becomes that value.
cat > "$BIN/fake_sleep" <<EOS
#!/usr/bin/env bash
echo "fake_sleep \$*" >> "\$CALLS"
[ -n "\${STUB_MEM_AFTER:-}" ] && printf 'MemTotal:        3905536 kB\nMemAvailable:    %s kB\n' "\$STUB_MEM_AFTER" > "$TMP/meminfo"
exit 0
EOS
chmod +x "$BIN"/*
# mv: a passthrough to the real binary by ABSOLUTE path (a PATH lookup would find this stub
# and recurse), failing on demand for the atomicity row.
REAL_MV="$(PATH=/usr/bin:/bin command -v mv)"
printf '#!/usr/bin/env bash\n[ -n "${STUB_MV_FAIL:-}" ] && exit 1\nexec %s "$@"\n' "$REAL_MV" > "$BIN/mv"
chmod +x "$BIN/mv"

KEY='canary-luks-key-4c1f9e'
STATE="$TMP/state/escrow.state"

# run_escrow [env...] -> runs the producer once; sets RC, OUT, ERR, RESULT_TOKEN.
run_escrow() {
  : > "$TMP/calls"; rm -rf "$TMP/keyseen" "$TMP/oom"
  env CALLS="$TMP/calls" KEYSEEN="$TMP/keyseen" REGISTRY_LUKS_KEY="$KEY" "$@" \
    bash "$ES" > "$TMP/out" 2> "$TMP/err"
  RC=$?
  RESULT_TOKEN="$(sed -n 's/^result=\([a-z_]*\) at=[0-9]*$/\1/p' "$STATE" 2>/dev/null | head -1)"
}
meminfo() { printf 'MemTotal:        3905536 kB\nMemAvailable:    %s kB\n' "$1" > "$TMP/meminfo"; }
fresh() { rm -rf "$TMP/state"; }

# --- Vocabulary reachability: each token from exactly one stubbed condition --------------------
meminfo 3000000
fresh; run_escrow
check "ok: the key opened the header -> result=ok" "[ '$RESULT_TOKEN' = ok ] && [ '$RC' -eq 0 ]"
check "ok: the key reached cryptsetup through the pipe (stdin), byte-exact" "[ \"\$(cat '$TMP/keyseen')\" = '$KEY' ]"
check "ok: the OOM shield was raised to exactly 1000 before the KDF" "[ \"\$(cat '$TMP/oom')\" = 1000 ]"
check "ok: luksOpen ran exactly once, with the exact argv, and no retry wait happened" \
  "[ \"\$(grep -cxF 'cryptsetup luksOpen --test-passphrase --key-file - /dev/sdb' '$TMP/calls')\" -eq 1 ] && ! grep -q fake_sleep '$TMP/calls'"
check "ok: no systemd-run in the comment-stripped script (it rejects OOMScoreAdjust= on a scope)" "! grep -q 'systemd-run' '$ES'"
check "ok: the state file is 0600 in a 0700 directory" \
  "[ \"\$(stat -c %a '$STATE')\" = 600 ] && [ \"\$(stat -c %a '$TMP/state')\" = 700 ]"
check "ok: the state file is exactly one 'result=<token> at=<epoch>' line" \
  "grep -qxE 'result=ok at=[0-9]+' '$STATE' && [ \"\$(wc -l < '$STATE')\" -eq 1 ]"

fresh; run_escrow STUB_OPEN_RC=2
check "fail_passphrase: cryptsetup exit 2 (no permission) -> fail_passphrase" "[ '$RESULT_TOKEN' = fail_passphrase ]"
fresh; run_escrow STUB_UUID=""
check "fail_header: luksUUID rc 0 but empty -> fail_header" "[ '$RESULT_TOKEN' = fail_header ]"
fresh; run_escrow STUB_UUID="" STUB_UUID_RC=1
check "fail_header: luksUUID rc 1 (no LUKS header) -> fail_header" "[ '$RESULT_TOKEN' = fail_header ]"
fresh; run_escrow REGISTRY_LUKS_KEY=""
check "fail_key_absent: an EMPTY key -> fail_key_absent (never a skip)" "[ '$RESULT_TOKEN' = fail_key_absent ]"
check "fail_key_absent: no luksOpen was attempted without a key" "! grep -q luksOpen '$TMP/calls'"

meminfo 1000000
fresh; run_escrow STUB_PBKDF_KIB=1048576
check "indeterminate: MemAvailable below PBKDF memory + 256 MiB -> indeterminate, NO KDF run" \
  "[ '$RESULT_TOKEN' = indeterminate ] && ! grep -q luksOpen '$TMP/calls'"
meminfo 1310720
fresh; run_escrow STUB_PBKDF_KIB=1048576
check "memory pre-check boundary: exactly PBKDF + 256 MiB available -> proceeds (ok)" "[ '$RESULT_TOKEN' = ok ]"
meminfo 1310719
fresh; run_escrow STUB_PBKDF_KIB=1048576
check "memory pre-check boundary: one KiB short of PBKDF + 256 MiB -> indeterminate, NO KDF run" \
  "[ '$RESULT_TOKEN' = indeterminate ] && ! grep -q luksOpen '$TMP/calls'"
check "memory short on every sample: exactly TWO retry waits of 300 s (three samples)" \
  "[ \"\$(grep -cxF 'fake_sleep 300' '$TMP/calls')\" -eq 2 ]"
fresh; run_escrow STUB_PBKDF_KIB=524288 STUB_PBKDF2_KIB=1048576
check "two keyslots: the LARGER second slot's memory is the one required (1310719 KiB -> indeterminate)" \
  "[ '$RESULT_TOKEN' = indeterminate ]"
meminfo 1000000
fresh; run_escrow STUB_PBKDF_KIB=1048576 STUB_MEM_AFTER=3000000
check "memory retry: short on the first sample, enough after one wait -> ok, with exactly one wait" \
  "[ '$RESULT_TOKEN' = ok ] && [ \"\$(grep -cxF 'fake_sleep 300' '$TMP/calls')\" -eq 1 ]"
meminfo 3000000
fresh; run_escrow STUB_SRC=/dev/sda1
check "indeterminate: /var/lib/zot not on a mapper -> indeterminate" "[ '$RESULT_TOKEN' = indeterminate ]"
fresh; run_escrow STUB_STATUS_RC=1
check "indeterminate: cryptsetup status refused -> indeterminate" "[ '$RESULT_TOKEN' = indeterminate ]"
fresh; run_escrow STUB_UUID_RC=127
check "indeterminate: luksUUID tool absent (127) is a refusal, not a header verdict" "[ '$RESULT_TOKEN' = indeterminate ]"
fresh; run_escrow STUB_UUID_RC=124
check "indeterminate: luksUUID timed out (124) is a refusal, not a header verdict" "[ '$RESULT_TOKEN' = indeterminate ]"
fresh; run_escrow STUB_LD_RC=1
check "indeterminate: luksDump failed -> indeterminate, NO KDF run (an empty dump must not read as 0 KiB)" \
  "[ '$RESULT_TOKEN' = indeterminate ] && ! grep -q luksOpen '$TMP/calls'"
fresh; rm -rf "$TMP/oom"; mkdir -p "$TMP/oom"
: > "$TMP/calls"; rm -f "$TMP/keyseen"
env CALLS="$TMP/calls" KEYSEEN="$TMP/keyseen" REGISTRY_LUKS_KEY="$KEY" bash "$ES" > "$TMP/out" 2> "$TMP/err"
RESULT_TOKEN="$(sed -n 's/^result=\([a-z_]*\) at=[0-9]*$/\1/p' "$STATE" 2>/dev/null | head -1)"
check "indeterminate: the OOM shield could not be raised -> indeterminate, NO KDF run" \
  "[ '$RESULT_TOKEN' = indeterminate ] && ! grep -q luksOpen '$TMP/calls'"
rm -rf "$TMP/oom"
fresh; run_escrow STUB_OPEN_RC=3
check "indeterminate: luksOpen out of memory (3) -> indeterminate, never ok" "[ '$RESULT_TOKEN' = indeterminate ]"
fresh; run_escrow STUB_OPEN_RC=137
check "indeterminate: luksOpen OOM-killed (137) -> indeterminate" "[ '$RESULT_TOKEN' = indeterminate ]"

# --- Atomicity: static pattern + a stubbed mv failure ----------------------------------------
check "static: the state is written to a temp file in the SAME directory, then mv -f'd into place" \
  "grep -qF 'local tmp=\"\$STATE_DIR/.escrow.state.tmp\"' '$RAW' && grep -qF 'mv -f \"\$tmp\" \"\$STATE\"' '$RAW'"
check "static: no plain redirect writes the state file directly" "! grep -qE '> *\"?\\\$STATE\"?( |\$)' '$RAW'"
fresh; run_escrow
cp "$STATE" "$TMP/state.before"
run_escrow STUB_OPEN_RC=2 STUB_MV_FAIL=1
check "a failed mv leaves the PREVIOUS state intact (old ok, not a torn or empty file)" \
  "cmp -s '$STATE' '$TMP/state.before'"
check "a failed mv leaves no temp file behind" "[ ! -e '$TMP/state/.escrow.state.tmp' ]"

# --- The key canary ----------------------------------------------------------------------------
fresh; run_escrow
check "key canary: absent from the state file" "! grep -qF '$KEY' '$STATE'"
check "key canary: absent from stdout and stderr" "! grep -qF '$KEY' '$TMP/out' '$TMP/err'"
check "key canary: absent from every stubbed argv" "! grep -qF '$KEY' '$TMP/calls'"
check "static: the key is fed through printf into a pipe, never a here-string" \
  "grep -qF \"printf '%s' \\\"\\\$REGISTRY_LUKS_KEY\\\" | timeout 120 cryptsetup luksOpen --test-passphrase --key-file - \\\"\\\$DEV\\\"\" '$RAW' && ! grep -qE '<<<.*REGISTRY_LUKS_KEY' '$RAW'"

# --- Refusals and the EXIT trap -----------------------------------------------------------------
: > "$TMP/calls"
env CALLS="$TMP/calls" KEYSEEN="$TMP/keyseen" REGISTRY_LUKS_KEY="$KEY" bash -x "$ES" > "$TMP/out" 2> "$TMP/err"
XRC=$?
check "refuses to run under xtrace (exit 78), before any tool call" "[ '$XRC' -eq 78 ] && [ ! -s '$TMP/calls' ]"
check "the xtrace refusal leaks no key into the trace" "! grep -qF '$KEY' '$TMP/err'"
check "static: an EXIT trap writes indeterminate when no verdict was recorded (a crash stays visible)" \
  "grep -qF \"trap '[ -n \\\"\\\$RESULT\\\" ] || write_state indeterminate' EXIT\" '$RAW'"

# --- Writer == reader vocabulary ------------------------------------------------------------------
# Every token the producer can write must be one the heartbeat reader accepts, and vice versa: a
# token only one side knows is either an unreadable verdict or a dead reader arm.
WRITER_TOKS="$(grep -oE 'write_state [a-z_]+' "$RAW" | awk '{print $2}' | sort -u | tr '\n' ' ')"
READER_TOKS="$(grep -E '^[[:blank:]]+ok \| fail_passphrase .*\) STORE_ESCROW="\$_esr" ;;$' "$CI_YML" \
  | sed -E 's/^[[:blank:]]+//; s/\).*$//' | tr -d ' ' | tr '|' '\n' | sort -u | tr '\n' ' ')"
check "writer vocabulary ($WRITER_TOKS) == heartbeat reader vocabulary ($READER_TOKS), and non-trivial" \
  "[ -n '$WRITER_TOKS' ] && [ '$WRITER_TOKS' = '$READER_TOKS' ] && [ \"\$(wc -w <<<'$WRITER_TOKS')\" -eq 5 ]"

# --- Delivery: the cron line, the boot call, and minute isolation --------------------------------
# shellcheck disable=SC2034  # read inside check()'s eval'd condition string
CRON_LINE="$(grep -E '^      19 3 \* \* \* root .*registry-luks-escrow\.sh$' "$CI_YML" || true)"
check "the cron line is EXACTLY: 03:19 daily, sourced doppler env, --only-secrets, --no-fallback" \
  "[ \"\$CRON_LINE\" = '      19 3 * * * root set -a; . /etc/default/registry-doppler; set +a; doppler run --project soleur-registry --config prd --only-secrets REGISTRY_LUKS_KEY --no-fallback -- /usr/local/bin/registry-luks-escrow.sh' ]"
# Every other cron.d minute field on this host, expanded, must not contain 19.
OTHER_MIN="$(grep -E '^      [0-9*][0-9*/,-]* [0-9*][0-9*/,-]* [0-9*] [0-9*] [0-9*] root ' "$CI_YML" | grep -v registry-luks-escrow | awk '{print $1}')"
minutes_of() { # expand one cron minute field to its minute list
  local f="$1" part base step lo hi m
  for part in ${f//,/ }; do
    step=1; base="$part"
    case "$part" in */*) base="${part%/*}"; step="${part#*/}" ;; esac
    case "$base" in
      '*') lo=0; hi=59 ;;
      *-*) lo="${base%-*}"; hi="${base#*-}" ;;
      *) lo="$base"; hi="$base"; [ "$step" -ne 1 ] && hi=59 ;;
    esac
    for ((m = lo; m <= hi; m += step)); do printf '%s\n' "$m"; done
  done
}
OTHER_N="$(grep -c . <<<"$OTHER_MIN" || true)"
check "derived the host's other cron.d minute fields (>= 3: heartbeat, shipper, NIC guard; found $OTHER_N)" "[ '$OTHER_N' -ge 3 ]"
CLASH=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  minutes_of "$f" | grep -qx 19 && CLASH=$((CLASH + 1))
done <<<"$OTHER_MIN"
check "no other cron.d minute set on this host contains minute 19" "[ '$CLASH' -eq 0 ]"
BOOT_LN="$(grep -nxF "  - set -a; . /etc/default/registry-doppler; set +a; nohup sh -c 'sleep 900; exec doppler run --project soleur-registry --config prd --only-secrets REGISTRY_LUKS_KEY --no-fallback -- /usr/local/bin/registry-luks-escrow.sh' >/dev/null 2>&1 &" "$CI_YML" | cut -d: -f1)"
check "exactly one boot escrow call, deferred 900 s, with the cron's exact wrapper (found line(s): ${BOOT_LN//$'\n'/,})" \
  "[ \"\$(grep -c . <<<'$BOOT_LN')\" -eq 1 ] && [ \"\$(grep -vE '^[[:blank:]]*#' '$CI_YML' | grep -c 'doppler run .*-- /usr/local/bin/registry-luks-escrow.sh')\" -eq 2 ]"
ZOT_RUN_LN="$(grep -nE '^[[:blank:]]*docker run -d --name zot ' "$CI_YML" | head -1 | cut -d: -f1)"
HB_BOOT_LN="$(grep -nF -- '-- bash /usr/local/bin/zot-disk-heartbeat.sh || true' "$CI_YML" | head -1 | cut -d: -f1)"
check "the boot escrow run exists, backgrounded, with the cron's wrapper (a bare run records fail_key_absent)" "[ -n '$BOOT_LN' ]"
check "the boot escrow run comes AFTER zot's docker run (a slow KDF never lengthens the pull-path window)" \
  "[ '${ZOT_RUN_LN:-0}' -gt 0 ] && [ '${BOOT_LN:-0}' -gt '${ZOT_RUN_LN:-0}' ]"
check "the boot escrow run comes BEFORE the first boot heartbeat" "[ '${BOOT_LN:-0}' -lt '${HB_BOOT_LN:-0}' ]"

# --- Anti-vacuity floors: printf + exit, never through check() (ADR-193) ------------------------
MIN_CASES=51
if [ "$cases" -lt "$MIN_CASES" ]; then
  printf '\n[FATAL] floor: only %s cases ran (expected >= %s).\n' "$cases" "$MIN_CASES" >&2
  exit 1
fi
if [ $((passes + fails)) -ne "$cases" ]; then
  printf '\n[FATAL] conservation: pass+fail (%s) != cases (%s).\n' "$((passes + fails))" "$cases" >&2
  exit 1
fi
printf '\n%s passed, %s failed (%s cases)\n' "$passes" "$fails" "$cases"
[ "$fails" -eq 0 ]
