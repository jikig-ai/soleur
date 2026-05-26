---
title: Brainstorm substrate extension — CTO-vs-research reconciliation patterns
date: 2026-05-25
category: workflow-patterns
tags: [brainstorm, cto, repo-research, reconciliation, inngest, playwright]
---

# Learning: Brainstorm substrate extension — CTO-vs-research reconciliation patterns

## Problem

When brainstorming a substrate-extension migration (TR9 PR-11: cron-ux-audit-inngest with Playwright+MCP), the CTO domain leader returned 3 recommendations that repo-research corrected. The CTO assessed strategically but couldn't verify claims against the specific codebase; the research agent could verify but couldn't assess tradeoffs. Without explicit reconciliation, the CTO-shaped framing would have won by default.

## Solution

After all agents returned, ran a cross-agent reconciliation pass before presenting approaches. Each correction was tabled:

| CTO claim | Research correction | Resolution |
|-----------|-------------------|------------|
| `claude-code@2.1.79` from Dockerfile L45 is the canonical pin | `package.json:25` pins `2.1.142`; Dockerfile is global-install bootstrap | Decision: no version bump needed |
| `.mcp.json` cloned from repo just-works | `--user-data-dir` points at operator home, doesn't exist in container | Decision: handler writes per-fire `.mcp.json` overlay |
| Dual-key concurrency (`cron-platform` + `bot-fixture-shared-state`) | `cron-platform` already enforces limit=1 across ALL cron-* handlers | Decision: single key, defer dual-key until non-cron consumer |

## Key Insight

For substrate-extension brainstorms (where the CTO assesses beyond the established template), repo-research is the mandatory cross-check before any CTO claim about "what's already wired" becomes a decision. The reconciliation table format makes corrections explicit rather than silently overriding leader recommendations.

## Session Errors

1. **CTO version-pin assumption (Dockerfile L45 vs package.json).** The Dockerfile L45 global-install `2.1.79` is visually prominent but is NOT the I4 canonical pin — that's `package.json:25` resolved via `createRequire`. Recovery: repo-research corrected it. Prevention: when spawning CTO for Inngest cron work, include "I4 canonical pin is package.json, not Dockerfile global-install" in the leader prompt's ground-truth section.

2. **CTO `.mcp.json` just-works assumption.** The file IS cloned unaltered (repo-research confirmed), so "just works" is half-correct. The error is that `.mcp.json` contains operator-home paths that don't resolve in the container runtime. Recovery: researched `.mcp.json` overlay pattern from `cron-legal-audit.ts:333-340`. Prevention: for any cron handler that uses MCP tools, verify `--user-data-dir` and other path arguments resolve in the container runtime, not just the operator workstation.

3. **Pre-write hook false positive on subprocess-spawn terminology in prose.** The security hook pattern-matches on spawn-family strings regardless of context (planning doc vs code file). Recovery: rewrote to use the ADR-033 I1 terminology (spawn). Prevention: none needed — hook is correctly conservative; rewording prose to match the accurate ADR term is the right outcome.

## Tags

category: workflow-patterns
module: brainstorm, inngest, playwright
