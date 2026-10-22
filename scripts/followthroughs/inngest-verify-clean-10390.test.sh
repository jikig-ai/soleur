#!/usr/bin/env bash
# inngest-verify-clean-10390.test.sh — verdict-matrix suite for
# scripts/followthroughs/inngest-verify-clean-10390.sh via the FT10390_QUERY_SH seam.
# The seam stub prints canned JSONEachRow; every row here is synthetic.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBE="$DIR/inngest-verify-clean-10390.sh"
passes=0; fails=0
pass() { passes=$((passes + 1)); }
fail() { fails=$((fails + 1)); echo "FAIL: $1" >&2; }

[ -f "$PROBE" ] || { echo "FATAL: probe missing" >&2; exit 1; }
bash -n "$PROBE" && pass || fail "probe bash -n"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/inngest-verify-clean-10390.XXXXXXXX")"; trap 'rm -rf "$WORK"' EXIT
# stub query: echoes a JSON row built from $FIX_ROW
cat > "$WORK/q.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$FIX_ROW"
exit "${FIX_QRC:-0}"
EOF
chmod +x "$WORK/q.sh"

run_probe() { # $1 = canned query JSON row; $FIX_QRC forces the stub's exit code
  env -i PATH="$PATH" HOME="$WORK" \
    BETTERSTACK_QUERY_HOST=h BETTERSTACK_QUERY_USERNAME=u BETTERSTACK_QUERY_PASSWORD=p \
    SOLEUR_FT_EARLIEST=2020-01-01T00:00:00Z \
    FT10390_QUERY_SH="$WORK/q.sh" FIX_ROW="$1" FIX_QRC="${FIX_QRC:-0}" \
    bash "$PROBE" 2>/dev/null
}

row() { printf '{"control_rows":%s,"vf_rows":%s,"vf_detailed":%s,"sig_rows":%s,"sig_detailed":%s}' "$1" "$2" "$3" "$4" "$5"; }

# dark channel → 3
run_probe "$(row 0 0 0 0 0)" >/dev/null 2>&1; [ $? -eq 3 ] && pass || fail "dark channel did not exit 3"
# undetailed signature row → FAIL(1)
run_probe "$(row 5 1 0 1 0)" >/dev/null 2>&1; [ $? -eq 1 ] && pass || fail "undetailed signature row did not exit 1"
# non-signature VERIFY_FAIL only → NOT a fail (the discriminator bug this suite exists for)
run_probe "$(row 5 2 0 0 0)" >/dev/null 2>&1; [ $? -eq 0 ] && pass || fail "non-signature VERIFY_FAIL rows must not FAIL (got non-0)"
# detailed signature rows still rejecting → NOT YET(2)
run_probe "$(row 5 1 1 1 1)" >/dev/null 2>&1; [ $? -eq 2 ] && pass || fail "detailed signature rows should be NOT YET (rc 2)"
# earliest in the future → NOT YET(2) — the "no evidence can exist yet" anti-vacuity arm;
# deleting it (earliest check absent) is invisible to every row above.
env -i PATH="$PATH" HOME="$WORK" \
  BETTERSTACK_QUERY_HOST=h BETTERSTACK_QUERY_USERNAME=u BETTERSTACK_QUERY_PASSWORD=p \
  SOLEUR_FT_EARLIEST=2999-01-01T00:00:00Z \
  FT10390_QUERY_SH="$WORK/q.sh" FIX_ROW="$(row 5 1 1 1 1)" \
  bash "$PROBE" >/dev/null 2>&1; [ $? -eq 2 ] && pass || fail "future earliest did not exit 2"
# transport error (stub rc=3) → CANNOT ESTABLISH(3), not a verdict on data that never arrived
FIX_QRC=3 run_probe "$(row 5 0 0 0 0)" >/dev/null 2>&1; [ $? -eq 3 ] && pass || fail "query transport rc=3 did not map to CANNOT ESTABLISH"
# generic nonzero transport → NOT YET(2), never a fail or pass
FIX_QRC=7 run_probe "$(row 5 0 0 0 0)" >/dev/null 2>&1; [ $? -eq 2 ] && pass || fail "query transport rc=7 did not map to NOT YET"
# xtrace with a live credential bound → refused(78), before any query runs
env -i PATH="$PATH" HOME="$WORK" \
  BETTERSTACK_QUERY_HOST=h BETTERSTACK_QUERY_USERNAME=u BETTERSTACK_QUERY_PASSWORD=p \
  SOLEUR_FT_EARLIEST=2020-01-01T00:00:00Z \
  bash -x "$PROBE" >/dev/null 2>&1; [ $? -eq 78 ] && pass || fail "xtrace+live-cred did not refuse (want 78)"

# clean → PASS(0)
run_probe "$(row 5 0 0 0 0)" >/dev/null 2>&1; [ $? -eq 0 ] && pass || fail "clean window did not PASS"
# missing creds → 3
env -i PATH="$PATH" SOLEUR_FT_EARLIEST=2020-01-01T00:00:00Z bash "$PROBE" >/dev/null 2>&1
[ $? -eq 3 ] && pass || fail "missing creds did not exit 3"
# malformed earliest → 3
env -i PATH="$PATH" BETTERSTACK_QUERY_HOST=h BETTERSTACK_QUERY_USERNAME=u BETTERSTACK_QUERY_PASSWORD=p \
  SOLEUR_FT_EARLIEST="not-a-date" FT10390_QUERY_SH="$WORK/q.sh" FIX_ROW="$(row 5 0 0 0 0)" bash "$PROBE" >/dev/null 2>&1
[ $? -eq 3 ] && pass || fail "malformed earliest did not exit 3"
# unparseable scan → 2
run_probe 'not-json' >/dev/null 2>&1; [ $? -eq 2 ] && pass || fail "unparseable scan did not exit 2"

# pass/fail counter self-test (sibling-suite convention): a rewritten fail() that still
# counts would satisfy a bare assertion-count floor — prove the instrument moves.
_pre="$passes"; pass; [ "$passes" -eq $((_pre + 1)) ] || fail "counter self-test: pass() did not increment"
MIN_ASSERTIONS=14
[ "$passes" -ge "$MIN_ASSERTIONS" ] \
  || { echo "FLOOR: ${passes} assertions < floor $MIN_ASSERTIONS — a block stopped running"; fails=$((fails+1)); }

echo "inngest-verify-clean-10390.test.sh: ${passes} passed, ${fails} failed"
[ "$fails" -eq 0 ] || exit 1
