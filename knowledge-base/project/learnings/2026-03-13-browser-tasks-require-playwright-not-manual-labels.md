---
topic: Browser tasks require Playwright MCP, not "manual" labels
category: workflow
severity: high
related_issues: ["#139"]
---

# Browser Tasks Require Playwright MCP, Not "Manual" Labels

## Problem

Plans and task lists repeatedly labeled browser-based tasks (account creation, credential generation, settings configuration) as "manual — browser" without first attempting Playwright MCP automation. This pattern surfaced in multiple sessions and wasted the founder's time on tasks the agent could have automated.

## Root Cause

The planning phase had no check for browser task automation. Once a task was labeled "manual" in the plan, the execution phase trusted that label and asked the user to do it by hand — even when Playwright MCP was available and capable of completing the task.

## What Actually Works

Playwright MCP can automate ~95% of browser tasks:

- Account signups (navigate, fill forms, click buttons)
- App password generation (navigate settings, create, copy)
- Settings configuration (toggle switches, fill fields)
- Form submissions of all kinds

The only genuinely manual steps are:

- **CAPTCHA solving** (image-based challenges like hCaptcha)
- **Interactive OAuth consent screens** (Google, GitHub OAuth dialogs)

Even these should be automated up to the CAPTCHA/consent gate, then handed to the user for just that single interaction.

## Prevention

Three layers now prevent this anti-pattern:

1. **AGENTS.md hard rule** — Agents must attempt Playwright MCP before labeling any browser task as manual
2. **Plan skill pre-submission check** — Step 6 checklist scans for "manual"/"browser" labels and rewrites them as Playwright automation steps
3. **This learning** — `learnings-researcher` surfaces this document during future brainstorms and plans involving browser tasks, catching the pattern before it enters the plan

## Key Insight

The cost asymmetry is extreme: 30 seconds of Playwright setup vs. minutes of user context-switching. For a solo operator, every "manual" label is a broken promise of automation.
