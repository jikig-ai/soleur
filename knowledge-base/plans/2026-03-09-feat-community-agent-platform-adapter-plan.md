---
title: "feat: Add X/Twitter support to community agent"
type: feat
date: 2026-03-09
semver: minor
---

# feat: Add X/Twitter support to community agent

## Overview

Add X/Twitter as a data source to the community-manager agent. Create the missing community SKILL.md entry point. Leave existing Discord and GitHub scripts untouched.

**Issue:** #127
**Brainstorm:** `knowledge-base/brainstorms/2026-03-09-community-agent-x-brainstorm.md`
**Spec:** `knowledge-base/specs/feat-community-agent-x/spec.md`

## Problem Statement

The community-manager agent only supports Discord and GitHub. X/Twitter is the highest-priority missing platform for reaching solo founders (#buildinpublic audience). The community skill (`plugins/soleur/skills/community/`) has scripts but no SKILL.md, making it uninvocable.

## Proposed Solution

### Architecture

```
skills/community/
  SKILL.md                      # NEW: Entry point with digest/health/platforms sub-commands
  scripts/
    discord-community.sh        # EXISTING: No changes
    github-community.sh         # EXISTING: No changes
    x-community.sh              # NEW: X API wrapper
    x-setup.sh                  # NEW: X credential setup + validation
    discord-setup.sh            # EXISTING: No changes
```

No adapter interface. No changes to working scripts. `x-community.sh` follows the same structural conventions as the existing scripts (case dispatch, JSON stdout, validate + request helpers) but with X-specific commands.

### What Is NOT In Scope

- **Adapter pattern refactor** — Deferred until platform #4 arrives and we can see what is actually common across 4+ implementations. With 2 existing scripts, designing a formal interface is premature.
- **`engage` sub-command** — The most complex feature in the original plan. Requires X account, verified API access, and a moderation guide. Filed as a separate follow-up issue after X integration is validated.
- **Rate limit counter file** — The X API returns rate limit errors. The human is in the loop. No need for a local ledger tracking 50 tweets/month. The script reports the X API's rate limit headers and the user decides.
- **Modifying discord-community.sh or github-community.sh** — These scripts work. Do not touch them.

## Critical: X API Free Tier Limitations

**The brainstorm assumed "monitoring (read-only) is unlimited on Free tier." This is likely incorrect.**

X API Free tier (as of early 2025) includes:
- POST /2/tweets (50 tweets/month)
- DELETE /2/tweets/:id
- GET /2/users/me (self-lookup only)

Free tier likely does **not** include:
- GET /2/users/:id/mentions
- GET /2/users/:id/tweets
- Search endpoints

**Phase 1 includes a hard verification gate.** If Free tier lacks read endpoints, `x-community.sh` ships with only:
- `fetch-metrics` — GET /2/users/me (follower/following/tweet counts)
- `post-tweet` — POST /2/tweets (for manual engagement when given a tweet ID)

Commands that require Basic tier ($100/mo) are not built. They get added if/when the user upgrades.

## Technical Considerations

### OAuth 1.0a Signing

Requires `openssl` for HMAC-SHA1. **Spec TR2 must be updated** from "curl + jq" to "curl + jq + openssl" — `openssl` is universally available and not an additional install.

### Platform Detection in SKILL.md

Detection validates **all** required env vars per platform:
- Discord: `DISCORD_BOT_TOKEN` + `DISCORD_GUILD_ID`
- X: `X_API_KEY` + `X_API_SECRET` + `X_ACCESS_TOKEN` + `X_ACCESS_TOKEN_SECRET`
- GitHub: Always enabled via `gh` CLI

Partial config reported: "X partially configured. Missing: X_ACCESS_TOKEN."

### Security

- All secrets via env vars, never CLI args
- Suppress `curl` stderr during auth requests (`2>/dev/null`)
- `.env` written with `chmod 600` before secrets

### Shell Script Conventions

- `#!/usr/bin/env bash` + `set -euo pipefail`
- `${N:-}` for optional positional args in dispatch functions
- `grep ... || true` in pipelines under pipefail
- HTTP status capture: `curl -s -o /dev/null -w "%{http_code}"`
- `local` for all function variables, errors to stderr

## Implementation Phases

### Phase 1: X/Twitter Integration

Create `x-community.sh` and `x-setup.sh`. Requires X Developer Portal credentials (manual founder action).

**Files created:**
- `plugins/soleur/skills/community/scripts/x-community.sh`
- `plugins/soleur/skills/community/scripts/x-setup.sh`

**Files modified:**
- `knowledge-base/specs/feat-community-agent-x/spec.md` — update TR2 to include `openssl`
- `.gitignore` — add any X-related local state files if needed

**Tasks:**
1. **Update spec TR2** to include `openssl` in allowed dependencies
2. **Verify X API Free tier endpoints.** Hard gate — do not build commands for endpoints that are unavailable. Document actual Free tier scope.
3. Create `x-setup.sh` following `discord-setup.sh` pattern:
   - `validate-credentials` — verify all 4 env vars via GET /2/users/me
   - `write-env` — write credentials to `.env` with `chmod 600`
   - `verify` — round-trip API check
4. Create `x-community.sh` with commands that Free tier actually supports:
   - `fetch-metrics` — GET /2/users/me (follower/following/tweet counts)
   - `post-tweet` — POST /2/tweets (with optional `--reply-to TWEET_ID`)
   - Additional commands only if Free tier verification confirms they work
5. Implement OAuth 1.0a signing helper function
6. Implement `x_request` helper with retry depth limit (max 3 retries on 429)

**Acceptance:**
- `x-setup.sh validate-credentials` verifies X API access
- `x-community.sh fetch-metrics` returns follower count
- `x-community.sh post-tweet "test"` posts a tweet (manual test with real credentials)
- `openssl` absence detected and reported clearly

### Phase 2: Community SKILL.md + Agent Update

Create the missing SKILL.md and update the community-manager agent to mention X.

**Files created:**
- `plugins/soleur/skills/community/SKILL.md`

**Files modified:**
- `plugins/soleur/agents/support/community-manager.md` — add X as a data source, update description
- `plugins/soleur/agents/support/cco.md` — update delegation table
- `plugins/soleur/docs/_data/skills.js` — register community skill

**Tasks:**
1. Create SKILL.md with frontmatter (`name: community`, third-person description)
2. Implement sub-commands:
   - `digest` — detect enabled platforms, collect data from each (Discord via `discord-community.sh`, GitHub via `github-community.sh`, X via `x-community.sh`), write unified digest to `knowledge-base/community/YYYY-MM-DD-digest.md`
   - `health` — detect platforms, collect metrics, display inline report
   - `platforms` — list known platforms, check env vars, report enabled/disabled/partial status
3. Add `--headless` bypass for all prompts
4. Add `$ARGUMENTS` passthrough for programmatic callers
5. Register in `skills.js` under appropriate category
6. Update `community-manager.md`:
   - Description: mention X alongside Discord and GitHub (no "Discord" exclusive references)
   - Prerequisites: add X env var requirements alongside Discord
   - Scripts: list `x-community.sh` and `x-setup.sh`
   - Digest: add X metrics section alongside Discord (additive — existing headings preserved)
   - Health: include X metrics in report
   - Content Suggestions: analyze X activity alongside Discord
   - Guidelines: note X channel notes in brand guide for tone
7. Update CCO delegation table to reflect expanded community-manager capabilities
8. Run agent description token budget check: `shopt -s globstar && grep -h 'description:' plugins/soleur/agents/**/*.md | wc -w` (must stay under 2500)
9. Add social-distribute disambiguation to community-manager description ("Use social-distribute for broadcast content; use this agent for monitoring and engagement")

**Digest heading contract (additive):**

```markdown
## Activity Summary        # Existing — unchanged
## Top Contributors        # Existing — unchanged
## GitHub Activity          # Existing — unchanged
## Discord Activity         # NEW — Discord-specific metrics
## X Activity               # NEW — X-specific metrics (omitted if X not configured)
```

Existing headings preserved. New platform-specific sections added at the end. Digests note: "Contributor counts are per-platform and may include duplicates across platforms."

**Acceptance:**
- `/soleur:community digest` produces a multi-platform digest
- `/soleur:community health` displays cross-platform metrics
- `/soleur:community platforms` shows configured platform status
- Skill appears on docs site skills page
- Agent description under 2500 cumulative words
- CCO delegation table updated

### Deferred Work (separate issues to file)

1. **`engage` sub-command** — Interactive X mention engagement with AskUserQuestion approval flow, brand guide tone, rate limit awareness. Requires: X account active, API access verified, moderation guide written.
2. **Platform adapter interface** — Formal shared interface across all platform scripts. Build when platform #4 is being added and we can see real commonality.
3. **X monitoring (fetch-mentions, fetch-timeline)** — Requires Basic tier ($100/mo). Add commands to `x-community.sh` when/if tier is upgraded.
4. **discord-community.sh recursive 429 retry bug** — Pre-existing: `discord_request` calls itself without depth limit.

## Rollback Plan

All changes are additive:
- `x-community.sh` and `x-setup.sh` are new files — delete to roll back
- `SKILL.md` is new — delete to roll back
- `community-manager.md` changes can be reverted with `git revert`
- No existing script behavior is modified

## Acceptance Criteria

### Functional

- [ ] `x-community.sh fetch-metrics` returns X follower/following/tweet counts
- [ ] `x-setup.sh validate-credentials` verifies X API access
- [ ] Existing `discord-community.sh` commands work unchanged (no files modified)
- [ ] Community-manager agent mentions X alongside Discord and GitHub
- [ ] Community SKILL.md is invocable with `digest`, `health`, `platforms` sub-commands
- [ ] Multi-platform digest includes X section when X is configured
- [ ] Platform detection validates all required env vars per platform

### Non-Functional

- [ ] No additional dependencies beyond `curl`, `jq`, `openssl`, `gh`
- [ ] Secrets never in CLI args, `.env` has `chmod 600`
- [ ] Discord functionality not regressed (existing scripts untouched)
- [ ] Skill registered in `skills.js`
- [ ] Agent description cumulative word count under 2500

## Test Scenarios

### X API Integration

- Given X credentials are configured, when `x-community.sh fetch-metrics` is called, then JSON with follower/following/tweet counts is returned
- Given X credentials are configured, when `x-community.sh post-tweet "test"` is called, then tweet is posted and JSON result returned
- Given `openssl` is not available, when any X API command is called, then clear error: "openssl required for OAuth 1.0a signing"
- Given X credentials are invalid, when `x-setup.sh validate-credentials` is called, then exit 1 with auth error message

### Platform Detection

- Given all 4 X env vars are set, when platforms are detected, then X is reported as "enabled"
- Given only `X_API_KEY` is set (3 missing), when platforms are detected, then X is reported as "partially configured. Missing: X_API_SECRET, X_ACCESS_TOKEN, X_ACCESS_TOKEN_SECRET"
- Given no platform env vars are set, when `/soleur:community digest` is invoked, then GitHub-only digest is generated

### SKILL.md

- Given `/soleur:community platforms` is invoked, then all known platforms listed with enabled/disabled/partial status
- Given both Discord and X are configured, when `/soleur:community digest` is invoked, then digest includes both `## Discord Activity` and `## X Activity` sections
- Given `--headless` flag is passed, when `/soleur:community digest` is invoked, then all prompts use defaults
- Given X is not configured, when `/soleur:community digest` is invoked, then digest omits `## X Activity` section (no empty section)

### Backwards Compatibility

- Given `discord-community.sh` is unmodified, when `messages <channel_id>` is called, then output is identical to before this PR
- Given `github-community.sh` is unmodified, when `activity` is called, then output is identical to before this PR

## Dependencies and Prerequisites

| Dependency | Type | Status |
|------------|------|--------|
| X account (@soleur) | Manual, blocking for Phase 1 | Not registered |
| X Developer Portal + API keys | Manual, blocking for Phase 1 | Not provisioned |
| X API Free tier endpoint verification | Hard gate for Phase 1 scope | Unverified |

## Non-Goals

- Adapter pattern refactor (deferred to platform #4)
- `engage` sub-command (separate issue)
- Rate limit counter file (API handles rate limiting)
- Modifying existing Discord or GitHub scripts
- X API Basic or Pro tier features
- Other platform integrations (#134-#140)
- X DM support
- Cross-platform user deduplication
- Brainstorm routing changes (already works)
- `--platform` flag for scoping to single platform (deferred)

## References

### Internal

- Brainstorm: `knowledge-base/brainstorms/2026-03-09-community-agent-x-brainstorm.md`
- Spec: `knowledge-base/specs/feat-community-agent-x/spec.md`
- Community-manager agent: `plugins/soleur/agents/support/community-manager.md`
- Discord adapter: `plugins/soleur/skills/community/scripts/discord-community.sh`
- GitHub adapter: `plugins/soleur/skills/community/scripts/github-community.sh`
- Discord setup: `plugins/soleur/skills/community/scripts/discord-setup.sh`
- Discord-content skill (approval pattern): `plugins/soleur/skills/discord-content/SKILL.md`
- Brand guide X channel notes: `knowledge-base/overview/brand-guide.md:150`
- Skills registry: `plugins/soleur/docs/_data/skills.js`

### Learnings Applied

- `2026-03-03-set-euo-pipefail-upgrade-pitfalls.md` — dispatch function `${N:-}` guards
- `2026-02-18-token-env-var-not-cli-arg.md` — secrets via env vars, never CLI args
- `2026-03-03-community-skill-missing-skill-md.md` — the tech debt this fixes
- `2026-02-13-bash-operator-precedence-ssh-deploy-fallback.md` — `{ cmd || true; }` grouping
- `2026-03-05-autonomous-bugfix-pipeline-gh-cli-pitfalls.md` — curl HTTP status capture

### Related Issues

- #127 — This feature
- #96 — Original community agent (spec archived)
- #134-#140 — Platform extension issues (enabled by future adapter refactor)
