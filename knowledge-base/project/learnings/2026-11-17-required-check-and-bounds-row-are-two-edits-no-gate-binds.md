---
title: A required check and its bounds row are two edits no pre-merge gate binds
date: 2026-11-17
category: workflow-issues
module: scripts/required-check-wallclock-bounds.tsv, scripts/watch-wallclock-p90-11774.sh
tags: [wallclock-p90, required-checks, bounds-tsv, unbound, ratchet, seeding-method]
pr: 12877
issues: [11556, 12329, 12885]
---

# Learning: a required check and its bounds row are two edits no pre-merge gate binds

## Problem

Epic #11556's weekly wall-clock watch
(`scripts/watch-wallclock-p90-11774.sh`) flagged `oracle-review-required`
as `unbound` on every scheduled run after #12329 made the check required
on 2026-11-08 — that PR added the context to `required-checks.txt` but not
a row to `scripts/required-check-wallclock-bounds.tsv`, and no pre-merge
gate binds the two edits. A required context with no bound row is itself a
ratchet finding, so the gap was loud-by-design; the watch is the intended
≤7-day backstop, not a defect. PR #12877 closed the gap.

## Solution

Seeded the missing row per the TSV header's own SEEDING METHOD — bound =
the measured p90 latency of the last ~30 completed+conclusion=success
`ci.yml` runs per surface, rounded UP to the next minute, margin 0.30:

- Probe dry-run 2026-11-17 measured PR p90 **139 s** (n=30) and
  merge_group p90 **100 s** (n=29), so the committed row is
  `oracle-review-required	180	120	0.30` (tab-separated, four columns,
  placed between `vendor-pin-required` and `cla-check` to mirror
  `required-checks.txt` ordering).
- Added a dated `# ROW SEED` header note recording the check, the PR that
  made it required, and the measured values behind the seed.
- Recorded the measurement as a `## Measured history` bullet in
  `knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md`.
- Re-ran `watch-wallclock-p90-11774.sh --dry-run`: exit 0, zero findings,
  13↔13 parity between `required-checks.txt` and the bounds table.
- The residual parity-test gap (no automated test binds the two files
  pre-merge) is tracked in #12885 rather than silently absorbed.

## Key Insight

Making a check required and adding its wall-clock bound row are two file
edits that no pre-merge gate binds — the weekly watch is the designed
backstop, so an `unbound` flag is the system working, but it still needs a
human to close the loop. When a change makes a context required, seed the
bounds row in the same change using the file's own SEEDING METHOD
(measured p90 → next-minute ceiling, margin 0.30), never the epic target —
seeding at target fires immediately on real latencies.

## Session Errors

1. **`gh pr view 12329 --json merged` failed — `merged` is not a field.**
   Recovery: corrected to `mergedAt`; PR confirmed MERGED 2026-11-08.
   **Prevention:** check the `gh pr view --json` field list before
   inventing field names. (one-off)
2. **markdownlint MD038 fired on a code span in AC-4 of the plan.**
   Recovery: fixed the spacing at write time; all artifacts lint clean.
   **Prevention:** lint markdown artifacts before committing them.
   (one-off)
3. **`technical-ruling-gate.sh --branch` exited 1 on `unruled-technical`
   rows** — expected gate semantics, not a failure. Recovery: resolved via
   the parent pipeline's batched CTO spawn, which ruled all three rows
   (defaults affirmed). **Prevention:** plan phases should emit rulings
   eagerly, not `pending - assumed` placeholders. (one-off)
4. **Subagent harness lacks Task/fan-out capability.** Recovery:
   deepen-plan fan-outs ran as inline verification passes, disclosed in
   the plan. **Prevention:** same substitution — run the passes inline and
   disclose the substitution in the artifacts. (recurring-process)
5. **Edit-tool `old_string` failed to match tab-encoded TSV text.**
   Recovery: used `awk` for byte-exact row insertion instead.
   **Prevention:** for tab-delimited files prefer awk/sed over
   exact-match edits. (recurring-process)
6. **Two background dry-run probe shells exceeded their output waits.**
   Recovery: treated them as incomplete, not success; re-ran with output
   captured to a file and read the file. **Prevention:** redirect long
   probe output to a file and poll the file, never the shell.
   (recurring-process)
7. **`markdownlint` not on PATH in the worktree** (worktrees lack
   `node_modules`). Recovery: invoked the canonical binary at
   `<repo-root>/node_modules/.bin/markdownlint`. **Prevention:** resolve
   the repo-root `node_modules/.bin` path, or install into the worktree.
   (recurring-process)
8. **`emit-review-trailer.sh --risk-tier` rejected `non-code`** — the
   enum is `none|single-user incident|aggregate pattern`. Recovery:
   re-emitted with a valid enum value. **Prevention:** read the script's
   usage/enum before guessing values. (one-off)
9. **`gh issue create` refused twice** — the hook requires `--milestone`
   and one filing exit (the `meta/machinery` label, a
   `User-Impact:`/`Fix-Size:` pair, or a `Mandated-By:` line). Recovery:
   re-filed with `--milestone` and a filing exit (#12885).
   **Prevention:** already hook-enforced — include milestone plus a filing
   exit on every issue create. (recurring-process)

## Tags

category: workflow-issues
module: scripts/required-check-wallclock-bounds.tsv
