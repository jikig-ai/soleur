---
feature: constraint-scaffold v2 — transitive client→helper→server-secret gate
issue: 5777
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-07-01-feat-constraint-scaffold-transitive-secret-leak-gate-plan.md
note: "Spec lacks valid lane: (no spec.md — pipeline entered plan directly) — defaulted to cross-domain (TR2 fail-closed). Deepened 2026-07-01 (3 review agents; conflicts resolved for brand-survival)."
---

# Tasks — constraint-scaffold v2 transitive gate (#5777)

## Phase 0 — Empirical spike & preconditions (no committed writes; brand-survival gate)

- [ ] 0.1 `cd apps/web-platform && bun install --frozen-lockfile` (worktree has no node_modules).
- [ ] 0.2 Reachable-rule capability proof (D1): scratch `.cjs`, `tsPreCompilationDeps:false`, direct rule sans `dependencyTypesNot`, reachable rule (no `pathNot`). Confirm: config validates (no additionalProperties error); `import type` chains NOT reported; value chain IS reported.
- [ ] 0.2b Mixed-import proof (security P1): `import { type A, realValue } from "@/server/x"` keeps the VALUE edge under the flip; barrel (`export *`) + static dynamic-import resolve.
- [ ] 0.3 D1 GATE: diff direct-rule violation set before (`true`+filter) vs after (`false`, dropped). MUST be byte-identical; else STOP + re-plan (reachable-only second config, do NOT pre-build).
- [ ] 0.4 Enumerate reachable target set (D2): list EVERY server module transitively reached; classify value-safe vs real leak. Bounded, not total — record a `SOLEUR-DEBT:` marker + issue for unresolvable dynamic/template-literal imports.
- [ ] 0.5 Perf probe: wall-clock reachable cruise on real tree; note runner timeout budget if slow.
- [ ] 0.6 Confirm no `description:` frontmatter edit (SKILL.md body only) → no budget re-check.
- [ ] 0.7 Re-prove `couldNotResolve`-into-`server/` == 0 on the real tree UNDER the flip (security P1).
- [ ] 0.8 Assess Phase 2.2-A relocation blast radius (`domain-leaders` = 8 client importers) to choose 2.2-A vs 2.2-B.

## Phase 1 — Config: template + emitted .cjs (D1)

- [ ] 1.1 Edit `references/depcruise-config.template`: `tsPreCompilationDeps:false`; `const clientFrom = computeClientFromSet()` once; direct rule `to:{path:SECRET_PATH}` (drop `dependencyTypesNot`); reachable rule + (if 2.2-B) `VALUE_SAFE_PATH` with coupling comment; updated header/rule comments. Verify `.cjs` parses.
- [ ] 1.2 Byte-identical change to `apps/web-platform/.dependency-cruiser.cjs` (parity.test.sh #1).
- [ ] 1.3 Do NOT touch `package.json` (pin stays `^16.10.0`).

## Phase 2 — Value-safe exclusion + zero reachable baseline (D2, P0)

- [ ] 2.1 Fix every real transitive leak from 0.4 (break the value chain). Never baseline a real leak.
- [ ] 2.2 Decide exclusion by blast radius:
  - [ ] 2.2-A (preferred): relocate the 3 value-safe modules out of `server/**` (+ update importers) → delete `pathNot`, direct baseline → zero; OR
  - [ ] 2.2-B (minimum): keep `pathNot` = Phase-0-verified value-safe set WITH the mandatory D4 content guard + `SOLEUR-DEBT:` relocation issue.
- [ ] 2.3 Single `--refresh-baseline` (clean tree + merge-base). Review full diff: MUST show ZERO `type:"reachability"` entries. Any ⇒ back to 2.1/2.2.

## Phase 3 — CI guards (D3)

- [ ] 3.1 boundary.test.sh: toolchain-free assertion — committed baseline has zero `type:"reachability"` entries.
- [ ] 3.2 MANDATORY runner guard (security P1): `shared-runner.template` + `constraint-gates.sh` byte-identical — fail-closed on any `type:"reachability"` baseline entry. parity.test.sh #1/#2 green. Do NOT cut.
- [ ] 3.3 Direct-rule non-regression (arch P1-A): boundary.test.sh asserts baseline `type:"dependency"` count == 10 unchanged after the flip.
- [ ] 3.4 D4 value-safe drift guard (if 2.2-B): assert each `VALUE_SAFE_PATH` module reads no `process.env` value / imports no secret; `.cjs` coupling comment.

## Phase 4 — Fixtures + anti-vacuity guard (boundary.test.sh, mktemp)

- [ ] 4.1 NEGATIVE transitive `lib/` helper (secret NOT in VALUE_SAFE_PATH) — MUST flag (subsumes old AC6).
- [ ] 4.2 POSITIVE first-hop type-only — MUST NOT flag.
- [ ] 4.3 NEGATIVE mixed import `{ type A, realValue }` (both hops) — MUST flag.
- [ ] 4.4 NEGATIVE barrel/re-export (`export *` + named) — MUST flag.
- [ ] 4.5 NEGATIVE dynamic `import()` (static-resolvable) — MUST flag.
- [ ] 4.6 POSITIVE pathNot target (or, under 2.2-A, N/A) — MUST NOT be flagged by transitive rule.
- [ ] 4.7 NEGATIVE value-safe drift (2.2-B) — D4 guard MUST fail when a listed module gains a secret/env read.
- [ ] 4.8 real-runner rc≠0 via `CONSTRAINT_GATES_DIR` seam on a transitive-leak fixture — exit≠0.
- [ ] 4.9 Anti-vacuity guard: toolchain-present ⇒ assertions run + fail (not skip); after the SKIP guard; test-webplat coverage.

## Phase 5 — Docs / ADR / prose

- [ ] 5.1 ADR-071 DATED APPEND (`## Amendment 2026-07-01 (#5777)`): reachable rule; `tsPreCompilationDeps` true→false reversal+rationale; exclusion decision; #5777 deferred→closed. Leave v1 sections intact.
- [ ] 5.2 SKILL.md body: remove "direct-edge only"/"transitive deferred". Do NOT edit `description:`.
- [ ] 5.3 No plugin.json/README count change.

## Exit verification (maps to AC1–AC13)

- [ ] parity.test.sh green (template↔.cjs and runner↔template byte-identical).
- [ ] boundary.test.sh green in test-webplat: all fixtures + anti-vacuity + zero-reachability assertion + direct-count==10 + (2.2-B) drift guard.
- [ ] `depcruise --config .dependency-cruiser.cjs --ignore-known .dependency-cruiser-known-violations.json --output-type err app components server` → rc=0.
- [ ] committed baseline zero `type:"reachability"` entries; runner guard fails if one present; every real leak fixed.
- [ ] `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` + existing suites pass; package.json pin unchanged.
- [ ] ADR-071 dated amendment; no `.c4` edit (enumeration confirmed).
