---
title: Harness Engineering Review — Soleur Workflow Audit
date: 2026-05-04
branch: feat-harness-engineering-review
pr: 3119
sources:
  - https://martinfowler.com/articles/harness-engineering.html
  - https://developers.redhat.com/articles/2026/04/07/harness-engineering-structured-workflows-ai-assisted-development
  - https://www.philschmid.de/agent-harness-2026
  - https://ai.gopubby.com/harness-engineering-what-every-ai-engineer-needs-to-know-in-2026-0ab649e5686a
---

# Harness Engineering Review

Audit of Soleur's workflow against four 2026 essays on agent harness engineering: Martin Fowler (taxonomy of feedforward/feedback controls), Red Hat (structured-workflow planning with grounded code analysis), Phil Schmid (the harness as OS / dataset), and Liu / AI gopubby (harness obsolescence as the dominant design pressure).

## What We're Building

Not a feature — a workflow audit producing a prioritized list of harness gaps and proposed improvements. The deliverable is decisions about which gaps to convert into tracked issues and brainstorms.

## Article Synthesis

| Source | Core thesis | Strongest prescription |
| --- | --- | --- |
| Fowler | Harness = guides (feedforward) + sensors (feedback), split across maintainability / architecture-fitness / behavior categories | Distribute checks across change lifecycle by cost/speed; make linter messages prompt-injectable so the agent self-corrects |
| Red Hat | Structured workflows replace "vague-in, vague-out" with grounded planning + structured task templates | Produce a Repository Impact Map (real file paths + symbols) BEFORE task creation; human review checkpoint between planning and implementation |
| Schmid | Harness is the OS layer above models; build to delete; harness is the dataset | Capture trajectories as competitive advantage; expect to refactor every 6 months as models change |
| Liu | Harness components decay quickly: "load-bearing in March, dead weight by April" | Design for adaptability over stability; harness simplification as models advance is itself a discipline |

## Where Soleur Already Aligns (Strong)

- **Feedforward guides (Fowler):** AGENTS.md (89-line / ~115-rule cap with byte budget), CLAUDE.md inheritance, `knowledge-base/`, 67 skills, ~9 domain leaders + many specialists.
- **Computational sensors:** lefthook (`lint-rule-ids.py`), `guardrails.sh`, CI workflows, hook-enforced rules tagged `[hook-enforced: ...]` in AGENTS.md.
- **Inferential sensors:** `/soleur:review` multi-agent (DHH, Kieran, simplicity, security-sentinel, performance-oracle, type-design-analyzer, agent-native-reviewer, user-impact-reviewer, semgrep-sast); `/ultrareview` cloud review; per-domain compliance auditors.
- **Three regulation categories:**
  - Maintainability: `/soleur:simplify`, code-quality-analyst, pattern-recognition-specialist.
  - Architecture: architecture-strategist, ADR skill, `hr-all-infrastructure-provisioning-…` (Terraform-only), `cq-pg-security-definer-search-path-…`.
  - Behavior: `atdd-developer`, `cq-write-failing-tests-before` work-skill TDD gate, `test-fix-loop`.
- **Structured workflow (Red Hat):** explicit `brainstorm → plan → work → ship` lifecycle with worktree isolation, draft PR seeded at brainstorm time.
- **Grounded planning (Red Hat):** plan skill enforces `## Files to Edit` / `## Files to Create` enumeration with `git ls-files | grep -E` glob verification (`hr-when-a-plan-specifies-relative-paths`); ~25 plan-skill learnings instruct path/symbol grep-verification before drafting.
- **Repository as source of truth (Red Hat):** AGENTS.md inherits via CLAUDE.md; rules tagged with `[skill-enforced: <skill> <phase>]` so the rule and its enforcement are co-located.
- **Steering loop (Fowler):** `/soleur:compound` after every commit; learnings route to skill edits or AGENTS.md additions; `wg-when-a-workflow-gap-causes-a-mistake-fix-skill-first` — verbal acknowledgment is not a fix.
- **Inferential review of plans (Red Hat human-in-loop):** `/soleur:plan-review` (DHH + Kieran + simplicity reviewers); `deepen-plan` Phase 4.x gates.
- **Self-correcting linter messages (Fowler):** `[hook-enforced]` markers + `Why:` lines in AGENTS.md rules tell the agent why and how to recover.
- **Build-to-delete (Schmid):** `skill-creator`, `heal-skill`, `retired-rule-ids.txt` for AGENTS.md, plugin/marketplace versioning.
- **Telemetry (Schmid trajectories):** `incidents.sh emit_incident` records when each rule fires; weekly aggregator for rule-application counts.
- **User-impact framing (cross-cutting):** brainstorm Phase 0.1 + plan Phase 2.6 + deepen-plan Phase 4.6 + preflight Check 6 + user-impact-reviewer — load-bearing per `hr-weigh-every-decision-against-target-user-impact`.

## Gaps & Improvement Candidates

### Theme A — Behavior harness uplift (Fowler: "behavior harness is not good enough yet")

A1. **Mutation testing absent.** Fowler explicitly calls it out as a feedback sensor. Soleur has zero mutation-testing infrastructure. Worth piloting on `apps/web-platform/server/` critical paths.

A2. **Approved-fixtures / golden-test pattern not systematic.** We have ad-hoc snapshot tests but no convention for stable-surface golden tests (e.g., LLM prompt outputs, Markdown→HTML rendering, SQL builders).

A3. **ATDD enforcement is opt-in.** `cq-write-failing-tests-before` exists but is gated by "if a plan includes Test Scenarios or Acceptance Criteria." User-facing changes routinely ship without ATDD. Could harden the trigger.

A4. **Architectural fitness functions not codified in CI.** Architecture review agents are inferential; we lack computational fitness gates (bundle-size budgets, p95 latency budgets, cyclomatic complexity caps, dependency-cruiser layer rules).

### Theme B — Symbol-level grounding (Red Hat: Repository Impact Map)

B1. **Plan does not produce a separate "Impact Map" artifact.** Files-to-Edit/Create sections exist inside the plan, but a focused Impact Map review checkpoint (paths + symbols + existing-pattern references) before task expansion is implicit, not enforced.

B2. **LSP symbol verification at plan time is not codified.** The `LSP` tool exists; many plan-skill learnings instruct `rg '^function <symbol>'`-style greps, but LSP-driven "does this symbol exist; here are its references" is not a plan-skill step. Plans still cite symbols that have been renamed or deleted.

### Theme C — Drift & rot detection (Fowler: ambiguous signals; orphaned controls)

C1. **Audits require manual invocation.** `ux-audit`, `agent-native-audit`, `seo-aeo`, `legal-audit`, `competitive-analysis` exist but most are not on a schedule. `/soleur:schedule` is the wiring; the schedule itself is sparse.

C2. **Never-fired rules are invisible.** `incidents.sh` records when rules fire. There is no report for rules that have NEVER fired over N days (potentially dead, never-needed, or detection broken — Fowler's "ambiguous signal" warning).

C3. **Skill freshness is not telemetry-tracked.** No "last-applied" date per skill; no flag for skills that haven't been invoked in > 90 days. Pairs with C2.

C4. **Hook coverage on `[hook-enforced]` claims.** AGENTS.md rules tag themselves `[hook-enforced: <hook>]` but there is no test that asserts the hook actually exists and rejects the violation. Tag rot is a known class.

### Theme D — Trajectory dataset & eval (Schmid: harness is the dataset)

D1. **No regression eval suite for new harness rules.** When we add an AGENTS.md rule or skill phase, we don't run it against a corpus of past failures (the issues it's meant to prevent) to verify it would have caught them. Closes the steering loop tighter — Fowler's "if sensors never fire, is quality high or detection broken?" is partially answered by a positive corpus.

D2. **Failure trajectories not captured into a dataset.** `compound` writes prose learnings, but the full agent transcript that produced the failure is not extracted into a structured dataset (input → tools → output → root cause). Schmid's central thesis is that this data is the moat.

D3. **Post-ship trajectory analysis is absent.** When a brainstorm pivots heavily mid-session, abandons, or ships in 2x the planned scope, that's signal. We don't aggregate it.

### Theme E — Build-to-delete cadence (Schmid + Liu: harness decay)

E1. **Quarterly / model-upgrade harness retirement review.** When a new model lands (Opus 4.7 → 4.8), some rules become obsolete (the model now self-corrects) and some need tightening (the model hallucinates differently). We have `retired-rule-ids.txt` mechanics but no scheduled retirement review. Schmid: Manus refactored 5x in 6mo; LangChain 3x in a year; Vercel cut 80% of agent tools. Liu: "load-bearing in March, dead weight by April."

E2. **Pre-rule additive bias.** Soleur's compounding loop is biased toward adding rules — `wg-when-a-workflow-gap-causes-a-mistake-fix-skill-first` and the per-rule incident telemetry both grow the harness. There is no symmetric pressure to *remove* rules when they are no longer load-bearing. The 600-byte / ~115-rule cap forces trimming, but only at the budget threshold — not by ongoing relevance review. Liu's central observation: simplification *as models advance* is its own engineering discipline, not a budget-driven side effect.

### Theme F — Harness templates per service topology (Fowler)

F1. **Only one topology template (`docs-site`).** Fowler advocates pre-built bundles per topology (CRUD API, event processor, dashboard). Soleur has skills but not topology-bundled scaffolds. Lower priority — apps/web-platform is the only sustained app today.

## Why This Approach

Rather than a single sweeping refactor, treat each theme as an independent track that can ship asynchronously. Apply YAGNI: pick the 1-2 themes with the highest ratio of (failure cost prevented) / (build cost) and defer the rest.

**Likely highest-ratio bets (operator's call):**

- **D1 (regression eval suite for harness rules)** — closes Fowler's "ambiguous signals" loop and gives every future rule addition a verifiable claim. Low build cost (corpus = closed issues with `Closes #N` references already in git).
- **C1+C2 (scheduled audits + stale-rule reporter)** — makes our existing audits load-bearing instead of forgotten. Cheap.
- **B1 (Impact Map artifact)** — Red Hat's load-bearing prescription; we already have ~80% of it inside the plan; making it a separate reviewable artifact is mostly process, not code.

**Higher-effort bets to consider:**

- A1 (mutation testing pilot)
- D2 (trajectory dataset capture)

## Key Decisions

| # | Decision | Rationale |
| --- | --- | --- |
| 1 | Output is a prioritized improvement list, not a single feature | Each theme has independent build/ship risk |
| 2 | Defer to operator which themes to convert into tracked issues | Avoid speculative scope creep |
| 3 | Capture full text in brainstorm doc, not in AGENTS.md | Audit findings are not session invariants |

## Open Questions

- Which themes (A-F) does the operator want to convert into tracked GitHub issues right now? **Resolved 2026-05-04:** D+C2, A, C1+C3.
- Is there appetite for D1 (regression eval suite) as the first track? It's the most novel and most directly answers "are we doing harness engineering well?" **Resolved:** yes — see #3120.
- Should mutation testing (A1) pilot on `apps/web-platform/server/` or wait for a less time-pressured moment? **Deferred to issue #3121.**

## Tracked Follow-ups

- #3120 — Harness eval suite + stale-rule reporter (Theme D+C2)
- #3121 — Behavior harness uplift: mutation testing, golden tests, ATDD, fitness functions (Theme A)
- #3122 — Scheduled audits + skill freshness telemetry (Theme C1+C3)
- Themes B, E, F: not converted to issues this session — captured here for future reference.

## Domain Assessments

**Assessed:** Engineering (CTO).

### Engineering

**Summary:** This audit is squarely engineering-domain — workflow architecture, tooling, and rule infrastructure. The findings are derived from rule inventory in main context (AGENTS.md is fully loaded every turn) plus targeted greps of the plan skill. No domain leader spawn was needed because the entire harness inventory is already in working memory; spawning would have re-derived known information at higher cost. Other domains (Marketing/CMO, Product/CPO, etc.) are not relevant: this is internal tooling, not a user-facing capability or content-opportunity surface. The `hr-new-skills-agents-or-user-facing` rule does not yet apply because we have not committed to building a new skill — we are auditing the existing ones.

## Capability Gaps

(No new capability gaps; all gaps are improvements to existing harness layers.)
