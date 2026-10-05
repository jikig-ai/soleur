---
title: Each new consumer of a shared format re-derived it, and the copies diverged toward silence
date: 2026-10-01
category: workflow-issues
module: cron-egress-firewall
tags: [egress, ghcr, review, fail-open, drift-guard, alert-reference, vacuity-floor, fixture-ratchet]
issue: 9275
pr: 9385
---

# Learning: each new consumer of a shared format re-derived it, and the copies diverged toward silence

## Problem

PR #9385 carved GitHub's Packages frontends out of the container-egress allow list and added a probe,
a sampler filter, an apply-time assertion and a Sentry route. It was green on 79 + 146 + 276 assertions,
three mutation batteries and shellcheck. An 11-seat review then found one P1 and about eleven P2s, and
most reduced to one cause: **each new consumer of the `# Excluded (GitHub Packages frontends): <cidr>`
header and of the probe verdict re-derived its own parse, so the copies disagreed in the silent direction.**

- The resolver's probe verdict was three-state (held needs rc 28 AND time_connect 0); the apply-time
  assertion's copy was two-state, so a missing `curl`, a failing `docker exec` or empty output printed
  `ghcr-frontend-held-ok` without probing anything.
- The header validator existed three times (generator, resolver awk, assert) with different octet,
  leading-zero, alignment and prefix rules; a header the assert accepted the sampler ignored.
- The generator warned and wrote an uncarved file on zero effective holes, while the assert and the
  committed-file test treated that same file as fatal, and the daily direct-merge cron could have landed it.
- `... | filter || true` turned an awk runtime failure into an empty drop list, silently disabling the only
  no-SSH drop alert; a budget skip returned before the blind counter moved, so a probe that never ran was
  indistinguishable from a healthy one.
- The one merge blocker was in the plan: step 5.2 deferred `alert-reference.json` to "regenerate from the CI
  artifact", but that file is a required PR gate (`plan_pr` compares it to the Terraform projection), so
  deferring it made the PR unmergeable. It was a one-value edit that could be derived locally.

## Solution

- Review fixes landed from one SHA by four write-only agents on disjoint file sets, the lead committing.
- Every guard added during review was mutation-proven in the same change; the verdict-owning helpers got
  negative controls (drive `check()`/`ga_row` with a mismatch and assert FAIL moved), plus a call-site CASES
  count with a `PASS+FAIL==CASES` identity and exact printf+exit floors.
- Parity rows now run every consumer against the committed artifact (the resolver filter against the real
  CIDR file, the assert's header grep, the generator's own floor constant) so a spelling change in one
  consumer cannot go unseen.
- New suites that landed a floor in a deferred directory were promoted in `guard-vacuity-floor.test.sh`
  instead of raising the shrink-only ledger; new fixture write windows were guarded with the canonical
  `assert_fixture_dir` instead of regenerating the ratchet baseline (it went 5 -> 8 -> 5, never rewritten up).

## Key Insight

When a PR adds a THIRD consumer of a format or a verdict, the author tests the consumer's own logic and the
copy drifts on the axis nobody fixtured: *what does this report when its input is missing or malformed?*
Every divergence here failed toward "held" or "nothing to report". Write the shared parse once (or pin all
copies against the real committed artifact), and make "could not decide" its own counted outcome.

A plan step that defers a PR-required generated artifact to a post-push CI artifact is a merge blocker; derive
it locally before the first push.

## Session Errors

1. **Stop hook fired twice on closing text that promised an action ("I'll start #9275", "I'll commit once they
   return").** Recovery: performed the action in the same turn or ended with an explicit `<stop>BLOCKED:`.
   **Prevention:** already hook-enforced (`unkept-promise-hook.sh`); end waiting turns with a `<stop>` line.
2. **`git commit` through lefthook exceeded the 600 s foreground limit twice (bun-test/typecheck queue under
   sibling load) and was killed.** Recovery: re-ran in the background with a 30-minute timeout and read
   `COMMIT_RC` from a log. **Prevention:** commit staged `.ts` changes via `run_in_background` with a long
   timeout; never retry a second writer while one may survive.
3. **Plan subagent could not use the Playwright MCP and its first `gh issue create` was rejected by the
   issue-filing hook for a helper-function wrapper.** Recovery: top-level commands with a `Mandated-By` line.
   **Prevention:** none beyond the existing hook text.
4. **`git stash list` was blocked by the never-stash hook.** Recovery: used `git show <commit>:<path>`.
5. **Merge conflict on the single-line `PROMOTED_FILES` assignment in `guard-vacuity-floor.test.sh` when a
   sibling promoted two suites.** Recovery: took main's side and re-added the one token on all four lines.
   **Prevention:** when several PRs promote suites, expect that one line to conflict.
6. **Fix agents added fixture writes that moved the fixture-relative ratchet (5 -> 17 -> 8).** Recovery: guarded
   the windows with the canonical helper. **Prevention:** brief every test-editing agent to run
   `fixture-relative-assert.test.sh` and `fixture-dir-operand-assert.test.sh` and never regenerate upward.
7. **The first implementation shipped fail-open paths a green 276-assertion suite could not see** (above).
   **Prevention:** on a guard-shaped PR, run the structural-enumeration seat and ask per consumer what it reports
   on missing input.
8. **#9334 was auto-closed by `apply-deploy-pipeline-fix.yml` with "Server state was re-aligned with HEAD"
   while the `hcloud_server` replacements were still pending (re-filed as #9382).** Not fixed here:
   the follow-up that scopes the auto-close step awaits the operator's yes.
