---
title: feat: passive domain leader routing for mid-conversation signals
type: feat
date: 2026-03-12
---

# feat: passive domain leader routing for mid-conversation signals

## Overview

Add always-on domain leader routing so that when a user mentions domain-relevant information mid-conversation (expenses, legal obligations, marketing signals), the agent auto-routes to the relevant domain leader as a background task. Also remove the AskUserQuestion confirmation gate from brainstorm Phase 0.5 for consistency.

## Problem Statement / Motivation

Domain leader routing only fires during brainstorm Phase 0.5 — at task initiation time. If a user says "I subscribed to X Premium" during an engineering task, the COO's expense tracking never triggers. This leaves business-relevant signals unrecorded.

## Proposed Solution

Four file edits, no new files:

1. **`AGENTS.md`** — Add a `## Passive Domain Routing` section (2 bullets) and scope the zero-agents exception
2. **`plugins/soleur/skills/brainstorm/SKILL.md`** — Rewrite Phase 0.5 Processing Instructions to auto-fire without AskUserQuestion; add explicit workshop invocation path
3. **`plugins/soleur/skills/brainstorm/references/brainstorm-domain-config.md`** — Update header instruction to remove AskUserQuestion reference
4. **`plugins/soleur/AGENTS.md`** — Update Domain Leaders table entry points and "Adding a New Domain Leader" checklist

## Design Decisions

1. **Zero-agents exception:** Scope `AGENTS.md:22` to exclude passive domain routing. The zero-agents rule prevents premature research agents, not domain assessments.
2. **Workshop vs. assessment:** Passive routing always uses assessment mode. Workshops remain explicitly user-invoked ("start brand workshop" / "run validation workshop"). Phase 0.5 defaults to assessment but preserves workshops as a conditional path triggered by explicit user request.
3. **Domain config header:** Update to describe auto-fire pattern. Routing Prompt and Options columns retained for workshop reference only.
4. **AGENTS.md leanness:** 2 bullets maximum. One for the behavioral rule (including qualifying language), one for `run_in_background` and the config reference. Per lean AGENTS.md convention — only what the LLM would violate without being told.
5. **No deduplication clause:** The LLM has conversational context and can see what it already spawned. Adding explicit deduplication rules is defensive programming against a failure mode unlikely in a single-turn context.
6. **No explicit per-message cap:** The global 5-agent constitution limit is sufficient. Most real signals trigger 1-2 domains.
7. **No return contract format:** Existing Task Prompts say "Output a brief structured assessment." The LLM produces readable output. Formalize later if output quality is actually poor.

## Acceptance Criteria

- [x] AGENTS.md has a `## Passive Domain Routing` section (2 concise bullets)
- [x] The "zero agents until user confirms" rule is scoped to exclude passive domain routing
- [x] Brainstorm Phase 0.5 auto-fires domain leaders without AskUserQuestion
- [x] Domain config file header updated to reflect auto-fire behavior
- [x] Workshop paths reachable via explicit user request (not dead code)
- [x] `plugins/soleur/AGENTS.md` Domain Leaders table reflects new entry points

## Test Scenarios

- Given a user mentions "I paid for Vercel Pro" mid-engineering-conversation, when the agent processes the message, then it spawns COO as a background agent and continues the primary task
- Given a user says "yes" or "continue", when the agent processes the message, then no domain routing fires
- Given a user describes a feature that triggers Marketing and Legal, when brainstorm Phase 0.5 runs, then both leaders auto-fire without AskUserQuestion
- Given a user says "let's define our brand voice" mid-conversation, when passive routing detects Marketing, then it spawns CMO assessment (not brand workshop)
- Given a user explicitly says "start brand workshop" during brainstorm, when Phase 0.5 processes the request, then the Brand Workshop path is followed

## Dependencies & Risks

- **Risk:** False positive rate unknown until real-world testing. Mitigated by qualifying language in the rule.
- **Risk:** Workshop entry points less discoverable. Mitigated by keeping workshop sections with clear invocation instructions.
- **Dependency:** Agent tool `run_in_background` parameter must work as documented.

## Implementation Sequence

### Task 1: Add Passive Domain Routing section to AGENTS.md
**Files:** `AGENTS.md`
- Add `## Passive Domain Routing` section between Workflow Gates and Communication
- 2 bullets: (1) behavioral rule with qualifying language ("clear, actionable domain signal unrelated to the current task"), (2) spawn as background agent via `run_in_background: true`, reference `plugins/soleur/skills/brainstorm/references/brainstorm-domain-config.md` for domain→leader mapping
- Modify line 22: add "Exception: passive domain routing" to the zero-agents rule

### Task 2: Rewrite brainstorm Phase 0.5 and update domain config
**Files:** `plugins/soleur/skills/brainstorm/SKILL.md` (lines 70-77), `plugins/soleur/skills/brainstorm/references/brainstorm-domain-config.md`
- Replace AskUserQuestion with direct Task spawn for each relevant domain using Task Prompt from config table
- Spawn relevant domains in parallel (respect 5-agent constitution limit)
- Add explicit workshop conditional: "If the user explicitly requests a brand workshop or validation workshop, follow the named workshop section below. Otherwise, use the assessment Task Prompt for all domains."
- Simplify step 6 to "If no domains are relevant, continue to Phase 1"
- Update domain config file header: remove AskUserQuestion instruction, describe auto-fire pattern, note Routing Prompt/Options columns are for workshop reference

### Task 3: Update plugin AGENTS.md
**File:** `plugins/soleur/AGENTS.md`
- Update Domain Leaders table: change "Auto-consulted via brainstorm domain detection" to "Auto-consulted via passive domain routing and brainstorm domain detection"
- Update "Adding a New Domain Leader" checklist step 3: note that new domains are automatically routable via both passive routing and brainstorm Phase 0.5

## References & Research

- Brainstorm: `knowledge-base/brainstorms/2026-03-12-passive-domain-routing-brainstorm.md`
- Spec: `knowledge-base/specs/feat-passive-domain-routing/spec.md`
- Issue: #544
- Domain config: `plugins/soleur/skills/brainstorm/references/brainstorm-domain-config.md`
- Brainstorm SKILL.md Phase 0.5: `plugins/soleur/skills/brainstorm/SKILL.md:60-85`
- AGENTS.md: `AGENTS.md:20-29` (Workflow Gates section)
- Plugin AGENTS.md: `plugins/soleur/AGENTS.md:159-186` (Domain Leader Interface)
