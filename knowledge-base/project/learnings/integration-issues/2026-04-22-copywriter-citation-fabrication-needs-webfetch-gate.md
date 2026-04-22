---
title: "Copywriter agent fabricates URLs and report stats without WebFetch verification"
date: 2026-04-22
module: copywriter
problem_type: integration_issue
component: agent
symptoms:
  - "Cited URL resolves to the wrong article (e.g., Entrepreneur 492010 → Gen Z recruiting instead of Amodei)"
  - "Cited URL returns 404 (e.g., pymnts.com/.../2025/anthropic-ceo-predicts-one-person-...)"
  - "Cited report URL points to wrong domain (e.g., anthropic.com/news/... instead of resources.anthropic.com/...)"
  - "Cited stat is not present in the cited source (fabricated from adjacent framing)"
root_cause: missing_verification_step
severity: high
tags: [copywriter, citations, fact-checker, docs-trust, hallucination]
synced_to: [copywriter]
---

# Copywriter agent fabricates URLs and report stats without a WebFetch verification gate

## Problem

On PR #2811 (P1.7 "Billion-Dollar Solo Founder Stack" pillar), the `copywriter` agent produced a 3,964-word draft with 11 external citations. The `fact-checker` agent, run after drafting, found:

- **5 broken URLs** — three 404s, one wrong-article (URL resolves but points at a Gen Z recruiting piece, not the Amodei prediction), and one domain-misplaced (Anthropic's 2026 Agentic Coding Trends Report lives at `resources.anthropic.com`, not `www.anthropic.com/news/...`).
- **1 fabricated stat** — the draft claimed the Anthropic report documents "the measurable failure point for multi-step software tasks moved from step 3 in 2023 to step 50+ in 2026." The report discusses ~60% AI usage and multi-agent coordination; the specific step-count claim is not in the report text.

A reader clicking those citations would have hit dead ends on five load-bearing stats. On a high-intent pillar page targeting head keywords, that's a first-touch-trust failure (the `#1810/#2550` / `cq-docs-cli-verification` class, applied to citations instead of CLI tokens).

## Root cause

The copywriter agent's system prompt emphasizes brand voice, outline adherence, and word count; it does NOT have a "verify every URL before embedding" gate. When the plan's citation list said "cite the Anthropic 2026 Agentic Coding Trends Report," the agent generated a plausible URL (`www.anthropic.com/news/2026-agentic-coding-trends-report`) from pattern-matching against how Anthropic usually URLs newsroom posts, without actually fetching it to confirm. Same for the other four broken URLs.

Stats get fabricated the same way: the agent pattern-matches "Anthropic report about coding trajectory" → plausible-sounding numbers consistent with the narrative, without returning to the source to confirm the specific figures are in the report.

## Solution

Applied fixes inline (see PR #2811, commit 696a1e9f):

- Entrepreneur 492010 → Benzinga coverage of the same quote + officechai (the companion post's existing Amodei citation)
- PYMNTS 2025 404 → dropped (Inc.com primary already carries the 70-80% figure)
- Anthropic domain → `resources.anthropic.com/2026-agentic-coding-trends-report`
- CIO 3816270 → 4134741 (verified-live article on the same framing)
- Deloitte → dropped (CIO alone is sufficient for the orchestration-layer point)
- Fabricated "step 3 → step 50+" stat → rewrote to the 60%-AI-usage / multi-agent-coordination framing the report actually supports

## Prevention

**Workflow change (preferred):** `copywriter` agent prompt must include a pre-write verification gate:

> Before embedding any URL as an inline citation, call `WebFetch` on that URL. If it returns 200 and the content supports the specific stat you are attaching to it, embed. If it returns 4xx/5xx, try one archived URL via `web.archive.org/web/*`. If that also fails, **drop the stat** — do NOT ship a placeholder URL or a citation to a related-but-different article.
>
> Before citing a specific number, quote, or finding from a named report, the quote or number must appear in the actual fetched source text. If you can only paraphrase the source's framing, cite the framing — do not invent specific numbers.

**Pipeline change (belt-and-suspenders):** the `fact-checker` agent already runs in `/soleur:plan` Phase 5 for any PR that introduces user-facing citations. Keep it as a shipping gate — do not downgrade it to advisory.

**Plan-skill change:** plans that delegate drafting to `copywriter` should list fact-checker in the Delegation Summary as mandatory, not optional. PR #2811's plan did this correctly; the copywriter still fabricated.

**Agent-level rule** (proposed, AGENTS.md class): "Agent-generated citations in user-facing docs are unverified until fact-checker confirms." Same shape as `cq-docs-cli-verification`, applied to `citations` instead of `CLI tokens`.

## Cross-references

- `cq-docs-cli-verification` — sibling rule for fabricated CLI tokens in user-facing docs (same class, different surface)
- PR #2811 — the pillar, incident, and inline fix
- `plugins/soleur/agents/marketing/copywriter.md` — routing target for the skill instruction

## Tags

category: integration-issues
module: copywriter
