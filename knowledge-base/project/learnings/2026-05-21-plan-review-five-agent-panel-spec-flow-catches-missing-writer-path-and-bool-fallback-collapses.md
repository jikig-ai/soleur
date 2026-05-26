---
date: 2026-05-21
category: workflow-patterns
tags: [plan-review, five-agent-panel, spec-flow-analyzer, writer-path, fallback-query, cascade-ordering, aggregate-ac-count]
related_issues: [4078]
related_prs: [4213]
related_learnings:
  - 2026-05-11-five-agent-plan-review-panel-and-architectural-false-trails.md
  - 2026-05-10-plan-phase-order-load-bearing-when-contract-changes.md
  - 2026-05-15-plan-ac-verification-commands-awk-self-match-and-marker-conjunction.md
  - 2026-04-21-agents-md-rule-retirement-deprecation-pattern.md
  - 2026-05-18-worm-trigger-bypass-role-check-fails-under-postgrest-routing.md
---

# Plan-review 5-agent panel: spec-flow catches missing-writer-path; "BOTH panels fire" collapses fallback queries; cascade rationales must be re-derived per-cascade

## Problem

PR-I (#4078) plan v1 was reviewed by the 5-agent panel (DHH + Kieran + code-simplicity + architecture-strategist + spec-flow-analyzer) at single-user-incident brand-survival threshold. 22 findings surfaced: 11 cuts (ceremony) + 11 fixes (correctness). Three classes of finding are reusable beyond this PR — each represents a category that v1 review-time hits and earlier-phase research missed:

1. **Missing writer-path (spec-flow P0).** Plan v1 defined an `authorize_template` RPC and an `isTemplateAuthorized` predicate but never wired the RPC into any user flow. Predicate would deny forever for new templates — the feature would be non-functional. Schema-shaped review agents (Kieran, DHH) verified the RPC contract, validated the partial UNIQUE, checked the SECURITY DEFINER pattern — all green. The trap was that none of those checks ask "who calls this from the founder's perspective." Only spec-flow-analyzer's "walk the user journey end-to-end" lens caught it.

2. **Fallback double-query collapses to single-query under BOTH-panels-fire heuristic.** Plan v1 had a primary SELECT returning `null` on deny + a fallback SELECT to recover `DenyReason` granularity. Four reviewers fired on the same scope: DHH P0 ("just return the row and branch in TS"), code-simplicity P0 ("premature optimization"), Kieran P1 ("fallback doesn't compute `sends_used` cleanly"), architecture-strategist P2 ("needs a non-partial index for the fallback path"). The "both panels fire" rule per `2026-05-11-five-agent-plan-review-panel-and-architectural-false-trails.md` says: when the simplification panel AND the correctness panel BOTH fire on the same scope, prefer delete over fix. v2 collapsed to a single SELECT returning the row + computed flags (`expired`, `quota_exhausted`) + TS branching. Eliminated the second query AND the index need.

3. **Cascade ordering rationale paraphrased instead of re-derived (Kieran P1).** Plan v1 said "FK ON DELETE RESTRICT requires this ordering" — copied from the sibling `anonymise_action_sends` → `anonymise_scope_grants` rationale in PR-H. But PR-I's RPCs UPDATE rows (anonymise zeros `user_id`, doesn't delete), and `ON DELETE RESTRICT` does NOT fire on UPDATE. The real reason ordering matters is semantic — `dsr_erasure` `revocation_reason` must be set on child rows BEFORE the parent grant's `user_id` is nulled, or the Art. 5(2) accountability attribution chain breaks. Inheriting cascade ordering from a sibling cascade without re-deriving the reason is the trap.

## Solution / Reusable Patterns

### Pattern 1 — At single-user-incident threshold, plan-review MUST include spec-flow-analyzer in the 5-agent panel

Already encoded in `plugins/soleur/skills/plan-review/SKILL.md` ("plan declares Brand-survival threshold: single-user incident → also include architecture-strategist and spec-flow-analyzer in the parallel batch"). PR-I confirms this gate fires correctly and catches a P0 the other four reviewers missed. The reusable insight is **why** spec-flow is non-substitutable at this threshold: schema-shaped reviewers verify contracts; spec-flow verifies user journeys. Both classes can fire P0, and the schema/journey split is orthogonal. **Action:** no skill edit needed — gate works. Document in learnings so future planners trust it.

### Pattern 2 — "Fallback path structurally distinct from happy path" is a redesign signal, not an implementation detail

When a plan introduces a primary path (one SELECT, one schema, one index) and a fallback path (additional SELECT, additional logic, additional index) that exists ONLY to recover information the primary path discarded, the design is wrong. The fallback isn't recovering — it's compensating for an under-specified primary. Collapse: the primary SHOULD return the data the fallback needs.

Concrete pattern from PR-I v2: instead of `predicate returns null → second SELECT recovers granularity`, predicate returns `{ status, ...flags }` from one SELECT, TS branches on the discriminated result. Common path AND deny paths each cost one SELECT.

Generalized signal: if a plan has a non-trivial fallback section, ask "what if the primary just returned the data needed?" The answer is usually "we save a query and remove a code path." **Action:** add to plan SKILL.md Sharp Edges.

### Pattern 3 — Cascade ordering rationale must be re-derived per-cascade

When a plan inherits an ordering pattern from a sibling cascade (`account-delete.ts` already has `anonymise_action_sends → anonymise_scope_grants`; PR-I adds `anonymise_template_authorizations` between them), the rationale that justifies the parent's ordering may not transfer. The most common drift:

- Parent uses `DELETE` → `ON DELETE RESTRICT` enforces ordering.
- Child uses `UPDATE` → `ON DELETE RESTRICT` doesn't fire on UPDATE; ordering must be justified semantically (e.g., Art. 5(2) attribution chain) or by transactional invariants.

Don't paraphrase. Trace the original rationale to its enforcement mechanism, then check whether your operation triggers that mechanism. If not, derive the new reason. **Action:** add to plan SKILL.md Sharp Edges.

### Pattern 4 — Aggregate-count ACs (existing sharp edge) extend to threshold counts

Plan SKILL.md already has a sharp edge for "aggregate numeric targets in ACs must show per-item contributions" (PR #2754 lineage). PR-I v1's AC7 (`grep -c session_replication_role ≥ 2`) was a related-but-distinct miss: the threshold `≥ 2` was a guess; actual literal count is ≥5 (one trigger body + 2 `SET LOCAL` + 2 `RESET` across two anonymising RPCs). The plan must compute the count from per-item contributions, not pick a round number.

This is a tightening of the existing sharp edge: it applies to AC threshold values (`≥ N`, `< N`, `== N`), not just aggregate targets. **Action:** extend the existing sharp edge wording.

### Pattern 5 — WORM bypass mechanism is learning-cited (already established but worth reinforcing)

`2026-05-18-worm-trigger-bypass-role-check-fails-under-postgrest-routing.md` documents that `current_user = 'service_role'` is silently always-false under PostgREST. Mig 050 uses this broken mechanism; mig 051 uses the working `SET LOCAL session_replication_role = 'replica'`. When a new plan adds a WORM trigger needing a bypass, the plan MUST explicitly pick the mig 051 mechanism and cite the learning — not hand-wave "WORM bypass via SECURITY DEFINER."

PR-I v1 didn't make the mechanism choice explicit; reconciliation table in v2 added it. No new pattern needed — this is the existing learning firing in a new context. **Action:** none beyond the existing learning.

## Key Insight

The 5-agent panel at single-user-incident threshold operates as **two orthogonal axes**:

- **Simplification axis** (DHH + code-simplicity): "is this design too complex?"
- **Correctness axis** (Kieran + architecture-strategist + spec-flow-analyzer): "does this design work?"

The "BOTH panels fire → prefer delete" heuristic (`2026-05-11-five-agent-plan-review-panel-and-architectural-false-trails.md`) catches **over-architected designs**. PR-I v1's fallback-query was the canonical case — simultaneously "too complex" and "has 4 specific bugs." Deleting the fallback dissolved the bugs.

But the heuristic is not the only mode. Two other modes the PR-I review exercised:

- **Single-panel correctness P0** (spec-flow caught missing writer-path; the simplification axis had nothing to say about it) → fix as written, not delete.
- **Single-panel correctness P1** (Kieran caught cascade rationale paraphrase) → re-derive, not delete.

A 5-agent panel that produces only "BOTH panels fire" findings is suspicious — it suggests the simplification axis isn't reaching deep enough. The PR-I split (11 cuts + 11 fixes) is approximately the right ratio for a single-user-incident plan: half of findings should be ceremony (cuts), half should be correctness gaps.

## Session Errors

1. **Plan v1 missing writer-path** — `authorize_template` RPC defined but never invoked. **Recovery:** v2 added first-send-IS-authorization (send route auto-calls authorize_template in the same transaction as action_sends INSERT). **Prevention:** confirm spec-flow-analyzer is in the 5-agent panel at single-user-incident threshold (plan-review SKILL.md already enforces this; no change needed). Pattern documented above.

2. **Plan v1 cascade rationale was wrong** — claimed FK RESTRICT enforces ordering when anonymise is UPDATE, not DELETE. **Recovery:** v2 rewrote rationale to semantic Art. 5(2) attribution chain. **Prevention:** plan SKILL.md sharp-edge addition — when inheriting cascade ordering from a sibling cascade, re-derive the rationale.

3. **AC7 threshold too lenient (`≥2` vs actual `≥5`)** — picked a round number without computing per-item contributions. **Recovery:** v2 tightened to `≥5` with per-item enumeration in the AC description. **Prevention:** plan SKILL.md sharp-edge extension — aggregate-count rule applies to AC threshold values, not just aggregate targets.

## Cross-References

- `knowledge-base/project/plans/2026-05-21-feat-pr-i-template-authorizations-plan.md` — the plan that surfaced these patterns (v1 → v2).
- `knowledge-base/project/learnings/2026-05-11-five-agent-plan-review-panel-and-architectural-false-trails.md` — parent learning for the 5-agent panel + BOTH-panels-fire heuristic.
- `knowledge-base/project/learnings/2026-05-18-worm-trigger-bypass-role-check-fails-under-postgrest-routing.md` — WORM bypass mechanism choice (Pattern 5).
- `plugins/soleur/skills/plan-review/SKILL.md` — already enforces 5-agent panel at single-user-incident threshold; this learning validates the gate.
- `plugins/soleur/skills/plan/SKILL.md` — target for Pattern 2 + Pattern 3 + Pattern 4 sharp-edge additions (routed below).
