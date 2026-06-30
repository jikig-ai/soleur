---
feature: constraint-scaffold
lane: cross-domain
plan: knowledge-base/project/plans/2026-06-30-feat-constraint-scaffold-l1-gate-generator-plan.md
issue: 5765
---

# Tasks: constraint-scaffold — L1 import-boundary gate (#5765)

v1 = the dep-cruiser client→server-secret boundary gate ONLY, in CI, one shared runner.
Naming gate / contract gate / pre-commit / multi-stack / transitive → deferred (see plan NG1–NG5).

## Phase 0 — Preconditions & calibration (no writes)

- [ ] 0.1 Detect Next.js (`next.config.*` + anchored `"next":` key in package.json); fail-closed if not.
- [ ] 0.2 Calibration scan: enumerate `"use client"` modules; classify `server/` imports type-only vs value; emit the explicit, non-empty secret-module match set; record current value-violation count.
- [ ] 0.3 Run the canonical skill-description budget one-liner; confirm bump amount.
- [ ] 0.4 Note clean-tree requirement for baseline; confirm test convention `*.test.sh` (`scripts/test-all.sh:185`).

## Phase 1 — Skill scaffold + budget + devDep (Setup)

- [ ] 1.1 Write `plugins/soleur/skills/constraint-scaffold/SKILL.md` (≤25–30-word description; recovery model; escape-hatch doc) AND bump `SKILL_DESCRIPTION_WORD_BUDGET` in `plugins/soleur/test/components.test.ts` in the SAME commit (zero-headroom).
- [ ] 1.2 Write `scripts/constraint-scaffold.sh` — modes: default + `--refresh-baseline`; strict-mode + exit matrix; non-destructive (refuse-if-exists, no `--force`).
- [ ] 1.3 Add `dependency-cruiser@>=13` devDep to `apps/web-platform/package.json` (+ lockfile); ensure-semgrep-style bootstrap. (Before the Phase 4 dogfood.)
- [ ] 1.4 Templates/heredocs: `.cjs` dep-cruiser config, CI workflow, shared runner `apps/web-platform/scripts/constraint-gates.sh`. (No disclaimer/OSS-license note in v1.)

## Phase 2 — Boundary gate (Core)

- [ ] 2.1 Emit `.dependency-cruiser.cjs`: `tsConfig.fileName="tsconfig.json"`, `tsPreCompilationDeps:true`; client→secret-module forbidden rule (`dependencyTypesNot:['type-only']`, direct edges) + "only server/ imports secret modules" rule.
- [ ] 2.2 Capture `.dependency-cruiser-known-violations.json` via `--output-type baseline`, on a clean tree, against the `origin/main` merge-base (refuse on dirty tree).
- [ ] 2.3 Self-tests `…/test/boundary.test.sh`: value-import-via-`@/server`-alias FAILS; `import type` PASSES; `couldNotResolve`-into-secret-set == 0; empty-input fail-closed; broken-`.cjs` rc∉{0,1} hard FAIL.

## Phase 3 — CI wiring (Core)

- [ ] 3.1 Emit `apps/web-platform/.github/workflows/constraint-gates.yml`: always-runs + internal path-check (no required-check deadlock); calls the shared runner with the pinned `--ignore-known … --output-type err` invocation; rc∉{0,1} hard fail; prints `/soleur fix constraints` summon path on failure; fail-closed; NO override label.

## Phase 4 — Dogfood + ADR/C4 + catalog (Testing/Docs)

- [ ] 4.1 Run the skill end-to-end on `apps/web-platform`; commit `.cjs` + baseline + runner + workflow; confirm green on HEAD via `--ignore-known` + positive control fires (M1).
- [ ] 4.2 Author ADR-070 (short; cross-ref ADR-011; not off ADR-068); minimal C4 component + edge + view include (no count-string bump); run `c4-code-syntax.test.ts` + `c4-render.test.ts`.
- [ ] 4.3 `/soleur:release-docs` — plugin.json description + README skill count.

## Exit / verification

- [ ] V1 `components.test.ts` green (budget bump landed). `apps/web-platform` `tsc --noEmit` + existing tests green.
- [ ] V2 `scripts/test-all.sh` (skill self-tests) green.
- [ ] V3 All ACs (AC1–AC14) satisfied; AC10 `--ignore-known` invocation identical across runner/CI/observability.
