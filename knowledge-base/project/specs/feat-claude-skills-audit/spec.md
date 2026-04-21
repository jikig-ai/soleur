# Feature: claude-skills-audit (action plan from comparative audit of alirezarezvani/claude-skills)

## Problem Statement

The weekly competitive-intelligence report surfaced `https://github.com/alirezarezvani/claude-skills` (MIT, v2.0.0, 12.2k stars, 235+ skills) as allegedly "closest to Soleur." A comparative audit (CPO + CMO + CTO + external deep-scan) found the "closest" framing incorrect — their repo is a portable skill library, structurally different from Soleur's workflow plugin. However, the audit surfaced three high-leverage architectural patterns worth extracting, five targeted skill/agent gaps worth filling, one deferral bucket (RA/QM regulatory — off current ICP), and a need to formalize the peer-plugin-audit workflow so future CI cycles can run this comparison without hand-cranking.

No current Soleur skill does "scan peer repo → inventory skills/agents/commands → map against Soleur catalog → output port/improve/inspire recommendations." Closest analogs (`competitive-analysis`, `functional-discovery`, `agent-finder`) are scoped to SaaS-tier CI, per-feature registry queries, and stack-gap discovery respectively.

## Goals

- Productize the peer-plugin comparative-audit workflow so future peer repos surfaced by weekly CI trigger a one-command audit rather than a 3-hour manual session.
- Extract three architectural meta-patterns into existing Soleur skills (security scan, promotion loop, orchestration lanes) — zero new skills added; existing skills strengthened.
- Fill 5 confirmed gaps with targeted new skills/agents, each with its own brainstorm and founder-outcome justification.
- Update the competitive-intelligence report with a new "Skill Library" tier that correctly categorizes this class of repo.
- Publish one category-creation content piece that reframes the comparison axis on Soleur's terms.
- Defer RA/QM regulatory skills as a single "Post-MVP / Later" tracking issue for future "Soleur for regulated founders" ICP expansion.

## Non-Goals

- Wholesale port of 235 skills from alirezarezvani/claude-skills.
- Multi-tool skill converter (Claude Code → Cursor/Aider/Windsurf). Rejected by CTO — loses agent orchestration and KB integration, ships ~20% of skill value.
- Head-to-head "68 vs. 235" comparison content. Rejected by CMO — cedes the framing axis.
- RA/QM regulatory skill family (FDA 510k, MDR 745, ISO 27001, GDPR specialist, CAPA coordinator) in this cycle. Deferred.
- Skill-by-skill launch announcements. Ports bundle into ICP-expansion launches.

## Functional Requirements

### FR1: Peer-plugin-audit sub-mode in competitive-analysis

`soleur:competitive-analysis` gains a `peer-plugin-audit <repo-url>` sub-command (or sub-mode invocation). Given a GitHub repo URL, it produces a markdown report with:

- **Inventory summary** (skills, agents, commands, personas, scripts).
- **High-value gaps** (their skill/agent → no Soleur equivalent, with effort-to-adapt estimate).
- **Overlap table** (their skill → closest Soleur equivalent, which looks deeper).
- **Architectural patterns worth examining** (meta-skills, orchestration protocols, tooling conventions).
- **Recommendation** (port, improve-existing, inspire-only, reject).

Output lands in the new "Skill Library" tier of `knowledge-base/product/competitive-intelligence.md`.

### FR2: Pre-install security scan integrated into skill-creator + agent-finder

When `skill-creator` scaffolds a new skill or `agent-finder` suggests a community skill for installation, a pre-install scan runs detecting:

- Shell/Python code-execution anti-patterns (dynamic `eval`, `exec`, raw system-shell invocations, obfuscation).
- Prompt-injection attempts in SKILL.md frontmatter (system-prompt overrides, role hijacking, safety-bypass text).
- Supply-chain risk (unpinned deps, typosquats, known CVEs).
- Filesystem boundary violations (path traversal, symlinks outside designated dirs).

Scan emits `PASS | WARN | FAIL` with remediation guidance. FAIL blocks install by default.

### FR3: Promotion loop in compound + compound-capture

When `compound` captures a learning, it records an occurrence count. When the same class of learning (same topic keyword or same rule-proposal shape) is captured N times (default threshold TBD during plan — candidates 3 or 5), `compound` auto-proposes an AGENTS.md rule, skill instruction edit, or hook definition — blocking on explicit user approval before applying.

Operationalizes `wg-every-session-error-must-produce-either` so a workflow gap that has caused ≥N incidents cannot remain un-codified.

### FR4: Named orchestration lanes in brainstorm + work

Both skills expose four named lanes mapped from the external repo's orchestration protocol:

- **Solo Sprint** (one persona rotating across phases).
- **Domain Deep-Dive** (one persona stacking multiple skills within a phase).
- **Multi-Agent Handoff** (sequential persona review of each other's output).
- **Skill Chain** (procedural skills without a persona wrapper).

Each brainstorm/work session's plan explicitly selects a lane — domain-leader routing uses the lane choice to scope which specialist agents to invoke.

### FR5: Five targeted new skills/agents, each with its own brainstorm

- **tech-debt-tracker** (agent, scheduled) — persistent debt ledger with trending, reports to CTO + code-quality-analyst.
- **mcp-server-builder** (skill) — OpenAPI → MCP server scaffolding with validation.
- **incident-commander** (skill or agent — decide during brainstorm) — SEV 1-4 classification + post-mortem generation.
- **code-to-prd** (skill) — reverse-engineer codebase → PRD, complements `spec-flow-analyzer`.
- **karpathy-check** (skill or extension of `code-simplicity-reviewer` agent — decide during brainstorm) — pre-merge review against Karpathy's 4 simplicity principles.

Each candidate goes through its own `/soleur:brainstorm` with CPO + CMO + CTO domain-leader assessments (per `hr-new-skills-agents-or-user-facing`) before planning and implementation. Any candidate that fails to name a founder outcome it unblocks is deferred.

### FR6: New "Skill Library" tier in competitive-intelligence.md

New tier added alongside Tier 0 / Tier 3 for portable-skill-library competitors. Initial entry: `alirezarezvani/claude-skills`. Overlap Matrix columns: Our Equivalent, Overlap, Differentiation, Convergence Risk. First convergence risk: Low (complementary product shape).

### FR7: One category-creation content piece

Blog/long-form content titled approximately "Skill libraries vs. workflow plugins: why Soleur is a different shape." Authored via `copywriter` + `content-writer`, reviewed by `fact-checker`. No head-to-head counts. Cites alirezarezvani/claude-skills as a category exemplar, not a competitor.

### FR8: RA/QM deferral issue

Single issue in `Post-MVP / Later` milestone titled "Evaluate RA/QM regulatory skill family for Soleur-for-regulated-founders ICP." Re-evaluation criteria: Soleur onboards first customer in a regulated industry (medical device, healthcare, financial services, enterprise-SOC-2-requiring) OR explicit roadmap decision to target regulated ICPs.

## Technical Requirements

### TR1: Architecture compatibility — no stdlib-Python-CLI skills

All new Soleur skills follow the existing Soleur skill contract: `SKILL.md` with YAML frontmatter + optional `scripts/*.sh` (bash) + optional `references/*.md` + agent-orchestration and KB integration. No direct ports of their stdlib Python CLI scripts — the valuable artifact is the SKILL.md body (domain prompt), not the Python implementation.

### TR2: Token-budget compliance

Each new skill description ≤ ~30 words (target). Cumulative skill-description total (via `bun test plugins/soleur/test/components.test.ts`) must stay under 1800 words after all Tier 1 + Tier 2 additions. Existing-skill descriptions may be compressed if needed. Agent description cumulative target <2500 words (hook-enforced).

### TR3: MIT attribution

When a new Soleur skill is directly inspired by a specific external repo skill (not just inspired by general industry practice), the SKILL.md file includes an attribution comment in the body (not in frontmatter):

```markdown
<!-- Inspired by alirezarezvani/claude-skills/<path> (MIT, Copyright (c) 2025 Alireza Rezvani). -->
```

No verbatim copies of their code. Attribution is not required in marketing/launch copy per CMO.

### TR4: Security-scan integration — FAIL by default

The FR2 pre-install scan is wired into `skill-creator` post-scaffolding and `agent-finder` pre-install with FAIL blocking by default. Override requires explicit `--acknowledge-scan-failures` flag + written justification in the skill's PR body. Supply-chain-scanner data source TBD during plan (candidates: osv.dev API, GitHub Advisory Database, Snyk free tier).

### TR5: Promotion-loop manual-confirm gate

The FR3 promotion loop never auto-applies AGENTS.md rule edits. It drafts the proposed change and surfaces via `AskUserQuestion` (or equivalent confirmation surface) with the exact diff, the N occurrences that triggered it, and links to the original learning files. Prevents runaway rule-inflation.

### TR6: Sub-mode discoverability

The FR1 `peer-plugin-audit` sub-mode is listed in `competitive-analysis`'s SKILL.md routing section AND in `/soleur:help` output when available. The existing weekly CI report workflow (if any) references the sub-mode in its runbook.

### TR7: Backwards-compatibility guarantee for existing skills

None of the three meta-pattern extractions (FR2, FR3, FR4) break existing workflows. Security scan defaults active but skippable for already-installed skills (scan-on-demand). Promotion loop is additive to `compound`, not a replacement. Named orchestration lanes default to auto-detection of an appropriate lane when no explicit choice is made — existing brainstorm/work invocations behave unchanged.
