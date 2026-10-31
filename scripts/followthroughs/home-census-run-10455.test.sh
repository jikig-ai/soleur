#!/usr/bin/env bash
# Companion suite for scripts/followthroughs/home-census-run-10455.sh (notify-only: never exits 0 or 1).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROBE="$HERE/home-census-run-10455.sh"
PASS=0; FAIL=0
check() { if [[ "$2" -eq 0 ]]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); printf 'FAIL: %s\n' "$1"; fi; }
_p=$PASS; _f=$FAIL; check "instrument" 0; check "instrument" 1 >/dev/null; moved=$((FAIL - _f)); FAIL=$_f
if [[ "$PASS" -le "$_p" || "$moved" -lt 1 ]]; then printf 'instrument: a counter did not move\n'; exit 1; fi

run() { # earliest now
  OUT="$(env -i PATH="/usr/bin:/bin" SOLEUR_FT_EARLIEST="$1" HOME_CENSUS_PROBE_NOW="$2" bash "$PROBE" 2>&1)"; RC=$?
}
EARLIEST="2026-11-02T00:00:00Z"
E_EPOCH="$(date -u -d "$EARLIEST" +%s)"
declare -a RCS=()
run "$EARLIEST" "$((E_EPOCH - 1))";  RCS+=("$RC"); check "one second before earliest exits 2" "$([[ $RC -eq 2 ]]; echo $?)"
run "$EARLIEST" "$E_EPOCH";          RCS+=("$RC"); check "at earliest exits 5" "$([[ $RC -eq 5 ]]; echo $?)"
run "$EARLIEST" "$((E_EPOCH + 86400 * 30))"; RCS+=("$RC"); check "long after earliest still exits 5" "$([[ $RC -eq 5 ]]; echo $?)"
check "the action text names only the preflight command" "$(grep -q -- '--mode dry_run' <<<"$OUT" && ! grep -q -- '--mode real' <<<"$OUT"; echo $?)"
for bad in "" "tomorrow" "now" "@0" "2026-11-02" "2026-11-02T00:00:00+02:00"; do
  run "$bad" "$E_EPOCH"; RCS+=("$RC"); check "unusable clock '$bad' exits 3" "$([[ $RC -eq 3 ]]; echo $?)"
done
run "$EARLIEST" "not-a-number"; RCS+=("$RC"); check "unusable now exits 3" "$([[ $RC -eq 3 ]]; echo $?)"
for rc in "${RCS[@]}"; do check "never exits 0 or 1 (saw $rc)" "$([[ $rc -ne 0 && $rc -ne 1 ]]; echo $?)"; done
CODE="$(sed -E 's/^[[:space:]]*#.*$//' "$PROBE")"
check "the probe touches no secret, network or census" "$(! grep -qiE 'doppler|curl|wget|INNGEST|secret|gh api|gh issue' <<<"$CODE"; echo $?)"
check "the probe has a RETIREMENT line" "$(grep -q '^# RETIREMENT:' "$PROBE"; echo $?)"
if [[ "$PASS" -lt 24 ]]; then
  printf 'FLOOR: only %d assertions ran (expected at least 24)\n' "$PASS"
  exit 1
fi
printf 'home-census-run probe tests: %d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
