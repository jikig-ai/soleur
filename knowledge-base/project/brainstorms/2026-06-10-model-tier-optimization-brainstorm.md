---
title: Model-Tier Optimization for the Fable 5 Era
date: 2026-06-10
status: decided
lane: cross-domain
brand_survival_threshold: single-user incident
closes: "#3791"
---

# Model-Tier Optimization: Workflow Call-Site Tiering

## What We're Building

Tiered model selection for Soleur's subagent spawns, triggered by Anthropic's Fable 5 release ($10/$50 per MTok — 2× Opus 4.8, 3.3× Sonnet 4.6, 10× Haiku 4.5). Today every one of the 66 agents uses `model: inherit` and none of the 8 dynamic-workflow scripts pass `opts.model`, so a Fable 5 session runs every grep sweep, web fetch, parse step, and commit-message agent at the top price tier.

v1 scope (Approach A — workflow call-site tiering):

1. **Workflow `opts.model` pins** at the ~14 allowlisted mechanical `agent()` steps across the 8 `*.workflow.js` scripts (parse, classify, fetch, commit, file, report, cluster). Sonnet is the workhorse downgrade tier; Haiku only for trivially small parse/fetch/file steps (200K context, no `effort` support).
2. **Cheap-tier spawn guidance** in SKILL.md prose for Explore/research fan-outs (deepen-plan per-section research, resolver trio, brainstorm Phase 1.1 research agents) via the Agent tool's per-call `model` parameter. Advisory, documented as such.
3. **Pin `claude-code-review.yml`** — the per-PR CI review action currently has no `--model` pin at all (drift-prone unattended spend).
4. **Inngest cron tier registry** — centralize the 15 web-platform cron model constants (currently ad-hoc per-file: 10× Sonnet, 5× Opus 4.7) into one workload-class registry.
5. **Tier-attribution telemetry** — extend `.claude/hooks/agent-token-tee.sh` (#3494) to record the model per spawn in `.claude/.session-tokens.jsonl`, satisfying `hr-observability-as-plan-quality-gate`.
6. **Amend the Model Selection Policy** in `plugins/soleur/AGENTS.md` (lines ~144-151): replace "no exceptions" with the three-tier vocabulary + allowlist criteria; each workflow pin requires a one-line justification comment at the call site. Lands in the same PR as the first pin.

**Agent frontmatter is untouched** — all 66 agents keep `model: inherit`.

## Why This Approach

- **The prior "no downgrades" decisions are stale on their own terms.** The Feb-2026 policy (PR #295) predates the workflow-script architecture and unbounded fan-outs; the Apr-2026 token-optimization brainstorm ruled out downgrades when `inherit` meant Opus. Issue #3791 deferred this exact work with "a pricing change" as a re-evaluation trigger — Fable 5 is that trigger.
- **Anthropic's own agent-design guidance endorses the pattern**: "Spawn a subagent with the cheaper model for the sub-task; keep the main loop on one model — Claude Code's Explore subagents use Haiku this way." Subagent dispatch on a cheaper model is cache-safe (fresh context); mid-session switching is not.
- **The web platform already runs tiered in production** (Sonnet concierge, Haiku domain-routing/triage, Opus growth-audit cron) — this extends an existing pattern to the plugin rather than inventing one.
- **Default-deny downgrades, explicit allowlist for cheap tiers** (CPO): a cheaper model only runs where the failure mode is "slow/retry," never "wrong work ships." The review layer is the safety net for the execution layer — which only works if the review layer itself is never downgraded.
- Frontmatter tiering (Approach B) was rejected as blunt: it applies in every spawn context, silently *upgrades* a deliberately-cheap session, and re-fights the Feb-2026 reversal. The full program (Approach C) was trimmed: the BYOK ledger column is deferred to a follow-up issue.

## User-Brand Impact

- **Artifact:** operator's Anthropic bill (BYOK) / Max quota (flat-rate seats); quality of shipped work product.
- **Vectors (operator selected "All"):** (a) billing surprise — Fable 5 used everywhere multiplies fan-out cost 2-10×; (b) degraded work quality — a cheaper model silently underperforming on a delegated task (e.g. a downgraded migration review missing a data-loss bug that ships to the operator's product).
- **Threshold:** single-user incident. One silently-missed P1 bug from a downgraded reviewer is brand-fatal; this is why review/security/compliance paths are exempt by construction, not by configuration.

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | Tier at workflow call sites (`opts.model`), not agent frontmatter | Versioned, testable code closest to the spawn decision; frontmatter pins are static and context-blind; preserves operator session-model agency |
| 2 | Never-downgrade exemption: all `engineering/review/*` agents, data-migration-expert, security/SAST, legal/compliance (clo, gdpr-gate, data-integrity-guardian), C-suite strategy, workflow `verify`/`concur`/synthesis steps, resolver/implementer fan-outs | Silent recall loss is the brand-fatal failure mode; CLO: weakening a GDPR Art. 24/32 organizational measure without reassessment is itself an accountability gap |
| 3 | Sonnet 4.6 is the workhorse downgrade tier; Haiku 4.5 only for trivially small parse/fetch/file steps | Haiku: 200K context (fan-out diffs can overflow), no `effort` parameter, separate rate-limit pool |
| 4 | Pins are absolute, not session-relative | The runtime only supports absolute `model` values; only pin steps where a fixed cheap tier is always correct, never "one tier below session" (avoids silent upgrades of cheap sessions) |
| 5 | Policy amendment ships in the same PR as the first pin | Avoids policy/practice drift (CTO risk: Medium) |
| 6 | Tier-attribution telemetry ships with or before the pins | `hr-observability-as-plan-quality-gate`; extends existing `agent-token-tee.sh`, no new infra |
| 7 | Quality gate: side-by-side on one real workflow run (tiered vs untiered), comparing output quality + token spend from telemetry JSONL | Proportionate for mechanical-steps-only scope; persistent eval set rejected as over-engineering at this stage |
| 8 | Automatic by default; disclosure over configuration | Target user is a non-technical operator — no per-agent model matrix; model-in-use disclosed in run output; global escape hatch deferred until demand |
| 9 | Tracking issue: adopt #3791 (supersedes its deferral); #2030 (advisor tool, web platform) noted as complementary API-level lever | Avoid parallel-tracking an open issue that already owns this scope |
| 10 | BYOK billable-run tiering deferred | If tiering ever applies to Web Platform BYOK runs: `audit_byok_use` needs a `model` column + Privacy Policy/DPD/T&C lockstep (CLO Finding B) — follow-up issue |
| 11 | Productize Candidate: `model-launch-review` skill | Every model release (4.6→4.7→4.8→Fable 5) re-triggers the same audit: ID swaps, action-pin sync, thinking-API shape, tier re-evaluation. Recurring pattern; follow-up issue, not v1 scope |

## Sharp Edges / Gotchas (carry into plan)

- **Action-pin sync:** changing `--model` in any CI workflow against a stale `anthropics/claude-code-action` pin 400s (rule `cq-claude-code-action-pin-freshness`; learning 2026-04-18).
- **Thinking-API shape differs per tier:** Fable 5/Opus 4.7+ use `thinking: adaptive` + `output_config.effort`; Sonnet 4.6 deprecates but accepts `budget_tokens`; Fable 5 400s on explicit `thinking: disabled`. Any cron/CI model swap must swap the thinking config with it.
- **Tier changes change error surfaces:** Sonnet 4.6 400s on assistant-prefill resume (the prefill-guard exists for this — learning 2026-06-03).
- **Per-agent effort does not exist in the plugin spec** — tiering must come from model choice; `CLAUDE_CODE_EFFORT_LEVEL` is session-global (pinned `high` in `.claude/settings.json`).
- **Who pays:** operator Max seats are flat-rate — plugin-side savings are quota headroom, not dollars. Real per-token savings accrue to BYOK users (~65-80% per fan-out run, CFO estimate) and metered cron spend.
- **Telemetry correction:** per-agent token telemetry already exists (`agent-token-tee.sh`, #3494); the gap is model attribution + aggregation only. Two leader agents (CTO, CFO) asserted otherwise — corrected by repo grep.

## Open Questions

1. Exact per-step tier map for the ~14 mechanical workflow steps (Sonnet vs Haiku per step) — decide at plan time with the token-budget discipline from learning 2026-05-11 (model the runtime prompt, not file size).
2. Where exactly model-in-use disclosure surfaces (workflow `log()` line vs PR body vs both).
3. Inngest registry shape: workload-class enum (routing/mechanical/judgment) vs per-cron explicit entries.
4. Whether `claude-code-review.yml` pins Sonnet (cost) or stays on the action default pinned explicitly (drift-fix only).

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering (CTO)

**Summary:** Tier via workflow `opts.model` at allowlisted mechanical steps only; keep all 66 frontmatters on `inherit`; keep every review/judgment path untouched (recall loss is silent and no eval harness exists). Risks: policy/practice drift (land policy + pins in one PR), tier-inversion (pins are absolute — never "one tier below session"), Haiku context limits. Phasing: telemetry first, then parse/fetch/commit/file pins, then evaluate research fan-outs against a real run. Recommends an ADR for the tiering semantics.

### Product (CPO)

**Summary:** Target user is a non-technical solo founder — automatic by default, no per-agent config surface; visible-but-not-interactive (disclosed in output, globally overridable later). Default-deny downgrades with an explicit cheap-tier allowlist. Found the `spawnClaudeEval()` cron surface (~20 consumers, no model flag) as the highest-leverage unattended spend. MVP: policy amendment + mechanical-step tiering + disclosure; per-operator model UI and dynamic routing are over-engineering.

### Legal (CLO)

**Summary:** No published commitment names a model tier, so plugin-side tiering breaches nothing by name. Three requirements: hard exemption list for compliance/security/attestation agents (changing it is a clo-attestation-class change); operator visibility rather than silence; if tiering reaches BYOK billable runs, `audit_byok_use` needs a `model` column + Privacy Policy/DPD/T&C lockstep (deferred, tracked). Anthropic ToS does not prohibit per-call model selection — it's the documented pattern.

### Finance (CFO)

**Summary:** Three spend buckets with different economics: operator Max seats (flat-rate — savings are quota headroom), BYOK users (real 65-80% per-run savings; this is users' money and product competitiveness), metered crons ($15/mo today, grows with scheduled automation). Input-side context re-reads dominate cost (>20:1 input:output in agentic loops) — tiering attacks exactly that line. Measurement protocol: transcript `usage` blocks on a fixed sample, per-run spend summary in workflow output.

## Capability Gaps

- **Tier-attribution + aggregation in token telemetry** (Engineering). Evidence: `grep -n "model" .claude/hooks/agent-token-tee.sh` — the hook records `totalTokens`/`totalToolUseCount`/`totalDurationMs` per Agent spawn but no model field; `knowledge-base/finance/` has no per-workflow token feed. Needed to verify savings and re-validate the tier map at each model release. (Note: the telemetry *capture* layer itself exists — #3494 — contrary to two leader assessments; only the model-attribution column and aggregation are missing.)

## Lane

cross-domain (inferred from "audit"/"review" triggers; confirmed by operator). USER_BRAND_CRITICAL=true (operator selected "All" — billing surprise + degraded quality + no-direct-impact).
