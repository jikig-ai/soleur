#!/usr/bin/env bash
# Wire check for mutation-scorer.sh consumers (#8855).
#
# mutation-scorer.test.sh proves the scorer is right; nothing there proves a battery still CALLS it.
# A battery whose call site became `if false`, or that went back to an inline scorer, keeps passing
# its own rows and reports every red row KILLED without attributing it. So: derive every battery
# that sources the lib, run each with MUTATION_SCORER_PROBE set, and require it to reach the scorer
# (the lib exits 86 and prints MUTATION_SCORER_PROBE_REACHED on its first call). Each run stops at
# that first call, so the cost is the battery's set-up plus one row.
#
# Scope: this proves a battery reaches the scorer at least once. A battery with several call sites
# (web-host-provisioner-parity has three) is pinned on the first one it reaches.
#
# Exit: 0 green; 1 a consumer did not reach the scorer or the consumer set shrank; 2 set-up fault.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || { echo "HARNESS ABORT: could not resolve this suite's directory" >&2; exit 2; }
ROOT="$(cd "$HERE/../../../.." && pwd)" || { echo "HARNESS ABORT: could not resolve the repo root" >&2; exit 2; }
command -v git >/dev/null 2>&1 || { echo "HARNESS ABORT: git missing — the consumer set cannot be derived" >&2; exit 2; }

T="$(mktemp -d -t mutation-scorer-consumers.XXXXXXXX)" || { echo "HARNESS ABORT: cannot create a scratch dir" >&2; exit 2; }
[[ "$T" == /* && -d "$T" && ! -L "$T" ]] || { echo "HARNESS ABORT: bad scratch dir '$T'" >&2; exit 2; }
trap 'rm -rf -- "$T"' EXIT INT TERM

# Every tracked shell file with a `source "…/lib/mutation-scorer.sh"` line. The lib's own self-test
# sources it as "$HERE/mutation-scorer.sh" and is not a battery, so it is not matched.
rc=0
git -C "$ROOT" grep -lE '^[[:space:]]*source[[:space:]].*/lib/mutation-scorer\.sh"' -- '*.sh' > "$T/consumers" || rc=$?
(( rc <= 1 )) || { echo "HARNESS ABORT: git grep failed (rc=$rc) — the consumer set cannot be derived" >&2; exit 2; }
mapfile -t CONSUMERS < "$T/consumers"

PASS=0; FAIL=0
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

# Floor: the six batteries #8855 routed through the lib. A shrinking set means a battery stopped
# sourcing the lib, which is the regression this suite exists to see. Raise it when one joins.
MIN_CONSUMERS=6
if (( ${#CONSUMERS[@]} < MIN_CONSUMERS )); then
  printf 'mutation-scorer consumers: only %d batteries source the lib (floor %d):\n' "${#CONSUMERS[@]}" "$MIN_CONSUMERS"
  printf '  %s\n' "${CONSUMERS[@]}"
  exit 1
fi

for c in "${CONSUMERS[@]}"; do
  log="$T/$(basename "$c").log"
  crc=0
  MUTATION_SCORER_PROBE=1 timeout -k 10 600 bash "$ROOT/$c" >"$log" 2>&1 || crc=$?
  if [[ "$crc" == 86 ]] && grep -qF 'MUTATION_SCORER_PROBE_REACHED' "$log"; then
    pass "$c reaches the scorer ($(grep -F 'MUTATION_SCORER_PROBE_REACHED' "$log" | head -1 | cut -d' ' -f2-3))"
  else
    fail "$c never reached mutation_scorer_failed_on (rc=$crc) — its row verdicts are not attributed"
    tail -5 "$log" | sed 's/^/      | /'
  fi
done

if (( FAIL != 0 || PASS != ${#CONSUMERS[@]} )); then
  printf 'mutation-scorer consumers: %d reached, %d did not, %d derived\n' "$PASS" "$FAIL" "${#CONSUMERS[@]}"
  exit 1
fi
echo "mutation-scorer consumers: all ${#CONSUMERS[@]} reach the scorer"
