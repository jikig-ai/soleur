# Onboarding Audit Report

**Date:** 2026-03-03
**Branch:** feat-product-strategy
**Fixes tracked in:** #432

---

## Summary

| Checklist Item | Status | Severity |
|---|---|---|
| Getting Started nav position | PASS | -- |
| Fresh install flow | PASS with caveats | Medium |
| `/soleur:sync` on empty project | PASS | -- |
| Legal document generation | PASS | Low |
| Brand guide creation | PASS | Low |
| Competitive intelligence | PASS with caveats | Medium |
| First 5 minutes flow | FAIL | High |
| Docs Getting Started page | PASS with issues | Medium |

## Top 3 Blockers

1. **No post-install onboarding** -- User gets zero guidance after `claude plugin install soleur`. No welcome message, no "try this first" prompt. Needs at minimum a suggestion to run `/soleur:help` or `/soleur:sync`.

2. **`/soleur:go` routing gap for non-engineering tasks** -- The 3-intent model (explore/build/review) funnels all non-engineering tasks through brainstorm's domain detection, adding 2-3 unnecessary steps. A user typing "generate our privacy policy" goes through brainstorm rather than directly to `/soleur:legal-generate`. Needs a "generate/create" intent or direct domain skill routing.

3. **Getting Started page positions engineering first** -- `/soleur:sync` is not called out as the recommended first action for existing projects. Non-engineering workflows are in a separate "Beyond Engineering" section rather than integrated into the main flow.

---

## Detailed Findings

### 1. Getting Started Nav Position

**Status: PASS**

"Get Started" is the first navigation item in `plugins/soleur/docs/_data/site.json`. The homepage also has three prominent CTAs linking to Getting Started. No changes needed.

### 2. Fresh Install Flow

**Status: PASS with caveats**

`plugin.json` registers the plugin with 3 MCP servers and all skills/agents. No install hooks exist (only a Stop hook for ralph-loop). After `claude plugin install soleur`, the user gets zero feedback -- no welcome message, no suggested first action. They must already know to type `/soleur:go` or `/soleur:help`.

**What would fix it:**
- Add a PostInstall hook (if supported by Claude Code plugin spec) that prints a welcome message
- Alternatively, document the expected first action more prominently

**Files:** `plugins/soleur/hooks/hooks.json`

### 3. `/soleur:sync` on Empty Project

**Status: PASS**

Phase 0 explicitly handles missing `knowledge-base/`:

```bash
if [[ ! -d "knowledge-base" ]]; then
  mkdir -p knowledge-base/{learnings,brainstorms,specs,plans,overview/components}
fi
```

Creates the full directory tree. Warns but continues if `.git` is missing. Well-designed.

### 4. Non-Engineering Domain Tasks

#### Legal Document Generation

**Status: PASS**

Reachable via `/soleur:legal-generate` (direct) or `/soleur:go generate legal documents` (routed through brainstorm domain detection). End-to-end flow works: gathers company context interactively, invokes agent, presents draft for review, writes to `docs/legal/`.

**Friction:** `/soleur:go` routing is ambiguous -- "generate legal documents" could classify as "build" (wrong, goes to one-shot engineering workflow) or "explore" (correct, goes to brainstorm which detects legal domain).

#### Brand Guide Creation

**Status: PASS**

Reachable via brainstorm domain detection (Marketing domain). No dedicated skill -- must go through `/soleur:go define our brand identity` -> brainstorm -> Phase 0.5 -> "Start brand workshop" -> `brand-architect` agent. Adds 2-3 interaction steps.

**Friction:** No direct skill shortcut. Same routing ambiguity as legal.

#### Competitive Intelligence

**Status: PASS with caveats**

Reachable via `/soleur:competitive-analysis` (direct skill). Not reachable from `/soleur:go` -- no "research" or "analyze" intent in the routing table.

**Friction:** Requires prior artifacts (`brand-guide.md`, `business-validation.md`) for full context. First-time user gets a base report but cascade outputs may be thin. Not discoverable through `/soleur:go`.

### 5. First 5 Minutes Flow

**Status: FAIL**

**What happens today:**
1. Install completes silently. No guidance.
2. User tries random commands or eventually finds `/soleur:help`.
3. If they start with `/soleur:go`, engineering tasks route well but non-engineering tasks hit routing friction.
4. `/soleur:sync` is the natural first step but nothing suggests it.

**What should happen:**
1. Install -> welcome message suggesting `/soleur:sync` as first step
2. Sync analyzes project, creates knowledge-base
3. User picks a task (engineering or non-engineering)
4. First task completes and shows value in under 5 minutes

**Critical gaps:**
- Silent install with no guidance (highest priority)
- No suggested first action
- No "quick win" -- shortest non-engineering paths (legal, brand) take 5-10 minutes of interactive dialogue
- `/soleur:go` routing gap for non-engineering tasks

### 6. Docs Getting Started Page

**Status: PASS with issues**

Structure: Why Soleur -> Installation -> The Workflow -> Commands -> Common Workflows -> Beyond Engineering -> Learn More.

**Passes:**
- First action (install) is clear and prominently displayed
- Non-engineering domains are mentioned in a "Beyond Engineering" section with 4 examples

**Issues:**
- `/soleur:sync` not positioned as the recommended first action for existing projects
- The 5-step workflow section is engineering-centric (brainstorm -> plan -> work -> review -> compound uses engineering language throughout)
- "Common Workflows" only shows engineering examples (Build Feature, Fix Bug, Review PR)
- Non-engineering workflows are in a separate section, creating a two-tier impression
- No "Try this first" callout for a single immediate-value command

**Files:** `plugins/soleur/docs/pages/getting-started.md`

---

## Recommended Fixes

### P0: Post-install guidance
- Investigate whether Claude Code plugin spec supports PostInstall hooks
- If yes, add a hook that prints: "Soleur installed. Run /soleur:sync to analyze your project, or /soleur:help to see all commands."
- If no, add a prominent "After Installing" section to the Getting Started page

### P1: Getting Started page restructure
- Position `/soleur:sync` as Step 1 after install
- Merge "Common Workflows" and "Beyond Engineering" into a single "What You Can Do" section with mixed engineering/non-engineering examples
- Add a "Try this first" callout with one 30-second command

### P2: `/soleur:go` routing for non-engineering tasks
- Add a "generate" or "create" intent that routes directly to domain-specific skills (legal-generate, brand workshop, etc.)
- Or add domain detection to the go command itself, bypassing brainstorm for direct-action requests
