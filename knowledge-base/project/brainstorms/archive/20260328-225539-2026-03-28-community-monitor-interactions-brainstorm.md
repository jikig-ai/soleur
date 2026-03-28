# Community Monitor: GitHub Issue Comment Interactions

**Date:** 2026-03-28
**Status:** Complete
**Participants:** Founder

## What We're Building

Add external user interaction tracking to the daily community monitor digest. The first phase adds GitHub issue/PR comment tracking — surfacing when external users (non-org, non-bot) comment on project issues and PRs.

The digest will include a summary table showing commenter, issue/PR title, and a comment snippet, grouped by issue. This gives daily visibility into community engagement without manually scanning GitHub notifications.

## Why This Approach

- **Extend `github-community.sh`** with a `fetch-interactions` command rather than creating a new script. This follows the existing one-script-per-platform convention and the community-router pattern.
- **REST API** over GraphQL — the existing script uses REST exclusively, and the `author_association` field on comment endpoints makes external user filtering trivial.
- **External comments only** — org members, bots, and self-authored comments are filtered out. The signal is "who from the outside is engaging with us?"
- **Summary table format** — commenter, issue/PR title, comment snippet. Enough context to decide whether to respond, without overwhelming the digest.

## Key Decisions

1. **GitHub only for now** — X/Twitter reply tracking deferred until API tier upgraded (Free tier blocks fetch-mentions with 403)
2. **External comments only** — filter using `author_association` field (keep `NONE`, `CONTRIBUTOR`, `FIRST_TIMER`, `FIRST_TIME_CONTRIBUTOR`; exclude `MEMBER`, `OWNER`, `COLLABORATOR`)
3. **Summary table format** — grouped by issue, showing commenter + snippet
4. **Extend existing script** — add `fetch-interactions` command to `github-community.sh`
5. **24-hour lookback** — fetch comments from the last day to match daily digest cadence

## Open Questions

- None — scope is well-defined.

## Deferred

- X/Twitter reply tracking (requires Basic tier ~$100/mo)
- Reaction tracking on issues/PRs (can add later as a separate enhancement)
- Cross-platform interaction correlation
