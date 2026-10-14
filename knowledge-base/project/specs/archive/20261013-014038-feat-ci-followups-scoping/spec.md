---
title: Bun version probe for FPE-class re-evaluation (#3692)
date: 2026-05-12
status: draft
related_issues: [3692]
deferred_issues: [3693, 3694]
related_pr: 3709
parent_pr: 3672
lane: single-domain
brand_survival_threshold: none
---

# Bun version probe for FPE-class re-evaluation (#3692)

## Problem Statement

Three open follow-ups from PR #3672 (merged 2026-05-12) have differing ship-readiness gates:

- **#3692** — Bun FPE-class re-evaluation probe. No gate; informational. `.bun-version` currently 1.3.11 (6 patches past the FPE-1.3.5 baseline). Latest published 1.3.x: **1.3.14**.
- **#3693** — Suite-internal split of `apps/web-platform/test/`. Parent plan deferred to a conditional trigger (`test-webplat` shard >100s sustained); zero post-#3672 data exists. Plan-time discovery: 355 top-level files; would be a 200+ file refactor. **Excluded from this PR.**
- **#3694** — `e2e` job synthetic-aggregator shard. Hard gate: ≥1 week post-#3672 stability. **Cannot be met today. Excluded from this PR.**

Per AGENTS.md `wg-after-merging-a-pr-that-adds-or-modifies` and the parent plan's `Rule of thumb: When a Bun test runner crash correlates with RSS or subprocess count, suspect a GC bug and check if a newer Bun version fixes it before adding workarounds.`, this probe is the cheapest way to test whether the FPE class is still live on the latest patch.

## Goals

1. Bump `.bun-version` from `1.3.11` to `1.3.14` (latest published 1.3.x at plan time).
2. Push the bump on `feat-ci-followups-scoping`; observe a full CI run.
3. **If the bun-test surfaces (`test-bun` shard: `bun test test/{content-publisher,x-community,pre-merge-rebase}.test.ts` + `bun test plugins/soleur/` + `bash scripts/validate-blog-links.sh`) green:** keep the bump, record the finding in learnings.
4. **If any bun-test surface re-triggers FPE-class (SIGFPE crash, segfault, abnormal exit with crash artifacts):** revert `.bun-version` to `1.3.11` in the same commit and record the failing patch in learnings so the next minor-version probe has prior art.
5. Honor the deferrals of #3693 (re-evaluate on parent plan's conditional trigger) and #3694 (re-evaluate ≥2026-05-19).

## Non-Goals

- **NOT** shipping #3693 (webplat sub-directory split) in this PR. Re-open under parent plan's conditional trigger.
- **NOT** shipping #3694 (`e2e --shard=2`). Hard 1-week gate unmet.
- **NOT** introducing `bun test --max-pool-size` or any in-process parallelism — that is a downstream re-evaluation only unlocked if this probe shows the FPE-class is gone.
- **NOT** modifying `scripts/test-all.sh`'s sequential test-runner logic. The sequential isolation remains as defense-in-depth even if the version bump is clean.
- **NOT** editing `scripts/test-all.sh` or `.github/workflows/ci.yml`. The 5 workflows already using `bun-version-file: ".bun-version"` pick up the bump automatically. (Review-time addendum: this PR also pins `skill-security-scan-corpus.yml` and `skill-security-scan-pr-trailer.yml` from `bun-version: latest` to the file pin per review F1 — these 2 workflows had been silently floating to whatever Bun publishes as `latest`.)
- **NOT** modifying `apps/web-platform`, `apps/telegram-bridge` (does not exist), `plugins/soleur/`, or any other code outside `.bun-version` itself + the learnings update.

## Functional Requirements

- **FR1** — Single commit. Bumps `.bun-version` 1.3.11 → 1.3.14.
- **FR2** — CI runs the existing `test-bun` shard against 1.3.14 with no workflow edits required.
- **FR3** — On green: keep the bump and append a `## 2026-05-13 probe: 1.3.14 clean` block to `knowledge-base/project/learnings/2026-03-20-bun-fpe-spawn-count-sensitivity.md` documenting the outcome, runner OS, and which surfaces passed.
- **FR4** — On FPE-class regression: revert `.bun-version` to 1.3.11 (amend the single commit), and append a `## 2026-05-13 probe: 1.3.14 FPE` block to the same learnings file with the failing surface, crash signature, and revert decision. The PR still merges (the learning capture is the deliverable).
- **FR5** — Cross-link this PR back to issue #3692 via `Closes #3692` in body.
- **FR6** — #3693 and #3694 remain open with comments noting their re-evaluation triggers.

## Technical Requirements

- **TR1** — `.bun-version` MUST contain exactly `1.3.14\n` (trailing newline) on green. Reverted to `1.3.11\n` on failure. The file is consumed by `scripts/test-all.sh`'s version-check guard (`expected=$(tr -d '[:space:]' < .bun-version)`) — whitespace handling is already robust.
- **TR2** — Of the 7 workflow files in `.github/workflows/` that touch Bun, 5 already used `bun-version-file: ".bun-version"` pre-PR (`ci.yml`, `main-health-monitor.yml`, `scheduled-bug-fixer.yml`, `scheduled-ship-merge.yml`, `scheduled-ux-audit.yml`). The remaining 2 (`skill-security-scan-corpus.yml`, `skill-security-scan-pr-trailer.yml`) pinned `bun-version: latest`; this PR aligns them to the file pin per review F1.
- **TR3** — No edits to `scripts/test-all.sh`. The sequential test-runner logic remains as defense-in-depth.
- **TR4** — Learnings update preserves the existing taxonomy and adds a single dated section. Do not rewrite the original analysis.
- **TR5** — FPE-class detection criteria: any of (a) job exit non-zero with `Floating point error` in logs, (b) job exit non-zero with `panic:` from Bun, (c) any of the named bun-test surfaces fails with no Vitest/test-assertion explanation (i.e., crash-class, not test-class). Test-level failures unrelated to the runner do NOT trigger the revert protocol — they are a separate bug surface.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] Single commit on `feat-ci-followups-scoping` touching only `.bun-version` and (post-CI outcome) the learnings file.
- [ ] CI green on PR #3709 OR (on FPE outcome) CI green with `.bun-version` reverted to 1.3.11 + learning file updated.
- [ ] Learning file `knowledge-base/project/learnings/2026-03-20-bun-fpe-spawn-count-sensitivity.md` updated with the probe outcome.
- [ ] PR body contains `Closes #3692`.
- [ ] #3693 carries a comment: "Plan-time discovery: 355 top-level files in `apps/web-platform/test/`; deferred to parent plan's conditional trigger (`test-webplat` shard >100s sustained)."
- [ ] #3694 carries a comment: "Earliest re-evaluation: 2026-05-19 (≥1 week post-#3672)."

### Post-merge

- [ ] If green outcome: parent plan's N1 ("`.bun-version` stays at 1.3.11") is now superseded — update parent plan's deferred-items section with a back-reference to this probe.
- [ ] If FPE outcome: open a follow-up issue tracking the next probe (target version, re-evaluation date) — `gh issue create` with `domain/engineering`, `type/chore`, `priority/p3-low`.

## Deferred Work

- **#3693 (webplat split)** — Re-evaluate when `test-webplat` shard wall-clock data exists. Parent plan's `TEST_TIMING_LOG` mechanism captures per-suite timing; cron or a manual gh-actions log scrape can detect the >100s-sustained threshold.
- **#3694 (e2e shard)** — Re-evaluate ≥2026-05-19 once #3672 has ≥1 week of post-merge stability.
- **Bun `--max-pool-size`** — Only re-evaluate if this probe shows FPE-class no longer fires.
