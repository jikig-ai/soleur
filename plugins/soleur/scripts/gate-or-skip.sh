#!/usr/bin/env bash
# The token-aware front door to the local affected-test gate (#12247).
#
# Work Phase 2 (step 9 and the fan-out lead's consolidation run) and review's lead gate call THIS instead of
# affected-tests.sh. On a BARE invocation it asks the one reader, `battery-owed.sh --token-only`, whether the operator's
# brief declared CI the gate (a `ci-is-the-gate` token in the branch's session-state.md). Exit 42 from the reader is the
# ONLY skip: the wrapper prints the reader's verdict, then `affected gate: SKIPPED (NOT run, NOT passed); CI test is the
# gate` and the machine line `AFFECTED_GATE_SKIPPED reason=operator-ci-is-the-gate`, and exits 0. Every other reader
# status (0 owed, 2 undecidable, 1 or 137 an error, or a missing reader) runs `affected-tests.sh` and returns its rc
# (0/1/4/6/7, see skills/ship/references/affected-gate-contract.md). The reader's rc is never parsed from its output.
#
# ANY argument (`--full`, `--explain`, `--base`, even an empty string) bypasses the token and goes to the gate verbatim:
# a preview or a full run must never be waived by a hint.
#
# NOT used by: soleur:ship (calls the reader directly, bare), soleur:test-fix-loop (a fix loop must run tests) and
# lefthook.yml's bun-test hook (deferred, #12297) nor the opt-in scripts/hooks/pre-push hook. The reader and the gate are siblings resolved from THIS file's own
# directory, never through CLAUDE_PLUGIN_ROOT (ADR-179: an env-directed root is a trust class).
# Precedent for the shape: collision-precheck.sh (no `-e`, siblings via BASH_SOURCE).
set -uo pipefail

HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P)"
READER="$HERE/../skills/ship/scripts/battery-owed.sh"
GATE="$HERE/affected-tests.sh"

if (( $# == 0 )) && [[ -r "$READER" ]]; then
  "$BASH" "$READER" --token-only
  rc=$?
  if (( rc == 42 )); then
    echo "affected gate: SKIPPED (NOT run, NOT passed); CI test is the gate"
    echo "AFFECTED_GATE_SKIPPED reason=operator-ci-is-the-gate"
    exit 0
  fi
fi
exec "$BASH" "$GATE" "$@"
