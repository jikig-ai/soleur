# Check MCP Tools and APIs Before Using Playwright

**Date:** 2026-03-25
**Context:** Scheduled tasks migration (#1094)
**Category:** engineering/automation

## Problem

When creating Cloud scheduled tasks, the agent defaulted to Playwright browser automation (navigating claude.ai/code web UI) to create tasks. This required user login, was slow (~3 minutes per task), fragile (element refs change between snapshots), and consumed significant context window.

## Root Cause

The agent followed the AGENTS.md Playwright-first mandate ("never label a browser task as manual") but skipped the higher-priority check: whether an MCP tool or API exists for the same operation.

The `RemoteTrigger` tool was available the entire time and supports `create`, `list`, `get`, `update`, and `run` actions — a direct API for Cloud scheduled task management. One `RemoteTrigger` create call replaces 10+ Playwright interactions (navigate, fill form, click buttons, wait for snapshots).

## Fix

Before any external service interaction, follow this priority order:

1. **MCP tools** — Run `ToolSearch` with relevant keywords (e.g., "schedule trigger remote")
2. **CLI tools** — Check if a CLI exists (`which doppler`, `gh`, `hcloud`, etc.)
3. **REST APIs** — Check if `curl`/`WebFetch` can hit an API endpoint
4. **Playwright** — Last resort for browser-only interactions (OAuth, CAPTCHAs, no API)

The check takes 5 seconds (one `ToolSearch` call) and can save 10+ minutes of Playwright interaction per task.

## Broader Lesson

AGENTS.md says "exhaust all automated options." MCP tools and APIs ARE automated options — Playwright is the fallback, not the first choice. The priority chain is: MCP > CLI > API > Playwright > Manual handoff.

This applies to ANY external service interaction, not just Cloud tasks. Before opening a browser, always ask: "Is there an MCP tool or API for this?"
