---
title: "infra: adopt GitHub merge queue on main via advisory-CodeQL path (merge-train tax)"
date: 2026-10-03
slug: adopt-merge-queue-advisory-codeql
branch: feat-one-shot-9454-merge-queue-advisory-codeql
issue: 9454
closes: [9454, 4856]
type: feat
priority: p2
domain: engineering
lane: cross-domain
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: false
---

# infra: adopt GitHub merge queue on main via advisory-CodeQL path

Spec lacks a valid `lane:` (no `spec.md` exists for this branch) — defaulted to `cross-domain` (fail-closed).

## Enhancement Summary

**Deepened on:** 2026-10-03
**Agents used:** best-practices-researcher (GitHub docs), architecture-strategist, security-sentinel, spec-flow-analyzer, observability-coverage-reviewer, terraform-architect (offline provider-schema probe), plus the plan-review panel (DHH, Kieran, code-simplicity), CTO and CLO assessments and the plan Sharp Edges pass.

### Key Improvements

1. Premise correction: ADR-032 2026-07-01 had already evaluated and rejected "queue with advisory CodeQL" as a bad trade, and the 2026-09-14 amendment re-rejected the queue on capacity grounds (three runs per merged PR, 28-minute max runner start spread). The plan now treats this as an operator override (trigger (b)) and re-derives `check_response_timeout_minutes` to 60 and the stall probe to 45 minutes on a `*/10` cron.
2. The alert gate no longer uses a `created_at` watermark (it misses queued-PR alerts first seen on the PR ref). "New" means "no bot-authored open tracking issue"; added poisoning-resistant dedupe, data-minimised issue content, a `codeql-gate-degraded` issue so a red run on a queue-made push reaches someone, and input validation.
3. CLA synthetic hardened: strict `head_ref` shape, base_ref check, latest run per name, and logic run from a default-branch checkout.
4. Terraform specifics confirmed against provider 6.12.1: all seven `merge_queue` attributes optional with provider defaults 60/5/5/1/5; DR script must send all seven REST parameters; admin bypass canary made mandatory and run FIRST after the apply; the emergency rollback is a PUT of a queue-less payload to the existing ruleset id (no script knob).
5. Bot-PR and armed-PR flows: queue enqueue by `GITHUB_TOKEN`, gates that were fabricated green now running for real, and PRs armed before the apply are listed and confirmed to enqueue.

### New Considerations Discovered

- GitHub documentation does not settle several behaviors this plan relies on (documentation research returned UNVERIFIED): the squash-message source for queue-built commits, whether a `pull_request`-mode bypass actor can merge past the queue, the `mergeStateStatus` value for a behind-but-queued PR under a strict ruleset, and what happens when the timeout is exceeded. Each is recorded as a canary measurement with a defined fallback, not as an assumption.
- Documentation CONFIRMED the GraphQL `MergeQueueConfiguration` fields (checkResponseTimeout, maximumEntriesToBuild/Merge, minimumEntriesToMerge, mergeMethod, mergingStrategy ALLGREEN|HEADGREEN) and the `isInMergeQueue` / `mergeQueueEntry` fields on `PullRequest`.

## Overview

Direct merge under `strict_required_status_checks_policy` makes every main advance force a
`gh pr update-branch` plus a full CI cycle per PR (CI wall-clock on PRs: p50 17.7 min, p90 25.9 min,
max 32.8 min over the last 60 green runs). Adopt the GitHub merge queue on `main` by adding a
`merge_queue` rule to `infra/github/ruleset-ci-required.tf` and removing the `CodeQL` required check
(CodeQL cannot report a status on `merge_group`, upstream `github/codeql-action#1537`, still open,
last updated 2026-05-22). CodeQL stays advisory: the `pull_request` scan stays, and a new
`on: push` to `main` workflow turns the pushed commit's CodeQL result into a loud, deduplicated
signal about ten minutes after the push (measured 9 to 11 minutes).

The operator decision is taken (queue ON, CodeQL advisory, upstream watcher kept). This plan does
not re-litigate it. It does report four pieces of evidence the issue body did not have, one of which
(CLA ruleset) would have recreated the 2026-06-30 deadlock:

1. **The CLA Required ruleset is a second ruleset gating `main`** and its two contexts
   (`cla-check`, `cla-evidence`) cannot run on `merge_group`. The PR-1 workflows that covered this
   (`merge-queue-cla-synthetics.yml`, `merge-queue-stall-check.yml`) were deleted in #5842 after the
   revert. They must be restored (from `git show 4439c23c39^:<path>`) — the issue's "~2 files + 1
   workflow + 2 docs" size is understated.
2. **Removing the `CodeQL` required check trips `apply-github-infra.yml`'s destroy-guard** (a nested
   `required_check` shrink). The merge commit needs a line that is exactly `[ack-destroy]`;
   `workflow_dispatch` cannot carry it (`HEAD_MSG` is empty on dispatch), so the apply cannot be staged
   through a manual dispatch.
3. **Ship's BEHIND auto-sync is queue-unaware** (`plugins/soleur/scripts/sync-pr-behind.sh`,
   `plugins/soleur/lib/pr-merge-poll.ts`, merge-pr §5.2, ship Phase 7). Pushing an `update-branch`
   merge to a queued PR dequeues it.
4. **"Advisory" removes more than interaction-only coverage.** Today the required `CodeQL` check blocks
   a PR whose own head carries a new critical/high alert; after this change nothing blocks it. The post-merge
   gate catches it about ten minutes after the push (measured), not before merge. Persisted as a User-Challenge in
   `knowledge-base/project/specs/feat-one-shot-9454-merge-queue-advisory-codeql/decision-challenges.md`
   (operator direction stays the default).

## Research Reconciliation — Spec vs. Codebase

| Claim (issue / brief) | Reality (verified) | Plan response |
|---|---|---|
| "`merge_group:` trigger arms already sit dormant in the workflows — verify coverage for every required check" | Verified for all 23 `integration_id 15368` contexts in the CI Required canonical JSON: 8 workflow files declare `merge_group`; no required job carries an `if:` that excludes it (`allowlist-diff`, `rename-guard`, `waiver-discipline` use `pull_request \|\| merge_group`; `test`, `tenant-integration-required`, `sentry-destroy-required`, `vendor-pin-required` use `always()`). **Falsified for the CLA Required ruleset**: `cla-check`/`cla-evidence` run only on `pull_request_target`/`issue_comment`. | Restore `merge-queue-cla-synthetics.yml` (hardened to fail closed against the PR head's real contexts, per CLO) and add a mechanical coverage guard that spans BOTH rulesets (Guard 1). |
| "New workflow + 2 doc touch-ups, ~2 files Terraform" | The CodeQL requirement is also encoded in the canonical JSON, the DR restore script, `required-checks.txt` prose, five audit tests, the live-ruleset audit, `admin-merge-ready` fixtures, legal register PA12; queue-awareness is needed in ship/merge-pr/sync-pr-behind. | Files to Edit below enumerates the real lockstep set. |
| "Fail loudly + file an issue on NEW critical/high alerts" | `codeql-to-issues.yml` (daily) already files `sec: CodeQL alert #N` issues for ALL open critical/high, deduped on open issues, and swallows API errors (`... \|\| true` → "No open alerts"). It has no notion of "new" and no red run signal. | New gate keeps the same title/label convention (shared dedupe, no double filing) and defines "new" as "no tracking issue yet"; it adds the push-time red run and must fail closed on API errors. |
| "wait for the pushed commit's analyses" | Analyses per main commit are 3 (`/language:actions`, `/language:python`, `/language:javascript-typescript`) while the commit carries FOUR `Analyze (*)` check-runs (`ruby` has a check-run and no analysis) and the default-setup `languages` list has 5 overlapping entries. A count of analyses or languages is not a valid wait condition. | Wait on the `Analyze (*)` check-runs (app `github-actions`) all `completed`, then read analyses/alerts. |
| "One Terraform diff reverts" | Rollback = the merge_queue block + the `CodeQL` required_check + the canonical JSON/DR skeleton/test lines. The apply's destroy-guard does not count a `merge_queue` block removal or a `required_check` addition. | Rollback = revert of the named files; includes `[ack-destroy]` anyway (harmless). |
| "#4856 duplicate" | #4856 (open, p3) proposes `merge_queue` in the same ruleset via IaC, keeping strict policy, ADR-032/docs update — same scope, no CodeQL analysis. | Verified same scope; carry `Closes #4856`. |

## Research Insights

### Premise Validation (Phase 0.6)

- #9454 OPEN (no closing PR). #4856 OPEN, same scope. #5840 OPEN (stays open as the upstream tracker, label `merge-queue-revisit`).
- Upstream `github/codeql-action#1537`: `state=open`, `state_reason=null`, `updated_at=2026-05-22T00:55:36Z` (probed 2026-10-03).
- Cited paths exist on this branch: `infra/github/ruleset-ci-required.tf`, `plugins/soleur/skills/drain-prs/SKILL.md` §4 (the "No merge queue on `main`" bullet and the "If the queue is re-adopted" bullet), `.github/workflows/scheduled-terraform-drift.yml` (the `infra/github` comment), `codeql-1537-revisit-watch.yml`, the PIR.
- ADR corpus (read in full, deepen pass): ADR-032's 2026-07-01 amendment DID evaluate this exact mechanism and rejected it as a trade ("Merge queue ⇒ CodeQL must be dropped from the ruleset's required checks (advisory only) … Rejected: trading a blocking SAST gate for marginally smoother merges over the working auto-sync loop is a bad trade"), while naming re-adoption trigger (b) "a deliberate decision to make CodeQL advisory". The 2026-09-14 amendment (#8149; mirrored in ADR-216's 2026-09-14 addendum) re-rejected the queue on a CAPACITY factor (Free plan, 20 concurrent hosted jobs; a queue costs three full runs per merged PR; measured 28-minute max start spread on a drained group, so `check_response_timeout_minutes` must be re-derived above it) and added trigger (iii); the 2026-09-22 amendment records (iii) satisfied (plan change Free 20 → Team 60) with the qualification that 60 is an entitlement, not a guarantee. So this plan is the operator exercising trigger (b) against a recorded rejection: it supersedes those rulings through ADR-269, and must carry the capacity factor and the timeout re-derivation rather than assume them away.
- Empirical facts (commands, 2026-10-03): `gh api repos/jikig-ai/soleur/rulesets` → four rulesets on default branch: CI Required (14145388), CLA Required (13304872), Force Push Prevention, a disabled Copilot one. `gh api .../code-scanning/default-setup` → `configured`, languages `[actions, javascript, javascript-typescript, python, typescript]`. `gh api ".../code-scanning/alerts?state=open&ref=refs/heads/main"` → 3 open alerts, all `medium` (0 critical/high → the standing critical/high backlog is empty). `gh api ".../code-scanning/analyses?ref=refs/heads/main"` → 3 analyses per commit, ~3 min after push. `gh api graphql … isInMergeQueue mergeQueueEntry{state position}` → both fields exist; `gh pr view --json` (gh 2.102.0) has neither.
- `curl -sf https://api.github.com/repos/jikig-ai/soleur/rules/branches/main` works unauthenticated (public repo) → currently `deletion non_fast_forward required_status_checks` (no `merge_queue`).

### Property List (Phase 0.6b)

- P1 — A PR's wait on main churn stops costing an `update-branch` + full-CI cycle per main advance (speculative queue).
- P2 — Every context required by any ruleset on `main` can report on a queue candidate (no deadlock redux).
- P3 — A new critical/high CodeQL alert on `main` is surfaced loudly about ten minutes after the push (measured 9 to 11 minutes), without standing-backlog noise.
- P4 — Rollback to direct merge is one Terraform diff and does not depend on the queue draining.
- P5 — Tooling that assumed direct merge stays correct under the queue (no dequeue-by-sync, no stale docs).
- P6 — A stalled queue entry is detected without eyeballing.

### Cut List (Phase 0.6b)

| Mechanism | Property it would buy | Disposition |
|---|---|---|
| Advanced setup + `merge_group` shim | P2 for CodeQL | Cut by operator decision (fragility; re-owns the #5800 bug class). |
| Bot pseudo-queue | P1 | Cut by operator decision (serial, no speculation, merge-driving orchestrator). |
| Drop strict policy | P1 | Cut by operator decision (semantic conflicts land with no integrated-state CI). |
| New issue-body/dedupe format for the gate | P3 | Cut — reuse `codeql-to-issues.yml`'s `sec: CodeQL alert #N — <rule>` title + `type/security` label so the daily cron and `close-orphans` keep working and never double-file. |
| Persisted "seen alerts" store (cache/artifact/branch) and a `created_at` watermark | P3 backlog-diff | Cut — the issue tracker already is the state (`sec: CodeQL alert #N` dedupe); a watermark misses queued-PR alerts first seen on the PR ref. |
| Auto-revert / merge-driving reaction to a bad alert | P3 | Cut — post-merge, page-and-continue; a revert bot is its own incident class. |
| Refactor `codeql-to-issues.yml` to share code with the gate | P3 | Cut — coexist via the shared title convention; the daily cron stays the backstop for reopened alerts. |
| Terraform flag to stage the queue separately from the CodeQL removal | P4 | Cut — one resource update is atomic; `workflow_dispatch` cannot ack the destroy-guard anyway. |
| Merge-queue stall probe | P6 | **Kept** — nothing else detects a pending entry (the queue's own `check_response_timeout_minutes` ejects silently). |

### Value measurement (Phase 0.6c)

The saving claimed is wall-clock merge latency. Measured baseline (command:
`gh run list --workflow ci.yml --event pull_request --status success --limit 60 --json startedAt,updatedAt`):
n=60, p50 17.7 min, p90 25.9 min, max 32.8 min; sibling required workflows are shorter
(`pr-quality-guards` p90 5.0, `secret-scan` p90 5.0, `tenant-integration` p90 2.9). After the queue,
the per-PR cost is one CI cycle on the queue candidate with no manual sync; throughput is bounded by
`max_entries_to_build` parallel candidate builds. Post-merge measurement (queue enqueue-to-merge
latency vs. the current update-branch loop) is a canary AC, not a plan-time number.

### Institutional learnings applied

- `2026-06-30-github-merge-queue-adoption-wire-all-ruleset-producers.md` — enumerate producers at JOB level across BOTH rulesets; job-level `if: github.event_name == 'pull_request'` skips a required context on `merge_group`; `github.base_ref` is empty on `merge_group` (hard-fail, never vacuous-pass); trust-pre-queue passes must cite the GitHub entry-gate premise.
- `2026-06-30-merge-queue-iac-provider-schema-probe-and-positional-rule-readers.md` — probe the provider schema offline in a scratch dir WITHOUT a backend block; never read `.rules[0]`; select by `.type`.
- PIR `merge-queue-codeql-merge-group-deadlock-postmortem.md` — the root cause was a Phase-0 empirical hard gate treated as prose after a subagent-crash recovery. This plan makes the coverage audit a committed, executable guard and lists the empirical gates in Phase 0 as commands with expected output.
- `2026-06-02-auto-merge-livelock-fast-moving-main.md` — the failure mode the queue removes.
- `2026-04-03-github-ruleset-put-replaces-entire-payload.md` — the DR restore script PUT must carry every top-level field (`bypass_actors`, `conditions`).
- `2026-03-20-github-required-checks-skip-ci-synthetic-status.md` — bot PRs and `[skip ci]`; unchanged here, but the queue re-runs real CI on the temp ref for bot PRs too.
- CLO assessment (2026-10-03): no published legal doc claims CodeQL is a required merge check; update `knowledge-base/legal/article-30-register.md` PA12 and `compliance-posture.md` line 59; the CLA synthetic must fail closed against the PR head's real `cla-check`/`cla-evidence`.
- CTO assessment (2026-10-03): single-PR sequencing acceptable; set `min_entries_to_merge_wait_minutes = 0` (default adds 5 min to every merge); start `max_entries_to_build = 2`; queue squash message may be built from PR title+body, so carry `[ack-destroy]` in both a commit message and the PR body; canary one admin bypass.

## Hypotheses (network-outage gate, Phase 1.4)

The gate's keyword scan matched `timeout` (the merge-queue `check_response_timeout_minutes` and CI
wall-clock). There is no SSH/connectivity symptom: L3 firewall allow-list and DNS/routing hypotheses
are not applicable (the only network dependency is a GitHub-hosted runner calling `api.github.com`
with the job token). Service-layer hypotheses (sshd, fail2ban) are not in play.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Queue ON via infra/github/ruleset-ci-required.tf (add `merge_queue` rule)" [brief] | Phase 5 (`ruleset-ci-required.tf` edit), Guard 2 | mapped |
| 2 | "CodeQL/Analyze REMOVED from required checks" [brief] | Phase 5 (tf + canonical JSON + DR skeleton + audit tests lockstep) | mapped |
| 3 | "NEW on:push-to-main alert-gate workflow (wait for the pushed commit's analyses → query code-scanning/alerts?state=open → fail + file an issue on new critical/high)" [brief] | Phase 3 (`codeql-main-alert-gate.yml` + `scripts/codeql-main-alert-gate.sh`), Guard 3 | mapped |
| 4 | "Keep codeql-1537-revisit-watch.yml → re-tighten CodeQL to required if upstream resolves (one Terraform diff)" [brief] | Phase 6 (watcher header + ADR-269 re-tighten recipe; workflow itself unchanged) | mapped |
| 5 | "drain-prs/SKILL.md §4 ... flip its conditional bullet to active. Also update the scheduled-terraform-drift.yml comment." [brief] | Phase 4 (drain-prs) and Phase 6 (drift comment) | mapped |
| 6 | "#5840 stays open as the upstream-revisit tracker (do not close it)" [brief] | PR body uses `Ref #5840`; no close | mapped |
| 7 | "carry `Closes #4856` into the PR body plan notes after verifying it is the same scope" [brief] | Research Reconciliation row + PR-body note | mapped |
| 8 | "Plan must carry a ## Observability block; gating-ruleset change → elevated risk-tier review + dark-launch guidance" [brief] | `## Observability`, `## Rollout, Dark-Launch and Rollback` | mapped |
| 9 | "Revert path = single Terraform diff — document it in the plan." [brief] | `## Rollout, Dark-Launch and Rollback` | mapped |
| 10 | "1. Does every REQUIRED check's workflow already declare merge_group: (audit before enabling...)" [brief] | Research Reconciliation row 1, Phase 0, Guard 1 | mapped |
| 11 | "2. Post-merge gate semantics: block-on-new-alert vs page-and-continue; how to diff "new on this push" vs the standing alert backlog." [brief] | `### Alert-gate semantics` (decision + tracker-state rule) | mapped |
| 12 | "3. merge_queue params (min/max group size, check timeout) vs the repo's CI duration (~15 min)." [brief] | `### merge_queue parameters` | mapped |
| 13 | "terraform apply on infra/github is a shared-prod write → per-command go-ahead required" [brief] | Phase 7 (go-ahead before merge; merge is the apply trigger) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `infra/github/ruleset-ci-required.tf` edit | "Queue ON via infra/github/ruleset-ci-required.tf" | asked |
| `scripts/ci-required-ruleset-canonical-required-status-checks.json` | "CodeQL/Analyze REMOVED from required checks" | inferred — justification: the daily live-ruleset audit and `.tf`↔canonical parity test (T-rsc-9) fail if the canonical keeps CodeQL |
| `scripts/create-ci-required-ruleset.sh` | "CodeQL/Analyze REMOVED from required checks" | inferred — justification: the DR from-scratch restore would otherwise re-add CodeQL and omit the queue (ADR-032 DR clobber note) |
| `tests/scripts/test-audit-ruleset-bypass.sh` (T-rsc-2/3/5b/6/7, T-mq-1 successor) | "Queue ON ... (add `merge_queue` rule)" | inferred — justification: T-mq-1 fails CI if a `merge_queue` rule appears; it was written to be replaced by a param-parity gate "when re-adopting" |
| `.github/workflows/merge-queue-cla-synthetics.yml` (restored) | "verify coverage for every required check's workflow" | inferred — justification: the audit found the CLA ruleset's contexts have no `merge_group` producer; without it the first queue entry stalls |
| `.github/workflows/merge-queue-stall-check.yml` (restored) | "Revert path = single Terraform diff" | inferred — justification: README/ADR-032 re-adoption checklist requires the stall probe; a pending entry is otherwise invisible (hr-observability-as-plan-quality-gate) |
| `scripts/probe-merge-group-coverage.sh` (Guard 1 engine, prints `merge-group-coverage=OK`) and `plugins/soleur/test/required-checks-merge-group-coverage.test.sh` (mutation battery that runs the engine on the real repo as case 0) | "audit before enabling — a missing trigger = deadlock redux" | asked |
| `scripts/merge-queue-cla-verify.sh` + `plugins/soleur/test/merge-queue-cla-verify.test.sh` | "verify coverage for every required check's workflow" | inferred — justification: CLO design requirement that the restored CLA synthetic fail closed against the PR head's real contexts (latest run per name), which needs testable logic outside workflow YAML |
| `codeql-main-alert-gate.yml` + script + test | "NEW on:push-to-main alert-gate workflow" | asked |
| `sync-pr-behind.sh`, `pr-merge-poll.ts`, ship Phase 7 / merge-pr §5.2 text | "flip its conditional bullet to active" | inferred — justification: a queued PR that receives an `update-branch` push is dequeued; the drain-prs bullet says "do not hand-roll update/wait loops then" and ship's loop is exactly that |
| `plugins/soleur/skills/drain-prs/SKILL.md` §4 | "flip its conditional bullet to active" | asked |
| `.github/workflows/scheduled-terraform-drift.yml` comment | "Also update the scheduled-terraform-drift.yml comment" | asked |
| ADR-269 + ADR-032 amendment pointer | "Plan must carry a ## Observability block; gating-ruleset change → elevated risk-tier review" | inferred — justification: plan Phase 2.10 (wg-architecture-decision-is-a-plan-deliverable): this reverses the ADR-032 2026-07-01 decision to keep CodeQL required |
| `knowledge-base/legal/article-30-register.md` PA12, `compliance-posture.md` | "CodeQL/Analyze REMOVED from required checks" | inferred — justification: CLO assessment — PA12 says the ruleset gates merges on CodeQL (57789); a stale register row is a compliance-record defect |
| `infra/github/README.md`, `codeql-bot-coverage.md` runbook | "Queue ON" | inferred — justification: README documents the queue as inactive and says restoration steps are mandatory on re-adoption |

### Split Assessment

- Subsystems touched: 5 — `infra/github`, `.github/workflows`, `scripts` + `tests`, `plugins/soleur` (skills/scripts/lib/test), `knowledge-base`
- Planned files: ~38 (12 create, ~26 edit) | Estimated changed lines: ~1,100 (most are tests, fixtures, docs)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines — TRIPPED
- Recommendation: single PR — the pieces are mutually dependent (the queue must not be live without the CLA synthetics, the coverage guard and the gate; the canonical JSON/DR script/tests must move with the `.tf` or the next audit and CI go red), and README/ADR-032 already record that enabling and verifying cannot be separated across merges. A split would put the `.tf` flip in a PR whose prerequisites are in another, and `workflow_dispatch` cannot ack the destroy-guard, so the apply cannot be staged. Rejected split: (a) PR-1 prerequisites / PR-2 flip. Cost: a second cycle and the same unverifiable-before-enable gap; benefit: observe the alert gate on a real push before the flip — which is instead delivered by Phase 7's ordering (the gate and CLA synthetics land on main in the same commit that the apply fires from, before any entry can be queued).

## Problem Statement / Motivation

- Merge-train tax: ~10 auto-merge-armed PRs race the same BEHIND → `update-branch` → full CI loop (observed 3x BEHIND cycles, ~45 min churn on a docs-only PR; `2026-06-02-auto-merge-livelock-fast-moving-main.md`).
- The earlier adoption (#5800) deadlocked in ~14 minutes because CodeQL cannot report on `merge_group`; the decision recorded was to keep CodeQL required and skip the queue. The operator re-weighed: the merge-train tax is the top CD bottleneck, so CodeQL becomes advisory.

## Proposed Solution

### Architecture

```text
PR ──pull_request──> CI Required (23 ctx, 15368) + CLA Required (2 ctx)  [real]   + CodeQL (advisory, not required)
 │
 └─ enqueue (auto-merge) ──> merge_group temp ref gh-readonly-queue/main/pr-N-<sha>
        23 CI contexts: real (workflow-level merge_group + no excluding job `if:`)       <- Guard 1
        cla-check, cla-evidence: merge-queue-cla-synthetics.yml, fail-closed vs PR head   <- Guard 1
        pending > 45 min: merge-queue-stall-check.yml (*/10 cron) files an issue
 └─ merge ──push to main──> CodeQL default setup (3 analyses, ~3 min)
                           codeql-main-alert-gate.yml: wait Analyze(*) check-runs -> untracked critical/high alerts
                           -> critical/high: file `sec: CodeQL alert #N` + exit 1 (page-and-continue)
```

### merge_queue parameters (open question 3)

Derived from the measured CI distribution above (p50 17.7 / p90 25.9 / max 32.8 min), the prior adoption's
provider-schema probe (provider `integrations/github` 6.12.1 supports the full block), and the CTO review.

| Param | Value | Why |
|---|---|---|
| `merge_method` | `SQUASH` | Matches `gh pr merge --squash`; repo `squash_merge_commit_message=COMMIT_MESSAGES`. |
| `grouping_strategy` | `ALLGREEN` | Safe default; with `max_entries_to_merge = 1` every group is one PR. |
| `max_entries_to_merge` | `1` | One PR per merged group keeps CLA verification exact (the group's PR number is in `head_ref`) and avoids batch-failure bisection. |
| `min_entries_to_merge` | `1` | Merge a green candidate immediately. |
| `min_entries_to_merge_wait_minutes` | `0` | Provider default would add 5 minutes to every merge (CTO). Set explicitly. |
| `max_entries_to_build` | `2` | Speculation (the point of the queue) with bounded runner contention: each entry runs all 25 contexts, so 3 parallel builds is ~3x jobs and may push wall-clock past p90 on hosted runners (CTO). Raise to 3 after the canary shows contention is not binding. |
| `check_response_timeout_minutes` | `60` | Must exceed the slowest required check on `merge_group` INCLUDING runner start spread. Inputs: PR wall-clock max 32.8 min (p90 25.9, `gh run list --workflow ci.yml`), and ADR-032's 2026-09-14 measurement of a 28-minute (1708 s) maximum start spread on a drained group, i.e. spread plus critical path can reach ~43 min; 60 leaves margin and is a one-line change either way. The prior value (15) was sized on an 8-minute critical path; an under-set value dequeues a green PR and re-creates the starvation. The stall probe threshold is 50 (below this, so a stuck entry is reported before the queue ejects it silently). |

`merge_group` CI wall-clock has not been measured (no `merge_group` runs exist); Phase 0 and the canary
record it. If the slowest required check on a real candidate exceeds 30 min, raise the timeout in the
same Terraform root (a one-line diff).

### Alert-gate semantics (open question 2)

Decision: **page-and-continue**, not block. The gate runs after the merge commit is on `main`, so it
cannot block; it must (a) turn the run red, (b) file a deduplicated issue, and (c) never auto-revert.

"New on this push" vs the standing backlog, without state or timestamps:

- An alert is **new** when no tracking issue exists for it. The tracker is the state: the daily
  `codeql-to-issues.yml` cron files `sec: CodeQL alert #N` for every open critical/high alert, so the standing
  backlog is by definition already tracked (today: 3 open alerts, all `medium`, zero critical/high — nothing
  to seed). A `created_at` watermark was rejected: `created_at` is the alert's first detection on ANY ref,
  normally the PR's own scan, so a queued PR scanned before the previous main push would sit below the
  watermark and be missed (review finding; this is the common case under a queue).
- Candidate = open alert on `ref=refs/heads/main` with `rule.security_severity_level ∈ {critical, high}`.
- For each candidate, look for an existing OPEN issue whose title starts with `sec: CodeQL alert #<N>` (the daily cron's
  convention), label `type/security`, authored by the Actions bot
  (`gh issue list --label type/security --author app/github-actions --state open --limit 200`, exact prefix match
  in `jq`). Free-text `gh search issues` is not used: the repo is public, so anyone can open an issue titled for an
  upcoming alert number and poison a title-only dedupe (the existing `codeql-to-issues.yml` has the same flaw at
  its `gh search issues` line). Closed issues are NOT a dedupe signal: an open alert whose tracker was closed is
  not tracked (the owner dismisses the alert, which the orphan sweep then reconciles). Exists → skip. Missing →
  file it. Issue content is data-minimised: title from `#N` and a rule id validated against
  `^[A-Za-z0-9_./-]{1,100}$`; body holds only the alert number, rule id, severity and a URL built from the number
  (never the alert message or file text, which a PR author controls and which can carry markdown, `@mentions`
  and links), written via `--body-file`; labels `type/security`, `priority/p1-high`, `action-required`. The page
  is the labelled issue, not a notification: a push made by the merge queue has no human actor to notify, and a
  `GITHUB_TOKEN`-filed issue does not trigger `auto-label-security.yml`, so the script sets every label itself;
  `action-required` is the operator-visible surface `operator-digest` harvests.
- Accepted residual (design-pass review): the gate reads only `state=open` alerts, so an insider dismissing a
  critical/high alert is not covered. It is the same trust that can `--admin` merge; the earlier dismissal-evasion
  check (allow-list, `dismissed — review` issues) was removed as unreachable beyond that trust and prone to
  misfire on a null `dismissed_by`. Accepting a risk is done by DISMISSING the alert; closing the tracking issue
  re-files it on the next push.
- Degraded exits (deadline exceeded, cap hit, zero check-runs, API error) upsert one `codeql-gate-degraded` issue (labels
  `meta/machinery` (ADR-216: a finding about the gate's own machinery), `type/security` (the dedupe read is scoped to
  it), `priority/p2-medium`, and `action-required` (added in the review round: it is the label the operator digest
  harvests, and `meta/machinery` alone is dropped from the digest; precedent `scheduled-actions-queue-health.yml`);
  exact-title dedupe, bot-authored, open) instead of leaving a red run nobody sees. A degraded exit reads no alerts.
- `workflow_dispatch` inputs are validated: `sha` must match `^[0-9a-f]{40}$`, `dry_run` is a boolean input.
- Concurrency: one pending run per group; the check is state-based, so a dropped SHA is covered by the next run.
- Verdict: **RED iff this run filed at least one issue**; any API/filing error is also RED. A re-run on the
  same alert is green (already tracked) — the issue is the durable page, the red run is the push-time signal.
  Accepted race: if the daily cron files the issue first, the push run is green and the issue still exists.
  Accepted: attribution to "this push" is by run time, not by proof of introduction.
- Wait: poll `GET repos/{r}/commits/{sha}/check-runs` for check-runs named `Analyze (*)` from app
  `github-actions` until at least one exists and all are `completed` (30s poll, 50 polls, under a 30-minute wall-clock
  deadline checked after every poll in both phases); take the latest
  run per name; a cap or deadline hit or a non-success conclusion is a RED run (degraded), never green. A run with zero
  `Analyze (*)` check-runs after the cap is RED (vacuous-green guard). Completed check-runs do not prove the
  analyses were ingested, so phase 2 additionally waits for THIS commit's analyses: the `analyses` endpoint IGNORES
  `sha=` when `ref=` is set (measured: 8,926 analyses over 90 pages, ~30 s), so ONE page (`per_page=100`, newest
  first, `ref=refs/heads/main`) is read per poll and filtered in `jq` on `.commit_sha == <sha>`, until that count is
  at least one and unchanged across two consecutive polls (still within its own poll budget and the deadline), then read alerts.
- Fail closed: any `gh api` error in any step is a non-zero exit (the existing `codeql-to-issues.yml` pattern
  `... || true` is the failure this avoids).
- Permissions: `contents: read`, `security-events: read`, `issues: write`, `checks: read`; `GITHUB_TOKEN` only.

### CLA synthetics (hardened)

Restore `merge-queue-cla-synthetics.yml` (from `git show 4439c23c39^:.github/workflows/merge-queue-cla-synthetics.yml`)
with one change required by the CLO: do not post unconditional success. Parse the PR number from
`merge_group.head_ref` (`refs/heads/gh-readonly-queue/main/pr-<N>-<sha>`), read the PR's head SHA, require the
real `cla-check` and `cla-evidence` check-runs to be `success` (app `github-actions`, 15368, `--paginate`) on that head, taking the LATEST run per name (the `pull_request_target`/`issue_comment` producers leave several runs, so an old red followed by a newer green passes and the reverse fails — as the ruleset itself resolves them), and
post the two check-runs on `merge_group.head_sha` only then; any miss or red → fail the job AND post both names on `merge_group.head_sha` with `conclusion=failure` and the reason in the title (review round: a bare job failure left the entry pending until the 60-minute timeout, since the synthetic job is not itself a required context; with failure contexts the queue dequeues it immediately). The latest run per name is chosen by check-run id, not `started_at` (a queued re-run has a null `started_at` and a stale success must not mask it). Auth stays `GITHUB_TOKEN` (the ruleset matches
integration_id 15368); permissions `checks: write`, `checks: read`, `pull-requests: read`, `contents: read`.
Hardening (security and architecture review): `head_ref` is routed through an env var and validated against
`^refs/heads/gh-readonly-queue/main/pr-[0-9]+-[0-9a-f]{40}$`; `merge_group.base_ref` must be `refs/heads/main`; there is
deliberately no parent-of-candidate check (with SQUASH the candidate is a single-parent squash commit and a push to a queued PR dequeues it, see ADR-269); the verification
logic runs from a checkout of the repository's DEFAULT branch tip (`ref: ${{ github.event.repository.default_branch }}`,
`persist-credentials: false`), never the candidate, because the workflow was originally checkout-free precisely so no
PR-controlled code ran with a `checks: write` token under the 15368 identity. Residual, accepted and recorded in
ADR-269: the workflow definition itself comes from the candidate commit like every other `merge_group` workflow, and
entry to the queue requires a write-access actor (the same trust that already lets a same-repo PR run its own
workflows with a token); `CODEOWNERS` review is not enforced by the CI ruleset. Entry-gate premise (cite in the workflow header): GitHub docs "Managing a merge queue" — a PR can be
added to the queue only after passing all required branch protection checks.

### Queue-awareness of the merge tooling

- `plugins/soleur/scripts/sync-pr-behind.sh`: before `--step` or the standalone loop pushes, read the queue state
  (`isInMergeQueue`, `mergeQueueEntry`, `state`, `autoMergeRequest`); when queued → `--step` prints `kind=queued rc=11` and
  exits 11 (the fences' uncounted `sync_noop` arm; the standalone loop exits 0). One read, retried once, lives in the
  script and is reachable as `--queue-state`; the hook and `monitor-pr-checks.sh` use it. A failed read must not be read as
  "not queued" (exit 4 with `kind=gh`). Dequeue detection (review round): the script marks a PR it read as queued and
  prints `kind=dequeued rc=13` on a later not-queued + OPEN + auto-merge-disarmed read, detected only on a BEHIND tick
  (canary: which `mergeStateStatus` a queued PR shows); `MAX_POLL_MIN` 60 → 90 in both fences; recovery in
  `ship/references/merge-queue-dequeue.md`. Details and the hook's recognised argument forms: ADR-269 Decision 5.
- `plugins/soleur/lib/pr-merge-poll.ts` + ship Phase 7 / merge-pr §5.2: treat `BEHIND`/`DIRTY` on a queued PR as
  "queued, keep polling for MERGED / removed-from-queue"; a PR that leaves the queue without merging (OPEN, no
  `mergeQueueEntry`, auto-merge disarmed) is the "rejection" arm that ship already handles at "If CLOSED (merge
  queue rejection …)" — extend to OPEN-but-dequeued.
- Verify, do not assume: whether `mergeStateStatus` still reports `BEHIND` for a PR that is enqueued under a
  strict ruleset is empirical (the canary records the observed value; the guard above is correct either way).
- `.claude/hooks/pre-merge-rebase.sh` (runs on `gh pr merge`): skips its sync for an already-queued PR (bare-number and
  the other recognised forms only), warns on stderr when the queue read fails and falls back to the sync; a not-yet-queued
  behind PR still syncs (pre-enqueue tax, ADR-269 Follow-up (d)).

## Implementation Phases

Order follows `cq-write-failing-tests-before`: tests (RED) first, then the implementation that turns them green.

### Phase 0 — Empirical gates (commands, expected output; paste results into the PR body)

| # | Command | Expected |
|---|---|---|
| 0.1 | `bash scripts/probe-merge-group-coverage.sh` (written in Phase 1) run on the base branch | RED: names `cla-check` and `cla-evidence` as having no `merge_group` producer; 23 CI contexts GREEN. (This reproduces the audit finding as an executable fact.) |
| 0.2 | `gh api repos/jikig-ai/soleur/commits/<main-sha>/check-runs --paginate --jq '.check_runs[]\|select(.name\|startswith("Analyze ("))\|[.name,.app.slug,.status]\|@tsv'` | `Analyze (actions\|javascript-typescript\|python\|ruby)`, app `github-actions`, `completed` |
| 0.3 | `gh api "repos/jikig-ai/soleur/code-scanning/analyses?ref=refs/heads/main&sha=<main-sha>" --jq '[.[].category]'` | three `/language:*` categories (no ruby) — documents why the wait is on check-runs |
| 0.4 | Provider schema probe in a scratch dir with no `backend` block (`terraform init -backend=false` + `terraform providers schema -json`) | `github_repository_ruleset.rules.merge_queue` nested block (`max_items = 1`) with 7 OPTIONAL attributes, enums `merge_method` MERGE|SQUASH|REBASE and `grouping_strategy` ALLGREEN|HEADGREEN, provider defaults 60/5/5/1/5 (confirmed by the deepen-pass offline probe against 6.12.1; the plan sets all seven explicitly). The real plan shape (`nested_deletes=1`) is first seen in the apply run's plan step; `tests/scripts/test-destroy-guard-counter.sh` only exercises the counter. |
| 0.5 | `gh api graphql -f query='{repository(owner:"jikig-ai",name:"soleur"){mergeQueue(branch:"main"){id}}}'` | `mergeQueue: null` before apply, non-null after |

### Phase 1 — RED tests and fixtures

1. `scripts/probe-merge-group-coverage.sh` (the Guard 1 engine: a fast read-only probe, also the Observability `discoverability_test`) and `plugins/soleur/test/required-checks-merge-group-coverage.test.sh` (the mutation battery; runs the engine against the real repo as case 0 and against mutated copies; auto-globbed by `SUITE_GLOBS` in `scripts/test-all.sh`) + fixtures under `plugins/soleur/test/fixtures/merge-group-coverage/`.
2. `plugins/soleur/test/codeql-main-alert-gate.test.sh` (Guard 3) + fixtures under `plugins/soleur/test/fixtures/codeql-main-alert-gate/` (check-runs, analyses, alerts pages, a `gh` shim that records calls). Fixtures are synthesized (`cq-test-fixtures-synthesized-only`).
2b. `plugins/soleur/test/merge-queue-cla-verify.test.sh` (verification rows above), same shim conventions as item 2.
3. `tests/scripts/test-audit-ruleset-bypass.sh`: replace T-mq-1 "stays reverted" with the param-parity + CodeQL-absent gate (Guard 2); update T-rsc-2/3/5b/6/7 (24 → 23 entries, no CodeQL row). The CodeQL spoof-guard intent (a same-name 15368 check must not satisfy a 57789 gate) moves to a synthetic two-row fixture, not the real canonical.
4. `plugins/soleur/test/sync-pr-behind.test.sh`: queued PR → `kind=queued`, no merge, no push; GraphQL failure → non-zero `kind=gh`.
4b. (Dropped at design-pass review: no committed destroy-guard fixture or T9/T10 cases. The existing nested-removal cases already cover the counter; the live apply plan is the authority that exactly ONE `required_check` (`CodeQL`) is removed.)
5. Run all four: they must be RED for the stated reason before any implementation edit (`wg-when-tests-fail…`).

### Phase 2 — CLA synthetics + stall probe (restore, harden)

- `.github/workflows/merge-queue-cla-synthetics.yml` (hardened as above) calling `scripts/merge-queue-cla-verify.sh` (run from a default-branch checkout, see Hardening above), which holds the verification logic so it is testable with the `gh` shim (`plugins/soleur/test/merge-queue-cla-verify.test.sh`: old red then newer green passes, old green then newer red fails, a missing context fails, an unparseable or wrong-shape `head_ref` fails, a single-parent squash-shaped candidate whose parent is not the PR head passes, a `gh` error fails, and a bot-PR head carrying the composite action's synthetic `cla-check`/`cla-evidence` (app 15368) passes).
- `.github/workflows/merge-queue-stall-check.yml` from `git show 4439c23c39^:.github/workflows/merge-queue-stall-check.yml`; set `STALL_THRESHOLD_MINUTES` to 45 (< 60-min timeout) and the cron to `*/10` (the original `*/30` cadence against a 15-minute margin below the timeout would miss most ejections: a 10-minute cadence gives a detection window at least as wide as the cadence), update header comment (timeout 60, not 15). It is a GH-Actions cron on `GITHUB_TOKEN` (ADR-033 repo-scoped) — no Inngest, no app secrets. Review round: it ages only entries at `position <= max_entries_to_build` (a healthy deep queue is not a stall), labels its issue `merge-queue-stall` + `action-required`, and is BEST-EFFORT because GitHub `schedule:` delivery on this repo measured gaps of hours (ADR-269 "Stall probe"); the Inngest dispatch cron that would fix it is a follow-up, not part of this PR.
- Re-run `bash plugins/soleur/test/c4-count-parity.test.sh` (baseline 12/12) and the repo's workflow-inventory/orphan-suite guards; neither new workflow uses the heartbeat composite, so no monitor-count edits are expected — verify, don't assume.

### Phase 3 — Alert gate

- `scripts/codeql-main-alert-gate.sh` (logic; bounded `--limit` on every `gh` enumeration to satisfy the #6793 gate in `plugins/soleur/test/components.test.ts`; `gh api --paginate` for alerts; `set -euo pipefail`; no `|| true` on a data fetch; env-var inputs only, no `${{ }}` in `run:`).
- `.github/workflows/codeql-main-alert-gate.yml`: `on: push: branches: [main]` + `workflow_dispatch` (inputs `sha`, `dry_run`); `concurrency: group: codeql-main-alert-gate, cancel-in-progress: false`; `timeout-minutes: 40` (the script's 30-minute wall-clock deadline degrades first); SHA-pinned actions; permissions as above; calls the script with `GITHUB_SHA`.
- Not a required check, not a dependency of the release/deploy chain (verify with a grep that no workflow `needs:`/`workflow_run:`/`deploy-arm.sh` keys on it).

### Phase 4 — Tooling queue-awareness and docs that describe the merge flow

- `plugins/soleur/scripts/sync-pr-behind.sh` (+ `--help` text, the exit-code table), `plugins/soleur/lib/pr-merge-poll.ts` (+ its test if one exists), `plugins/soleur/skills/ship/SKILL.md` Phase 7 prose and `plugins/soleur/skills/merge-pr/SKILL.md` §5.2 mirror fence (`kind=queued` is a no-op tick; the fences keep their `BEHIND detected` / `auto-sync N pushed` sentinels). **Byte budget:** `plugins/soleur/test/skill-body-budget.json` caps `ship` at 274000 bytes and `ship/SKILL.md` is 273751 bytes today (measured with `wc -c`), i.e. 249 bytes of headroom, enforced against the merge base by `scripts/lint-skill-body-budget.py --base origin/main`. So the queue behavior lives in `sync-pr-behind.sh` and `pr-merge-poll.ts` (the fences already call the script), and the `ship/SKILL.md` edit is at most one sentence (<= 200 bytes net) or none; `merge-pr` and `drain-prs` carry no ceiling.
- `plugins/soleur/skills/drain-prs/SKILL.md` §4: replace the "No merge queue on `main`" bullet with the active-queue bullet (`gh pr merge --squash --auto` enqueues; no hand-rolled update/wait loops; admin bypass is last resort), keep a one-line history pointer to #5800/#5811 and #5840 as the upstream tracker. Add the dequeue arm: a PR that leaves the queue with CI red on the `gh-readonly-queue/...` temp ref (the failing check-run is on the queue SHA, not the PR head, so `gh pr checks` still reads green) is read via `gh run list --event merge_group --branch gh-readonly-queue/main/pr-<N>-*`; on a conflict or lockfile/`kb-index` drift the local arm is merge `origin/main`, push, re-arm, capped at ONE re-enqueue before escalating. Sweep other skills that state or assume direct merge (grep `gh pr merge`, `update-branch`, `BEHIND` under `plugins/soleur/skills` and `.claude/hooks`) and edit only prose that is now false.
- `plugins/soleur/skills/ship/scripts/battery-owed.sh` header comment (26 contexts / CodeQL 57789) and `plugins/soleur/scripts/admin-merge-ready.sh` (+ test + fixtures): verify the rule-shape handling with a `merge_queue` rule in `rules/branches/main` and the CodeQL context absent; adjust fixtures to the post-change live shape. Skill description budget: no `description:` frontmatter edits planned — if one becomes necessary, run the budget one-liner first (`cq-skill-description-budget-headroom`).

### Phase 5 — Terraform and lockstep (the gating change)

- `infra/github/ruleset-ci-required.tf`: remove the `CodeQL` `required_check`; add the `merge_queue` block inside `rules {}` (params table above); rewrite the two header/kill-switch comments (the "REVERTED / DO NOT re-adopt" text becomes the re-adoption record; keep the "select by `.type`, never `.rules[0]`" warning). Keep `variable "codeql_integration_id"` in `variables.tf` (referenced by the rollback/re-tighten recipe) with a comment that it is unused while CodeQL is advisory. Count-contract comment: 24 → 23 contexts.
- `scripts/ci-required-ruleset-canonical-required-status-checks.json`: drop the `CodeQL` row (the `.tf`↔canonical parity test T-rsc-9 and the daily live audit key on it).
- `scripts/create-ci-required-ruleset.sh`: DR skeleton gains the `merge_queue` rule with a sync guard that its params track the `.tf`; drop CodeQL; the PUT carries `bypass_actors` and `conditions` (replace semantics). The REST API requires ALL seven parameters together (a partial payload 422s): `{"type":"merge_queue","parameters":{"merge_method":"SQUASH","grouping_strategy":"ALLGREEN","max_entries_to_merge":1,"min_entries_to_merge":1,"min_entries_to_merge_wait_minutes":0,"max_entries_to_build":2,"check_response_timeout_minutes":60}}` — do not copy the 15/5/5 values from the historical skeleton at commit `1f041b9d6a`; restore the DR verification `jq` that prints the queue parameters. If the queue deadlocks AND the admin bypass fails, the emergency path is documented prose, not code: PUT the script's payload minus the `merge_queue` rule to the EXISTING ruleset id (`gh api -X PUT repos/jikig-ai/soleur/rulesets/14145388 --input <payload>`); deleting the live ruleset first would leave `main` with no required checks during the window.
- `scripts/lib/canonicalize-required-status-checks.sh`, `scripts/required-checks.txt`, `.github/actions/bot-pr-with-synthetic-checks/action.yml` comments: CodeQL is no longer in any required set; "intentionally omitted" prose becomes "not required (advisory)".
- Merge-commit requirement: one commit message BODY (never a subject line — a multi-commit `COMMIT_MESSAGES` squash prefixes subjects with an asterisk and a space) carries a line that is exactly `[ack-destroy]`; verify it is present on its own line in the final squash message before merging. The PR body carries it too (the queue may build the message from the PR title/body for later infra PRs).

### Phase 6 — Records

- ADR-269 (provisional ordinal; re-verify next-free against `origin/main` at ship): "Merge queue with advisory CodeQL and a post-merge alert gate" — supersedes the ADR-032 2026-07-01 "keep CodeQL required, no queue" decision; records the trade (PR-head blocking → post-merge detection), accepted residual risks, parameters, CLA synthetic trust model, rollback and re-tighten recipe, and the status `adopting` until the canary passes. ADR-032 gets an amendment pointer (its checklist items move to the canary below).
- `infra/github/README.md` "Merge queue (#5780)" section: status → active; params table; two-PR sequencing paragraph rewritten (restoration done); kill switch; rollback file list.
- `.github/workflows/scheduled-terraform-drift.yml` comment (queue is live, drift detector now also sees the `merge_queue` rule); `.github/workflows/codeql-1537-revisit-watch.yml` header (on upstream close: re-add the `CodeQL` required_check — queue and a working `merge_group` CodeQL status then coexist; one Terraform diff).
- `knowledge-base/engineering/operations/runbooks/codeql-bot-coverage.md`: CodeQL on bot PRs is advisory now.
- Legal records (CLO): `knowledge-base/legal/article-30-register.md` PA12 in-cell correction with a `Superseded <date> (#9454)` marker; `knowledge-base/legal/compliance-posture.md` line 59 superseded pointer; one-line CLO determination in `knowledge-base/legal/audits/2026-08-17-clo-ruling-cla-evidence-admin-bypass-7597.md` that its re-evaluation trigger does not fire (`cla-evidence` stays required, satisfied on `merge_group` by a verified synthetic).
- C4: see `## Architecture Decision (ADR/C4)`.

### Phase 7 — Ship, apply, canary (see Rollout section)

## Alternative Approaches Considered

| Alternative | Verdict |
|---|---|
| Advanced setup + `merge_group` trigger + status shim | Rejected by operator: re-owns the #5800 bug class; a self-owned shim in the queue's highest-concurrency path; hand-maintaining a 5-language matrix. |
| Bot pseudo-queue (cron: oldest armed PR → update-branch → wait green → merge) | Rejected by operator: strictly serial, no speculation, merge-driving orchestrator. |
| Drop `strict_required_status_checks_policy` | Rejected by operator: independent-green PRs with semantic conflicts land with no integrated-state CI. |
| Required Pattern-B PR-head alert gate (a required Actions job that waits for the PR's CodeQL analyses, fails on new critical/high on `refs/pull/N/merge`, and passes through on `merge_group` via the entry-gate premise) | Not adopted (operator chose advisory). It would keep PR-head blocking with no shim on CodeQL's own status. Persisted as a User-Challenge in `decision-challenges.md`; not scheduled. |
| Two PRs (prerequisites, then the flip) | Rejected, see Split Assessment. |
| `max_entries_to_build = 3` from day one | Deferred to the canary result (runner contention). |

## User-Brand Impact

- **If this lands broken, the user experiences:** the merge path to `main` stalls (queue entries pending), delaying every fix and release to the web-platform product; no running service is affected (prod keeps serving the prior commit, as in the 2026-06-30 incident).
- **If this leaks, the user's data is exposed via:** a critical/high CodeQL finding (for example an injection or auth flaw in `apps/web-platform`) merging to `main` and deploying before the post-merge gate's alert and issue are acted on — now possible for a PR-head finding as well as an interaction-only one, because CodeQL no longer blocks pre-merge.
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** `aggregate pattern`, not `single-user incident`: the exposure needs a critical/high finding that the pre-merge scan reports but nothing now blocks, and the gate pages about 9 to 11 minutes after the push (measured: `Analyze (javascript-typescript)` 21:47:17Z to 21:56:16Z/21:57:57Z on origin/main b77bee3707, plus ingestion); the deploy completes 12.9 to 41.1 min after the merge (n=12) and nothing in the deploy chain waits for the gate, so a flagged commit can deploy unattended. That is an accepted residual (measured numbers and the deploy-hold alternative: `decision-challenges.md` User-Challenge 1; the `actions`-language vector that needs no deploy: Challenge 3; the reviewer's case for `single-user incident`, which the operator has not taken: Challenge 2). It is a pattern risk across users rather than a one-user incident, and revert is a single diff. Not `none`: the control being weakened is a security gate on a product that handles user data.

## Observability

```yaml
liveness_signal:
  what: >
    Per-push conclusion of .github/workflows/codeql-main-alert-gate.yml (green = analyses settled and
    no new critical/high alert; a push superseded in the concurrency group concludes `cancelled`, which is neither
    green nor red, and the next run still reads the whole ref's alerts); conclusion of
    .github/workflows/merge-queue-stall-check.yml (requested every 10 minutes, delivered best-effort: see failure_modes);
    merge_group runs of the 23 CI contexts + merge-queue-cla-synthetics.yml.
  cadence: per push to main (gate) / requested every 10 minutes, actual schedule delivery degraded (stall probe) / per queue entry (synthetics)
  alert_target: >
    GitHub issues labelled `action-required` (`sec: CodeQL alert #N` with type/security and priority/p1-high;
    `codeql-gate-degraded` with meta/machinery, type/security, priority/p2-medium and action-required;
    `merge-queue stall: PR #N pending` with merge-queue-stall and action-required); a red run on a queue-made push
    notifies no person, so the labelled issue is the page (the operator digest harvests `action-required`
    weekly; nothing pushes a notification beyond the issue-creation event); no Sentry (GitHub-hosted workflows on
    GITHUB_TOKEN per ADR-033).
  configured_in: .github/workflows/codeql-main-alert-gate.yml, .github/workflows/merge-queue-stall-check.yml, .github/workflows/merge-queue-cla-synthetics.yml

error_reporting:
  destination: GitHub Actions run log (layer 6, workflow run log) and the filed GitHub issues
  fail_loud: "`::error::` annotations and exit code 1 from scripts/codeql-main-alert-gate.sh (the red-vs-degraded distinction is in the log text only); stall-check files `merge-queue stall: PR #N pending >45m`; a failed CLA verify posts failing `cla-check`/`cla-evidence` contexts on the candidate"

failure_modes:
  - mode: A required context has no producer on merge_group (queue deadlock redux)
    detection: >
      Pre-merge: scripts/probe-merge-group-coverage.sh (run by plugins/soleur/test/required-checks-merge-group-coverage.test.sh) fails CI (workflow run log, ::error::).
      Post-enable, BEST-EFFORT: merge-queue-stall-check.yml (layer 6 workflow run log + filed issue) for an entry at position <= max_entries_to_build
      pending past 45 minutes; detection latency is the threshold plus the schedule delivery delay, and `schedule:` delivery on this repo measured gaps of
      hours, so no issue is not proof of a healthy queue and an ejected entry leaves the queue silently. Measured post-merge (schedule-event gap row); the
      Inngest dispatch cron that removes the dependency is a follow-up (decision-challenges.md, Follow-up (a)).
    alert_route: GitHub issue labels merge-queue-stall + action-required; red `test` check on the PR
  - mode: CLA synthetic cannot verify the PR head's real cla-check/cla-evidence
    detection: merge-queue-cla-synthetics.yml exits non-zero with ::error:: naming the PR and the missing/red context (workflow run log) AND posts `cla-check` and `cla-evidence` with conclusion=failure on the candidate with the reason in the title
    alert_route: the queue entry fails visibly and is dequeued at once (the failure contexts, visible in `gh run list --event merge_group`); the best-effort stall probe covers a hung job
  - mode: New critical/high CodeQL alert on main after a merge
    detection: codeql-main-alert-gate.yml red run + `sec: CodeQL alert #N` issue (workflow run log, ::error::)
    alert_route: GitHub issue label type/security; red run on the push
  - mode: CodeQL analyses never appear or never complete for the pushed commit
    detection: gate poll cap or the 30-minute wall-clock deadline hit, or zero `Analyze (*)` check-runs -> red run with ::error:: (workflow run log) AND one upserted `codeql-gate-degraded` issue (deduplicated, labels type/security, meta/machinery, priority/p2-medium, action-required) — a push made by the merge queue notifies no person, so a red run alone routes to nobody; the deadline sits below the 40-minute job timeout so the issue is filed before a job kill
    alert_route: GitHub issue `codeql-gate-degraded` (action-required); red run on the push
  - mode: GitHub API error inside the gate (alerts, analyses, check-runs, issue create)
    detection: non-zero exit with the failing endpoint named (workflow run log, ::error::); never reported as "no alerts"; also upserts the `codeql-gate-degraded` issue
    alert_route: GitHub issue `codeql-gate-degraded`; red run on the push
  - mode: The gate never fires (workflow disabled, deleted, or not triggered by queue-made pushes)
    detection: the daily codeql-to-issues.yml cron (workflow run log + its `sec:` issues) is the only backstop, so exposure is up to 24 hours plus schedule delay, and that cron swallows API errors with `|| true` today (decision-challenges.md, Follow-up (b)); the first-push canary proves the trigger fires for a queue-made push; a `GITHUB_TOKEN` push does not fire push workflows
    alert_route: GitHub issue label type/security
  - mode: merge_queue rule silently removed or edited outside Terraform
    detection: scheduled-terraform-drift.yml infra/github plan (workflow run log + its drift issue); the stall probe is blind to a disabled queue by design
    alert_route: drift issue
  - mode: Queue entry dequeued by a BEHIND sync push
    detection: sync-pr-behind.sh prints `kind=queued` and does not push (stdout, layer 6 workflow/session log); the script marks a PR it read as queued (a file in the git dir) and on a later `--step` read of not queued + OPEN + auto-merge disarmed prints `kind=dequeued rc=13`, which the ship and merge-pr fences' existing `*)` arm turns into "Stopping the poll"; `monitor-pr-checks.sh` ends `LEFT THE MERGE QUEUE UNMERGED`; recovery in `ship/references/merge-queue-dequeue.md`. The hook warns on stderr when its queue read fails. Known limit: the script runs only on a BEHIND tick, so a dequeued PR that reads another state runs the poll to the 90-minute timeout (canary records which `mergeStateStatus` a queued PR shows)
    alert_route: ship escalation arm (poll stops with the recovery text)

logs:
  where: GitHub Actions run logs for the three workflows above
  retention: GitHub default Actions log retention (90 days)

discoverability_test:
  command: bash scripts/probe-merge-group-coverage.sh
  expected_output: merge-group-coverage=OK
```

Post-merge live probes (not the Check 10 command, because they hold only after the apply): see Phase 7.

## Encryption Posture

```yaml
at_rest: []   # introduces no persistent store (workflows are stateless; the gate keeps no cache or artifact)
in_transit:
  - connection:        GitHub-hosted runner -> api.github.com (gh CLI, GITHUB_TOKEN)
    enforced_at:       scripts/codeql-main-alert-gate.sh and .github/workflows/*.yml (gh api / gh issue calls)
    tls:               HTTPS, TLS 1.2+ (gh CLI default)
    cert_verification: on
    does_not_defend:   a compromised GITHUB_TOKEN scope or a malicious workflow edit merged to main; the token is least-privilege per workflow (security-events:read, issues:write, checks:read) but TLS does not stop misuse of a valid token
    disclosed_as:      not-publicly-claimed
```

## Architecture Decision (ADR/C4)

### ADR

Create ADR-269 (provisional; next free after ADR-268 — re-verify against `origin/main`, sweep this plan, `tasks.md`
and any AC that names the ordinal if it moves) via `soleur:architecture`: "Merge queue with advisory CodeQL and a
post-merge alert gate". Decision: queue ON; CodeQL removed from `required_status_checks` and monitored by a push
gate; `max_entries_to_merge = 1`, `max_entries_to_build = 2`, 60-minute timeout; CLA contexts satisfied on
`merge_group` by a verified synthetic; revert/re-tighten recipes. It supersedes the ADR-032 2026-07-01 "keep
CodeQL required" decision (added to that ADR's amendments as a one-line pointer; its Alternatives table gains
"advisory CodeQL — adopted by ADR-269"). Status `adopting` until the Phase 7 canary passes.

### C4 views

Pre-finding (grep over `model.c4`, `views.c4`, `spec.c4` for `CodeQL`, `merge queue`, `ruleset`, `branch protection`,
`required check`): no hits; `github = system "GitHub"` and `engine -> github "Git operations and CI"` already model
this surface; CodeQL, the merge queue and rulesets are GitHub features, not new external systems or actors; no new
container or data store; no actor<->surface access relationship changes (the founder/agents already merge via
GitHub). The work phase MUST still READ all three `.c4` files in full (not a keyword grep) and confirm: no element
description is falsified (the `github` element/`engine -> github` edge prose does not state "direct merge" or
"CodeQL required"), then run `bash plugins/soleur/test/c4-count-parity.test.sh` (12/12 at baseline). Conclusion if
confirmed: "no C4 impact", citing external actors (none new), external systems (GitHub already modeled), data stores
(none), access relationships (unchanged), and the green count-parity run.

### Sequencing

The ADR is authored in this PR describing the target state with status `adopting`; it is not deferred. It must also record, as accepted residuals: the CodeQL pre-merge blocking loss; the pass-through gates (`rename-guard`, `allowlist-diff`, `waiver discipline`) trusting a pre-queue run that is synthetic for bot PRs and bypass actors; bot-PR `test`/`e2e`/`grok-fidelity`/content gates now earned rather than fabricated; and that the workflow definition on `merge_group` comes from the candidate commit.

## Guard Contract

### Guard 1 — merge_group coverage of every required context

**Property.** Every context required by ANY ruleset on the default branch is produced on a `merge_group` event, either by a job that runs on `merge_group` or by an explicitly listed synthetic producer that verifies the real result first.

**Assembly.** The quantifier ranges over (a) every context in `scripts/ci-required-ruleset-canonical-required-status-checks.json` AND `scripts/ci-cla-required-ruleset-canonical-required-status-checks.json` (both rulesets, not one), (b) every job in every `.github/workflows/*.yml` — the producer is resolved by job `name:` else job id, and a context must have EXACTLY ONE producing job (zero is a missing producer, two is ambiguity), (c) for each producer: the workflow's `on:` must contain `merge_group` (handle map, list and string forms and the PyYAML `on` -> `True` key quirk), the job's `if:` must be absent, exactly `always()`, or contain the literal `merge_group` (anything else fails closed unless allowlisted with a justification line), and (d) the single chokepoint for the CLA contexts is `merge-queue-cla-synthetics.yml`, which must itself post BOTH names. Members drift; the chokepoint is the canonical JSON files, so a context added to either ruleset is checked without editing the test. `CodeQL` is not in either JSON after this change; if it reappears the test fails with "no merge_group producer" (the 57789 GHAS context is not a workflow job).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Remove `merge_group:` from the `on:` block of `ci.yml` | RED naming `lockfile-sync` (and the other ci.yml contexts) |
| 2 | Add `if: github.event_name == 'pull_request'` to a required job (`adr-ordinals`) | RED |
| 3 | Empty or relocate the canonical JSON so zero contexts are read (the guard's own dispatch) | RED ("0 contexts examined"; floor of >= 20) |
| 4 | Add a context `cla-new` to the CLA canonical JSON with no synthetic producer (a second member after the compliant first two) | RED |
| 5 | Delete the `cla-evidence` iteration from `merge-queue-cla-synthetics.yml` (keep `cla-check`) | RED |
| 6 | Rename a required job (`name: lockfile-sync` -> `lockfile-sync2`) | RED ("no producer") |
| 7 | Add a second job in another workflow with the same `name:` as a required context | RED (ambiguous producer) |
| 8 | The most natural repair for a red row 4: add `cla-new` to the suite's synthetic allowlist without `merge-queue-cla-synthetics.yml` posting it | RED (the allowlist is cross-checked against the names the synthetic workflow actually posts) |

**Harness rows:** (H1) edit the suite so the YAML loader reads `d["on"]` only (misses the `True` key): the fixture `on: [pull_request, merge_group]` and the real `ci.yml` must still be classified correctly, so the suite goes RED if the loader regresses. (H2) a must-PASS non-canonical fixture: a workflow declaring `on: {merge_group: null, pull_request: {types: [opened]}}` with a job `if: always()` and one with `if: github.event_name == 'pull_request' || github.event_name == 'merge_group'` — both PASS. (H3) the engine prints `merge-group-coverage=OK contexts=<n> producers=<m>` and a run that prints `OK` with `contexts=0` is RED by the floor.

**Review-round additions (Guard 1).** The probe now EXECUTES the synthetic's wiring rather than scraping its text: a synthetic poster with a step-level `if`, a `continue-on-error` (job or any step), a job `needs`, a negated or `&& false` `merge_group` in the job `if`, or an extra posted name is rejected; `if: true` is accepted; only steps that post `conclusion=success` count as producers, and the synthetic names are derived from the CLA canonical JSON. Queue-off state: when no source carries a `merge_queue {` block (comments `#`, `//`, `/* */` ignored) the probe prints `merge-group-coverage=SKIPPED (no merge_queue rule: producers not required)` and exits 0, so a rollback PR that re-adds `CodeQL` does not go red; the check runs before the floor and producer checks, and a missing `.tf` is exit 2. The verdict helpers carry positive controls so a helper that stops recording cannot report green (coverage suite 47 rows, exact floor).

**Anchor.** The context list is read from the canonical JSONs, which are held equal to the live rulesets by the daily `cron-ruleset-bypass-audit` (outside any single commit) and to the `.tf` by T-rsc-9; weakening the guard requires editing the guard, the canonical, and the live ruleset in agreement.

### Guard 2 — merge_queue parameter parity and CodeQL-absent invariant (successor of T-mq-1)

**Property.** The `merge_queue` rule's value-bearing parameters are identical in the Terraform root, the DR restore skeleton and the README table, and no `CodeQL` required check coexists with a `merge_queue` rule in any of those sources.

**Assembly.** Sources: `infra/github/ruleset-ci-required.tf` (HCL block with comments stripped; the parser must accept aligned `=` whitespace and trailing `# comments` inside the block, as the historical block used), the heredoc skeleton in `scripts/create-ci-required-ruleset.sh` (JSON `rules[]` selected by `.type == "merge_queue"`, never positional), the params table in `infra/github/README.md`, and `scripts/ci-required-ruleset-canonical-required-status-checks.json`. All seven params compared, with the HCL keys mapped to the REST names.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Change `check_response_timeout_minutes` in the DR skeleton only | RED |
| 2 | Re-add the `CodeQL` required_check to the `.tf` while the queue block exists | RED |
| 3 | Re-add `CodeQL` to the DR skeleton only (second source after a compliant first) | RED |
| 4 | Delete the `merge_queue` block from the `.tf` but not from the DR skeleton | RED |
| 5 | Make the parser find zero params (rename the block key) — the guard's own dispatch | RED ("0 params compared") |

**Harness rows:** (H1) flip the comparison operator in the suite so everything matches: mutation 1 must still RED the suite under the unmodified harness (the test of the test: run the mutation battery against the real script, not a copy). (H2) must-PASS non-canonical: same values with different HCL whitespace/ordering and keys in a different order in the skeleton PASS.

**Review-round additions (Guard 2).** The HCL reader strips `#`, `//` and block comments with a tokenizer (a commented-out block no longer fakes presence). Beyond parity it pins the safety values (`max_entries_to_merge = 1`, `merge_method = SQUASH`, `check_response_timeout_minutes` strictly greater than the stall threshold). Queue-off is GREEN (no source carries `merge_queue`: the rolled-back state) while a half-removed state (queue in some sources only, or `CodeQL` required beside a live queue) stays RED. The suite carries controls and exact floors (62 assertions in `tests/scripts/test-audit-ruleset-bypass.sh`).

**Anchor.** Not applicable as a stored hash: parity is between live-edited sources, and the `.tf` is the value the apply workflow enacts; the drift cron holds the `.tf` equal to the live ruleset.

### Guard 3 — codeql-main-alert-gate verdict

**Property.** For a push to `main`, every open critical/high CodeQL alert on `refs/heads/main` that has no `sec: CodeQL alert #N` tracking issue yields exactly one such issue and a non-zero exit, already-tracked alerts yield neither, and no error path exits 0.

**Assembly.** Inputs and failure arms across the whole script: the check-runs wait (zero runs, in-progress at cap, a non-success `Analyze (*)` conclusion), the analyses-settled poll (one newest-first page, filtered to this commit; count non-zero and stable; other commits' rows never count), the alerts read (pagination: a qualifying alert on page 2; severity filter; ref filter), the dedupe search (open issues only, bounded), the issue create (failure), dry-run mode. Every `gh` invocation is an assembly member: a `gh` error at any of them must propagate. The chokepoint is a single `die()`/exit path; a `|| true` on any data fetch is the defect.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Seed a critical alert with no tracking issue (its `created_at` older than the previous push, the queued-PR case) | exit 1; one issue created |
| 2 | Seed a critical alert that already has a tracking issue (standing backlog) | exit 0; no issue |
| 3 | Make the alerts endpoint return HTTP 500 | exit non-zero (never "no alerts") |
| 4 | Put the qualifying alert on page 2 of a paginated response after a compliant page 1 | exit 1 |
| 5 | Leave one `Analyze (*)` check-run `in_progress` past the cap | exit non-zero (degraded), not green |
| 6 | Serve zero `Analyze (*)` check-runs | exit non-zero (vacuous-green guard) |
| 7 | The tracking issue exists but is CLOSED while the alert is open | the alert is untracked: a new issue is filed and the run is RED |
| 8 | `dry_run=true` with a qualifying alert | no `gh issue create`; exit 1 |
| 9 | Analyses count keeps changing, stays zero, or only OTHER commits' analyses are present (stable, non-empty) until the cap | exit non-zero (degraded), not green; this commit's stable count settles even while other commits' rows keep arriving |
| 10 | An alert whose message/rule text/file path contains a newline followed by `::error::forged`, markdown, or an `@mention` | no alert-controlled text reaches any annotation or issue field except the validated rule id (`^[A-Za-z0-9_./-]{1,100}$`; a non-matching id is replaced by `invalid-rule-id`); body built only from the alert number, rule id, severity and a URL derived from the number |
| 11 | All `Analyze (*)` check-runs completed but one concluded `failure` | exit non-zero (green requires a positive count of completed-success runs, never "no culprit named") |
| 14 | An open issue titled `sec: CodeQL alert #N` exists but is authored by a non-bot account (the poisoning case) | treated as untracked: the alert is filed and the run is RED |
| 15 | `workflow_dispatch` input `sha` is not 40 hex characters | rejected before any API call |
| 12 | Any degraded exit (cap hit, zero check-runs, API error) | exactly one `codeql-gate-degraded` issue is created or updated (deduplicated on title), plus the non-zero exit; a second degraded run does not create a second issue |

**Harness rows:** (H1) the `gh` shim records every call; a run with zero recorded calls and exit 0 is RED (vacuous harness). (H2) edit the suite to ignore the shim's exit status: mutation 3 must turn the suite RED. (H4) the shim replays the real `gh api --paginate` shape — concatenated top-level JSON arrays with no outer array, and `gh issue list` capped at its default 30 rows unless `--limit` is given; the analyses endpoint ignores `sha=` like the real API — so a parser that assumes one array, or an unbounded dedupe search, goes RED. (H3) must-PASS non-canonical: an alert with severity `High` (capitalised) and a `medium` standing alert — medium never files; a `refs/pull/*` alert instance is ignored.

**Review-round additions (Guard 3).** Row 13 (the dismissal-evasion row) is intentionally absent: that machinery was removed and insider dismissal is an accepted residual (ADR-269). Row 14 (the poisoned non-bot tracker) stays and is the bot-author dedupe check. Added rows: production poll defaults pinned by running the script with nothing overridden against a counting sleep stub (30 s, 50 polls, 8 phase-2 polls, 1800 s deadline); wall-clock deadline (a slow API degrades before the deadline); phase 2 has its own budget; unset `GH_REPO` exits 2; a hostile `gh` stderr does not survive `sanitize()`; non-`Analyze` check-runs are ignored; a duplicate alert number across pages files one issue; positive controls on the verdict helpers; the degraded issue carries `action-required`. The workflow's wiring is asserted by a separate suite that PARSES the YAML (`codeql-main-alert-gate-workflow-wiring.test.sh`, 65 assertions with mutants), not by greps.

**Anchor.** Not applicable: no stored value is compared; the tracking-issue state is read from GitHub at run time.

## Open Code-Review Overlap

1 open code-review scope-out touches a planned file path:

- #8593 ("#6793 probe gate window is narrower than the silent-truncation property it names") names `.github/workflows/codeql-to-issues.yml:57` (`gh search issues … --jq 'length'` over the default page cap). **Acknowledge:** this plan does not edit `codeql-to-issues.yml` (the gate coexists through the shared title convention); the new script uses explicitly bounded `--limit` on every `gh` enumeration so it does not add a member to #8593's list. The scope-out stays open.

## Domain Review

**Domains relevant:** Engineering, Legal

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Conditionally sound; gaps are lockstep files and queue squash-message semantics, not the CLA fix. Added: CodeQL lockstep sweep beyond the `.tf` (canonical JSON, DR script, `canonicalize-required-status-checks.sh`, `audit-ruleset-bypass.sh`, `admin-merge-ready.sh` + fixtures); `[ack-destroy]` in commit message AND PR body (queue message source uncertainty); runner contention -> `max_entries_to_build = 2`; `min_entries_to_merge_wait_minutes = 0`; an ADR for the security downgrade; queue-aware ship Phase 7. Single-PR sequencing accepted (merge happens under the old ruleset; the CLA workflows land in the same commit before the apply fires). Concurrency groups checked (`ci.yml` keys non-PR events on `github.sha`, no cancel on main).

### Legal (CLO)

**Status:** reviewed
**Assessment:** No blocking concern; no published legal doc claims CodeQL is a required merge check. Update `article-30-register.md` PA12 and `compliance-posture.md` line 59 (superseded markers, cell text changed in place); the CLA synthetic must read the PR head's real contexts and fail closed (adopted above); record that the 2026-08-17 `cla-evidence` ruling's re-evaluation trigger does not fire. Art. 32 posture unchanged (code scanning is cited only as a ruleset detail).

No Product/UX surface (infra/CI/tooling only): mechanical UI-surface override did not fire (no files under `components/`, `app/`, `*.tsx`).

## Rollout, Dark-Launch and Rollback

This is a gating-ruleset change (elevated risk tier at review; `wg-dark-launch-deploy-gates` applies in spirit).
The new gate (`codeql-main-alert-gate.yml`) ships NON-BLOCKING by construction (post-merge, not a required check,
no deploy depends on it). The only new gating surface is the queue itself, whose first real exercise is only
possible after the apply (`merge_group` does not fire before it — README), so the pre-enable evidence is the
offline Guard 1 audit plus the restored synthetics, and the post-enable evidence is the canary below.

### Sequencing

1. Review + preflight: elevated risk-tier panel; the PR body states "merge == apply of `infra/github`" and that it removes a required check.
2. **Per-command go-ahead before the merge** (`hr-menu-option-ack-not-prod-write-auth`): the agent presents the exact consequence ("merging triggers `apply-github-infra.yml`: removes the `CodeQL` required check and adds `merge_queue` on ruleset 14145388") and waits for the explicit go-ahead, and the go-ahead text also states the weakened control and asks the two decisions that `decision-challenges.md` ("What the operator should decide at the go-ahead") names: hold the deploy on a red or unfinished gate (default no) and the brand-survival threshold (default `aggregate pattern`); auto-merge is NOT armed on this PR. A headless run pauses here (irreversible-production-effect exception).
3. Merge with the squash message carrying a line that is exactly `[ack-destroy]`. The workflows and the apply arrive in the same push; `apply-github-infra.yml` runs after the files are on `main`, so no window exists with a queue and no CLA synthetics.
4. `wg-after-a-pr-merges-to-main-verify-all`: watch the apply run (`gh run list --workflow apply-github-infra.yml`). The FIRST canary step after the apply is the admin-bypass check (below): a failure is an IMMEDIATE rollback trigger. Then verify the live ruleset (below). A destroy-guard failure means the `[ack-destroy]` line did not survive into the squash message: merge a trivial follow-up touching `infra/github/` with the line in a commit message, or revert.
5. Before merging, confirm the apply plan (first visible in the apply run's plan step) shows exactly ONE `required_check` removal (`CodeQL`): `[ack-destroy]` blanket-authorizes any other destroy in the same plan, and a PR author controls both the commit message and the PR body, so it is a tripwire, not an independent control.
6. In-flight sessions and armed PRs: before the merge, list armed PRs (table below) so each can be confirmed to enqueue after the apply; an older checkout's `sync-pr-behind.sh` has no queued-skip and would dequeue a queued PR, so the queued-skip lands on `main` in this same PR and sessions pick it up on their next plugin sync.
7. `wg-after-merging-a-pr-that-adds-or-modifies` a workflow: dispatch `codeql-main-alert-gate.yml` (`sha` = current main, `dry_run=true`) and `merge-queue-stall-check.yml`; poll to completion; investigate failures.

### Post-merge verification (agent-run, no SSH)

| Check | Command | Expected |
|---|---|---|
| **1st: admin bypass (MANDATORY, run FIRST after the apply; the rollback depends on it)** | one `gh pr merge --admin` of a second trivial PR | merges past the queue (bypass_actors `RepositoryRole 5`, mode `pull_request`); if it does NOT bypass, this is an IMMEDIATE rollback trigger: the PUT-of-a-queue-less-payload emergency path (Phase 5) is the rollback and the plan must be amended before the queue is left on |
| Queue rule live | `gh api repos/jikig-ai/soleur/rulesets/14145388 --jq '[.rules[]\|select(.type=="merge_queue")]\|length'` | `1` |
| CodeQL no longer required | `gh api repos/jikig-ai/soleur/rulesets/14145388 --jq '[.rules[]\|select(.type=="required_status_checks")\|.parameters.required_status_checks[].context]\|index("CodeQL")'` | `null` and count `23` |
| Anonymous probe | `curl -sf https://api.github.com/repos/jikig-ai/soleur/rules/branches/main \| jq -r '[.[].type]\|join(" ")'` | contains `merge_queue` |
| Queue object | GraphQL `mergeQueue(branch:"main"){id}` | non-null |
| Drift clean | dispatch `scheduled-terraform-drift.yml` | `infra/github` plan: no changes |
| Canary human PR | a trivial docs PR via `gh pr merge --squash --auto` | `mergeQueueEntry` progresses; on the temp ref all 25 contexts (23 + `cla-check` + `cla-evidence`) report; merges; record enqueue-to-merge minutes, the observed `mergeStateStatus`, the entry `state` and `position` values (is `position` 1-based), the candidate squash shape (parents) and that the push SHA equals `merge_group.head_sha` (ADR-269 canary 3) |
| Stall probe schedule gap | `gh run list --workflow merge-queue-stall-check.yml --event schedule` | median gap vs the 15-minute window between the 45-minute threshold and the 60-minute timeout; a wider gap makes the Inngest dispatch cron (Follow-up (a)) the next change (ADR-269 canary 10) |
| Sync pushes per merged PR | count hook and fence sync pushes per merged PR, before and after the queue | recorded; compared to the 1.3 break-even (ADR-269 canary 9, Follow-up (d)) |
| Canary bot PR | next `weakness-miner.yml` bot PR (or its dispatch) | flows through without stalling |
| Gate on a real push | the first `codeql-main-alert-gate.yml` push run | green; elapsed time recorded |
| PRs armed before the apply | `gh pr list --state open --json number,autoMergeRequest --jq '[.[]\|select(.autoMergeRequest!=null)\|.number]'` | each armed PR shows a `mergeQueueEntry` within minutes (or merges); list them in the PR notes |
| Bot-PR enqueue by `GITHUB_TOKEN` | the bot canary above | `merge_group` workflows fire and the entry merges. If a `GITHUB_TOKEN`-armed bot PR sits pending (the sentry workflow already notes `GITHUB_TOKEN`-authored `merge_group` events may lack secrets), the queue stays on for human PRs only if bot PRs fall back to the admin-merge path, and the follow-up to arm bot PRs with an App token is filed in the same session |
| Squash message | inspect the queue-built squash commit | records whether the message came from commits or PR title/body |

When all pass: flip ADR-269 `adopting` -> `accepted`, close #9454 and #4856 with the evidence, leave #5840 open.

### Rollback (single Terraform diff)

Revert exactly these hunks in one PR (the apply workflow enacts it on merge): `infra/github/ruleset-ci-required.tf`
(remove the `merge_queue` block; re-add the `CodeQL` `required_check` with `integration_id = var.codeql_integration_id`),
`scripts/ci-required-ruleset-canonical-required-status-checks.json` (re-add the CodeQL row), `scripts/create-ci-required-ruleset.sh`
(skeleton), and the Guard 2/T-rsc test expectations. Adding a required check and dropping the queue block are both
`0 destroy`; include `[ack-destroy]` anyway. If the queue is stalled, merge the rollback with `gh pr merge --admin`
(admin bypass is retained; `plugins/soleur/scripts/admin-merge-ready.sh` is the readiness gate). The ADR-032 2026-06-30
kill-switch ran in ~4 minutes as a direct `terraform apply`, so it rehearses neither the admin merge nor the PUT. Queue-off, a rollback PR that re-adds `CodeQL` does not go red on Guard 1 or Guard 2 (they skip when no source carries `merge_queue`). The emergency PUT is prose, not rehearsed, and it REPLACES the whole ruleset object (keep `bypass_actors`, `conditions`, target, enforcement and every rule but `merge_queue`). After a rollback, reopen #9454/#4856 and add the observed cause
to the PIR directory.

## Acceptance Criteria

### Functional Requirements

- [ ] `grep -vE '^\s*#' infra/github/ruleset-ci-required.tf | grep -cE 'merge_queue\s*\{'` prints `1`, with `merge_method=SQUASH`, `grouping_strategy=ALLGREEN`, `max_entries_to_merge=1`, `min_entries_to_merge=1`, `min_entries_to_merge_wait_minutes=0`, `max_entries_to_build=2`, `check_response_timeout_minutes=60`.
- [ ] The CI Required canonical JSON, the `.tf`, `required-checks.txt` and the DR skeleton contain no `CodeQL` required check; the other 23 contexts are unchanged (`jq 'length'` = 23).
- [ ] `bash scripts/probe-merge-group-coverage.sh` exits 0 and prints `merge-group-coverage=OK` with >= 25 contexts examined (the probe is offline — no `gh`, no network, no credentials — and runs under `env -i PATH=/usr/local/bin:/usr/bin:/bin` in under 15 seconds, confirming the sandbox's python3 has the YAML module the engine imports (else use a dependency-free parser); the battery in `plugins/soleur/test/required-checks-merge-group-coverage.test.sh` is the suite and is NOT the declared probe); its mutation battery (Guard 1 rows 1-7, H1-H3) is wired into the suite and each row is RED.
- [ ] `merge-queue-cla-synthetics.yml` exists, triggers on `merge_group`, uses `GITHUB_TOKEN`, verifies the PR head's real `cla-check`/`cla-evidence` before posting, and posts both names.
- [ ] `merge-queue-stall-check.yml` exists with `STALL_THRESHOLD_MINUTES: '45'`, a `*/10` cron, the `position <= max_entries_to_build` filter (suite-asserted equal to the `.tf`) and a header stating the 60-minute timeout and the best-effort delivery caveat.
- [ ] `scripts/codeql-main-alert-gate.sh` + `.github/workflows/codeql-main-alert-gate.yml` exist; `bash plugins/soleur/test/codeql-main-alert-gate.test.sh` passes all Guard 3 rows (seeded untracked critical -> exit 1 + one issue; already-tracked alert -> exit 0; API failure -> non-zero; dry run -> no issue).
- [ ] No workflow `needs:`/`workflow_run:`/deploy-arm logic references `codeql-main-alert-gate`: `git grep -n 'codeql-main-alert-gate' .github plugins/soleur/scripts` shows only the workflow, its tests and docs.
- [ ] `sync-pr-behind.sh` skips a queued PR (`--step`: `kind=queued`, exit 11, no merge/push; standalone loop exit 0), reports a seen-queued then dequeued PR as `kind=dequeued` exit 13, and fails non-zero on a GraphQL error after one retry; ship Phase 7 and merge-pr §5.2 text match (`MAX_POLL_MIN` 90).
- [ ] `plugins/soleur/skills/drain-prs/SKILL.md` §4 asserts the queue is active and no longer says "No merge queue on `main`".
- [ ] T-mq-1 is replaced by the Guard 2 gate; `bash tests/scripts/test-audit-ruleset-bypass.sh` passes (23 entries, no CodeQL row).
- [ ] ADR-269 exists with status `adopting`; ADR-032 carries the pointer; `infra/github/README.md` describes the queue as active; the drift-workflow and revisit-watch comments are updated; PA12 and `compliance-posture.md` carry superseded markers.
- [ ] `bash plugins/soleur/test/c4-count-parity.test.sh` passes (12/12) and the three `.c4` files were read in full with the "no C4 impact" citation recorded in the ADR.
- [ ] `python3 scripts/lint-guard-contract.py` (no path arguments — the gate's own invocation, which scans every plan) exits 0.
- [ ] `actionlint` is clean on the three new workflows and `shellcheck` is clean on `scripts/codeql-main-alert-gate.sh` and the restored workflows' embedded shell (not `bash -n` on YAML).
- [ ] Every `gh` call in the new script is time-bounded (`timeout 60 gh …`) and every enumeration bounded (`--limit` / `--paginate`); alert-controlled text (message, file path) never reaches an annotation or issue; only the validated rule id, alert number and severity do (Guard 3 row 10).
- [ ] `plugins/soleur/skills/ship/SKILL.md` stays <= 274000 bytes (`python3 scripts/lint-skill-body-budget.py --base origin/main` passes); the net delta is recorded in the PR.
- [ ] Consumers of the new workflow's RUN are enumerated: `git grep -n -e 'workflow_run' -e 'conclusion' -- .github/workflows plugins/soleur/scripts/deploy-arm.sh` shows nothing that aggregates "every workflow run for a sha" in a way a red gate run would change (a red `codeql-main-alert-gate` must not skip a deploy or red a monitor).
- [ ] `bash scripts/lint-orphan-test-suites.sh` (or the repo's orphan census) reports the two new suites as registered, not orphaned.
- [ ] Squash message carries a line that is exactly `[ack-destroy]`; the PR body's FIRST line states that merging this PR applies `infra/github` to production (removes the `CodeQL` required check, adds `merge_queue`), followed by `Ref #9454`, `Ref #4856`, `Ref #5840` (the canary runs after the apply, so the agent closes #9454 and #4856 with evidence; plan deepen decision).

### Non-Functional Requirements

- [ ] All new workflows: SHA-pinned actions, least-privilege `permissions:`, no `${{ }}` interpolation of event data inside `run:` (env-var routing), `timeout-minutes` set.
- [ ] Every `gh` enumeration in new code is explicitly bounded (`--limit` / `--paginate`), satisfying the #6793 gate in `plugins/soleur/test/components.test.ts`.
- [ ] The `scripts/test-all.sh` orphan-suite linter reports no orphan for the two new suites (they sit under the `plugins/soleur/test/*.test.sh` glob).

### Quality Gates (post-merge, Phase 7)

- [ ] Apply run green; live ruleset probes as in the table; canary human and bot PRs merged through the queue; gate green on a real push; admin bypass verified or documented; ADR-269 flipped to `accepted`; #9454 and #4856 closed with evidence; #5840 still open.

## Test Scenarios

### Acceptance Tests (RED phase targets)

- Given the base branch, when the coverage guard runs, then it fails naming `cla-check` and `cla-evidence` (Phase 0.1) — and passes after Phase 2.
- Given a seeded critical alert with no tracking issue, when the gate runs, then exit 1 and exactly one `sec: CodeQL alert #N` create call.
- Given the queue block in the `.tf` but a different timeout in the DR skeleton, when Guard 2 runs, then it fails.
- Given a queued PR, when `sync-pr-behind.sh <n> --step` runs, then `kind=queued`, exit 11, no push.

### Regression Tests

- `bash tests/scripts/test-audit-ruleset-bypass.sh` (T-rsc-1..9 with 23 entries), `bash tests/scripts/test-destroy-guard-counter.sh`, `bash plugins/soleur/test/required-checks-canonical-parity.test.sh` (canonical filtered to 15368 still equals `required-checks.txt`), `bash plugins/soleur/test/c4-count-parity.test.sh`, `bash plugins/soleur/scripts/admin-merge-ready.test.sh`, `plugins/soleur/test/sync-pr-behind.test.sh`, `apps/web-platform` `cron-ruleset-bypass-audit.test.ts` (fixtures use CodeQL as an arbitrary 57789 member; confirm they still pass or re-point them at a neutral name).

### Edge Cases

- A docs-only push whose CodeQL analyses are skipped or empty: the settled-poll cap and zero-count rule decide RED vs green explicitly (zero `Analyze (*)` runs is RED).
- Concurrent pushes: one pending run per concurrency group; the check is state-based (open alerts vs tracking issues), so a skipped SHA is covered by the next run.
- `ruby` check-run with no analysis: wait on check-runs, never on an analysis count.
- Bot PR through the queue: real CI re-runs on the temp ref; CLA synthetic verifies the bot PR's synthetic CLA check-runs on its head.
- Multi-PR group: not reachable while `max_entries_to_merge = 1`; if it is ever raised, the CLA synthetic must enumerate PRs (add to the raise checklist in the ADR).

### Integration Verification (for `soleur:qa`)

- **Apply verify:** `gh run view <apply-run-id> --json conclusion` -> `success`.
- **Queue verify:** the Phase 7 table.

## Success Metrics

- Median enqueue-to-merge latency for a green PR <= one CI cycle (p50 ~18 min) with zero manual `update-branch` pushes (current: p50 CI cycle plus N BEHIND resyncs).
- Gate: median push-to-verdict <= 10 min; zero false-red runs from the standing backlog.

## Dependencies & Risks

| Risk | Likelihood / impact | Mitigation |
|---|---|---|
| Bot PRs have no `pull_request` CodeQL scan, so the post-merge gate is their only CodeQL coverage | Certain; low impact (bot diffs are limited to `weakness-digest.md`/`rule-metrics.json` by `ALLOWED_PATHS`) | Documented; the gate covers them |
| Gates that were fabricated green for bot PRs (`test`, `e2e`, `grok-fidelity`, `credential-path-guard`, `rule-body-lint`, `marketplace-manifest-guard`) now run for real on `merge_group` (two reach the network: the Grok CLI install and an `mcr` image pull); Guard 1 proves the trigger and `if:`, not that the job body succeeds on `merge_group` | Medium; a flake ejects the PR | Unprovable before the queue is enabled; the first canary enqueue is the empirical test; ADR-269 records that bot-PR `test` is now earned, not fabricated |
| Pass-through gates (`rename-guard`, `allowlist-diff`, `waiver discipline`) trust the pre-queue run on `merge_group`; for bot PRs and bypass actors that run is itself synthetic | Accepted residual (those actors can already merge directly) | Recorded in ADR-269 |
| Merge-to-apply window: the canonical JSON on `main` drops `CodeQL` before the live ruleset does (the safe "added" direction for the audit); a rollback has the reverse order and could page a false "removed" alert; the audit cannot see a removed `merge_queue` rule | Low | Stated in the README; the drift cron's cadence is the detection latency for a removed queue |
| A required context lacks a `merge_group` producer (deadlock redux) | Low after Guard 1; high impact | Guard 1 across both rulesets, CLA synthetic (fails with visible failure contexts), best-effort stall probe at 45 min (schedule delivery degraded), revert in one diff, admin bypass |
| Pre-merge CodeQL blocking is lost (PR-head findings merge) | Certain; medium impact | Post-merge gate about 9-11 min after the push (measured, n=1); nothing in the deploy chain waits for it and an `actions`-language finding is live on `main` for the window (accepted; User-Challenges 1 to 3 in `decision-challenges.md`: required PR-head gate, deploy hold, threshold); daily cron backstop |
| Destroy-guard rejects the apply (missing `[ack-destroy]`) | Medium; low impact (apply fails, nothing changes) | Ack in commit message and PR body; verify in the apply run; follow-up commit path |
| Queue builds exhaust hosted runner concurrency | Medium; medium impact | `max_entries_to_build = 2`, raise only after canary data |
| Queue dequeued by tooling that pushes `update-branch` | High without Phase 4; medium impact | Queue-aware `sync-pr-behind.sh`/poll/hook/monitor, dequeue detection on BEHIND ticks only; canary observes `mergeStateStatus` |
| Flake ejection: 11% of `main` CI runs fail post-merge on PR-green content (11 of 99) and become pre-merge ejections | Medium; medium impact (a full extra cycle per ejection) | Recorded in ADR-269; canary records the candidate failure rate; fix the e2e flake first |
| `merge_group` CI wall-clock exceeds 60 min (runner start spread, ADR-032 2026-09-14: 28-min max spread; three full runs per merged PR on a Team-plan 60-job pool that is an entitlement, not a guarantee) | Medium | Timeout raise is one line; stall probe at 45 min; canary records `merge_group` start spread and wall-clock; `max_entries_to_build` stays 2 until measured |
| Alert gate false-green on API/timing gaps | Medium without Guard 3 | Fail-closed paths, vacuous-green floor, check-run wait |
| Provider/`terraform plan` surprise on the nested block | Low | Phase 0.4 schema probe; destroy-guard counter fixture; plan in the apply run |
| Admin bypass does not skip the queue | Low; medium impact on rollback | Canary the bypass once; the kill-switch also works by letting the queue drain/eject |

## Review-round changes

PR #9455 went through a multi-agent review after this plan was written. The code now differs from the plan text above in the places already edited in line (labels, deadline, CLA failure contexts, queue-awareness, stall filter, Guard additions). The measured facts, the three User-Challenges and the follow-ups are recorded once in `knowledge-base/project/specs/feat-one-shot-9454-merge-queue-advisory-codeql/decision-challenges.md`; the accepted residuals and canary additions in ADR-269. The dated Enhancement Summary above is left as written.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold fails `deepen-plan` Phase 4.6; this one carries all four lines.
- The PIR's root cause was a Phase-0 hard gate treated as prose. Phase 0 here lists commands with expected output; the first (0.1) is an executable guard, not a claim.
- Required-check names are public ABI (ADR-032 job-name contract): renaming any job in Guard 1's assembly un-requires it; the guard resolves producers by exact name.
- `workflow_dispatch` cannot ack the destroy-guard (`HEAD_MSG` is empty on dispatch). A staged "merge first, apply later by dispatch" sequence does not work for a `required_check` removal.
- Do not select ruleset rules by position (`.rules[0]`); select by `.type`. The apply workflow's verify step already does.
- Plan prose and edits under `infra/` are screened by `iac-plan-write-guard.sh`; keep wording to what the apply workflow and the agent do.
- ADR ordinal 269 is provisional and the probe must quantify over every pushed `origin/*` ref, not `origin/main` alone; re-run it immediately before merge and sweep plan/tasks/ACs if it moves.
- `Closes #9454`/`Closes #4856` auto-close at merge, while the canary runs after the apply the merge triggers (the ops-remediation `Ref` rule). Kept as `Closes` per the brief; the agent owns merge-through-canary in the same session and reopens both on rollback. If the canary cannot be run in-session, switch the PR body to `Ref` and close after it passes.
- Appliers of `infra/github`: only `apply-github-infra.yml` applies (it also runs on `workflow_dispatch`, which cannot ack the destroy-guard); `scheduled-terraform-drift.yml` only plans; `scheduled-marketplace-drift.yml` dispatches the same apply workflow. No second apply path reaches the ruleset without the destroy-guard.
- Greps for "absent" claims in this plan were not `head`-truncated; the 23-context audit was produced by parsing every workflow with PyYAML (`on` parses to the boolean key `True`), not by a line grep.

## References & Research

### Internal References

- `infra/github/ruleset-ci-required.tf`, `infra/github/ruleset-cla-required.tf`, `infra/github/README.md` (Merge queue section), `infra/github/variables.tf`
- `.github/workflows/apply-github-infra.yml` (destroy-guard, `[ack-destroy]`, `[skip-github-apply]`), `scheduled-terraform-drift.yml`, `codeql-1537-revisit-watch.yml`, `codeql-to-issues.yml`, `ci.yml`/`pr-quality-guards.yml`/`secret-scan.yml`/`tenant-integration.yml`/`apply-sentry-infra.yml`/`vendor-pin-verify.yml` (merge_group arms)
- Removed workflows: `git show 4439c23c39^:.github/workflows/merge-queue-cla-synthetics.yml`, `…/merge-queue-stall-check.yml`
- `knowledge-base/engineering/architecture/decisions/ADR-032-github-branch-protection-as-iac.md` (2026-06-30/2026-07-01/2026-07-05/2026-07-06 amendments)
- `knowledge-base/engineering/operations/post-mortems/merge-queue-codeql-merge-group-deadlock-postmortem.md`
- `plugins/soleur/scripts/sync-pr-behind.sh`, `plugins/soleur/lib/pr-merge-poll.ts`, `plugins/soleur/skills/{ship,merge-pr,drain-prs}/SKILL.md`
- `scripts/required-checks.txt`, canonical JSONs, `tests/scripts/test-audit-ruleset-bypass.sh`, `apps/web-platform/server/inngest/functions/cron-ruleset-bypass-audit.ts`

### Related Work

- #9454 (this), #4856 (same scope, closed here), #5840 (upstream tracker, stays open), #5780/#5800/#5811 (first adoption and revert), #5842 (removal of PR-1 workflows), #8593 (open scope-out touching `codeql-to-issues.yml`, acknowledged), `github/codeql-action#1537`.
