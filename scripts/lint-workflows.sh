#!/usr/bin/env bash
# Local entry point for linting .github/workflows/ with actionlint (#7002).
#
# WHY THIS EXISTS. actionlint pipes each `run:` body into shellcheck over a pipe. When a
# body exceeds the 65536-byte pipe buffer, actionlint blocks writing while shellcheck
# blocks reading, and the process NEVER RETURNS — so the repo's only workflow linter
# reported nothing at all, on every file, silently. Measured: cutover-inngest.yml's single
# 118722-byte run: body deadlocked; 65043 bytes completed and 65564 bytes hung, putting
# the threshold exactly at the pipe buffer.
#
# So this wrapper does three things a bare `actionlint` does not:
#   1. wraps the invocation in `timeout`, so a recurrence is a BOUNDED failure with a
#      nameable exit code instead of a hang someone eventually Ctrl-Cs;
#   2. reports `rc` explicitly and distinguishes 124 (HUNG — the #7002 defect) from
#      1 (findings, expected) and 0 (clean);
#   3. never pipes actionlint into `head`/`tail`, because `$?` after a pipe is the TAIL's
#      status — which is how a hang or a crash reads as success.
#
# EXITS 0 ON BOTH 0 AND 1. Findings are the expected steady state (93 of them across 20
# files as of 2026-07-28, 67% the benign SC2016 markdown-backtick shape; driving them down
# is tracked in #7042). A wrapper that exited non-zero on findings would break the
# discoverability chain in this repo's `discoverability_test` convention, where this script
# is chained after scripts/test-all.sh. Only a HANG is failure here.
#
# NO COMPANION .test.sh, DELIBERATELY — and NO LONGER BY PRECEDENT. This paragraph used to
# cite scripts/lint-orphan-test-suites.sh's "deliberately ~20 lines with NO companion
# .test.sh" header. That file grew to 396 lines and four independent checks while the header
# stayed, and #7402 both corrected it and gave it the companion suite it needed; the citation
# was borrowing authority from a claim that had stopped being true. The argument stands on its
# own facts instead: this is a ~20-line invocation wrapper with no decision logic of its own,
# and the property that matters — "actionlint terminates on this repo's workflows" — is
# enforced in CI by the actionlint hang guard step in .github/workflows/ci.yml, which is where
# a regression would actually be caught. A suite here would test `timeout`. If this file ever
# acquires decision logic, that reasoning expires with it.
#
# Usage:  bash scripts/lint-workflows.sh [<path>…]     # default: .github/workflows/

set -uo pipefail

# actionlint takes FILES, not a directory: `actionlint .github/workflows/` exits 3 with
# "is a directory", and only a bare `actionlint` auto-discovers. A wrapper that passed the
# directory would scan nothing and — unless every unrecognised status is a failure — report
# success forever. Hence the glob default AND the catch-all case arm below.
TARGETS=("$@")
if [[ "${#TARGETS[@]}" -eq 0 ]]; then
  shopt -s nullglob
  TARGETS=(.github/workflows/*.yml)
  shopt -u nullglob
  if [[ "${#TARGETS[@]}" -eq 0 ]]; then
    echo "lint-workflows: no .github/workflows/*.yml found from $(pwd) — refusing to report a clean sweep of nothing."
    exit 1
  fi
fi

if ! command -v actionlint >/dev/null 2>&1; then
  echo "lint-workflows: actionlint not installed."
  echo "  Install: go install github.com/rhysd/actionlint/cmd/actionlint@v1.7.7"
  echo "  or download the pinned release the CI hang guard uses (see .github/workflows/ci.yml)."
  exit 1
fi

# An OWNING trap, not an inline rm: the script can exit between allocation and cleanup via
# the `set -u` / signal paths, and a leaked file in a shared /tmp is the count-shaped growth
# tmpfs-guard cannot reclaim (#6734, ADR-129).
out="$(mktemp -t lint-workflows.XXXXXXXX.out)"
trap 'rm -f "$out"' EXIT INT TERM HUP

timeout 120 actionlint "${TARGETS[@]}" > "$out" 2>&1
rc=$?

cat "$out"

case "$rc" in
  0)
    echo "lint-workflows: rc=0 (clean)"
    ;;
  1)
    echo "lint-workflows: rc=1 (findings — expected; the census and ratchet are tracked in #7042)"
    ;;
  124)
    echo "lint-workflows: rc=124 — actionlint HUNG (#7002 recurrence)."
    echo "  A run: body has crossed the 65536-byte pipe buffer and deadlocked actionlint's"
    echo "  shellcheck integration. Find it with:"
    echo "    python3 -c 'import yaml,sys;d=yaml.safe_load(open(sys.argv[1]));[print(len(s[\"run\"]),s.get(\"name\")) for j in d[\"jobs\"].values() for s in j.get(\"steps\",[]) if \"run\" in s]' <workflow>"
    echo "  Fix by extracting the body to a checked-in script (precedent: scripts/cutover-inngest.sh)."
    echo "  Escape hatch to lint everything else meanwhile: actionlint -shellcheck= <paths>"
    exit 1
    ;;
  *)
    echo "lint-workflows: rc=$rc (unexpected — not 0, 1, or 124)"
    exit 1
    ;;
esac

exit 0
