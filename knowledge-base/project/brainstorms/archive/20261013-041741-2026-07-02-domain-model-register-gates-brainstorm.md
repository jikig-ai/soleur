---
date: 2026-07-02
topic: Mechanical enforcement gates for the domain-model register
issue: 5871
branch: feat-domain-model-register-gates
pr: 5895
lane: cross-domain
brand_survival_threshold: single-user incident
status: brainstorm-complete
---

# Brainstorm: Mechanical enforcement gates for the domain-model register (#5871)

## What We're Building

Mechanical enforcement so the domain-model register
(`knowledge-base/engineering/architecture/domain-model.md`) can't silently drift
when a PR changes a business rule (an entity invariant, ownership/access model, or
relationship encoded in a migration constraint / RLS policy / resolver-guard).

The register's own maintenance contract names three fast-follow gates "not yet
mechanically gated": **plan-time flagging**, a **review drift-check**, and a
**ship block** — all tracked here in #5871. #5754 shipped the reusable primitive
they consume: the deterministic analyzer `scripts/domain-model-drift.sh`, whose
`drift` mode exits **1** on drift (stale citations or undocumented business-rule
tables), 0 clean, 2 error, 3 secret-refuse.

**Chosen scope (Approach A):** one real blocking gate + two advisory reminders.

1. **Analyzer false-positive fix (hard prerequisite).** `drift` exits 1 on clean
   `main` today because the undocumented-table extraction captures the *schema
   qualifier* — `.anchor | capture("› (?<t>[^.]+)\\.")` grabs `public` from an
   anchor like `migration › public.workspaces` instead of the table name
   (`scripts/domain-model-drift.sh:167`). Fix the capture to take the table
   segment (strip a leading `public.` / grab the post-`.` token). Without this,
   any blocking gate red-walls every PR.
2. **Ship block — preflight `Check 11` (the one real enforcement point).**
   Diff-scoped: fast-path SKIP unless the PR diff touches a business-rule surface
   (`supabase/migrations|app/api|lib/(auth|byok|stripe|supabase)`), reusing the
   cached diff classifier `$PREFLIGHT_TMP/preflight-diff-files.txt`
   (`preflight/SKILL.md` Step 0.1). When it fires, run `drift` and gate on the
   exit code. Ship's Phase 5.4 already invokes preflight and halts on FAIL, so the
   "ship block" needs **zero extra wiring** in the ship skill.
3. **Review drift-check — advisory review comment.** A new conditional gate in
   `review/SKILL.md` Conditional-Agents block (same diff predicate) that runs
   `drift` and surfaces stale/undocumented rows as review feedback. Advisory, not a
   second blocker — early feedback for the author.
4. **Plan-time flag — advisory reminder.** In `plan/SKILL.md` Phase 0.6
   (Premise Validation): when the feature touches migration/RLS/guard surfaces,
   remind the planner to update the register / re-run `/soleur:sync domain-model`.
   No diff exists at plan time, so this is a soft nudge, never a gate.

**Rollout:** advisory-first, then block. After the FP fix, ship the preflight
check as a warning; flip to hard FAIL once it's proven clean on `main`.

## Why This Approach

- **YAGNI — one signal, one blocker.** The review drift-check and ship block are
  the *identical* primitive (run `drift`, read exit code). Building two independent
  blockers doubles maintenance for one signal. One blocking chokepoint at
  preflight (which ship consumes) + a soft advisory copy at review captures the
  contract's intent without duplication. (CTO assessment; learnings
  `2026-03-25-plan-review-simplifies-gate-design.md`.)
- **Diff-scope the gate, not the analyzer.** The analyzer has no `--since`/`--path`
  mode and adding one is net-new engine work. Instead the *gate* checks the diff
  path-set first and only runs the whole-register `drift` when a business-rule
  surface changed. A docs-only PR never triggers it — structurally eliminating the
  "unrelated PR blocked by pre-existing drift" failure mode.
- **Deterministic-first (ADR-076).** The gate runs the bash analyzer in the
  detection path; no LLM. Byte-identical re-runs → CI-gateable.
- **Fix the FP before blocking.** Invariant gates should fail-closed
  (`2026-04-27-preflight-security-gates-skip-vs-fail-defaults.md`), but a gate that
  fails on a parser false-positive is fail-noisy, not fail-closed. The `public`
  FP is the true sequencing blocker — **not** the #5882 backlog, which is CLOSED
  and drained.

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| How many gates | One blocking (preflight) + 2 advisory (review, plan) | YAGNI; contract's 3 gates without 2 blockers on one signal |
| Enforcement home | preflight `Check 11`; ship inherits via Phase 5.4 | Zero duplication — ship already halts on preflight FAIL |
| Diff-scoping | Gate-side path predicate (reuse preflight diff cache) | Avoids blocking unrelated PRs; no analyzer change |
| Analyzer FP fix | In-scope, prerequisite step | `public` schema-qualifier mis-capture; blocks clean main today |
| Blocking posture | Advisory-first → flip to block after green-on-main soak | Safe against residual parser quirks |
| Review gate | Advisory comment, not a blocker | Early feedback; the preflight block is the enforcement |
| Plan gate | Advisory reminder in Phase 0.6 | No diff at plan time; theatre as a blocker |

*Approach A + advisory-first rollout were the recommended defaults; auto-selected
when the operator was away. Overridable at plan time.*

## Open Questions

1. **Exit-2 (error) / exit-3 (secret-refuse) handling.** Should the preflight check
   FAIL, SKIP, or PASS on analyzer error/secret-refuse? Leaning FAIL on 2 (a gate
   that can't run its check shouldn't fail-open) and treating 3 per the existing
   secret-refuse convention. Resolve at plan time.
2. **Review-gate delivery.** Inline PR comment vs. a section in the review summary —
   pick the lower-friction surface that doesn't duplicate the preflight FAIL text.
3. **Guard-file glob precision.** The business-rule-surface path predicate should be
   validated against the register's actual `Source` column (which migrations/guards
   it cites) so the SKIP fast-path isn't over- or under-inclusive.

## Domain Assessments

**Assessed:** Engineering (CTO). Product (CPO) and Legal (CLO) surface is nil — this
is internal CI/workflow tooling with no user-facing surface, no user data, and no
legal/compliance dimension; the always-on user-brand-critical framing (per #5175) is
recorded below but carries no material CPO/CLO concern.

### Engineering

**Summary:** Build ONE diff-scoped gate at ship/preflight and reuse it as an advisory
review comment; don't build two independent blockers. Diff-scope the gate (reuse
preflight's diff-cache + migration path-gate), not the analyzer. Plan-flag is
advisory-only (theatre as a blocker — no diff at plan time). The sequencing blocker is
the `public` schema-qualifier false positive in the analyzer (not the #5882 backlog,
which is closed) — fix it before any blocking gate goes live. Complexity: small
(wiring, not a new engine). No capability gaps — all four hook points exist and
preflight already owns the diff-cache + path-gate pattern.

## User-Brand Impact

- **Artifact:** the preflight domain-model-drift enforcement check (`Check 11`) and
  its advisory siblings at review/plan time.
- **Vector:** a business-rule change (migration / RLS policy / resolver-guard) ships
  with the register left silently stale, so the register misrepresents the enforced
  data-tenancy / ownership model to a future engineer or auditor who trusts it as an
  access-control reference — a single wrong owner/visibility read can leak or
  wrongly deny one user's data.
- **Threshold:** single-user incident.

*Note: the register is best-effort structural extraction, NOT a security audit or
access-control attestation (ADR-076 completeness disclaimer). The gate enforces
documentation coverage of static structure only; it makes no semantic
access-control-correctness claim.*
