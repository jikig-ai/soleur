---
date: 2026-06-30
topic: constraint-scaffold — L1 deterministic structural gate generator
issue: 5765
status: complete
lane: cross-domain
brand_survival_threshold: single-user incident
---

# Brainstorm: `constraint-scaffold` — L1 deterministic structural gates (#5765)

## What We're Building

A Soleur plugin skill, **`constraint-scaffold`**, that detects a Next.js product
codebase's stack and **generates deterministic, no-LLM structural gates** into it —
gates that reject structurally-wrong agent output on mechanical grounds *before* the
LLM-judged review layer (`soleur:review` → `architecture-strategist` +
`pattern-recognition-specialist`) runs. This is the "Layer 1 / Constraint Layer" the
issue's 5-layer-harness framing says Soleur is missing for *product-code shape* (it
already has rich deterministic L1 for git/secret/branding *process* — `guardrails.sh`,
`brand-hex-commit-gate.sh`, `git-commit-secret-scan.sh`, the change-class classifier).

**v1 scope (operator decisions, 2026-06-30):**

- **Gate types — ALL THREE** the issue lists:
  1. **Import/layer-boundary** — `dependency-cruiser` (MIT) config: `server/` not
     importable from `app/`/`components/`; client cannot reach server secrets.
  2. **File-structure / naming validators** — required files in required locations,
     convention linting (component naming, directory structure).
  3. **API/schema contract gate** — OpenAPI / JSON-Schema validation in CI for routes
     the agent creates under `app/api/`.
- **Run surface — CI + pre-commit hook:** an authoritative **GitHub Actions job**
  (fail-closed on PR/push, mirrors `pr-quality-guards.yml`) PLUS a fast local
  **lefthook pre-commit hook** so the agent catches violations before pushing.
- **First target = `apps/web-platform/`** (Soleur's own Next.js app). The skill's first
  run IS the dogfood — abstraction and the real gate rules get validated together.
- **Stack: Next.js-only for v1.** dep-cruiser is JS/TS-only; "portable across runtimes"
  is deferred (multi-stack serves zero current users — `apps/web-platform` is the only
  product codebase Soleur operates).

## Why This Approach

The operator chose **build the skill greenfield now** (collapsing the unbuilt #3132
fitness-functions precedent into this build, with `apps/web-platform` as the skill's
first generated target) over the leaders' lower-risk "prove on #3132 first, then
extract" reframe. The accepted tradeoff: one artifact instead of two, at the cost of
debugging the *generator abstraction* and the *gate rules* simultaneously.

To blunt the risk CTO flagged, the build carries four non-negotiable mitigations
(below). The skill is genuinely valuable because the gap is real and verified: **no
`dependency-cruiser`, no fitness functions, no structural CI exists anywhere in the
repo** — every structural check today is LLM-judged (L4), which is probabilistic,
token-costly, and (per ADR-011) the wrong tier for a mechanical invariant.

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| D1 | Build greenfield this cycle as a skill (not plain CI) | Operator decision; #3132 folds in as the skill's first run on `apps/web-platform`. |
| D2 | Emit all three gate types in v1 | Operator decision (full issue scope). |
| D3 | CI workflow (authoritative, fail-closed) **+** lefthook pre-commit hook | Operator decision; CI is source of truth, pre-commit shortens the agent's feedback loop. |
| D4 | Next.js-only; defer multi-stack | dep-cruiser is JS/TS-only; only stack Soleur operates. Multi-stack → follow-up issue. |
| D5 | **Agent owns gates; founder never faces unrecoverable red CI** | Brand-critical. `never-defer-operator-actions`: a non-technical founder cannot read/unblock a `.cjs` config. The agent maintains rules + bumps thresholds; when the agent trips a generated gate, the resolution path (re-run the skill to amend config, or route to `review`) is defined in SKILL.md, not discovered in prod. |
| D6 | **Per-gate positive-control self-test + calibrate rules to the target corpus** | Learnings: a green-only gate goes vacuous — each generated rule ships with a fixture proving it *fires*, and with an empty-input fail-closed test. Thresholds/boundaries are data-driven from the codebase scan, never upstream defaults. |
| D7 | **Override discipline mirrors `pr-quality-guards.yml`** | Label-based bypass `confirm:constraint-<name>` applied by a **non-author** (no self-bypass); in-code `# constraint:disable <rule>` escape hatch documented. Mirrors the existing `confirm:claude-config-change` non-author gate. |
| D8 | **Generated artifacts carry a machine-generated disclaimer header** | CLO: each emitted config/workflow gets a header stating it is machine-generated scaffolding, not warranted correct, owner reviews before merge. Generator is non-destructive (no overwrite of existing CI without explicit confirmation). |
| D9 | OSS-license check on the transitive devDep tree | CLO soft-flag: dep-cruiser is MIT (attribution auto-satisfied via `node_modules`), but the skill emits a one-line note recommending the founder's existing OSS-license check run against the resolved tree. |
| D10 | Bump-label override workflow | Mirror the repo's `semver:*` / `override_bump_type` precedent for threshold bumps (D7's label is the per-gate analogue). |

## Open Questions

- **OQ1 (deferred to plan):** Stack-detection mechanism — `[[ -f next.config.ts ]]` +
  `grep -q '"next"' package.json`, vs. a richer probe (monorepo app enumeration). Plan
  decides; v1 only needs to recognize `apps/web-platform`.
- **OQ2 (deferred to plan):** API/schema contract gate strategy for Next.js route
  handlers — AST-based route-param scanner vs. requiring an OpenAPI doc. Repo has
  OpenAPI only for Supabase PostgREST introspection, not user-authored contracts.
- **OQ3 (deferred to plan):** How the agent-owned threshold-bump path is wired
  end-to-end (re-invoke skill in `--amend` mode vs. a dedicated bump sub-command).
- **OQ4 (measurement, not blocking):** L4 token-offload is *unproven* — instrument the
  `review` skill's `architecture-strategist`/`pattern-recognition` token spend on PRs
  that passed L1 gates vs. a pre-gate baseline. Success metric, not a launch blocker.

## User-Brand Impact

- **Artifact:** the `constraint-scaffold` skill and the fail-closed CI/pre-commit gates
  it generates into the product codebase (`apps/web-platform/` first).
- **Vector:** a generated fail-closed gate hard-blocks CI on a violation the
  non-technical founder cannot read, diagnose, or unblock — converting an invisible
  internal quality check into a founder-facing wall and stranding a deploy. (D5/D7
  mitigate: agent owns resolution; non-author override label; in-code escape hatch.)
- **Threshold:** `single-user incident`.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support
(triad CPO + CLO + CTO spawned per `USER_BRAND_CRITICAL`; others not relevant.)

### Engineering (CTO)

**Summary:** Cited precedent #3132 is OPEN/unbuilt and dep-cruiser exists nowhere —
recommended proving the config on `apps/web-platform` before extracting a generator
(operator overrode to greenfield). dep-cruiser is the correct JS/TS tool; the lethal
failure mode is a fail-closed `.cjs` gate the founder can't unblock → **the agent must
own gate maintenance + threshold bumps** with a defined escape hatch. "Portable across
runtimes" is scope creep → Next.js-only v1. Token-savings claim is real but unproven →
make it a success metric. MVP gate-shape: import/layer boundaries first (operator chose
all three). Flagged an Architecture Decision (new "Layer 1" pipeline boundary + the
agent-owns-gates ownership model).

### Product (CPO)

**Summary:** Category error in the original framing — Soleur both *writes* the code and
*is* the constrained party, so this is an **internal agent-harness gate**, not a
founder-repo deliverable. As framed (fail-closed gates into a non-technical founder's
repo) it is hostile to the "ship without a dev team" promise and violates
`never-defer-operator-actions`; as an internal gate (agent trips it, agent fixes it,
founder never sees red) it helps. Value is invisible plumbing accruing to Soleur's
economics. Recommended dogfood on `apps/web-platform` first — which the greenfield
decision honors by making `apps/web-platform` the skill's first target.

### Legal (CLO)

**Summary:** Minimal legal surface. dependency-cruiser is MIT (attribution
auto-satisfied via `node_modules`). Two actions: (1) generated artifacts carry a
machine-generated "not warranted, owner reviews before merge" disclaimer header and the
generator stays non-destructive; (2) emit a one-line note recommending an OSS-license
check on the transitive devDep tree. No PII / data-processing / GDPR impact.

## Capability Gaps

None. Execution is covered by `soleur:skill-creator` (scaffold the skill),
`soleur:review` + `architecture-strategist`/`pattern-recognition-specialist` (the L4
layer this offloads), and existing deterministic-gate exemplars to model
(`brand-hex-commit-gate.sh`, `canary-bundle-claim-check.sh`,
`review/scripts/ensure-semgrep.sh`). Verified via repo-research grep — no missing tool.

## Session Errors

None.

## Productize Candidate

The skill IS the productized artifact; no separate candidate.

## Architecture Decision (plan deliverable)

CTO flagged this introduces a new **"Layer 1" deterministic constraint boundary** into
the build pipeline (before LLM review) **and** an **agent-owns-gates ownership model**.
The plan should capture both via `/soleur:architecture create` — the layering rationale
and the ownership/escape-hatch contract are the load-bearing decisions.
