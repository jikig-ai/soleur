---
title: "fix: monitor registry guard gaps — NON_INNGEST_MONITORS stale-entry message + cadence-parity evidence"
type: fix
date: 2026-11-01
slug: fix-monitor-registry-guard-gaps
branch: feat-one-shot-8595-monitor-guard-parity
issue: 8595
closes: [8595]
lane: cross-domain
brand_survival_threshold: none
domain: engineering
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- The flag fired on the verbatim `## Operator Holds` record, which names acts this batch must NOT perform, not prescribed steps. Phase 2.8 evaluated: zero new infrastructure and no `.tf` edit, so no `## Infrastructure (IaC)` section is owed. -->

# fix: monitor registry guard gaps — NON_INNGEST_MONITORS stale-entry message + cadence-parity evidence

## Overview

Issue #8595 (review scope-out from PR #8588, epic #10390 PR 3) asks for a
reverse-direction guard on the `NON_INNGEST_MONITORS` exemption set in
`apps/web-platform/test/server/inngest/function-registry-count.test.ts`, a
failure message that prescribes removing stale entries, and cadence parity
between GitHub Actions `schedule:` crons and the Sentry monitor `crontab`
declared in `apps/web-platform/infra/sentry/cron-monitors.tf`. A 2026-11-01 CTO
epic-ownership ruling found roughly ninety percent of the issue already
satisfied on `origin/main` by later drift (test (c3) added by PR #9303, plus the
#8450 crontab-parity and #8495 watchdog-dispatch-clock-parity suites). This plan
ships only the verified residual: a removal-prescribing failure message on test
(c3), plus in-plan evidence that each remaining acceptance criterion already
holds at HEAD.

Spec lacks valid `lane:` — defaulted to cross-domain (TR2 fail-closed).

<!-- markdownlint-disable MD034 -->
<!-- lint-infra-ignore start: the `## Operator Holds` block below is a verbatim hold RECORD naming acts this batch must NOT perform — it prescribes no step (same verbatim record as the batch-1 plan, which predates this lint's coverage of plans/) -->
## Operator Holds

Delegation: https://github.com/jikig-ai/soleur/issues/10390#issuecomment-6361717901
Envelope: knowledge-base/engineering/operations/runbooks/inngest-epic-10390-envelope.md

- Hold: Operator-reserved: op=backup dispatch — the operator runs the cutover-inngest.yml op=backup dispatch themselves; it performs a Hetzner create_image write on a third-party system, is outside the recorded Scope, and is on the Excluded list
- Hold: Operator-reserved: DOPPLER_TOKEN_INFRA_PRIVILEGED seed — the operator seeds the privileged Doppler token themselves; a secret-store write is never delegable

**Gated acts in this plan: none.** Every deliverable is a test file, a server-source edit, a ledger JSON edit, or a CI workflow step-env pin. No Terraform apply, no host write, no secret-store write, no vendor-dashboard act is prescribed, so no envelope file is created; the Envelope line above names the recommended path should a later batch need one. The two recorded holds are untouched by this batch (the op=backup dispatch and the Doppler seed belong to other epic workstreams).
<!-- lint-infra-ignore end -->
<!-- markdownlint-enable MD034 -->

## Problem Statement / Motivation

`NON_INNGEST_MONITORS` is a hand-maintained allow-list of Sentry cron monitors
that legitimately have no `cron-*.ts` Inngest counterpart. Guard (c2) requires
every `sentry_cron_monitor` name in `cron-monitors.tf` to resolve to a
`SENTRY_MONITOR_SLUG` or a `NON_INNGEST_MONITORS` entry — but when the issue
was filed nothing asserted the reverse direction, so a deleted tf monitor left
a permanent, meaningless exemption behind. Since then, PR #9303 merged test
(c3), which asserts exactly that reverse direction — but with a bare
`expect(stale).toEqual([])`, whose vitest diff output names the stale entries
without telling the next author what to do about them. The residual defect is
the missing remediation affordance: the failure must name each stale entry AND
prescribe removing it from the set, matching the "remove the stale entry"
contract the issue asked for.

The issue's second leg — cadence parity — asked that every `monitor-slug:`
heartbeat in `.github/workflows/` have its workflow `cron:` ≡ the monitor's tf
`crontab`, and `checkin_margin_minutes` ≡ interval where a tf comment documents
that convention. Two suites landed after the issue: the #8450
`GHA schedule cron ↔ monitor crontab parity` block and the #8495
`Watchdog dispatch clock parity` block in
`apps/web-platform/test/server/inngest/sentry-monitor-iac-parity.test.ts`. The
`checkin_margin_minutes ≡ interval` leg is conditioned on a convention the tf
file explicitly refutes (its comments document measured-delivery margin sizing,
NOT margin == interval), so that leg is vacuous by design and is a documented
Non-Goal — not a new assertion.

## Proposed Solution

One edit, in place, at
`apps/web-platform/test/server/inngest/function-registry-count.test.ts` — the
existing (c3) test at `it("(c3) every NON_INNGEST_MONITORS entry names a
monitor declared in cron-monitors.tf", ...)`. Add a second-arg failure message
to the expectation, interpolated with the offending entries:

```ts
it("(c3) every NON_INNGEST_MONITORS entry names a monitor declared in cron-monitors.tf", () => {
  const stale = [...NON_INNGEST_MONITORS].filter((name) => !tfMonitors.has(name));
  expect(
    stale,
    `stale NON_INNGEST_MONITORS entries name no sentry_cron_monitor in cron-monitors.tf — remove them from the set: ${stale.join(", ")}`,
  ).toEqual([]);
});
```

This is the vitest `expect(actual, message)` form — the message surfaces only
on failure, names every stale entry via the `stale` interpolation, and
prescribes the remedy ("remove them from the set"). The same second-arg form
is already the convention in the sibling suite (`expect(entry, "#8495: …")`
in `sentry-monitor-iac-parity.test.ts`). vitest `^4.1.11` supports the
second-arg message (installed version verified in
`apps/web-platform/package.json`).

### Non-Goals

- **No `checkin_margin_minutes ≡ interval` assertion.** The issue conditions
  that leg on "where the tf comment documents that convention", and
  `cron-monitors.tf` documents the opposite — its comments state that measured
  delivery refutes `margin == interval` (see the `checkin_margin_minutes = 360`
  rationale blocks around the `scheduled-zot-restart-loop` and prod-version
  monitors), and the file declares zero `type = "interval"` monitors. Pinning
  the vacuity would guard prose comments the issue never asked to guard.
  Disposition inside the CTO's ruled option set recorded in
  `decision-challenges.md`.
- **No new test file, no new suite, no new monitors.** The coverage the issue
  describes already exists; this PR is a message change plus evidence.
- **Sibling (d) `KNOWN_UNMONITORED_SLUGS` staleness message.** `expect(stale).
  toEqual([])` at the (d) test has the identical missing-remediation-message
  shape, but the issue names `NON_INNGEST_MONITORS` only. Recorded as a
  fold-in candidate for review; descoped here to keep the residual diff at the
  single line the CTO ruling sized.
- **No margin/cadence re-measurement.** The #8495 block already pins the
  measured queue-allowance budget; this plan does not re-derive it.

## Implementation Phases

### Phase 1 — Message change + verification

- [ ] RED: temporarily append a bogus name (e.g. `"nonexistent-monitor-probe"`)
  to `NON_INNGEST_MONITORS`, run the suite, and confirm (c3) fails with output
  naming the bogus entry and prescribing removal. Revert the probe.
- [ ] Apply the message change in
  `apps/web-platform/test/server/inngest/function-registry-count.test.ts`.
- [ ] GREEN: `cd apps/web-platform && ./node_modules/.bin/vitest run
  test/server/inngest/function-registry-count.test.ts` — all tests pass.
- [ ] `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` — clean.

## Research Insights

**Premise Validation.** All cited references verified at HEAD
(2026-11-01): issue #8595 is OPEN (labels: `code-review`,
`deferred-scope-out`, `meta/machinery`, `domain/engineering`,
`priority/p3-low`); epic #10390 is OPEN; #11653 (the drift that satisfied
parts of the issue) is MERGED; draft PR #11824 exists on this branch; test
(c3) exists at `function-registry-count.test.ts` and its provenance commit
`b2cebec0d6` (PR #9303, merged 2026-09-30) adds it verbatim; all 16
`NON_INNGEST_MONITORS` entries resolve to `name =` attributes in
`cron-monitors.tf` (zero stale — measured by set-difference at plan time);
the #8450 crontab-parity describe-block and #8495 watchdog-parity
describe-block both exist in `sentry-monitor-iac-parity.test.ts`;
`cron-monitors.tf` contains zero `type = "interval"` monitors and its comments
explicitly refute the `margin == interval` convention. The collision precheck
(`collision-precheck.sh 8595`) returned the expected self-hit (draft PR
#11824) plus foreign `test-all.sh` runs owned by other worktrees — none name
#8595.

**Property List** (what the asks reduce to):

1. A failing state exists when a `NON_INNGEST_MONITORS` entry names no
   `sentry_cron_monitor` in `cron-monitors.tf` — already bought by (c3).
2. That failure's output names each stale entry and prescribes its removal —
   the residual; bought by the second-arg message.
3. The suite stays green — a verification, not a mechanism.
4. Every `monitor-slug:` heartbeat's workflow `cron:` ≡ tf `crontab` — bought
   by the #8450 block (and dispatch-clock budget by #8495).
5. `checkin_margin_minutes ≡ interval` where documented — vacuous by design;
   no mechanism exists or is owed (Non-Goal).

**Cut List** (mechanisms the issue proposed that an existing mechanism already
covers):

- "Add a reverse-direction assertion mirroring the `KNOWN_UNMONITORED_SLUGS`
  staleness check" → property 1 → covered by test (c3), added by PR #9303
  (`b2cebec0d6`, merged 2026-09-30).
- "Cadence-parity assertion exists for every `monitor-slug:` heartbeat" →
  property 4 → covered by `describe("GHA schedule cron ↔ monitor crontab
  parity (#8450)")` + `describe("Watchdog dispatch clock parity (#8495)")` in
  `sentry-monitor-iac-parity.test.ts`.
- A `margin ≡ interval` assertion → property 5 → vacuous by design; the tf
  comments refute the convention the leg is conditioned on. Cut as Non-Goal.

**Relevant files:**

- `apps/web-platform/test/server/inngest/function-registry-count.test.ts` —
  the only file edited. `NON_INNGEST_MONITORS` set (~L120-229, 16 entries);
  test (c2) ~L308; test (c3) ~L321; sibling (d) staleness check ~L329;
  `extractTfMonitorNames()` reads `name =` attributes out of
  `apps/web-platform/infra/sentry/cron-monitors.tf` (path at ~L30).
- `apps/web-platform/test/server/inngest/sentry-monitor-iac-parity.test.ts` —
  evidence file only, NOT edited. `monitorCrontabBySlug()` ~L596; #8450
  describe ~L621 (asserts each crontab-scheduled heartbeat monitor's tf
  `crontab` is one of its own workflow's `cron:` expressions, with an
  anti-vacuity `checked.length >= 3` floor plus named-slug presence); #8495
  describe ~L769 (margin budget predicate `marginWithinBudget`, dispatch-table
  parity, the "dispatched at least every 15 minutes" pin).
- `apps/web-platform/infra/sentry/cron-monitors.tf` — evidence file only,
  NOT edited. The margin-rationale comments explicitly reject
  `margin == interval` ("sized to MEASURED delivery rather than to the
  nominal interval… deliberately NOT followed").

**Institutional learnings applied:**

- `knowledge-base/project/learnings/2026-09-30-the-adr-sentence-i-cited-was-about-another-routine-and-a-history-seat-confirmed-it.md` —
  run every literal command the plan prescribes once before freezing it (the
  discoverability probe and each AC grep were run at plan time).
- `knowledge-base/project/learnings/2026-10-30-the-required-set-check-passed-review-with-no-p1-and-its-own-fixes-needed-two-more-rounds.md` —
  `decision-challenges.md` technical rows must carry the `Ruled by CTO agent,
  <date>:` shape or be reclassified; unresolved forks stay `pending -
  assumed:` for the parent pipeline's batched CTO consult.
- `knowledge-base/project/learnings/2026-09-23-a-sub-step-hands-its-exits-to-its-caller.md` —
  before deleting/cheapening an assertion, name the mutation it kills; the
  (c3) message change adds affordance without weakening the assertion.
- `knowledge-base/project/learnings/2026-06-07-self-discovering-parity-guard-for-cross-producer-drift.md` —
  the self-discovering-parity-guard convention this suite family already
  follows (derive the cohort by walking the producer set, never a hand list).
- `knowledge-base/project/learnings/integration-issues/2026-09-24-a-reliable-dispatch-clock-still-waits-in-the-runner-queue.md` —
  the measured queue-allowance basis for the #8495 margin budget; the reason
  no `margin == interval` convention exists.
- `knowledge-base/project/learnings/2026-05-29-target-allowlist-extension-must-sweep-all-guard-suites.md` —
  allow-list edits are asserted on by sibling guards; landmine note below.

**Related issues / PRs:** #8588 (review source), #9303 / `b2cebec0d6` ((c3)
provenance), #9304 (the monitor-deletion follow-up (c3) was written for),
#8450, #8495 (cadence legs), #11653 (merged drift satisfying the rest),
#10390 (epic), #11824 (this draft PR).

**CLAUDE.md / constitution conventions:** minimalism ladder rung 1 — the
question "does it need to exist" is answered by the CTO ruling: only the
message line is new code; grep-stable symbol anchors (`it("(c3) …")`,
`NON_INNGEST_MONITORS`, `extractTfMonitorNames`) used instead of load-bearing
line numbers (the ~L-numbers above are orientation only).

**External research:** skipped — strong local context; every anchor was
verified against HEAD in Phase 0.6 and the suite's own comments carry the
design rationale.

**Community / functional overlap:** none — a repo-internal vitest assertion
message; no community artifact covers a repository-specific exemption set.

## Research Reconciliation — Spec vs. Codebase

| Issue claim | Reality at HEAD (verified 2026-11-01) | Plan response |
|---|---|---|
| "nothing asserts the reverse direction" (a `NON_INNGEST_MONITORS` entry with no tf monitor stays) | Test (c3) asserts exactly that direction — added by PR #9303 after the issue was filed | AC evidence grep pins (c3)'s presence; no new test needed |
| "else fail with a 'remove the stale entry' message" | (c3) uses bare `expect(stale).toEqual([])` — names entries via vitest diff, prescribes nothing | The residual edit: second-arg message naming entries + prescribing removal |
| "no cadence parity" for `monitor-slug:` heartbeats | #8450 block asserts `cron:` ≡ `crontab` for every workflow heartbeat slug with an anti-vacuity floor; #8495 block pins dispatch-clock margin budget | Evidence ACs; no new suite |
| "`checkin_margin_minutes` ≡ interval where the tf comment documents that convention" | The tf comments document the opposite (measured-delivery margins); zero `type = "interval"` monitors | Non-Goal, recorded in `decision-challenges.md` |
| `NON_INNGEST_MONITORS` "~lines 83-199" | The set now spans ~L120-229 with 16 entries (drift added members) | Plan anchors on the symbol, not line numbers |

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing — worst
  case is a red required check on a PR that deletes a tf monitor, with a less
  actionable failure message than intended.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no
  exposure vector — the diff is a failure-message string in a test file; it
  ships no runtime path, touches no credential, and reads no user data.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** `none` and not `aggregate pattern`
  because the blast radius of a defect here is one confusing CI failure
  message on an internal guard — no user-facing artifact exists to break or
  leak.

## Observability

```yaml
liveness_signal:
  what: the (c3) NON_INNGEST_MONITORS staleness assertion — a red vitest result on the web-platform test shard when an exemption outlives its sentry_cron_monitor
  cadence: per-PR (required check) and on every main push via the full battery
  alert_target: PR author and reviewer via the failing required check
  configured_in: apps/web-platform/test/server/inngest/function-registry-count.test.ts (`it("(c3) every NON_INNGEST_MONITORS entry names a monitor declared in cron-monitors.tf")`)

error_reporting:
  destination: the GitHub Actions check-run output carrying the vitest failure text
  fail_loud: the (c3) expectation failure prints the message naming each stale entry and prescribing its removal from the set

failure_modes:
  - mode: a sentry_cron_monitor is deleted from cron-monitors.tf while its NON_INNGEST_MONITORS exemption stays
    detection: (c3) red on the next run of the suite, naming the stale entry
    alert_route: failing required check on the PR that deletes the monitor (or the next suite run on main)
  - mode: the exemption set is emptied or the it-block deleted outright
    detection: emptied entries go red via the (c2) phantom-name assertion; a deleted it-block is pinned by AC4's presence grep and by review
    alert_route: failing required check / PR review
  - mode: extractTfMonitorNames() is weakened (regex stops matching `name =` attributes)
    detection: tfMonitors.size floor assertion `expect(tfMonitors.size).toBeGreaterThan(0)` plus (c2) phantom-name reds
    alert_route: failing required check

logs:
  where: GitHub Actions run log for the web-platform test job
  retention: repository default run-log retention (~90 days)

discoverability_test:
  command: grep -c -e 'stale NON_INNGEST_MONITORS' apps/web-platform/test/server/inngest/function-registry-count.test.ts
  expected_output: "1"
```

## Guard Contract

The deliverable amends an existing assertion-based drift-check — the (c3)
staleness guard — so its contract is recorded here even though the diff is a
message string.

### Guard 1 — (c3) NON_INNGEST_MONITORS staleness guard (amended failure message)

**Property.** No `NON_INNGEST_MONITORS` entry outlives the
`sentry_cron_monitor` it exempts, and a violation's failure output names each
stale entry and prescribes removing it from the set.

**Assembly.** Two chokepoints the property quantifies over. (a) The
`NON_INNGEST_MONITORS` set literal in
`function-registry-count.test.ts` — every exemption for a monitor with no
Inngest counterpart must be declared there, because the reverse-direction (c2)
assertion makes any tf `name =` that maps to neither a `SENTRY_MONITOR_SLUG`
nor a set entry red, so the set is the only place an exemption can live.
(b) `extractTfMonitorNames()`'s parse of `name =` attributes inside
`resource "sentry_cron_monitor"` blocks in `cron-monitors.tf` — the universe
the set is checked against.

**Mutation matrix.**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Append `"nonexistent-monitor-probe"` to `NON_INNGEST_MONITORS` (no matching `name =` in tf) | RED — (c3) fails, output names `nonexistent-monitor-probe` and prescribes removal |
| 2 | Delete the `it("(c3) …")` block entirely — the guard's own dispatch | RED via AC4's presence grep on the test name (a suite cannot observe its own deleted test; the plan-level census pins the block) |
| 3 | Keep the 16 compliant entries and append TWO stale names | RED — `stale` enumerates all offenders, the message names both (a check that stops at the first member is the defect) |
| 4 | Harness must-PASS, non-canonical input: add `"example-gha-fired"` to the set AND a matching `name = "example-gha-fired"` monitor in tf | PASS — a compliant new exemption; the guard is not a reject-everything stub |
| 5 | Anchor row: weaken `extractTfMonitorNames()` so it unions in a hardcoded name covering a stale entry | Would fake-green — the stored value (tf `name =` literals) and the reader live in the same diff's reach; the outside-the-commit anchor is the (c2) reverse assertion plus IaC review of `cron-monitors.tf` |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "A test fails when a `NON_INNGEST_MONITORS` entry names no `sentry_cron_monitor` in `cron-monitors.tf`" [issue #8595] | Already satisfied by test (c3) (PR #9303); AC4 evidence grep pins its presence | mapped |
| 2 | "The failure message names the stale entry and prescribes removal" [issue #8595] | The (c3) second-arg message edit (Files to Edit #1); AC1, AC2 | mapped |
| 3 | "`vitest run test/server/inngest/function-registry-count.test.ts` green" [issue #8595] | AC3 | mapped |
| 4 | "Cadence-parity assertion exists for every `monitor-slug:` heartbeat in `.github/workflows/` (workflow `cron:` ≡ tf `crontab`, …)" [issue #8595] | Already satisfied by the #8450 + #8495 describe-blocks; AC4 evidence greps pin both | mapped |
| 5 | "…and `checkin_margin_minutes` ≡ interval where the tf comment documents that convention" [issue #8595] | — | descoped — justification: the leg's own condition is unsatisfiable by design — `cron-monitors.tf` documents measured-delivery margins and explicitly refutes `margin == interval`; zero `type = "interval"` monitors exist. Recorded as a Non-Goal inside the CTO ruling's sanctioned option set |
| 6 | "record this section VERBATIM in the plan file" [brief — `## Operator Holds`] | `## Operator Holds` verbatim copy | mapped |
| 7 | "`## Observability` block (5 fields, discoverability_test.command runnable without SSH)" [brief] | `## Observability` yaml block | mapped |
| 8 | "decision-challenges.md rows for: the CTO scope ruling (technical), and any rulings made during planning" [brief] | `knowledge-base/project/specs/feat-one-shot-8595-monitor-guard-parity/decision-challenges.md` | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Files to Edit #1 — `(c3)` second-arg message edit | "The failure message names the stale entry and prescribes removal" | asked |
| AC4 evidence greps (c3 presence, #8450, #8495) | "the subagent must re-verify at HEAD and cite" [brief — CTO ruling carry-forward] | asked |
| `## Operator Holds` verbatim | "Re-record the `## Operator Holds` section VERBATIM" [brief] | asked |
| `## Observability` | "`## Observability` block (5 fields…)" [brief] | asked |
| `decision-challenges.md` | "decision-challenges.md rows for: the CTO scope ruling (technical)…" [brief] | asked |
| `tasks.md` | — | inferred — justification: the Save Tasks contract derives it from the plan; the one-shot pipeline consumes it |
| `session-state.md` and other `specs/<branch>/` pipeline artifacts | — | inferred — justification: pipeline bookkeeping the branch convention writes, not part of the product diff |

### Split Assessment

- Subsystems touched: 1 — `apps/web-platform/test/server/inngest/`
- Planned files: 1 product file (plus knowledge-base planning artifacts) | Estimated changed lines: ~4
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Open Code-Review Overlap

Checked `gh issue list --label code-review --state open` (200 issues) for
bodies containing `apps/web-platform/test/server/inngest/function-registry-count.test.ts`
and `sentry-monitor-iac-parity.test.ts`. Sole hit: **#8595 — this plan's own
target issue.** No other open scope-out touches the planned files. Nothing to
fold in, acknowledge, or defer.

## Acceptance Criteria

<!-- founder-stated check: see plan-founder-check.md -->

- [ ] **AC1** — Test (c3) in `apps/web-platform/test/server/inngest/function-registry-count.test.ts`
  passes a second-arg message to `expect(stale, …)` that (a) interpolates the
  `stale` array so each offending entry is named and (b) prescribes removing
  the entries from the set. Verify:
  `grep -n 'stale NON_INNGEST_MONITORS' apps/web-platform/test/server/inngest/function-registry-count.test.ts`
  returns ≥1 hit and the matched text contains a removal directive.
- [ ] **AC2** — RED proof: with a temporary bogus entry appended to
  `NON_INNGEST_MONITORS`, the (c3) test fails and its output names the bogus
  entry and prescribes removal (mutation-matrix row 1; the probe entry is
  reverted before commit).
- [ ] **AC3** — `cd apps/web-platform && ./node_modules/.bin/vitest run
  test/server/inngest/function-registry-count.test.ts` exits 0 (13/13 green at
  HEAD, verified 2026-11-01).
- [ ] **AC4** — Evidence of prior satisfaction: all three greps return ≥1 hit —
  `git grep -n 'every NON_INNGEST_MONITORS entry names a monitor declared in
  cron-monitors.tf' -- apps/web-platform/test/`,
  `git grep -n 'GHA schedule cron ↔ monitor crontab parity' --
  apps/web-platform/test/`, and `git grep -n 'Watchdog dispatch clock parity'
  -- apps/web-platform/test/` — and `git grep -c 'type = "interval"' --
  apps/web-platform/infra/sentry/cron-monitors.tf` returns 0 (the Non-Goal
  leg's condition remains unsatisfiable).
- [ ] **AC5** — Diff scope: `git diff --name-only origin/main...HEAD` outside
  `knowledge-base/project/` touches only
  `apps/web-platform/test/server/inngest/function-registry-count.test.ts`
  (three-dot merge-base form per the diff-scope convention; pipeline-written
  artifacts under `knowledge-base/project/{plans,specs}/` are the only
  permitted additions).

## Test Scenarios

- **Given** a `NON_INNGEST_MONITORS` entry with no `name =` counterpart in
  `cron-monitors.tf`, **when** the suite runs (c3), **then** it fails and the
  failure output names the entry and prescribes removing it. (`unit`)
- **Given** the committed set (16 entries, every one resolving to a tf
  `name =`), **when** the suite runs, **then** (c3) passes. (`unit`)
- **Given** a new compliant exemption (set entry + matching tf monitor added
  together — mutation-matrix row 4), **when** the suite runs, **then** (c3)
  passes — the guard is not a reject-everything stub. (`unit`)
- **Given** the message change applied, **when** `cd apps/web-platform &&
  ./node_modules/.bin/tsc --noEmit` runs, **then** it exits clean. (`unit`)

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — a CI test-message change on internal
observability machinery.

## Success Metrics

- A tf-monitor deletion PR immediately produces a red required check whose
  output names the stale exemption and tells the author to remove it — no
  tribal knowledge needed to interpret the failure.
- The PR body and issue #8595 close with cited evidence that the remaining
  acceptance criteria were already satisfied on `origin/main` (AC4 greps).

## Dependencies & Risks

- **Risk: rebase drift.** `NON_INNGEST_MONITORS` is hand-maintained and other
  epic PRs add/remove entries; a rebase conflict on the set is possible.
  Mitigation: the edit is one line inside the it-block, not the set literal.
- **Risk: the (d) sibling left un-messaged** — the identical affordance gap
  survives one block away. Recorded as a fold-in candidate; a reviewer can
  extend the diff by one line if judged in-scope.
- **Risk: evidence greps go stale mid-pipeline.** AC4 greps pin the satisfied
  legs; if a sibling PR lands first and removes/renames a describe-block, AC4
  goes red rather than silently losing coverage.
- **Landmines noted (do not apply to this diff, recorded for the implementer):**
  (a) bounding `gh` probes is a class change requiring mock/oracle updates in
  the same PR — not applicable, no probe shapes change; (b) a NEW
  floor-bearing suite would be three write sites (`suite-durations.tsv`,
  `suite-shard-legs.tsv`, `guard-vacuity-floor.test.sh` `PROMOTED_FILES`) —
  not applicable, no new suite is created; (c) `expect(stale).toEqual([])` at
  sibling test (d) shares the missing-message shape — recorded as a descoped
  fold-in candidate, not silently expanded.
- **Pipeline bookkeeping:** `knowledge-base/INDEX.md` regeneration and
  `specs/<branch>/session-state.md` are pipeline-written artifacts covered by
  AC5's knowledge-base carve-out.

## Deepen Pass

Ran 2026-11-01 in-process (this harness has no Agent/Task spawn — the
per-section research and review fan-outs degrade to in-process equivalents;
the residual is recorded in `decision-challenges.md`).

Gate verdicts:

- **4.4 Precedent-diff** — `expect(actual, message)` second-arg form has an
  in-repo precedent: `expect(entry, "#8495: …")` /
  `expect(entry!.intervalMinutes, "#8495: …")` in
  `sentry-monitor-iac-parity.test.ts`; the prescribed message shape matches
  that convention verbatim. Not novel.
- **4.45 Verify-the-negative** — every negative claim was measured at HEAD,
  not asserted: zero stale set entries (set-difference over all 16
  `NON_INNGEST_MONITORS` members vs `name =` attributes in
  `cron-monitors.tf`), zero `type = "interval"` monitors
  (`grep -c 'type = "interval"'` → 0), (c3) presence, both parity
  describe-blocks present.
- **4.5 Network-outage** — no trigger (the only `SSH` hit is a quoted brief
  constraint, not a connectivity symptom).
- **4.55 Downtime & Cutover** — no downtime-inducing operation (test-file
  message change).
- **4.6 User-Brand Impact halt** — PASS: section present, threshold `none`,
  diff path `apps/web-platform/test/…` does not match `SENSITIVE_PATH_RE`.
- **4.7 Observability halt** — PASS: 5-field block present;
  `discoverability_test.command` is `grep`-verbed (allowlisted), contains no
  shell-active characters, finishes in <1 s; `expected_output` is the literal
  `"1"`; no `credentials_required` (so `BASELINE_DECLARED_PROBES` does not
  move).
- **4.8 PAT-shaped variable halt** — PASS: regex sweep clean.
- **4.9 UI-wireframe halt** — no UI-surface file in scope.
- **4.10 Encryption Posture halt** — no `.tf`/migration/store/connection in
  scope.
- **4.11 Guard Contract halt** — PASS: `lint-guard-contract.py` green (1 guard
  entry, 5-row matrix); assembly names the two chokepoints (the set literal
  and `extractTfMonitorNames()`'s parse), not today's member list.
- **4.12 Scope Check halt** — PASS: single unfenced `## Scope Check` (count =
  1), all three subsections, zero `unmapped` rows, one `descoped` row with a
  non-empty justification, `Recommendation:` line present.
- **4.13 Task-Design halt** — no new autonomous-task surface.
- **Suite re-verification** — `vitest run
  test/server/inngest/function-registry-count.test.ts` 13/13 green and
  `vitest run test/server/inngest/sentry-monitor-iac-parity.test.ts` 27/27
  green at HEAD 2026-11-01.

Findings applied: none — the deepen pass produced no new plan items (the
residual was already minimal and every anchor was measured in Phase 0.6/1.7).

## References & Research

- Issue: #8595 (review scope-out of PR #8588; `Re-eval by: 2026-10-06`)
- Epic: #10390; delegation comment:
  `https://github.com/jikig-ai/soleur/issues/10390#issuecomment-6361717901`
- Provenance: PR #9303 / `b2cebec0d6` — added test (c3); #9304 — the monitor
  deletion (c3) was built for; PR #11653 — merged drift satisfying the
  cadence legs; #8450 / #8495 — the parity suites.
- Suites: `apps/web-platform/test/server/inngest/function-registry-count.test.ts`,
  `apps/web-platform/test/server/inngest/sentry-monitor-iac-parity.test.ts`,
  `apps/web-platform/infra/sentry/cron-monitors.tf`.
- Plan-review panel note: this harness has no Agent/Task spawn capability;
  the reviewer fan-out could not run. Gates ran in-process (premise
  validation, scope check, guard-contract lint shape, AC command execution);
  a `pending - assumed:` row in `decision-challenges.md` records the
  residual for the parent pipeline's batched CTO consult.
