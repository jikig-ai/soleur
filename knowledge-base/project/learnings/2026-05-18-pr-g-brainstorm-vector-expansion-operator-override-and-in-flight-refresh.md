---
title: PR-G brainstorm — read-path vector expansion, operator override + replacement safety primitive, in-flight feature refresh as compute right-sizing
date: 2026-05-18
category: workflow-patterns
tags:
  - brainstorm-skill
  - user-brand-critical
  - vector-expansion
  - operator-override
  - safety-primitive-replacement
  - in-flight-feature-refresh
  - leader-compute-right-sizing
  - cross-domain-lane
  - pr-g
  - pr-3244
related:
  - "#3947 (PR-G issue)"
  - "PR #3984 (PR-G draft)"
  - "#3244 (umbrella)"
  - "PR #3940 (PR-F merged predecessor)"
  - 2026-05-11-bundle-brainstorm-deliberate-revert-and-fixture-source-record
  - 2026-05-12-brainstorm-re-audit-inherited-transparency-surfaces
  - 2026-05-15-brainstorm-enumerate-umbrella-child-prs-before-leader-spawn
---

# Problem

The PR-G brainstorm (2026-05-18, brainstorm of issue #3947 for the agent-runtime umbrella #3244) surfaced three brainstorm-process patterns that the existing brainstorm-skill conventions did not yet name. PR-G follows PR-F (#3940) by one day; the predecessor brainstorm explicitly recommended deferring PR-G's surfaces (scope-grant UX, audit-log viewer, runtime onboarding) and named the user-brand-critical threshold. Without explicit handling of (a) new vector classes that the predecessor's framing did not anticipate, (b) operator overrides of unanimous specialist recommendations, and (c) compute right-sizing when an adjacent plan already carries Domain Review (carry-forward), the brainstorm would have either over-spawned redundant leaders or under-recognized a new safety boundary.

# Patterns

## Pattern 1 — Read-path vector expansion can be invisible to a write-path-framed predecessor

**Observation.** PR-F's brainstorm enumerated four brand vectors: cross-tenant write, BYOK leak via write path, wrong-action triggered, billing surprise. All four were write-path framings — the runtime emits an action that touches user data, then a vector evaluates the action site. PR-G adds an **audit viewer** that reads `audit_byok_use` rows (PR-E's writer table) plus Inngest function executions. The viewer is a NEW read-path tenancy boundary: `audit_byok_use_owner_select` RLS is the only thing between Founder A and Founder B's BYOK history, and a service-role direct read in a server component (a known foot-gun the codebase has paid for in PR-A→C) silently bypasses it.

**Why this is non-obvious.** The brand-survival threshold (`single-user incident`) and the brainstorm doc's User-Brand Impact block are typically inherited verbatim from the predecessor. The threshold IS the same (one mis-tenanted read = brand-ending), but the VECTOR LIST under it changes when the slice introduces a new surface category. Reusing the predecessor's vector list without an explicit "what new surface category is being introduced" pass undercounts the threat surface.

**Pattern.** When a brainstorm slice introduces a categorically new surface (new route, new query path, new UI section reading from a tenant-scoped table), enumerate which of the predecessor's vector classes apply AND ask explicitly: "does this surface introduce a vector class the predecessor did not exercise?" Read-path vs write-path is the canonical split, but the same logic applies to admin-vs-founder, server-vs-client bundle reads, and cross-domain reads (e.g., a CFO surface reading from CMO state).

**Where this lives.** Add a one-line check to `plugins/soleur/skills/brainstorm/SKILL.md` Phase 0.1 (or Phase 0.5 leader prompts): "If the slice introduces a new surface category not exercised by the predecessor, ask the triad to enumerate vector classes for the new surface independently of carry-forward."

## Pattern 2 — Operator override of a unanimous specialist recommendation must name the replacement safety primitive

**Observation.** All three leaders (CPO, CTO) plus the predecessor's PR-F brainstorm posture recommended that PR-G ship with `SOLEUR_FR5_ENABLED=false` and flip the flag in a SEPARATE operator step after BetterStack on-call + synthetic Stripe smoke + first dogfood founder QA. The operator chose "Flip in PR-G" as the merge step. This is a defensible call (single deploy, single QA pass, no inter-PR coordination tax) — but it changes the load-bearing safety primitive: the env flag was the *intended* gate; with the flip-in-PR-G choice, the env flag becomes a global kill-switch and the *per-grant deny-by-default webhook predicate* becomes the load-bearing per-tenant gate.

**Why this matters.** An operator override without a named replacement primitive degrades the threshold silently. "Operator chose differently from specialists" is fine; "operator's choice has no specialist-validated replacement primitive enforcing the threshold" is brand-survival regression. The brainstorm doc MUST identify the replacement primitive in the same paragraph as the override decision.

**Pattern.** When an operator selects an answer that diverges from unanimous specialist recommendation on a brand-survival-threshold decision: (a) record the override explicitly in the Key Decisions table (PR-G K14 cites both the override AND the replacement primitive), (b) require the brainstorm doc's Sharp Edges section to name the replacement primitive, (c) ensure the plan's Test Plan exercises the replacement primitive specifically (PR-G TR3: `flag=true && no scope_grants row → no inngest.send`).

**Where this lives.** Add a Sharp Edges bullet to `plugins/soleur/skills/brainstorm/SKILL.md` Phase 3.5 (capture step): "If a Key Decision overrides unanimous specialist recommendation on a brand-survival-threshold question, the brainstorm doc MUST name the replacement safety primitive in the same Sharp Edges bullet."

## Pattern 3 — In-flight feature refresh is effective compute right-sizing when an adjacent plan carries Domain Review

**Observation.** PR-F merged 2026-05-17 (yesterday); its plan at `knowledge-base/project/plans/2026-05-18-feat-pr-f-inngest-iac-plan.md` carries `## Domain Review` and `## User-Brand Impact` sections. PR-G is the next slice in the same umbrella, with new UX surfaces (scope-grant UI, audit viewer, onboarding explainer). The brainstorm-skill Phase 0.5 step 4 names three options: carry-forward only, focused refresh, full triad spawn.

The operator chose **focused refresh**. Outcome: three triad agents returned narrowly-scoped assessments (≤350 words each) in 60–180 seconds, surfacing one new vector (Pattern 1 above), four new legal-doc deltas (CLO), and concrete substrate verification (CTO grepped `apps/web-platform/` for `scope_grants` and confirmed absence). Full triad spawn would have cost ~5-8 min compute and reproduced PR-F's substrate analysis; carry-forward only would have missed the read-path vector that PR-F could not anticipate.

**Pattern.** When the feature description references an issue with an adjacent plan that already carries `Domain Review (carry-forward)` AND `User-Brand Impact` sections, the focused-refresh option is the default. Carry-forward only is right when the new slice is genuinely isomorphic to the prior slice (same surface category, same vector classes). Full triad spawn is right when the new slice is in a different domain or the prior plan is older than 7 days.

**Heuristic.** Adjacent plan age:
- 0–3 days + same surface category → **carry-forward only**
- 0–7 days + new surface category → **focused refresh** (this case)
- 7+ days OR cross-domain pivot → **full triad spawn**

**Where this lives.** Add the heuristic table to `plugins/soleur/skills/brainstorm/SKILL.md` Phase 0.5 step 4 to make the default deterministic for pipeline/headless mode.

# Why these matter together

All three patterns showed up in one brainstorm because PR-G is the *seventh* slice of a long-running umbrella with a one-day-old predecessor plan and a user-brand-critical threshold. Slices late in an umbrella's lifecycle are where:

- New surface categories sneak in (Pattern 1) — the umbrella has shipped substrate; new slices ship UX, which introduces read/write/admin surfaces the substrate didn't.
- Operator overrides accumulate (Pattern 2) — specialists have already given six rounds of advice; the operator has cumulative context the specialists don't and rationally diverges.
- Adjacent plans pile up (Pattern 3) — the umbrella has 5+ prior brainstorms and plans; full triad spawn for every slice burns compute the operator has already invested in.

Naming these patterns explicitly in the brainstorm skill turns late-umbrella-slice expertise into reusable conventions.

# Session Errors

**worktree-manager.sh feature silently announced "Feature setup complete!" with a non-functional worktree.** — Recovery: removed the broken worktree dir, ran `git worktree prune`, used `git worktree add` directly, committed an empty `chore:` to push the branch immediately. — Prevention: see sibling learning `2026-05-18-worktree-manager-feature-silent-failure-missing-registration-check.md` for the proposed positive-registration check.

# References

- Brainstorm: `knowledge-base/project/brainstorms/2026-05-18-pr-g-cohort-onboarding-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-pr-g-cohort-onboarding/spec.md`
- Issue: [#3947](https://github.com/jikig-ai/issues/3947)
- Draft PR: [#3984](https://github.com/jikig-ai/soleur/pull/3984)
- Predecessor brainstorm (PR-F): `knowledge-base/project/brainstorms/archive/20260517-203729-2026-05-17-pr-f-inngest-trigger-layer-brainstorm.md`
- Predecessor plan (PR-F): `knowledge-base/project/plans/2026-05-18-feat-pr-f-inngest-iac-plan.md`
- Umbrella spec: `knowledge-base/project/specs/feat-agent-runtime-platform/spec.md`
