---
title: "fix: default to Playwright MCP for all browser interactions"
type: fix
date: 2026-03-10
semver: patch
---

# fix: default to Playwright MCP for all browser interactions

## Overview

Agents that need browser interaction currently treat Playwright MCP as one option among three (Playwright MCP, agent-browser CLI, manual instructions), with the "provide manual instructions" fallback positioned as the natural second option. Issue #474 proved Playwright MCP handles provisioning well. Since Playwright MCP is available as an MCP server in the plugin environment, it should be the assumed default -- not a conditional branch behind an availability check.

## Problem Statement

Three agents reference browser-based workflows with varying levels of Playwright MCP awareness:

1. **ops-provisioner** (`plugins/soleur/agents/operations/ops-provisioner.md`) -- Has a three-tier fallback (Playwright MCP > agent-browser CLI > manual instructions) but gates Playwright MCP behind an `agent-browser --help` availability check that has nothing to do with MCP tool availability. The "neither is available" fallback to manual instructions is positioned as a normal path.

2. **ops-research** (`plugins/soleur/agents/operations/ops-research.md`) -- Checks `agent-browser --help` availability and falls back to "provide direct URLs and tell the user to navigate manually." No mention of Playwright MCP at all.

3. **community-manager** (`plugins/soleur/agents/support/community-manager.md`) -- Directs users to setup scripts but does not use browser automation for any verification steps.

4. **constitution.md** (`knowledge-base/overview/constitution.md`) -- Line 89 references `agent-browser` as a verification tool for infrastructure agents alongside `gh`, `openssl`, and `curl`. Should mention Playwright MCP as the preferred browser tool.

Additionally, there is no documented convention establishing Playwright MCP as the default for browser interaction. The rule belongs in constitution.md's Architecture > Prefer section (not AGENTS.md Hard Rules, which loads on every turn for every agent -- unnecessary bloat for a rule that applies to only 2 agents).

## Proposed Solution

### Change 1: constitution.md Prefer rule (not AGENTS.md Hard Rule)

[Updated 2026-03-10 per plan review: moved from AGENTS.md Hard Rules to constitution.md Architecture > Prefer to avoid system prompt bloat -- only 2 agents need browser interaction, but Hard Rules load on every turn for every agent.]

Add a Prefer rule to constitution.md Architecture section establishing the browser interaction hierarchy:

> When browser interaction is needed, default to Playwright MCP tools (browser_navigate, browser_snapshot, browser_click, browser_fill_form, browser_file_upload) -- fall back to agent-browser CLI only if MCP tools are unavailable; manual instructions are a last resort, not a default

File: `knowledge-base/overview/constitution.md` (Architecture > Prefer section)

### Change 2: ops-provisioner update

Restructure the Setup section:

- Remove the `agent-browser --help` availability check (irrelevant to MCP tool availability)
- Make Playwright MCP the default path (no conditional check needed -- MCP tools are always available when the plugin is active)
- Move agent-browser CLI to an explicit "Fallback" section
- Change "If neither is available" manual instructions to "Last resort" with language that makes it clear this path should rarely trigger

File: `plugins/soleur/agents/operations/ops-provisioner.md`

### Change 3: ops-research update

- Remove the `agent-browser --help` check
- Add Playwright MCP as the default browser navigation method
- Keep agent-browser CLI as fallback
- Change "tell the user to navigate manually" to last-resort language

File: `plugins/soleur/agents/operations/ops-research.md`

### Change 4: constitution.md update

- Update line 89 to list Playwright MCP tools alongside `gh`, `openssl`, `curl` as verification tools
- Add or update the MCP preference to reflect Playwright MCP as the default browser interaction method

File: `knowledge-base/overview/constitution.md`

### Non-changes (community-manager)

The community-manager agent does not perform browser-based verification workflows. It directs users to run setup scripts (shell commands, not browser flows). No change needed -- the setup scripts are the correct path for credential configuration.

## Technical Considerations

- **Playwright MCP availability**: Playwright MCP is configured as a user-level MCP server (visible in the deferred tools list), not bundled in `plugin.json`. Constitution.md line 182 notes: "Agents that depend on external MCP servers (stdio binaries from IDE extensions) must include a graceful degradation check." This means agents should still have a fallback path, but the hierarchy should be Playwright MCP (try first) > agent-browser CLI (fallback) > manual instructions (last resort).
- **Path resolution**: AGENTS.md already has a hard rule about MCP path resolution from repo root. The learning `2026-02-17-playwright-screenshots-land-in-main-repo.md` documents this gotcha. The ops-provisioner already has a sharp edge about this. No additional path rules needed.
- **Sensitive field handling**: The ops-provisioner safety rules already cover never entering credentials, payments, or MFA. These rules stay unchanged.
- **No code changes**: All changes are to agent instruction markdown files. No scripts, no CI, no tests affected.

## Acceptance Criteria

- [ ] constitution.md Architecture > Prefer section contains a rule establishing Playwright MCP as the default for browser interactions
- [ ] ops-provisioner Setup section defaults to Playwright MCP without an `agent-browser --help` check
- [ ] ops-provisioner Setup section positions manual instructions as "last resort," not a normal fallback
- [ ] ops-provisioner Configure section (line 55) defaults to Playwright MCP instead of agent-browser
- [ ] ops-research uses Playwright MCP as the default browser navigation method
- [ ] ops-research positions manual instructions as "last resort"
- [ ] constitution.md line 89 mentions Playwright MCP tools as preferred, with agent-browser as fallback
- [ ] All agents retain graceful degradation (agent-browser fallback, then manual as last resort)
- [ ] Existing safety rules (no credentials, no payments, pause for sensitive fields) are preserved unchanged
- [ ] No changes to community-manager (it does not perform browser-based workflows)

## Test Scenarios

- Given ops-provisioner is invoked with a signup URL, when Playwright MCP tools are available, then it navigates using `browser_navigate` without checking `agent-browser --help`
- Given ops-research is invoked to check a provider's website, when Playwright MCP tools are available, then it uses `browser_navigate` and `browser_snapshot` to inspect the page
- Given Playwright MCP tools are unavailable (e.g., MCP server not configured), when an agent needs browser interaction, then it falls back to agent-browser CLI
- Given both Playwright MCP and agent-browser are unavailable, when an agent needs browser interaction, then it provides manual instructions as a last resort with clear language that this is not the normal path
- Given the constitution.md Architecture > Prefer section, when read during planning or review, then the Playwright MCP default rule is present and unambiguous

## Non-goals

- Bundling Playwright MCP in `plugin.json` (it's a stdio binary, not an HTTP MCP server -- constitution.md line 182)
- Adding Playwright MCP to agents that don't need browser interaction
- Modifying the community-manager agent (no browser automation use case)
- Changing the safety rules around credentials, payments, or MFA

## MVP

### constitution.md (new Prefer rule in Architecture section)

```markdown
- When browser interaction is needed, default to Playwright MCP tools (browser_navigate, browser_snapshot, browser_click, browser_fill_form, browser_file_upload) -- fall back to agent-browser CLI only if MCP tools are unavailable; manual instructions are a last resort, not a default
```

### constitution.md (updated line 89)

```markdown
- Infrastructure agents that wire external services (DNS, SSL, Pages) must own the full verification loop -- use Playwright MCP tools (browser_navigate, browser_snapshot, browser_click), `gh` CLI, `openssl`, and `curl` to verify each step programmatically instead of asking the user to check manually; fall back to agent-browser CLI if MCP tools are unavailable; only stop for genuine decisions, not mechanical verification
```

### ops-provisioner.md (restructured Setup section)

```markdown
## Setup

...existing branch check and tool lookup...

Use Playwright MCP tools to automate the signup flow:

1. Navigate to the signup page: `browser_navigate` to <signup_url>
2. Snapshot the page: `browser_snapshot` to identify form fields
3. Fill non-sensitive fields using `browser_click` and `browser_fill_form`
4. For file uploads (logos, avatars): use `browser_file_upload` with absolute paths (MCP resolves from repo root, not CWD)
5. When reaching payment or credential fields, stop and move to the pause step

**Fallback (agent-browser CLI):** If Playwright MCP tools are unavailable, use agent-browser CLI commands (`agent-browser open`, `agent-browser snapshot`, `agent-browser fill`, `agent-browser click`).

**Last resort:** If no browser automation is available, provide the signup URL and step-by-step instructions. This path should rarely trigger -- investigate why browser tools are unavailable.
```

### ops-provisioner.md (updated Configure section)

```markdown
## Configure

After the user confirms payment is complete:

1. Navigate to the tool's dashboard or settings page using Playwright MCP (`browser_navigate`). Fall back to agent-browser if MCP tools are unavailable.
2. Take a snapshot (`browser_snapshot`) to understand the current state
3. Guide through initial configuration steps (add site/project, copy integration snippet, configure options)
4. If the tool requires code changes in the project (script tags, env vars, config files), make those changes using the Edit or Write tools
```

### ops-research.md (restructured Browser Navigation section)

```markdown
## Browser Navigation

Use Playwright MCP tools to navigate to the chosen provider's website:

1. Navigate: `browser_navigate` to the provider URL
2. Snapshot: `browser_snapshot` to inspect live pricing or availability

**Fallback:** If Playwright MCP tools are unavailable, check if agent-browser is available (`agent-browser --help`). If available, use it. If neither is available, provide direct URLs as a last resort.
```

## References

- #474 -- X provisioning proved the Playwright MCP pattern
- #484 -- X banner upload needs Playwright MCP
- `plugins/soleur/agents/operations/ops-provisioner.md` -- Primary target
- `plugins/soleur/agents/operations/ops-research.md` -- Secondary target
- `knowledge-base/overview/constitution.md:89` -- Infrastructure verification tools
- `knowledge-base/learnings/2026-03-09-x-provisioning-playwright-automation.md` -- Learnings from the X provisioning
- `knowledge-base/learnings/2026-02-17-playwright-screenshots-land-in-main-repo.md` -- MCP path resolution gotcha
- `knowledge-base/overview/constitution.md` -- Architecture > Prefer section for new browser hierarchy rule
