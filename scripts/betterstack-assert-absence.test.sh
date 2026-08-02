#!/usr/bin/env bash
# Tests for betterstack-assert-absence.sh (#7103 R3 4.8).
#
# The whole point of the helper is that it must NOT report `clean` when it does not know. So the
# arms that matter most are the ones where the transport misbehaves — a non-zero exit, an empty
# body, an HTML error page — because each of those is a state the naive row-count read reports
# as success.
#
# The transport is stubbed through BETTERSTACK_QUERY_SCRIPT. The stub DISPATCHES ON THE SQL it
# receives (control marker vs absence pattern) rather than answering identically to everything:
# a stub that ignores its input cannot tell "asked the right question and got zero" from "asked
# the wrong question", which is exactly the class of defect this helper exists to close.
set -euo pipefail

export TMPDIR="${TMPDIR:-/var/tmp}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/betterstack-assert-absence.sh"

pass=0; fail=0
ok()   { echo "  PASS: $1"; pass=$((pass + 1)); }
bad()  { echo "  FAIL: $1"; fail=$((fail + 1)); }
eq()   { if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi }

TMP=$(mktemp -d) || { echo "SETUP FAILED: mktemp"; exit 2; }
trap 'rm -rf "$TMP"' EXIT

# Build a stub transport. $1 = control row count, $2 = absence row count.
# A count of "FAIL" makes that arm exit non-zero; "GARBAGE" makes it emit unparseable output.
make_stub() {
  local control="$1" absence="$2"
  cat > "$TMP/stub.sh" <<STUB
#!/usr/bin/env bash
sql="\$1"
# Argv fidelity: mode 1 requires the SQL as the first positional. A caller that passed
# convenience flags instead would be a real defect (betterstack-query.sh would reject it with
# exit 64), so the stub refuses rather than helpfully answering.
case "\$sql" in
  SELECT*|*\$'\n'*SELECT*) : ;;
  *) echo "stub: expected raw SQL as \\\$1, got '\$sql'" >&2; exit 64 ;;
esac
# The host predicate must be present on every read, or another host's canary could certify this
# one. Asserted in the stub so EVERY arm below carries the check, not just a dedicated test.
case "\$sql" in
  *"JSONExtractString(raw,'host_name') = 'soleur-web-1'"*) : ;;
  *) echo "stub: read was not host-scoped" >&2; exit 65 ;;
esac
if [[ "\$sql" == *"SOLEUR_PROBE_CANARY"* ]]; then v="$control"; else v="$absence"; fi
case "\$v" in
  FAIL)    echo "simulated transport failure" >&2; exit 3 ;;
  GARBAGE) echo "<html>gateway timeout</html>" ;;
  EMPTY)   : ;;
  *)       echo "{\"n\":\"\$v\"}" ;;
esac
exit 0
STUB
  chmod +x "$TMP/stub.sh"
}

# Run the SUT against the current stub; sets RC and OUT.
run_sut() {
  RC=0
  OUT=$(BETTERSTACK_QUERY_SCRIPT="$TMP/stub.sh" bash "$SUT" \
    --host soleur-web-1 --absence 'IMAGE_PULL_FAIL' --since 6h 2>&1) || RC=$?
}

echo "=== betterstack-assert-absence.sh ==="

# --- clean: the only exit 0, and it requires a live control ---
make_stub 3 0; run_sut
eq "control>=1 and absence==0 exits 0 (clean)" "0" "$RC"
if grep -q 'outcome=clean' <<<"$OUT"; then ok "verdict line reports clean"; else bad "no clean verdict: $OUT"; fi
if grep -q 'control_rows=3' <<<"$OUT"; then ok "verdict line carries the control count"; else bad "control count missing: $OUT"; fi

# --- present: the absence pattern matched ---
make_stub 3 2; run_sut
eq "absence>0 exits 1 (present)" "1" "$RC"
if grep -q 'outcome=present' <<<"$OUT"; then ok "verdict line reports present"; else bad "no present verdict: $OUT"; fi

# --- unshipping: control is zero, so absence is meaningless ---
# THE HEADLINE ARM. Without it, a host that stopped shipping logs entirely reports `clean` —
# the reading that made #7095's telemetry unfalsifiable.
make_stub 0 0; run_sut
eq "control==0 exits 2 (unshipping), NOT 0" "2" "$RC"
if grep -q 'outcome=unshipping' <<<"$OUT"; then ok "verdict line reports unshipping"; else bad "no unshipping verdict: $OUT"; fi
if grep -qi 'dead vector agent from a dead probe unit' <<<"$OUT"; then
  ok "unshipping states its own limit rather than implying a diagnosis"
else
  bad "unshipping did not record what it cannot distinguish: $OUT"
fi

# --- unknown: the query did not answer ---
# Each transport failure shape gets its own arm. They fail differently (non-zero exit vs a
# 200 carrying an error body vs a genuinely empty body) and one representative case would let
# the other two regress into being read as zero.
make_stub FAIL 0; run_sut
eq "a non-zero transport exit on the control exits 3 (unknown)" "3" "$RC"
if grep -q 'outcome=unknown' <<<"$OUT"; then ok "transport failure reports unknown"; else bad "no unknown verdict: $OUT"; fi

make_stub GARBAGE 0; run_sut
eq "unparseable control output exits 3 (unknown), not 0" "3" "$RC"

make_stub EMPTY 0; run_sut
eq "an EMPTY control body exits 3 (unknown), not 0" "3" "$RC"

# The absence arm needs the same protection: a live control does not license trusting a
# transport that then failed on the second read.
make_stub 3 FAIL; run_sut
eq "a non-zero transport exit on the absence read exits 3 (unknown)" "3" "$RC"
make_stub 3 EMPTY; run_sut
eq "an EMPTY absence body exits 3 (unknown), not clean" "3" "$RC"

# --- ordering: unknown and unshipping dominate a zero absence ---
# If these were evaluated after the absence read, a dark channel with zero rows would exit 0.
make_stub FAIL EMPTY; run_sut
eq "unknown is evaluated before anything can read as clean" "3" "$RC"

# --- window discipline (4.4) ---
make_stub 3 0
RC=0; OUT=$(BETTERSTACK_QUERY_SCRIPT="$TMP/stub.sh" bash "$SUT" \
  --host soleur-web-1 --absence X --since 30m 2>&1) || RC=$?
eq "a sub-1h window is REJECTED by name, not evaluated" "64" "$RC"
if grep -q '1800s' <<<"$OUT"; then ok "rejection names the rate-limit that motivates it"; else bad "rejection did not explain itself: $OUT"; fi
RC=0; OUT=$(BETTERSTACK_QUERY_SCRIPT="$TMP/stub.sh" bash "$SUT" \
  --host soleur-web-1 --absence X --since 1h 2>&1) || RC=$?
eq "exactly 1h is accepted (boundary, not off-by-one)" "0" "$RC"

# --- malformed --since must be a USAGE error, never an outcome ---
# Found in review. The original implementation fed the flag straight to `$(( ))`; an arithmetic
# EXPANSION error is fatal at expansion time, so the `|| echo -1` guarding it never ran, `set -e`
# killed the script, and it exited **1** with empty output — and 1 is `present` in this script's
# own table. The follow-through probe maps `present` to FAIL, so a typo'd window would have
# reported "the credential channel has regressed" with no way to tell it was a usage error.
for badwin in '1;evil h' 'abc' '$(id) h' '1 h' 'h' '-5h'; do
  RC=0; OUT=$(BETTERSTACK_QUERY_SCRIPT="$TMP/stub.sh" bash "$SUT" \
    --host soleur-web-1 --absence X --since "$badwin" 2>&1) || RC=$?
  eq "malformed --since '$badwin' is a usage error (64), never an outcome code" "64" "$RC"
  if [[ -n "$OUT" ]]; then
    ok "  and it says why (non-empty diagnostic)"
  else
    bad "malformed --since '$badwin' exited silently — undiagnosable"
  fi
done

# --- required flags ---
RC=0; OUT=$(BETTERSTACK_QUERY_SCRIPT="$TMP/stub.sh" bash "$SUT" --absence X 2>&1) || RC=$?
eq "--host is required (an unscoped read is refused)" "64" "$RC"
RC=0; OUT=$(BETTERSTACK_QUERY_SCRIPT="$TMP/stub.sh" bash "$SUT" --host h 2>&1) || RC=$?
eq "--absence is required" "64" "$RC"

# --- host scoping is enforced against the SQL, not just documented ---
# The stub exits 65 if the read is not host-scoped; a passing run above already proves it, but
# assert the mechanism explicitly so removing the predicate cannot go unnoticed.
if grep -q "JSONExtractString(raw,'host_name') = '\${HOST_LIT}'" "$SUT"; then
  ok "the read carries an explicit host_name equality (not an OR-combined --grep term)"
else
  bad "host predicate is not an explicit host_name equality in the SQL"
fi
# And it must NOT reach for --grep, whose repeated terms OR-combine and would defeat scoping.
if grep -qE '^\s*[^#]*--grep' "$SUT"; then
  bad "the helper uses --grep, whose OR semantics let another host's canary certify this one"
else
  ok "the helper does not use --grep for scoping"
fi

# --- the archive arm is present (a hot-only read answers 6h with ~40 minutes) ---
# The `\$` is load-bearing, not incidental: the SQL lives in a double-quoted string, so the
# token must reach betterstack-query.sh UNexpanded for it to substitute the real table name.
# Matched with an optional backslash so the assertion pins the call shape rather than the
# quoting style of the line it happens to sit on.
# The table token below is a literal string being searched for in the SUT's source, not a
# variable this test wants expanded — hence single quotes and the directive.
# shellcheck disable=SC2016
if grep -qE 's3Cluster\(primary, \\?\$BS_TABLE_S3\)' "$SUT"; then
  ok "reads span the archive arm as well as the hot window"
else
  bad "no archive arm — a soak-length window would get a silently short answer"
fi

echo "---"
echo "betterstack-assert-absence.test.sh: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]] || exit 1
echo "OK"
