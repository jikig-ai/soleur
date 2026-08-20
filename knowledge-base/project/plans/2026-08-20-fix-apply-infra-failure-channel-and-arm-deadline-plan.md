---
title: "fix: a RED apply run reaches a channel, and the ARM gate fits inside its job budget"
type: fix
date: 2026-08-20
slug: fix-apply-infra-failure-channel-and-arm-deadline
branch: feat-one-shot-7586-7587-red-apply-no-channel-arm-deadline
issue: 7586
closes: [7586, 7587]
priority: p1
domain: engineering
brand_survival_threshold: aggregate pattern
lane: cross-domain
---

# fix: a RED apply run reaches a channel, and the ARM gate fits inside its job budget

## Overview

Two pre-existing observability defects in `.github/workflows/apply-web-platform-infra.yml`, the
workflow that applies production web-platform infrastructure on every merge to `main`. Neither is a
regression; both were surfaced by the review panel of PR #7568 (merged 2026-08-17T01:25:52Z, which
closed the unrelated #7539) and both were re-verified present on `main` before this worktree existed.

**#7586 (P1)** — a run of this workflow that does not end green reaches no notification channel at
all. Its single `notify-ops-email` arm is gated on a green-**skip** condition, not on failure, and
no other workflow watches this one.

**#7587 (P2)** — the Better Stack heartbeat ARM gate's cumulative per-monitor deadlines exceed the
enclosing job's wall-clock budget. When the job is terminated from outside, the in-script rollback
that re-pauses a monitor never runs, leaving a production uptime heartbeat unpaused with nothing
feeding it — so it pages on absence, while the only signal is a cancelled run rather than a named
failure.

Both live in the same file and share one root cause: **an internal deadline sum larger than its
enclosing budget disarms the failure handler.** One PR is appropriate.

The fix is deliberately small: one new job, one raised job budget, one step-level timeout, one
rollback sweep, and one resized deadline. An earlier draft of this plan carried eight further
mechanisms — a cumulative wall-clock cap, a `budget-exhausted` third outcome, a build-time sum
assertion, a `trap`, burst-suppression state, a green-again email, a channel-failure annotation, and
a second C4 edit. The plan-review panel cut all eight; the reasoning is recorded in the Cut List
rather than discarded.

## Problem Statement / Motivation

### #7586 — the channel

The workflow has exactly one `notify-ops-email` call site, the step
`- name: Notify ops — SSH stage skipped, nothing delivered (#7539)`, gated on:

```yaml
if: ${{ !cancelled() && steps.ssh_token_gate.outputs.ssh_apply_skip == 'true' }}
```

That is a **green-skip** predicate. It fires when the run completed green having delivered nothing.
It cannot fire when the run goes red.

Nothing else covers the gap, verified three ways:

- **No `workflow_run` watcher names this workflow.** The only three in the repo watch
  `"Version Bump and Release"` (`deploy-docs.yml`), `"fix-constraints-stage-a"`
  (`fix-constraints-stage-b.yml`) and `"CI"` (`post-merge-monitor.yml`, which additionally filters
  to `[bot-fix]` commits).
- **This workflow has no `sentry-heartbeat` call site.** The composite has 14 call sites across the
  repo, all in scheduled workflows; this file has none.
- **GitHub's built-in failed-run email routes to the pushing actor**, which `reusable-release.yml`
  already documents in-repo as "frequently a GitHub App identity, i.e. nobody".

The cost of this shape is already on the record for the sibling defect:
`knowledge-base/engineering/operations/post-mortems/web-platform-infra-apply-bridgeless-target-postmortem.md`
records detection as *"by looking at the Actions tab"* after three days of unapplied production
infrastructure. ADR-154's 2026-08-16 amendment states the rule this plan enforces: **a stage with
no channel must not plan over it.**

**Measured (pulled directly, per `hr-no-dashboard-eyeball-pull-data-yourself`):**

```bash
gh run list --workflow=apply-web-platform-infra.yml --branch main --limit 60 \
  --json conclusion --jq '[.[]|.conclusion]|group_by(.)|map({(.[0]):length})'
# → [{"cancelled":1},{"failure":24},{"success":35}]
```

24 red and 1 cancelled of the last 60 `main` runs — none of which notified anyone.

### #7587 — the budget

The ARM gate is the step `- name: Arm web-host probe heartbeats (unpause→verify-status→rollback,
fail-loud)`, inside the `apply` job (`timeout-minutes: 15`). It calls a bash function `arm_one` six
times with per-monitor deadlines derived as `period + grace − 10`:

| Arm | Deadline | Present in merge-path tfstate? |
|---|---|---|
| `web_zot_consumer["web-1"]` | 230 s | yes |
| `web_nic_guard["web-1"]` | 470 s | yes |
| `web_zot_consumer["web-2"]` | 230 s | yes |
| `web_nic_guard["web-2"]` | 470 s | yes |
| `git_data_prd` | 230 s | **no** — measured `not present in tfstate` |
| `inngest_consumer` | 230 s | yes |

Nominal sum **1860 s**; reachable sum on the merge path **1630 s**. Against a 900 s job budget minus
33–62 s of measured job overhead, roughly **838 s** is actually available. The issue's worked case
— three simultaneously-unfed monitors, `470 + 230 + 230 = 930 s` — already exceeds it.

**A finding the issue does not carry.** `arm_one`'s poll loop advances its counter by the sleep
only:

```bash
while (( waited < deadline )); do
  sleep 10
  waited=$(( waited + 10 ))
  status=$(hb_status "$id")   # curl --max-time 15
```

`hb_status` is *inside* the loop and is not counted. A nominal deadline can therefore consume up to
`deadline + (deadline/10) × 15 = deadline × 2.5` of real wall clock. Better Stack currently answers
in ~0.2 s, so today's overhead is +3% (measured: 237 s elapsed for a 230 s nominal deadline); the
exposure is to vendor latency, not to normal operation.

**A second finding the issue does not carry: the 15-minute budget's stated justification is false.**
The in-file comment reads *"15 min is the operator-tolerance ceiling that matches
`apply-deploy-pipeline-fix.yml`."* That sibling workflow has exactly two jobs, and its `apply` job is
**`timeout-minutes: 90`** — six times the cited value. The 15 is therefore not a measured constraint
and not the match it claims to be; it is an unverified paraphrase sitting on `main`. This matters
because the entire "the sum must be truncated to fit" framing rests on treating 900 s as fixed.

**Why the failure mode is bad rather than merely slow.** The rollback
`hb_patch_paused "$id" true` lives on `arm_one`'s in-script terminal branch. There is no step-level
`timeout-minutes` on the gate. On an externally-imposed cut, that line never runs and a heartbeat is
left unpaused-and-unfed — it pages on absence, at whatever hour the grace window expires.

**And it is expensive every single merge.** Measured on run `32356859661` (2026-08-20) from the job
log:

```
10:06:01.2981600Z web-zot-consumer (web-1): already armed (status=up) — no-op.
10:06:01.5246440Z web-nic-guard  (web-1): already armed (status=up) — no-op.
10:06:01.7599874Z web-zot-consumer (web-2): already armed (status=up) — no-op.
10:06:01.9911961Z web-nic-guard  (web-2): already armed (status=up) — no-op.
10:06:01.9980166Z git-data-prd: not present in tfstate — skipping.
10:06:02.2552243Z inngest-consumer (web-1): monitor 482259 is paused; unpausing … deadline=230s
```

The five healthy arms complete in **1.0 s** of wall clock. The step ran **240 s** (10:05:59 →
10:09:59) inside a **302 s** job. So the single `inngest_consumer` arm is **98.8%** of the ARM step
and **78.5%** of the entire apply job — and it cannot succeed by construction while incident #7228
stays open, because its feeder correctly suppresses its ping against a host that has never bound
`:8288`.

## Research Reconciliation — Claims vs. Codebase

| Claim (issue / brief / earlier draft) | Reality (measured) | Plan response |
|---|---|---|
| "8 of last 10 `main` runs were `failure`" | True for the 2026-08-16 window. As of 2026-08-20 the last 10 are 9 `success` + 1 `cancelled`; over 60 runs, 24 `failure`. | The *symptom* cleared; the *gap* did not. The Problem Statement cites the 60-run figure, not the stale 10-run one. |
| Cumulative deadline "1860 s" | Nominal sum 1860 s, but `git_data_prd` is measured **absent** from merge-path tfstate, so the reachable sum is **1630 s**. | Both exceed the 838 s currently available. Plan states both. |
| "~23-38 min/day of runner time" | Measured merge rate 45 push runs over 16.59 days = **2.71/day**; × 237 s = **643 s/day ≈ 10.7 min/day** (≈ 5.4 h/month). Over-estimate by 2-3.5×. | Plan uses the measured figure. Repo is **public**, so runner minutes are free: the saving is wall-clock and fleet-mutex hold, **not dollars**. |
| PR "merged 2026-08-16" | PR #7568 merged **2026-08-17T01:25:52Z**; it closed #7539 (a different issue, as stated). | Provenance corrected in the Overview. |
| Issue proposes `if: ${{ failure() }}` sibling arm | A job that exceeds `timeout-minutes` concludes **`cancelled`**, not `failure`, and `failure()`-gated steps are **skipped**. | Structurally silent on exactly the #7587 path. Replaced — Cut List **C1**. |
| Brief proposes `brand_survival_threshold: single-user incident` | The post-mortem on **this exact workflow and defect class** declares `aggregate pattern`, rationale *"the harm is fleet-wide configuration drift and a blinded detection channel, not a named user's incident."* | Downgraded. Declaring a higher threshold for the *fix* than the *incident* is incoherent. Give-back: `user-impact-reviewer` retained at review time. |
| In-file comment: `timeout-minutes: 15` "matches `apply-deploy-pipeline-fix.yml`" | **False.** That workflow's `apply` job is `timeout-minutes: 90`. | The 15 is an unverified paraphrase, not a constraint. Raised to 30 and the comment corrected in the same edit. |
| Earlier draft's Cut List **C4**: a new test suite "would require the six-site registration protocol and risks tripping `lint-orphan-test-suites.sh`" | **False.** `scripts/test-all.sh:1427` runs `run_suite "plugins/soleur" bun test plugins/soleur/` — directory recursion, so a new `.test.ts` is auto-discovered. `scripts/lint-orphan-test-suites.sh:96` enumerates `git ls-files '*.test.sh'` and cannot see a `.test.ts`. | C4's *conclusion* stands but its *justification* is replaced: co-location with the `#7539` guard and its shared `extractJobBlock` / `extractStep` helpers. A false cost claim is not left standing in a plan others will cite. |
| Earlier draft: the separate job "reports when the apply job produced no steps at all" | True for a **job** timeout (measured). **False for run-level cancellation** — a manual cancel or a concurrency supersede cancels queued jobs too, so an `always()` job never starts. | The new arm shrinks the gap from 25/60 to ~1/60; it does not close it. Stated as a named residual, not as closure. |
| Earlier draft: "the ARM step already uses `set -uo pipefail` (no `-e`) and is ADR-170-compliant" | **Inverted.** ADR-170 §Context: GitHub invokes a `run:` step declaring no `shell:` key as `/usr/bin/bash -e {0}`, and *"`set -uo pipefail` only adds flags — it cannot clear one."* Errexit is **on** in that step today; it survives only because every `arm_one` call sits behind `\|\| rc=1`. | Corrected throughout. The reworked step and the new sweep must clear errexit explicitly — this is the single most consequential correction the panel made, because a `rollback_all` under errexit aborts at its **first** failing PATCH and silently truncates the sweep. |
| Earlier draft: the `model.c4` "thirteen Resend emitters" numeral is "verified still correct" | **Not verified — the arithmetic double-counted.** 11 workflow files call the composite and 2 carry an inline `api.resend.com` curl, but `web-platform-release.yml` appears in **both**, so the distinct-file count is **12**, not 13. | The claim is withdrawn. C10 still declines the edit, but on the honest ground that the numeral's referent (files vs call sites) is ambiguous and reconciling it is unrelated debt — not on a verification that did not hold. |
| Earlier draft: "all 14 workflow `run:` traps use bare `EXIT`" | `.github/workflows/*.yml` carries **8** trap lines, one of which is `ERR`. | Figure corrected in Cut List C6. The conclusion (a bare `EXIT` trap does not fire on SIGTERM) is unaffected, and the trap is cut regardless. |
| Earlier draft: "roughly 838 s is available" to the ARM gate | Derived from run `32356859661`, where the ARM step was 240 s of a 302 s job — a **no-op** apply. The ARM gate is step 16 of 18, *after* two `terraform apply` steps, so a non-trivial apply consumes budget before the gate starts. | The raised job budget is sized to absorb a real apply **plus** a full arming pass, not just the modal no-op. See Proposed Solution §2. |
| ADR-117 amendment property 1 | Claims the arm step runs "only when the monitor is live-`paused==true` **OR** its feeder was replaced this apply (`triggers_replace`)". The shipped `arm_one` implements **only** the live-paused gate. | Pre-existing doc/code divergence. Recorded here as an observation; **not** folded into this PR's ADR amendment (it is unrelated debt). |

## Hypotheses

Phase 1.4's network-outage gate fired on the literal token `timeout` in the brief. The trigger is a
true positive in form and a near-miss in substance — the "timeout" here is a GitHub Actions
wall-clock budget, not a network stall — but the ARM gate does make HTTPS calls to a third-party API
from a hosted runner, so the L3→L7 layers are answered rather than waived. One artifact settles all
four: run `32356859661`'s job log.

1. **L3 — firewall allow-list.** Not applicable. The gate runs on a GitHub-hosted runner reaching
   `uptime.betterstack.com` over the public internet; no `hcloud_firewall` and no egress allow-list
   entry sits on that path.
2. **L3 — DNS / routing.** Verified: five successive `GET /heartbeats/<id>` round-trips completed
   between 10:06:01.298 and 10:06:02.255 — **~0.24 s each**. A resolver or route fault would have
   produced `--max-time 15` stalls; the timestamps exclude it.
3. **L7 — TLS / proxy.** Verified by the same artifact: each call returned a parsed `status` value
   (`up`), so the chain terminated at the real API with a valid body. `curl -fsS` would have failed
   on any intermediary error.
4. **L7 — application layer.** Verified: the only arm that does not complete is `inngest_consumer`,
   and the log names the cause — `monitor 482259 is paused; unpausing and watching for a real beat`.
   The absence is on the **feeder** side (#7228's surface), not the API path.

**Conclusion:** the 237 s is not a network fault at any layer. It is the gate doing exactly what it
was written to do against a monitor whose feeder is knowingly dark, which rules out the entire
network-hypothesis tree and leaves the deadline arithmetic as the sole cause.

## Research Insights

### Premise Validation (Phase 0.6)

All three cited issues verified via `gh issue view`: **#7586 OPEN** (p1-high), **#7587 OPEN**
(p2-medium), **#7228 OPEN** (p1-high, `type/bug`, `follow-through`). Neither work target is already
closed by a merged PR. #7228 is a live incident and **not** a work target. Provenance PR **#7568
MERGED** 2026-08-17, `closes: [7539]`. Every cited file path and line region confirmed present:
the notify arm at `:1001-1029`, the ARM gate at `:1054-1185`, `hb_patch_paused "$id" true` at
`:1137`, `timeout-minutes: 15` at `:350`, workflow-level
`concurrency: { group: terraform-apply-web-platform-host, cancel-in-progress: false }` at `:273-288`.

**ADR corpus grep for the proposed mechanisms** (Phase 0.6 item 4): ADR-117 governs this gate. Its
`## Alternatives Considered` holds five rejected options — unpause-now, keep-arming-as-prose,
forward-only-grep, nightly-reconcile-instead-of-static-guard, widen-`period`/`grace`. **Neither a
job-budget raise nor a per-arm deadline resize appears among them**, so no mechanism here is an
ADR-rejected alternative. ADR-100's 2026-08-12 addendum records that #7228 **cannot close until the
#7462 host restore lands** (#7462 verified OPEN) — decisive input for Cut List C2.

### Property List (Phase 0.6b)

| # | Property (observable outcome) |
|---|---|
| P1 | A run of this workflow on `main` that does not end green delivers a notification to a channel a non-technical recipient reads. |
| P2 | That notification covers the **cancelled / timed-out** outcome, not only the named-failure outcome. |
| P3 | The notification names, in plain language, what did not land, plus one copy-pasteable recovery command. |
| P4 | The ARM gate cannot consume more wall clock than the enclosing job can give it. |
| P5 | No path through the ARM gate leaves a Better Stack heartbeat unpaused with nothing feeding it. |
| P6 | The everyday cost of the ARM gate is proportional to the work it actually does. |
| P7 | Nothing added here can silently outlive the incident that justified it. |

### Cut List (Phase 0.6b + plan-review) — mechanisms removed before they were built

| Cut | Mechanism | Property it was meant to buy | Why it is cut |
|---|---|---|---|
| **C1** | The issue's step-level `if: ${{ failure() }}` sibling arm | P1 (partially) | Does **not** buy P2. Measured on run `32168637847`: a job exceeding `timeout-minutes` concludes `cancelled`, its `failure()`-gated step was `skipped`, and both `always()` steps ran to `success`. It also collides with the `#7539` guard, whose `extractStep` takes the **first** `/Notify ops/` step in the `apply` job. Replaced by a separate job. |
| **C2** | A self-expiring / `gh issue view 7228`-reading short-circuit of the `inngest_consumer` arm | P6, and P7 only by adding machinery | A **deadline resize** buys P6 *and* preserves the self-clearing property a short-circuit destroys (`arm_one` returns 0 via `already armed (status=…)` once the feeder is live). No `issues: read` widening on the job holding production secrets and the fleet mutex; no follow-through script; no expiry mechanism — so it buys P7 for free, because nothing is left to outlive. ADR-100's addendum makes the suppression long-lived (#7228 blocks on #7462), exactly the regime where expiry mechanisms rot (ADR-185's recorded anti-pattern). |
| **C3** | A cumulative wall-clock cap (~700 s) across `arm_one` calls | P4 | The cap exists only because 900 s is treated as fixed. It is not — the 15-minute budget's sole stated justification is **false** (it claims to match a sibling that is 90). Raising the budget to 30 lets every arm finish instead of truncating the sum and leaving monitors unmeasured. The cap's endgame was "some monitors are skipped", which improves nothing and adds a state machine. |
| **C4** | A `budget-exhausted` third outcome | P4 | Existed only to serve C3. With no cap there is nothing to report. Its one defensible form — a failing exit consumed by the notify job's cause enum — is moot once no arm is ever skipped. |
| **C5** | A build-time assertion that `sum(deadlines) > budget ⇒ a cap exists below budget` | P4 | A conditional whose antecedent is a constant under our control. With the budget raised the antecedent is false, and the direct assertion (`sum(deadlines) < job budget − overhead`) is simpler and is what the guard now checks. |
| **C6** | `trap 'rollback_all' EXIT INT TERM` inside the ARM step | P5 | **Bought by the `if: always()` sweep.** Any signal that kills the step leaves the job alive, so the sweep runs; a job-level cancellation runs it in the measured grace window. The trap's marginal value is a few seconds inside a 240 s absence window. Deleting it removes three hazards the panel identified: bash keeps only the last `EXIT` handler; after an `INT`/`TERM` handler returns bash *resumes* rather than exiting, so the `EXIT` trap then fires too and double-PATCHes; and bash defers the handler until the foreground `sleep 10` returns. It also makes the state file + sweep honestly **one** mechanism with **one** entry point — the earlier draft's "one mechanism, two entry points" framing did not survive scrutiny, since a trap needs no state file at all and bash functions do not cross step boundaries. *(An earlier draft cited "all 14 workflow `run:` traps use bare `EXIT`"; the measured figure is **8** trap lines in `.github/workflows/*.yml`, one of them `ERR`. The conclusion — a bare `EXIT` trap does not fire on SIGTERM — is unaffected.)* |
| **C7** | Burst suppression by failing-step identity, with backoff | none of P1-P7 — **anti-P1** | P1 says a non-green run *delivers* a notification; this withholds them. It requires cross-run state on a substrate that has none (a `gh api` jobs walk plus persisted timestamps), is racy under `cancel-in-progress: false`, and sits between a red run and the only email that exists — so its first bug is *the suppressor ate the alert*, the very defect being fixed, one layer up. Deferred, where it belongs to the catch-all rather than being the 25th hand-rolled copy. |
| **C8** | The green-again ("recovery") email | none | **Self-contradictory:** it requires the notify job to run on green, which the predicate, Test Scenario 3 and Guard 1's mutation row 1 all forbid. Deferred with C7. |
| **C9** | A post-step emitting `::error::` when `steps.email.outcome != 'success'` | "the channel itself failed" | **Dead by construction.** `notify-ops-email/action.yml` exits 0 with a `::warning::` on a non-2xx, so `outcome` reads `success`; it exits non-zero only on a missing key, and on that path it **already** emits `::error::` itself. The step could only ever duplicate an annotation that exists. The residual is recorded honestly in `failure_modes` instead. |
| **C10** | Editing the `github -> resend` C4 edge description | none | Still cut, but the earlier justification is **withdrawn**: it claimed the "thirteen Resend emitters" numeral was verified correct via `11 composite callers + 2 inline curl = 13`, and that arithmetic double-counts `web-platform-release.yml`, which appears in **both** sets — the distinct-file count is **12**. Whether the model's "thirteen" counts files or call sites (21 composite call sites + 2 inline) is genuinely ambiguous, and reconciling it is unrelated debt this PR did not create. The honest disposition is "ambiguous referent, out of scope", not "verified correct". |
| **C11** | A standalone new test-suite file | — | *Conclusion retained, justification replaced.* The earlier justification (six-site registration, orphan-lint risk) is **false** — verified above. The real reason is co-location: `terraform-target-parity.test.ts` already owns this workflow's channel guard and its `extractJobBlock` / `extractStep` helpers, so a sibling `describe` reuses both. The genuine cost — a 24th `describe` in a suite whose name already lies about its contents — is paid down by the header note and a pointer comment from the workflow itself, not by a new file. |

### Value-Proposition Measurement (Phase 0.6c)

| Quantity | Value | Command that produced it |
|---|---|---|
| ARM step share of the apply job | 240 s of 302 s = **79.5%** | `gh api repos/:owner/:repo/actions/runs/32356859661/jobs` |
| `inngest_consumer` share of the ARM step | ~237 s of 240 s = **98.8%** | job-log timestamps, quoted above |
| Merge-apply rate | **2.71/day** (45 push runs, 2026-08-03 → 2026-08-20) | `gh run list --workflow=apply-web-platform-infra.yml --branch main --limit 60 --json createdAt,event` |
| Wall clock + fleet-mutex hold reclaimed | **643 s/day ≈ 10.7 min/day ≈ 5.4 h/month** | 2.71 × 237 s |
| Dollar saving | **$0** — repo is public, runner minutes free | `gh repo view --json isPrivate,visibility` → `PUBLIC` |
| Better Stack API calls removed per merge | **~26** | `arm_one`'s loop at `deadline/10` iterations |

### Applicable institutional learnings

- `knowledge-base/project/learnings/best-practices/2026-05-05-workflow-jwt-mint-silent-failure-traps.md`
  **Trap 3** — `if: failure()` does not fire when the previous step carries `continue-on-error: true`,
  because `failure()` reads the **job's** outcome. Its worked example uses `notify-ops-email`.
- `knowledge-base/project/learnings/2026-07-30-the-guard-i-wrote-for-the-failure-path-could-not-run-on-the-failure-path.md`
  — a step `if:` with no status-check function is implicitly ANDed with `success()`.
- `knowledge-base/project/learnings/workflow-patterns/2026-08-01-alert-step-and-its-fallback-died-together-guard-fallbacks-with-not-cancelled.md`
  (#7136) — any step existing to catch another's failure needs `always()`; the fallback's own crash
  path must be considered.
- `knowledge-base/project/plans/2026-08-03-feat-luks-verify-scheduled-with-alarm-plan.md` §617-622 —
  corrected at review to **`always()`, not `!cancelled()`** for an alarm.
- `knowledge-base/project/learnings/best-practices/2026-06-30-adaptive-ci-poll-gate-wall-clock-ceiling-not-attempt-count.md`
  (#5795) — an in-script bound must be wall-clock, not attempt count; a budget counting only its
  sleeps is out-raced by its own API round-trips. This is the defect `arm_one` carries today, and it
  is fixed independently of any cap.
- `knowledge-base/project/learnings/best-practices/2026-07-18-deploy-script-tests-at-budget-timeout-and-infra-pr-ci-gotchas.md`
  — an at-budget job cancels wherever execution happens to be; the cancel location is a red herring.
- `knowledge-base/project/learnings/2026-08-14-my-gate-reserved-its-reassuring-message-for-its-alarming-condition.md`
  (#7542/PR #7543) — a gate **in this same workflow** whose success branch the real producer could
  never reach, because its fixture modelled *absence of a change* rather than *an unchanged
  resource*, with 19 green assertions over it. Binding on the test design: model the steady state.
- `knowledge-base/engineering/architecture/decisions/ADR-170-workflow-run-step-must-clear-inherited-errexit.md`
  — **load-bearing here, and this plan's first draft got it backwards.** GitHub invokes a `run:`
  step declaring no `shell:` key as `/usr/bin/bash -e {0}`, and *"`set -uo pipefail` only adds flags
  — it cannot clear one."* So errexit **is on** inside the ARM step today; it survives only because
  every `arm_one` call sits behind `|| rc=1`. Any rework must clear it explicitly. Enforced by
  `scripts/lint-workflow-errexit-capture.py`.
- `knowledge-base/project/learnings/2026-07-15-silent-fallback-masked-a-dead-primary-for-14-days.md`
  — never trust a `continue-on-error` step's green conclusion; read `outcome`, not `conclusion`.
  Why C9 was examined at all, and why the residual is recorded rather than papered over.

### Repo conventions and guards that bind this change

- **`plugins/soleur/test/terraform-target-parity.test.ts`** — 23 `describe` blocks, 3,345 lines; an
  orphan by name. It pins the `#7539` notify arm (its `if:` line must contain `!cancelled()` and not
  `always()`), asserts `jobs.length >= 15` (a **floor**; currently 18, so adding a job is safe), and
  owns Guard 1 (bridge-less stage may not target an SSH-provisioned resource).
- **`apps/web-platform/infra/web-1-swap-concurrency-parity.test.sh`** — the orphan to watch. Asserts
  an **exact** count (`web1_count -eq 8`) of `group: web-1-swap` occurrences plus a named
  allow-list, and a negative assertion that the routine `apply` job is not a member. A new job is
  safe **only if** it declares no `group: web-1-swap`.
- **`tests/scripts/test-vector-redeliver-wiring.sh:168`** — asserts `timeout-minutes: 15`, but
  scoped to `JOB_BODY="$(_job_body 'vector_redeliver')"` (`:95`), **not** the `apply` job. Raising
  `apply`'s budget does not break it. Named because a grep for `timeout-minutes: 15` finds it and it
  reads like a blocker.
- **`plugins/soleur/test/stock-preflight-coverage.test.ts`** — maps every `apply_target` option to
  exactly one *applying* job. A notify job with no `apply_target` guard and no `terraform apply` is
  invisible to it. Safe.
- **`tests/scripts/test-preapply-entrypoint-gate.sh`** check `W4` — asserts step **order by line
  number** between `Terraform plan (allow-list`, `Pre-apply entrypoint gate` and
  `^      - name: Terraform apply$`. All edits land after the main apply, so ordering is untouched —
  but it must be re-run.
- **In-file precedent for a raised budget.** Two mutex-holding jobs in this same file use
  `timeout-minutes: 30`, each documenting the pattern this plan adopts: *"`timeout-minutes: 30` is
  load-bearing: this job holds that fleet-wide apply mutex, so GitHub's 360-minute default would let
  a hung poll block EVERY merge-apply for six hours. The D11 poller's own bound … is strictly below
  it so its diagnostic wins over an [anonymous cancellation]."* A job ceiling above, an in-script
  bound strictly below — exactly the ladder this plan builds.
- **`.github/actions/notify-ops-email/action.yml`** — inputs are exactly `subject`, `body`,
  `resend-api-key`; recipient hard-coded `ops@jikigai.com`. **Fails hard** on a missing key
  (`::error::` + `exit 1`) and **fails soft** on a Resend error (`::warning::`, exit 0). Six callers
  wrap it in `continue-on-error: true`; `apply-web-platform-infra.yml:1005` does not.
- **`registry-host-replace-dispatch.yml`** step `- name: Record a refused delivery on the tracker` —
  the repo's only cancellation-aware arm, `if: always() && job.status != 'success'` with a body
  branching on `JOB_STATUS == "cancelled"`. The canonical in-repo shape for P2.
- **`BS_TOKEN` is minted *inside* the ARM step** (`doppler secrets get BETTERSTACK_API_TOKEN --plain
  --token "$DOPPLER_TOKEN_WEB_ARM"`). A sibling step cannot see it — the sweep must re-mint. Named
  because an unnamed re-mint makes the sweep decorative.
- **Nothing asserts on the ARM gate at all.** `git grep` for `arm_one` / `hb_patch_paused` across
  the test trees returns only two unrelated comments. The gate is untested; Guard 2 is built from
  the design, not from the code as it happens to be shaped.

## Proposed Solution

Four changes to one workflow, one guard extension, and one record correction.

### 1. A separate `notify-apply-failure` job (#7586 → P1, P2, P3)

Mirror `infra-validation.yml`'s `notify-main-failure` (#7299) — **but not its predicate**. That job
gates on `needs.X.result == 'failure'`, which is silent on the cancelled path and would reproduce
#7587's blind spot one layer up.

```yaml
notify-apply-failure:
  needs: [preflight, apply]
  # NOT `event_name == 'push'`: `apply` also runs on the manual-rerun dispatch (`:344`), which is
  # the exact recovery command this job's own email prescribes. Gating on push would leave the
  # retry with no channel.
  # NOT `needs.apply.result != 'success'` alone: a failed `preflight` leaves `apply` *skipped*,
  # which that predicate reads as fine while the run is red.
  if: >-
    always() &&
    (github.event_name == 'push' || inputs.apply_target == 'manual-rerun') &&
    !(needs.preflight.result == 'success' &&
      (needs.apply.result == 'success' || needs.apply.result == 'skipped'))
  runs-on: ubuntu-24.04
  timeout-minutes: 5          # bounds the fleet-mutex hold; GitHub's default is 360 min
  permissions:
    contents: read
    actions: read             # to read the failing step's name from the jobs API
  steps:
    - uses: actions/checkout@<pinned-sha>
    # Every step below carries a `name:` — the guard suite's `extractStep` helper matches on
    # `^ {6}- name:`, so an unnamed step is invisible to it and the ACs below could not assert
    # anything about it.
    - name: Resolve the failing step from the jobs API
      id: cause
      run: …                  # gh api …/runs/${{ github.run_id }}/jobs -> sanitized token
    - name: Email ops on a non-green apply run
      continue-on-error: true # a Resend outage must not red an already-red run
      uses: ./.github/actions/notify-ops-email
      with: { subject: …, body: …, resend-api-key: ${{ secrets.RESEND_API_KEY }} }
```

Two defects the panel found in the first draft of this predicate, both fixed above:

- **The manual-rerun path had no channel.** `apply` runs on `push` **or**
  `inputs.apply_target == 'manual-rerun'` (`:344`). A `push`-only gate would mean the recovery the
  email itself prescribes is the one run nobody is told about.
- **A failed `preflight` was invisible.** `apply` declares `needs: preflight`, so a `preflight`
  failure leaves `apply` **skipped** — which `needs.apply.result != 'skipped'` reads as fine while
  the run is red. `preflight` is in `needs:` precisely so the predicate can see it; the negated form
  above ("not everything is fine") uses it. This is Guard 1's mutation row 3 catching the plan's own
  first draft.

Why a separate **job** rather than the sibling step the issue proposes:

- **It covers the cancelled outcome.** `needs.apply.result` is `cancelled` when the apply job hits
  `timeout-minutes`.
- **It does not depend on the cancellation grace window.** Measured (run `32168637847`) that
  `always()` steps do run after a job timeout — but the window's **length** is undocumented. A
  downstream job reads `needs.apply.result` regardless.
- **It does not touch the `#7539` guard.** `extractStep(applyJob, /Notify ops/)` takes the first
  match inside the `apply` job; a second such step there would couple the new arm to that guard by
  source ordering. A separate job is outside `extractJobBlock(wf, "apply")` entirely.
- **Mutex cost is not material.** On a green run the job is `skipped` — no runner allocated. On a
  red run it adds ~20-45 s to a run whose successor merge is already blocked, bounded by
  `timeout-minutes: 5`.

**A residual this does NOT close, stated rather than glossed.** A **run-level** cancellation — a
manual cancel, or a concurrency supersede — cancels queued jobs too, so an `always()` job never
starts. The only mechanism covering that path is a `workflow_run` watcher, which does not exist for
this workflow (see Deferrals). Measured: 1 of the last 60 runs was `cancelled`. So this arm takes
the un-notified share from 25/60 to roughly 1/60. It shrinks the gap; it does not close it.

**Email content (P3).** The bar is this file's own `#7539` arm: it states blast radius in a
sentence, gives a **three-literal cause enum with per-value guidance** (`absent` / `empty` /
`unreadable`, each saying what it means for the reader), enumerates what did NOT land by class, and
carries a fenced copy-pasteable `gh workflow run …`. The new body must carry all of that plus four
elements the first draft omitted:

1. **The failing step's name** — `needs.apply.result` is a token, not a cause. Resolved with one
   `gh api …/jobs` call under `actions: read`. Without it the reader's only handle is "something
   failed".
2. **Per-outcome guidance** — `cancelled` usually means a re-dispatch is enough; `failure` means
   read the run first, because a re-dispatch will likely fail the same way.
3. **The heartbeat state** — on a cancelled apply mid-ARM-gate the sweep may have re-paused
   monitors, so production uptime alerting may be paused. That is the 03:00-page risk ranked first
   in the Engineering review, and it appeared in no email line.
4. **"Is anything down right now?"** — the previously applied state is still serving. Without this a
   non-technical reader assumes an outage.

**Interpolation allow-list.** The body interpolates only workflow-context scalars (`github.sha`,
`github.run_id`, `github.repository`, `github.server_url`, `needs.apply.result`) plus the
shape-validated token produced by **this job's own** `cause` step. Never raw step logs, `curl`
output or a shell trace: the ARM gate reads `BETTERSTACK_API_TOKEN` and handles monitor ids, and
terraform error strings carry resource identifiers and Doppler variable names. The destination is a
plaintext, no-expiry mailbox behind a third-party processor.

**Where the cause token may NOT come from.** The `apply` job declares **no `outputs:`** — only the
jobs at `:310`, `:2078` and `:2528` do — so a downstream job cannot read
`steps.ssh_token_gate.outputs.*` or any other `apply` step output, and on the `cancelled` path (the
path this job exists for) job outputs would be unreliable even if they existed. The `cause` step
therefore derives everything it needs from the **jobs API** under `actions: read`
(`gh api repos/:owner/:repo/actions/runs/${{ github.run_id }}/jobs`), reducing the failing step's
name to a sanitized token before it reaches the body. Adding `outputs:` to `apply` to carry a cause
is explicitly *not* the design.

### 2. Raise the job budget so the work fits (#7587 → P4)

Raise `apply`'s `timeout-minutes` from **15 to 30**, and correct the false comparator comment in the
same edit.

The 15 was never a measured constraint — its only recorded justification claims to match
`apply-deploy-pipeline-fix.yml`, whose `apply` job is **90**. The in-file precedent for a
mutex-holding job is **30**, documented twice with the exact ladder this needs: a job ceiling above,
an in-script bound "deliberately strictly below it so its diagnostic wins over an anonymous
cancellation".

After the §4 resize the reachable sum is `230 + 470 + 230 + 470 + 30 = 1430 s` (1660 s if
`git_data_prd` enters state), and **every monitor still gets measured** — which is what a truncating
cap could not offer.

**Sizing against a real apply, not the modal no-op.** The 838 s figure in the Problem Statement is
derived from run `32356859661`, where the ARM step was 240 s of a 302 s job — an apply that changed
nothing. The ARM gate is **step 16 of 18**, running *after* two `terraform apply` steps, so on a
substantive merge the apply itself consumes budget before the gate starts. The worst case that
matters is the one Kieran's review surfaced: a **web-host birth**, where this gate is the *only*
unpause path for four born-paused monitors (`:3807`, `:4159`) and the arming pass alone is
`230 + 470 + 230 + 470 = 1400 s`. At 30 min the job has `1800 − 62 = 1738 s`, leaving ~338 s for the
apply that precedes it — adequate for the measured 3-5 min typical apply, and the case where it is
not adequate is a cold-cache provisioning run that the step-level timeout will surface as a named
step failure rather than an anonymous cancellation. Raising further is available if a real birth run
measures otherwise; the point of the ladder is that the gate now fails *with a name*.

### 3. A rollback that survives cancellation (#7587 → P5)

- **One state file, one sweep.** `arm_one` appends `<id>` to `$RUNNER_TEMP/armed-unconfirmed`
  immediately after a successful `PATCH {paused:false}`. A sibling step
  `- name: Re-pause any monitor left unconfirmed`, gated `if: always()`, re-PATCHes `paused:true`
  for every id still listed. `$RUNNER_TEMP` persists across steps within a job, and the sweep is in
  the same job.
- **An id is removed from the file only when its `PATCH` actually succeeded.** Removing on
  "rollback attempted" drops a *failed* rollback's id, so the sweep — the last chance to re-pause
  it — never retries the exact monitor the in-step `::error::` is warning about. Removal is
  conditional on the PATCH returning 2xx, which also makes `rollback_all` idempotent: the trap-free
  design has one caller, but the sweep may still run after the step already cleared some ids, and
  re-PATCHing `paused:true` on an already-paused monitor is a no-op.
- **The sweep needs its own credential, and that has to be wired.** `BS_TOKEN` is derived *inside*
  the ARM step from `doppler secrets get BETTERSTACK_API_TOKEN --plain --token
  "$DOPPLER_TOKEN_WEB_ARM"`, so a sibling step sees neither. The sweep step therefore declares
  `env: { DOPPLER_TOKEN_WEB_ARM: ${{ secrets.DOPPLER_TOKEN_WEB_ARM }} }`, repeats the mint, and
  emits `printf '::add-mask::%s\n'` on the result exactly as the ARM step does. Without that `env:`
  block the sweep is decorative — it would run, find ids, and be unable to PATCH any of them. Its
  residual failure mode (inert precisely when the mint is what broke) is recorded in
  `failure_modes`, and it emits `::error::` on that path rather than exiting quietly.
- **Fix the wall-clock accounting.** `arm_one`'s loop counter must advance by measured elapsed time,
  not by its `sleep` alone, so a slow vendor cannot make a 230 s deadline consume 575 s. This is
  needed regardless of any cap and is the #5795 defect class.
- **A step-level `timeout-minutes` on the ARM gate**, sized strictly below the job budget, so the
  gate fails *inside* the job — where the sweep and the post-apply summary still run — rather than
  being cancelled with it. This is the P4 mechanism at the step level and the lower rung of the
  documented ladder.

No `trap`: any signal that kills the step leaves the job alive so the sweep runs, and a job-level
cancellation runs it in the measured grace window (Cut List C6).

### 4. Resize the `inngest_consumer` deadline (#7587 → P6, P7)

Change that one arm's deadline from **230 s to ~30 s**:

- Measured healthy arms return in ≤ 1.0 s, so 30 s costs nothing on the happy path.
- It reclaims ~200 s of the ~237 s burned on **every** merge apply.
- It **preserves self-clearing with no expiry mechanism**. Once the feeder is live, each apply has
  roughly a 1-in-6 chance of catching a beat; at 2.71 applies/day the monitor arms within a few days
  on its own, and `already armed (status=…)` makes every later apply a true no-op.
- The unpause window stays far below the monitor's first absence alert (`period + grace` = 240 s),
  so no false page is possible during a failed attempt.
- **The cost, owned explicitly:** after #7228 heals there is an expected ~2-day window in which the
  monitor is still paused. It was *already* paused every day of the incident, so this is not a new
  dark state — but the window is real and is named here rather than left for a reader to derive.

The existing `arc == 2` soft-landing branch and its `::warning::` are retained.

## Technical Considerations

- **Architecture impact.** No new substrate, vendor, secret, host or Terraform resource.
  `RESEND_API_KEY` is an existing repo secret already referenced at `:1008`; a new job in the same
  (non-reusable) workflow inherits it with no `secrets:` plumbing. `actions: read` is a job-level
  grant on the notify job only — the file already uses job-level `permissions:` blocks
  (`entrypoint_audit` at `:5857`), and a job-level block **replaces** the workflow-level one, so
  `contents: read` must be re-declared alongside it.
- **Gates assessed and skipped, with reasons:**
  - *Phase 2.7 GDPR* — **skip**. No schema, migration, auth flow, API route or `.sql` touched; none
    of the four expansion triggers fire (and with the threshold at `aggregate pattern`, trigger (b)
    does not either). Resend is an existing processor on an existing modelled edge. The
    interpolation allow-list is the data-minimisation control.
  - *Phase 2.8 IaC routing* — **skip**. No server, systemd unit, cron job, vendor account, DNS
    record, TLS cert, secret or firewall rule introduced; the change is confined to an
    already-provisioned surface, so no `## Infrastructure (IaC)` section is required.
  - *Phase 2.11 Encryption posture* — **skip**. No persistent store; no new cross-component
    connection. GitHub Actions → Resend and → Better Stack both already exist in this file; the
    change adds call sites, not connections.
- **Vendor expense** (`wg-record-recurring-vendor-expense-before-ready`): **no ledger edit required,
  explicit disposition.** Resend is `Pro, $20/mo, 50,000 emails/mo`
  (`knowledge-base/operations/expenses.md:49`); projected volume ~45/month = **0.09%** of quota.
  Better Stack call volume **decreases** by ~26/merge. Runner minutes are free (public repo). The
  ship-time grep will still match `secrets.RESEND_API_KEY`; this is that hit's written disposition.
  Two stale ledger rows (Resend `verify_by=2026-08-16`, Better Stack tier unknown) are **out of
  scope** and left to `ops-advisor`.
- **`bash -e` and errexit — corrected at review, and consequential.** The ARM step is **not**
  errexit-free: GitHub runs it as `/usr/bin/bash -e {0}` and `set -uo pipefail` cannot clear that.
  It survives today only because every `arm_one` call sits behind `|| rc=1`. Three concrete
  requirements follow, and skipping any of them produces a sweep that silently does less than it
  reports: (a) the reworked step and the new sweep declare `set +e` explicitly; (b) **every**
  rollback `PATCH` carries `|| true`, because `curl -fsS` returns non-zero on a 5xx and an
  unguarded `rollback_all` would abort at the *first* failure and leave the remaining monitors
  unpaused-and-unfed — the exact condition the sweep exists to clear; (c) no bare `(( … ))`, which
  exits non-zero when the expression evaluates to 0. `scripts/lint-workflow-errexit-capture.py` is
  the enforcing gate.
- **NFR impacts.** Reduces apply-job wall clock ~79% on the modal merge and fleet-mutex hold by the
  same amount. Raises the *worst-case* mutex ceiling from 15 to 30 min — accepted, matching the
  in-file precedent for mutex-holding jobs and still well below the sibling's 90.

## User-Brand Impact

- **If this lands broken, the user experiences:** no email in `ops@jikigai.com`, and
  `apply-web-platform-infra.yml`'s run history accumulating red runs nobody opens — 24 of the last
  60 already — while `soleur.ai` and `app.soleur.ai` keep serving on infrastructure configuration
  that `main` says was applied days ago.
- **If this leaks, the user's workflow is exposed via:** the failure email body, rendered by
  `.github/actions/notify-ops-email` and POSTed to `api.resend.com` (a third-party processor) into a
  plaintext, no-expiry mailbox. Commit SHA, branch, job names and run URL are low-sensitivity. The
  real vector is **interpolated step output** — the ARM gate reads `BETTERSTACK_API_TOKEN` and
  handles monitor ids, and terraform error strings carry resource identifiers and Doppler variable
  names. The control is the interpolation allow-list in §1.
- **Brand-survival threshold:** `aggregate pattern`

The brief proposed `single-user incident`. Downgraded on verified precedent: the post-mortem
covering **this same workflow and this same blindness defect** declares
`brand_survival_threshold: aggregate pattern` and states *"the harm is fleet-wide configuration
drift and a blinded detection channel, not a named user's incident."* Declaring a higher threshold
for the fix than for the incident is incoherent, and `single-user incident` carries a specific
obligation (§1218) a notification job does not clear. So the downgrade is not a gate dodge,
`user-impact-reviewer` is retained at review time voluntarily.

## Observability

```yaml
liveness_signal:
  what: "GitHub Actions job conclusion of `apply`, consumed by the sibling notify-apply-failure job"
  cadence: "per merge to main (measured 2.71/day) and per manual-rerun dispatch"
  alert_target: "ops@jikigai.com via .github/actions/notify-ops-email (Resend HTTP API)"
  configured_in: ".github/workflows/apply-web-platform-infra.yml (job notify-apply-failure)"

error_reporting:
  destination: "email via Resend; plus ::error:: annotations on the run summary card and $GITHUB_STEP_SUMMARY"
  fail_loud: "a non-green apply produces an email naming the failing step, the outcome (failed vs cancelled), what did not land, whether uptime alerting may be paused, and a copy-pasteable re-dispatch command"

failure_modes:
  - mode: "apply job fails on a named step"
    detection: "the notify job's predicate reads needs.apply.result, and its cause step resolves the failing step name from the jobs API"
    alert_route: "ops@jikigai.com email + red run"
  - mode: "apply job exceeds timeout-minutes and is cancelled mid-ARM-gate"
    detection: "needs.apply.result == 'cancelled'; measured on run 32168637847 that a timed-out job concludes cancelled and always() steps still run"
    alert_route: "ops@jikigai.com email with the cancelled-specific guidance"
  - mode: "preflight fails, leaving apply skipped on a red run"
    detection: "the predicate's negated form reads needs.preflight.result, not needs.apply.result alone"
    alert_route: "ops@jikigai.com email"
  - mode: "the whole RUN is cancelled before the notify job starts (manual cancel or concurrency supersede)"
    detection: "NOT DETECTED by this change — an always() job never starts when queued jobs are cancelled with the run. Measured frequency 1 of the last 60 runs. The covering mechanism is a workflow_run watcher, which does not exist for this workflow"
    alert_route: "none — named residual, tracked by the Deferrals item"
  - mode: "a heartbeat is left unpaused-and-unfed by an abnormal exit"
    detection: "the always() sweep step re-pauses every id in $RUNNER_TEMP/armed-unconfirmed and reports the count"
    alert_route: "::error:: on the run + the failure email; residually, the Better Stack absence alert itself"
  - mode: "the sweep step cannot re-mint BETTERSTACK_API_TOKEN, so it is inert exactly when the mint is what broke"
    detection: "the sweep emits ::error:: naming the unreadable credential rather than exiting quietly"
    alert_route: "red apply run -> notify-apply-failure email"
  - mode: "Resend rejects or drops the notification"
    detection: "none available in-workflow — the composite action collapses a non-2xx into ::warning:: and exits 0, so steps.<id>.outcome reads success. Known residual; fixing it means changing a composite shared by 11 workflows"
    alert_route: "the composite's own ::warning:: on a run that is already red and therefore being read"

logs:
  where: "GitHub Actions run logs for apply-web-platform-infra.yml; $GITHUB_STEP_SUMMARY per run"
  retention: "90 days (GitHub Actions default log retention)"

discoverability_test:
  command: "bun test plugins/soleur/test/terraform-target-parity.test.ts"
  expected_output: "0 fail — including the new `apply-web-platform-infra has a failure channel` and `the ARM gate's deadlines fit its job` describes, alongside the untouched `the ssh_token_gate green-skip has a channel (#7539)` describe"
```

## Guard Contract

Both guards share one anti-vacuity helper (`expectNonEmptyDispatch`) so "the guard must not pass on
an empty scan" is asserted once per guard rather than restated as four separate rows.

### Guard 1 — a non-green apply run has a channel

**Property.** Every run in which the `apply` job does not reach `success`, and every run in which
`apply` is skipped because `preflight` did not succeed, reaches `notify-ops-email`.

**Assembly.** The chokepoint is the `if:` **line** of the `notify-apply-failure` job, parsed by
`extractJobBlock(wf, "notify-apply-failure")` — not the job body, because a body-wide `toContain` is
satisfiable by an explanatory comment (the collision `terraform-target-parity.test.ts` already
documents for the `#7539` arm, per `cq-assert-anchor-not-bare-token`). The property quantifies over
the **conclusion enum** `{success, failure, cancelled, skipped}` and over **both** jobs the run's
health depends on, so the guard asserts the predicate's *shape* and that every job in `needs:`
appears in it — not an enumerated member list, which would drift as GitHub adds conclusions.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Change the predicate to `needs.apply.result == 'failure'` (the `infra-validation.yml` precedent's shape) | RED — silent on `cancelled` |
| 2 | Delete the `notify-apply-failure` job, so the guard has **zero** jobs to check | RED — `expectNonEmptyDispatch` must fire; a guard reporting "0 checked" and exiting 0 is vacuous |
| 3 | Drop the `needs.preflight.result` clause, leaving only `needs.apply.result` — a **second** `needs:` member the predicate no longer covers | RED — this is the defect the plan's own first draft shipped; a check that stops at the first `needs:` member is the class |
| 4 | Narrow the trigger clause to `github.event_name == 'push'` only | RED — the manual-rerun recovery path loses its channel |

**Harness rows:**

| # | Edit to the SUITE (not the guard) | Expected |
|---|---|---|
| H1 | Point `WEB_PLATFORM_WORKFLOW` at a fixture with no `notify-apply-failure` job while the assertions still "pass" | RED — proves the suite cannot go vacuous on a missing subject |
| H2 | (must-PASS, non-canonical) A fixture whose predicate reorders the operands, semantics identical | PASS — the contract permits reordering; a guard that only accepts the canonical byte string rejects a correct implementation |

### Guard 2 — the ARM gate's deadlines fit its job

**Property.** The sum of the ARM gate's per-arm deadlines is strictly less than the wall clock the
`apply` job can give it, and no exit path leaves a monitor unpaused-and-unfed.

**Assembly.** Three structural facts, all inside `extractJobBlock(wf, "apply")`: (i) the job's
`timeout-minutes`; (ii) the ARM step's own step-level `timeout-minutes`; (iii) every `arm_one` call
site's deadline argument. The chokepoint is the `arm_one` function — the call list does **not** fan
out with `for_each` (per the `2026-07-24-followthrough-soak-must-arm-every-new-member-monitor.md`
sharp edge), so each monitor is a hand-written line the guard must see. The rollback assembly
quantifies over the step's exit paths, all of which flow through the state file
`$RUNNER_TEMP/armed-unconfirmed`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Lower the `apply` job's `timeout-minutes` back to 15 while leaving the deadlines unchanged | RED — the sum no longer fits; this is #7587 restored |
| 2 | Delete every `arm_one` call, so the per-call-site scan checks **nothing** | RED — `expectNonEmptyDispatch` must fire |
| 3 | Add a **second** `arm_one` call whose deadline is individually fine but pushes the sum past the available budget, after a compliant first call | RED — a check that validates only the first call site is the defect class |
| 4 | Remove the step-level `timeout-minutes` from the ARM gate | RED — the gate reverts to being cancelled *with* the job rather than failing inside it |
| 5 | Remove the `if: always()` sweep step | RED — P5 is lost on every abnormal-exit path |
| 6 | Change the loop counter back to advancing only on `sleep`, ignoring the per-iteration `curl` | RED — reintroduces the 2.5× wall-clock undercount |

**Harness rows:**

| # | Edit to the SUITE (not the guard) | Expected |
|---|---|---|
| H3 | Feed a fixture whose `apply` job has **no** `timeout-minutes` at all | RED — must fail closed on a missing budget, never treat it as unbounded-and-fine |
| H4 | (must-PASS, non-canonical) A fixture where the step timeout is written `timeout-minutes: 27` vs the canonical value, still strictly below the job's | PASS — the contract is the inequality, not a literal |

**A known fragility, accepted.** Rows 3 and 6 regex over bash embedded in a YAML scalar, so a reflow
of that `run:` block breaks them. Accepted because the gate is currently asserted by **nothing**;
noted so a future editor knows why the block is brittle rather than deleting it.

## Architecture Decision (ADR/C4)

### ADR

**Amend `knowledge-base/engineering/architecture/decisions/ADR-117-executable-heartbeat-arming.md`.**
An amendment, not a new ordinal — this diverges from an existing Decision rather than making a new
one. Two items:

1. **A deadline that is deliberately not `period + grace − 10`.** The `inngest_consumer` arm moves
   to ~30 s, trading a per-apply arming probability for ~200 s of every merge. The ADR's formula
   stays the default; the exception and its bounded cost (an expected ~2-day arming window after
   the feeder heals) get named.
2. **The already-shipped soft-landing.** The `arc == 2` branch emits a `::warning::` instead of
   failing the apply for `inngest_consumer`, which departs from amendment property 3 ("fail-loud")
   and is today justified only in a workflow comment. This PR changes that arm, so documenting why
   it diverges is now this PR's business.

Two items were **cut** from an earlier draft: a `budget-exhausted` third outcome (it dissolved with
the cap, Cut List C4), and the property-1 `triggers_replace` doc/code divergence — genuinely
unrelated debt, recorded in Research Reconciliation as an observation rather than ridden into this
PR.

*Recorded disagreement:* the CTO consult judged no ADR necessary because the change "mirrors an
existing pattern". True of the notify job, false of the deadline exception — a reader of ADR-117
alone would be misled about a formula the ADR states unconditionally. The dissent is recorded rather
than hidden.

### C4 views

All three model files were read in full — `model.c4` (691 lines), `views.c4` (74), `spec.c4` (54) —
not grepped for the feature's noun. Enumeration per the completeness mandate:

- **(a) External human actors.** `founder = actor "Founder / Operator"` (`model.c4:8`) is the
  recipient behind `ops@jikigai.com`. Already modelled — **no new actor**.
- **(b) External systems.** `github` (`:234`), `resend` (`:272`), `betterstack` (`:309`), all
  `#external`. Already modelled — **no new system**.
- **(c) Containers / data stores touched.** None new.
- **(d) Access relationships that change.** One edit, down from two:
  - `github -> betterstack` (`:599`) describes the heartbeats API as "read-only (GET
    /api/v2/heartbeats) from the scheduled-terraform-drift.yml heartbeat-live-reconcile job", then
    says "SINCE #7278/ADR-172 THIS EDGE IS NO LONGER READ-ONLY" citing **only** the Logs INGEST
    POST. It never mentions that this workflow's ARM gate `PATCH`es `/api/v2/heartbeats/<id>` under
    a dedicated `DOPPLER_TOKEN_WEB_ARM` write token — a **pre-existing modelling gap on an edge
    this plan modifies**, so naming it is in scope.
  - `github -> resend` (`:618`) — **not edited** (Cut List C10). This workflow is already among the
    emitters that line counts, so the change adds no new one. The line's "thirteen" numeral is
    *not* asserted correct here: measured, there are 11 workflow files calling the composite (21
    call sites) plus 2 with an inline `api.resend.com` curl, and `web-platform-release.yml` is in
    both — 12 distinct files. Which quantity the numeral names is ambiguous, and resolving it is
    pre-existing debt this PR did not create and does not touch.

No new element and no new relationship edge, so **`views.c4` needs no `include` line and `spec.c4`
needs no change** — both read and confirmed. After editing, run the c4 syntax and render suites.

## Files to Edit

- `.github/workflows/apply-web-platform-infra.yml` — add the `notify-apply-failure` job; raise the
  `apply` job's `timeout-minutes` 15 → 30 and correct the false comparator comment; add the ARM
  gate's step-level `timeout-minutes`, the state file, and the `if: always()` sweep step; fix the
  loop's wall-clock accounting; resize the `inngest_consumer` deadline; add a one-line pointer
  comment to the guard suite. **Do not touch** the `#7539` notify step at `:1001-1029`.
- `plugins/soleur/test/terraform-target-parity.test.ts` — add two sibling `describe` blocks
  (Guard 1, Guard 2), the shared `expectNonEmptyDispatch` helper, and a header note that this suite
  also owns the apply workflow's channel and budget invariants. **Leave
  `describe("the ssh_token_gate green-skip has a channel (#7539)")` byte-identical** — it must stay
  green untouched, which is the regression signal that the new job did not disturb the old arm.
- `knowledge-base/engineering/architecture/decisions/ADR-117-executable-heartbeat-arming.md` — the
  two-item amendment above.
- `knowledge-base/engineering/architecture/diagrams/model.c4` — the `github -> betterstack` edge
  description only.

## Files to Create

None.

## Open Code-Review Overlap

**None.** Queried `gh issue list --label code-review --state open --limit 200` (64 open issues) and
matched each planned path against every issue body with `jq --arg path … contains`. Zero matches for
`.github/workflows/apply-web-platform-infra.yml`,
`plugins/soleur/test/terraform-target-parity.test.ts`, `ADR-117` and `model.c4`. Three issues
(#4133, #3531, #3216) match the bare directory prefix `plugins/soleur/test/` but name unrelated
suites — **acknowledged**, not folded in.

## Acceptance Criteria

### Pre-merge

- [ ] **AC1** — `.github/workflows/apply-web-platform-infra.yml` contains a job
      `notify-apply-failure` whose `if:` **line** (a) contains `always()`, (b) references
      `needs.preflight.result` **and** `needs.apply.result`, (c) admits both `push` and
      `apply_target == 'manual-rerun'`, and (d) is false only when `preflight` succeeded and `apply`
      is `success` or `skipped`; whose `needs:` array is `[preflight, apply]`; which declares
      `timeout-minutes` ≤ 10 and job-level `permissions:` containing both `contents: read` and
      `actions: read`; and whose `notify-ops-email` step declares `continue-on-error: true`.
- [ ] **AC2** — both new steps carry a `name:` (so the suite's `extractStep`, which matches
      `^ {6}- name:`, can see them). The email body interpolates only `github.sha`,
      `github.run_id`, `github.repository`, `github.server_url`, `needs.apply.result` and the
      `cause` step's shape-validated token: every `${{ … }}` inside the `body:` block resolves to
      that allow-list, and **none** references `needs.apply.outputs.*` or any `apply` step output
      (the `apply` job declares no `outputs:`, so such a reference would render empty). The body
      contains a **branch on `needs.apply.result == 'cancelled'`** — asserted on the expression, not
      on the prose word `cancelled`, which a body with no branch would also satisfy — plus the
      failing-step name, a line on whether uptime alerting may be paused, and a fenced
      `gh workflow run … -f apply_target=manual-rerun` block.
- [ ] **AC3** — the `apply` job's `timeout-minutes` is 30, its comparator comment no longer claims
      to match a 15-minute sibling, and the guard asserts
      `sum(arm_one deadlines) < apply_timeout_seconds − 62`.
- [ ] **AC4** — the ARM step declares a step-level `timeout-minutes` strictly below the job's; a
      named sibling step gated `if: always()` re-pauses every id in `$RUNNER_TEMP/armed-unconfirmed`,
      declares `DOPPLER_TOKEN_WEB_ARM` in its own `env:`, re-mints and masks
      `BETTERSTACK_API_TOKEN`, and emits `::error::` when that mint fails. An id is removed from the
      state file only on a 2xx `PATCH`.
- [ ] **AC5** — `arm_one`'s loop counter advances by measured elapsed time, not by `sleep` alone;
      the ARM step and the sweep step each declare `set +e` explicitly (errexit is inherited from
      `/usr/bin/bash -e {0}` and `set -uo pipefail` does not clear it); every rollback `PATCH`
      carries `|| true`; and no bare `(( … ))` appears in either step.
- [ ] **AC6** — the `inngest_consumer` `arm_one` call's deadline argument is ≤ 60, and every other
      `arm_one` deadline is unchanged from `origin/main`.
- [ ] **AC7** — every row of both mutation matrices and both harness tables has been executed
      against the implementation and produced the stated verdict; the log is recorded in
      `knowledge-base/project/specs/<branch>/measurements.md`.
- [ ] **AC8** — CI is green on every suite bound to this file, each named because a touched-file
      selection reaches only the first: `bun test plugins/soleur/test/terraform-target-parity.test.ts`,
      `bun test plugins/soleur/test/stock-preflight-coverage.test.ts`,
      `bash tests/scripts/test-preapply-entrypoint-gate.sh`,
      `bash tests/scripts/test-vector-redeliver-wiring.sh`,
      `bash apps/web-platform/infra/web-1-swap-concurrency-parity.test.sh`, the c4 syntax + render
      suites, `python3 scripts/lint-workflow-errexit-capture.py`,
      `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` (the gate's own
      invocation over the changed set, not a hand-enumerated path list), and `actionlint` — with
      each new/edited `run:` snippet additionally checked via `bash -c '<snippet>'`, never
      `bash -n` on the `.yml`.
- [ ] **AC9** — ADR-117 carries a dated amendment naming both items, and `model.c4`'s
      `github -> betterstack` description names the ARM gate's `PATCH` write.

### Post-merge (automated by `/ship`)

- [ ] **AC10** — `/ship` dispatches `gh workflow run apply-web-platform-infra.yml --ref main
      -f apply_target=manual-rerun -f reason='verify #7586/#7587 fix'` (its existing behaviour for
      modified workflows) and asserts the resulting run's `apply` job completes with an ARM step
      duration **< 60 s**, read from `gh api repos/:owner/:repo/actions/runs/<id>/jobs`. This is the
      end-to-end proof of the deadline resize and is fully automated.

## Test Scenarios

Written against the design, before the guard — and modelling the **steady state**, not only the
change (`2026-08-14-my-gate-reserved-its-reassuring-message-for-its-alarming-condition.md`).

1. **Given** `apply` concludes `failure`, **then** `notify-apply-failure` runs, resolves the failing
   step's name, and sends one email.
2. **Given** `apply` concludes `cancelled` (the `timeout-minutes` path), **then** the same job runs
   and renders the cancelled-specific guidance. Run `32168637847` is the fixture establishing that a
   timed-out job concludes `cancelled`.
3. **Given** `preflight` fails so `apply` is `skipped` on a red run, **then** an email is still sent.
   This is the case the first-draft predicate missed.
4. **Given** the run is a `workflow_dispatch` with `apply_target == 'manual-rerun'` that fails,
   **then** an email is sent — the recovery path has a channel.
5. **Given** `apply` concludes `success` — **the steady state, exercised deliberately** — **then**
   `notify-apply-failure` is `skipped` and no email is sent. Without this row the guard cannot
   detect a predicate that fires on everything.
6. **Given** `preflight` sets `skip=true` via the `[skip-web-platform-apply]` kill switch so `apply`
   is legitimately `skipped` on a green run, **then** no email is sent.
7. **Given** Resend returns a non-2xx, **then** the job still concludes green via
   `continue-on-error` and the composite's own `::warning::` is the only signal — the recorded
   residual, asserted so it cannot silently become something else.
8. **Given** the `apply` job is cancelled at its job budget while the ARM step holds an unconfirmed
   id, **then** the `always()` sweep re-mints its token and re-pauses that monitor inside the grace
   window.
9. **Given** the sweep runs but `BETTERSTACK_API_TOKEN` cannot be re-minted, **then** it emits
   `::error::` naming the credential rather than exiting quietly.
10. **Given** all monitors are already `up` — **the modal merge, and the steady state** — **then**
    every `arm_one` returns via `already armed (status=…)`, the state file is never written, the
    sweep finds nothing to do, and the ARM step completes in ≤ 5 s.
11. **Given** `inngest_consumer` is `paused` and its feeder is still dark, **then** the arm unpauses,
    polls for ≤ 30 s, rolls back to `paused`, and emits the existing `arc == 2` `::warning::` — same
    end state as today, ~200 s sooner.
12. **Given** `inngest_consumer` is `paused` and its feeder has become live, **then** a beat landing
    inside the 30 s window arms it, and the next apply is a no-op via `already armed`. This is the
    self-clearing property C2 preserves.

## Success Metrics

- ARM step duration on a modal merge apply drops from a measured 240 s to < 60 s.
- Apply-job wall clock on a modal merge drops from a measured 302 s to < 120 s.
- Fleet-mutex hold reclaimed: ~643 s/day (≈ 5.4 h/month) at 2.71 merge-applies/day.
- The share of non-green `main` runs that notify nobody goes from 25/60 to ~1/60 — the residual
  being run-level cancellation, which no in-run mechanism can cover.

## Dependencies & Risks

| Risk | Mitigation |
|---|---|
| Raising the job budget 15 → 30 doubles the worst-case fleet-mutex hold | Accepted, with in-file precedent: two mutex-holding jobs in this same file already use 30 and document the ladder (job ceiling above, in-script bound strictly below). Still well under the sibling `apply-deploy-pipeline-fix.yml`'s 90. The ceiling binds only when something is genuinely stuck. |
| Deadline resize re-pauses a monitor that was arming | Scoped to `inngest_consumer` alone (AC6 asserts every other deadline unchanged). Its monitor is already left paused on every apply today, so the end state is unchanged; the ~2-day post-heal arming window is owned explicitly in §4. |
| The `always()` sweep does not complete inside GitHub's cancellation grace window | The window's length is **undocumented and unmeasured** — a known unknown, not assumed away. The raised budget means the gate normally finishes well inside the job, so the sweep is a backstop rather than the primary path; and the notify job's correctness does not depend on the window at all. |
| The sweep is inert exactly when the Doppler mint is what broke | Recorded in `failure_modes` and asserted by Scenario 9: it emits `::error::` naming the credential instead of exiting quietly. |
| A YAML or `needs:` error stops the workflow parsing, so no apply runs on any merge — silently | AC8 (`actionlint` + per-snippet `bash -c`) plus AC10's `manual-rerun` dispatch before the change is relied upon. |
| The notify predicate is too loose and emails on green merges | Scenarios 5 and 6 are must-PASS steady-state rows, the only kind that can catch an always-fires predicate; Guard 1 mutation row 1 targets the shape. |
| Run-level cancellation still notifies nobody | Named residual, not closure: 1 of the last 60 runs. The covering mechanism is the deferred `workflow_run` catch-all. |
| Guard 2 rows 3 and 6 regex over bash inside a YAML scalar and break on a reflow | Accepted and documented in the Guard Contract, because the gate is currently asserted by nothing. |

## Deferrals (tracking issue to file at ship time)

**A default notification posture for production-affecting workflows.** Raised independently by the
CPO and CTO consults. This is the *second* notification arm bolted onto this one workflow (#7539
covered the green-skip shape, #7586 the red shape) — coverage bought one post-mortem at a time, per
workflow, per failure shape. Concrete first data point: `apply-deploy-pipeline-fix.yml`, the sibling
that also holds the fleet apply mutex and also applies production infrastructure, has **zero**
`notify-ops-email` call sites.

Estimated scope, from the CTO consult: 24 workflows carry a `push:` trigger and 12 already call
`notify-ops-email`. A `workflow_run` catch-all is one new file (~70 lines) with a
`workflows: [<names>]` list and `if: github.event.workflow_run.conclusion != 'success'`, plus ~60
lines of suite asserting every push-triggered workflow's `name:` appears in that list — mandatory,
because `workflow_run` matches on `name:`, not path, so a rename silently drops coverage. Total
≈ 130 lines. Because `workflow_run` fires on `completed` including `cancelled`, it buys P1 and P2
for all 24 workflows **and closes this plan's run-level-cancellation residual**, which no in-run
mechanism can.

It does **not** buy P3 — a catch-all cannot say "the post-bridge `terraform_data` set did not land"
or hand over a workflow-specific recovery command. That is why the bespoke arm ships now and the
catch-all is deferred rather than substituted.

**Also folded into this deferral:** the burst-suppression and green-again-email machinery cut from
this plan (C7, C8). De-duplication belongs in the catch-all as one implementation across 24
workflows, not as the 25th hand-rolled copy — building it per-workflow is precisely the pathology
the deferral exists to end. Re-evaluation criterion: the next workflow found to have no channel, or
a request from the notification's recipient.

## References & Research

- Issues: **#7586** (P1, the channel), **#7587** (P2, the budget). Context only, **not** work
  targets: **#7228** (OPEN incident), **#7462** (OPEN, blocks #7228 per ADR-100's addendum),
  **#7539** (closed by PR #7568), **#7299** (closed; its `notify-main-failure` precedent is live).
- Provenance PR: **#7568**, merged 2026-08-17T01:25:52Z.
- In-repo precedents: `.github/workflows/infra-validation.yml` (`notify-main-failure` job),
  `.github/workflows/registry-host-replace-dispatch.yml` (`always() && job.status != 'success'` with
  a cancelled branch), `.github/workflows/apply-deploy-pipeline-fix.yml` (the `#7220` alerting arm
  and its `!= 'success'` reasoning; also the 90-minute apply job that falsifies this file's
  comparator comment).
- ADRs: [ADR-117](../../engineering/architecture/decisions/ADR-117-executable-heartbeat-arming.md),
  [ADR-154](../../engineering/architecture/decisions/ADR-154-repair-the-credential-channel-not-the-host.md),
  [ADR-170](../../engineering/architecture/decisions/ADR-170-workflow-run-step-must-clear-inherited-errexit.md),
  [ADR-136](../../engineering/architecture/decisions/ADR-136-preapply-entrypoint-enumeration-gate.md).
- Post-mortem: `knowledge-base/engineering/operations/post-mortems/web-platform-infra-apply-bridgeless-target-postmortem.md`.
- Measurement runs cited: `32356859661` (modal green apply, the 240/302 s split),
  `32168637847` (`main-health-monitor` job timeout — the `cancelled`-conclusion + `always()`-runs
  measurement), `31976455160` / `31974987253` (the two 2026-08-16 red runs).
- Rules applied: `hr-no-dashboard-eyeball-pull-data-yourself`, `hr-observability-layer-citation`,
  `hr-observability-as-plan-quality-gate`, `hr-verify-repo-capability-claim-before-assert`,
  `hr-technical-fork-is-not-an-operator-question`, `cq-assert-anchor-not-bare-token`,
  `cq-cite-content-anchor-not-line-number`, `wg-architecture-decision-is-a-plan-deliverable`,
  `wg-record-recurring-vendor-expense-before-ready`, `wg-when-deferring-a-capability-create-a`.

**Observability layer (`hr-observability-layer-citation`).** The layer this change operates on is
**GitHub Actions job conclusions → the `notify-ops-email` composite action → the Resend HTTP API →
`ops@jikigai.com`**, with `::error::` annotations and `$GITHUB_STEP_SUMMARY` as the in-band second
channel. It is deliberately *not* Sentry (this workflow has no `sentry-heartbeat` call site) and not
Better Stack (which this workflow *writes* to as a subject, never reads from as an alerting
channel). The PR body must name this same layer.

## Domain Review

**Domains relevant:** Engineering, Operations, Product

*Substitution note: the `cto`, `coo`, `cpo`, `dhh-rails-reviewer`, `kieran-rails-reviewer` and
`code-simplicity-reviewer` agents are not registered in this session; each was run as a
`general-purpose` agent carrying the corresponding prompt verbatim.*

### Engineering

**Status:** reviewed
**Assessment:** Endorsed the separate-job shape but rejected copying `infra-validation.yml`'s
`== 'failure'` predicate, silent on exactly the #7587 path. Settled the `always()`-under-job-timeout
question **by measurement** (run `32168637847`), retiring it from assumption to fact. Applied YAGNI
to the proposed sub-mechanisms, replacing the `inngest_consumer` short-circuit with a deadline
resize (C2) — the single highest-value change in the plan. Dissented on the need for an ADR; the
dissent is recorded with its counter-argument. Ranked blast radius: (1) a rollback bug leaving a
heartbeat unpaused-and-unfed pages the recipient at 03:00; (2) an over-eager rollback leaves
production alerting silently paused; (3) a YAML error stops every apply.

### Operations

**Status:** reviewed
**Assessment:** No recurring vendor expense created — Resend Pro carries 50,000 emails/mo against a
projected ~45/mo; Better Stack call volume *decreases*; the repository is public so runner minutes
are free and the saving is wall-clock, not dollars. Flagged that
`wg-record-recurring-vendor-expense-before-ready` will still match `secrets.RESEND_API_KEY`
mechanically at ship time and must carry an explicit written no-change disposition — folded into
Technical Considerations. Measured notification volume (24 failures / 60 runs / 16.59 days ≈ 1.5/day)
and judged the average tolerable but the distribution bursty; the de-duplication that judgement
implied was subsequently **cut** by the plan-review panel and moved to the Deferrals item, where it
is one implementation across 24 workflows rather than the 25th. Named the likeliest trap as a
suppression outliving #7228, which C2 removes by construction.

### Product/UX Gate

**Tier:** none
**Decision:** reviewed
**Agents invoked:** cpo (for the brand-survival threshold determination required by Phase 2.6
Step 3, not as a UX gate)
**Skipped specialists:** none
**Pencil available:** not applicable — no UI surface

The mechanical UI-surface override was evaluated and did **not** fire: `## Files to Edit` contains
one `.yml`, one `.test.ts`, one `.md` and one `.c4` — no path matches
`components/**/*.{tsx,jsx,vue,svelte}`, `app/**/page.tsx`, `app/**/layout.tsx`, `pages/**`,
`routes/**`, `*.njk`, `*.html`, `*.vue`, `*.svelte` or `*.astro`. `ux-design-lead` is therefore not
a required producer and `wg-ui-feature-requires-pen-wireframe` does not fire.

#### Findings

CPO **granted** sign-off, reasoning that the change replaces an unmonitored channel with a named one
and its worst failure mode is the status quo rather than a new production write. It then **rejected
the proposed `single-user incident` threshold** on verified precedent and supplied the three impact
lines, the interpolation allow-list, and the alert-fatigue framing. Its one blocking-adjacent note
(heartbeat behaviour depending on mutable issue state) is **dissolved by Cut List C2**. Its
strategic finding — a repo-wide default notification posture — is the Deferrals item, independently
corroborated by the CTO devex review with a costed estimate.

### Plan Review Panel

**Status:** reviewed (5 of 5 reviewers returned)
**Consolidated outcome:** the panel cut **eight** mechanisms (C3-C10). Both the simplification lens
(DHH, code-simplicity) and the correctness lens (the scoped advisor consult, CTO devex) fired on the
same scope for the burst-suppression machinery, so per `plan-review`'s consolidation rule the
disposition was **delete rather than fix** — and doing so dissolved two Test Scenarios, a Success
Metric, an AC and a Risk row without leaving a property uncovered. Acceptance Criteria went 19 → 10,
guard rows 17 → 12.

Eight defects were found in the plan's own drafts and fixed rather than shipped: the `push`-only
trigger clause silently excluded the manual-rerun recovery path; the predicate ignored
`needs.preflight.result`; Cut List C4's stated cost was factually wrong; the ADR-170 errexit claim
was **inverted**; the cause token was specified to come from job outputs that do not exist; a failed
rollback would have dropped its own id from the sweep's state file; the sweep had no credential; and
two of the plan's own counts (Resend emitters, workflow traps) were wrong. Every one of these would
have surfaced at `/work` or later. All findings classified **Mechanical** (correctness and
simplification on a purely-technical surface) and were auto-applied; the one **User-Challenge** —
substituting a deadline resize for the brief's requested short-circuit — is persisted to
`knowledge-base/project/specs/<branch>/decision-challenges.md` for `ship` to render, per the headless
routing in ADR-084.

## Session Notes

- **Lane.** No `spec.md` exists on this branch, so `lane:` is written by Save Tasks as the
  fail-closed default. Spec lacks valid `lane:` — defaulted to `cross-domain` (TR2 fail-closed).
- **Panel completeness.** All five plan-review reviewers returned. The correctness lens returned
  last and was the most valuable: it **inverted** this plan's ADR-170 claim (errexit is inherited,
  not absent — see Research Reconciliation), showed the cause token could not come from `apply` step
  outputs, showed that removing an id on a *failed* rollback defeats the sweep, showed the sweep
  needs its own `DOPPLER_TOKEN_WEB_ARM` in `env:`, corrected two of this plan's own counts (Resend
  emitters, workflow traps), and supplied the web-host-birth arithmetic (1400 s of arming) that
  sizes the raised budget. It independently confirmed the `preflight`-path predicate defect the
  author had already found, and independently verified nine of the plan's factual claims about the
  repo as holding.
- **Sharp edge for `/work`.** A plan whose `## User-Brand Impact` section is empty, contains only
  placeholder text, or omits the threshold fails `deepen-plan` Phase 4.6. This plan's section is
  complete and its threshold is `aggregate pattern`.
