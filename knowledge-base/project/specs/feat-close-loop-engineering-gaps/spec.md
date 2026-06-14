---
feature: close-loop-engineering-gaps
date: 2026-06-14
lane: cross-domain
brand_survival_threshold: single-user incident
status: draft
branch: feat-close-loop-engineering-gaps
pr: 5257
issue: 5269
deferred_issues: [5270, 5271, 5272]
brainstorm: knowledge-base/project/brainstorms/2026-06-14-close-loop-engineering-gaps-brainstorm.md
---

# Spec: Close-Loop Engineering Gaps

## Problem Statement

Many AGENTS.md workflow-gate rules (`wg-*`, `hr-*`) exist as **prose** with **no mechanical
enforcement** (no hook, no CI check, no test). The same classes of mistake recur and are
caught only at human review or post-merge — the engineering feedback loop is *open*. Adding
more prose rules is not a viable fix: the rule budget is capped
(`wg-every-session-error-must-produce-either`, #2865: "4.7 rules/day consumed the 100→115
raise in 2 days"). The loop closes only by converting prose gates into self-enforcing
mechanisms, which consumes zero rule budget.

## Goals

- G1. Ship a **reusable enforcement-harness pattern** (mirroring the existing `*.sh` +
  `*.test.sh` paired-hook / `pr-quality-guards.yml` CI conventions) so future workflow gates
  become config instances rather than bespoke code.
- G2. Close **Gap 1 (artifact format-contract)**: a CI/vitest check that validates required
  artifact shape regardless of authorship, catching hand-authored skill-bypass at CI.
- G3. Close **Gap 3 (sweep-completeness)**: a CI check that fails a PR editing one member of a
  registered sibling-set while leaving a registered sibling untouched.
- G4. Both gates deterministic (no LLM judgment) → no false-positive friction operators route
  around.

## Non-Goals

- NG1. **No new AGENTS.md prose rules** (budget-capped; mechanism only).
- NG2. **Gaps 2, 5, 6 — out of scope** (LLM-judgment gates; belong in agent prompts, not
  deterministic checks). Tracked as a deferred re-eval issue.
- NG3. **Gap 4 (operator-only Playwright evidence) — out of scope** this PR (only partially
  deterministic). High user-impact; first reuse candidate after harness lands.
- NG4. **Gap 7 (skill runtime-premise validation) — out of scope** (too heterogeneous).
- NG5. Not co-located under #5212 (distinct marketing topic).

## Functional Requirements

- FR1. **Enforcement harness.** A reusable substrate (shared test/CI helper or paired-hook
  template) with its own `*.test.*` coverage, following the in-repo pair convention. New gates
  register via config, not new harness code.
- FR2. **Gap 1 — format-contract gate.** Given a registry of artifact classes (file glob +
  required-shape schema: frontmatter fields, exact headings, absolute-URL rules), fail CI when
  a `status: scheduled|draft` artifact of a registered class violates its schema, regardless
  of who authored it. Seed classes from documented bypass evidence; extend
  `distribution-content-format.test.ts` precedent rather than re-inventing.
- FR3. **Gap 3 — sweep-completeness gate.** Given a registry of sibling-sets, compute
  `edited = git diff --name-only base...HEAD`; for any registered group with a non-empty
  intersection with `edited`, fail when `group ⊄ edited` (a sibling was left untouched).
  Emit the specific missing sibling(s) in the failure message.
- FR4. **Registries are explicit and committed** (not pure inference) to guarantee zero false
  positives. Naming-convention auto-pairing MAY supplement but not replace the explicit list.
- FR5. **Failing-test-first.** Each gate ships with a RED test proving it catches the exact
  recent session-error case it targets (see TR3).

## Technical Requirements

- TR1. Host on proven surfaces only: `.claude/hooks/` paired convention,
  `.github/workflows/pr-quality-guards.yml` CI lane, and/or vitest under
  `plugins/soleur/test/`. No new service, data model, or trust boundary (no
  `/soleur:architecture` needed).
- TR2. Deterministic execution only — no network, no LLM call inside a gate.
- TR3. Regression fixtures must reproduce: (a) the 2026-06-13 error #6 missed-3rd-sibling-test
  case; (b) the 2026-06-11 cross-file-drift unguarded-file case; (c) a hand-authored
  artifact missing a required frontmatter field.
- TR4. Zero AGENTS.md rule-budget consumption (NG1).
- TR5. Gate failures must be self-explanatory in CI output (name the file/sibling/field at
  fault) so the loop closes without a human decoding the failure.

## Open Questions (resolve at plan time)

- OQ1. Sibling-set declaration mechanism for FR3 (explicit registry file format + location).
- OQ2. Harness placement: PreToolUse hook vs CI-only vitest helper vs both.
- OQ3. Initial artifact-class set + per-class schema for FR2.

## Acceptance Criteria

- AC1. Harness + Gap 1 gate + Gap 3 gate merged with passing CI and RED→GREEN regression
  fixtures (TR3).
- AC2. A demonstrably-malformed artifact and a demonstrably-incomplete sweep each fail CI in
  the PR's own checks.
- AC3. Zero new AGENTS.md rules added.
- AC4. Deferred Gaps (2/5/6, 4, 7) each have a tracking issue with re-eval criteria.
