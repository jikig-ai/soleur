---
title: "A backlog issue whose code has merged is not closeable until its deploy/activation gate clears"
date: 2026-07-18
category: workflow-patterns
tags: [issue-triage, stale-premise, drift-guard, inngest-cutover, one-shot]
issues: ["#6608", "#6197"]
---

# Learning: merged code ≠ done — a backlog issue closes on its deploy gate, not its merge

## Problem

`/go` was asked to "fix #6608 and #6197" (two pre-cutover hardening items for the dedicated
Inngest host). During the shallow `/go` triage I stated I would "close #6197 as already-delivered"
after verifying its arm64 Vector shipper + `BETTERSTACK_LOGS_TOKEN` code was merged (PR #6209,
hardened #6631, baked into OCI `v1.1.23` #6651). The one-shot planning + review phases then
corrected this: #6197's **code** is merged, but the wiring only takes effect when the dark Inngest
host is **re-provisioned**, which is gated on the HELD Phase-2 cutover (#6178). So #6197 must stay
OPEN as the Phase-2 re-provision tracker — closing on merged-code would have marked undeployed work
as done. A contradictory "close #6197" bullet I wrote into `session-state.md` was caught by the
architecture reviewer.

## Solution / Key Insight

- **An issue's own text describing "remaining work" is a stale claim** (the #6497 stale-premise
  class): a "implement X" backlog item can already be fully delivered by later PRs. Verify against
  the tree before implementing — but ALSO verify the **close-condition** before closing.
- **Merged ≠ deployed ≠ closeable.** For infra/cutover-gated work the close-condition is often a
  post-merge apply/re-provision, not the code merge. Close on the actual gate
  (`hr-before-asserting-github-issue-status`), and when the code is inert-at-merge (excluded from
  per-PR CI `-target`, or delivered via an image the host hasn't rebooted onto), say so and keep the
  tracker open.
- This is also why #6608's PR uses `Ref #6608` (ops-remediation) not `Closes` — the nftables
  re-render only lands at the Phase-2 `inngest-host-replace`.

## Session Errors

1. **SEC-H2 comment reintroduced the removed `10.0.1.11` literal** — the GREEN-phase comment rewrite
   embedded the full `10.0.1.11`, tripping the AC `grep -c '10\.0\.1\.11' == 0`. **Recovery:**
   reworded to the short `.11` form. **Prevention:** when a comment documents a *removed* literal,
   use a non-canonical/short form or drop it — the same file's assertion greps the canonical form
   (`cq-assert-anchor-not-bare-token`).
2. **`session-state.md` "close #6197" contradiction** — wrote a bullet contradicting the
   authoritative plan (keep #6197 open). **Recovery:** corrected to "reconcile only; do not close".
   **Prevention:** the merged≠deployed close-gate rule above; align session-state decisions with the
   plan's explicit close-disposition.
3. **§6b parity-guard greps matched comment lines** (P2, test-design review) — `variables.tf:101`
   documents `# web-2 (fsn1, 10.0.1.11) RETIRED`, one rewrite from injecting `.11` into the
   canonical set → CI would then DEMAND the allowlist re-add the retired host. **Recovery:**
   `sed 's/#.*//'` comment-strip before matching. **Prevention:** already `cq-assert-anchor-not-bare-token`;
   strip comments in any drift-guard grep over a `.tf`/`.yml` that also eulogizes retired values.
4. **Runbook web-2-retired note adjacent to still-live "quiesce web-2 (MANDATORY)" steps** (P2,
   code-quality review) — an operator running the HELD cutover would quiesce a destroyed host.
   **Recovery:** marked step 1a HISTORICAL with a superseded caveat. **Prevention:**
   `cq-ref-removal-sweep-cleanup-closures` — retiring an entity requires sweeping its dependent
   prose across runbooks, not just the config.

All four classes are already covered by existing hard rules; none warrant a new AGENTS.md rule
(always-loaded payload is already at the 22k budget ceiling).
