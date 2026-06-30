---
title: "feat(harness): constraint-scaffold — L1 import-boundary gate (v1: client→server-secret)"
type: feat
issue: 5765
branch: feat-constraint-scaffold
pr: 5770
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
brainstorm: knowledge-base/project/brainstorms/2026-06-30-constraint-scaffold-brainstorm.md
spec: knowledge-base/project/specs/feat-constraint-scaffold/spec.md
created: 2026-06-30
---

# Plan: `constraint-scaffold` — L1 import-boundary gate (#5765)

## Overview

Build a Soleur plugin skill, `constraint-scaffold`, whose v1 generates **one** deterministic,
no-LLM structural gate into a Next.js product codebase: a **dependency-cruiser import-boundary
gate** that fails closed when a client module (`"use client"`) takes a **value** (non-`type-only`)
import on a server-secret module — i.e. a server secret leaking into the browser bundle. The
gate runs in CI and rejects the violation *before* the LLM-judged review layer (`soleur:review`).

**Scope decision (operator, 2026-06-30, after 4-reviewer plan-review):** ship the
brand-survival gate **alone** first. The original brainstorm chose all three gate types + CI +
pre-commit; plan-review (DHH + code-simplicity + Kieran) and the brainstorm CTO/CPO converged on
boundary-gate-first because (a) the naming gate is near-vacuous (Next.js already enforces
`route.ts`; kebab-case is lint-level), (b) the contract gate is a fragile AST-lite heuristic,
and (c) pre-commit can't do the cheap staged-subset thing for an import-graph gate and is the
lefthook-worktree-hang surface. Those three are **deferred to fast-follow issues** (filed at
plan-end). This proves the generator + CI + agent-recovery pipeline on the one gate that carries
the `single-user incident` threshold before triplicating.

First target = `apps/web-platform/` (Soleur's own Next.js app) — the skill's first run IS the
dogfood. Next.js-only.

## Research Reconciliation — Spec vs. Codebase

| Spec / brainstorm claim | Codebase reality (verified 2026-06-30) | Plan response |
|---|---|---|
| FR2: "`server/` not importable from `app/`/`components/`" | **128** `app/`+`components/` files import from `server/` — legitimate Next.js App Router server-component / route-handler imports. A directory ban = 128-violation false-positive wall. | Recalibrate to the **client boundary**: a `"use client"` module must not take a **value** (`dependencyTypesNot: ['type-only']`) import on a server-secret module. **Direct edges only** in v1 (transitive → deferred). |
| Calibrated rule still fires on existing code | 170–178 `"use client"` modules; ~20+ import from `server/`, many `import type` (erased). dep-cruiser needs config to even see these correctly. | **Mandatory `.cjs` config:** `tsConfig.fileName="tsconfig.json"` (resolves `@/*` aliases — real code imports via `@/server/...`, not relative; without this they resolve to `couldNotResolve` and the rule is blind) + `tsPreCompilationDeps:true` (populates `type-only`). Capture current value-violations as a dep-cruiser **known-violations baseline** (`>=13`), read with `--ignore-known`. |
| FR4 (contract gate) / FR3 (naming gate) / FR5 (pre-commit) | 91 `app/api` routes; no user-authored OpenAPI; root `lefthook.yml`. Naming is Next.js-enforced; contract gate's `.parse(` collides with `JSON.parse(`. | **Deferred to fast-follow issues** (operator descope). Not in v1. |
| Brainstorm: "land #3132 first" | #3132 OPEN/unbuilt; `dependency-cruiser` absent everywhere; no fitness-function prior art. | #3132 folds in as the skill's first run on `apps/web-platform`. No dependency on it landing first. |
| New skill | Skill-description budget at **2250/2250, zero headroom** (`components.test.ts:15`). | Bump `SKILL_DESCRIPTION_WORD_BUDGET` co-located with SKILL.md creation (Phase 1). |
| Architecture Decision | No existing ADR on fitness functions / dep-cruiser / layer boundaries. ADR-011 (Three-Tier Enforcement) is the parent. Highest = ADR-069 (note: a pre-existing duplicate ADR-068 exists — do NOT pattern-match off it). | Create **ADR-070** (short); minimal C4 component (eval-harness precedent). |

## User-Brand Impact

**If this lands broken, the user experiences:** the `constraint-gates` CI job hard-blocks the
founder's PR on a violation they cannot read (a `.cjs` config) or unblock — a deploy stranded
with no recovery path that doesn't need an engineer.

**If this leaks, the user's workflow is exposed via:** a mis-calibrated rule that greenlights a
real `"use client"` → server-secret **value** import (shipping a server secret into the browser
bundle) because alias resolution was silently off, the type-only/value distinction was inert, or
the baseline grandfathered a same-PR leak.

**Brand-survival threshold:** single-user incident.

`requires_cpo_signoff: true` (CPO reviewed at brainstorm Phase 0.5 — carried forward);
`user-impact-reviewer` runs at PR-review time. The agent-owns-gates recovery (below) is the
primary mitigation.

> **Sharp Edge:** a plan whose `## User-Brand Impact` section is empty/`TBD`/threshold-less fails
> `deepen-plan` Phase 4.6. This section is filled.

## Agent-Owns-Gates Recovery Model (load-bearing)

Keeps the fail-closed gate from becoming a founder footgun. Captured in ADR-070, stated in `SKILL.md`:

1. **The agent authors and maintains the gate.** The founder never hand-edits the `.cjs`, the
   baseline, or the workflow.
2. **When the agent's own change trips the gate:** (a) real leak → the agent fixes the import;
   (b) legitimate new cross-boundary import → the agent runs `constraint-scaffold.sh
   --refresh-baseline` (clean-tree + merge-base capture, below), and the baseline diff is
   PR-reviewable. **(OQ3 resolved.)**
3. **In-code escape hatch:** dep-cruiser's native `// dependency-cruiser-disable-next-line`
   comment, documented in `SKILL.md`. Agent-owned; used sparingly.
4. **Founder hotfix with no agent in the loop (SpecFlow P0-4 — the brand-survival deadlock).**
   Nothing forces every change through an agent (a GitHub-web hotfix, a machine without the
   repo's tooling). The single-account-safe recovery: the red `constraint-gates` check
   annotation prints **one** instruction — comment `/soleur fix constraints` on the PR — which
   dispatches the **existing `/soleur` comment-handler** (claude-code-action) to run the agent;
   the agent fixes-or-refreshes and pushes a clean commit, after which the gate passes normally.
   **No override label, no synthetic App-as-labeler actor, no net-new dispatch workflow.**
   (This removes the internal contradiction code-simplicity flagged: the prior plan disabled the
   non-author label on the only gate that mattered, so the label apparatus served nothing.)
5. **The founder is never required to read or unblock the gate** — `never-defer-operator-actions`.

## Architecture Decision (ADR/C4)

### ADR

Create **ADR-070 — "Layer 1 deterministic constraint gates for product code"** via
`/soleur:architecture` (short). Decision: *deterministic, no-LLM structural gates (generated by
`constraint-scaffold`) run in CI and reject structural violations of the product codebase BEFORE
the LLM-judged review layer; the agent — never the founder — owns gate maintenance, baseline
refresh, and recovery (comment-summon path).* Cross-reference ADR-011 (Three-Tier Enforcement)
as the parent (this is the product-code instantiation of tier 1). Status `accepted` (M1 — green
gate on `apps/web-platform` — verified in this PR; not soak-gated). Do NOT pattern-match the
ADR off ADR-068 (pre-existing duplicate-number collision).

### C4 views

Verified against all three model files (`model.c4`, `views.c4`, `spec.c4`). Completeness-mandate
enumeration: **external human actors** — none added; **external systems/vendors** — none (gate
runs in `github`, already modeled; dep-cruiser is a build-time devDep, not a modeled system);
**containers/data stores** — none; **access relationships** — none changed. The one
architecturally-significant element is the skill itself — a new deterministic enforcement-layer
generator; precedent: `eval-harness` is modeled as L3 component `platform.plugin.evalharness`.

C4 edit (in-scope, minimal): add `constraintscaffold = component "constraint-scaffold skill" {
technology "Constraint Generator"; description "Generates the L1 dep-cruiser import-boundary gate
(client→server-secret) into the product codebase CI" }` in the `plugin` system + edge
`constraintscaffold -> webapp "Generates L1 import-boundary gate (CI)"`; add
`platform.plugin.constraintscaffold` to the `components of platform.plugin` view include. Run
`apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts`. **Do NOT** hand-bump the
`"61 workflow skills"` count string in `model.c4` (merge-conflict magnet); `release-docs` owns
component counts.

## Infrastructure (IaC)

**Skipped — no provisioned infrastructure.** `constraint-gates.yml` is committed config-as-code;
`dependency-cruiser` is an npm devDep. No Terraform root touched. (Phase 2.8 considered, cleared.)

## Observability

```yaml
liveness_signal:
  what: "constraint-gates CI job conclusion on every PR (always-runs + internal path-check)"
  cadence: "per PR event"
  alert_target: "GitHub PR checks (red = blocked merge); gh pr checks"
  configured_in: "apps/web-platform/.github/workflows/constraint-gates.yml (generated)"
error_reporting:
  destination: "GitHub Actions job log + PR check annotation (prints the /soleur summon path on failure)"
  fail_loud: "job exits non-zero on any new (non-baselined) boundary violation OR dep-cruiser config/binary error (rc ∉ {0,1})"
failure_modes:
  - mode: "new client→server-secret value-import leak"
    detection: "dep-cruiser forbidden rule fires (non-type-only dep to a secret module), --ignore-known baseline excludes only pre-existing"
    alert_route: "constraint-gates CI job fails → red PR check + summon annotation"
  - mode: "dep-cruiser config/parse/binary error (would otherwise read as green)"
    detection: "shared runner treats depcruise rc ∉ {0,1} as hard fail"
    alert_route: "constraint-gates CI job fails"
  - mode: "gate goes vacuous (rule stops firing / alias resolution silently off)"
    detection: "positive-control fixture (value import via @/server alias must fail) + couldNotResolve-into-server==0 self-test, in plugins/soleur/skills/constraint-scaffold/test/*.test.sh"
    alert_route: "scripts test shard (ci.yml) fails on PRs touching the skill"
logs:
  where: "GitHub Actions run logs (constraint-gates job)"
  retention: "GitHub Actions default (90d)"
discoverability_test:
  command: "cd apps/web-platform && ./node_modules/.bin/depcruise --config .dependency-cruiser.cjs --ignore-known .dependency-cruiser-known-violations.json --output-type err app components server; echo rc=$?"
  expected_output: "rc=0 with 'no dependency violations found' (baseline-clean) — NO ssh"
```

## Implementation Phases

### Phase 0 — Preconditions & calibration scan (no writes)

- 0.1 Detect Next.js: `[[ -f apps/web-platform/next.config.* ]] && grep -qE '"next"\s*:' apps/web-platform/package.json` (anchor the key — `"next"` substring matches `next-themes`). Fail-closed + no writes if not Next.js (Next.js-only v1).
- 0.2 **Calibration scan:** enumerate `"use client"` modules; classify their `server/` imports into **type-only** (allowed) vs **value** (forbidden); emit the explicit, non-empty **secret-module match set** (`server/**` value-targets + modules reading server-only `process.env`). Record the current value-violation count → the baseline population.
- 0.3 Run the canonical skill-description **budget one-liner** (Node form, per `2026-04-21-skill-description-budget-at-cap-requires-plan-time-surgery.md`); confirm the bump amount.
- 0.4 Clean-tree guard requirement noted for Phase 2 baseline capture. Test convention: `*.test.sh` (scripts shard globs `plugins/soleur/skills/*/test/*.test.sh`, `scripts/test-all.sh:185`).

### Phase 1 — Skill scaffold + budget + devDep

- 1.1 `plugins/soleur/skills/constraint-scaffold/SKILL.md` (third-person description ≤ 25–30 words; the recovery model; escape-hatch doc) **AND** bump `SKILL_DESCRIPTION_WORD_BUDGET` in `plugins/soleur/test/components.test.ts` in the **same phase** (inline-documented bump; budget is zero-headroom — they must land together or `components.test.ts` is red).
- 1.2 `plugins/soleur/skills/constraint-scaffold/scripts/constraint-scaffold.sh` — two modes: default (detect + scan + emit + wire + self-test) and `--refresh-baseline` (clean-tree + merge-base capture). Strict-mode + exit matrix (model `canary-bundle-claim-check.sh`); non-destructive (refuse-if-exists, no `--force`).
- 1.3 Add `dependency-cruiser@>=13` devDep to `apps/web-platform/package.json` (+ lockfile; `cq-before-pushing-package-json-changes`); bootstrap pattern modeled on `review/scripts/ensure-semgrep.sh`. **(Before Phase 4 dogfood, which needs the binary.)**
- 1.4 Templates (minimal): the `.cjs` dep-cruiser config + the CI workflow + the **shared runner** (`apps/web-platform/scripts/constraint-gates.sh`). Inline small fragments as heredocs. (No disclaimer-header / OSS-license note — v1 targets Soleur's own `apps/web-platform`, not an external founder repo; defer that to the multi-repo follow-up.)

### Phase 2 — Boundary gate

- 2.1 Emit `apps/web-platform/.dependency-cruiser.cjs`: `options.tsConfig.fileName="tsconfig.json"`,
  `options.tsPreCompilationDeps=true`; `forbidden` rule (`from "use client"` → `to` secret-module
  set, `dependencyTypesNot:['type-only']`, **direct edges only**) + a "only `server/` imports
  secret modules" rule.
- 2.2 Capture `.dependency-cruiser-known-violations.json` via `--output-type baseline`, **on a
  clean tree** (`git diff --quiet && git diff --cached --quiet` else hard-refuse) **against the
  `origin/main` merge-base** — so a violation introduced in the SAME PR is NOT grandfathered (P0-3).
- 2.3 Self-tests in `…/test/boundary.test.sh`: (a) value import of a secret module via `@/server/...`
  alias FAILS; (b) `import type` of the same PASSES; (c) **0 `couldNotResolve` edges into the
  secret set** (alias resolution live); (d) empty-input → fail-closed (distinguish "no client
  modules" from "glob broke"); (e) broken `.cjs` → rc ∉ {0,1} → hard FAIL.

### Phase 3 — CI wiring (one surface)

- 3.1 Generate `apps/web-platform/.github/workflows/constraint-gates.yml`: **always-runs +
  internal path-check** (triggers every PR, computes "did `apps/web-platform/**` change", exits 0
  fast otherwise — so a required check never deadlocks on the path filter; P1-6). Calls the shared
  runner `apps/web-platform/scripts/constraint-gates.sh`, which owns the pinned `depcruise
  --ignore-known .dependency-cruiser-known-violations.json … --output-type err` invocation and the
  rc∉{0,1} hard-fail. On failure, the job annotation prints the `/soleur fix constraints` summon
  path. Fail-closed. **No override label** (recovery is the summon path, not a label).

### Phase 4 — Dogfood + ADR/C4 + catalog

- 4.1 Run the skill end-to-end against `apps/web-platform`; commit the `.cjs` + baseline + runner +
  workflow; confirm the gate is **green on HEAD** via the `--ignore-known` invocation and the
  positive control proves the rule fires (M1).
- 4.2 Author ADR-070 + the minimal C4 component edit; run the C4 validation tests.
- 4.3 Catalog: `/soleur:release-docs` (plugin.json description + README skill count).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1 — `constraint-scaffold` skill exists with valid SKILL.md (third-person, no `<example>`,
  under char limit); `components.test.ts` passes **including the same-PR budget bump** (no red span).
- [ ] AC2 — Running `constraint-scaffold.sh` against `apps/web-platform` emits the `.cjs`, baseline,
  shared runner, and CI workflow; a second run is non-destructive (refuse-if-exists; baseline JSON
  is the only re-writable artifact and only via `--refresh-baseline`).
- [ ] AC3 — The gate FAILS on a positive-control fixture importing a secret module via the **same
  `@/server/...` alias** as a **value** import, and PASSES on `import type` of the same; the emitted
  `.cjs` sets `tsConfig.fileName` + `tsPreCompilationDeps:true`; a self-test asserts **0
  `couldNotResolve` edges into the secret set** (SpecFlow P0-1).
- [ ] AC4 — Baseline capture refuses on a dirty tree and captures against the `origin/main`
  merge-base; a violation introduced in the same PR surfaces as a real failure, not grandfathered
  (P0-3).
- [ ] AC5 — The shared runner treats `depcruise` rc ∉ {0,1} as a hard FAIL; a broken-`.cjs`
  self-test confirms fail-closed (P1-12); empty-input is fail-closed, distinguished from "no client
  modules exist" (P2-14).
- [ ] AC6 — The secret-module match set is explicit and **non-empty** on `apps/web-platform`
  (self-test) (P1-5).
- [ ] AC7 — `constraint-gates` CI job present, **always-runs + internal path-check** (reports a real
  conclusion on every PR; no pending-forever deadlock; P1-6), fails closed, prints the
  `/soleur fix constraints` summon path on failure.
- [ ] AC8 — `constraint-scaffold.sh --refresh-baseline` regenerates the baseline (clean-tree +
  merge-base) and the baseline diff is the only change (OQ3 agent-owned recovery).
- [ ] AC9 — Founder-recovery (SpecFlow P0-4): a human-authored commit tripping the gate is
  recoverable with exactly one (founder) account via the `/soleur fix constraints` comment — no
  override label, no `.cjs` edit. Recovery contract recorded in ADR-070.
- [ ] AC10 — On `apps/web-platform` HEAD the gate is **green** via
  `depcruise --ignore-known .dependency-cruiser-known-violations.json --output-type err app
  components server` (exit 0); the same `--ignore-known` invocation is used identically in the
  shared runner, the CI workflow, and the observability `discoverability_test` (Kieran P0).
- [ ] AC11 — ADR-070 created (status accepted, cross-refs ADR-011, not pattern-matched off ADR-068);
  `model.c4` + `views.c4` add the minimal `constraintscaffold` component + edge + view include;
  `c4-code-syntax.test.ts` + `c4-render.test.ts` pass. No `"61 workflow skills"` count-string edit.
- [ ] AC12 — `apps/web-platform` typecheck (`cd apps/web-platform && ./node_modules/.bin/tsc
  --noEmit`) and existing tests still pass; `dependency-cruiser@>=13` devDep + lockfile committed.
- [ ] AC13 — `plugin.json` description + `README.md` skill count updated (release-docs).

### Post-merge (operator)

- [ ] AC14 — None. (No provisioned infra; no operator mint; no migration. The dogfood gate runs in
  CI automatically on the next `apps/web-platform/**` PR.)

## Non-Goals (deferred — fast-follow issues filed at plan-end)

- **NG1.** Multi-stack / "portable across runtimes" — Next.js-only v1. → deferred issue.
- **NG2.** **File-structure/naming gate** — near-vacuous (Next.js enforces `route.ts`; kebab-case is
  lint-level). → deferred issue.
- **NG3.** **API/schema contract gate** (body-validation; full OpenAPI) — heuristic/fragile; needs
  schema-anchored matching + founder-authored or Soleur-generated contracts. → deferred issue.
- **NG4.** **Pre-commit (lefthook) surface** — CI is authoritative for an import-graph gate; defer
  the local fast-feedback surface. → deferred issue.
- **NG5.** **Transitive boundary leaks** (client → non-client helper → secret) — v1 is direct-edge
  only; needs dep-cruiser `reachable`. → deferred issue.
- **NG6.** Generating gates into a second/arbitrary founder repo + the machine-generated
  disclaimer/OSS-license artifacts (CLO) — only meaningful once a non-Soleur target exists. →
  folded into NG1's deferred issue.
- **NG7.** Bundle-size / p95-latency / complexity caps (rest of #3132 / #3133) — tracked under
  #3132/#3133, no new issue.

## Domain Review

**Domains relevant:** Engineering, Product, Legal (carry-forward from brainstorm Phase 0.5 triad;
`USER_BRAND_CRITICAL=true`).

### Engineering (CTO) — reviewed (carry-forward)
dep-cruiser correct JS/TS tool; lethal failure mode is a fail-closed gate the founder can't unblock
→ agent owns maintenance + recovery (encoded above). Next.js-only; token offload is a success
metric. ADR-070 + agent-owns-gates flagged (captured). Boundary-first descope honors the
"prove on one gate" recommendation.

### Product (CPO) — reviewed (carry-forward; satisfies `requires_cpo_signoff`)
Internal agent-harness gate; value is invisible plumbing. Dogfood on `apps/web-platform` first.
Founder-can't-unblock is the brand risk; the summon-path recovery is the mitigation.

### Legal (CLO) — reviewed (carry-forward)
Minimal legal surface. dependency-cruiser MIT (attribution auto-satisfied via `node_modules`). The
disclaimer-header / OSS-license-note recommendation applies only to **external** founder repos →
deferred with NG1/NG6 (v1 targets Soleur's own `apps/web-platform`). No PII / GDPR impact.

### GDPR / Compliance Gate (Phase 2.7)
Trigger (b) (`single-user incident`) fires, but the feature touches no regulated-data surface — no
schema/migration/auth/API-route data processing, no LLM on operator-session data. CLO carry-forward
is the compliance assessment. Documented no-op.

### Product/UX Gate
**Tier:** none — no UI surface (CI/CLI skill; no `components/**`, `page.tsx`, modal, banner, flow).
spec-flow-analyzer ran (it found the 4 P0s, all folded).

## Open Code-Review Overlap

None. 63 open `code-review` issues checked against every path in Files to Create/Edit — zero
overlap. Net-new surface.

## SpecFlow & Plan-Review Findings (resolutions)

- spec-flow P0-1 (tsConfig/tsPreCompilationDeps) → Phase 2.1, AC3. P0-2 (contract `.parse(`) →
  **gate deferred (NG3)**. P0-3 (same-PR baseline) → Phase 2.2, AC4. P0-4 (solo-founder deadlock) →
  Recovery item 4 (summon path), AC9. P1-5 (secret set) → 0.2/2.1, AC6. P1-6 (required-check
  deadlock) → Phase 3.1, AC7. P1-7 (CI/pre-commit disagree) → **pre-commit deferred (NG4)** + shared
  runner. P1-11 (transitive) → **NG5**. P1-12 (rc∉{0,1}) → AC5.
- Kieran P0 (`--ignore-known` missing) → Phase 3.1, AC10, observability. P1 (budget-bump ordering)
  → Phase 1.1. P2 (devDep ordering) → Phase 1.3. P2 (version ≥13) → Phase 1.3/2.1. P2 (glob :185,
  ADR-068 dup) → Phase 0.4 / ADR section.
- DHH + code-simplicity: descope to boundary gate (operator-confirmed); one shared runner; drop the
  non-author label machinery (internal contradiction — disabled on the only gate that matters); drop
  `--force` / `--check` / disclaimer ceremony; collapse recovery to the summon path; short ADR;
  minimal C4 (no count-string bump).

## Files to Create

- `plugins/soleur/skills/constraint-scaffold/SKILL.md`
- `plugins/soleur/skills/constraint-scaffold/scripts/constraint-scaffold.sh`
- `plugins/soleur/skills/constraint-scaffold/references/{depcruise-config,constraint-gates-workflow,shared-runner}.template` (or heredocs)
- `plugins/soleur/skills/constraint-scaffold/test/boundary.test.sh`
- `knowledge-base/engineering/architecture/decisions/ADR-070-l1-constraint-gates.md`
- Generated into `apps/web-platform/`: `.dependency-cruiser.cjs`,
  `.dependency-cruiser-known-violations.json`, `scripts/constraint-gates.sh`,
  `.github/workflows/constraint-gates.yml`

## Files to Edit

- `plugins/soleur/test/components.test.ts` — bump `SKILL_DESCRIPTION_WORD_BUDGET` (Phase 1.1).
- `apps/web-platform/package.json` (+ lockfile) — add `dependency-cruiser@>=13` devDep.
- `knowledge-base/engineering/architecture/diagrams/model.c4` + `views.c4` — minimal component +
  edge + view include (no count-string bump).
- `plugins/soleur/plugin.json` + `README.md` — skill count/description (release-docs).

## Risks & Mitigations

- **R1 — baseline grandfathers a real leak.** Mitigation: clean-tree + merge-base capture (AC4) so
  same-PR leaks aren't eligible; positive control (AC3) proves new leaks fire; baseline diff
  PR-visible.
- **R2 — type-only vs value misclassification ships server secrets to client** (the
  single-user-incident vector). Mitigation: `tsPreCompilationDeps:true` + `tsConfig` alias
  resolution + AC3's both-arm assertion + the `couldNotResolve==0` self-test. deepen-plan
  precedent-diff if any existing client/server boundary check exists.
- **R3 — direct-edge rule misses a transitive leak.** Mitigation: documented known gap (NG5);
  deferred `reachable` follow-up. Acceptable for v1 (the common leak is a direct import).
- **R4 — gate red on HEAD day one** (Kieran P0). Mitigation: `--ignore-known` pinned identically in
  runner + CI + observability + AC10.

## Sharp Edges

- The rule is **client-boundary, not directory-boundary** (128 legit `app/→server/` imports) and
  **value-not-type-only** and **direct-edge-only**. Get any of the three wrong and the gate is
  either a false-positive wall or silently blind.
- `--refresh-baseline` is **agent-only**; never present it to the founder
  (`never-defer-operator-actions`). Founder recovery is the `/soleur fix constraints` comment.
- Verify the CI path-filter logic matches `apps/web-platform/**` via `git ls-files | grep -E`
  before freezing (`hr-when-a-plan-specifies-relative-paths`).
- dep-cruiser baseline read REQUIRES `--ignore-known`; the bare `--config … --output-type err`
  form is red on HEAD with a non-empty baseline (Kieran P0).
