---
date: 2026-05-22
module: plan
problem_type: workflow_pattern
component: review_layering
severity: high
tags: [plan-review, deepen-plan, single-user-incident, layered-review, brand-survival]
synced_to: []
related:
  - knowledge-base/project/learnings/workflow-patterns/2026-05-22-brainstorm-cto-must-grep-not-estimate-call-sites.md
  - knowledge-base/project/learnings/2026-05-15-brainstorm-leader-research-sequencing-and-prior-art-cwd.md
  - knowledge-base/project/learnings/2026-05-12-type-widening-cascades-and-write-boundary-sentinels.md
  - knowledge-base/project/plans/2026-05-22-feat-byok-delegations-pr-a-plan.md
---

# Plan-Review and Deepen-Plan Catch Categorically Different Issue Classes at Single-User-Incident Threshold

## Problem

The `/soleur:plan` skill runs `plan-review` (DHH + Kieran + Simplicity) automatically. The ultrathink mode additionally auto-invokes `deepen-plan` which runs domain-specific agents (data-integrity-guardian + security-sentinel + architecture-strategist). At single-user-incident brand-survival threshold, an implicit assumption is that plan-review's 3-agent panel is sufficient quality control. That assumption is **wrong** — deepen-plan's domain agents catch a categorically different class of issues that plan-review structurally cannot.

Concrete evidence from PR-A `byok-delegations` (#4232) plan in this session:

**Plan-review v2 (DHH + Kieran + Simplicity) caught 12 findings** — mostly about scope/YAGNI/style/code-organization:

- Two-form RPC YAGNI (drop `_as_self` for PR-A)
- Sibling-class fan-out (collapse to abstract base)
- Test file count (8 → 3)
- Inline SQL in plan body bloat
- Phase count (13 → 8)
- Rolling 24h cap window (matches existing idiom)
- WORM Shape 1' member-departure variant (collapse via OLD.user_id)
- pg_default_acl audit scope (fold to single assertion)
- Drop expires_at column (debatable; not applied)
- Sharp Edges trim (3 generic cut)
- TaskUpdate `taskId` validation (not applicable)
- Inline SQL bodies trim

Operator chose "Apply all"; plan v2 written.

**Deepen-plan v3 (data-integrity-guardian + security-sentinel + architecture-strategist) caught 7 P0 architectural issues plan-review missed entirely:**

1. **Cap-check concurrency hole** (DIG F4) — separate `check_byok_delegation_cap` + `write_byok_audit` RPCs allow two concurrent turns to both pass SUM=$15 vs $20 cap then both write $10 → $25 total. Fix: merge to single atomic RPC under one FOR UPDATE row lock.
2. **`now()` vs `clock_timestamp()`** (SS F1) — `now()` is transaction-start; long-running txn opened pre-revoke commits cap-check post-grace and sees "within grace" wrongly. Fix: `clock_timestamp()` for absolute-time comparisons.
3. **Resolver wrong-workspace inference** (DIG F3) — SQL function picks oldest workspace by `created_at`; for a multi-workspace grantee this maps to the wrong workspace. Fix: take `p_workspace_id` as explicit param; TS layer derives.
4. **Unbounded `daily_usd_cap_cents`** (SS F2) — table CHECK was `> 0` only; admits $10B/day. Fix: CHECK ≤ $10K/day + RPC body guard.
5. **WORM Shape 1 audit-ledger poisoning** (DIG F1) — admin caller can set `revoked_by_user_id` to arbitrary UUID. Fix: add `revoked_by_user_id IN (grantor, grantee, created_by)` attribution constraint to Shape 1.
6. **No per-founder brake on delegated path at single-user threshold** (Arch A1) — PR-A's delegated path had NO hourly brake; runaway loop spends full daily cap. Fix: add `hourly_usd_cap_cents` column + check in same RPC (defaults daily/4).
7. **Missing reconciliation column** (Arch A2) — without `audit_byok_use.attribution_shift_reason`, the eventual reconciliation flow has no data to reconcile from.

PLUS 8 P1 findings (HMAC pepper for Sentry hashes, CLI confirmation prompt, WORM column-enumeration smoke test, etc.).

## Root Cause

**Plan-review and deepen-plan operate on different axes:**

- **Plan-review** (DHH-style, Kieran-style, Simplicity-style) operates on prose-level **style and scope** — over-engineering, YAGNI violations, premature abstraction, scope creep, code-organization issues. The reviewers reason about whether the plan document is *well-shaped*. They don't necessarily simulate the SQL execution model or the security threat model.
- **Deepen-plan** domain agents (data-integrity-guardian, security-sentinel, architecture-strategist) operate on substance-level **correctness and security** — Postgres MVCC semantics, plpgsql edge cases, FK cascade interactions, attack surfaces, secondary brake analysis. They simulate behavior at the database/RPC/security layer.

A plan can be perfectly well-shaped (passes plan-review) AND have a latent SQL atomicity bug, a clock-skew exploit, a wrong-workspace inference, an unbounded cap, or a missing per-founder brake — these are *substance-level* bugs that style-level review structurally cannot catch.

At single-user-incident brand-survival threshold, missing ANY of these substance-level findings is a brand-survival regression class. The cap-check concurrency hole alone would allow Jean's $20 cap to bill $40 under concurrent turns. The wrong-workspace resolver would silently use Alice's key for Harry's runs in OrgB. These are not nice-to-have findings; they are existential at this threshold.

## Solution

**At single-user-incident threshold, BOTH plan-review AND deepen-plan are necessary.** Neither subsumes the other.

Workflow implication for `/soleur:plan` skill:

1. **Plan-review always runs** (existing default). Catches style/scope issues.
2. **Ultrathink auto-invokes deepen-plan** (existing default when user passes "ultrathink"). Catches substance issues.
3. **At single-user-incident threshold, ultrathink should be STRONGLY recommended** — not optional. The plan skill should:
   - Detect `brand_survival_threshold: single-user incident` in the plan frontmatter
   - If detected AND ultrathink was NOT used, prompt the user before completing: "Plan is at single-user-incident threshold. plan-review caught style issues; deepen-plan catches substance issues. Recommend running deepen-plan before /work. Run now?"

This is the workflow-pattern learning. The substance findings from deepen-plan are not "nice-to-have polish" — they are load-bearing correctness/security checks that plan-review is structurally blind to.

## Prevention

Two enforcement layers:

1. **Plan skill addition** (Sharp Edges entry): When the plan body declares `brand_survival_threshold: single-user incident`, the plan skill at exit-gate time MUST recommend ultrathink/deepen-plan if not yet run. This catches the workflow gap at the cheapest enforcement point.

2. **Operator-facing principle** (this learning + brainstorm 0.5 routing): both plan-review and deepen-plan are necessary at high brand-survival thresholds. The cost (~10 minutes additional review time per plan) is trivial compared to brand-survival regression cost.

## Session Errors

1. **Inline halt-gate script false-positive FAIL** (4.8 PAT check) — `&& ... ||` chaining returned "FAIL" when `$HITS` was empty because the right-hand-side of `||` evaluated as the failed branch. **Recovery:** re-ran with explicit `if [ -z "$VAR" ]; then ... else ... fi`. **Prevention:** for one-shot shell verifications, prefer explicit if/else over `&&||` — `&&||` silently swaps success/failure semantics on empty-string or zero-length output.
2. **TaskCreate `subagent_type` validation error** — passed the field intended for Agent tool. **Recovery:** removed the field; rest of TaskCreate calls succeeded. **Prevention:** TaskCreate accepts only `subject/description/activeForm/metadata`. Don't conflate tool param schemas.
3. **YAML field-grep regex underspecified** — first regex returned 0 fields for the Observability section because the YAML had no leading whitespace and my regex required `^(  )?`. **Recovery:** corrected to flexible leading-whitespace + re-ran. **Prevention:** YAML schema validation belongs in a yaml-parse, not regex. For inline scripts, accept both flush-left and indented forms.

## Cross-References

- `2026-05-22-brainstorm-cto-must-grep-not-estimate-call-sites.md` — sibling workflow learning from the same byok-delegations brainstorm/plan cycle (CTO subagent prompt quality).
- `2026-05-15-brainstorm-leader-research-sequencing-and-prior-art-cwd.md` — reconciliation rule between leader and research findings.
- `2026-05-12-type-widening-cascades-and-write-boundary-sentinels.md` — write-boundary sentinel sweep as a separate enforcement layer.
- Source plan: `knowledge-base/project/plans/2026-05-22-feat-byok-delegations-pr-a-plan.md` v1 → v2 → v3 progression.
- Brainstorm: `knowledge-base/project/brainstorms/2026-05-22-byok-delegations-brainstorm.md`.
