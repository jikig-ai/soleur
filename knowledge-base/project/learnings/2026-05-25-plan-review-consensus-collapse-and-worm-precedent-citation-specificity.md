---
title: "Plan-review consensus collapse: when 2-of-3 reviewers converge on YAGNI, the cut is signal. Plus: WORM SQL precedent citations must name the exact migration whose pattern is adopted."
date: 2026-05-25
category: workflow-patterns
tags: [plan-review, yagni, scope-cut, worm, supabase-migration, citation-discipline, brand-survival]
module: plan
symptoms:
  - "plan-review DHH + simplicity converge on collapsing N PRs to M with the same root cause"
  - "kieran says plan-shape is solid but flags SQL P0s independently"
  - "operator-override path produces plan that reviewers push back against"
  - "WORM trigger bypass branch silently allows UPDATE because TG_OP check is missing"
  - "retention bypass cites precedent migration that actually uses a different pattern"
related_learnings:
  - 2026-05-22-plan-review-and-deepen-plan-catch-different-issue-classes.md
  - 2026-05-21-plan-review-five-agent-panel-spec-flow-catches-missing-writer-path-and-bool-fallback-collapses.md
  - 2026-05-21-worm-ledger-rls-owner-insert-policy-is-an-rpc-bypass.md
  - 2026-05-15-worm-trigger-blocks-pg-cron-retention-sweep.md
  - 2026-05-18-worm-trigger-bypass-role-check-fails-under-postgrest-routing.md
---

# Plan-review consensus collapse + WORM precedent-citation specificity

Two patterns from the 2026-05-25 plan cycle for umbrella #4456 (`feat-audit-env-flags-flagsmith-policy`).

## Pattern 1: Plan-review consensus as scope-cut signal

### Context

Umbrella #4456 is operator-override of CTO+CPO+CLO triad consensus ("don't migrate today"). Plan v1 sequenced the override into a **6-PR ladder**: PR-1 legal, PR-2 per-org capability standalone, PR-3 WORM standalone, PR-4 team-workspace-invite migration, PR-5 byok-delegations migration, PR-6 dev-signin docs.

Brand-survival threshold: `single-user incident`. Three plan-review agents ran in parallel (DHH, Kieran, Code Simplicity).

### Observed behavior

- **DHH** and **Code Simplicity** **independently** converged on the same scope cut: collapse 6 PRs → 3 PRs by folding per-org capability + WORM table INSIDE PR-2 (with the consumers that need them), not shipping them as standalone scaffolding. Both cited the same YAGNI: per-org Flagsmith capability has zero consumers at the moment its standalone PR would merge; WORM ledger ships before any writer.
- **Kieran** dissented on shape ("plan is solid in shape and well-cited") but independently flagged P0 SQL correctness issues (WORM trigger TG_OP miss + single-trigger BEFORE UPDATE OR DELETE bypass + mig 043 precedent miscite).

The two-class outcome — shape-disagreement vs. tactical-correctness-convergence — is the load-bearing signal. The shape-collapse is **not** unanimous; the tactical SQL P0s **are** uncontroversial.

### Heuristic

> When 2-of-3 plan-review reviewers independently converge on the same scope cut, the cut is signal not noise. When the third dissents on shape but produces uncontroversial tactical findings, apply both: collapse per the 2-of-3, and fix the tactical findings regardless.

This heuristic is asymmetric:
- **2-of-3 on cuts:** accept as signal (operator may still reject — but the default is accept).
- **2-of-3 on additions:** more skeptical — additions tend to be reviewer-shaped opinions; cuts tend to surface YAGNI the planner missed.
- **1-of-3 dissent on shape:** dissent is noise; convergence is signal. (Reviewers operate from different priors; convergence across priors is harder to achieve than consensus among similar priors.)
- **1-of-3 on tactical findings:** judge on merit. SQL P0s, file-path P0s, regex P0s are typically uncontroversial regardless of how many reviewers raised them. Apply.

### Two-stage override authority

The brainstorm-time "operator override of triad consensus" (Phase 1.0.5) and the plan-time "plan-review pushback against the override" form a two-stage gate:

1. **Brainstorm stage:** triad (CTO+CPO+CLO) recommendation; operator can override.
2. **Plan stage:** plan-review agents may push back AGAINST the override; operator can:
   - Fully accept the pushback (revert to triad recommendation)
   - Fully reject the pushback (keep v1 plan as-is)
   - Partially accept (this session — collapse to 3 PRs but keep per-org capability + WORM in scope)

The operator is final authority at both stages. The plan skill should surface the pushback **as a structured choice** (4-option AskUserQuestion in this session), not silently apply or silently ignore.

### Why this matters

In this session, ignoring the convergence would have shipped a 6-PR ladder with two scaffolding PRs that had zero consumers at merge time. The collapse reduced plan-body size ~50%, removed 3 cross-PR coupling boundaries, and dissolved the staleness-anchor risk (each PR planned >30 days out would have needed premise probes per the plan-time Sharp Edge).

Accepting the cuts without question would have stripped the operator's brainstorm-time decision. The structured choice preserved their authority.

## Pattern 2: WORM SQL precedent citations must name the exact migration whose pattern is adopted

### Context

PR-3 (in v1; folded into PR-2 in v2) introduces `flag_flip_audit` WORM ledger. Plan v1 cited "mig 043 precedent" for the `session_replication_role='replica'` retention bypass. Plan v1's SQL sketch also used a single trigger `BEFORE UPDATE OR DELETE` with a bypass branch that did NOT check `TG_OP`.

### Failure mode (caught by Kieran P0-1 + P0-2)

Mig 043 (`tenant_deploy_audit.sql:165-168`) actually uses a **row-state** bypass:

```sql
IF TG_OP = 'DELETE' AND OLD.retention_until IS NOT NULL AND OLD.retention_until < now() THEN
  RETURN OLD;
END IF;
```

The `session_replication_role='replica'` GUC pattern is real in migrations 037 / 044 / 051 / 052 / 053 — but NOT 043.

Combining:
1. Wrong cite ("mig 043 precedent" → mig 043 uses row-state, not GUC)
2. Single-trigger BEFORE UPDATE OR DELETE
3. Bypass branch with no `TG_OP` check

yields a silent UPDATE-via-replica-GUC exploit: a caller who can set `session_replication_role='replica'` (pg_cron typically can) can UPDATE rows because the BEFORE UPDATE trigger fires on UPDATE, hits the `replica` check, and returns `OLD` — silently allowing the UPDATE to proceed. WORM invariant is broken.

The row-state bypass (mig 043 precedent) is narrower because:
- No GUC-setting privilege required
- Only DELETE branch hits the bypass (UPDATE always raises)
- Bypass conditions are visible in the row (`OLD.retention_until < now()`)

### Lesson

> When a plan prescribes a SQL precedent for a WORM/audit table, the citation must name the **exact** migration whose pattern is adopted — not the nearest sibling, not "WORM precedent generally." Read the cited migration's actual implementation to confirm the pattern, the privilege model, and the bypass conditions match.

Distinct from but generalizes prior learnings:
- `2026-05-21-worm-ledger-rls-owner-insert-policy-is-an-rpc-bypass.md` (WORM RLS posture)
- `2026-05-15-worm-trigger-blocks-pg-cron-retention-sweep.md` (retention bypass design — but this learning recommends row-state, not GUC; plan v1's citation contradicted the learning it cited)
- `2026-05-18-worm-trigger-bypass-role-check-fails-under-postgrest-routing.md` (PostgREST routing collapses `current_user='service_role'` checks)

### Companion rules

1. **Two separate triggers, not one.** Mig 043 splits into `tenant_deploy_audit_no_update` BEFORE UPDATE + `tenant_deploy_audit_no_delete` BEFORE DELETE. Single trigger BEFORE UPDATE OR DELETE means one bypass branch covers both operations — TG_OP-less bypass silently allows UPDATE if the branch fires.
2. **Trigger functions need `SET search_path = public, pg_temp` + REVOKE matrix.** Plan v1 omitted both on the trigger fn (had them on the writer RPC only). Mig 043 has both on the trigger fn.
3. **Verify ALL cited learnings recommend the pattern you're proposing.** Plan v1 cited `2026-05-15-worm-trigger-blocks-pg-cron-retention-sweep.md` in support of the `replica` GUC bypass — but that learning actually recommends row-state. The citation should have been a contradiction signal, not a support signal.

## Prevention

For plan-time author discipline:

1. **Before naming a SQL precedent migration**, `cat` the cited file's trigger function and bypass branch. Confirm the pattern (row-state vs GUC vs role-check) matches the proposed code.
2. **Before naming an ADR slot**, `ls knowledge-base/engineering/architecture/decisions/ADR-0*.md | tail -5` to confirm the slot is free. Multiple existing ADRs share numbers, so monotonic-next is the safe default.
3. **Before naming a new audit table**, grep sibling migrations for the audit-table naming convention. Suffix-led `_audit` is this codebase's convention; `_log` is not used for audit tables.
4. **When plan-review produces shape vs tactical findings**, surface both classes separately. Don't bundle a 2-of-3 scope-cut consensus with a 1-of-3 SQL P0 finding — they have different acceptance thresholds.

For plan-review agent prompts:

5. **Plan-review prompts should ask reviewers to verify the precedent migration's actual content**, not just that the citation exists. ("Read mig 043 and confirm the bypass pattern matches the plan's SQL sketch" beats "verify the plan cites a valid precedent migration.")

## Session Errors

1. **ADR-039 naming drift** — brainstorm + spec + umbrella issue all named "ADR-039" without grepping the ADR directory. **Recovery:** corrected to ADR-043 across 4 docs at plan-time. **Prevention:** plan/brainstorm/spec author MUST `ls knowledge-base/engineering/architecture/decisions/ADR-03*.md` before naming any new ADR. Generalizes the existing Sharp Edge "every named repo artifact in a plan MUST be verified against current repo state."
2. **WORM table naming drift** — spec FR7 + AC4 named `flag_audit_log` without checking sibling-migration convention. **Recovery:** renamed to `flag_flip_audit` at plan-write. **Prevention:** before naming a new audit table in a spec, grep `ls apps/web-platform/supabase/migrations/ | grep -E '_audit|_log|_ledger'` and adopt the dominant suffix convention.
3. **Initial 6-PR shape (per-org capability + WORM as standalone PRs)** — plan v1 split capability + audit before any consumer existed. **Recovery:** plan-review DHH + Simplicity convergence → collapsed to 3 PRs. **Prevention:** when a plan introduces capability + consumer in the same umbrella, default to "capability ships with first consumer" unless there's a specific reason to split (e.g., capability is reused by N>1 unrelated consumers, or capability requires its own legal disclosure round).
4. **Mig 043 retention bypass mis-cite** — plan v1 cited mig 043 as `replica` GUC precedent; 043 uses row-state. **Recovery:** Kieran P0-1 caught at plan-review; v2 corrected. **Prevention:** see Pattern 2 above — read the cited migration's actual implementation, not the citation's claim.
5. **Bare-repo CWD attempt** — `git rev-parse --show-toplevel` exit 1 in bare repo. **Recovery:** worked around with absolute paths. **Prevention:** pre-existing constraint documented in `/soleur:go` Sharp Edges ("Bare-repo CWD guard"); no new prevention needed.

## Tags

```
category: workflow-patterns
module: plan
```
