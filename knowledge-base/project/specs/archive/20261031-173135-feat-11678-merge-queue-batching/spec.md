---
feature: 11678-merge-queue-batching
issue: 11678
lane: cross-domain
brand_survival_threshold: single-user incident
brainstorm: knowledge-base/project/brainstorms/2026-10-31-merge-queue-batching-queue-jump-brainstorm.md
status: draft
---

# Feature: Merge-queue grouping + documented queue-jump path

## Problem Statement

Soleur's `main` merge queue (ADR-270) has two gaps, measured in the 2026-10-30
Dependabot drain (13 bot PRs → 12 merged):

1. **No sanctioned urgency path.** An urgent PR (hotfix, broken-main fix) either
   waits serially (~50 min per `merge_group` entry — #11646 dwelled 3h53m at
   positions 5→2) or merges via `gh pr merge --admin`, which bypasses the entire
   `required_status_checks` rule — no integrated-state CI at all. GitHub's
   native `enqueuePullRequest(jump: true)` keeps the full gate but has no
   sanctioned path to invoke it.
2. **Strictly serial merges.** `max_entries_to_merge = 1` lands one PR per group.
   Per GitHub docs this batches *landings*, not `merge_group` *builds* — so the
   real win is post-merge amortization (push CI / deploy / alert-gate per group)
   plus fewer merge boundaries on burst traffic, not reduced queue wait.

## Goals

- A committed, operator-run **queue-jump script + runbook**: deliberate-act
  trigger, blast-radius disclosure, attribution on the PR timeline, written
  urgency bar — the gated middle tier between queue wait and `--admin` merge.
- **Grouped merges**: `max_entries_to_merge` 1 → 3, executed against ADR-270's
  raise checklist — CLA group enumeration (merge-blocking, fail-closed),
  Guard-2 pin rewrite, ejection-clock + group-ref-shape measurements, canary.

## Non-Goals

- Raising `max_entries_to_build` (separate canary-gated lever; issue non-goal).
- Reintroducing a required `CodeQL` check on `merge_group` (#5840, upstream).
- Per-check duration reduction (#11556 epic).
- Label-triggered jump workflow (deferred; script becomes its core if cadence
  justifies it).
- `min_entries_to_merge` / `min_entries_to_merge_wait_minutes` changes (stay
  1/0 — solo merges never wait; CTO-ruled).

## Functional Requirements

### FR1: Queue-jump script + runbook

- Committed script (home per repo convention — `scripts/` or
  `plugins/soleur/scripts/`; CODEOWNERS explicit row for new load-bearing
  queue machinery).
- Runs under the operator's own `gh` auth; GraphQL `enqueuePullRequest` with
  `jump: true` and `expectedHeadOid` pinned to the PR's current head.
- Reads `mergeQueueEntry` state first: refuses gracefully when the PR is not
  queued (or offers the dequeue + re-enqueue sequence); prints in-flight entry
  count and the rebuild cost (~45 min × N in-progress entries); requires an
  explicit confirmation.
- Leaves an attribution record on the PR timeline (actor + reason).
- Runbook (alongside `merge-queue-canary-log.md` / dequeue reference): trigger,
  urgency bar (prod-down / security / data-loss class), rebuild-cost caveat,
  attribution model, position in the tiered model (queue → jump → `--admin`).
- A `queue-jump` label is NOT created in this scope (script-only trigger).

### FR2: CLA group enumeration (precondition for the raise)

- `scripts/merge-queue-cla-verify.sh` enumerates EVERY constituent PR of a
  merged group (GraphQL `mergeQueue(branch:"main").entries`, positions ≤ the
  named PR's position — the cumulative candidate's contents) and verifies each
  member's head `cla-check` + `cla-evidence` (app 15368) is completed/success.
- Fails closed on enumeration gaps: unparseable group, unresolvable member, or
  `gh` error → post failure and dequeue, never partial success.
- Negative test: green head-PR + red/missing member CLA → must fail.
- `GITHUB_TOKEN` (integration 15368) retained for the synthetic — never an
  App token (ruleset matches 15368).
- Companion updates: `merge-queue-cla-synthetics.yml` comment/contract,
  `merge-queue-cla-verify.test.sh` (ref battery + pass floor), wiring test
  `merge-queue-cla-workflow-wiring.test.sh`, merge-group-coverage fixture.

### FR3: `max_entries_to_merge` raise to 3

- All three parity sources move together: `infra/github/ruleset-ci-required.tf`,
  `scripts/create-ci-required-ruleset.sh`, `infra/github/README.md` params table.
- Guard-2 safety pin in `tests/scripts/test-audit-ruleset-bypass.sh` rewritten
  value-aware (accepts 3, still fails unauthorized values); mutation row
  `T-mq-1.m9` reworked to prove a raise to an *unsanctioned* value goes RED.
- Keep: `SQUASH`, `ALLGREEN`, `min=1`, `wait=0`, `max_build=2`,
  `check_response_timeout=75` (subject to TR2's clock finding).
- Sweep `gh-readonly-queue/main/pr-<N>-` readers (sync-pr-behind.sh,
  monitor-pr-checks.sh, merge-queue-dequeue.md, drain-prs SKILL.md,
  merge-queue-stall-check.yml issue template, test-trio-baseline-census.sh)
  for grouped-ref assumptions; update triage commands where a group's ref no
  longer carries each member's number.
- ADR-270 addendum recording measured group semantics + the jump-path decision
  (not a new ADR).
- CLO addendum on `2026-08-17-clo-ruling-cla-evidence-admin-bypass-7597.md`
  conditioned on merge of the implementing PR.

### FR4: Canary verification (post-apply, agent-run, no SSH)

- First grouped merge: confirm per-PR squash commit shape, push-event count per
  group (dedupe interaction per ADR-276), CLA synthetic coverage on each member.
- Observe first group ejection under ALLGREEN for blast-radius behavior.
- Verify live config: `mergeQueue(branch:"main").configuration` reports
  maximumEntriesToMerge=3.

## Technical Requirements

### TR1: Measurement preconditions (resolve before or inside the PR)

- **`MergeQueueEntry.headCommit` ↔ candidate `head_sha` correlation** — if
  entries sharing `headCommit.oid` are the exact group, use it for enumeration.
- **Grouped `merge_group.head_ref` shape** — does a batched group keep
  `pr-<N>-<sha>` and which member's N? (First live batched queue read.)
- **Ejection-clock origin** — does `check_response_timeout` count from enqueue
  or build dispatch? If from enqueue, deep-queue entries eject healthy; the
  raise must not ship before this is determined.

### TR2: Test/gate updates

- `merge-queue-cla-verify.test.sh`, `merge-queue-cla-workflow-wiring.test.sh`,
  `required-checks-merge-group-coverage.test.sh` + fixture,
  `test-audit-ruleset-bypass.sh` (Guard 2 + mutation rows) — all updated with
  mutation-tested assertions.
- New script: test suite mirroring the merge-queue script conventions
  (fixture battery + assertion floor), registered in `scripts/test-all.sh`.

### TR3: Auth

- Jump script: operator `gh` auth — no new credential surface.
- If a follow-on workflow is ever added: `mint-infra-app-token` with
  `environment: infra-privileged`, permissions re-derived from GitHub's
  endpoint permission table (never `GITHUB_TOKEN` — ADR-285 enqueuer-identity
  failure mode), caller registered per ADR-241 census row G7f.
- CLA synthetic stays on `GITHUB_TOKEN` (15368) — explicitly NOT harmonized.

## Observed Values (verified 2026-10-31)

- Live `mergeQueue` config: maxMerge=1, maxBuild=2, minMerge=1, wait=0,
  ALLGREEN, SQUASH, timeout=4500s — matches tf exactly.
- #11646: armed 15:24:58Z → enqueued 17:00:09Z → merged 20:53:38Z.
- `merge_group` flake rate ~15.4% (37/240); healthy entries merge in 15–18 min.
- gh CLI has no `--jump` flag (v2.103.3); GraphQL `EnqueuePullRequestInput.jump`
  exists; `MergeQueueEntry.jump` field exists.
