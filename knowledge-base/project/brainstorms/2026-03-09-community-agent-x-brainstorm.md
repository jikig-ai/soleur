# Brainstorm: Extend Community Agent with X Presence

**Date:** 2026-03-09
**Issue:** #127
**Approach:** Platform Adapter Pattern (Approach A)
**Participants:** CMO, CCO, repo-research-analyst, learnings-researcher

## What We're Building

A platform-agnostic refactor of the community-manager agent that adds X/Twitter as the first non-Discord platform, using an adapter pattern that unblocks all 8 open platform extension issues (#127, #134-#140). This includes:

1. **Platform adapter abstraction** — Each platform gets a shell script implementing a common interface (`fetch-mentions`, `fetch-metrics`, `post-reply`, `fetch-timeline`). The agent's capabilities (digest, health, content suggestions, engagement) call adapters, not platform-specific APIs directly.

2. **X/Twitter integration (Free tier)** — New `x-community.sh` script for data collection and monitoring. Read-only monitoring + engagement drafting within the 50 tweets/month free tier limit.

3. **Community SKILL.md** — Fix the documented tech debt from #96. The skill becomes the unified entry point with sub-commands (`digest`, `health`, `engage`, `platforms`).

4. **X account bootstrap** — Register @soleur on X. Profile branding aligned with brand guide. Manual founder action.

## Why This Approach

- **8 platform issues are open.** Bolting X on as a point solution means repeating the same work 7 more times. The adapter pattern is a one-time investment that unblocks all of them.
- **social-distribute already generates X content.** The community agent should focus on monitoring and engagement, not broadcast content creation. Clear ownership: social-distribute = broadcast, community-manager = monitoring + engagement.
- **Free tier is sufficient for MVP.** 50 tweets/month covers engagement replies. Monitoring (read-only) is unlimited on Free tier. Upgrade to Basic ($100/mo) when posting volume demands it.
- **The community skill is structurally broken.** No SKILL.md means `/soleur:community` doesn't work. Fixing it as part of this refactor ensures the new multi-platform agent has a proper entry point.

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | **Platform Adapter Pattern** over X sidecar or agent split | One-time investment unblocks all 8 platform issues. Clean separation of platform logic from agent capabilities. |
| 2 | **@soleur** as X handle | Cleanest handle, matches brand. Check availability; fallback to @soleur_ai. |
| 3 | **Free tier first** | 50 tweets/month is enough for engagement. Read-only monitoring is unlimited. Upgrade path clear. |
| 4 | **Monitor + engage** scope | Not just read-only monitoring. Agent drafts replies to mentions and engages in relevant threads. But no original content posting (that's social-distribute's job). |
| 5 | **Include community SKILL.md fix** | Fix documented tech debt in-scope. Clean foundation for multi-platform entry point. |
| 6 | **No brainstorm routing change needed** | Current domain config already routes "community engagement" to CCO -> community-manager. Confirmed by research. |

## Architecture Sketch

```
skills/community/
├── SKILL.md                    # Entry point: digest, health, engage, platforms
└── scripts/
    ├── discord-community.sh    # Existing — refactored to adapter interface
    ├── github-community.sh     # Existing — refactored to adapter interface
    ├── x-community.sh          # NEW — X API adapter (Free tier)
    ├── discord-setup.sh        # Existing — credential setup
    └── x-setup.sh              # NEW — X credential setup + validation

agents/support/
└── community-manager.md        # Refactored: platform-agnostic capabilities
                                # Calls adapters via platform flag
```

### Adapter Interface (per platform script)

Each `*-community.sh` script implements:

- `fetch-mentions [--since TIMESTAMP]` — Recent mentions/messages
- `fetch-metrics` — Follower count, engagement rate, activity summary
- `post-reply MESSAGE [--in-reply-to ID]` — Reply to a specific message/tweet
- `fetch-timeline [--count N]` — Recent timeline/channel activity

### Agent Capabilities (platform-agnostic)

| Capability | Description | Platforms |
|------------|-------------|-----------|
| Digest | Collect cross-platform activity, generate unified digest | All enabled |
| Health | Cross-platform community health metrics | All enabled |
| Content Suggestions | Analyze activity, suggest content topics | All enabled |
| Engage | Draft replies to mentions, review before posting | X (new), Discord (existing via webhook) |

## Open Questions

1. **Is @soleur available on X?** Check before registering. Fallback: @soleur_ai.
2. **X API rate limit management.** Free tier = 50 tweets/month. How should the agent track remaining quota to avoid hitting limits?
3. **Engagement approval flow.** Should replies require user approval before posting (like discord-content's AskUserQuestion pattern), or can some be auto-approved?
4. **Digest format extension.** Current digest headings are Discord-specific. How should the unified digest present multi-platform metrics without breaking existing consumers?
5. **X moderation policy.** X is public and adversarial. Need response SLAs, tone guidelines, escalation paths before going live with engagement.

## Capability Gaps

| Gap | Domain | What Is Missing | Why Needed |
|-----|--------|-----------------|------------|
| X API shell script | Support | No `x-community.sh` for fetching mentions, followers, timeline | Community-manager cannot monitor X without a data collection script |
| X credential setup | Support | No `x-setup.sh` for API key provisioning and validation | Agent cannot authenticate without credential infrastructure |
| X account | Operations | No account exists — manual founder action | Everything depends on this |
| Community SKILL.md | Engineering | Entry point missing — scripts exist without discoverable skill | Agent capabilities not invocable via `/soleur:community` |
| X moderation guide | Support | No response SLAs, escalation paths, or tone guidelines for X | X is public — moderation policy needed before engagement goes live |
| Platform abstraction | Engineering | Agent hardcoded to Discord primitives | Adding any platform without abstraction creates parallel code paths |

## CMO Assessment Summary

- **Handle squatting risk is high** — register @soleur ASAP
- **Cold-start problem** — new account needs follower building before content distribution threads will get reach
- **Content ownership is clear** — social-distribute = broadcast, community-manager = monitoring + engagement
- **Brand guide X channel notes exist** — agent must read them when generating engagement content
- **X is P2 channel** in marketing strategy — but high leverage for #buildinpublic and solofounder audience

## CCO Assessment Summary

- **Community digests are stale** (last: 2026-02-19, 18 days ago) — establish baseline before adding platform
- **No support documentation infrastructure** — `knowledge-base/support/` doesn't exist
- **X is adversarial** — unlike Discord (gated community), X posts are public. Moderation guide needed
- **Cross-platform dedup** not addressed — same person on Discord + X could double-count metrics
- **Brainstorm routing already works** — no change needed, confirmed

## Not In Scope

- Automated X posting for blog distribution (that's social-distribute's job)
- X API Basic or Pro tier (start Free, upgrade later)
- Other platform integrations (#134-#140) — this refactor enables them, but implementation is separate
- X DM support — public engagement only for MVP
- Paid advertising on X
