#!/usr/bin/env bash
# Weekly local runner for the #8323 transcript-format drift canary.
#
# WHY THIS EXISTS RATHER THAN A `soleur:schedule` WORKFLOW. The plan's task 4.2
# said to register the canary as a GitHub Actions schedule. Measured: the canary
# reads `~/.claude/projects/**/*.jsonl`, a GitHub runner has none, and the
# canary correctly reports TRANSIENT when it cannot measure. So that
# registration produces a probe that can never PASS and can never FAIL -- the
# could-not-measure / measured-bad collapse, in a probe whose whole purpose is
# to notice something. It runs here instead, on the machine that has the data.
#
# The `scripts/followthroughs/` script keeps the sweeper's 0/1/2 exit contract
# so it stays independently runnable and testable; this wrapper adapts it to a
# SessionStart hook, where ANY non-zero exit other than 2 makes Claude Code
# silently drop the output. It therefore exits 0 unconditionally and reports
# through stderr.
#
# Cadence is a stamp file, so the overwhelming majority of sessions pay one
# `find` and nothing else.

set -uo pipefail
trap 'exit 0' ERR EXIT

[[ "${SOLEUR_DISABLE_COMPACTION_HOOKS:-0}" == "1" ]] && exit 0

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -P "$SCRIPT_DIR/../.." && pwd -P)"
CANARY="$REPO_ROOT/scripts/followthroughs/compaction-format-drift-8323.sh"
[[ -x "$CANARY" ]] || exit 0

STAMP_DIR="${TMPDIR:-/tmp}/soleur-compaction"
STAMP="$STAMP_DIR/drift-canary.stamp"
INTERVAL_MIN="${SOLEUR_COMPACTION_DRIFT_INTERVAL_MIN:-10080}"   # 7 days
case "$INTERVAL_MIN" in ''|*[!0-9]*) INTERVAL_MIN=10080 ;; esac

# Ran recently enough? `find -newermt` would need a date string; -mmin is the
# direct question. A missing stamp means "never ran", which is due.
if [[ -f "$STAMP" ]]; then
  due="$(find "$STAMP" -maxdepth 0 -mmin "+$INTERVAL_MIN" -print 2>/dev/null || true)"
  [[ -n "$due" ]] || exit 0
fi

mkdir -p "$STAMP_DIR" 2>/dev/null || true
# Stamp BEFORE running, not after: a canary that hangs or dies must not re-fire
# on every subsequent session start.
: > "$STAMP" 2>/dev/null || true

# `out="$(...)"` is a SIMPLE command, so a non-zero status fires the ERR trap
# above and the wrapper exits 0 before it can report anything -- measured: the
# FAIL arm printed nothing. `|| rc=$?` puts it in a tested context, where bash
# exempts it (the same exemption that makes the `[[ ... ]] && ...` lists in
# compaction-state.sh safe).
rc=0
out="$(timeout 60 bash "$CANARY" 2>&1)" || rc=$?

case "$rc" in
  0) : ;;   # format still recognized; say nothing
  2) : ;;   # could not measure (no transcripts on this machine) -- not a finding
  *)
    # A real drift signal, or a genuinely compaction-free week. The message says
    # which readings it makes, so the reader does not have to re-derive them.
    printf 'SOLEUR_COMPACTION_DRIFT rc=%s -- the transcript format that compaction-state.sh\n' "$rc" >&2
    printf 'reports prior_boundaries from may have changed upstream, or this machine simply had\n' >&2
    printf 'no compactions in the scanned window. Re-run to see both readings:\n' >&2
    printf '  bash scripts/followthroughs/compaction-format-drift-8323.sh\n' >&2
    printf '%s\n' "$out" >&2
    ;;
esac
exit 0
