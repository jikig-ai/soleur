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

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
# stub query: echoes a JSON row built from $FIX_ROW
cat > "$WORK/q.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$FIX_ROW"
EOF
chmod +x "$WORK/q.sh"

run_probe() { # $1 = canned query JSON row
  env -i PATH=/usr/bin:/bin HOME="$WORK" \
    BETTERSTACK_QUERY_HOST=h BETTERSTACK_QUERY_USERNAME=u BETTERSTACK_QUERY_PASSWORD=p \
    SOLEUR_FT_EARLIEST=2020-01-01T00:00:00Z \
    FT10390_QUERY_SH="$WORK/q.sh" FIX_ROW="$1" \
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
# clean → PASS(0)
run_probe "$(row 5 0 0 0 0)" >/dev/null 2>&1; [ $? -eq 0 ] && pass || fail "clean window did not PASS"
# missing creds → 3
env -i PATH=/usr/bin:/bin SOLEUR_FT_EARLIEST=2020-01-01T00:00:00Z bash "$PROBE" >/dev/null 2>&1
[ $? -eq 3 ] && pass || fail "missing creds did not exit 3"
# malformed earliest → 3
run_probe "$(row 5 0 0 0 0)" >/dev/null 2>&1
env -i PATH=/usr/bin:/bin BETTERSTACK_QUERY_HOST=h BETTERSTACK_QUERY_USERNAME=u BETTERSTACK_QUERY_PASSWORD=p \
  SOLEUR_FT_EARLIEST="not-a-date" FT10390_QUERY_SH="$WORK/q.sh" FIX_ROW="$(row 5 0 0 0 0)" bash "$PROBE" >/dev/null 2>&1
[ $? -eq 3 ] && pass || fail "malformed earliest did not exit 3"
# unparseable scan → 2
run_probe 'not-json' >/dev/null 2>&1; [ $? -eq 2 ] && pass || fail "unparseable scan did not exit 2"

echo "inngest-verify-clean-10390.test.sh: ${passes} passed, ${fails} failed"
[ "$fails" -eq 0 ] || exit 1
