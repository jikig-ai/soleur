---
title: Merge-queue ejections were two e2e causes (not one flake), and the fix PR's own guard shipped survivors in both review rounds
date: 2026-10-05
category: engineering
tags: [merge-queue, e2e, playwright, next-font, guard-tests, mutation-testing, review]
symptoms: [merge queue "feels slow", e2e red on merge_group runs, 64 authenticated tests red in 14 minutes, entries behind an ejection rebuild]
module: CI e2e harness, merge queue
synced_to: []
component: process
problem_type: workflow_issue
resolution_type: process-correction
root_cause: a build-time font loader failure on the first compile of the authenticated dev server, read as "ready" by a TCP-only webServer check, cascaded into every test; a second, unrelated strict-mode collision was filed with it as one flake
---

# Learning: queue ejections decomposed into two causes; fix the readiness contract, not the retry

## Problem

The operator reported the merge queue "feels slow". Measurement showed healthy PRs merge in 15 to 18 minutes and the long waits were ejections: a failed `merge_group` run removes its entry and every entry behind it rebuilds. The handoff counted "5 of 25 runs failed (20%)"; re-derived it is 4 ejections of 27 runs (15%), because one red run was an advisory job (`lint-bot-statuses`) that reddens the run without ejecting.

## Solution

Per-run log reads split the three e2e ejections into two causes, not one flake:

1. `next/font/google` failed to resolve its loader on the first compile of `app/layout.tsx`. Playwright's `port:` webServer readiness is a TCP check, so a server answering 5xx counted as ready and 64 tests failed one by one (13.3 min instead of about 3). Fix: vendor the Inter woff2 and load it with `next/font/local`; poll `/login` with `url:` readiness so a broken compile fails at server start; a guard test keeps the network loader out.
2. A `role=status` locator collided with the nav-pending island (strict-mode violation, #9170): select the banner by text.

Contention was measured at job level (60 concurrent jobs = the plan limit, 22% of demand from `merge_group`), which showed `max_entries_to_build=2` is not the lever and the duplicate push-to-main run (#9512) is 3% of demand, so no ruleset change.

## Key Insight

- Decompose an aggregate failure rate by run and by failing step before choosing a fix; the handoff's count, its "one flake" framing and its causes were all inputs, not findings.
- A readiness check that does not exercise the compile path certifies nothing about it. `url:` on a route that renders the root layout moves the failure to where it is cheap and attributable.
- Playwright starts `webServer` entries serially, each with its own deadline, so the worst case for two broken servers is 2 x timeout.
- Auto-merge stays armed after a `failed_checks` removal and GitHub re-queues the PR 2 to 3.5 minutes later; a push removes it again (`reason=manual`). This was ADR-270 canary 3 ("unmeasured").
- The fix PR was a guard-writing PR, and it shipped survivors in BOTH review rounds: round 1 (5 test-design P2s: a regex alternative, extensions, enumerator flags, an unpinned readiness key, a size-only asset check) and round 2 (directory list, comment-masked `src`, timeout counted across the block instead of per entry, hash unenforced). Each was found by mutating a sandbox copy, not by reading. The axes that kept surviving: per-member rows for every alternative/extension/directory, per-entry (not per-block) assertions, and fixtures where the weak and strong predicate disagree.

## Session Errors

1. **Playwright 1.58.2's pinned browser build (1208) was not installed and two `playwright install` runs died (stale `__dirlock`, killed during extraction).** Recovery: symlinked the installed 1247 headless shell into the 1208 slot (local cache only). Prevention: one-off, host-specific; QA Step 2.6 already prescribes the override install and the INFRA-BLOCKED path.
2. **A comment in `fonts.ts` containing `next/font/google` tripped the new guard that forbids it.** Recovery: reworded. Prevention: documented class (a guard's own explanatory prose); resolved in this PR by deriving the sweep from raw text deliberately and saying so in the header.
3. **`playwright-dev-server-distdir.test.ts` counted webServer entries by `port:`; switching to `url:` broke it, found only by the scoped gate.** Recovery: count `port|url`, cross-check against `command:`, pin readiness per entry. Prevention: the work skill already says to `git grep` suites asserting a changed literal; I skipped it for `playwright.config.ts`. Grep consumers of every config literal before editing it.
4. **An `eslint-disable-next-line no-console` for a rule that is not enabled raised `unused-disable-directive` 31 to 32 and tripped the eslint ratchet.** Recovery: removed it (and the `console.log`). Prevention: do not add a disable directive for a rule the config does not enable; run `test/eslint-config.test.ts` for any new test file.
5. **`tsc` rejected `env: Record<string,string>` (Next requires `NODE_ENV` on `ProcessEnv`) after vitest had passed.** Recovery: re-state `NODE_ENV` as `roster-entry-gate.test.ts` does. Prevention: existing rule (standalone `tsc --noEmit`); vitest does not type-check.
6. **Importing the plugin's `git-clean-env` helper made the new guard repo-escaping, so `repo-wide-containment` failed.** Recovery: declared it in `REPO_WIDE_SUITES`. Prevention: the containment guard names the fix; an import from outside `apps/web-platform` is an escape.
7. **Review-seat claims that were wrong and had to be falsified before acting**: "old build shipped more font subsets" (the old config was `subsets: ["latin"]`) and "Playwright pipes no stderr" (my broken-layout run printed the compile error). Prevention: existing rule (a finding is a hypothesis; verify before applying).
8. **The scoped affected gate (`TEST_GROUP=affected`) ran 1h40m under contention and its nested `test-all-orphan-log-retention` suite fails 8 of 28 when `TEST_GROUP` leaks into its nested runs (30/0 isolated).** Recovery: stopped my own gate, verified isolated. Prevention: tracked on #8621 (selector convergence); do not use `TEST_GROUP=affected` as a merge gate.
9. **Two blocked commands**: `pgrep -f` (self-matching) and a chained `sleep` (use a Monitor until-loop). Prevention: hooks worked as intended; use `proc.sh` and Monitor.
10. **A one-off Bash hook feedback twice flagged closing prose naming an un-taken action.** Recovery: acted or declared the blocking condition. Prevention: end a waiting turn with the blocked state, not a promise.

## Tags
category: workflow-issues
module: ci-e2e-merge-queue
