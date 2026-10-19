# Learning: a sibling session merged half of my batch PR while a 30-minute verification ran

## Problem

PR #10320 was a deliberate batch (#10119 htpasswd/heartbeat template conversion, #8408 close-out, #7530 clientIP
alert) built over about 20 hours of pipeline time (plan, 13-seat review panel, two fix rounds). The plan's
Hand-over already recorded a competing PR (#10322) carrying the same #10119 template change and marked it "owner
decision needed". The owner's other session then merged #10322 (2026-10-15T09:36Z) and its unattended registry host
replace ran and passed (dispatcher run 38714214071). I only learned this when the final `git fetch` ran after a
~78 minute verification of the pre-merge tree: 16 commits of #10119 work (template, five suites, ADR text, a second
probe with the same file name) were now duplicates that conflicted with main in eleven files.

## Solution

- Backed the branch up to a local ref, reset to `origin/main`, restored only the #7530-owned files from the backup,
  and re-applied the shared-file hunks (registration tables, baselines, Art. 30 register, workflow registration) by
  hand, 7530 lines only. No `cloud-init-registry.yml` change survives, so merging no longer fires a registry replace.
- Re-ran the registered suites and every repo-wide ratchet on the new tree; the one new red was the
  `test-affected-kb-consumers` baseline (+2 text-pointer rows for the 7530 probe), regenerated with the sanctioned
  `--write-baseline` and the diff checked to be exactly those two rows.
- Added a dated Re-scope addendum at the top of the plan (never edited the old body), a tasks.md note and a
  decision-challenges row.

## Key Insight

A one-time "is anything else touching these files" check at plan time is not a property of the branch, it is a
snapshot. In a repo where a second session has the same account and the same epic, the question has to be re-asked at
every long phase boundary (before the review panel, before a multi-hour verification, before the final push), and the
cheapest form is `git fetch origin main && git log --oneline HEAD..origin/main -- <the branch's own infra paths>` plus
`gh pr list --state merged --search <issue numbers>`. The earlier merge-tree probe at review start only proves the
branch rebases, not that its purpose is still unfulfilled. A retry-able 30 minutes became 78 minutes and a rebuild
because the collision surfaced after the verification, not before it.

## Session Errors

1. **Competing PR resolved while I verified, found only at the end.** Recovery: re-scope onto main (above).
   **Prevention:** run the fetch-and-path-log check at each phase boundary of a long pipeline, not only at review
   start (instance: this branch's verification script now begins with it implicitly via the rebase).
2. **Lease push rejected ("stale info") because I typed a placeholder sha.** Recovery: re-ran with the real remote
   tip read from `git rev-parse origin/<branch>`. **Prevention:** build the lease argument from the command output,
   never type it.
3. **`gh issue create` refused four times by the filing hook** (milestone, a body-file the gate could not read, then
   the user-visible-consequence exit). The first two refusals also swallowed the heredoc that was meant to write the
   body in the same command, so the file did not exist. **Prevention:** write the body with the Write tool as its own
   step, pass a literal absolute path, include `--milestone`, and for a finding about a guard use `--label
   meta/machinery`.
4. **A foreground `sleep` was blocked** (hook). **Prevention:** Monitor with an until-loop on the log's `DONE` line.
5. **Subagent verifier reported five P3s after the last targeted round.** Handled by fixing three trivially and
   filing the other two as #10374 (not a new fix round).

## Tags

category: workflow-issues
module: one-shot pipeline, registry batch PR #10320
