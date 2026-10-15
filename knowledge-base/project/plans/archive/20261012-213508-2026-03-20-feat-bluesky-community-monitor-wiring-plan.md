---
title: "feat(community): wire Bluesky into community monitor CI workflow"
type: feat
date: 2026-03-20
deepened: 2026-03-20
---

## Enhancement Summary

**Deepened on:** 2026-03-20
**Sections enhanced:** 3 (Implementation, Test Scenarios, Context)
**Research sources:** AT Protocol docs, Bluesky rate limit docs, project learnings (CI patterns, CLA ruleset, synthetic status checks)

### Key Improvements

1. Added edge case: `bsky-community.sh` `create-session` call counts against rate limit (5,000 points/hour) -- negligible for daily runs but noted for awareness
2. Added security note: secrets are already confirmed to exist in the repo via the content publisher workflow reference pattern
3. Added consideration: the monitor's PR-based commit pattern (step 5 in prompt) already handles CLA ruleset and synthetic status checks correctly -- no additional work needed for Bluesky addition
4. Identified future enhancement opportunity: `getAuthorFeed` API could enrich digest with recent post engagement data (deferred -- out of scope for #852)

### New Considerations Discovered

- The AT Protocol `getProfile` endpoint used by `get-metrics` is publicly accessible and does not require authentication, but the existing script authenticates anyway for consistency with other commands -- this is fine
- Bluesky rate limits (5,000 points/hour, 35,000/day) are generous; one `getProfile` call per daily run is negligible
- App password auth is the current standard; OAuth for AT Protocol is the future direction but not yet required

# feat(community): Wire Bluesky into Community Monitor CI Workflow

Closes #852.

## Problem

The community monitor CI workflow (`scheduled-community-monitor.yml`) reports Bluesky as "Disabled -- Not configured" because it does not pass `BSKY_HANDLE` and `BSKY_APP_PASSWORD` secrets to the agent environment. The Bluesky platform adapter scripts (`bsky-community.sh`, `bsky-setup.sh`), the router entry in `community-router.sh`, the SKILL.md references, and the `community-manager` agent instructions are all already implemented and on main. The only missing piece is CI wiring.

### Prior Art

- The content publisher workflow (`scheduled-content-publisher.yml`) already passes `BSKY_HANDLE`, `BSKY_APP_PASSWORD`, and `BSKY_ALLOW_POST` (lines 62-64) -- confirming secrets exist in the repo.
- Learning from `2026-03-19-content-pipeline-channel-extension-pattern.md`: the 3-layer update pattern (generation, publisher script, CI workflow) applies here. Layers 1 and 2 are done; layer 3 (CI) is the gap.
- Learning from `2026-03-20-claude-code-action-max-turns-budget.md`: the monitor workflow was increased to 50 max-turns. Adding one more `bsky get-metrics` command adds ~1 turn of data collection -- well within budget.

## Acceptance Criteria

- [x] `scheduled-community-monitor.yml` passes `BSKY_HANDLE` and `BSKY_APP_PASSWORD` secrets as env vars to the `claude-code-action` step
- [x] The monitor prompt instructs the agent to collect Bluesky metrics (batch with existing platform calls)
- [ ] The digest file contract section `## Bluesky Metrics` is populated when Bluesky is configured
- [ ] `community platforms` shows Bluesky as `enabled` when secrets are set (already works locally -- this confirms CI behavior)
- [x] Verify the content publisher already passes Bluesky secrets (no change needed there)

## Test Scenarios

- Given `BSKY_HANDLE` and `BSKY_APP_PASSWORD` are set in repo secrets, when the community monitor runs, then Bluesky appears as `enabled` in platform detection and `## Bluesky Metrics` section is included in the digest
- Given `BSKY_HANDLE` and `BSKY_APP_PASSWORD` are NOT set, when the community monitor runs, then Bluesky appears as `disabled` and the digest omits `## Bluesky Metrics` (graceful degradation)
- Given the monitor workflow runs with Bluesky enabled, when data collection completes, then the Bluesky metrics command (`bsky get-metrics`) is batched with other platform calls using `;` separator to conserve turns
- Given the Bluesky API returns a non-2xx response (e.g., temporary outage, invalid credentials), when the monitor agent runs, then the error is logged and the digest is generated without Bluesky data (matches existing graceful degradation pattern -- the `;` separator ensures failures do not halt the batch)

## Implementation

### Phase 1: Wire Bluesky Secrets into CI Workflow

**File:** `.github/workflows/scheduled-community-monitor.yml`

1. Add `BSKY_HANDLE` and `BSKY_APP_PASSWORD` to the `env:` block of the `claude-code-action` step (after the LinkedIn env vars, lines ~60-61):

```yaml
          BSKY_HANDLE: ${{ secrets.BSKY_HANDLE }}
          BSKY_APP_PASSWORD: ${{ secrets.BSKY_APP_PASSWORD }}
```

Note: `BSKY_ALLOW_POST` is intentionally omitted -- the community monitor is read-only (monitoring, not posting). The defense-in-depth guard in `bsky-community.sh` prevents accidental posting when this variable is absent.

### Research Insights

**Security:** The secrets `BSKY_HANDLE` and `BSKY_APP_PASSWORD` are confirmed to exist in the repo's GitHub Secrets store -- the content publisher workflow (`scheduled-content-publisher.yml`) already references them successfully. No manual secret creation step is needed.

**Rate limits:** The AT Protocol allows 5,000 points/hour and 35,000 points/day. A single `getProfile` call per daily monitor run is negligible. No rate-limit mitigation is needed for this use case.

**Env indirection:** Per the learning `2026-03-19-github-actions-env-indirection-for-context-values.md`, all `${{ }}` expressions should flow through `env:` blocks. The existing pattern in this workflow already does this correctly for all secrets -- the Bluesky additions follow the same pattern.

### Phase 2: Add Bluesky to Monitor Prompt Data Collection

**File:** `.github/workflows/scheduled-community-monitor.yml`

2. Update the prompt's data collection instructions. Currently Batch 1 covers Discord + X. Add Bluesky to Batch 1 since it's a single fast API call:

In the prompt section under "Batch 1 (Discord + X)":

- Add: `bash $ROUTER bsky get-metrics` to the batch, separated by `;`
- Update the batch label from "Discord + X" to "Discord + X + Bluesky"

3. Update the prompt's digest template instruction. The prompt currently lists optional sections including `## X/Twitter Metrics` and `## LinkedIn Activity`. Add `## Bluesky Metrics` to the list of optional sections.

4. Update the workflow's comment header (line 2) to include Bluesky in the description.

### Phase 3: Verify

5. After merging, trigger a manual run: `gh workflow run scheduled-community-monitor.yml`
6. Poll until complete and verify the digest includes `## Bluesky Metrics` section

## Files Changed

| File | Change |
|------|--------|
| `.github/workflows/scheduled-community-monitor.yml` | Add Bluesky secrets to env, update prompt to include Bluesky in data collection and digest sections |

## Scope Boundary

The following are already done and require NO changes:

- `plugins/soleur/skills/community/scripts/bsky-community.sh` -- AT Protocol wrapper (complete)
- `plugins/soleur/skills/community/scripts/bsky-setup.sh` -- credential setup (complete)
- `plugins/soleur/skills/community/scripts/community-router.sh` -- Bluesky already in PLATFORMS array
- `plugins/soleur/skills/community/SKILL.md` -- Bluesky already documented in platform detection, scripts, and sub-commands
- `plugins/soleur/agents/support/community-manager.md` -- Bluesky already in digest, health, and engage capabilities

This is a 1-file change (CI workflow only).

## Context

- Predecessor issues: #139 (analysis only, closed), #470 (adapter refactor, complete)
- Related workflow: `scheduled-content-publisher.yml` (already passes Bluesky secrets)
- Engagement from Bluesky is high (16.38 interactions/post avg per #139 analysis)
- Bluesky grew 302% in 2025 (10M to 41M users) -- community monitoring on this platform has increasing strategic value

### Relevant Learnings Applied

| Learning | How it applies |
|----------|---------------|
| `content-pipeline-channel-extension-pattern` | Confirms this is a layer-3-only change (CI wiring); layers 1+2 complete |
| `claude-code-action-max-turns-budget` | 50-turn budget is sufficient; adding 1 API call is within headroom |
| `content-publisher-cla-ruleset-push-rejection` | The PR-based commit pattern in the monitor prompt (step 5) already handles CLA ruleset; no change needed |
| `github-required-checks-skip-ci-synthetic-status` | The synthetic `cla-check` and `test` status posts in step 5 already cover the Bluesky addition |
| `github-actions-env-indirection-for-context-values` | Secrets are passed via `env:` block (safe pattern), not interpolated in `run:` blocks |

### Future Enhancement (Out of Scope)

The AT Protocol's `app.bsky.feed.getAuthorFeed` endpoint could provide recent post engagement data (likes, reposts, replies per post) for richer digest content. This would require adding a `get-feed` command to `bsky-community.sh` and updating the community-manager agent's digest generation. Track separately if desired.

### References

- [AT Protocol Rate Limits](https://docs.bsky.app/docs/advanced-guides/rate-limits)
- [AT Protocol API Hosts and Auth](https://docs.bsky.app/docs/advanced-guides/api-directory)
- [app.bsky.actor.getProfile API](https://docs.bsky.app/docs/api/app-bsky-actor-get-profile)
