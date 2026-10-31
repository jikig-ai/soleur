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
run "$EARLIEST" "$((E_EPOCH + 86400 * 10))"; RCS+=("$RC"); check "ten days after earliest (before the sunset) still exits 5" "$([[ $RC -eq 5 ]]; echo $?)"
check "the action text names only the preflight command" "$(grep -q -- '--mode dry_run' <<<"$OUT" && ! grep -q -- '--mode real' <<<"$OUT"; echo $?)"
run "$EARLIEST" "$(date -u -d "2026-11-30T00:00:00Z" +%s)"; RCS+=("$RC")
check "at the sunset the probe says to retire, not to run" "$([[ $RC -eq 5 ]] && grep -q 'sunset has passed' <<<"$OUT" && grep -q 'Do not run the census' <<<"$OUT"; echo $?)"
run "$EARLIEST" "$(( $(date -u -d "2026-11-30T00:00:00Z" +%s) - 1 ))"; RCS+=("$RC")
check "one second before the sunset it still says the census can be considered" "$([[ $RC -eq 5 ]] && grep -q 'can now be considered' <<<"$OUT"; echo $?)"
MOD_SUNSET="$(sed -n 's/^export const SUNSET_UTC = "\([^"]*\)";$/\1/p' "$HERE/../../apps/web-platform/server/home-census.ts")"
PROBE_SUNSET="$(sed -n 's/^SUNSET_UTC="\([^"]*\)"$/\1/p' "$PROBE")"
check "the probe's sunset equals the module's SUNSET_UTC (non-empty on both sides)" "$([[ -n "$MOD_SUNSET" && "$MOD_SUNSET" == "$PROBE_SUNSET" ]]; echo $?)"
check "the action text says a real run is blocked until the CLO discharge" "$(run "$EARLIEST" "$E_EPOCH"; grep -q 'blocked until the controller records the CLO discharge' <<<"$OUT"; echo $?)"
for bad in "" "tomorrow" "now" "@0" "2026-11-02" "2026-11-02T00:00:00+02:00"; do
  run "$bad" "$E_EPOCH"; RCS+=("$RC"); check "unusable clock '$bad' exits 3" "$([[ $RC -eq 3 ]]; echo $?)"
done
run "$EARLIEST" "not-a-number"; RCS+=("$RC"); check "unusable now exits 3" "$([[ $RC -eq 3 ]]; echo $?)"
for rc in "${RCS[@]}"; do check "never exits 0 or 1 (saw $rc)" "$([[ $rc -ne 0 && $rc -ne 1 ]]; echo $?)"; done
CODE="$(sed -E 's/^[[:space:]]*#.*$//' "$PROBE")"
check "the probe touches no secret, network or census" "$(! grep -qiE 'doppler|curl|wget|INNGEST|secret|gh api|gh issue' <<<"$CODE"; echo $?)"
check "the probe has a RETIREMENT line" "$(grep -q '^# RETIREMENT:' "$PROBE"; echo $?)"
if [[ "$PASS" -lt 29 ]]; then
  printf 'FLOOR: only %d assertions ran (expected at least 29)\n' "$PASS"
  exit 1
fi
printf 'home-census-run probe tests: %d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
