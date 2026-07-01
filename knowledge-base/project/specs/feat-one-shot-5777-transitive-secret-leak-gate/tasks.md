---
feature: constraint-scaffold v2 — transitive client→helper→server-secret gate
issue: 5777
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-07-01-feat-constraint-scaffold-transitive-secret-leak-gate-plan.md
note: "Spec lacks valid lane: (no spec.md — pipeline entered plan directly) — defaulted to cross-domain (TR2 fail-closed)."
---

# Tasks — constraint-scaffold v2 transitive gate (#5777)

## Phase 0 — Empirical spike & preconditions (no committed writes; brand-survival gate)

- [ ] 0.1 `cd apps/web-platform && bun install --frozen-lockfile` (worktree has no node_modules; depcruise binary required).
- [ ] 0.2 Reachable-rule capability proof (D1): scratch `.cjs` with `tsPreCompilationDeps:false`, direct rule sans `dependencyTypesNot`, reachable rule (no `pathNot`). Confirm config validates; `import type` chains NOT reported; a value chain IS reported.
- [ ] 0.3 **D1 GATE:** diff direct-rule violation set from `--output-type baseline` before (`true`+filter) vs after (`false`, filter dropped). MUST be byte-identical; else adopt D1-alt (two-config split) + record divergence.
- [ ] 0.4 Enumerate the reachable target set (D2): list EVERY distinct `server/**` module transitively reached from any client origin (parse `--output-type json` via/to). Classify each value-safe (→ `pathNot`) vs real leak (→ Phase 2). Re-scan; do not trust v1 count.
- [ ] 0.5 Perf probe (P2-1): wall-clock the reachable cruise on the real tree; record delta; note runner timeout budget if slow.
- [ ] 0.6 Confirm no `description:` frontmatter edit (SKILL.md body prose only) → no components.test.ts budget re-check.

## Phase 1 — Config: template + emitted .cjs (D1)

- [ ] 1.1 Edit `references/depcruise-config.template`: `tsPreCompilationDeps:false`; `const clientFrom = computeClientFromSet()` once; direct rule `to:{path:SECRET_PATH}` (drop `dependencyTypesNot`); add `VALUE_SAFE_PATH` + reachable rule (D2 shape); update header + rule comments.
- [ ] 1.2 Apply byte-identical change to `apps/web-platform/.dependency-cruiser.cjs` (parity.test.sh #1).
- [ ] 1.3 Do NOT touch `package.json` (pin stays `^16.10.0`).

## Phase 2 — Zero-out the reachable baseline (D2)

- [ ] 2.1 Fix every real transitive leak enumerated in 0.4 (break the value chain / server-boundary façade). Never baseline a real leak; if the fix set is large/risky, STOP and surface for scoping.
- [ ] 2.2 Finalize `VALUE_SAFE_PATH` = Phase-0-verified value-safe reached modules (start with the 3 v1-verified; each addition security-reviewed + justified inline).
- [ ] 2.3 Single `constraint-scaffold.sh --refresh-baseline` (clean tree + merge-base). Review full diff: MUST show zero new `type:"reachability"` entries. Any reachability entry ⇒ back to 2.1/2.2.

## Phase 3 — CI guard (D3)

- [ ] 3.1 boundary.test.sh: assert committed baseline has zero `type:"reachability"` entries (jq/node), fail loud.
- [ ] 3.2 Add generic additive guard to `shared-runner.template` + `constraint-gates.sh` (byte-identical): fail-closed if baseline holds any reachability entry. Keep parity.test.sh #1/#2 green. Fallback: 3.1 alone if runner guard judged out-of-scope at review.

## Phase 4 — Fixtures + anti-vacuity guard

- [ ] 4.1 NEGATIVE (helper in `lib/`, locks P2-2): client → `@/lib/leak-helper`(non-client) → `@/server/secret`(value, NOT in VALUE_SAFE_PATH). MUST flag.
- [ ] 4.2 NEGATIVE depth-3: client → lib/a → lib/b → server(value). MUST flag.
- [ ] 4.3 POSITIVE terminal type-only: client → lib/helper(value) → server via `import type`. MUST NOT flag.
- [ ] 4.4 POSITIVE first-hop type-only (load-bearing): client → `import type` helper → server(value). MUST NOT flag.
- [ ] 4.5 POSITIVE pathNot-target: client → lib/helper(value) → server/domain-leaders(value). MUST NOT be flagged by transitive rule.
- [ ] 4.6 Anti-vacuity guard: toolchain-present (`PARSED_COMPONENTS>=1`) ⇒ transitive assertions run + fail (not skip); assertions after the existing SKIP guard; covered by test-webplat.

## Phase 5 — Docs / ADR / prose

- [ ] 5.1 Amend ADR-071 (§Decision, §Alternatives, §Consequences record #5777/NG5 closed).
- [ ] 5.2 SKILL.md body: remove "direct-edge only"/"transitive deferred"; state transitive now covered (cite #5777). Do NOT edit `description:`.
- [ ] 5.3 No plugin.json/README count change (no new component).

## Exit verification (maps to Acceptance Criteria AC1–AC13)

- [ ] parity.test.sh green (byte-identical template↔.cjs and runner↔template).
- [ ] boundary.test.sh green in test-webplat (all fixtures + anti-vacuity + zero-reachability-baseline assertion).
- [ ] `depcruise --config .dependency-cruiser.cjs --ignore-known .dependency-cruiser-known-violations.json --output-type err app components server` → rc=0 (green on HEAD).
- [ ] committed baseline has zero `type:"reachability"` entries; every real leak fixed (not grandfathered).
- [ ] `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` + existing suites pass; package.json pin unchanged (`^16.10.0`).
- [ ] ADR-071 amended; no `.c4` edit (enumeration confirmed).
