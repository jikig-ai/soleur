---
date: 2026-07-04
topic: gstack-capability-adoption
lane: cross-domain
brand_survival_threshold: single-user incident
status: brainstorm-complete
pr: 5982
---

# Brainstorm: Adopting gstack capabilities into Soleur

## What We're Building

A wave-sequenced epic that adapts 12 capabilities from **gstack** (Garry Tan's
Claude Code library, ~119k★) into Soleur's committed-knowledge, operator-legible
frame. gstack targets *technical* founders with per-machine `~/.gstack` state,
multi-model and multi-host machinery; Soleur targets *non-technical* solo
founders with repo-committed knowledge and an all-Claude model policy. The epic
imports gstack's **engineering-craft depth** (design taste, decision discipline,
runtime monitoring, hardening) while rejecting its per-machine/multi-host
machinery, which contradicts Soleur's constitution.

Full source comparison lives in the session that produced this brainstorm; the
12 candidates and their gstack origins are enumerated in the spec.

## Why This Approach

Operator chose **"all 12 in scope"** delivered as a **wave-sequenced epic**
(umbrella + per-item sub-issues, PRs landing in dependency order) rather than
independent one-shots — the shared-surface bundles (PreToolUse hook, docs,
agent-wiring) and the two dependency chains would otherwise cause throwaway work
or conflicting hook rewrites.

Two CTO/CLO-convergent dependency chains drive the ordering:
- **T1-3 decision-principles → T1-4 plan panel** — the Mechanical/Taste/User-Challenge
  classifier is the arbitration logic the multi-dimensional panel needs to avoid
  auto-deciding taste calls.
- **T2-6 declarative context-injection → T2-5 taste-learning** — the taste-profile
  loader *is* a `context_queries` consumer; building the mechanism first prevents
  a bespoke loader that gets ripped out.
- **CLO gate:** redaction hardening (T2-7) ships before any feature that increases
  data egress.

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| D1 | All 12 candidates in scope | Operator directive |
| D2 | Wave-sequenced epic (umbrella + per-item/bundle sub-issues) | Preserves dependency order + shared-surface bundles |
| D3 | **Drop cross-vendor OpenAI review**; substitute a two-Claude-persona "User-Challenge / cost-if-wrong" pass using `fable`→`opus` | CTO+CLO convergent; no new sub-processor, no privacy-doc/Art.30/SCC churn, non-technical operators can't consent to an unknown sub-processor |
| D4 | Extend the **existing ADR-083 scoped consult** (plan Step 4.5 / ship Phase 5.5) for D3 — do NOT build a new mechanism | ADR-083 already wires `fable`→`opus` at two decision gates |
| D5 | **Defer canary + web-vitals (T1-1+T1-2) to Wave 4** behind a new ADR | Repo uses agent-browser CLI, NOT Playwright; Lighthouse/INP needs Playwright = deliberate new dependency; needs stable deployed URL + auth first |
| D6 | Bundle T2-8 + T3-11 (same PreToolUse hook surface) into one PR | Avoid two conflicting `guardrails.sh` rewrites |
| D7 | Bundle T3-9 + T3-10 (docs-site/content-writer surface) | Shared surface |

### Wave plan

| Wave | Items | Effort | Notes |
|------|-------|--------|-------|
| **1 — cheap engine wins** | T1-3 decision-principles (extends ADR-083), T1-4 named plan panel (wires existing cpo/cmo/cto/ux-design-lead), T3-12 operator velocity metrics | S | T1-3 unblocks T1-4 |
| **2 — safety + memory spine** | T2-7 redaction hardening, **T2-8+T3-11 bundled** (delete guards + freeze edit-lock), T2-6 declarative context-injection | M | Highest blast radius: T2-6 touches SessionStart loader all ~90 skills use; redaction precedes any egress |
| **3 — build on the spine** | T2-5 taste-learning (rides T2-6), **T3-9+T3-10 bundled** (Diataxis docs + MD→PDF) | M | Depend on Wave 2 |
| **4 — deferred, needs ADR** | **T1-1+T1-2** one Playwright runtime-measurement harness (visual canary + Core Web Vitals) | L | ADR: "Playwright harness alongside agent-browser CLI" + deployed URL/auth story |

## Open Questions

- **OQ1 (Wave 4 gate):** what is the stable deployed-preview URL + auth story the
  canary/vitals harness measures against? Blocks T1-1+T1-2; resolve in the ADR.
- **OQ2:** T2-6 declarative-injection — extend the SessionStart hook loader, or a
  new per-skill frontmatter reader? Decide at plan time; blast radius demands a
  fail-open-on-parse-error design (a parse bug must not fail-closed all skills).
- **OQ3:** T3-12 velocity metrics for a *single* non-technical operator — confirm
  which metrics are legible (shipping cadence, cost trend) vs. noise (context-switching).

## Domain Assessments

**Assessed:** Engineering, Legal (scoped to the two items with technical/legal weight; Marketing/Product/Ops/Sales/Finance/Support not spawned — this is internal plugin tooling, not a user-data product surface).

### Engineering (CTO)

**Summary:** Corrected two source assumptions — `test-browser` uses agent-browser
CLI not Playwright MCP (canary/vitals = new dependency + ADR, L-effort), and
context-injection is the SessionStart hook loading `AGENTS.{core,docs,rest}.md`
(T2-6 is highest-blast-radius). Recommends build order T1-3 → T1-4 → T2-6 →
(T2-8+T3-11) → T2-7 → T2-5 → T3-9/10/12; defer T1-1+T1-2; drop cross-vendor,
substitute two-Claude-persona review. Top risks: (1) canary/vitals need deployed
URL+auth+stable baseline; (2) T2-6 loader parse-bug fails-closed all skills;
(3) T2-8/T3-11 both edit shared PreToolUse `guardrails.sh` — freeze-deny can
shadow existing sentinel checks.

### Legal (CLO)

**Summary:** Cross-vendor OpenAI review routes operator (and operator-*customer*)
data to a new sub-processor → GDPR Art.28/44 disclosure, three privacy docs +
Art.30 register + SCCs in lockstep; non-technical operators cannot give informed
consent. Recommend the Anthropic-only two-persona substitute (no reversal).
Redaction hardening (T2-7) is high-priority and MUST precede any egress feature.
Delete guards reduce erasure-integrity/data-loss risk. Order: T2-7 → T2-8 → only
then reconsider any egress.

## Capability Gaps

Genuinely ABSENT in Soleur today (evidence: CTO grep of `plugins/soleur/skills/`,
`plugins/soleur/agents/`, and `.claude/hooks/`):
- **Runtime web-vitals / Lighthouse measurement** — `performance-oracle` reviews
  *code*, not runtime; no LCP/CLS/INP harness. (T1-2)
- **Client-side post-deploy synthetic canary** — `postmerge` watches infra/SDK
  rollback + prod health, no per-page screenshot/console-error baseline. (T1-1)
- **Persistent design taste model** — no `taste-profile` artifact; `frontend-design`/
  `ux-design-lead` generate without a learned-preference loop. (T2-5)
- **Diataxis doc structuring** — `docs-site` scaffolds Eleventy, no tutorial/how-to/
  reference/explanation framing; zero "diataxis" refs in plugin. (T3-9)
- **Markdown→PDF** — no operator-deliverable PDF path. (T3-10)

PARTIAL (adjacent coverage, extend not build): decision discipline (ADR-083
consult exists), plan review (eng-only today), context injection (SessionStart
hook exists), redaction (incident/code-to-prd/legal paths exist), delete guards
(`guardrails.sh` blocks rm-rf on worktrees/root), operator digest (`operator-digest`).

## User-Brand Impact

- **Artifact:** the gstack-adoption epic's changes to Soleur's engine surfaces
  (PreToolUse hooks, SessionStart context loader, redaction paths, review gates).
- **Vector:** a regression in the shared hook/loader surface (T2-6/T2-8/T3-11)
  silently disarms a guardrail or fails-closed every skill for one operator mid-session.
- **Threshold:** single-user incident.

## Session Errors

- The "Anthropic-only = ADR-083" citation carried from the prior synthesis was
  wrong: ADR-083 is the *scoped strong-model consult*; the all-Claude model policy
  is **ADR-053**. Both domain leaders repeated the wrong citation until
  premise-validation grep corrected it. Lesson: verify ADR numbers against the
  corpus before threading them into leader prompts.
