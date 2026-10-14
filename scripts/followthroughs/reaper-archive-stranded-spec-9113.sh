#!/usr/bin/env bash
# Follow-through probe for the reaper stranded-spec scope-out (Ref #9113 review).
#
# Defect: cleanup_merged_worktrees archives TRACKED KB files with plain `mv`,
# leaving unstaged deletions + untracked archive/ copies on the main checkout;
# the next session-start treats that state as stale and `git reset --hard`s it,
# resurrecting the live copy while the archive twin persists.
#
# Baseline verified at filing (2026-09-28): 3 live specs/feat-* dirs carry an
# archive twin. Re-eval trigger (counter): the twin count CHANGES — an
# increase means the defect kept firing (re-evaluate now); reaching 0 means
# the deferred dedup landed (close). Either transition exits 0 and closes
# this tracker; no-change returns TRANSIENT so the sweeper retries silently.
#
# Exit semantics (enforced by scripts/sweep-followthroughs.sh):
#   0 = PASS         (twin count changed; close the issue)
#   1 = FAIL         (unused here)
#   * = TRANSIENT    (no change / probe couldn't run; retry next sweep)
set -uo pipefail

# REFUSE TO RUN UNDER XTRACE (#7797).
case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: this probe handles live credentials and -x would print them (see #7797)\n' >&2; exit 78 ;;
esac

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SPECS="$REPO_ROOT/knowledge-base/project/specs"
[[ -d "$SPECS" && -d "$SPECS/archive" ]] || exit 2   # TRANSIENT: tree not laid out

live="$(mktemp)"; arch="$(mktemp)"
trap 'rm -f "$live" "$arch"' EXIT

ls -1 "$SPECS" | grep '^feat' | sort > "$live" || true
# Strip BOTH stamp prefixes (compact YYYYMMDD-HHMMSS- and legacy dashed
# YYYY-MM-DD-HHMMSS-) so either archive lineage matches its live twin.
ls -1 "$SPECS/archive" \
  | sed -E 's/^[0-9]{8}-[0-9]{6}-//; s/^[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{6}-//' \
  | sort > "$arch" || true

twins=$(comm -12 "$live" "$arch" | grep -c . || true)
if [[ "$twins" -ne 3 ]]; then
  printf 'stranded-spec twin count changed: baseline=3 now=%s\n' "$twins"
  exit 0
fi
exit 2
