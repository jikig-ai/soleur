# Brainstorm: Merge-queue grouping + documented queue-jump path (#11678)

**Date:** 2026-10-31
**Issue:** #11678 (OPEN, meta/machinery, milestone Post-MVP / Later)
**Branch:** feat-11678-merge-queue-batching
**Draft PR:** #11681
**Lane:** cross-domain (USER_BRAND_CRITICAL unconditional per #5175)

## What We're Building

Two related pieces of merge-queue machinery, sequenced:

1. **A documented queue-jump path for urgent PRs (Proposal B, ships first).** A committed script + runbook that re-enqueues a queued PR at position 1 via the GraphQL `enqueuePullRequest(jump: true)` mutation — the gated middle tier between "wait in queue" (~50 min/entry serial) and `gh pr merge --admin` (skips all integrated-state CI).
2. **Grouped merges for batchable traffic (Proposal A, gated).** Raise `max_entries_to_merge` 1 → 3 in `infra/github/ruleset-ci-required.tf` behind ADR-270's raise checklist, so bursts (Dependabot drains, follow-through PRs) land in grouped merges instead of strictly serial ones.

## Mechanism Correction to the Issue's Framing (verified against GitHub docs)

**`max_entries_to_merge` batches landings, not builds.** GitHub docs state verbatim: *"Merge limits do not combine `merge_group` builds. Merge limits only affect merges to the base branch once one or more `merge_group` has satisfied build checks."* Under `grouping_strategy = ALLGREEN`, every queued PR still pays its own ~50-min cumulative candidate build, bounded by `max_entries_to_build = 2` (the issue's explicit non-goal).

Measured attribution on #11646 (the issue's motivating datapoint, verified via GraphQL timeline): armed 15:24Z → enqueued 17:00Z (95 min arm→enqueue) → merged 20:53Z (3h53m queue dwell across ~4–5 ahead-entries). That dwell is **build-slot-bound**, not merge-boundary-bound — batching would not have shortened it. A's true win is post-merge amortization (fewer push-CI/deploy/alert-gate runs per landed group) plus fewer merge boundaries — real, but secondary to the issue's framing.

Queue dwell's actual levers remain `max_entries_to_build` (canary-gated; queue is ~22% of runner entitlement per the ejection learnings) and per-check duration (#11556, in flight in a sibling worktree).

## Why This Approach

- **B first:** smallest diff for a real gap. The only sanctioned urgency path today is `--admin` merge, which bypasses the entire `required_status_checks` rule — a jump keeps the full 25-context gate. Script runs under the operator's own `gh` auth (admin ⇒ jump authority by definition) — zero new auth surface, `hr-github-app-auth-not-pat` vacuously satisfied.
- **A second, checklist-gated:** ADR-270's raise checklist (lines 533–541) makes CLA group-enumeration a precondition, and the Guard-2 safety pin (`tests/scripts/test-audit-ruleset-bypass.sh` asserts `max_entries_to_merge == 1` with a mutation row proving parity-preserving raises go RED) must be deliberately rewritten — no silent bump.

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Scope | B + A, sequenced | Operator chose grouped scope; B unblocks urgency today, A gated by checklist |
| Jump trigger | Committed script + runbook | Operator choice. Label→workflow deferred: GITHUB_TOKEN enqueuer identity had a measured failure mode (ADR-285 — zero `merge_group` runs for `github-actions[bot]`-armed entries), needs App mint + labeler-authorization gate + label lifecycle |
| `max_entries_to_merge` | **3** (Ruled by CTO agent) | At measured ~15.4% `merge_group` flake rate, P(group green) ≈ 0.85^N: 3 ≈ 61%, 5 ≈ 44% |
| `min_entries_to_merge` / wait | 1 / 0 (Ruled by CTO agent) | Solo PRs never wait for a batch; grouping stays opportunistic (burst-only benefit, zero cost on singleton traffic) |
| `grouping_strategy` | Keep `ALLGREEN` (Ruled by CTO agent) | `HEADGREEN` lets members merge on the head's cumulative build with no per-PR verification — CLA hole |
| `check_response_timeout_minutes` | 75, pending ejection-clock measurement | Covers p95 44.1 / max 60.5 min; but if the clock counts from enqueue (unverified), deep entries eject healthy — determine origin before raise |
| `max_entries_to_build` | Unchanged at 2 | Issue's non-goal stands; runner-spread risk is the binding constraint |
| Jump audit | Actor + reason recorded on PR timeline (CLO) | "Attributed, deliberate, recorded" — a designed exception of ordering, not a defeat of it |
| Record home | ADR-270 addendum, not new ADR (Ruled by CTO agent) | The raise checklist exists in ADR-270 precisely for this change |

## Open Questions (measurement preconditions for A — all agent-resolvable in plan)

1. **`MergeQueueEntry.headCommit` ↔ candidate `head_sha` correlation** — if entries sharing `headCommit.oid == HEAD_SHA` are the exact group membership, enumeration is one GraphQL read (same surface `merge-queue-stall-check.yml` already uses). Field semantics unverified — one live read settles it.
2. **Ejection-clock origin** — does `check_response_timeout` count from enqueue or from build dispatch? If from enqueue, deep-queue entries eject healthy at 75 min — the drain pathology aggravated. Must be determined before raising.
3. **Grouped `merge_group.head_ref` shape** — `merge-queue-cla-verify.sh` pins `^refs/heads/gh-readonly-queue/main/pr-<N>-<40hex>$` (single PR). Whether a batched group's ref keeps that shape (and for which member) must be measured on a live batched queue; today the regex fails closed → posts failure → ejects the group.
4. **Grouped-merge commit/push shape** — one squash commit per PR is documented; whether grouped merges emit one push event per PR or per group decides the push-CI/dedupe benefit (ADR-276 dedupe keys on identical head SHA — intermediate group members may not match).
5. **Urgency bar wording** — written bar for when jump is legitimate (prod-down / security / data-loss class) vs everyday impatience; belongs in the runbook.

## User-Brand Impact

- **Artifact:** the merge-queue CLA attestation (`cla-check`/`cla-evidence` synthetics) and the queue ordering control.
- **Vector:** worst case — a grouped merge lands code on `main` whose contributor never signed the CLA (silent scope-narrowing of the merge-time license-grant attestation), or a jumped entry silently skips integrated-state verification.
- **Threshold:** `single-user incident`.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering (CTO)

**Summary:** `max_entries_to_merge` batches landings, not builds — A's real win is post-merge amortization. Recommend B (script + runbook) first, then A at max=3 gated by: headCommit-correlation measurement, ejection-clock origin, `merge-queue-cla-verify.sh` enumeration rework (positions ≤ named PR via `mergeQueue.entries` GraphQL), Guard-2 pin + T-mq-1.m9 + DR skeleton + README in one PR, first-grouped-merge canary. Keep ALLGREEN/min=1/wait=0/timeout=75/max_build=2. Ejection blast radius grows with batch size; jump rebuilds every in-progress entry so script prints blast radius + confirm.

### Product (CPO)

**Summary:** The operator's ship cadence is the product — queue dwell taxes the autonomy story. But A doesn't reduce dwell (build-bound); B fills the gap between "wait in queue" and "skip all verification" — a genuinely safer middle tier. Recommended B-lite + A scheduled; operator chose both grouped. Flagged: urgency inflation (jump needs a written bar) and A×B adversarial interaction (jump rebuilds scale with batch size).

### Legal (CLO)

**Summary:** The sharp edge is CLA enforcement under grouped merges — the synthetic verifies exactly one PR per group today, and a raise silently degrades whole-group CLA posture onto the entry-gate premise alone. Requirements: enumerate every constituent PR (MUST, merge-blocking), fail closed on enumeration gaps (MUST), negative test with green head + red member (MUST), keep `GITHUB_TOKEN`/15368 for the synthetic (MUST), CLO addendum on the 2026-08-17 cla-evidence-admin-bypass ruling once enumeration lands (SHOULD, conditioned on merge of the implementing PR). Jump = designed exception: attributed, deliberate, recorded. GDPR gate: likely not triggered unless new record shapes persist actor identity.

## Non-Goals

- Raising `max_entries_to_build` (separate canary-gated lever; issue non-goal retained).
- Reintroducing a required `CodeQL` check on `merge_group` (upstream-blocked, #5840).
- Cutting per-check duration (#11556 epic's lane, in flight).
- A label-triggered jump workflow (script becomes its core if cadence later justifies it).

## Deferred Items

- `max_entries_to_build` raise — re-evaluate only if burst dwell persists post-A, measured against the 22% runner headroom and runner-start spread.
- Label→workflow jump trigger — if jump cadence becomes routine.

## Session Errors

None. All cited issue/PR states verified live (#11678 OPEN; #9454, #11556, #5840 OPEN; #11646 timeline pulled via GraphQL; live `mergeQueue` config read — matches tf values exactly).
