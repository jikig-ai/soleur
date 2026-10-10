#!/usr/bin/env bash
# Behavioural table for the resolver's enforcement self-heal (op=enforcement_missing, #9392).
#
# WHAT IT PROVES.
#   1. `enforcement_probe` (extracted from cron-egress-resolve.sh, NO logic copy) reads the enforcement
#      rules with capture-then-match instead of `nft ... | grep -q` under `set -euo pipefail`, and is
#      THREE-valued per rule: present / absent / unreadable. A failed read is never reported as an absent
#      rule, except ENOENT (the object is gone), which IS an absent rule.
#   2. The self-heal BLOCK itself (extracted and EXECUTED with stub loader / sentry_event / log): the loader
#      re-runs iff a rule is not confirmed present and CRON_EGRESS_FROM_LOADER is not 1, the event posts
#      AFTER the loader and BEFORE `fail`, and the event carries the payload `enforcement_extra` built.
#   3. `enforcement_extra` field VALUES flow from the probe and the host, not just its key names.
# Each probe case runs in its own `bash -c 'set -euo pipefail'` subprocess against an `nft` shim on PATH
# whose output and exit status are per-scenario files.
#
# The ONE permitted logic copy is the OLD pipeline form in the SIGPIPE control rows (ambient, forced-ignored,
# forced-default): it no longer exists in the resolver, so the controls inline it to prove the reproducer
# really yields rc 141 (a reproducer that does not reproduce makes the new-form row vacuous).
#
# SIGPIPE DISPOSITION. A CI runner starts jobs with SIGPIPE ignored; a developer shell leaves it default. The
# re-exec below normalises the suite's own ambient to the default (what the reproducer assumed). This suite also
# makes the shim correct under BOTH: rows force SIGPIPE ignored per row (Linux only: proven by /proc SigIgn), so
# the ignored half stays covered. Reproduce the CI ambient with:
#   bash -c "trap '' PIPE; bash apps/web-platform/infra/cron-egress-self-heal.test.sh"
#
# Accounting: every verdict goes through check()/okc(), each bumping CASES. The suite end asserts
# PASS + FAIL == CASES; the helpers are negative-controlled first; mutation rows edit a COPY of the
# extracted library or block (literal replace, asserted to land) and require the discriminating row to change.
# shellcheck disable=SC2016,SC2329,SC2319  # payloads single-quoted; cleanup via trap; `[[ ]]; okc ... $?` is the suite idiom (okc records the verdict of the condition)
set -uo pipefail

# The SIGPIPE reproducer needs the DEFAULT SIGPIPE disposition, as a cron/systemd job has it. A step started
# with SIGPIPE ignored (the CI runner does: `echo: write error: Broken pipe` instead of a killed writer) turns
# the reproducer's rc 141 into 0, which fails the control row and its mutant for a reason that is not the
# resolver's. Bash cannot un-ignore a signal ignored at entry (`trap - PIPE` is a no-op), so re-exec once
# through python3, which restores SIG_DFL before exec. `SELF_HEAL_PIPE_RESET` bounds it to one re-exec.
if [[ -z "${SELF_HEAL_PIPE_RESET:-}" && "$(trap -p PIPE)" == *"''"* ]]; then
  if command -v python3 >/dev/null 2>&1; then
    SELF_HEAL_PIPE_RESET=1 exec python3 -c 'import os, signal, sys; signal.signal(signal.SIGPIPE, signal.SIG_DFL); os.execv(sys.argv[1], sys.argv[1:])' "$BASH" "$0" "$@"
  fi
  printf '[FATAL] SIGPIPE is ignored and python3 is unavailable to reset it: the SIGPIPE control row cannot run.\n' >&2
  exit 2
fi

export TMPDIR="${TMPDIR:-/var/tmp}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOLVER="${RESOLVER:-$SCRIPT_DIR/cron-egress-resolve.sh}"
LOADER_SRC="$SCRIPT_DIR/cron-egress-nftables.sh"
RUNBOOK="$SCRIPT_DIR/../../../knowledge-base/engineering/operations/runbooks/cron-egress-blocked.md"

PASS=0
FAIL=0
CASES=0
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }
check() { # check "label" want got
  CASES=$((CASES + 1))
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1 (want='$2' got='$3')"; fi
}
okc() { # okc "label" <exit status of the test just run>  (0 = holds)
  CASES=$((CASES + 1))
  if [[ "$2" == "0" ]]; then pass "$1"; else fail "$1"; fi
}
# Run an EXTERNAL command with SIGPIPE ignored on entry (an ignored signal survives exec). exec cannot run a
# shell function, so never pass one.
with_sigpipe_ignored() { ( trap '' PIPE; exec "$@" ); }
# SIGPIPE_PROBE reports the disposition of the shell that runs it, from /proc SigIgn (signal 13 is mask
# 0x1000); `unknown` (no /proc) fails the canary loud instead of skipping. The file is read ONCE into a
# variable and parsed from that: reading /proc/<pid>/status line by line under load can return no SigIgn line
# (measured 8 in 4500 runs; 0 in 4500 with the snapshot).
SIGPIPE_PROBE='st=""; { st=$(</proc/$$/status); } 2>/dev/null; sv=""; while read -r k v; do [[ "$k" == "SigIgn:" ]] && sv="$v"; done <<< "$st"; if [[ -z "$sv" ]]; then echo unknown; elif (( 0x$sv & 0x1000 )); then echo ignored; else echo default; fi'

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

WORK="$(mktemp -d "${TMPDIR}/self-heal-test.XXXXXX")"
assert_fixture_dir "$WORK"
cleanup() { assert_fixture_dir "$WORK"; rm -rf "$WORK"; }
trap cleanup EXIT

[[ -f "$RESOLVER" ]] || { echo "FATAL: resolver not found: $RESOLVER" >&2; exit 2; }

# --- negative control of the verdict-owning helpers --------------------------------------------
nc_p=$PASS; nc_f=$FAIL; nc_c=$CASES
check "negative-control mismatch" "want-A" "got-B" > "$WORK/nc1.out"
okc "negative-control failing condition" 1 > "$WORK/nc2.out"
check "negative-control match" "same" "same" > "$WORK/nc3.out"
okc "negative-control holding condition" 0 > "$WORK/nc4.out"
if (( FAIL - nc_f != 2 || PASS - nc_p != 2 || CASES - nc_c != 4 )) \
  || ! grep -q '^  FAIL: negative-control mismatch' "$WORK/nc1.out" \
  || ! grep -q '^  PASS: negative-control holding condition' "$WORK/nc4.out"; then
  printf '[FATAL] negative control: check()/okc() did not record the expected PASS/FAIL.\n' >&2
  exit 1
fi
PASS=$nc_p; FAIL=$nc_f; CASES=$nc_c

# --- extraction (no logic copy) ----------------------------------------------------------------
extract_fn() { # extract_fn name  (definition line `name() {` through the closing `}` at col 0)
  awk -v n="$1" '
    $0 == n "() {" { p = 1 }
    p { print }
    p && $0 == "}" { exit }' "$RESOLVER"
}
LIB="$WORK/lib.sh"
LIB_FNS="enforcement_probe enforcement_extra"
{
  echo '# generated by cron-egress-self-heal.test.sh from cron-egress-resolve.sh'
  for fn in $LIB_FNS; do extract_fn "$fn"; done
} > "$LIB"
BLOCK="$WORK/block.sh"
# The self-heal call site: from its guard `if` to the first column-0 `fi`.
awk '
  $0 == "if [[ \"${CRON_EGRESS_FROM_LOADER:-}\" != \"1\" ]]; then" { p = 1 }
  p { print }
  p && $0 == "fi" { exit }' "$RESOLVER" > "$BLOCK"
echo "-- extraction (non-vacuous) --"
for fn in $LIB_FNS; do
  n="$(extract_fn "$fn" | wc -l)"
  [[ "$n" -ge 15 ]]; okc "extracted $fn ($n lines; expected >= 15)" $?
done
n="$(wc -l < "$BLOCK")"
[[ "$n" -ge 10 ]]; okc "extracted self-heal block ($n lines; expected >= 10)" $?
grep -qE '^  enforcement_probe$' "$BLOCK"; okc "self-heal block carries the bare enforcement_probe call" $?
bash -n "$LIB"; okc "extracted library parses" $?
bash -n "$BLOCK"; okc "extracted block parses" $?

# --- shims -------------------------------------------------------------------------------------
SHIM="$WORK/shim"
assert_fixture_dir "$WORK"
mkdir -p "$SHIM"
cat > "$SHIM/nft" <<'SHIM_EOF'
#!/usr/bin/env bash
chain="${*: -1}"
case "$chain" in DOCKER-USER) k=jump ;; SOLEUR-EGRESS) k=chain ;; *) echo "nft shim: unhandled: $*" >&2; exit 99 ;; esac
n=$(( $(cat "$SC/$k.n" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$SC/$k.n"
ff="$(cat "$SC/$k.failfirst" 2>/dev/null || echo 0)"
if [[ -f "$SC/$k.enoent1" ]] && (( n == 1 )); then printf 'Error: No such file or directory\nlist chain ip filter %s\n' "$chain" >&2; exit 1; fi
if (( n <= ff )); then echo "netlink: Resource busy" >&2; exit 1; fi
if [[ -f "$SC/$k.enoent" ]]; then printf 'Error: No such file or directory\nlist chain ip filter %s\n' "$chain" >&2; exit 1; fi
if [[ -f "$SC/$k.enoent2" ]]; then printf 'Error: No such file or directory\nlist chain ip filter %s\n' "$chain" >&2; exit 2; fi
if [[ -f "$SC/$k.ruleerr" ]]; then printf 'Error: Could not process rule: No such file or directory\nlist chain ip filter %s\n' "$chain" >&2; exit 1; fi
if [[ -f "$SC/$k.lib127" ]]; then echo '/usr/sbin/nft: error while loading shared libraries: libnftables.so.1: cannot open shared object file: No such file or directory' >&2; exit 127; fi
if [[ -f "$SC/$k.sigpipe" ]]; then
  st=""; { st=$(</proc/$$/status); } 2>/dev/null; sv=""; while read -r sk sval; do [[ "$sk" == "SigIgn:" ]] && sv="$sval"; done <<< "$st"
  if [[ -z "$sv" ]]; then echo unknown > "$SC/shim.sigign"; elif (( 0x$sv & 0x1000 )); then echo ignored > "$SC/shim.sigign"; else echo default > "$SC/shim.sigign"; fi
  # A reader that hung up yields rc 141 under either inherited disposition: SIGPIPE death under a default
  # one, the failed (EPIPE) write under an ignored one. Without this the shim exits 0 on a CI runner.
  cat "$SC/$k.out"; /usr/bin/sleep 0.3
  { head -c 204800 /dev/zero | tr '\0' 'x'; } 2>/dev/null || exit 141
  echo
  exit "$(cat "$SC/$k.rc" 2>/dev/null || echo 0)"
fi
[[ -f "$SC/$k.out" ]] && cat "$SC/$k.out"
exit "$(cat "$SC/$k.rc" 2>/dev/null || echo 0)"
SHIM_EOF
cat > "$SHIM/systemctl" <<'SHIM_EOF'
#!/usr/bin/env bash
echo "$*" >> "$SC/systemctl.calls"
[[ -f "$SC/systemctl.fail" ]] && exit 1
case "$*" in *docker.service*) echo "DOCKERSTAMP" ;; *) echo "LOADERSTAMP" ;; esac
SHIM_EOF
cat > "$SHIM/timeout" <<'SHIM_EOF'
#!/usr/bin/env bash
echo "$*" >> "$SC/timeout.calls"
if [[ -n "${TIMEOUT_FORCE_RC:-}" && "$*" == *loader-stub* ]]; then exit "$TIMEOUT_FORCE_RC"; fi
while [[ "${1:-}" == -k ]]; do shift 2; done
shift
exec "$@"
SHIM_EOF
cat > "$SHIM/sleep" <<'SHIM_EOF'
#!/usr/bin/env bash
echo "$*" >> "$SC/sleep.calls"
[[ "${1:-}" =~ ^[0-9]+$ ]] || { echo "sleep: invalid time interval" >&2; exit 1; }
SHIM_EOF
cat > "$WORK/loader-stub.sh" <<'SHIM_EOF'
#!/bin/bash
echo "LOADER" >> "$CALLS"
exit "${LOADER_RC:-0}"
SHIM_EOF
chmod +x "$SHIM/nft" "$SHIM/systemctl" "$SHIM/timeout" "$SHIM/sleep" "$WORK/loader-stub.sh"

JUMP_PRESENT='table ip filter {
	chain DOCKER-USER {
		iifname "docker0" counter packets 1 bytes 60 jump SOLEUR-EGRESS comment "soleur-egress: jump"
	}
}'
JUMP_ABSENT='table ip filter {
	chain DOCKER-USER {
		counter packets 0 bytes 0 return
	}
}'
JUMP_NEAR='table ip filter {
	chain DOCKER-USER {
		iifname "docker0" counter jump SOLEUR-EGRESS-OLD comment "ref SOLEUR-EGRESS"
	}
}'
CHAIN_FULL='table ip filter {
	chain SOLEUR-EGRESS {
		ip daddr @soleur_egress_allow accept comment "soleur-egress: allowlist"
		limit rate 10/minute burst 50 packets log prefix "egress-blocked: " level notice comment "soleur-egress: default drop log"
		counter packets 3 bytes 180 drop comment "soleur-egress: default drop"
	}
}'
CHAIN_NODROP='table ip filter {
	chain SOLEUR-EGRESS {
		ip daddr @soleur_egress_allow accept comment "soleur-egress: allowlist"
		limit rate 10/minute burst 50 packets log prefix "egress-blocked: " level notice comment "soleur-egress: default drop log"
	}
}'
CHAIN_NOLOG='table ip filter {
	chain SOLEUR-EGRESS {
		ip daddr @soleur_egress_allow accept comment "soleur-egress: allowlist"
		counter packets 3 bytes 180 drop comment "soleur-egress: default drop"
	}
}'
CHAIN_LLLOG='table ip filter {
	chain SOLEUR-EGRESS {
		ip daddr 169.254.0.0/16 limit rate 6/minute burst 10 packets log prefix "egress-blocked: " level notice comment "soleur-egress: link-local (instance metadata) probe log"
		counter packets 3 bytes 180 drop comment "soleur-egress: default drop"
	}
}'
CHAIN_EMPTY='table ip filter {
	chain SOLEUR-EGRESS {
	}
}'
CHAIN_NOISY="$(printf 'table ip filter {\n\tchain SOLEUR-EGRESS {\n'; for i in $(seq 1 400); do printf '\t\tip daddr 10.%d.%d.1 tcp dport 443 accept comment "soleur-egress: noise"\n' "$((i / 250))" "$((i % 250))"; done; printf '\t\tlimit rate 10/minute burst 50 packets log prefix "egress-blocked: " level notice comment "soleur-egress: default drop log"\n\t\tcounter packets 3 bytes 180 drop comment "soleur-egress: default drop"\n\t}\n}')"

# scenario <name> <jump-out> <chain-out> <failfirst-jump> <failfirst-chain> <rc-jump> <rc-chain> [flags: sigpipe-jump enoent-jump enoent-chain enoent1-jump enoent2-jump ruleerr-jump lib127-jump enoent2-chain ruleerr-chain lib127-chain]
scenario() {
  local d="$WORK/sc.$1"
  assert_fixture_dir "$WORK"
  rm -rf "$d"; mkdir -p "$d"
  printf '%s\n' "$2" > "$d/jump.out"
  printf '%s\n' "$3" > "$d/chain.out"
  echo "$4" > "$d/jump.failfirst"; echo "$5" > "$d/chain.failfirst"
  echo "$6" > "$d/jump.rc"; echo "$7" > "$d/chain.rc"
  [[ " ${8:-} " == *" sigpipe-jump "* ]] && : > "$d/jump.sigpipe"
  [[ " ${8:-} " == *" enoent-jump "* ]] && : > "$d/jump.enoent"
  [[ " ${8:-} " == *" enoent-chain "* ]] && : > "$d/chain.enoent"
  [[ " ${8:-} " == *" enoent1-jump "* ]] && : > "$d/jump.enoent1"
  [[ " ${8:-} " == *" enoent2-jump "* ]] && : > "$d/jump.enoent2"
  [[ " ${8:-} " == *" ruleerr-jump "* ]] && : > "$d/jump.ruleerr"
  [[ " ${8:-} " == *" lib127-jump "* ]] && : > "$d/jump.lib127"
  [[ " ${8:-} " == *" enoent2-chain "* ]] && : > "$d/chain.enoent2"
  [[ " ${8:-} " == *" ruleerr-chain "* ]] && : > "$d/chain.ruleerr"
  [[ " ${8:-} " == *" lib127-chain "* ]] && : > "$d/chain.lib127"
  echo "$d"
}
# probe_out <lib> <scenario-dir>  -> "J|D|L|rcj|rcd|read_failed|read_retried|heal"
# PROBE_SIGPIPE_IGNORED=1 runs the probe with SIGPIPE ignored on entry (the shim's shim.sigign proves it).
probe_out() {
  ${PROBE_SIGPIPE_IGNORED:+with_sigpipe_ignored} env -i PATH="$SHIM:/usr/bin:/bin" SC="$2" NFT_RETRY_SLEEP="${NFT_RETRY_SLEEP:-0}" LIB="$1" bash -c '
    set -euo pipefail
    source "$LIB"
    enforcement_probe
    printf "%s|%s|%s|%s|%s|%s|%s|%s\n" "$ENF_JUMP" "$ENF_DROP" "$ENF_LOG" "$ENF_RC_JUMP" "$ENF_RC_DROP" "$ENF_READ_FAILED" "$ENF_READ_RETRIED" "$ENF_HEAL"
  ' 2>"$WORK/probe.err" || true
}

echo "-- three-valued read table (each case: its own set -euo pipefail subprocess) --"
TABLE_ROWS=0
row() { # row "label" want jump chain ffj ffc rcj rcc [flags]
  TABLE_ROWS=$((TABLE_ROWS + 1))
  local d
  d="$(scenario "r$TABLE_ROWS" "$3" "$4" "$5" "$6" "$7" "$8" "${9:-}")"
  check "$1" "$2" "$(probe_out "$LIB" "$d")"
}
#   label                                                   want J|D|L|rcj|rcd|failed|retried|heal            jump           chain          ffj ffc rcj rcc
row "both rules present: no heal"                           "present|present|present|0|0|false|false|false" "$JUMP_PRESENT" "$CHAIN_FULL"   0 0 0 0
row "jump absent: heal"                                     "absent|present|present|0|0|false|false|true"   "$JUMP_ABSENT"  "$CHAIN_FULL"   0 0 0 0
row "drop absent, LOG rule still there: heal (old check read this as healthy)" \
                                                            "present|absent|present|0|0|false|false|true"   "$JUMP_PRESENT" "$CHAIN_NODROP"  0 0 0 0
row "default-drop LOG rule absent, drop present: heal"      "present|present|absent|0|0|false|false|true"   "$JUMP_PRESENT" "$CHAIN_NOLOG"   0 0 0 0
row "both absent, every status 0 (a real external flush)"   "absent|absent|absent|0|0|false|false|true"    "$JUMP_ABSENT"  "$CHAIN_EMPTY"   0 0 0 0
row "noisy 400-rule chain around the needle: present"       "present|present|present|0|0|false|false|false" "$JUMP_PRESENT" "$CHAIN_NOISY"   0 0 0 0
row "a jump to SOLEUR-EGRESS-OLD (and a comment naming SOLEUR-EGRESS) is not our jump" \
                                                            "absent|present|present|0|0|false|false|true"   "$JUMP_NEAR"    "$CHAIN_FULL"   0 0 0 0
row "nft fails persistently (rc 1, netlink busy): unreadable, never absent" \
                                                            "unreadable|unreadable|unreadable|1|1|true|true|true" "" ""                       9 9 1 1
row "ONLY the chain read fails persistently: jump present, drop and log unreadable" \
                                                            "present|unreadable|unreadable|0|1|true|true|true" "$JUMP_PRESENT" ""            0 9 0 1
row "jump read fails once then succeeds: retried, no heal"  "present|present|present|0|0|false|true|false"  "$JUMP_PRESENT" "$CHAIN_FULL"   1 0 0 0
row "chain read fails once then succeeds: retried, no heal" "present|present|present|0|0|false|true|false"  "$JUMP_PRESENT" "$CHAIN_FULL"   0 1 0 0
row "read fails once then succeeds and the rule IS absent"  "absent|present|present|0|0|false|true|true"    "$JUMP_ABSENT"  "$CHAIN_FULL"   1 0 0 0
row "a read that fails TWICE is unreadable: the retry is bounded at one" \
                                                            "unreadable|present|present|1|0|true|true|true" "$JUMP_PRESENT" "$CHAIN_FULL"   2 0 0 0
row "nonzero status with a matching partial listing is still unreadable" \
                                                            "unreadable|present|present|1|0|true|true|true" "$JUMP_PRESENT" "$CHAIN_FULL"   0 0 1 0
row "ENOENT on both objects (a deleted table): absent, NOT contention, not retried" \
                                                            "absent|absent|absent|1|1|false|false|true"     "" ""                           0 0 0 0 "enoent-jump enoent-chain"
row "ENOENT on the SOLEUR-EGRESS chain only (chain deleted, jump present)" \
                                                            "present|absent|absent|0|1|false|false|true"    "$JUMP_PRESENT" ""              0 0 0 0 "enoent-chain"
row "a default-drop LOG rule lost while the link-local probe LOG rule (same egress-blocked prefix) remains: heal" \
                                                            "present|present|absent|0|0|false|false|true"   "$JUMP_PRESENT" "$CHAIN_LLLOG"   0 0 0 0
row "a missing nft binary (rc 127, '... No such file or directory'): unreadable, not ENOENT" \
                                                            "unreadable|present|present|127|0|true|true|true" "" "$CHAIN_FULL"             0 0 0 0 "lib127-jump"
row "ENOENT text with a different status (rc 2): unreadable, the status anchor matters" \
                                                            "unreadable|present|present|2|0|true|true|true" "" "$CHAIN_FULL"                0 0 0 0 "enoent2-jump"
row "another error that merely ends in the same words (Could not process rule: ...): unreadable" \
                                                            "unreadable|present|present|1|0|true|true|true" "" "$CHAIN_FULL"                0 0 0 0 "ruleerr-jump"
row "CHAIN read: a missing nft binary (rc 127) is unreadable, not ENOENT" \
                                                            "present|unreadable|unreadable|0|127|true|true|true" "$JUMP_PRESENT" ""         0 0 0 0 "lib127-chain"
row "CHAIN read: ENOENT text with a different status (rc 2) is unreadable" \
                                                            "present|unreadable|unreadable|0|2|true|true|true" "$JUMP_PRESENT" ""           0 0 0 0 "enoent2-chain"
row "CHAIN read: another error that merely ends in the same words is unreadable" \
                                                            "present|unreadable|unreadable|0|1|true|true|true" "$JUMP_PRESENT" ""           0 0 0 0 "ruleerr-chain"
row "ENOENT on the first read then a busy read: the per-attempt reset keeps it unreadable (not a stale absent)" \
                                                            "unreadable|present|present|1|0|true|true|true" "$JUMP_PRESENT" "$CHAIN_FULL"   2 1 0 0 "enoent1-jump"
row "SIGPIPE reproducer on the jump listing: new form reads present" \
                                                            "present|present|present|0|0|false|false|false" "$JUMP_PRESENT" "$CHAIN_FULL"   0 0 0 0 "sigpipe-jump"
if [[ "$TABLE_ROWS" -lt 25 ]]; then printf '[FATAL] probe table ran %d rows, expected >= 25.\n' "$TABLE_ROWS" >&2; exit 1; fi

# Precondition of the control below: SIGPIPE is not ignored (SigIgn bit 13 of this process; the re-exec at the top
# restores it when the runner started the step with it ignored). Named here so a removed re-exec reads as this, not as a resolver defect.
sig_ign="$(awk '/^SigIgn:/ {print $2}' /proc/$$/status 2>/dev/null)"
check "the suite runs with the default SIGPIPE disposition (the reproducer's precondition)" "0" "$(( (0x${sig_ign:-0} >> 12) & 1 ))"

# Control: the reproducer really reproduces. The OLD form on the SAME shim reads rc 141 under pipefail.
d="$(scenario control "$JUMP_PRESENT" "$CHAIN_FULL" 0 0 0 0 "sigpipe-jump")"
old_rc=0
env -i PATH="$SHIM:/usr/bin:/bin" SC="$d" bash -c 'set -o pipefail; nft list chain ip filter DOCKER-USER | grep -q "jump SOLEUR-EGRESS"' || old_rc=$?  # sigpipe-demo: intentional (the OLD pipeline form the SIGPIPE control must reproduce)
check "control: the OLD nft-piped-into-grep-q form on the reproducer shim returns 141 (SIGPIPE read as missing)" "141" "$old_rc"

# SIGPIPE disposition forced on entry, not left to the ambient: the CI runner's (ignored) AND a developer
# shell's (default) are both reproduced on any machine, and each forcing is proven (canary, recorder, routing).
echo "-- SIGPIPE disposition forced on entry (ignored and default) --"
check "harness canary: with_sigpipe_ignored really runs with SIGPIPE ignored" "ignored" "$(with_sigpipe_ignored bash -c "$SIGPIPE_PROBE")"
check "harness canary negative control: ignoring only SIGINT does not read as SIGPIPE ignored" "default" "$(bash -c "trap '' INT; $SIGPIPE_PROBE")"
d="$(scenario control-ign "$JUMP_PRESENT" "$CHAIN_FULL" 0 0 0 0 "sigpipe-jump")"
old_rc=0
with_sigpipe_ignored env -i PATH="$SHIM:/usr/bin:/bin" SC="$d" bash -c 'set -o pipefail; nft list chain ip filter DOCKER-USER | grep -q "jump SOLEUR-EGRESS"' || old_rc=$?  # sigpipe-demo: intentional (the same control with SIGPIPE forced ignored)
check "control, SIGPIPE ignored (forced): the OLD nft-piped-into-grep-q form on the reproducer shim returns 141 (the shim's EPIPE failure, read as missing)" "141" "$old_rc"
check "routing: the forced-ignored control ran the shim with SIGPIPE ignored" "ignored" "$(cat "$d/shim.sigign" 2>/dev/null || echo missing)"
cap="$(scenario capture-ign "$JUMP_PRESENT" "$CHAIN_FULL" 0 0 0 0 "sigpipe-jump")"
check "SIGPIPE ignored: the capture form on the reproducer shim still reads all three rules present" \
  "present|present|present|0|0|false|false|false" "$(PROBE_SIGPIPE_IGNORED=1 probe_out "$LIB" "$cap")"
check "routing: probe_out with the knob runs the shim with SIGPIPE ignored" "ignored" "$(cat "$cap/shim.sigign" 2>/dev/null || echo missing)"
d="$(scenario recorder-def "$JUMP_PRESENT" "$CHAIN_FULL" 0 0 0 0 "sigpipe-jump")"
env -i PATH="$SHIM:/usr/bin:/bin" SC="$d" nft list chain ip filter DOCKER-USER > /dev/null 2>&1
check "recorder negative control: the shim records default when SIGPIPE is default (the re-exec above guarantees it)" "default" "$(cat "$d/shim.sigign" 2>/dev/null || echo missing)"

echo "-- retry seam --"
d="$(scenario sleep1 "$JUMP_PRESENT" "$CHAIN_FULL" 1 0 0 0)"
NFT_RETRY_SLEEP=3 probe_out "$LIB" "$d" > /dev/null
check "one failed read sleeps exactly once, with the configured seconds" "3" "$(tr '\n' ' ' < "$d/sleep.calls" 2>/dev/null | sed 's/ $//')"
d="$(scenario sleep2 "$JUMP_PRESENT" "$CHAIN_FULL" 1 0 0 0)"
check "a non-numeric NFT_RETRY_SLEEP degrades to 1 s and never aborts the probe" \
  "present|present|present|0|0|false|true|false 1" "$(NFT_RETRY_SLEEP=abc probe_out "$LIB" "$d") $(tr '\n' ' ' < "$d/sleep.calls" 2>/dev/null | sed 's/ $//')"
d="$(scenario sleep4 "$JUMP_PRESENT" "$CHAIN_FULL" 1 0 0 0)"
check "an oversized NFT_RETRY_SLEEP (two digits) degrades to 1 s too" \
  "present|present|present|0|0|false|true|false 1" "$(NFT_RETRY_SLEEP=99 probe_out "$LIB" "$d") $(tr '\n' ' ' < "$d/sleep.calls" 2>/dev/null | sed 's/ $//')"
d="$(scenario sleep5 "" "" 9 9 1 1)"
probe_out "$LIB" "$d" > /dev/null
check "a persistently failing read sleeps exactly ONCE (never after the final attempt)" "1" "$(wc -l < "$d/sleep.calls" | tr -d ' ')"
d="$(scenario sleep3 "$JUMP_PRESENT" "$CHAIN_FULL" 0 0 0 0)"
NFT_RETRY_SLEEP=3 probe_out "$LIB" "$d" > /dev/null
check "a healthy read never sleeps" "" "$(cat "$d/sleep.calls" 2>/dev/null)"

# --- the extra payload -----------------------------------------------------------------------
echo "-- enforcement_extra --"
extra_json() { # extra_json <scenario-dir> [fault]  -> compact JSON on stdout
  local d="$1" fault="${2:-}"
  rm -f "$d/systemctl.fail" "$d/systemctl.calls" "$d/timeout.calls"
  assert_fixture_dir "$d"
  [[ "$fault" == "systemctl-fail" ]] && : > "$d/systemctl.fail"
  local shim="$SHIM"
  if [[ "$fault" == "jq-fail" ]]; then
    shim="$WORK/shim-jq"; mkdir -p "$shim"; cp "$SHIM"/* "$shim"/
    printf '#!/usr/bin/env bash\nexit 1\n' > "$shim/jq"; chmod +x "$shim/jq"
  fi
  env -i PATH="$shim:/usr/bin:/bin" SC="$d" NFT_RETRY_SLEEP=0 LIB="$LIB" LRC="${EXTRA_LRC:-0}" bash -c '
    set -euo pipefail
    source "$LIB"
    enforcement_probe
    enforcement_extra "$LRC"
  ' 2>/dev/null
}
jq_field() { python3 -c 'import json,sys; d=json.load(sys.stdin); print(d[sys.argv[1]])' "$1" 2>/dev/null || echo INVALID; }
d="$(scenario extra "$JUMP_PRESENT" "$CHAIN_NOLOG" 9 0 1 0)"
j="$(extra_json "$d")"
keys="$(printf '%s' "$j" | python3 -c 'import json,sys; print(",".join(sorted(json.load(sys.stdin))))' 2>/dev/null || echo INVALID)"
check "extra: exact key set" "docker_since,drop_present,host,jump_present,loader_rc,loader_since,log_present,rc_drop,rc_jump,read_failed,read_retried,remediation" "$keys"
check "extra: jump_present flows from the probe (jump read failing persistently)" "unreadable" "$(printf '%s' "$j" | jq_field jump_present)"
check "extra: drop_present flows from the probe" "present" "$(printf '%s' "$j" | jq_field drop_present)"
check "extra: log_present flows from the probe (the log rule is absent in this scenario)" "absent" "$(printf '%s' "$j" | jq_field log_present)"
check "extra: rc_jump carries the jump read's status" "1" "$(printf '%s' "$j" | jq_field rc_jump)"
check "extra: rc_drop carries the chain read's status (and is not the jump's)" "0" "$(printf '%s' "$j" | jq_field rc_drop)"
check "extra: read_failed is a true boolean when a read stayed unreadable" "True" "$(printf '%s' "$j" | jq_field read_failed)"
check "extra: read_retried is a true boolean after a retry" "True" "$(printf '%s' "$j" | jq_field read_retried)"
check "extra: docker_since is the docker.service stamp" "DOCKERSTAMP" "$(printf '%s' "$j" | jq_field docker_since)"
check "extra: loader_since is the cron-egress-firewall.service stamp (not docker's)" "LOADERSTAMP" "$(printf '%s' "$j" | jq_field loader_since)"
check "extra: host is this host's hostname" "$(hostname 2>/dev/null || echo unknown)" "$(printf '%s' "$j" | jq_field host)"
check "extra: loader_rc is 0 by default, and a NUMBER (not a string)" "0/int" "$(printf '%s' "$j" | jq_field loader_rc)/$(printf '%s' "$j" | python3 -c 'import json,sys; print(type(json.load(sys.stdin)["loader_rc"]).__name__)' 2>/dev/null)"
EXTRA_LRC=124 j2="$(extra_json "$d")"
check "extra: loader_rc carries the loader re-run's status (124 = timed out)" "124" "$(printf '%s' "$j2" | jq_field loader_rc)"
d2="$(scenario extra2 "$JUMP_PRESENT" "$CHAIN_FULL" 1 0 0 0)"
j3="$(extra_json "$d2")"
check "extra: a read that failed once and then succeeded is read_failed=False, read_retried=True (not swapped)" "False/True" "$(printf '%s' "$j3" | jq_field read_failed)/$(printf '%s' "$j3" | jq_field read_retried)"
check "extra: both systemctl reads are wrapped in timeout 2" "2" "$(grep -c '^2 systemctl show' "$d/timeout.calls" 2>/dev/null)"
j="$(extra_json "$d" systemctl-fail)"
check "extra: a failing systemctl read degrades to unknown, never aborts" "unknown unknown" "$(printf '%s' "$j" | jq_field docker_since) $(printf '%s' "$j" | jq_field loader_since)"
j="$(extra_json "$d" jq-fail)"
check "extra: a jq failure falls back to the minimal remediation object (valid JSON)" "['remediation']" "$(printf '%s' "$j" | python3 -c 'import json,sys; print(sorted(json.load(sys.stdin)))' 2>/dev/null || echo INVALID)"

# --- the self-heal block, EXECUTED -------------------------------------------------------------
echo "-- self-heal block (executed with a stub loader, sentry_event and log) --"
run_block() { # run_block <scenario-dir> <FROM_LOADER> <loader-rc> [block-file]  -> rc in BLOCK_RC; trace in $d/calls
  local d="$1" blk="${4:-$BLOCK}"
  assert_fixture_dir "$d"
  : > "$d/calls"
  BLOCK_RC=0
  env -i PATH="$SHIM:/usr/bin:/bin" SC="$d" NFT_RETRY_SLEEP=0 CRON_EGRESS_FROM_LOADER="$2" LOADER_RC="$3" TIMEOUT_FORCE_RC="${BLOCK_TIMEOUT_RC:-}" \
    LIB="$LIB" BLK="$blk" CALLS="$d/calls" LOADER="$WORK/loader-stub.sh" bash -c '
    set -euo pipefail
    source "$LIB"
    log() { echo "LOG|$*" | tee -a "$CALLS" > /dev/null; }
    fail() { echo "FAIL|$*" | tee -a "$CALLS" > /dev/null; exit 1; }
    sentry_event() { printf "SENTRY|%s|%s|%s\n" "$1" "$2" "$3" | tee -a "$CALLS" > /dev/null; }
    source "$BLK"
  ' 2>/dev/null || BLOCK_RC=$?
}
cnt() { grep -c "$2" "$1/calls" 2>/dev/null || true; }
lineno() { grep -n "$2" "$1/calls" 2>/dev/null | head -1 | cut -d: -f1; }
order() { # order <scenario-dir>: before|after|n/a  (loader line vs event line)
  local l s; l="$(lineno "$1" '^LOADER')"; s="$(lineno "$1" '^SENTRY')"
  if [[ -z "$l" || -z "$s" ]]; then echo "n/a"; elif (( l < s )); then echo before; else echo after; fi
}
payload_keys() { # payload_keys <scenario-dir>: key count of the posted event payload (0 when none posted)
  local pl; pl="$(grep '^SENTRY' "$1/calls" 2>/dev/null | head -1 | cut -d'|' -f4-)"
  if [[ -z "$pl" ]]; then echo 0; else printf '%s' "$pl" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))' 2>/dev/null || echo INVALID; fi
}
payload_field() { # payload_field <scenario-dir> <key>: one field of the posted event payload ("-" when none posted)
  local pl; pl="$(grep '^SENTRY' "$1/calls" 2>/dev/null | head -1 | cut -d'|' -f4-)"
  if [[ -z "$pl" ]]; then echo "-"; else printf '%s' "$pl" | jq_field "$2"; fi
}
MSG='cron-egress-firewall: enforcement rules were MISSING at tick (jump/drop absent) — loader re-run triggered'

d="$(scenario blk-ok "$JUMP_PRESENT" "$CHAIN_FULL" 0 0 0 0)"
run_block "$d" "" 0
check "block: healthy host: rc 0" "0" "$BLOCK_RC"
check "block: healthy host: no loader re-run, no event" "0/0" "$(cnt "$d" '^LOADER')/$(cnt "$d" '^SENTRY')"

d="$(scenario blk-absent "$JUMP_ABSENT" "$CHAIN_FULL" 0 0 0 0)"
run_block "$d" "" 0
check "block: jump absent: rc 0" "0" "$BLOCK_RC"
check "block: jump absent: the loader re-runs exactly once and the event posts exactly once" "1/1" "$(cnt "$d" '^LOADER')/$(cnt "$d" '^SENTRY')"
check "block: the loader re-run comes BEFORE the event post (egress is open until it does)" "before" "$(order "$d")"
check "block: the event message is byte-identical (same Sentry group)" "SENTRY|$MSG" "$(grep '^SENTRY' "$d/calls" | cut -d'|' -f1,2)"
check "block: the event op is enforcement_missing" "enforcement_missing" "$(grep '^SENTRY' "$d/calls" | cut -d'|' -f3)"
payload="$(grep '^SENTRY' "$d/calls" | cut -d'|' -f4-)"
check "block: the event carries the NEW payload (all 12 keys), fed from enforcement_extra" "12" "$(printf '%s' "$payload" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))' 2>/dev/null || echo INVALID)"
check "block: the payload carries the probe's rule states (jump absent) and the loader status (0)" "absent/0" "$(printf '%s' "$payload" | jq_field jump_present)/$(printf '%s' "$payload" | jq_field loader_rc)"
check "block: the heal WARN names the rule states, logged once" "1/1" "$(cnt "$d" '^LOG|WARN: enforcement rules missing')/$(cnt "$d" 'LOG|WARN.*jump=absent drop=present log=present read_failed=false')"

d="$(scenario blk-fail "$JUMP_ABSENT" "$CHAIN_FULL" 0 0 0 0)"
run_block "$d" "" 1
check "block: a failed loader re-run exits non-zero via fail" "1" "$BLOCK_RC"
ls_="$(lineno "$d" '^SENTRY')"; lf_="$(lineno "$d" '^FAIL')"
check "block: a failed loader re-run STILL posts the event exactly once, and posts it before fail" "1/ok" "$(cnt "$d" '^SENTRY')/$([[ -n "$ls_" && -n "$lf_" && "$ls_" -lt "$lf_" ]] && echo ok || echo bad)"
check "block: the failed re-run's status reaches the event (loader_rc=1) and the fail message" "1/1" "$(payload_field "$d" loader_rc)/$(grep -c '^FAIL|self-heal loader re-run failed (rc=1)' "$d/calls")"

d="$(scenario blk-hang "$JUMP_ABSENT" "$CHAIN_FULL" 0 0 0 0)"
BLOCK_TIMEOUT_RC=124 run_block "$d" "" 0
check "block: a loader that outlives its timeout (rc 124) still posts the event with loader_rc=124 and then fails" "1/124/1" "$(cnt "$d" '^SENTRY')/$(payload_field "$d" loader_rc)/$BLOCK_RC"
check "block: the loader call is wrapped in timeout -k 2 60" "1" "$(grep -c '^-k 2 60 .*loader-stub' "$d/timeout.calls" 2>/dev/null)"

d="$(scenario blk-fromloader "$JUMP_ABSENT" "$CHAIN_EMPTY" 0 0 0 0)"
run_block "$d" "1" 0
check "block: CRON_EGRESS_FROM_LOADER=1 skips the probe entirely (no loader -> resolver -> loader recursion)" "0/0/0" "$(cnt "$d" '^LOADER')/$(cnt "$d" '^SENTRY')/$(cnt "$d" '^LOG')"

d="$(scenario blk-unread "" "" 9 9 1 1)"
run_block "$d" "" 0
check "block: persistently unreadable chains still heal (idempotent loader), and the event says read_failed" "1/True" "$(cnt "$d" '^LOADER')/$(grep '^SENTRY' "$d/calls" | cut -d'|' -f4- | jq_field read_failed)"
check "block: the unreadable heal WARN names the unreadable states" "1" "$(cnt "$d" 'LOG|WARN.*jump=unreadable drop=unreadable log=unreadable read_failed=true')"

d="$(scenario blk-nolog "$JUMP_PRESENT" "$CHAIN_NOLOG" 0 0 0 0)"
run_block "$d" "" 0
check "block: a lost default-drop LOG rule alone heals (it feeds the egress_blocked page)" "1" "$(cnt "$d" '^LOADER')"
d="$(scenario blk-lllog "$JUMP_PRESENT" "$CHAIN_LLLOG" 0 0 0 0)"
run_block "$d" "" 0
check "block: the link-local probe LOG rule (same egress-blocked prefix) does not stand in for the default-drop LOG rule" "1" "$(cnt "$d" '^LOADER')"

# --- mutation rows: edit a COPY of the extracted library / block (literal replace, asserted to land) -----------
echo "-- mutation rows --"
MUT_ROWS=0
mut_copy() { # mut_copy <src> <dest> <old> <new> <label>: literal replace, exactly one occurrence, must parse
  MUT_ROWS=$((MUT_ROWS + 1))
  OLD="$3" NEW="$4" SRC="$1" DEST="$2" python3 - <<'PY' || { printf '[FATAL] mutation row %d did not land: %s\n' "$MUT_ROWS" "$5" >&2; exit 2; }
import os, sys
s = open(os.environ["SRC"]).read()
old = os.environ["OLD"]
if s.count(old) != 1:
    sys.exit(1)
open(os.environ["DEST"], "w").write(s.replace(old, os.environ["NEW"]))
PY
  cmp -s "$1" "$2" && { printf '[FATAL] mutation row %d is identical to pristine: %s\n' "$MUT_ROWS" "$5" >&2; exit 2; }
  bash -n "$2" 2>/dev/null || { printf '[FATAL] mutation row %d does not parse: %s\n' "$MUT_ROWS" "$5" >&2; exit 2; }
}
mut_probe() { # mut_probe "label" <old> <new> <want-pristine> <jump> <chain> <ffj> <ffc> <rcj> <rcc> [flags]; MUT_SIGPIPE_IGNORED=1 forces + requires SIGPIPE ignored
  local mlib="$WORK/mut.$((MUT_ROWS + 1)).sh" dd got
  mut_copy "$LIB" "$mlib" "$2" "$3" "$1"
  dd="$(scenario "m$MUT_ROWS" "$5" "$6" "$7" "$8" "$9" "${10}" "${11:-}")"
  got="$(PROBE_SIGPIPE_IGNORED="${MUT_SIGPIPE_IGNORED:-}" NFT_RETRY_SLEEP="${MUT_SLEEP:-0}" probe_out "$mlib" "$dd")"
  local verdict=0
  [[ "$got" != "$4" && ( -n "$got" || -n "${MUT_ALLOW_EMPTY:-}" ) ]] || verdict=1
  # With the knob set, a mutant row only counts if the shim really ran with SIGPIPE ignored.
  if [[ -n "${MUT_SIGPIPE_IGNORED:-}" ]]; then
    [[ "$(cat "$dd/shim.sigign" 2>/dev/null)" == "ignored" ]] || verdict=1
  fi
  okc "mutant caught: $1" "$verdict"
}
# harmless mutant: a whitespace respelling must grade EXACTLY like pristine (the row that proves a respelling is not mis-scored as a kill)
mut_copy "$LIB" "$WORK/mut.harmless.sh" 'local out_jump="" out_chain="" attempt' 'local out_jump=""  out_chain=""  attempt' "harmless whitespace respelling"
dd="$(scenario mharmless "$JUMP_ABSENT" "$CHAIN_FULL" 0 0 0 0)"
check "harmless mutant: a whitespace respelling grades exactly like pristine" "$(probe_out "$LIB" "$dd")" "$(probe_out "$WORK/mut.harmless.sh" "$dd")"
mut_probe "drop matched on the log prefix instead of the drop rule" \
  "comment \"soleur-egress: default drop\"'*" "egress-blocked'*" \
  "present|absent|present|0|0|false|false|true" "$JUMP_PRESENT" "$CHAIN_NODROP" 0 0 0 0
mut_probe "the retry is removed (a one-off read failure is no longer absorbed)" \
  "for attempt in 1 2; do" "for attempt in 1; do" \
  "present|present|present|0|0|false|true|false" "$JUMP_PRESENT" "$CHAIN_FULL" 1 0 0 0
mut_probe "the retry runs a third attempt (the bound is gone)" \
  "for attempt in 1 2; do" "for attempt in 1 2 3; do" \
  "unreadable|present|present|1|0|true|true|true" "$JUMP_PRESENT" "$CHAIN_FULL" 2 0 0 0
MUT_EARLY_PIPE='ip filter DOCKER-USER 2>&1 | grep -m1 "jump SOLEUR-EGRESS")"'  # sigpipe-demo: intentional (the early-exiting capture the mutants below re-introduce)
mut_probe "the capture is re-introduced as an early-exiting pipeline (SIGPIPE row changes)" \
  'ip filter DOCKER-USER 2>&1)"' "$MUT_EARLY_PIPE" \
  "present|present|present|0|0|false|false|false" "$JUMP_PRESENT" "$CHAIN_FULL" 0 0 0 0 "sigpipe-jump"
MUT_SIGPIPE_IGNORED=1 mut_probe "SIGPIPE ignored: the capture is re-introduced as an early-exiting pipeline (SIGPIPE row changes)" \
  'ip filter DOCKER-USER 2>&1)"' "$MUT_EARLY_PIPE" \
  "present|present|present|0|0|false|false|false" "$JUMP_PRESENT" "$CHAIN_FULL" 0 0 0 0 "sigpipe-jump"
mut_probe "ENOENT is no longer an absent object (a deleted table reads as contention)" \
  'if (( ENF_RC_JUMP == 1 )) && [[ "$out_jump" == "Error: No such file or directory"* ]]; then jump_gone=true; fi' ':' \
  "absent|absent|absent|1|1|false|false|true" "" "" 0 0 0 0 "enoent-jump enoent-chain"
mut_probe "the ENOENT status anchor is removed (rc 2 with the same text reads absent)" \
  '(( ENF_RC_JUMP == 1 )) && [[ "$out_jump" ==' '[[ "$out_jump" ==' \
  "unreadable|present|present|2|0|true|true|true" "" "$CHAIN_FULL" 0 0 0 0 "enoent2-jump"
mut_probe "the ENOENT text anchor is loosened to a suffix (another error ending in the same words reads absent)" \
  '[[ "$out_jump" == "Error: No such file or directory"* ]]' '[[ "$out_jump" == *"No such file or directory"* ]]' \
  "unreadable|present|present|1|0|true|true|true" "" "$CHAIN_FULL" 0 0 0 0 "ruleerr-jump"
mut_probe "the per-attempt jump_gone reset is removed (a stale ENOENT from attempt 1 survives a busy attempt 2)" \
  '    jump_gone=false; drop_gone=false' '    :' \
  "unreadable|present|present|1|0|true|true|true" "$JUMP_PRESENT" "$CHAIN_FULL" 2 1 0 0 "enoent1-jump"
mut_probe "the CHAIN-read ENOENT status anchor is removed (rc 2 with the same text reads absent)" \
  '(( ENF_RC_DROP == 1 )) && [[ "$out_chain" ==' '[[ "$out_chain" ==' \
  "present|unreadable|unreadable|0|2|true|true|true" "$JUMP_PRESENT" "" 0 0 0 0 "enoent2-chain"
mut_probe "the CHAIN-read ENOENT text anchor is loosened to a suffix (another error ending in the same words reads absent)" \
  '[[ "$out_chain" == "Error: No such file or directory"* ]]' '[[ "$out_chain" == *"No such file or directory"* ]]' \
  "present|unreadable|unreadable|0|1|true|true|true" "$JUMP_PRESENT" "" 0 0 0 0 "ruleerr-chain"
mut_extra() { # mut_extra "label" <old> <new> <pristine type name>
  local mlib="$WORK/mut.$((MUT_ROWS + 1)).sh" dd got
  mut_copy "$LIB" "$mlib" "$2" "$3" "$1"
  dd="$(scenario "m$MUT_ROWS" "$JUMP_PRESENT" "$CHAIN_FULL" 0 0 0 0)"
  got="$(env -i PATH="$SHIM:/usr/bin:/bin" SC="$dd" NFT_RETRY_SLEEP=0 LIB="$mlib" bash -c 'set -euo pipefail; source "$LIB"; enforcement_probe; enforcement_extra 124' 2>/dev/null | python3 -c 'import json,sys; print(type(json.load(sys.stdin)["loader_rc"]).__name__)' 2>/dev/null)"
  [[ "$got" != "$4" ]]; okc "mutant caught: $1" $?
}
mut_extra "loader_rc is emitted as a string (--arg instead of --argjson)" '--argjson lrc "$loader_rc"' '--arg lrc "$loader_rc"' "int"
mut_probe "the jump needle is a bare prefix (SOLEUR-EGRESS-OLD counts as ours)" \
  "jump_re='jump[[:space:]]+SOLEUR-EGRESS([[:space:]]|\$)'" "jump_re='jump[[:space:]]+SOLEUR-EGRESS'" \
  "absent|present|present|0|0|false|false|true" "$JUMP_NEAR" "$CHAIN_FULL" 0 0 0 0
mut_probe "a lost default-drop LOG rule no longer heals" \
  ' || "$ENF_LOG" != present' '' \
  "present|present|absent|0|0|false|false|true" "$JUMP_PRESENT" "$CHAIN_NOLOG" 0 0 0 0
MUT_SLEEP=abc MUT_ALLOW_EMPTY=1 mut_probe "the retry-sleep clamp is removed (a bad value aborts the probe)" \
  '[[ "$sleep_s" =~ ^[0-9]$ ]] || sleep_s=1' ':' \
  "present|present|present|0|0|false|true|false" "$JUMP_PRESENT" "$CHAIN_FULL" 1 0 0 0
# block mutants, driven through the EXECUTED block rows (graded against a PRISTINE control first)
mut_block() { # mut_block "label" <old> <new> <FROM_LOADER> <loader-rc> <want "LOADER/SENTRY/rc/order/payload-keys">
  local mblk="$WORK/mutblk.$((MUT_ROWS + 1)).sh" dd got
  mut_copy "$BLOCK" "$mblk" "$2" "$3" "$1"
  dd="$(scenario "mb$MUT_ROWS" "$JUMP_ABSENT" "$CHAIN_FULL" 0 0 0 0)"
  run_block "$dd" "$4" "$5" "$mblk"
  got="$(cnt "$dd" '^LOADER')/$(cnt "$dd" '^SENTRY')/$BLOCK_RC/$(order "$dd")/$(payload_keys "$dd")/$(payload_field "$dd" loader_rc)"
  [[ "$got" != "$6" ]]; okc "mutant caught: $1" $?
}
# pristine control: the grading string of the UNMUTATED block must equal the wanted value, so a broken payload_keys/order helper cannot make every mutant look caught
dd="$(scenario mb-control "$JUMP_ABSENT" "$CHAIN_FULL" 0 0 0 0)"
run_block "$dd" "" 0
check "mutation control: the unmutated block grades as LOADER/SENTRY/rc/order/keys/loader_rc = 1/1/0/before/12/0" "1/1/0/before/12/0" "$(cnt "$dd" '^LOADER')/$(cnt "$dd" '^SENTRY')/$BLOCK_RC/$(order "$dd")/$(payload_keys "$dd")/$(payload_field "$dd" loader_rc)"
mut_block "the heal condition keys on jump+drop both absent (a single lost rule no longer heals)" \
  'if [[ "$ENF_HEAL" == true ]]; then' 'if [[ "$ENF_JUMP" == absent && "$ENF_DROP" == absent ]]; then' "" 0 "1/1/0/before/12/0"
mut_block "the FROM_LOADER guard is inverted (the probe runs only under the loader)" \
  'if [[ "${CRON_EGRESS_FROM_LOADER:-}" != "1" ]]; then' 'if [[ "${CRON_EGRESS_FROM_LOADER:-}" == "1" ]]; then' "" 0 "1/1/0/before/12/0"
mut_block "the loader re-run is dropped from the heal path" \
  '    timeout -k 2 60 "$LOADER" || loader_rc=$?' '    :' "" 0 "1/1/0/before/12/0"
BLOCK_TIMEOUT_RC=124 mut_block "the loader timeout wrapper is removed (a wedged loader would take the event with it)" \
  'timeout -k 2 60 "$LOADER" || loader_rc=$?' '"$LOADER" || loader_rc=$?' "" 0 "0/1/1/n/a/12/124"
mut_block "the loader status is dropped from the payload (loader_rc always 0)" \
  'extra="$(enforcement_extra "$loader_rc")"' 'extra="$(enforcement_extra 0)"' "" 1 "1/1/1/before/12/1"
mut_block "the captured payload is replaced by the old one-key literal" \
  'extra="$(enforcement_extra "$loader_rc")"' 'extra="{\"remediation\":\"x\"}"' "" 0 "1/1/0/before/12/0"
mut_block "a failed loader re-run is swallowed (no fail)" \
  '(( loader_rc == 0 )) || fail "self-heal loader re-run failed (rc=$loader_rc)"' ':' "" 1 "1/1/1/before/12/1"
# ordering mutant: the loader runs AFTER the event (two literal edits on one copy)
mblk1="$WORK/mutblk.order1.sh"; mblk2="$WORK/mutblk.order2.sh"
mut_copy "$BLOCK" "$mblk1" '    timeout -k 2 60 "$LOADER" || loader_rc=$?
' '' "the loader runs after the event (step 1: remove the early call)"
mut_copy "$mblk1" "$mblk2" '    (( loader_rc == 0 )) || fail "self-heal loader re-run failed (rc=$loader_rc)"' '    timeout -k 2 60 "$LOADER" || loader_rc=$?
    (( loader_rc == 0 )) || fail "self-heal loader re-run failed (rc=$loader_rc)"' "the loader runs after the event (step 2: re-add it below the event)"
dd="$(scenario mb-order "$JUMP_ABSENT" "$CHAIN_FULL" 0 0 0 0)"
run_block "$dd" "" 0 "$mblk2"
[[ "$(order "$dd")" != "before" ]]; okc "mutant caught: the loader runs after the event post (egress stays open behind the POST)" $?
if [[ "$MUT_ROWS" -lt 25 ]]; then printf '[FATAL] mutation rows: only %d ran, expected >= 25.\n' "$MUT_ROWS" >&2; exit 1; fi

# --- the call site and its contracts (static, comment-stripped) ----------------------------------------------------
echo "-- resolver call site --"
HEAL_BLOCK="$(awk '/^# --- Self-heal: assert the enforcement rules are still live/{p=1} /^# --- GHCR deny probe/{p=0} p' "$RESOLVER" | grep -vE '^[[:space:]]*#')"
heal_lines="$(printf '%s\n' "$HEAL_BLOCK" | wc -l)"
[[ "$heal_lines" -ge 20 ]]; okc "the self-heal region was located non-vacuously ($heal_lines code lines)" $?
check "no 'nft ... | grep' pipeline is left in the self-heal region" "0" "$(printf '%s\n' "$HEAL_BLOCK" | grep -cE 'nft .*\|[[:space:]]*grep')"
grep -qE '^[[:space:]]+"cron-egress-firewall: enforcement rules were MISSING at tick \(jump/drop absent\) — loader re-run triggered" \\$' "$RESOLVER"; okc "the event message literal is byte-identical (same Sentry group)" $?
grep -qE '^[[:space:]]+"enforcement_missing" \\$' "$RESOLVER"; okc "the op literal stays top-level (the op-contract parser reads it)" $?
for lit in 'comment "soleur-egress: default drop"' 'comment "soleur-egress: default drop log"'; do
  grep -qF "$lit" "$RESOLVER" && grep -qF "$lit" "$LOADER_SRC"; okc "resolver and loader agree on the rule comment: $lit" $?
done
check "resolver and loader use the same jump_re literal" "$(grep -o "jump_re='[^']*'" "$LOADER_SRC" | head -1)" "$(grep -o "jump_re='[^']*'" "$RESOLVER" | head -1)"
RUNBOOK_KEYS=0
if [[ -f "$RUNBOOK" ]]; then
  TABLE="$(grep -E '^  \| ' "$RUNBOOK")"
  for k in jump_present drop_present log_present rc_jump rc_drop read_failed read_retried docker_since loader_since loader_rc host; do
    RUNBOOK_KEYS=$((RUNBOOK_KEYS + 1))
    printf '%s\n' "$TABLE" | grep -cF >/dev/null "\`$k"; okc "the runbook decode TABLE names the extra field $k" $?
  done
fi
if [[ "$RUNBOOK_KEYS" -ne 11 ]]; then printf '[FATAL] runbook parity ran %d rows, expected 11 (is the runbook missing?).\n' "$RUNBOOK_KEYS" >&2; exit 1; fi

echo
echo "self-heal suite: $PASS passed, $FAIL failed ($CASES cases)"
if [[ $((PASS + FAIL)) -ne "$CASES" ]]; then
  printf '\n[FATAL] accounting identity: PASS(%d) + FAIL(%d) != CASES(%d).\n' "$PASS" "$FAIL" "$CASES" >&2
  exit 1
fi
if [[ $((PASS + FAIL)) -lt 125 ]]; then
  printf '\n[FATAL] anti-vacuity floor: only %d verdict(s) recorded, expected >= 125. A row was deleted.\n' "$((PASS + FAIL))" >&2
  exit 1
fi
if [[ "$FAIL" -gt 0 ]]; then exit 1; fi
exit 0
