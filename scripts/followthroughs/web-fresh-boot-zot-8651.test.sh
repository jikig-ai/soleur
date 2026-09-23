#!/usr/bin/env bash
# web-fresh-boot-zot-8651.test.sh — fixture test for the #8651 close probe (AC13b).
# The Sentry read is replaced by a fake boot-trail reader (WEB_ZOT_8651_TRAIL) that prints a
# fixture; every exit code of the sweeper contract is driven at least once, and each verdict is
# pinned by BOTH its exit code and its leading word.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBE="$DIR/web-fresh-boot-zot-8651.sh"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
pass=0; fail=0
ok() { pass=$((pass + 1)); echo "[ok] $1"; }
no() { fail=$((fail + 1)); echo "[FAIL] $1" >&2; }

fake() {  # <rc> <body...> : a boot-trail reader that prints the body and exits rc
  local rc="$1"; shift
  { echo '#!/usr/bin/env bash'
    echo '[ "$1" = --image-origin ] && [ "$2" = soleur-web-2 ] || { echo "fake: bad argv $*" >&2; exit 64; }'
    echo "cat <<'FIX'"; printf '%s\n' "$@"; echo 'FIX'
    echo "exit $rc"; } > "$WORK/trail.sh"
}
run() {  # <want-rc> <want-word> <label>
  local out rc=0
  out=$(WEB_ZOT_8651_TRAIL="$WORK/trail.sh" SENTRY_ACTIONS_RO_TOKEN=x bash "$PROBE" 2>&1) || rc=$?
  if [ "$rc" = "$1" ] && grep -q "^$2" <<<"$out"; then ok "$3 → exit $1 ($2)"
  else no "$3: want exit $1 + '$2', got exit $rc: $(tr '\n' ' ' <<<"$out" | head -c 240)"; fi
}

Z='image-origin: stage=app_zot host=soleur-web-2 time=2026-09-24T10:05:00Z detail=zot_login=ok ghcr_login=fail nic=ready:0'
NF='seed-fatal: stage=none host=soleur-web-2 time=- detail=-'

fake 0 "$Z" "$NF";                                                  run 0 PASS "zot-served boot, no seed fatal"
fake 0 "$Z" 'seed-fatal: stage=pull host=soleur-web-2 time=2026-09-24T09:00:00Z detail=x'; run 0 PASS "an OLDER seed fatal (the dark boot before the fix) does not block"
fake 0 "$Z" 'seed-fatal: stage=pull host=soleur-web-2 time=2026-09-24T11:00:00Z detail=x'; run 1 FAIL "a seed fatal NEWER than the zot boot"
fake 1 'image-origin: stage=none host=soleur-web-2 time=- detail=-' 'seed-fatal: stage=pull host=soleur-web-2 time=2026-09-24T11:00:00Z detail=x'; run 1 FAIL "dark boot with no origin event at all"
fake 1 'image-origin: stage=none host=soleur-web-2 time=- detail=-' "$NF";  run 2 "NOT YET" "no fixed-template boot observed yet (AC13b: no app_zot)"
fake 0 'image-origin: stage=app_ghcr_served host=soleur-web-2 time=2026-09-24T10:05:00Z detail=zot_login=fail ghcr_login=ok nic=ready:0' "$NF"; run 1 FAIL "GHCR served the boot"
fake 0 'image-origin: stage=app_zot host=soleur-web-2 time=2026-09-24T10:05:00Z detail=' "$NF"; run 1 FAIL "app_zot without zot_login=ok"
fake 2 'TRANSIENT: Sentry HTTP 500'; run 3 TRANSIENT "reader TRANSIENT"
fake 0 'garbage';                    run 3 TRANSIENT "unparseable reader output"
# AC13b: token unbound → CANNOT ESTABLISH, never a verdict.
rc=0; out=$(env -u SENTRY_ACTIONS_RO_TOKEN WEB_ZOT_8651_TRAIL="$WORK/trail.sh" bash "$PROBE" 2>&1) || rc=$?
[ "$rc" = 3 ] && grep -q '^TRANSIENT:' <<<"$out" && ok "token unbound → exit 3 (TRANSIENT)" || no "token unbound: rc=$rc out=$out"
# xtrace refusal (the credential is in the environment).
rc=0; SENTRY_ACTIONS_RO_TOKEN=x bash -x "$PROBE" >/dev/null 2>&1 || rc=$?
[ "$rc" = 78 ] && ok "refuses to run under xtrace (exit 78)" || no "xtrace refusal: rc=$rc"

[ $((pass + fail)) -ge 11 ] || { printf 'assertion floor: %d < 11\n' $((pass + fail)); exit 1; }
echo "=== web-fresh-boot-zot-8651: $pass passed, $fail failed ==="
[ "$fail" -eq 0 ]
