#!/usr/bin/env bash
# Fixture tests for the #8611 double-bill follow-through probe. A stub query helper returns one
# aggregate row per case; each FAIL arm is driven by exactly one field so no arm is vacuous.
# Live calibration (2026-09-23, 7-day pre-deploy window): markers=117 cron_markers=30 cron_ids=22,
# i.e. the probe reads the pre-fix double-runs as FAIL — which is why its window starts after deploy.
set -uo pipefail

TMP_ROOT=$(mktemp -d -t ft8611root.XXXXXXXX) || { echo "FATAL: could not create scratch root" >&2; exit 1; }
[[ "$TMP_ROOT" == /* && -d "$TMP_ROOT" && ! -L "$TMP_ROOT" ]] || { echo "FATAL: bad scratch root: $TMP_ROOT" >&2; exit 1; }
trap 'rm -rf -- "$TMP_ROOT"' EXIT

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROBE="$REPO_ROOT/scripts/followthroughs/anthropic-double-bill-8611.sh"
[[ -f "$PROBE" ]] || { echo "FATAL: probe not found at $PROBE" >&2; exit 1; }

passes=0
FAILURES=()
pass() { echo "  PASS: $1"; passes=$((passes + 1)); }
fail() { echo "  FAIL: $1"; FAILURES+=("$1"); }

# run_case <label> <expected-rc> <stub-rc> <stub-stdout> [extra env...]
run_case() {
  local label="$1" want="$2" stub_rc="$3" stub_out="$4"; shift 4
  local stub="$TMP_ROOT/stub-$passes-${#FAILURES[@]}.sh"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" %q\nexit %s\n' "$stub_out" "$stub_rc" > "$stub"
  local got
  env -i PATH="$PATH" HOME="$TMP_ROOT" \
    BETTERSTACK_QUERY_HOST=h BETTERSTACK_QUERY_USERNAME=u BETTERSTACK_QUERY_PASSWORD=p \
    FT8611_MERGE_EPOCH=1790000000 FT8611_QUERY_SH="$stub" "$@" \
    bash "$PROBE" >/dev/null 2>&1
  got=$?
  if [ "$got" -eq "$want" ]; then pass "$label (rc=$got)"; else fail "$label: want rc=$want, got rc=$got"; fi
}

row() { # row markers leader_turns leader_retries leader_keys cron_markers cron_ids
  printf '{"markers":"%s","leader_turns":"%s","leader_retries":"%s","leader_keys":"%s","cron_markers":"%s","cron_ids":"%s"}' "$@"
}

echo "anthropic-double-bill-8611 probe:"
run_case "healthy: leader turns seen, no retries, no duplicates" 0 0 "$(row 40 3 0 3 12 12)"
run_case "leader attempt > 0 is a double bill"                    1 0 "$(row 40 3 1 3 12 12)"
run_case "two markers for one (id, turn) is a double bill"        1 0 "$(row 40 3 0 2 12 12)"
run_case "two cron markers for one run id is a double run"        1 0 "$(row 40 3 0 3 13 12)"
run_case "zero markers is a dark channel, never a clean zero"     1 0 "$(row 0 0 0 0 0 0)"
run_case "no leader-loop turn yet is NOT YET"                     2 0 "$(row 40 0 0 0 12 12)"
run_case "unparseable result is NOT YET, never PASS"              2 0 "Code: 62. DB::Exception: Syntax error"
run_case "query helper transient error is NOT YET"                2 1 ""
run_case "query helper 'nothing was queried' is CANNOT ESTABLISH" 3 3 ""
run_case "missing credential is CANNOT ESTABLISH"                 3 0 "$(row 40 3 0 3 12 12)" BETTERSTACK_QUERY_PASSWORD=
run_case "non-numeric merge floor is CANNOT ESTABLISH"            3 0 "$(row 40 3 0 3 12 12)" FT8611_MERGE_EPOCH=abc

if [ "${#FAILURES[@]}" -gt 0 ]; then
  printf '%s passed, %s failed\n' "$passes" "${#FAILURES[@]}"; exit 1
fi
# Anti-vacuity floor, reported outside the helpers it backstops (ADR-193: printf + exit 1).
if [[ "$passes" -lt 11 ]]; then
  printf '[FATAL] anti-vacuity floor: only %s cases passed (expected 11)\n' "$passes" >&2
  exit 1
fi
printf '%s passed, 0 failed\n' "$passes"
