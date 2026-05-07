#!/usr/bin/env bash
# Forbids `show_full_output: true` in recurring (non-`--once`) scheduled
# workflows. The action's docstring warns the flag leaks ALL tool execution
# results to public GHA logs. The --once template flips it because its prompt
# is committed verbatim with a fixed tool surface; recurring schedules
# accumulate new tool calls + skill invocations over time, where the
# bound-at-create-time safety reasoning does NOT extend.
#
# Detection heuristic: a workflow file whose `name:` does NOT start with
# `"Scheduled (once):"` (the canonical --once template prefix per
# plugins/soleur/skills/schedule/SKILL.md Step 3b) is treated as recurring,
# and its `show_full_output: true` is a violation.
#
# Waiver: a comment line containing `# allow-show-full-output:` (with any
# trailing reason text) anywhere in the same file suppresses the lint for
# that file. Use sparingly — it should be obvious in review why a recurring
# schedule needs to leak agent transcripts publicly.
#
# Linked rule: AGENTS.md `wg-after-merging-a-pr-that-adds-or-modifies` workflow
# pre-merge gate, plus the schedule SKILL.md `--once` vs Step 3a comment blocks.

set -uo pipefail

EXIT=0

# Caller may pass a list of files (lefthook `{staged_files}`); default to
# scanning all scheduled-*.yml workflows.
if [[ $# -gt 0 ]]; then
  FILES=("$@")
else
  mapfile -t FILES < <(find .github/workflows -maxdepth 1 -name 'scheduled-*.yml' 2>/dev/null)
fi

for f in "${FILES[@]}"; do
  [[ -f "$f" ]] || continue
  case "$f" in
    .github/workflows/scheduled-*.yml) ;;
    *) continue ;;
  esac

  if grep -qE '^\s*#\s*allow-show-full-output:' "$f"; then
    continue
  fi

  if ! grep -q 'show_full_output:' "$f"; then
    continue
  fi

  if ! grep -qE '^\s*show_full_output:\s*true' "$f"; then
    continue
  fi

  if grep -qE '^name:\s*"Scheduled \(once\):' "$f"; then
    continue
  fi

  echo "::error file=$f::show_full_output: true is forbidden in recurring scheduled workflows (only \"Scheduled (once):\" workflows may set it). Add a '# allow-show-full-output: <reason>' comment to waive (rare — must justify why a recurring agent transcript may leak to public logs)."
  EXIT=1
done

exit $EXIT
