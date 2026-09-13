---
date: 2026-09-11
topic: grok-build-claude-parity
lane: cross-domain
brand_survival_threshold: single-user incident
status: brainstorm-complete
draft_pr: 8061
issue: 8064
branch: feat-grok-build-claude-parity
---

# Grok Build plugin fidelity after Claude Code progress on main

## User-Brand Impact

- **Artifact:** Soleur plugin workflows under Grok Build (`/go`, pipeline skills, PreToolUse hooks, public getting-started / README / legal copy)
- **Vector:** A Grok user follows Claude-only instructions (`/soleur:go`, Skill tool), skips untrusted hooks, or the agent inlines the pipeline after `/go` classifies — shipping unverified code or sending repo content without the safety TOMs the corpus claims are shipped
- **Threshold:** `single-user incident`

Tagged **user-brand-critical** (auto, per #5175). CPO + CLO + CTO spawned in parallel before other specialists. The plan inherits `Brand-survival threshold: single-user incident` unless overridden.

## What We're Building

A **Track 1 plugin-fidelity spec** so Grok Build can run the same Soleur lifecycle Claude Code runs, **without regressing Claude**. Honest contract: Grok has no nested Skill/slash tool; after `/go` classifies, the parent **Reads the next SKILL.md in-process** via `invokeSkill()` / `routingInstructions()`. Claude keeps the Skill tool.

**Not building:** Soleur Web ACP (#6547 stays parked). GEX44 GPU order / Robot IaC (#6546 / #7882 stay engineering P3). “Full Grok support” marketing.

## Why This Approach

Epic #6320 (phases A–F) is **CLOSED**. Inspect CI and `harness.ts` exist. A live `/go` session on 2026-09-11 still classified to brainstorm and Read `SKILL.md` instead of invoking `/brainstorm`. That is the same class as `2026-07-11-grok-go-routes-one-shot-but-inlines-pipeline.md`. Prompt-level “REQUIRED (Grok Build)” headers cannot create a nested invoke primitive.

Operator chose **one spec, sequenced, public docs after eval is green** so we do not document a pipeline we have not re-proven. Claude Skill-tool path is a hard non-regression.

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | Spec **Track 1 only** | CPO/CTO/COO/CLO/CMO/CFO: the three tracks are different products. Web ACP and GPU are not this cycle. |
| 2 | Honest lifecycle: **in-process SKILL.md on Grok**, Skill tool unchanged on Claude | No nested slash tool exists. Dual-voice via `harness.ts`. Do not fake `/brainstorm` as a tool_use. |
| 3 | **Do not reopen #6320** | Closed epic claimed Skill→slash parity. New issue for the remaining contract + drift. |
| 4 | One spec, **sequenced**, docs after golden-path eval | CMO: do not claim until eval is green. Order below. |
| 5 | ADR-110 **implementation** is in this spec | #6316 closed after docs-only PR #6317. `harness-model-map.ts` does not exist. |
| 6 | Hook matcher **aliases**, never remove Claude matchers | Skill/Monitor/AskUserQuestion never fire on Grok; Claude must keep them. |
| 7 | Public getting-started + README Grok column **after** eval | Contributor `grok-onboarding.md` can refresh in the same sequence once eval is green, not before. |
| 8 | Legal corpus **harness-neutral** (plugin path only) | Pages already say “Claude Code plugin” while Grok contributors exist. Not an xAI customer-processor row (that is #6547). |
| 9 | #6547 / #6546 / #7882 **recertify, do not spec** | ACP = ~12k LOC + new US processor, zero xAI legal row. GPU = `approved-not-billing` ~$199/mo, no spend ack. |

### Implementation sequence (locked)

1. Dual-voice pipeline skills + eval (Claude arm stays green)
2. `CLAUDE_PLUGIN_ROOT` / `GROK_PLUGIN_ROOT` substitution
3. ADR-110 resolver + pin migration
4. Hook matcher ports (additive)
5. `grok-onboarding.md` + Eleventy getting-started + README Grok column
6. Legal lockstep: T&C, AUP, Privacy, DPD, GDPR Policy — “Claude Code or Grok Build plugin”; `grok --trust` as a safety TOM. **No xAI sub-processor row.**

## Open Questions

- Plan-time: exact pipeline-skill file list for dual-voice (minimum: review, qa, compound, drain-labeled-backlog, drain-prs, work Phase 4). Repo-research counted **5 Claude-only of 12**; re-derive at plan, do not quote the count as gospel.
- Whether `AskUserQuestion` on Grok maps to Grok’s `ask_user_question` tool or stays prose. Mechanical; plan decides.
- Eleventy getting-started: table on the **existing** page (copy; no `.pen`) vs a new layout (would fire `wg-ui-feature-requires-pen-wireframe`). Default: existing page.

## Productize Candidate

`eval-gate` / `grok-fidelity` assertion: pipeline SKILL.md files must not contain Skill-tool-only invocation (must mention `harness.ts` or a Grok slash branch). Recurring: every Claude skill edit can re-introduce drift.

## Lane

`cross-domain` (USER_BRAND_CRITICAL triad). No operator override.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product

**Summary:** Spec Track 1 only. Do not reopen #6320. Web ACP and GPU are not product this cycle. Grok is operator-as-builder quality, not a Phase 4 recruitment channel. Dual-harness copy waits on a real contract.

### Legal

**Summary:** Plugin fidelity is disclosure + Art. 32 TOM (`grok --trust`), not a new processor. Web ACP is blocked for customer data until `/gdpr-gate` and an xAI DPA row. Live ToS: xAI CLI has a training opt-in Anthropic commercial terms do not; onboarding must tell Grok users to refuse it. Legal corpus has **zero** xAI hits (`grep knowledge-base/legal`).

### Engineering

**Summary:** Nested invoke does not exist; inspect CI ≠ pipeline fidelity. ADR-110 still Proposed. 67 Grok agent stubs match the registry. Hook matchers and `CLAUDE_PLUGIN_ROOT` in `go.md` are load-bearing. Do not start ACP or fake GEX as `hcloud`.

### Operations

**Summary:** Track 1 ≈ $0 vendor. Do not order GEX. Phase 1 CX33 is live TF (`grok-dogfood.tf`). `GROK_SUBAGENTS=1` is user config only. No new expense row unless a company xAI seat appears.

### Marketing

**Summary:** Do not market “full Grok support.” Allowed after eval: “Same plugin. Claude: `/soleur:go`. Grok: `/go`.” Forbidden: echoing xAI “zero configuration.” Strip “model-agnostic” as current fact from AEO extract if it still appears. GPU is not a marketing surface.

### Support

**Summary:** Public getting-started is Claude-only. Discord already has a Grok contributor (`wasim7412`). Slash collisions (`/review`, `/plan`, `/help`) need a FAQ line. Untrusted sessions fail silent. Customer-reply skill #6261 is a separate gap.

### Finance

**Summary:** Track 1 is R&D time on existing Max seats. GEX is additive ~$199/mo opex, not a savings play. #6547 is the only path that can break BYOK $0 inference — parked.

## Capability Gaps

| Gap | Evidence |
|-----|----------|
| No nested Skill/slash invoke | This `/go` session Read SKILL.md. Learning `2026-07-11-grok-go-routes-one-shot-but-inlines-pipeline.md`. |
| Five pipeline skills Claude-only | `rg` on worktree: review, qa, compound, drain-labeled-backlog, drain-prs have no `\bgrok\b` / `harness.ts`. |
| ADR-110 unimplemented | `git ls-files` has no `harness-model-map.ts`. ADR status Proposed. #6316 CLOSED via docs PR #6317. |
| Plugin-root | `go.md` Step 0 bash keys `CLAUDE_PLUGIN_ROOT`; stubs use `GROK_PLUGIN_ROOT` (`agent-registry.ts`). ADR-179 residual. |
| Legal xAI silence | `git grep -iE 'xAI|xai|Grok' knowledge-base/legal` → zero hits (CLO). |
| Eval-harness Grok arm is not a live LLM grid | `models.generated.json` is three Anthropic IDs (repo-research). Golden-path unit tests exist under `grok-fidelity`. |

## Recertify (not this spec)

- **#6547** OPEN — Phase 1 measures exist (#6545 CLOSED); product decision + CLO/CPO customer-data sign-off unmet. Stay p3 / Post-MVP.
- **#6546** OPEN — artifacts merged #6597; GPU not ordered; spend ack + stock + license still required.
- **#7882** OPEN — GEX birth is three SSH lines; binds `hr-all-infrastructure-provisioning-servers`; do not fake Cloud TF. Revisit only if GEX is ordered.

## Next Steps

→ `/plan` for implementation details (sequenced Track 1 spec).
