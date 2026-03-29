---
title: "fix: auto-check Doppler for API keys before prompting users"
type: fix
date: 2026-03-29
---

# fix: auto-check Doppler for API keys before prompting users

## Enhancement Summary

**Deepened on:** 2026-03-29
**Sections enhanced:** 1 (Proposed Change)
**Research method:** Doppler CLI behavior verification, learnings scan

### Key Findings

1. `doppler secrets get <MISSING_KEY> --plain` exits with code 1 and writes error to stderr -- `2>/dev/null` in the proposed rule correctly handles this
2. `doppler secrets --only-names` outputs a clean table with header row -- usable for key discovery
3. No relevant learnings in `knowledge-base/project/learnings/` apply to this change
4. The `dev` config has 14 application secrets; `prd` has 23 -- checking `dev` first is the right default for local agent sessions

## Problem

When a tool or service requires an API key (e.g., Pencil CLI `PENCIL_CLI_KEY`), the agent should automatically check Doppler before asking the user to manually log in or provide credentials. During the feat-repo-connection session, the agent attempted `pencil login` (interactive) and suggested the user run it manually, when the key was already stored in Doppler (`soleur/dev` config). This wasted a round-trip and violated the "exhaust all automated options" rule.

The existing "exhaust all automated options" priority chain in AGENTS.md (Hard Rules section) covers the general principle but does not explicitly address credential lookup. The agent needs a concrete, unambiguous rule: before prompting for any credential, check Doppler first.

## Context

- Session: feat-repo-connection (2026-03-29)
- Specific case: `PENCIL_CLI_KEY` in `soleur/dev` Doppler config
- GitHub issue: #1269
- The pencil-setup skill already uses `doppler secrets get PENCIL_CLI_KEY -p soleur -c dev --plain` -- the pattern exists, but the agent didn't follow it because no hard rule mandated Doppler-first lookup

## Existing Doppler Configs

| Config | Purpose |
|--------|---------|
| `dev` | Local development secrets (PENCIL_CLI_KEY, DISCORD_BOT_TOKEN, etc.) |
| `dev_personal` | Personal dev overrides |
| `ci` | CI/CD pipeline secrets |
| `prd` | Production runtime secrets |
| `prd_scheduled` | Production scheduled task secrets |
| `prd_terraform` | Terraform-specific production secrets (AWS, CF tokens) |

## Proposed Change

Add a new rule to the **Hard Rules** section of `AGENTS.md`, positioned immediately before or as a sub-rule of the existing "exhaust all automated options" bullet. The rule:

> Before prompting the user for any API key, access token, or service credential, check Doppler first: `doppler secrets get <KEY_NAME> --project soleur --config dev --plain`. If the key name is uncertain, check all relevant configs (`dev`, `prd`, `ci`). Only prompt the user if the key is not found in any Doppler config.

### Placement in AGENTS.md

Insert as a new bullet in the Hard Rules section, directly before the existing "Exhaust all automated options" rule (currently around line 21). This positions the Doppler check as step 0 in the automation priority chain.

### Rule Text

```markdown
- Before prompting the user for any API key, access token, or service credential, check Doppler first: `doppler secrets get <KEY_NAME> --project soleur --config dev --plain 2>/dev/null`. If the key name is uncertain, list available secrets with `doppler secrets --only-names -p soleur -c dev` and check additional configs (`prd`, `ci`, `prd_terraform`). Only prompt the user if the key is not found in any Doppler config. **Why:** In the feat-repo-connection session (2026-03-29), the agent attempted interactive `pencil login` when `PENCIL_CLI_KEY` was already stored in Doppler `soleur/dev` -- a wasted round-trip that violated the "exhaust all automated options" rule.
```

## Files to Change

| File | Change |
|------|--------|
| `AGENTS.md` | Add Doppler-first credential lookup rule to Hard Rules section |

## Acceptance Criteria

- [x] AGENTS.md updated with Doppler-first credential lookup rule in Hard Rules section
- [x] Rule covers all credential scenarios (CLI tools, MCP servers, API tokens)
- [x] Existing priority chain preserved (Doppler check inserted as step 0 before MCP tools)
- [x] Rule includes the `2>/dev/null` suffix to handle cases where Doppler CLI is not installed
- [x] Rule includes guidance for uncertain key names (list secrets, check multiple configs)
- [x] Rule includes a `**Why:**` annotation with the triggering incident

## Test Scenarios

- Given the agent needs `PENCIL_CLI_KEY` for pencil-setup, when it encounters the credential requirement, then it runs `doppler secrets get PENCIL_CLI_KEY --project soleur --config dev --plain` before attempting interactive login
- Given the agent needs an unknown API key for a new service, when it encounters the credential requirement, then it runs `doppler secrets --only-names -p soleur -c dev` to check if a matching key exists
- Given Doppler CLI is not installed, when the agent tries the Doppler check, then the `2>/dev/null` suppresses the error and the agent falls through to the existing priority chain

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/tooling rule change.

## References

- Related issue: #1269
- Existing pattern: `plugins/soleur/skills/pencil-setup/SKILL.md` line 76
- Existing priority chain: `AGENTS.md` Hard Rules, "exhaust all automated options" bullet
