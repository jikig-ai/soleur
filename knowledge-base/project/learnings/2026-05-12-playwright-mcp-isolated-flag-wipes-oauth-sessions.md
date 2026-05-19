# Playwright MCP `--isolated` flag wipes OAuth sessions on every browser respawn

**Date:** 2026-05-12
**Trigger:** PR #3648 ship session — Sentry token creation flow

## Problem

Drove the Playwright MCP browser to `https://sentry.io/auth/login/jikigai/` to create an event-read Sentry auth token. Asked the user to complete Google SSO in the Playwright window. User confirmed login. On the very next tool call (`browser_navigate` to `/settings/jikigai/auth-tokens/`), Playwright landed back on the login page — session evaporated.

Repeated 3× across the same session. Every time the Playwright browser respawned (after idle-timeout death OR explicit `browser_close`), the fresh process had zero cookies. The user's authenticated SSO state never persisted.

## Root cause

Project `.mcp.json` launched `@playwright/mcp` with the `--isolated` flag:

```json
{
  "mcpServers": {
    "playwright": {
      "command": "npx",
      "args": ["@playwright/mcp@latest", "--isolated"]
    }
  }
}
```

Per the `@playwright/mcp` docs (verified via WebFetch 2026-05-12):

> `--isolated`: keep the browser profile in memory, do not save it to disk.

In-memory profile means cookies live only as long as the Chromium process. The MCP server kills the browser process on idle timeout (~60s observed in this session), then spawns a fresh one on the next tool call. The fresh process has no cookie jar — every OAuth/SSO login dies on the first respawn.

Compounded by: `@playwright/mcp` has **no idle-timeout flag** to disable (verified — docs only expose `--timeout-action` and `--timeout-navigation`). So you cannot just keep the browser alive; you have to make state survive death.

## Fix

Remove `--isolated`, add `--user-data-dir` pointing to a persistent host path:

```json
{
  "mcpServers": {
    "playwright": {
      "command": "npx",
      "args": [
        "@playwright/mcp@latest",
        "--user-data-dir=/home/jean/.cache/playwright-mcp-profile"
      ]
    }
  }
}
```

Cookies, localStorage, IndexedDB now persist to disk. Login once → state survives subsequent browser respawns. The next Sentry/Google/GitHub OAuth that this Soleur user does, the session sticks.

Takes effect on next Claude Code start (MCP servers read config at startup; running processes don't reload).

## Trade-off

A persistent profile dir accumulates state across sessions. Risks:
- A previously-visited malicious site's cookies persist
- Login state for one Sentry/Google account "sticks" — switching accounts requires explicit clear

Mitigation: nuke periodically (`rm -rf /home/jean/.cache/playwright-mcp-profile`) or override per-task with an ephemeral `--isolated` profile when working with untrusted surfaces. The MCP `tabs new` flow does not currently accept a per-request `--isolated` override; rotating the profile dir is the available knob.

## Why this matters cross-Soleur-user

`.mcp.json` is committed to the repo. Every Soleur user clones the same MCP config. If we keep `--isolated` to be safe-by-default, every user repeats this exact pain on their first multi-step Playwright OAuth flow. If we switch to persistent profile, every user benefits from session survival but inherits the trade-off above.

The repo decision in this PR: **persistent profile by default**. The Soleur agent-workflow value of "drive OAuth flows for the user once and never make them re-auth in the Playwright window" outweighs the marginal residue risk. Per-user override via `~/.claude/.mcp.json` (if it exists in user's harness) is the escape hatch for users who want `--isolated` ephemeral behavior.

## Session Errors

- **Playwright `browser_close` + immediate `browser_navigate` retry produced "Target page closed" error.** Recovery: a brief `sleep 3` allowed the MCP server to recycle its browser process; next `browser_navigate` succeeded. Prevention: when a Playwright tool returns "Target page closed", wait 3-5s before retrying the next tool call — the MCP server is mid-respawn.

- **Mistook the user's "logged in" for Playwright-window login.** The user logged in to Sentry in their own Chrome (where they're authenticated via SSO), not in the Playwright MCP browser. Playwright's isolated context shares no cookies with the user's main browser. Recovery: surfaced the constraint, re-drove Playwright, asked user to log in **in the Playwright window specifically**. Prevention: when handing off OAuth to user, explicitly clarify "in the Playwright window" vs "in your own browser" — and recognize that without a persistent profile the Playwright window auth is a single-tool-call window.

- **Surfaced manual `doppler secrets set` instructions instead of using Playwright handoff pattern.** Per the Playwright-first rule (AGENTS.md `hr-never-label-any-step-as-manual-without`), browser tasks → Playwright MCP first. I jumped to "you do it in your own browser" before exhausting the Playwright handoff. User caught this and redirected ("you were supposed to handoff the login to me"). Prevention: before surfacing manual browser instructions, attempt the Playwright drive-up-to-OAuth-gate pattern; only fall back to fully-manual after the Playwright path is verifiably blocked.

## Cross-references

- Plan trigger: PR #3648 (PR-A2 #3603) ship-time Sentry breadcrumb verification
- Related rule: `hr-never-label-any-step-as-manual-without` — Playwright-first for browser tasks
- Related rule: `hr-mcp-tools-playwright-etc-resolve-paths` — MCP tools resolve from repo root, not shell CWD
- Playwright MCP repo: https://github.com/microsoft/playwright-mcp

## Tags

```yaml
category: integration-issues
module: mcp-config
class: stateless-mcp-server-vs-multi-turn-oauth-flow
load-bearing: yes (blocked the Sentry token creation flow)
fix-target: project-level .mcp.json
```
