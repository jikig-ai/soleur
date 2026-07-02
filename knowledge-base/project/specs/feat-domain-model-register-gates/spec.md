---
feature: domain-model-register-gates
lane: cross-domain
brand_survival_threshold: single-user incident
status: draft
brainstorm: knowledge-base/project/brainstorms/2026-07-02-domain-model-register-gates-brainstorm.md
issue: 5871
created: 2026-07-02
---

# Spec: Mechanical enforcement gates for the domain-model register

## Problem Statement

The domain-model register (`knowledge-base/engineering/architecture/domain-model.md`)
documents Soleur's business rules (entity invariants, ownership/access models, RLS
policies, resolver-guards). Its maintenance contract requires a PR that changes a
business rule to update the affected row(s) in the same PR, but only the `architecture`
skill's ADR-`create` step enforces this today. The contract itself names three
fast-follow gates as "not yet mechanically gated" — plan-time flagging, a review
drift-check, and a ship block — tracked in #5871. Without them the register silently
drifts: a migration/RLS/guard change can ship while the register keeps describing the
old model, misleading any future engineer or auditor who trusts it.

#5754 shipped the reusable primitive these gates consume: `scripts/domain-model-drift.sh`,
whose `drift` mode exits 1 on drift, 0 clean, 2 error, 3 secret-refuse. The re-evaluation
criterion in #5871 ("build after #5754's drift report ships and is trusted") is met —
#5754 is CLOSED (PR #5869) and the analyzer is dogfooded (#5882, #5883, both closed).

## Goals

- G1: A PR that changes a business-rule surface (migration / RLS policy / resolver-guard)
  cannot merge with the register left drifted — enforced mechanically at ship time.
- G2: The gate never blocks a PR that does not touch a business-rule surface (diff-scoped);
  pre-existing whole-register drift never red-walls an unrelated PR.
- G3: Authors get early, advisory feedback about register drift at review time.
- G4: Planners are reminded to update the register when a change touches a business rule.
- G5: The gate is deterministic (bash analyzer in the detection path; no LLM), so CI runs
  are byte-identical and re-runnable.
- G6: The analyzer no longer reports a false-positive on clean `main` (the `public`
  schema-qualifier mis-capture is fixed as a prerequisite).

## Non-Goals

- NG1: No new detection engine — the gate consumes the existing `drift` mode; no
  `--since`/`--path`/diff mode is added to the analyzer.
- NG2: No semantic access-control attestation. The register + gate cover documentation
  coverage of static structure only (ADR-076 completeness disclaimer stands).
- NG3: No second independent blocker. The review drift-check is advisory; the single
  enforcement chokepoint is preflight (which ship inherits).
- NG4: The plan-time flag is not a blocking gate (no diff exists at plan time).
- NG5: No auto-write to the curated register. Recording rows stays the human-in-loop
  `/soleur:sync domain-model` path.

## Functional Requirements

- FR1 (analyzer FP fix — prerequisite): Fix the undocumented-table extraction in
  `scripts/domain-model-drift.sh` (~line 167) so it captures the table name, not the
  schema qualifier — the `capture("› (?<t>[^.]+)\\.")` grabs `public` from
  `migration › public.workspaces`. After the fix, `drift` exits 0 on clean `main`.
  Extend `scripts/domain-model-drift.test.sh` with a schema-qualified-anchor fixture.
- FR2 (ship block — preflight `Check 11`): New preflight check that fast-path SKIPs
  unless the cached diff path-set (`$PREFLIGHT_TMP/preflight-diff-files.txt`) matches
  the business-rule-surface predicate; when it fires, runs `drift` and maps exit code to
  result (0→PASS, 1→FAIL). Ship's Phase 5.4 already halts on preflight FAIL — no ship
  skill edit needed.
- FR3 (review drift-check — advisory): New conditional gate in `review/SKILL.md`
  Conditional-Agents block, same diff predicate, runs `drift` and reports stale/undocumented
  rows as advisory review feedback (never a blocker).
- FR4 (plan-time flag — advisory): In `plan/SKILL.md` Phase 0.6, when the feature touches
  migration/RLS/guard surfaces, remind the planner to update the register / re-run
  `/soleur:sync domain-model`.
- FR5 (rollout): Ship FR2 advisory-first (WARN, non-blocking); flip to FAIL after it is
  proven clean on `main`. Track the flip as a phased AC, not a separate issue.

## Technical Requirements

- TR1: Business-rule-surface path predicate (starting point, validate against the register's
  `Source` column): `(^|/)(supabase/migrations/.*\.sql|app/api/.*|lib/(auth|byok|stripe|supabase)/.*)$`.
- TR2: preflight `Check 11` reuses the Step 0.1 diff-cache SSOT; it does not recompute the diff.
- TR3: `drift` is invoked exactly as the sync path does:
  `bash scripts/domain-model-drift.sh drift --repo . --register knowledge-base/engineering/architecture/domain-model.md`.
- TR4: Exit-code mapping — 0→PASS, 1→FAIL (advisory: WARN), 2 (error)→FAIL (a gate that
  can't run must not fail-open), 3 (secret-refuse)→follow existing secret-refuse convention.
  Confirm 2/3 handling at plan time (Open Question 1).
- TR5: Deterministic — no LLM in the check path; the LLM only phrases advisory review output.

## Open Questions (carry to plan)

1. Exit-2/exit-3 preflight semantics (FAIL vs SKIP).
2. Review-gate delivery surface (inline comment vs review-summary section) without duplicating
   the preflight FAIL text.
3. Guard-file glob precision — validate TR1 against the register's actual `Source` citations.

## User-Brand Impact

- **Artifact:** the preflight domain-model-drift enforcement check (`Check 11`) + advisory
  siblings at review/plan time.
- **Vector:** a business-rule change ships with the register silently stale, so it
  misrepresents the enforced data-tenancy / ownership model to a future engineer/auditor —
  a single wrong owner/visibility read can leak or wrongly deny one user's data.
- **Threshold:** single-user incident.
