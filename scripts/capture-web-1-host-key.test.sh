#!/usr/bin/env bash
# Hermetic tests for scripts/capture-web-1-host-key.sh (#7226, ADR-237 D2).
# ssh-keyscan is a stub (SSH_KEYSCAN) that prints a key generated at test time; nothing touches
# the network and no real host key is used. KNOWN_HOSTS points at a fixture file.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUT="$REPO_ROOT/scripts/capture-web-1-host-key.sh"
export TMPDIR="${TMPDIR:-/var/tmp}"
pass=0; fail=0; cases=0
ok() { pass=$((pass + 1)); echo "[ok] $1"; }
no() { fail=$((fail + 1)); echo "[FAIL] $1" >&2; }

[[ -r "$SUT" ]] || { echo "FATAL: $SUT not readable" >&2; exit 2; }
S="$(mktemp -d -t capweb1.XXXXXXXX)" || exit 2
trap 'rm -rf "$S"' EXIT

ssh-keygen -q -t ecdsa -b 256 -N '' -f "$S/ec" >/dev/null
ssh-keygen -q -t ecdsa -b 256 -N '' -f "$S/ec2" >/dev/null
ssh-keygen -q -t ed25519 -N '' -f "$S/ed" >/dev/null
EC="$(cut -d' ' -f1,2 "$S/ec.pub")"; EC2="$(cut -d' ' -f1,2 "$S/ec2.pub")"; ED="$(cut -d' ' -f1,2 "$S/ed.pub")"
IP=203.0.113.7   # TEST-NET-3 (RFC 5737), never a real host

# The stub prints $SCAN_OUT verbatim and records its argv.
cat > "$S/keyscan" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$SCAN_ARGV"
echo "# $4:22 SSH-2.0-OpenSSH_fixture" >&2
printf '%b' "$SCAN_OUT"
STUB
chmod +x "$S/keyscan"

# run <label-for-logs> <scan-output> [known_hosts content] -- env CI/GITHUB_ACTIONS cleared.
run() {
  printf '%s' "${3:-}" > "$S/known_hosts"
  rm -f "$S/out.pub"
  env -u CI -u GITHUB_ACTIONS SSH_KEYSCAN="$S/keyscan" KNOWN_HOSTS="$S/known_hosts" \
    SCAN_OUT="$2" SCAN_ARGV="$S/argv" bash "$SUT" "$IP" --out "$S/out.pub" >"$S/stdout" 2>"$S/stderr"
  RC=$?
}
want_fp="$(ssh-keygen -lf "$S/ec.pub" | awk '{ print $2 }')"

# C1: happy path, no prior entry.
cases=$((cases + 1)); run c1 "$IP $EC\n"
if [[ "$RC" -eq 0 && "$(awk '!/^#/ && NF' "$S/out.pub")" == "$EC" ]] \
   && grep -qxF "# fingerprint: $want_fp" "$S/out.pub" \
   && grep -qF "no prior known_hosts entry" "$S/out.pub"; then
  ok "C1: writes header (fingerprint, cross-check) + exactly the scanned key"
else no "C1: happy path (rc=$RC) $(<"$S/stderr")"; fi

cases=$((cases + 1))
if [[ "$(<"$S/argv")" == "-T 10 -t ecdsa $IP" ]]; then ok "C2: keyscan is called as '-T 10 -t ecdsa <ip>'"
else no "C2: keyscan argv was [$(<"$S/argv")]"; fi

cases=$((cases + 1))
if bash "$REPO_ROOT/.github/actions/cf-tunnel-ssh-bridge/write-known-hosts.sh" web-1 "$S/out.pub" "$S/kh.c3" >/dev/null 2>&1; then
  ok "C3: the written pin file passes the shared writer"
else no "C3: the written pin file fails the shared writer"; fi

# C4: prior matching entry.
cases=$((cases + 1)); run c4 "$IP $EC\n" "$IP $EC"$'\n'
if [[ "$RC" -eq 0 ]] && grep -qF "MATCHES the operator's existing" "$S/out.pub"; then ok "C4: a matching known_hosts entry is recorded"
else no "C4: matching cross-check (rc=$RC) $(<"$S/stderr")"; fi

# C5: prior DIFFERENT ECDSA entry -> refuse, nothing written.
cases=$((cases + 1)); run c5 "$IP $EC\n" "$IP $EC2"$'\n'
if [[ "$RC" -ne 0 && ! -e "$S/out.pub" ]] && grep -qF "MISMATCH" "$S/stderr"; then ok "C5: a differing known_hosts ECDSA entry refuses"
else no "C5: mismatch (rc=$RC)"; fi

# C6: prior entry of another type only -> not comparable, still written.
cases=$((cases + 1)); run c6 "$IP $EC\n" "$IP $ED"$'\n'
if [[ "$RC" -eq 0 ]] && grep -qF "none of type ecdsa-sha2-nistp256" "$S/out.pub"; then ok "C6: a non-ECDSA prior entry is reported as not comparable"
else no "C6 (rc=$RC) $(<"$S/stderr")"; fi

# Refusals: nothing written.
refuse() { # <label> <scan-output> [env...]
  local label="$1" out="$2"; shift 2
  cases=$((cases + 1))
  rm -f "$S/out.pub"; : > "$S/known_hosts"
  env -u CI -u GITHUB_ACTIONS "$@" SSH_KEYSCAN="$S/keyscan" KNOWN_HOSTS="$S/known_hosts" \
    SCAN_OUT="$out" SCAN_ARGV="$S/argv" bash "$SUT" "$IP" --out "$S/out.pub" >/dev/null 2>&1
  local rc=$?
  if [[ "$rc" -ne 0 && ! -e "$S/out.pub" ]]; then ok "$label"; else no "$label (rc=$rc, file written: $([[ -e $S/out.pub ]] && echo yes || echo no))"; fi
}
refuse "R1: CI=true refuses (Guard 1 row 7: no keyscan in CI)" "$IP $EC\n" CI=true
refuse "R2: GITHUB_ACTIONS=true refuses" "$IP $EC\n" GITHUB_ACTIONS=true
refuse "R3: an empty scan refuses" ""
refuse "R4: two scanned keys refuse" "$IP $EC\n$IP $EC2\n"
refuse "R5: an ED25519-only answer refuses (STOP, plan R5)" "$IP $ED\n"
refuse "R6: an answer for a different host refuses" "198.51.100.9 $EC\n"
refuse "R7: a malformed key body refuses" "$IP ${EC}xx\n"

cases=$((cases + 1))
env -u CI -u GITHUB_ACTIONS SSH_KEYSCAN="$S/keyscan" bash "$SUT" 10.0.1.10 --out "$S/out.pub" >/dev/null 2>&1; rc=$?
if [[ "$rc" -ne 0 ]]; then ok "R8: a private address refuses"; else no "R8: private address accepted"; fi
cases=$((cases + 1))
env -u CI -u GITHUB_ACTIONS bash "$SUT" >/dev/null 2>&1; rc=$?
if [[ "$rc" -eq 2 ]]; then ok "R9: no argument is a usage error (exit 2)"; else no "R9: rc=$rc"; fi

if (( pass + fail != cases )); then echo "[FATAL] accounting: $((pass + fail)) != $cases" >&2; exit 1; fi
if (( cases < 15 )); then echo "[FATAL] floor: $cases < 15" >&2; exit 1; fi
echo "=== capture-web-1-host-key: $pass passed, $fail failed ($cases cases) ==="
[[ "$fail" -eq 0 ]]
