---
title: Multi-agent review catches stale plan-time RLS-policy enumeration and unreachable user-facing toast (code-traced vs. prose-approved)
date: 2026-05-25
category: best-practices
module: supabase-rls
related_prs: [4418]
related_issues: [3930, 3932]
tags: [multi-agent-review, rls, plan-time-vs-review-time, code-path-tracing, jti-revocation, ux-claim-verification]
---

# Multi-agent review catches stale plan-time RLS-policy enumeration and unreachable user-facing toast

PR #4418 shipped migration 068 (jti-deny RLS predicate + `revoke_jti` RPC +
`my_revocation_status` reader + operator CLI + WS discrimination), closing
issues #3930 + #3932. The plan declared two empirical premises — "19 tenant
tables carry an authenticated PERMISSIVE policy at HEAD" and "the
`revocation_notice` toast surfaces 'your most recent session was revoked,
reason = X' to the affected founder" — that BOTH proved false at PR-author
time. Multi-agent review caught both before merge. The two defects share a
single underlying anti-pattern: **plan-time review approves PROSE claims;
defects only surface when reviewers code-trace the claim end-to-end against
HEAD at review time.**

## Problem

### Defect 1 — Stale plan-time RLS-policy enumeration (silent JTI-bypass)

The plan's §Phase 2 declared "19 tenant tables have ≥1 RLS policy at HEAD"
based on a grep run at plan-write time. The work-skill phase added a
companion `*_jti_not_denied` RESTRICTIVE policy to each of those 19 tables.
But between plan-write and PR-author, two sibling PRs landed new
authenticated policies on tables NOT in the plan's enumeration:

- `public.organizations` (mig 053:159)
- `public.workspace_member_removals` (mig 062:128)

Both were missing from migration 068's RESTRICTIVE-policy sweep. A stolen JWT
could STILL `SELECT` from these two tables after `revoke_jti` had been called,
silently defeating the feature's core invariant for those surfaces.

### Defect 2 — User-facing toast unreachable due to control-flow drift

The plan's `## User-Brand Impact` section claimed: "the `revocation_notice`
toast surfaces 'your most recent session was revoked, reason = X' to the
affected founder." The code did NOT surface this toast in steady state. Two
independent failure modes:

(a) **Cache-hit-deny silently re-mints.** `tenant.ts:756` (cache-hit-deny
path) evicted the denied JTI from the in-process cache and re-minted the
session without throwing. `emitRevocationNotice(userId)` was wired inside the
throw branch only; the cache-hit-deny self-heal path never called it. For
operator-initiated revoke (the canonical user-facing path), the toast NEVER
fired.

(b) **Race between emit and ws.close.** When the throw DID fire (post-mint
race), the code was `void emitRevocationNotice(userId); ws.close()`. The
`void` discarded the Promise; `ws.close()` resolved synchronously; the
WebSocket closed before the toast emit reached the client. The toast was
structurally unreachable in BOTH the steady-state path AND the throw path.

## Root Cause

Both defects share an anti-pattern: **plan-time empirical assertions are
approved at the prose layer ("19 tables", "founder sees toast") without being
code-traced against HEAD at review time.**

- Plan-time grep for RLS policies decays as parallel branches land sibling
  RLS migrations between plan-write and PR-merge. The plan's enumerated
  list is a STARTING HYPOTHESIS, not the canonical work-list.
- Plan-time UX claims describe an intended user experience; the actual code
  path from trigger (`revoke_jti` RPC call) → emitter (`emitRevocationNotice`)
  → consumer (WebSocket client toast) traverses three modules with
  control-flow branches the plan-prose does not enumerate.

Both defects survived plan-time review because every plan-time agent read the
prose ("19 tables", "founder sees toast") and verified it AT THE PROSE LAYER.
None re-derived the canonical RLS-policied-table list, and none traced the
toast emit-call from cache-hit-deny → ws.close ordering.

## Discovery (How Multi-Agent Review Caught It)

### Defect 1: Two orthogonal agents re-ran the grep at HEAD

`data-integrity-guardian` AND `security-sentinel` independently re-ran the
canonical grep against HEAD during review:

```bash
grep -rnE "POLICY.*ON public\.[a-z_]+ .*TO authenticated" \
  apps/web-platform/supabase/migrations/*.sql \
  | grep -oE "ON public\.[a-z_]+" \
  | sort -u
```

Both reported the same 21-table union, intersected against migration 068's
RESTRICTIVE-policy targets, and surfaced the 2 missing tables. Two
independent agents reaching the same answer with the same canonical command
is the falsifying signal — neither echoed the plan's "19" framing.

### Defect 2: Six-agent triangulation on code-path drift

Six orthogonal agents — `architecture-strategist`, `user-impact-reviewer`,
`git-history-analyzer`, `performance-oracle`, `security-sentinel`, and
`pattern-recognition-specialist` — surfaced the toast unreachability with
varying entry points:

- `user-impact-reviewer` named the user vector ("founder receives toast") and
  traced from RPC → ws-handler → WebSocket client, hitting the void+close
  race.
- `architecture-strategist` walked the cache-hit-deny self-heal path and
  noted the missing emit-call.
- `pattern-recognition-specialist` matched the `void promise; ws.close()`
  shape against the known "fire-and-forget vs. await before close" pattern.
- `git-history-analyzer` surfaced that the `emitRevocationNotice` helper was
  added in a sibling commit with NO test exercising the cache-hit-deny path.

The triangulation cost ~6× agent spend but caught a single-user-incident-class
UX gap that 3-reviewer plan-time review approved.

## Solution

### For Defect 1: Re-derive the canonical list at REVIEW time

The review spawn prompts for `data-integrity-guardian` AND `security-sentinel`
were updated to mandate the grep at HEAD:

> "Re-derive the canonical authenticated-policied table list at review time
> via `grep -rnE 'POLICY.*ON public\.[a-z_]+ .*TO authenticated'
> apps/web-platform/supabase/migrations/*.sql` and assert every match has the
> new RESTRICTIVE policy in migration 068. Do NOT trust the plan's enumerated
> count."

The verify-068 sentinel (`apps/web-platform/test/verify-068-jti-deny.test.ts`)
was updated to encode this as a meta-assertion: "every authenticated-policied
table has a matching `*_jti_not_denied` RESTRICTIVE policy." Count widened
from 19 → 21.

### For Defect 2: Code-trace the user-facing claim end-to-end

The review-fix commits added:

- `await emitRevocationNotice(userId)` before `ws.close()` in the throw
  branch (replaces `void`).
- WebSocket readyState gate (`if (ws.readyState === ws.OPEN)`) before emit to
  avoid post-close emit attempts.
- Docblock at `tenant.ts:756` documenting the cache-hit-deny self-heal path
  and why the toast intentionally does NOT fire there (operator-initiated
  revoke surfaces via the `my_revocation_status` reader instead — a different
  user vector).

## Prevention

### Generalize beyond RLS sweeps

Any PR whose plan declares an empirical premise of the form "N items matching
pattern P at HEAD" must have the canonical command for re-deriving N+P in the
review spawn prompt, with explicit instructions NOT to trust the plan's
enumerated count. Examples:

- "19 tenant tables with RLS policies" → grep migrations dir at review.
- "12 callers of `assertWriteScope`" → grep callers at review.
- "8 routes under `/api/auth`" → ls + grep at review.

The plan-time count is a hypothesis; the review-time grep is the work-list.

### Generalize beyond UX toast claims

Any plan section labeled `## User-Brand Impact` / `## User-Facing Claim` /
`## UX Outcome` must have a code-path trace in the spawn prompt: "Trace from
[trigger] → [emitter] → [consumer], enumerating every control-flow branch
between trigger and consumer. Identify any branch where the consumer is NOT
reached." Six-agent triangulation is justified for single-user
incident-class UX claims (brand-survival threshold).

### Plan-quality gate

The plan's `requires_cpo_signoff: true` frontmatter flag, when present, should
mechanically pause the autonomous pipeline before Phase 2 — see Session
Errors #3 below. This is currently advisory metadata; a proposed `/soleur:work`
Phase 0.5 frontmatter check is documented in the deviation analyst phase.

## Session Errors

1. **First `/soleur:one-shot` invocation aborted at Step 0a.5** (closed-issue
   collision) because the bundle context referenced `#3887` (CLOSED) and
   `#3922` (MERGED) as predecessor citations. The Step 0a.5 regex matches any
   `#N` substring regardless of semantic role.
   - **Recovery:** Re-invoked with closed refs scrubbed from prose (replaced
     `PR #3922` with date-anchored phrasing "merged 2026-05-16").
   - **Prevention:** Documented as a separate workflow learning at
     `knowledge-base/project/learnings/workflow-patterns/2026-05-25-one-shot-closed-issue-gate-fires-on-contextual-refs.md`.

2. **Plan-quoted "19 tenant tables" was stale at PR-merge time (off-by-2).**
   - **Recovery:** `data-integrity-guardian` + `security-sentinel`
     independently re-ran the grep and surfaced the 2 missing tables.
   - **Prevention:** Verify-068 sentinel now asserts per-table presence by
     intersecting against the canonical grep. Documented above (§Solution).

3. **`requires_cpo_signoff: true` did not gate the autonomous pipeline.**
   - **Recovery:** Operator manually paused mid-pipeline to confirm scope
     before Phase 2 entry.
   - **Prevention:** Proposed `/soleur:work` Phase 0.5 frontmatter check — if
     the plan declares `requires_cpo_signoff: true`, pause and emit an
     AskUserQuestion gate before entering Phase 2. Routed to the Phase 1.5
     Deviation Analyst for skill-instruction addition (NOT a new hard rule).

## Cross-References

- `knowledge-base/project/learnings/2026-05-10-handshake-schema-drift-and-stale-precondition-budgets.md`
  — PR #3501; same defect class (replicated literals / stale plan-time premise) applied
  to skill-instruction handshakes. Migration 068's stale RLS-policy
  enumeration is the same anti-pattern applied to migrations.
- `knowledge-base/project/learnings/2026-05-11-multi-agent-review-catches-cache-write-back-gap-3-reviewers-convergent.md`
  — PR #3574; three convergent reviewers catching a feature-wiring gap that
  unit tests miss. The PR #4418 toast-unreachability is a new sub-pattern of
  the same class: user-facing UX claims in plans must be code-path-traced
  end-to-end at plan-time, not approved on prose plausibility.
- `knowledge-base/project/learnings/2026-04-15-multi-agent-review-catches-bugs-tests-miss.md`
  — full pattern catalogue.
- `knowledge-base/project/learnings/2026-05-12-multi-agent-review-cross-reconcile-catches-false-positive-high-findings.md`
  — counter-pattern (skip findings without orthogonal corroboration). In
  PR #4418 BOTH defects had ≥ 2 orthogonal corroborators, so the
  cross-reconcile triad confirmed APPLY.
