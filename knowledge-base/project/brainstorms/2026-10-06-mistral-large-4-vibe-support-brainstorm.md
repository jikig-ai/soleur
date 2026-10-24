---
date: 2026-10-06
topic: mistral-large-4-vibe-support
issue: 9648
lane: cross-domain
brand_survival_threshold: single-user incident
draft_pr: 9640
---

# Mistral Large 4 + Mistral Vibe support (staged)

## What We're Building

Operator request: "in light of our EU sovereignty play: Mistral just released their new model with open weights coming later this month. I'd like for Soleur users to be able to use this model or even their Mistral Vibe Harness, what would it take to add it to Soleur?"

"Add Mistral" is **three separate builds** with different effort, blast radius and gates. The operator scoped all three plus a content piece into this brainstorm, **staged by gate**:

| Stage | Piece | Gate to start | Deliverable |
|---|---|---|---|
| 0 | **Hedge content** | none (now) | Honest "harness-neutral, evaluating Large 4 + Vibe" post inside the news window. No "runs on Mistral", no "EU-sovereign". |
| 1 | **A0. Model dogfood on existing vehicles** *(added in second session)* | Mistral Studio API access | Run ML4/Devstral through Soleur on paths needing no new harness: Codex custom `model_providers` (OpenAI-compatible) and/or the #1215 Ollama+proxy BYOM path, measured with the `grok-measure.sh` classes. Produces the quality signal that gates A and B spend — inside the Oct 6→27 preview window. |
| 2 | **A. Vibe as 5th harness (skills-only)** | none; sequencing prefers after #9608 slice-1 lands *(amended in second session)* | `Harness` union member + detector + `inherit` tier map + `plugins/soleur/vibe/INSTRUCTIONS.md`; consume the #9609 adapter checklist once Cursor's measurements stabilize it. Operator dogfood + eval table before any public claim. |
| 3 | **B. BYOK `mistral` provider spike** | A0 not required; legal train required before flag-on | Provider + priced `MODEL_PRICING` row for ONE non-agentic path, behind a default-off flag. A bundled Soleur-paid Mistral option is a follow-up decision gated on usage data *(session 2)*. |
| 4 | **C1. Small-class self-host dogfood** *(added in second session)* | GPU host spend ack (ADR-120 gate) | Devstral Small 2 (24B, weights already released, Apache-2.0) or Mistral Small 4 (119B MoE) on a single GPU — GEX44-class runbook shape; NOT gated on the ML4 drop. |
| 5 | **C2. ML4 frontier self-host** | weights + licence + hardware published (~Oct 27) | Tracking issue only (#9649); re-evaluate then, fold into #6546 open-weight dogfood. 1T params = multi-GPU; beyond the GEX44 class. |

## Verified facts (2026-10-06)

- **Mistral Large 4 (ML4):** announced 2026-10-06; 1T-param MoE, 49B active, natively multimodal. API public preview on Mistral Studio, $1.36/M in, $4.18/M out (mistral.ai/news/mistral-large-4). Weights "end of this month" (Mistral) / Oct 27 (press) / "three weeks" pending safety testing (TechCrunch). **Weights licence: not stated. Self-host hardware: not stated.** API preview access is limited (developers, security professionals, state authorities) — dogfood access unverified.
- **Mistral Vibe:** Apache-2.0 CLI. Loads Agent Skills `SKILL.md` from `.agents/skills`, `.vibe/skills`, `~/.vibe/skills`; `AGENTS.md`; MCP (http/streamable-http/stdio); hooks in `.vibe/hooks.toml` (`pre_tool`/`post_tool`/`post_agent`); subagents via the `task` tool, defined as TOML in `~/.vibe/agents` (text-only result, cannot ask the user questions). Model providers documented: Mistral API only. Hook tool-blocking: undocumented. Telemetry on by default (`enable_telemetry = false`).
- **Repo today:** zero Mistral support (`git grep -il mistral` outside KB → only `dspy-ruby/references/providers.md`). `Harness` union = `claude|grok|codex|devin|unknown` (`plugins/soleur/lib/harness.ts`). ADR-110 tier map covers claude+grok only. Web platform runtime is coupled to `@anthropic-ai/claude-agent-sdk`; no `ANTHROPIC_BASE_URL` seam; `apps/web-platform/server/providers.ts` is a credential registry (`openai`, `bedrock`, `vertex` listed, no `mistral`). `MODEL_PRICING` is Anthropic-keyed (unknown model bills at zero — defeats BYOK cap).
- **Harness cost precedent:** Grok PR #8061 = 49 files, Codex PR #8507 = 42 files (re-derived with `gh pr view --json files`; repo-research's 51/44 and its "cursor in the union" claim were wrong — the union has no cursor member on main).
- **Retired precedent:** ADR-245 retired the OpenHands/Gemini hand ports (silent decay, double-sync cost). Re-entry rule: a `Harness` union member + a **generator** for any per-harness tree, never another hand copy.

## User-Brand Impact

| Field | Value |
|-------|--------|
| **Artifact** | Soleur Mistral support: the Vibe harness tree and the flagged BYOK `mistral` provider path |
| **Vector** | User content reaches a new sub-processor without a DPA / updated disclosures; a marketing claim ("EU-sovereign", "runs on Mistral") outruns what is shipped; unpriced model silently bills $0 against a BYOK cap; Soleur security guardrails absent in Vibe |
| **Threshold** | `single-user incident` |

Tagged user-brand-critical (auto, #5175). CPO + CLO + CTO mandatory; CMO added (new user-facing capability + positioning).

## Why This Approach

Staged by gate, not one big PR. Each stage has a different blocker (none / legal / upstream weights), so coupling them would let the slowest gate hold the fastest value, and the news window decays within days.

- **A0 before the adapter** *(second-session reorder, operator-chosen)*: the model can be dogfooded today through vehicles Soleur already has — Codex's custom `model_providers` (OpenAI-compatible) or the #1215 Ollama+proxy BYOM path — so the first quality signal lands inside the preview window without waiting on a fifth-harness build. The adapter then gets built against real eval data instead of a guess.
- **A skills-only first** because Vibe reads `SKILL.md` and `AGENTS.md` natively (no copied tree, so ADR-245's generator rule is not tripped). It mirrors Codex's first version (ADR-215). Agents (~70) are NOT ported in v1: skills that fan out to agents run each role sequentially inline with a disclosed `sequential-fallback` (Devin cloud precedent). Hooks/guardrails are unsupported on Vibe and the harness README must say so.
- **B behind a default-off flag** so code and the `MODEL_PRICING` row can land while the CLO's lockstep legal train (DPA, privacy policy, DPD, GDPR policy, T&C §3a.5, Art. 30 PA-22/PA-23 + vendor row, compliance-posture row, attestation) lands in the same PR train; flag flips only after those merge.
- **Hedge content decoupled from the build** (decouple-from-news-window pattern): ship the honest "evaluating" post now; the "runs on Mistral" claim waits for A's eval table.
- **C splits in two** *(amended in second session)*: C1 small-class self-host (Devstral Small 2 / Mistral Small 4 — single GPU, GEX44-class runbook shape, operator-spend gate) is a live dogfood stage since those weights already exist; C2 is the ML4 tracking issue only — 1T params means multi-GPU H100-class nodes, and licence + hardware are unpublished.

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Scope | A + hedge content + B spike + C tracking (operator chose all four) | Staged by gate; see table above |
| Vibe v1 agents | **Skills-only**, sequential-fallback, no agent generator | Operator chose; matches ADR-215; generator becomes follow-up |
| Vibe hooks | Unsupported in v1, disclosed | Vibe hook blocking undocumented; Soleur has 11 Claude-bound hook scripts |
| B gating | Default-off runtime flag; legal train before flip | Operator chose; CLO: no user data to Mistral before DPA |
| Tier map | Vibe ships `inherit` for all tiers | Mistral SKUs/tier semantics unmeasured; add real map after eval |
| Public claims | None beyond "evaluating" until A's eval + B's legal train | CMO/CLO: "EU-sovereign" contradicts today's legal docs (Stripe, Resend, Doppler, GitHub, Anthropic are US) |
| Staging order | Not asked of the operator — dependency-forced | Technical fork resolved by gates |
| Dogfood ordering *(session 2)* | Model before harness | Operator chose: cheapest quality signal inside the Oct 6→27 preview window via existing vehicles; the adapter is then built against eval data |
| Self-host scope *(session 2)* | Small-class only | Devstral Small 2 / Mistral Small 4 single-GPU dogfood is in scope (weights already released); ML4 (1T) self-host stays a tracking issue |
| Customer shape *(session 2)* | BYOK first; bundled later | Soleur stays out of the contract path until post-dogfood usage data exists; bundled keys = follow-up decision |
| Harness sequencing *(session 2)* | Vibe consumes the #9609 checklist | #9609 defers the adapter checklist until #9608 (Cursor) slice-1 measures which rows are stable — Vibe is its second consumer |
| Productize Candidate | `model-dogfood` eval skill | Two new-adapter/provider evaluations in one day (Cursor AM, Mistral PM); the grok-measure.sh classes want a vendor-neutral wrapper — follow-up issue |

## Non-Goals

- Hosted Concierge on Mistral (Claude SDK replacement) — parked with #6547's re-evaluation criteria.
- Self-hosting ML4 now.
- Any "EU-sovereign platform", "data never leaves the EU", "GDPR-compliant Mistral" claim.
- Quality-parity claim vs Claude (agents are prompt-engineered for Claude; needs `soleur:eval-harness` data).
- Porting Soleur's Claude hook guardrails to Vibe in v1.

## Open Questions

- ML4 weights **licence** and **hardware requirements** (blocks C; read the LICENSE/AUP live before any pull — Medium 3.5's "modified MIT" reportedly has a revenue cap, unverified).
- Is the ML4 API OpenAI- or Anthropic-compatible? (Decides whether B can reuse an existing seam or needs a new client; also gates A0's Codex `model_providers` path — session 2.)
- Vibe detection env markers: repo-research guessed `VIBE_HOME`/`VIBE_ROOT` — **unmeasured**; must be measured on a real Vibe install before the detector ships.
- Does Vibe `pre_tool` hook support blocking a call? (Decides whether any guardrail is portable.)
- Do Soleur skills run unmodified in Vibe (frontmatter fields such as `allowed-tools`)? Measure.
- ML4 API preview access for dogfood (limited audience) — unverified.
- What does Vibe telemetry send when running Soleur skills on a customer repo? (CLO: default off + disclose if Soleur ships Vibe config.)
- Is "EU sovereignty" a real demand signal? Evidence is one user quote (#1215) and one HN thread; run `soleur:product:business-validator` + 4.2 problem interviews before building a positioning on it (CPO). `(out of scope for this build)`
- `.agents/` directory: `.agents/plugins/marketplace.json` already exists for Codex; confirm Vibe's `.agents/skills` does not collide.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering (CTO)

**Summary:** A = M effort, contained in `plugins/soleur/` (harness union, parity, tier map, new `vibe/` tree); hooks are the risk. B = L (SDK coupling, no base-URL seam, Anthropic-keyed `MODEL_PRICING`); smallest increment is a priced BYOK provider on one non-agentic path. C = L-XL, defer. Order: A, B micro-spike, defer C.

### Product (CPO)

**Summary:** Sits Post-MVP/Later beside #1215, #6546, #6547. "EU sovereignty" is not a documented positioning (vision §6 "BYOK and Data Sovereignty" means tenant data control); ICP is solo non-technical founders, so a sovereignty ICP is unverified. Ship A as operator dogfood with an eval table; validate demand before B/C; fix L29 (#9500) first.

### Legal (CLO)

**Summary:** A hosted Mistral backend makes Mistral AI SAS a Jikigai sub-processor (Jikigai's server decrypts the key and relays prompts — PA-22). Needs DPA, transfer analysis per PA-7 (importer identity, not location), and a lockstep update of six legal docs plus Art. 30 and attestation. Do not claim EU-sovereign. Open-weight licence must be read before any pull. Vibe is Apache-2.0, compatible with the BSL plugin if only invoked; default Vibe telemetry off if we ship config.

### Marketing (CMO)

**Summary:** EU sovereignty would be a new pillar, not an existing one; today's docs name Anthropic (US) as processor. Honest ladder: now "harness-neutral, evaluating"; after tested integration "runs on Mistral"; after weights + licence "self-hosted open weights". Hedge-first to use the decaying news window; Mistral co-marketing only after it works.

### Operations / Finance / Sales / Support

**Summary:** Not spawned — no procurement, burn envelope, pipeline or support-process change at this scope (C's GPU procurement is deferred with its own gate).

## Capability Gaps

- **No Mistral provider anywhere in Soleur.** Evidence: `git grep -il mistral -- . ':!knowledge-base'` → only `plugins/soleur/skills/dspy-ruby/references/providers.md`; `apps/web-platform/server/providers.ts` has no `mistral` key.
- **No Vibe harness.** Evidence: `Harness` union in `plugins/soleur/lib/harness.ts:22` = claude|grok|codex|devin|unknown; no `vibe` tree under `plugins/soleur/`.
- **No provider abstraction for pricing.** Evidence: `MODEL_PRICING` in `apps/web-platform/server/inngest/functions/agent-on-spawn-requested.ts` is Anthropic-keyed (repo-research + CTO; unknown model bills at zero).
- **No Mistral DPA / sub-processor entry.** Evidence: CLO read `knowledge-base/legal/article-30-register.md`, `docs/legal/*` — no Mistral row.

## Session Errors

- repo-research reported a `cursor` member in the `Harness` union and invented `VIBE_*` env markers and "TOML skills"; all three were wrong (union read directly; Vibe skills are `SKILL.md`). File counts 51/44 were re-derived as 49/42. Orchestrator re-derived before writing this doc.
- **Session 2 (same day, ~17:50Z):** a parallel `/soleur:go` → brainstorm session on the same free-prose input did not see this worktree's artifacts — the Phase 1.1 prior-art `find` only scans the current tree, so a same-topic brainstorm in a sibling worktree was invisible until `worktree-manager.sh feature` collided on the remote namespace. That session's domain-leader + research fan-out was also refused by a free-model rate limit; the session-2 assessments above are orchestrator-synthesized. Operator-chosen outcome: amend this doc rather than keep a parallel `feat-mistral-support` worktree (removed).

## Tracking

- Umbrella: #9648. Deferred: #9649 (self-host weights), #9650 (Vibe TOML agent generator + hook portability), #9651 (validate sovereignty demand). Related: #1215, #6546, #6547.
