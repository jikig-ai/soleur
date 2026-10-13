---
title: constraint-scaffold — L1 deterministic structural gate generator
status: draft
owner: engineering
lane: cross-domain
brand_survival_threshold: single-user incident
brainstorm: knowledge-base/project/brainstorms/2026-06-30-constraint-scaffold-brainstorm.md
issue: 5765
created: 2026-06-30
---

# Spec: `constraint-scaffold`

## Problem Statement

Soleur has rich deterministic Layer-1 enforcement for its **meta-workflow** —
`guardrails.sh`, `brand-hex-commit-gate.sh`, `git-commit-secret-scan.sh`, the
change-class classifier — but **no deterministic constraint on the *shape of product
code*** the agent writes. Every structural check (layer boundaries, naming, API
contracts) is currently **LLM-judged** in `soleur:review` (`architecture-strategist`,
`pattern-recognition-specialist`) — i.e. L4, not L1. That is probabilistic,
token-costly, and (per ADR-011) the wrong tier for a mechanical invariant. Verified:
`dependency-cruiser` and any fitness-function infrastructure exist **nowhere** in the
repo; the cited precedent #3132 is OPEN and unbuilt.

## Goals

- **G1.** A skill `constraint-scaffold` detects a Next.js product codebase and emits
  three deterministic, no-LLM gate types: (a) `dependency-cruiser` import/layer
  boundaries, (b) file-structure/naming validators, (c) API/schema contract validation
  for `app/api/` routes.
- **G2.** Generated gates wire into BOTH an authoritative GitHub Actions CI job
  (fail-closed on PR/push) AND a lefthook pre-commit hook.
- **G3.** The skill's first run targets `apps/web-platform/` (dogfood) and leaves a
  working, passing gate suite on the real codebase.
- **G4.** Each generated rule ships with a **positive-control self-test** (a fixture
  proving the rule fires) and an **empty-input fail-closed test**; boundary/threshold
  values are calibrated from a scan of the target corpus, not upstream defaults.
- **G5.** **Agent owns gates.** SKILL.md defines the resolution path when the agent
  trips a generated gate (re-run skill to amend config / route to `review`); the
  non-technical founder is never required to read or hand-edit a gate to recover.
- **G6.** Override discipline: a `confirm:constraint-<name>` label applied by a
  **non-author** bypasses a gate; an in-code `# constraint:disable <rule>` escape hatch
  is documented. (Mirrors `pr-quality-guards.yml` `confirm:claude-config-change`.)
- **G7.** Generated artifacts carry a machine-generated disclaimer header; the generator
  is non-destructive (no overwrite of existing CI/config without explicit confirmation).
- **G8.** Documented in the plugin catalog (plugin.json description + README counts via
  `soleur:release-docs`); assumes no technical operator.

## Non-Goals

- **NG1.** Multi-stack / "portable across runtimes" — Next.js-only for v1. Other stacks
  → follow-up issue.
- **NG2.** Bundle-size budgets, p95-latency gates, cyclomatic-complexity caps (the rest
  of #3132 / sibling #3133) — not in this skill's v1.
- **NG3.** No change to `soleur:review` agent thoroughness — L4 agents still run;
  this offloads *mechanical* structural checks, it does not remove the LLM review.
- **NG4.** No generation into a second/arbitrary founder repo this cycle — `apps/web-
  platform` is the only target proven in v1.

## Functional Requirements

- **FR1.** Stack detection: recognize a Next.js app (`next.config.*` + `"next"` in
  `package.json`) and its layer layout (`app/`, `server/`, `components/`, `lib/`,
  `app/api/`). (OQ1)
- **FR2.** Emit dep-cruiser config encoding layer boundaries: `server/` not importable
  from `app/`/`components/`; client modules cannot import server-secret modules.
  Calibrated against the real import graph (no false positives on existing code).
- **FR3.** Emit file/naming validators (required files in required locations; component
  naming convention).
- **FR4.** Emit an API/schema contract gate for `app/api/` route handlers. (OQ2 — AST
  route-param scanner vs. OpenAPI doc requirement; plan decides.)
- **FR5.** Emit a fail-closed GitHub Actions workflow running all three gates on
  PR/push, and a lefthook pre-commit hook running the same checks locally.
- **FR6.** Emit per-gate positive-control + empty-input self-tests (G4).
- **FR7.** Wire the `confirm:constraint-<name>` non-author override label + document the
  in-code escape hatch (G6).
- **FR8.** Run end-to-end on `apps/web-platform`, leaving a green gate suite (G3).

## Technical Requirements

- **TR1.** Skill follows Soleur conventions: `SKILL.md` (name = `constraint-scaffold`,
  third-person `description`), single-file `scripts/` entry point, optional `references/`.
- **TR2.** Generator is deterministic (no LLM in the skill's execution path); all
  branches are shell conditionals / explicit exit codes. Model on
  `canary-bundle-claim-check.sh` (strict-mode, exit matrix) and `ensure-semgrep.sh`
  (optional-binary bootstrap for the dep-cruiser devDep).
- **TR3.** Generated artifacts include a machine-generated disclaimer header (G7) and an
  OSS-license-check note for the transitive devDep tree (D9).
- **TR4.** Architecture Decision recorded via `soleur:architecture create` capturing
  the new "Layer 1" pipeline boundary AND the agent-owns-gates ownership/escape-hatch
  contract (plan deliverable).
- **TR5.** Skill description word-budget checked against the cumulative SKILL.md cap
  before authoring (Budget checkpoint).

## Success Metrics

- **M1.** Gate suite runs green on `apps/web-platform` and each of the three gates has a
  passing positive-control proving it fires.
- **M2.** (Post-launch, non-blocking) Measure `review`-skill L4 token spend on
  L1-passing PRs vs. pre-gate baseline (OQ4).

## Open Questions

See brainstorm OQ1–OQ4. OQ1–OQ3 are plan-time; OQ4 is post-launch measurement.
