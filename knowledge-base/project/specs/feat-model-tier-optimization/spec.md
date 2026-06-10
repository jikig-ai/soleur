---
name: feat-model-tier-optimization
date: 2026-06-10
status: draft
lane: cross-domain
brand_survival_threshold: single-user incident
closes: "#3791"
brainstorm: knowledge-base/project/brainstorms/2026-06-10-model-tier-optimization-brainstorm.md
---

# Spec: Model-Tier Optimization (Workflow Call-Site Tiering)

## Problem Statement

Anthropic's Fable 5 release introduced a price tier above Opus ($10/$50 per MTok vs Opus 4.8 $5/$25, Sonnet 4.6 $3/$15, Haiku 4.5 $1/$5). Soleur's Model Selection Policy mandates `model: inherit` for all 66 agents, and none of the 8 dynamic-workflow scripts pass `opts.model` — so a Fable 5 session runs every mechanical subagent step (parse, classify, fetch, commit, file, report) and every research/Explore fan-out at the top tier. The per-PR CI review action (`claude-code-review.yml`) has no model pin at all, and the 15 web-platform Inngest crons hardcode model constants ad-hoc per file. Open issue #3791 deferred a model-downshift audit with "a pricing change" as a re-evaluation trigger; Fable 5 is that trigger.

## Goals

- Cut token spend on mechanical, high-volume subagent work (~65-80% per fan-out run, CFO estimate) without touching any judgment, review, security, or compliance path.
- Make model tier an explicit, audited, disclosed property of each spawn rather than an implicit session inheritance.
- Make savings verifiable via existing telemetry (`agent-token-tee.sh`) extended with model attribution.

## Non-Goals

- No agent frontmatter changes — all 66 agents keep `model: inherit`.
- No downgrades of review/security/compliance/synthesis/resolver paths (hard exemption list, Key Decision 2 in brainstorm).
- No per-operator model-configuration UI; no dynamic cost-based routing; no per-agent effort knobs (unsupported by plugin spec).
- No BYOK billable-run tiering — deferred with the `audit_byok_use.model` column + legal three-doc lockstep (follow-up issue).
- No persistent eval harness — acceptance is a side-by-side comparison on one real run.

## Functional Requirements

- **FR1 — Workflow tier pins.** Add `model: 'sonnet'` (or `'haiku'` for trivially small steps) to the allowlisted mechanical `agent()` call sites across the 8 workflow scripts: review (`classify`, `file`), plan-review (`detect`), agent-native-audit (8 enumeration audits), deepen-plan (`parse`), resolve-parallel (`analyze`, `commit`), resolve-todo-parallel (`analyze`, `commit`), resolve-pr-parallel (`fetch`, `commit`), drain-labeled-backlog (`cluster`, `report`). Each pin carries a one-line justification comment. Judgment steps (dimension reviewers, verify/concur, resolvers, synthesis/merge, one-shot) are explicitly NOT pinned.
- **FR2 — Research-spawn guidance.** SKILL.md prose for Explore/research fan-outs (deepen-plan per-section research and verify-the-negative passes, brainstorm Phase 1.1 research batch) directs spawning with the Agent tool's `model` parameter at the cheap tier, documented as advisory.
- **FR3 — CI pin.** `claude-code-review.yml` gets an explicit `--model` pin (tier decided at plan time; action-pin freshness verified per `cq-claude-code-action-pin-freshness`).
- **FR4 — Inngest cron tier registry.** `[Updated 2026-06-10]` **Deferred to #5106** at 5-agent plan review: independent deploy surface with zero shared code, and the parity AC was unsatisfiable without an unstated `MODEL_PRICING` opus pricing entry (Kieran P0). Corrected facts (16 cron/event files, not 15; pricing-path scoping; `constants.ts` coverage) recorded in #5106.
- **FR5 — Tier-attribution telemetry.** `agent-token-tee.sh` records the model per Agent spawn in `.claude/.session-tokens.jsonl`. Workflow scripts `log()` the tier of each pinned spawn (model-in-use disclosure).
- **FR6 — Policy amendment.** `plugins/soleur/AGENTS.md` Model Selection Policy replaces "no exceptions" with the three-tier vocabulary (never-downgrade exemption list / reasoning-heavy inherit / mechanical allowlist), the absolute-pin semantics, and the call-site justification-comment requirement. Ships in the same PR as FR1.

## Technical Requirements

- **TR1** — Pins are absolute model values; never "one tier below session." Only pin steps where a fixed cheap tier is always correct.
- **TR2** — Haiku only for steps whose runtime prompt fits comfortably in 200K context (model the runtime prompt per learning 2026-05-11, not file size); Sonnet is the default downgrade tier.
- **TR3** — Any CI/cron model change verifies the `claude-code-action` pin and thinking-API shape for the target tier (learnings 2026-04-18, 2026-02-22 §5; Fable 5 400s on explicit `thinking: disabled`).
- **TR4** — Telemetry extension is fire-and-forget, mirrors existing hook patterns (flock timeout, jq fallbacks, kill-switch).
- **TR5** — Acceptance: `[Updated 2026-06-10 — narrowed at 5-agent plan review]` one **single tiered** run of the review workflow on the PR's own diff; assert telemetry model attribution (pinned vs inherit per spawn class) + output well-formedness + classify against the known diff-class. The untiered comparison arm was cut: n=1 cross-arm agreement of nondeterministic agents is non-probative, telemetry rows cannot be attributed to arms, and it costs a full top-tier review run. The unpinned adjudication layer is the quality safety net by construction.

## Deferred (follow-up issues)

1. BYOK billable-run tiering: `audit_byok_use.model` column + Privacy Policy/DPD/T&C lockstep (CLO Finding B).
2. `model-launch-review` productized skill: recurring per-model-release audit (ID swaps, action-pin sync, thinking-API shape, tier re-evaluation).
3. Global "quality mode" operator toggle — only if demand surfaces.
