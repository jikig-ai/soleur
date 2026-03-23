---
name: action-completion-workflow-gap
description: Agent stopped at "next action" text instead of executing the automatable step (opening subscription page)
type: workflow-deviation
category: integration-issues
module: brainstorm, workflow
severity: medium
date: 2026-03-23
---

# Learning: Action Completion Workflow Gap

## Problem

After completing a brainstorm that concluded with a clear actionable next step (subscribe to Plausible Analytics before trial expiry), the agent output "Action item: subscribe to Plausible Starter before the trial expires tomorrow" and stopped. The user had to prompt the agent to actually execute the step.

This violated the existing "exhaust all automated options" hard rule and the Playwright-first rule, but neither rule explicitly covered the pattern of stopping at the *end* of a workflow with a prose action item.

## Solution

1. Opened the Plausible subscription page via `xdg-open` (Playwright failed due to existing Chrome session conflict).
2. Added a new hard rule to AGENTS.md: when a workflow concludes with an actionable next step, execute it — don't list it as "next action" and stop. Use Playwright, `xdg-open`, CLI tools, or APIs.

## Key Insight

The "exhaust all automated options" rule was interpreted as applying to *within* a task, not to the handoff *after* a task completes. The gap was in the transition between "task done" and "what's next" — the agent treated the conclusion as a summary rather than a continuation. Every workflow conclusion that names an action is itself a task to execute.

## Session Errors

1. **Action completion violation** — Agent stopped at "Action item: subscribe to Plausible" instead of opening the page. **Recovery:** User corrected, agent opened via `xdg-open`. **Prevention:** New AGENTS.md hard rule enforces action completion at workflow boundaries.

2. **Playwright MCP launch failure** — `browser_navigate` failed with "Opening in existing browser session" because Chrome was already running. Playwright MCP can't launch persistent context alongside an existing Chrome instance. **Recovery:** Fell back to `xdg-open` which opens in the existing browser. **Prevention:** When Playwright fails due to existing browser session, immediately fall back to `xdg-open` for navigation-only tasks rather than stopping.

3. **WebFetch 404/403 on Cloudflare docs** — Multiple Cloudflare documentation URLs returned errors (404 for `/analytics/web-analytics/limits/`, 403 for community forum). **Recovery:** Tried alternative URL paths and pieced together information from working pages. **Prevention:** One-off; Cloudflare's docs structure changes. No workflow change needed.

## Tags

category: integration-issues
module: brainstorm, workflow
