#!/usr/bin/env bash
# Suite for host-kernel-marker.sh and its plain systemd units (#12007).
#
# PROPERTY. The collector prints EXACTLY ONE line
#   SOLEUR_HOST_KERNEL v=1 role=<web|inngest|registry> kernel=<uname -r|unreadable> uptime_s=<uint|unknown>
#     reboot_required=<0|1|unknown> sec_updates=<uint|unknown>[ host=<registry host id>]
# (the `host=` token only for --role registry), `kernel=` is ALWAYS followed by one space and `uptime_s=` (readers
# delimit the kernel without a `$` anchor), a measurement failure is a token value and never a non-zero exit, a bad
# role is exit 64 with nothing on stdout, and the PATH is the script's own (cron and systemd both start without
# /usr/sbin, the 2026-07-15 blind-host learning).
#
# INSTRUMENT. The collector is driven through PATH-shimmed `uname`, `apt-get` and `hostname` plus file seams for
# /proc/uptime and the reboot-required marker. The seams are honoured only under HKM_TEST=1; a row proves they are
# inert without it. Every kernel string is SYNTHESIZED (9.9.9-...): no real version or host name appears here.
#
# SANDBOX COPY. The three helper files are resolved by BASENAME next to this suite, never by a repo path, so a copy of
# the four files in an empty directory runs green (a row does exactly that). No `knowledge-base/` path is read.
#
# ANTI-VACUITY. `cases` is incremented at the CALL SITE of every assertion helper, independently of pass()/fail(), so a
# neutered verdict helper cannot keep the floor satisfied; the floor and the passes+fails==cases identity are reported
# by a direct printf + exit 1, not through fail().
set -uo pipefail

export TMPDIR="${TMPDIR:-/var/tmp}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/host-kernel-marker.sh"
SVC="$SCRIPT_DIR/host-kernel-marker.service"
TMR="$SCRIPT_DIR/host-kernel-marker.timer"

cases=0
passes=0
fails=0
pass() { passes=$((passes + 1)); printf '  PASS: %s\n' "$1"; }
fail() { fails=$((fails + 1)); printf '  FAIL: %s\n' "$1" >&2; }

# INSTRUMENT SELF-TEST: drive both verdict helpers once; refuse to continue unless both counters moved.
pass "instrument self-test (pass)"
fail "instrument self-test (fail) - EXPECTED, subtracted below"
if [[ "$passes" -ne 1 || "$fails" -ne 1 ]]; then
  printf '[FATAL] INSTRUMENT BROKEN: self-test left passes=%d fails=%d, expected 1/1.\n' "$passes" "$fails" >&2
  exit 2
fi
passes=0
fails=0

# Assertion helpers. `cases` moves HERE (the call site), never inside pass()/fail().
eq() { # <name> <actual> <expected>
  cases=$((cases + 1))
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1 (got [$2], want [$3])"; fi
}
ok() { # <name> <rc-of-a-condition>: 0 = holds
  cases=$((cases + 1))
  if [[ "$2" -eq 0 ]]; then pass "$1"; else fail "$1"; fi
}
no() { # <name> <rc-of-a-condition>: non-zero = the bad thing is absent
  cases=$((cases + 1))
  if [[ "$2" -ne 0 ]]; then pass "$1"; else fail "$1"; fi
}

# INSTRUMENT SELF-TEST (comparison helpers): drive eq/ok/no once each with a comparison that MUST fail and once with one that must pass,
# then require the counters to have moved by exactly that much. A helper rewritten to always say ok (or never count) is caught here; the
# floor alone cannot catch it. The counters are unwound so the real totals stay exact; the verdict is reported by printf + exit.
ST_P="$passes"; ST_F="$fails"; ST_C="$cases"
{
  eq "selftest eq (must fail)" "a" "b"
  ok "selftest ok (must fail)" 1
  no "selftest no (must fail)" 0
  eq "selftest eq (must pass)" "a" "a"
  ok "selftest ok (must pass)" 0
  no "selftest no (must pass)" 1
} > /dev/null 2>&1
if [[ "$fails" -ne $((ST_F + 3)) || "$passes" -ne $((ST_P + 3)) || "$cases" -ne $((ST_C + 6)) ]]; then
  printf '[FATAL] INSTRUMENT BROKEN: eq/ok/no self-test left passes=%d fails=%d cases=%d (from %d/%d/%d), expected +3/+3/+6.\n' \
    "$passes" "$fails" "$cases" "$ST_P" "$ST_F" "$ST_C" >&2
  exit 2
fi
passes="$ST_P"; fails="$ST_F"; cases="$ST_C"

[[ -f "$SUT" && -f "$SVC" && -f "$TMR" ]] || {
  printf '[FATAL] host-kernel-marker.{sh,service,timer} must sit beside this suite (resolved by basename)\n' >&2
  exit 2
}

# Canonical assert_fixture_dir - byte-identical copy (fixture-scan.py requires the verbatim body).
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

WORK="$(mktemp -d "${TMPDIR}/host-kernel-marker-test.XXXXXXXX")" || { echo "FATAL: mktemp failed" >&2; exit 2; }
assert_fixture_dir "$WORK"
cleanup() { [[ -n "${WORK:-}" && -d "$WORK" ]] && rm -rf "$WORK"; return 0; }
trap cleanup EXIT

STUBS="$WORK/stubs"; FX="$WORK/fx"
assert_fixture_dir "$STUBS"; assert_fixture_dir "$FX"
mkdir -p "$STUBS" "$FX"

# --- stubs --------------------------------------------------------------------------------------------------------
cat > "$STUBS/uname" <<'STUB'
#!/usr/bin/env bash
[[ -f "$HKM_FX/uname.rc" ]] && rc="$(cat "$HKM_FX/uname.rc")" || rc=0
[[ -f "$HKM_FX/uname.out" ]] && cat "$HKM_FX/uname.out"
exit "$rc"
STUB
cat > "$STUBS/hostname" <<'STUB'
#!/usr/bin/env bash
[[ -f "$HKM_FX/hostname.rc" ]] && rc="$(cat "$HKM_FX/hostname.rc")" || rc=0
[[ -f "$HKM_FX/hostname.out" ]] && cat "$HKM_FX/hostname.out"
exit "$rc"
STUB
cat > "$STUBS/apt-get" <<'STUB'
#!/usr/bin/env bash
{ printf 'ARGS=%s\n' "$*"; printf 'PATH=%s\n' "$PATH"; printf 'LC_ALL=%s\n' "${LC_ALL-unset}"; } >> "$HKM_FX/apt.calls"
mode="$(cat "$HKM_FX/apt.mode" 2>/dev/null || echo ok)"
case "$mode" in
  ok)
    cat <<'OUT'
Reading package lists...
Inst libfixture1 [1.0] (1.1 Fixture:24.04/fixture-security [amd64])
Inst fixture-tools [2] (3 Fixture:24.04/fixture-updates [amd64])
Inst fixture-core [1] (2 Fixture:24.04/fixture-security, Fixture:24.04/fixture-updates [amd64])
Inst security-tools [1] (2 Fixture:24.04/fixture-updates [amd64])
Conf libfixture1 (1.1 Fixture:24.04/fixture-security [amd64])
OUT
    exit 0 ;;
  none) printf 'Reading package lists...\n'; exit 0 ;;
  fail) printf 'Inst libfixture1 [1.0] (1.1 Fixture:24.04/fixture-security [amd64])\n'; exit 100 ;;
  hang) exec sleep 30 ;;
  # A hang that IGNORES TERM (the signal `timeout` sends first; `trap ''` is inherited as ignore by the sleeps): only the `timeout -k 2` KILL ends it, so
  # dropping `-k` leaves this running for the full 25 s and the elapsed-time row below goes RED.
  hangterm) trap '' TERM; end=$((SECONDS + 25)); while [ "$SECONDS" -lt "$end" ]; do sleep 1; done; exit 0 ;;
  # One real security-pocket line plus a package NAME containing "-security" on a NON-security pocket (see the pkgname row for the rule it pins).
  pkgname)
    cat <<'OUT'
Reading package lists...
Inst libfixture1 [1.0] (1.1 Fixture:24.04/fixture-security [amd64])
Inst foo-security-bar [1] (2 Fixture:24.04/fixture-updates [amd64])
OUT
    exit 0 ;;
esac
exit 0
STUB
chmod +x "$STUBS/uname" "$STUBS/hostname" "$STUBS/apt-get"

reset_fx() {
  rm -f "$FX"/*
  printf '9.9.9-1-generic\n' > "$FX/uname.out"
  printf '12345.67 98765.43\n' > "$FX/uptime"
  : > "$FX/reboot-required.absent-marker"
  rm -f "$FX/reboot-required"
  printf 'fixture-host-1\n' > "$FX/hostname.out"
  printf 'ok\n' > "$FX/apt.mode"
}

# run_hkm <args...>: stdout -> OUT, stderr -> ERR, exit -> RC. The caller PATH is a decoy: the collector must set its own.
run_hkm() {
  OUT="$(env -i PATH=/nonexistent-caller-path HOME=/nonexistent LC_ALL=C.UTF-8 \
    HKM_TEST=1 HKM_FX="$FX" HKM_STUB_BIN_DIR="$STUBS" HKM_PROC_UPTIME="$FX/uptime" \
    HKM_REBOOT_FILE="${HKM_REBOOT_FILE_OVERRIDE:-$FX/reboot-required}" HKM_APT_TIMEOUT_S="${HKM_APT_TIMEOUT_OVERRIDE:-1}" \
    "$BASH" "$SUT" "$@" 2> "$WORK/stderr")"
  RC=$?
  ERR="$(cat "$WORK/stderr")"
}

WEB_RE='^SOLEUR_HOST_KERNEL v=1 role=(web|inngest) kernel=(unreadable|[0-9]+\.[0-9]+\.[0-9]+-[0-9]+-[a-z0-9-]+) uptime_s=([0-9]+|unknown) reboot_required=(0|1|unknown) sec_updates=([0-9]+|unknown)$'
REG_RE='^SOLEUR_HOST_KERNEL v=1 role=registry kernel=(unreadable|[0-9]+\.[0-9]+\.[0-9]+-[0-9]+-[a-z0-9-]+) uptime_s=([0-9]+|unknown) reboot_required=(0|1|unknown) sec_updates=([0-9]+|unknown) host=[A-Za-z0-9._-]{1,63}$'
# The grammar judge used by the rows below. Its own must-fail rows run first so a judge that accepts everything is RED.
grammar_ok() { # <role> <line>: rc 0 iff the line has the exact grammar and is a single line
  local role="$1" line="$2"
  [[ "$line" != *$'\n'* ]] || return 1
  if [[ "$role" == registry ]]; then [[ "$line" =~ $REG_RE ]]; else [[ "$line" =~ $WEB_RE ]]; fi
}

echo "=== instrument: the grammar judge rejects malformed lines ==="
GOOD_WEB='SOLEUR_HOST_KERNEL v=1 role=web kernel=9.9.9-1-generic uptime_s=1 reboot_required=0 sec_updates=0'
GOOD_REG='SOLEUR_HOST_KERNEL v=1 role=registry kernel=9.9.9-1-generic uptime_s=1 reboot_required=0 sec_updates=0 host=soleur-registry'
grammar_ok web "$GOOD_WEB"; ok "judge accepts a canonical web line" $?
grammar_ok registry "$GOOD_REG"; ok "judge accepts a canonical registry line" $?
grammar_ok web "${GOOD_WEB/kernel=9.9.9-1-generic uptime_s/kernel=9.9.9-1-generic  uptime_s}"; no "judge rejects a double space after kernel=" $?
grammar_ok web "${GOOD_WEB/v=1/v=2}"; no "judge rejects v=2" $?
grammar_ok web "${GOOD_WEB} host=soleur-registry"; no "judge rejects host= on a web line" $?
grammar_ok registry "${GOOD_REG% host=*}"; no "judge rejects a registry line without host=" $?
grammar_ok web "${GOOD_WEB} "; no "judge rejects a trailing space" $?
grammar_ok web "${GOOD_WEB/ sec_updates=0/}"; no "judge rejects a missing field" $?
grammar_ok web "${GOOD_WEB}"$'\n'"${GOOD_WEB}"; no "judge rejects two lines" $?
grammar_ok web "${GOOD_WEB/role=web/role=bogus}"; no "judge rejects an unknown role" $?
grammar_ok web "${GOOD_WEB/9.9.9-1-generic/9.9.9-1-Generic}"; no "judge rejects an upper-case kernel flavour" $?

echo "=== collector: canonical lines ==="
reset_fx
run_hkm --role web
eq "web: exit 0" "$RC" "0"
eq "web: exact line" "$OUT" "SOLEUR_HOST_KERNEL v=1 role=web kernel=9.9.9-1-generic uptime_s=12345 reboot_required=0 sec_updates=2"
eq "web: stderr empty" "$ERR" ""
grammar_ok web "$OUT"; ok "web: grammar" $?
eq "web: exactly one line" "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" "1"
no "web: no host= token" "$([[ "$OUT" == *" host="* ]] && echo 0 || echo 1)"

run_hkm --role inngest
eq "inngest: exit 0" "$RC" "0"
eq "inngest: exact line" "$OUT" "SOLEUR_HOST_KERNEL v=1 role=inngest kernel=9.9.9-1-generic uptime_s=12345 reboot_required=0 sec_updates=2"
no "inngest: no host= token" "$([[ "$OUT" == *" host="* ]] && echo 0 || echo 1)"

run_hkm --role registry
eq "registry: exit 0" "$RC" "0"
eq "registry: exact line with host=" "$OUT" "SOLEUR_HOST_KERNEL v=1 role=registry kernel=9.9.9-1-generic uptime_s=12345 reboot_required=0 sec_updates=2 host=soleur-registry"
grammar_ok registry "$OUT"; ok "registry: grammar" $?

echo "=== collector: kernel= is followed by one space then uptime_s= ==="
for k in 9.9.9-1-generic 9.9.9-123-amd64 9.9.9-12-cloud-arm64; do
  reset_fx; printf '%s\n' "$k" > "$FX/uname.out"
  run_hkm --role web
  [[ "$OUT" == *" kernel=$k uptime_s="* ]] && R=0 || R=1; ok "kernel $k is delimited by a single space and uptime_s=" "$R"
  grammar_ok web "$OUT"; ok "kernel $k: grammar" $?
done

echo "=== collector: kernel=unreadable on an odd uname -r ==="
odd_kernel() { # <label> <printf-format-with-escapes>
  reset_fx; printf "$2" > "$FX/uname.out"
  run_hkm --role web
  eq "odd uname [$1]: exit 0" "$RC" "0"
  [[ "$OUT" == *" kernel=unreadable uptime_s="* ]]; ok "odd uname [$1]: kernel=unreadable" $?
  grammar_ok web "$OUT"; ok "odd uname [$1]: still one grammatical line" $?
}
odd_kernel empty ''
odd_kernel word 'weird\n'
odd_kernel trailing-token '9.9.9-1-generic extra\n'
odd_kernel upper-flavour '9.9.9-1-Generic\n'
odd_kernel two-lines '9.9.9-1-generic\nINJECTED line\n'
odd_kernel shell-meta '$(id)\n'
odd_kernel no-abi '9.9.9-generic\n'
odd_kernel leading-space ' 9.9.9-1-generic\n'
reset_fx; printf '9.9.9-1-generic\n' > "$FX/uname.out"; printf '1\n' > "$FX/uname.rc"
run_hkm --role web
eq "uname failing with output: exit 0" "$RC" "0"
[[ "$OUT" == *" kernel=unreadable uptime_s="* ]] && R=0 || R=1; ok "uname exit 1: kernel=unreadable (no trust in a failed read)" "$R"

echo "=== collector: uptime_s ==="
uptime_row() { # <label> <content-or-@missing> <expected>
  reset_fx
  if [[ "$2" == "@missing" ]]; then rm -f "$FX/uptime"; else printf '%b' "$2" > "$FX/uptime"; fi
  run_hkm --role web
  eq "uptime [$1]: exit 0" "$RC" "0"
  [[ "$OUT" == *" uptime_s=$3 reboot_required="* ]]; ok "uptime [$1] -> $3" $?
}
uptime_row fraction '12345.67 98765.43\n' 12345
uptime_row sub-second '0.50 1.0\n' 0
uptime_row integer '77 5\n' 77
uptime_row empty '' unknown
uptime_row missing '@missing' unknown
uptime_row garbage 'abc def\n' unknown
uptime_row negative '-5.0 1\n' unknown

echo "=== collector: reboot_required ==="
reset_fx; : > "$FX/reboot-required"
run_hkm --role web
[[ "$OUT" == *" reboot_required=1 sec_updates="* ]] && R=0 || R=1; ok "reboot-required present -> 1" "$R"
reset_fx
run_hkm --role web
[[ "$OUT" == *" reboot_required=0 sec_updates="* ]] && R=0 || R=1; ok "reboot-required absent in a readable dir -> 0" "$R"
reset_fx
HKM_REBOOT_FILE_OVERRIDE="$FX/no-such-dir/reboot-required" run_hkm --role web
[[ "$OUT" == *" reboot_required=unknown sec_updates="* ]] && R=0 || R=1; ok "unreadable parent dir -> unknown" "$R"
eq "unreadable parent dir: exit 0" "$RC" "0"

echo "=== collector: sec_updates and apt ==="
reset_fx
run_hkm --role web
[[ "$OUT" == *" sec_updates=2" ]] && R=0 || R=1; ok "two '-security' Inst lines counted (security-only and mixed-pocket count; updates-only fixture-tools and security-tools do not: security-tools has no leading hyphen, so it is NOT the foo-security-bar name case, which the pkgname row below characterizes)" "$R"
CALLS="$(cat "$FX/apt.calls" 2>/dev/null || true)"
eq "apt-get argv is EXACTLY '-s -o Debug::NoLocking=1 upgrade' (simulate, no lock, local lists), invoked once" "$(grep '^ARGS=' <<<"$CALLS" | sort | uniq -c | sed -E 's/^ +//')" "1 ARGS=-s -o Debug::NoLocking=1 upgrade"
no "apt-get never runs 'update' (local lists only)" "$([[ "$CALLS" == *"ARGS="*" update"* || "$CALLS" == *"ARGS=update"* ]] && echo 0 || echo 1)"
SEEN_PATH="$(sed -n 's/^PATH=//p' <<<"$CALLS" | sort -u)"
eq "the PATH apt-get sees is the stub dir followed by EXACTLY /usr/sbin:/usr/bin:/sbin:/bin (recorded by the stub, not a source grep)" "${SEEN_PATH#"$STUBS:"}" "/usr/sbin:/usr/bin:/sbin:/bin"
no "the caller's PATH is not inherited" "$([[ "$CALLS" == *"nonexistent-caller-path"* ]] && echo 0 || echo 1)"
ok "LC_ALL is forced to C" "$([[ "$CALLS" == *"LC_ALL=C"* ]] && echo 0 || echo 1)"
ok "script source exports LC_ALL=C" "$(grep -qE '^export LC_ALL=C$' "$SUT"; echo $?)"
no "script never puts /usr/local on the PATH it runs apt-get/uname/timeout under" "$(grep -E '^(export )?PATH=.*/usr/local' "$SUT" > /dev/null; echo $?)"

reset_fx; printf 'none\n' > "$FX/apt.mode"
run_hkm --role web
[[ "$OUT" == *" sec_updates=0" ]] && R=0 || R=1; ok "apt with nothing pending -> 0 (a zero is a measurement, not unknown)" "$R"

reset_fx; printf 'fail\n' > "$FX/apt.mode"
run_hkm --role web
eq "failing apt: exit 0" "$RC" "0"
[[ "$OUT" == *" sec_updates=unknown" ]] && R=0 || R=1; ok "failing apt -> sec_updates=unknown even with Inst lines on stdout" "$R"

reset_fx; printf 'hang\n' > "$FX/apt.mode"
START="$SECONDS"
run_hkm --role web
ELAPSED=$((SECONDS - START))
eq "timing-out apt: exit 0" "$RC" "0"
[[ "$OUT" == *" sec_updates=unknown" ]] && R=0 || R=1; ok "timing-out apt -> sec_updates=unknown" "$R"
ok "timing-out apt is bounded (well under the stub's 30 s sleep)" "$([[ "$ELAPSED" -lt 15 ]] && echo 0 || echo 1)"
grammar_ok web "$OUT"; ok "timing-out apt: the line is still grammatical" $?

# A hang that ignores TERM: bounded only by `timeout -k 2` (KILL after 2 s). Without -k the stub runs its full 25 s, far past the bound below.
reset_fx; printf 'hangterm\n' > "$FX/apt.mode"
START="$SECONDS"
run_hkm --role web
ELAPSED=$((SECONDS - START))
eq "TERM-ignoring apt: exit 0" "$RC" "0"
[[ "$OUT" == *" sec_updates=unknown" ]] && R=0 || R=1; ok "TERM-ignoring apt -> sec_updates=unknown" "$R"
ok "TERM-ignoring apt is bounded by the KILL escalation (elapsed ${ELAPSED}s, bound 10 s; the stub itself runs 25 s)" "$([[ "$ELAPSED" -lt 10 ]] && echo 0 || echo 1)"
grammar_ok web "$OUT"; ok "TERM-ignoring apt: the line is still grammatical" $?

# CHARACTERIZATION PIN (documents current behaviour, NOT a statement that the behaviour is right). The collector counts by NAME: a substring match of
# -security on the WHOLE Inst line (not the pocket field), so a package NAME containing -security on a non-security pocket is counted: 2 here (1 real + 1 by
# name), an overcount. sec_updates is display only (never feeds kernel_state), so the overcount is tolerated for now. TIGHTEN LATER: match the pocket field
# only; that is a deliberate edit of the collector (and its three copies) plus a flip of this row to expect 1.
reset_fx; printf 'pkgname\n' > "$FX/apt.mode"
run_hkm --role web
[[ "$OUT" == *" sec_updates=2" ]] && R=0 || R=1; ok "CHARACTERIZATION (known overcount, tighten later): package name foo-security-bar on a non-security pocket IS counted by the whole-line rule -> 2" "$R"

echo "=== collector: nothing measurable still exits 0 ==="
reset_fx; printf '1\n' > "$FX/uname.rc"; : > "$FX/uname.out"; rm -f "$FX/uptime"; printf 'fail\n' > "$FX/apt.mode"
HKM_REBOOT_FILE_OVERRIDE="$FX/no-such-dir/reboot-required" run_hkm --role web
eq "all four measurements failing: exit 0" "$RC" "0"
eq "all four measurements failing: every token says so" "$OUT" "SOLEUR_HOST_KERNEL v=1 role=web kernel=unreadable uptime_s=unknown reboot_required=unknown sec_updates=unknown"

echo "=== collector: registry host= ==="
KM_REGID="$(sed -n "s/^readonly REGISTRY_HOST_ID='\(.*\)'$/\1/p" "$SUT")"
[[ -n "$KM_REGID" ]] && R=0 || R=1; ok "the collector carries a registry id constant" "$R"
reg_host() { # <label> <printf-content-or-@fail>: whatever hostname prints, host= is the constant
  reset_fx
  if [[ "$2" == "@fail" ]]; then printf '1\n' > "$FX/hostname.rc"; : > "$FX/hostname.out"; else printf "$2" > "$FX/hostname.out"; fi
  run_hkm --role registry
  eq "registry host [$1]: exit 0" "$RC" "0"
  [[ "$OUT" == *" sec_updates=2 host=$KM_REGID" ]]; ok "registry host [$1] -> host=<constant>" $?
  grammar_ok registry "$OUT"; ok "registry host [$1]: grammar" $?
}
reg_host plain 'fixture-host-1\n'
reg_host spaced 'bad host\n'
reg_host meta 'x;id\n'
reg_host empty ''
reg_host failing '@fail'

echo "=== collector: exit 64 on a bad role or usage ==="
bad_usage() { # <label> <args...>
  local label="$1"; shift
  reset_fx
  run_hkm "$@"
  eq "usage [$label]: exit 64" "$RC" "64"
  eq "usage [$label]: nothing on stdout" "$OUT" ""
  no "usage [$label]: a message on stderr" "$([[ -z "$ERR" ]]; echo $?)"
}
bad_usage bogus-role --role bogus
bad_usage upper-case --role WEB
bad_usage empty-role --role ''
bad_usage injection --role 'web;id'
bad_usage prefix --role webx
bad_usage git-data --role git-data
bad_usage no-args
bad_usage missing-value --role
bad_usage unknown-flag --bogus
bad_usage extra-arg --role web extra
bad_usage duplicate-role --role web --role inngest
bad_usage template-instance-style web

echo "=== collector: the test seams are inert without HKM_TEST=1 ==="
reset_fx
SEAM_OUT="$(env -i PATH=/usr/bin:/bin HKM_FX="$FX" HKM_STUB_BIN_DIR="$STUBS" HKM_PROC_UPTIME="$FX/uptime" HKM_REBOOT_FILE="$FX/reboot-required" \
  HKM_APT_TIMEOUT_S=1 "$BASH" "$SUT" --role web 2> /dev/null)"
SEAM_RC=$?
eq "seams off: exit 0" "$SEAM_RC" "0"
no "seams off: the stubbed kernel is not used" "$([[ "$SEAM_OUT" == *"9.9.9"* ]] && echo 0 || echo 1)"
grammar_ok web "$SEAM_OUT"; ok "seams off: the real read still has the exact grammar" $?

echo "=== units: plain service and timer (no systemd template) ==="
ok "service: Type=oneshot" "$(grep -qxE 'Type=oneshot' "$SVC"; echo $?)"
ok "service: SyslogIdentifier=host-kernel-marker (anchored)" "$(grep -qxE 'SyslogIdentifier=host-kernel-marker' "$SVC"; echo $?)"
ok "service: ExecStart runs the installed collector with --role web" "$(grep -qxE 'ExecStart=/usr/local/bin/host-kernel-marker\.sh --role web' "$SVC"; echo $?)"
no "service: no template specifier (%i / %I / %n)" "$(grep -qE '%[iIn]' "$SVC"; echo $?)"
no "service: no EnvironmentFile (the marker needs no credential)" "$(grep -qE '^EnvironmentFile=' "$SVC"; echo $?)"
no "service: the test seam is never set by the unit" "$(grep -q 'HKM_' "$SVC"; echo $?)"
ok "service: TimeoutStartSec=60 (above the collector's own 20 s apt bound)" "$(grep -qxE 'TimeoutStartSec=60' "$SVC"; echo $?)"
ok "service: IOSchedulingClass=idle" "$(grep -qxE 'IOSchedulingClass=idle' "$SVC"; echo $?)"
ok "service: CPUSchedulingPolicy=idle" "$(grep -qxE 'CPUSchedulingPolicy=idle' "$SVC"; echo $?)"
# OOMPolicy is only honoured inside [Service]: the same line under [Install] (or any other section) is silently ignored by systemd, so the pin is section-aware.
in_section() { # <file> <section> <exact-line>: rc 0 iff the line sits inside [<section>] (the section header opens it, the next header closes it)
  awk -v sec="[$2]" -v want="$3" '/^\[/ { cur = $0 } cur == sec && $0 == want { found = 1 } END { exit found ? 0 : 1 }' "$1"
}
ok "service: OOMPolicy=continue sits in [Service] (an OOM kill of apt degrades sec_updates to unknown, it must not stop the unit before the line prints)" "$(in_section "$SVC" Service 'OOMPolicy=continue'; echo $?)"
OOM_MUT="$WORK/oom-in-install.service"
{ grep -vxF 'OOMPolicy=continue' "$SVC"; printf '\n[Install]\nOOMPolicy=continue\n'; } > "$OOM_MUT"
ok "mutant landed: the OOMPolicy line moved out of [Service] (control: the file still carries the line)" "$(grep -qxF 'OOMPolicy=continue' "$OOM_MUT"; echo $?)"
no "mutant: OOMPolicy=continue moved to [Install] is NOT accepted as in [Service]" "$(in_section "$OOM_MUT" Service 'OOMPolicy=continue'; echo $?)"
ok "service: MemoryMax=256M (a kill degrades the row to unknown tokens)" "$(grep -qxE 'MemoryMax=256M' "$SVC"; echo $?)"
no "service: no Restart= (a oneshot is re-run by its timer only)" "$(grep -qE '^Restart=' "$SVC"; echo $?)"
ok "timer: OnBootSec=2min" "$(grep -qxE 'OnBootSec=2min' "$TMR"; echo $?)"
ok "timer: 6-hourly OnCalendar" "$(grep -qxE 'OnCalendar=\*-\*-\* 00/6:00:00' "$TMR"; echo $?)"
ok "timer: Persistent=true" "$(grep -qxE 'Persistent=true' "$TMR"; echo $?)"
ok "timer: RandomizedDelaySec set" "$(grep -qE '^RandomizedDelaySec=[0-9]+(s|min|m)?$' "$TMR"; echo $?)"
no "timer: no AccuracySec override (the 1min default is what it would restate)" "$(grep -qE '^AccuracySec=' "$TMR"; echo $?)"
ok "timer: WantedBy=timers.target" "$(grep -qxE 'WantedBy=timers\.target' "$TMR"; echo $?)"
no "timer: no OnUnitActiveSec (cadence is the calendar, not drift)" "$(grep -qE '^OnUnitActiveSec=' "$TMR"; echo $?)"
no "timer: no template specifier" "$(grep -qE '%[iIn]' "$TMR"; echo $?)"
ok "no file in the set is a systemd template (no '@' in a name)" "$([[ "$(basename "$SUT")$(basename "$SVC")$(basename "$TMR")" != *@* ]] && echo 0 || echo 1)"

echo "=== sandbox copy: the four files run green from an empty directory ==="
if [[ "${HKM_TEST_SANDBOXED:-0}" != 1 ]]; then
  SBX="$WORK/sandbox"; assert_fixture_dir "$SBX"; mkdir -p "$SBX"
  cp "$SUT" "$SVC" "$TMR" "$SBX/"
  cp "${BASH_SOURCE[0]}" "$SBX/host-kernel-marker.test.sh"
  ( cd "$SBX" && HKM_TEST_SANDBOXED=1 HKM_ORIG_SUT="$SUT" TMPDIR="$WORK" bash ./host-kernel-marker.test.sh > "$WORK/sandbox.log" 2>&1 )
  SBX_RC=$?
  eq "sandbox copy: exit 0" "$SBX_RC" "0"
  ok "sandbox copy: reports its own pass line" "$(grep -q '^host-kernel-marker: PASS' "$WORK/sandbox.log"; echo $?)"
else
  # Sandbox child: same row count as the parent, so one literal floor covers both. These two rows prove the child really ran the COPIES, alone in its directory.
  no "sandbox child: the collector under test is a copy, not the repo original" "$([[ -n "${HKM_ORIG_SUT:-}" && "$SUT" -ef "$HKM_ORIG_SUT" ]] && echo 0 || echo 1)"
  eq "sandbox child: the directory holds exactly the four files" "$(cd "$SCRIPT_DIR" && ls | tr '\n' ' ')" "host-kernel-marker.service host-kernel-marker.sh host-kernel-marker.test.sh host-kernel-marker.timer "
fi

echo "=== static: no durable real-world strings ==="
no "suite/script carry no kernel-shaped string outside the synthesized 9.9.9 family" \
  "$(grep -hoE '[0-9]+\.[0-9]+\.[0-9]+-[0-9]+-[a-z]+' "$SUT" "$SVC" "$TMR" "${BASH_SOURCE[0]}" | grep -vE '^9\.9\.9-' > /dev/null; echo $?)"

echo
# MIN_CASES is the measured count, parent and sandbox child alike (the child runs two sandbox-only rows where the parent runs the two sandbox-copy
# rows, so one literal holds for both). It is a `-lt` floor, so only a REMOVED assertion trips it (an added one does not): it bounds shrinkage, not growth,
# and must be moved up by hand when rows are added. A literal bound directly above its floor (the vacuity ratchet builds its
# mutant from that shape); the floor is a direct printf + exit 1, never routed through fail().
MIN_CASES=176
if [[ "$cases" -lt "$MIN_CASES" ]]; then
  printf 'host-kernel-marker: FAIL (only %d assertions ran; floor %d - the suite may have been truncated)\n' "$cases" "$MIN_CASES" >&2
  exit 1
fi
if [[ $((passes + fails)) -ne "$cases" ]]; then
  printf 'host-kernel-marker: FAIL (accounting: passes+fails=%d != cases=%d; a verdict helper was neutered)\n' "$((passes + fails))" "$cases" >&2
  exit 1
fi
if [[ "$fails" -gt 0 ]]; then
  printf 'host-kernel-marker: FAIL (%d of %d assertions failed)\n' "$fails" "$cases" >&2
  exit 1
fi
printf '%d assertions passed\n' "$cases"
printf 'host-kernel-marker: PASS\n'
