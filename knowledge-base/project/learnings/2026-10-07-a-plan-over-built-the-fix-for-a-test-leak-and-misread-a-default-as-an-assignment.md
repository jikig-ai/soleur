# Learning: plan misread a `${TMPDIR:-default}` as an assignment and over-built the fix (#9677)

## Problem

The #9677 plan said `test-git-data-boot-signal-poll.sh` "sets `TMPDIR=/var/tmp`" and prescribed sourcing the scratch-root allocator, splicing a cleanup into the EXIT trap and a four-writer marker sweep. The line is `export TMPDIR="${TMPDIR:-/var/tmp}"`: a default, and the library's `mktemp -d -t gdboot.*` already honours `TMPDIR`. Two reviewers (DHH, code-simplicity) found that `export TMPDIR="$SANDBOX"` after the existing trap fixes the leak in one line. The same plan also claimed macOS portability while prescribing `du -sb`, `df` on `/` (not the base the drain frees), an unguarded `timeout`, and a drain placed after the flock fd was closed. Architecture review found the unguarded new calls would abort cleanup-merged under `set -e`.

## Solution

Applied the one-line fix, `du -sk`, the repo's `timeout`/`gtimeout` fallback, `df` on the scratch base, drain inside the lock window, and guarded every new call; moved Docker and the space report to a wrapper that runs after the lock is released.

## Key Insight

A plan that prescribes a change to a script it only skimmed re-derives the *mechanism* from a one-line grep. Read the line as code (default vs assignment) and ask "what is the smallest edit that changes where the leak lands?" before choosing a framework. Reviewers who verified the lines in the repo caught what plan text could not.

## Session Errors

- **Plan claimed a test "sets TMPDIR=/var/tmp"; it defaults it** — Recovery: replaced with a one-line `export TMPDIR="$SANDBOX"` — Prevention: covered by the plan Sharp Edge on paraphrase-without-verification; no new rule.
- **Plan asserted portability but prescribed GNU-only `du -sb` and bare `timeout`** — Recovery: `du -sk` and the existing `gtimeout` fallback — Prevention: covered by the first plan Sharp Edge (portable commands); the miss was not running its checklist against the plan's own commands.
- **Plan placed the drain after the sweep's flock fd closed, and left new calls unguarded under `set -euo pipefail`** — Recovery: drain inside the lock window, guarded calls — Prevention: covered by reading the surrounding comments in `cleanup_merged_worktrees`; no new rule.
- **A classifier call in the brainstorm timed out at 100 s without a map** — one-off measurement, recorded in the plan.

## Tags

category: workflow-patterns
module: plan
