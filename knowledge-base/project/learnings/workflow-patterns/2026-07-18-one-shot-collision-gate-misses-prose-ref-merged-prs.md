---
title: one-shot collision gate misses merged PRs that referenced the issue via prose Ref (no formal link)
date: 2026-07-18
category: workflow-patterns
tags: [one-shot, collision-gate, github, dispatch-waste, premise-validation, deferred-automation]
---

# one-shot collision gate misses merged PRs that referenced the issue via prose `Ref #N`

## Context

`/soleur:go 6197` routed to `/soleur:one-shot` to "wire the arm64 Vector journal→Sentry
shipper on the dedicated Inngest host." The task was **already fully implemented and merged**
by **PR #6209** (`c890464ce`, 2026-07-07) — the same day #6197 was filed. Every line item was
verifiable on `main`: arch-parameterized Vector install off `VECTOR_CLI_ARCH`
(`inngest-bootstrap.sh:733-737`), the arm64 Vector SHA pinned (`vector.tf:22`
`vector_sha256_arm64`), and `BETTERSTACK_LOGS_TOKEN` provisioned into `soleur-inngest/prd`.
ADR-100:399 records it: **"Phase-1 caveat — RESOLVED (#6197)."** ("Sentry" in the title was
also stale — Vector ships to Better Stack Logs since #4273/#5526.)

The one-shot Step 0a.5 collision gate ran **clean** and did not flag any collision. The
worktree, the draft PR (#6674), and a full `/plan` planning subagent were all spun up before
`/plan` Phase 0.6 premise-validation surfaced the merged state.

## Why the gate missed it (distinct from the 2026-05-29 `--state all` fix)

The 2026-05-29 learning fixed a *state-filter* blind spot (MERGED PRs invisible to
`--state open`). This is a **different** blind spot that survives that fix:

- **PR #6209 referenced the issue via prose `Ref #6197`, not a `Closes`/`Fixes` keyword.**
  GitHub only creates a formal issue↔PR **link** from a closing keyword or a manual sidebar
  link. Prose (`Ref #N`, `Tracked-by #N`) creates no link.
- Consequently **both** gate probes returned empty:
  - Item 1 `closedByPullRequestsReferences` → `[]` (nothing *closed* the issue).
  - Item 3 `gh pr list --search "linked:issue #6197" --state all` → nothing (no formal link
    exists to match, even with the `--state all` fix applied).
- So an already-merged, scope-complete PR was **completely invisible** to a gate whose entire
  job is to catch already-done work. The issue stayed OPEN only because `Ref` (not `Closes`)
  left it un-auto-closed — a common pattern for `deferred-automation` tracker issues.

## Fix

Two-part, both landed in this PR:

1. **Gate hardening (`one-shot/SKILL.md` Step 0a.5 item 3).** For an OPEN issue, in addition
   to the `linked:issue` probe, run a **body-text** probe:
   `gh pr list --search "#<N> in:body is:merged"`. It over-matches (any merged PR that merely
   *cites* #N surfaces), so it is a **surface-for-verification** signal, not an auto-abort:
   interactive names the hits in the AskUserQuestion; headless logs them. The definitive
   discriminator is **scope** (read the surfaced PR's diff), not the link.
2. **Backstop is real and worked.** `/plan` Phase 0.6 premise-validation caught this after the
   gate passed. The premise-validation layer is the reliable defense; the gate probe is a
   cheap pre-worktree filter that should catch the *common* prose-`Ref` case, not the sole line
   of defense.

## Reconciliation action taken

No product-code PR for #6197 (re-implementing merged code = no-op or conflict). Instead:
**closed #6197** as `completed` with a comment citing PR #6209 + the code locations + ADR-100:399,
and explicitly handed the Phase-2 cutover runtime-activation residual to **#6178** (OPEN) +
ADR-100 §Phase-2 so nothing is dropped. #6197's Scope (the IaC wiring) was done; the Phase-2
cutover is a separate deliverable with its own tracker — keeping #6197 open only made its stale
`deferred-automation` title a re-trigger magnet (this run being the proof).

## Takeaway

- A gate that keys on GitHub's *link graph* (`linked:issue`, `closedByPullRequestsReferences`)
  is blind to prose references. When "already done" can be signalled by prose, add a **body-text**
  probe and treat it as surface-for-verification, never auto-abort.
- `Ref #N` (not `Closes #N`) on the implementing PR is the tell for a tracker issue that will
  linger OPEN after its work merges — a re-dispatch magnet. Reconcile (close + hand off residual)
  rather than leaving it to be re-picked.
- Premise-validation (`/plan` Phase 0.6) is the load-bearing backstop; verify a `#N` target's
  scope against `main` before trusting the dispatch, even when the collision gate is silent.
