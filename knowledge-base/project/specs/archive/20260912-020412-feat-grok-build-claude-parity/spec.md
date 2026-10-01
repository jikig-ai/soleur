---
title: Grok Build plugin fidelity after Claude Code progress
status: draft
lane: cross-domain
brand_survival_threshold: single-user incident
branch: feat-grok-build-claude-parity
issue: 8064
date: 2026-09-11
brainstorm: knowledge-base/project/brainstorms/2026-09-11-grok-build-claude-parity-brainstorm.md
---

# Spec — Grok Build plugin fidelity (Track 1)

## Problem Statement

Epic #6320 closed in July 2026 claiming Skill→slash parity. Grok Build still has **no nested Skill/slash tool**. A live `/go` session (2026-09-11) classified to brainstorm and Read `SKILL.md` instead of invoking `/brainstorm`. Meanwhile two months of Claude Code skill/hook/ship work landed on main; five pipeline skills remain Claude-only; ADR-110 was closed as docs-only; public getting-started and legal copy still describe Soleur as a Claude Code plugin only.

A Grok contributor following soleur.ai is taught the wrong commands, and an operator dogfood session can skip hooks (`grok --trust`) or inline the pipeline — a **single-user incident** on lifecycle quality.

## Goals

1. Make the Grok lifecycle contract **honest and executable**: after `/go` classifies, the parent follows the next SKILL.md in-process via `harness.ts`; Claude’s Skill tool is unchanged and eval-gated.
2. Close Claude-only invocation drift in pipeline skills.
3. Implement ADR-110 so Grok can resolve semantic model tiers (today `harness-model-map.ts` does not exist).
4. Additive hook-matcher ports so Grok-named tools can fire the same safety TOMs.
5. After golden-path eval is green: contributor onboarding, public getting-started/README Grok column, legal harness-neutral plugin copy.

## Non-Goals

- Soleur Web ACP / replacing Claude Agent SDK (#6547 stays parked)
- Ordering or IaC-birthing a GEX44 GPU host (#6546 / #7882 stay engineering P3)
- Porting `claude-code-action` CI to Grok
- Claiming “full Grok support”, “zero configuration”, or “self-hosted Grok”
- Adding an xAI customer sub-processor / DPA row (that is #6547)
- A live promptfoo xAI eval grid (unit golden-path + grok-fidelity-gate is the bar)
- New Eleventy layout/page (Grok column is copy on the existing getting-started page)

## Functional Requirements

### FR1: Honest dual-harness invocation

Every pipeline skill in the locked list uses `invokeSkill()` / `routingInstructions()` language (or equivalent dual-voice). Claude branch: Skill tool `soleur:<skill>`. Grok branch: slash `/<skill>` meaning **Read that SKILL.md in-process**, not a nested tool_use. Hardcoding “Use the Skill tool” as the only path is a spec failure.

Locked minimum list (re-derive at plan): `go`, `brainstorm`, `plan`, `work` (including Phase 4), `review`, `qa`, `compound`, `ship`, `one-shot`, `postmerge`, `drain-labeled-backlog`, `drain-prs`.

### FR2: Claude non-regression

Existing Claude eval / grok-fidelity Claude arm stays green. Claude hook matchers (`Skill`, `Monitor`, `AskUserQuestion`, `Task`) are not removed. No Skill-tool wording deleted from the Claude branch.

### FR3: Golden-path eval before public docs

A `grok-fidelity` (or sibling) assertion fails if a locked pipeline SKILL.md is Skill-tool-only. Public getting-started / README Grok column **must not merge before** this assertion is green on the same PR stack.

### FR4: ADR-110 implemented

`plugins/soleur/lib/harness-model-map.ts` (name may match the existing spec `feat-harness-model-map`) resolves semantic tiers for both harnesses. Workflow pins do not leave Grok resolving `'sonnet'`/`'haiku'` as no-ops. ADR-110 status becomes Accepted when this FR lands.

### FR5: Plugin-root substitution

`go.md` / plugin hooks / skill bash that today key only `CLAUDE_PLUGIN_ROOT` also honor `GROK_PLUGIN_ROOT` (or a documented fallback that is the in-repo plugin path). Grok sessions must not silently take the `SOLEUR_GIT_REPO_DIAG source=probe-unreachable` path when the plugin is present.

### FR6: Hook matcher aliases

Where Grok tool names differ (`run_terminal_command` vs `Bash`, `ask_user_question` vs `AskUserQuestion`, `spawn_subagent` vs `Task`, no Monitor tool), settings/hooks gain **aliases**. Claude matchers remain. Missed-gate class: unkept-promise, dispatch-watch, technical-fork, credential snapshot — if those hooks are Skill/Monitor-gated today, they must have a Grok-firing path or an explicit documented skip with a `SOLEUR_*` marker.

### FR7: Contributor onboarding refresh

`knowledge-base/engineering/grok-onboarding.md` dated to this change. Documents: `/go` not `/soleur:go`; `grok --trust` as a safety TOM; `GROK_SUBAGENTS=1` in **user** config; spawn keys are filename stems; in-process SKILL.md contract; refuse xAI CLI “improve the product and model” for non-personal repos (CLO live ToS 2026-09-11).

### FR8: Public docs Grok column (after FR3)

Eleventy getting-started and GitHub README (root + plugin) include a two-column command table. Allowed claim: “Same plugin. Claude Code: `/soleur:go`. Grok Build: `/go`.” Forbidden: “full Grok support”, “zero configuration”, “model-agnostic” as current fact.

### FR9: Legal harness-neutral plugin copy (after FR3)

Lockstep edit: Terms, AUP, Privacy Policy, Data Protection Disclosure, GDPR Policy — replace exclusive “Claude Code plugin” with harness-neutral plugin language. Document `grok --trust` as a confidentiality TOM. **Do not** add xAI as a sub-processor or Third-Party Services customer path (that is #6547).

## Technical Requirements

### TR1: Harness adapter is the single invoke surface

Edits go through `plugins/soleur/lib/harness.ts` and `workflow-fidelity.ts`. Skills must not invent a third invocation dialect.

### TR2: Eval placement

Extend `plugins/soleur/test/workflow-fidelity.test.ts` / `go-routing-golden-path.test.ts` / `grok-fidelity-gate.sh` as needed. `harness.test.ts` and `grok-agent-discoverability.test.ts` should ride a required check (today they ride `test-bun` only — plan may enroll them in `grok-fidelity` if cheap).

### TR3: Agent compat unchanged unless agents are edited

67 `.grok/agents` stubs match `EXPECTED_SOLEUR_AGENT_COUNT`. If this work edits canonical agents, run `sync-grok-agent-compat.ts`.

### TR4: No product runtime / IaC in this spec

Do not edit `apps/web-platform/server/agent-runner.ts` or `apps/web-platform/infra/grok-dogfood.tf` except docs citations. Do not add a Robot Terraform root.

### TR5: Sequencing

Implementation order is load-bearing (brainstorm Key Decision 4): FR1+FR2+FR3 → FR5 → FR4 → FR6 → FR7+FR8 → FR9.

## Brand-survival

Threshold: **single-user incident**. Worst case: Grok user skips hooks and inlines `/go` → ship without review, or follows public `/soleur:go` and concludes Soleur is broken.

## Recertify (out of spec)

| Issue | Disposition |
|-------|-------------|
| #6547 | Parked. Unpark needs CPO product decision + CLO `/gdpr-gate` + xAI DPA. |
| #6546 | Parked. Order needs spend ack + Robot stock + license memo. |
| #7882 | Engineering P3. Birth path only if GEX is ordered. |
