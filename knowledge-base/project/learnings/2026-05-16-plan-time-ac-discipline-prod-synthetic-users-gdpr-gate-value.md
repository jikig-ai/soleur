---
title: Plan-time AC discipline + prod synthetic-user testing is a `hr-dev-prd-distinct-supabase-projects` violation + gdpr-gate Phase 2.7 catches what brainstorm misses on single-user-incident threshold
date: 2026-05-16
category: workflow-issues
tags:
  - plan-skill
  - plan-review
  - acceptance-criteria
  - prod-safety
  - hr-dev-prd-distinct-supabase-projects
  - gdpr-gate
  - brand-survival-threshold
  - dhh-rails-reviewer
  - kieran-rails-reviewer
  - pr-d
  - pr-3244
related:
  - "#3244 (umbrella)"
  - "PR #3883 (PR-D draft)"
  - "PR #3854 (PR-C merged precedent)"
  - 2026-05-16-brainstorm-verify-register-citations-and-adjacent-silent-failures
  - 2026-05-13-helper-migration-must-preserve-operator-dashboard-message-strings
  - 2026-05-10-plan-phase-order-load-bearing-when-contract-changes
---

# Problem

PR-D plan session surfaced three distinct plan-time defect classes that the brainstorm + Phase 1.1 research had not caught, and that the parallel DHH + Kieran + Code Simplicity plan-review found at different layers:

**(A) ACs that re-state phase outputs are project-management LARP, not verification gates.** Initial PR-D plan draft contained:
- AC4: "Phase 0.4 SQL spike output is in PR body" — Phase 0.4 *mandates* the output.
- AC5: "Phase 0.5 orphan-path audit query output = 0 OR quarantine plan agreed in PR body" — Phase 0.5 *mandates* this.
- AC8: "Phase 0.6 sentinel sweep output in PR body" — Phase 0.6 *mandates* this.
- AC28: "Stale-comment sweep (Phase 9.2) output captured" — Phase 9.2 *mandates* this.
- AC29: "File follow-up issue [...]" — actionable instruction, not verifiable state.
- AC15: "Allowlist shrink lands as a single dedicated commit" — commit discipline, not a state assertion.
- AC17: "PR description includes [matrix]" — PR-template hygiene.

DHH plan-review correctly flagged these as ceremony. The rule: ACs are *load-bearing verification gates* at PR-review time — every AC must encode a *checkable post-condition* on file state, command output, or merged behavior. ACs that paraphrase phase instructions don't catch defects; they bloat the review checklist and train reviewers to skim.

**(B) Running synthetic-user integration tests against PROD violates `hr-dev-prd-distinct-supabase-projects` and creates DSAR/billing/support residue.** Initial plan AC25 prescribed:

> AC25. `TENANT_INTEGRATION_TEST=1 bun test test/server/attachment-pipeline.tenant-isolation.test.ts` passes against prod RLS.

…which would have created `tenant-isolation-<16hex>@soleur.test` auth.users in PROD on every run. Even with `afterAll` cleanup, a partial-failure path leaves the synthetic users live — visible to:
- DSAR audits (synthetic users count as Article 30 records of processing)
- Billing rollups (if usage events fire before cleanup)
- Support visibility (a test user showing up in customer-search confuses support agents)
- Sentry/Honeycomb dashboards (synthetic-user events become noise)

Kieran plan-review caught this as P1. The correct shape: replace integration-test run in PROD with **read-only `pg_policy` shape check + dry-run RLS predicate eval inside BEGIN/ROLLBACK**. The full integration suite stays DEV-only.

**(C) `gdpr-gate` Phase 2.7 catches what brainstorm + Phase 1.1 research miss when brand-survival = `single-user incident`.** The PR-D brainstorm did extensive research (5 agents in parallel: CTO/CLO/CPO triad + repo-research + learnings-researcher). The Phase 1.1 research at plan time spawned 4 more agents (repo-research-analyst + learnings-researcher + framework-docs-researcher + functional-discovery). Despite this thorough coverage, gdpr-gate at Phase 2.7 produced THREE fold-in items NONE of those nine agents surfaced:

1. **TS-05** (Phase 2.5 cleanup): Storage bytes do NOT cascade with `auth.users` FK — the `afterAll` cleanup needed an explicit `service.storage.from("chat-attachments").remove([victimPath, ...])` call. None of the research agents traced the cleanup chain.
2. **DL-04** (DSAR regression): NG2 keeps `dsar-export.ts:515` on service-role; the tenant-RLS tightening could regress the export path if a future migration touched it. Added as pre-merge AC20a (dev-env DSAR smoke).
3. **Art. 9 §1** (AUP follow-up): The existing chat-attachments bucket has been live since migration 019 without an Article 30 disclosure. The plan's PA2 amendment closes that gap, but the **Acceptable Use Policy** also lacks a warning against uploading Art. 9 special-category data. Filed as follow-up issue at Phase 9.2.

The gate's value-add scales with brand-survival threshold: at `single-user incident`, the marginal cost of gdpr-gate's compliance-shaped lens is justified; at `aggregate pattern` or `none`, the gate's findings are mostly noise that the standard review pipeline catches.

# Root cause

**Class (A) — AC discipline.** The plan template invites the author to fill in every phase with at least one AC. Authors comply by paraphrasing phase outputs, producing ACs that "feel comprehensive" but verify nothing the phase itself doesn't already mandate. Plan-reviewers (DHH-class) catch this because they read the AC list against the phase list and see the duplication. The defect class doesn't fire if the plan-skill's own template enforces AC = post-condition, not = phase-output-paraphrase.

**Class (B) — Prod synthetic-user testing.** AGENTS.md hard rule `hr-dev-prd-distinct-supabase-projects` exists, but the plan-skill author's mental model of "verify in prod" defaulted to "run the same test suite" rather than "run a strictly read-only check". Plan-review (Kieran-class verifier discipline) caught it because the verifier traces the AC's actual effects in PROD. The class can be plan-time defended by adding to plan-skill Sharp Edges: any AC running test integration suites against PROD must be flagged for explicit `read-only` annotation.

**Class (C) — gdpr-gate value vs other research.** Research agents (repo-research, learnings-researcher, framework-docs-researcher) look at code/docs/conventions; they don't have a compliance taxonomy. gdpr-gate has a Layer/article taxonomy (AP-01..AP-07, T-01..T-06, DL-01..DL-06, etc.) that catches different defect classes. The classes are orthogonal: research agents catch architectural/runtime defects; gdpr-gate catches Art. 9 column-name matches + retention + lifecycle + transparency surfaces.

# Solution

Three plan-skill defenses:

**(A) AC = load-bearing verification gate.** Add to `plugins/soleur/skills/plan/SKILL.md` Sharp Edges:

> Acceptance Criteria are load-bearing post-condition gates at PR-review time, not phase-output audits. Every AC must encode a *checkable post-condition* on file state, command output, or merged behavior. ACs that paraphrase phase instructions ("Phase X output captured") are ceremony; cut them. If a phase produces an output, the phase mandates it; the AC verifies the output's *shape* (e.g., "orphan_count = 0 in PR body"), not its existence.

**(B) Prod-test annotation rule.** Add to plan-skill Sharp Edges:

> Any AC that prescribes running an integration test suite, e2e suite, or any code path that creates synthetic users (auth.users rows, Storage objects, conversation records, billing events) against PROD violates `hr-dev-prd-distinct-supabase-projects`. Replace with a strictly read-only verification: `pg_policy` shape checks, dry-run RLS predicate eval inside `BEGIN; ... ROLLBACK;`, or `gh api`/`doppler secrets get` state probes. Full integration suites stay DEV-only.

**(C) gdpr-gate invocation default.** The plan-skill Phase 2.7 already invokes gdpr-gate when triggers fire. The PR-D session confirms the invocation has tangible value at `single-user incident` threshold; do NOT defer to "next plan" or scope it down. The 3-fold-in pattern is the expected output, not noise.

# Prevention

Three bulleted additions to the plan-skill SKILL.md Sharp Edges — single bullet append per item, well within bounded-surface budget.

# Operator-judgment escalation pattern (separate observation)

When DHH plan-review and Code Simplicity plan-review **disagree** on a scope decision (in PR-D: DHH KEEP pre-PR split for security-review pollution, Simplicity FOLD IN for ~30-line YAML simplicity), the disagreement is a *legitimate plan-time judgment call*, not a defect. The plan-skill's consolidation logic should:

1. **Apply agreements automatically** (3-reviewer consensus = apply without prompting).
2. **Apply Kieran verifier-discipline P1 fixes automatically** (these are correctness gates, not style).
3. **Escalate genuine disagreements to operator** via AskUserQuestion with each option labeled with the reviewer who proposed it + the trade-off.

This pattern was used successfully in PR-D plan: 4 operator escalations (pre-PR split, retry button, phase count, Phase 4.4 mock theater) — all resolved with brief operator decisions. Without this pattern, the plan author would either silently pick one side (drift from reviewer feedback) or apply both sides (incoherent plan).

# Session Errors

Session error inventory: none detected. The plan session was clean — research agents returned, edits applied, commits pushed without retries. The only friction was harness wakeup notifications referencing stale phase prompts (informational, not actionable).

# References

- This session's artifacts:
  - Plan: `knowledge-base/project/plans/2026-05-16-feat-pr-d-attachments-storage-tenant-rls-plan.md`
  - Tasks: `knowledge-base/project/specs/feat-pr-d-attachments-storage-tenant-rls/tasks.md`
  - Brainstorm: `knowledge-base/project/brainstorms/2026-05-16-pr-d-attachments-storage-tenant-rls-brainstorm.md`
  - Draft PR: #3883
- Adjacent learnings:
  - `2026-05-16-brainstorm-verify-register-citations-and-adjacent-silent-failures.md` (same session's brainstorm-phase learning)
  - `2026-05-13-helper-migration-must-preserve-operator-dashboard-message-strings.md` (the message-string-preservation discipline)
  - `2026-05-10-plan-phase-order-load-bearing-when-contract-changes.md` (Phase ordering)
- AGENTS.md rules referenced:
  - `hr-dev-prd-distinct-supabase-projects` (the rule violated by initial AC25)
  - `hr-weigh-every-decision-against-target-user-impact` (the rule that triggered the user-brand framing)
  - `hr-gdpr-gate-on-regulated-data-surfaces` (the rule that fired gdpr-gate at Phase 2.7)
