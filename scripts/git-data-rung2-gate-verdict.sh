#!/usr/bin/env bash
# git-data-rung2-gate-verdict.sh — print the rung-2 gate's CURRENT verdict line, and nothing else.
#
# WHAT THIS IS FOR. `hr-observability-as-plan-quality-gate` requires a plan to name one command an
# operator can run LOCALLY (no ssh) that proves the signal is reachable. For this gate the signal IS
# a single line — `git_data_rung2_rehearsal_gate: RELEASED …` or `… HOLD [<TOKEN>] …` — so the
# discoverability probe is "show me that line". This script is that command.
#
# WHY IT EXISTS AS A FILE rather than a one-liner in the plan. The gate is a sourced bash LIBRARY
# with no CLI entry point, so reading its verdict needs `source` + a function call. `soleur:preflight`
# Check 10 rejects shell-active tokens in a declared command and runs what remains inside a bubblewrap
# sandbox with a 15s cap, so a `bash -c 'source …; gate …'` form cannot be declared at all. A
# repo-relative script is the shape that contract accepts (`bash <script>` is an allowlisted verb).
#
# WHY NOT THE SUITE. The plan first declared `bash tests/scripts/test-git-data-birth-readiness-gate.sh`.
# That is the right command to TEST the gate and the wrong one to DISCOVER its verdict: it takes
# minutes, so Check 10 killed it at 15s (rc=124) with the suite still passing arms, and its
# expected_output was prose no matcher can compare against. Measured during #8010's ship.
#
# WHY NOT THE #8210 PROBE. `scripts/followthroughs/git-data-reboot-evidence-landed-8210.sh` reads
# MAIN's evidence with MAIN's history and refuses on a branch by design (exit 2). It answers a
# different question — "has the evidence landed on main" — not "what does the gate say about the tree
# I am standing in".
#
# WHAT IT DOES NOT DO. It does not grade, retry, or interpret. It prints the gate's own first line and
# exits with the gate's own status, so the caller sees exactly what the CI step would see.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE_LIB="${ROOT}/tests/scripts/lib/git-data-birth-readiness-gate.sh"
TEMPLATE="${ROOT}/apps/web-platform/infra/cloud-init-git-data.yml"

if [[ ! -r "$GATE_LIB" ]]; then
  echo "UNAVAILABLE: no gate library at ${GATE_LIB}"
  exit 3
fi
if [[ ! -r "$TEMPLATE" ]]; then
  echo "UNAVAILABLE: no cloud-init template at ${TEMPLATE}"
  exit 3
fi

# shellcheck source=tests/scripts/lib/git-data-birth-readiness-gate.sh
source "$GATE_LIB" 2>/dev/null || {
  echo "UNAVAILABLE: the gate library could not be sourced"
  exit 3
}

out="$(git_data_rung2_rehearsal_gate "$TEMPLATE" 2>&1)"; rc=$?

# FIRST LINE ONLY, deliberately. The RELEASED line runs to several hundred characters and the HOLD
# lines carry a full remedy paragraph; a discoverability probe wants the verdict, not the essay. The
# bracketed token — the thing that distinguishes a measured refusal from an instrument failure — is
# always on this first line.
printf '%s\n' "$out" | head -1
exit "$rc"
