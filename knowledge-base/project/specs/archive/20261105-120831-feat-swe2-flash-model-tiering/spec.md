---
title: "SWE-2 Flash adoption on the Devin harness — docs + routing"
status: specified
issue: none  # filing-gate refused at spec time on a docs-only estimate; scope grew at plan-review (harness.ts strings + pin suite) — inline delivery retained in PR #12135
brainstorm: knowledge-base/project/brainstorms/archive/20261105-120831-2026-11-05-swe2-flash-devin-tiering-brainstorm.md
branch: feat-swe2-flash-model-tiering
pr: 12135
date: 2026-11-05
lane: cross-domain
brand_survival_threshold: single-user incident
---

# Spec: SWE-2 Flash on the Devin harness (docs + routing)

## Problem Statement

Cognition released SWE-2 Flash on 2026-11-04 (~1/5 price, ~3x speed of SWE-2; free in
Devin through 2026-11-30; slugs `swe-2-flash-medium`/`-high`/`-max`, verified via
`devin models` 2026-11-05). Soleur has no Devin-side cheap-tier guidance: on this harness
every read-only subagent spawn lands on `subagent_general` (parent model) or the
unlabelled router default, `devin/INSTRUCTIONS.md` instructs "inherit the session model"
everywhere, and it carries a stale claim that Claude model aliases are not Devin model
identifiers (measured false — `opus`/`sonnet`/`swe`/`codex`/`gemini`/`gpt` are documented
Devin family aliases). `TIER_MAPS` has no `devin` entry — correct today, since nothing
consumes it on Devin.

## Goals

- **G1.** `devin/INSTRUCTIONS.md` Domain-agents guidance routes read-only spawns
  (research, review-panel reads, exploration) to `subagent_explore` and reserves
  `subagent_general` for write-capable work, noting it always inherits the parent model.
- **G2.** Same section documents `agent.subagent_model: "swe-2-flash-medium"` as the
  operator opt-in for the router's default subagent model (user-scope config only,
  org-policy-gated, silently ignored when disallowed — disclose that degradation mode).
- **G3.** Correct the stale aliases claim in `devin/INSTRUCTIONS.md`.
- **G4.** ADR-110 addendum: measured `devin models` output, the router-not-SKU decision,
  org-allowlist silent-degradation caveat, Free-plan availability boundary (SWE-1.6 only),
  and the promo expiry (2026-11-30, no published post-promo rate card).
- **G5.** `model-launch-review` gains a Devin freshness-check item (third-vendor analog
  of Grok item 6): compare `devin models` output against Devin slugs Soleur references.
- **G6.** `plugins/soleur/AGENTS.md` Model Selection Policy gains a Devin note: a tool-surface mapping — researchers stay
  `subagent_general` (exec/MCP duties), ad-hoc read-only explores may use
  `subagent_explore` + `agent.subagent_model`; `model: haiku` frontmatter is inert there.
- **G7.** File the deferred machinery follow-up (`TIER_MAPS.devin` + generated Devin
  custom subagent profiles) as a `meta/machinery` issue naming its three measurement
  gates: plugin-profile registration on current CLI, forbidden-pin fail-vs-reroute
  behavior, post-promo Flash rate card.

## Non-Goals

- **NG1.** No `TIER_MAPS.devin` row — no consumer exists on Devin (ruled by CTO agent;
  `resolveModelTier`'s warn→inherit fallback already covers the harness).
- **NG2.** No custom subagent profile machinery (`sync-devin-agent-compat.ts`,
  `.devin/agents/` profiles) — blocked on the G7 measurement gates.
- **NG3.** No change to cloud-session behavior — plugin subagents and profile pins are
  local-only on Devin; cloud stays router/parent.
- **NG4.** No change to `subagent_general` semantics or to session-model selection advice
  beyond the documented opt-in.
- **NG5.** No `model: haiku` frontmatter edits — inert on Devin today; translation is part
  of the deferred profile generator, not this change.

## Functional Requirements

- **FR1.** The edited INSTRUCTIONS.md text must not assert a capability not yet measured
  (e.g., must not claim `swe-2-flash` resolves everywhere — Free plan is SWE-1.6 only).
- **FR2.** The `model-launch-review` item must name a concrete check command
  (`devin models`) and the comparison target.
- **FR3.** The ADR-110 addendum must record the measurement date and source
  (`devin models` output, docs.devin.ai/cli/subagents).

## Technical Requirements

- **TR1.** Mixed docs+code diff: INSTRUCTIONS.md, ADR-110 addendum, SKILL.md, AGENTS.md, README.md, audit-models.sh, harness.ts emitted strings, devin-harness.test.ts re-pin, new devin-instructions-routing.test.ts pin suite, go.md + skills/go/SKILL.md stale-contract sweep, KB artifacts (spec, tasks, brainstorm, plan), and an expenses.md verify_by row (review fixes).
  — no issue was created; delivery is inline in PR #12135.

## Open Questions

- Does the Devin subagent router already pick Flash-class models during the free window?
- Does a forbidden-model `model:` pin fail or silently reroute? (unblocks NG2)
- Does the org Devin dashboard break spend down per model?
- Does Devin's family-alias resolver accept `haiku`? (matters only if plugin agents ever
  register as profiles — generator would translate it)

## Operator items (post-merge, not plan gates)

- Optional: set `agent.subagent_model: "swe-2-flash-medium"` in
  `~/.config/devin/config.json` to route explore traffic to Flash during the free window.
- Record the post-promo Flash rate card in `knowledge-base/operations/expenses.md` with a
  `verify_by` date at the 2026-11-30 promo expiry (no Devin row exists in the ledger).
