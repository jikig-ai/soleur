#!/usr/bin/env bash
# Follow-through probe for the archive-kb.sh staged-rename scope-out (PR #9136
# review; parent defect class #9127).
#
# Deferred finding: archive-kb.sh performs `git add` + `git mv` for interactive
# KB archival and never commits. On a non-committable checkout (main/master,
# detached, bare) that leaves a staged-but-unpersisted rename which the next
# session-start `git reset --hard` (SOLEUR-GUARD-MAINRESET) reverts
# symmetrically — the archive operation is silently undone (weaker than the
# reaper's live+archive twin, same unpersisted-mutation family).
#
# Re-eval trigger (dependency + event-grep, either arm fires):
#   dependency   — issue #7400 (retire KB archival) closes: the archive-kb.sh
#                  fix is then either moot or overdue.
#   event-grep   — a NEW specs/ live∩archive twin appears (any producer),
#                  i.e. the twin count rises above its post-#9127-dedup zero.
#
# Exit semantics (enforced by scripts/sweep-followthroughs.sh):
#   0 = PASS         (trigger fired; close this tracker, the work is due)
#   1 = FAIL         (unused here)
#   * = TRANSIENT    (neither arm fired / probe couldn't run; retry next sweep)
set -uo pipefail

# REFUSE TO RUN UNDER XTRACE (#7797).
case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: this probe handles live credentials and -x would print them (see #7797)\n' >&2; exit 78 ;;
esac

# Arm 1 (dependency): #7400 closed.
if grep -qi '^CLOSED$' < <(gh issue view 7400 --repo jikig-ai/soleur --json state --jq '.state' 2>/dev/null); then
  echo "dependency arm fired: #7400 (retire KB archival) is closed — archive-kb.sh fix is due-or-moot"
  exit 0
fi

# Arm 2 (event-grep): any live∩archive spec twin (the post-9127 baseline is 0).
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
if [[ "$twins" -gt 0 ]]; then
  echo "event-grep arm fired: $twins stranded spec twin(s) present (post-#9127 baseline is 0)"
  exit 0
fi
exit 2
