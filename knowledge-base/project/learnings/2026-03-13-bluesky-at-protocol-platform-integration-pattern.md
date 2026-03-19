# Learning: Bluesky AT Protocol Platform Integration Pattern

## Problem

The community agent supported Discord, GitHub, and X/Twitter but had no Bluesky integration. Bluesky has the highest engagement among emerging platforms (16.38 interactions/post avg) with a developer-heavy audience that overlaps Soleur's ICP. Adding it as the 4th platform required AT Protocol integration following the existing ad-hoc script pattern.

## Solution

Followed the established two-script pattern: `bsky-setup.sh` for credential provisioning and `bsky-community.sh` for the engagement loop. Key implementation decisions:

1. **Fresh session per invocation** via `com.atproto.server.createSession`. App password → JWT bearer token. No caching or refresh logic — sessions last minutes, scripts run seconds. Dependencies: `curl` + `jq` only.

2. **Single `post` command** handles both new posts and replies via optional `--reply-to-uri/cid --root-uri/cid` flags. Plain text only (no facets). Returns `{uri, cid}` for thread chaining.

3. **`listNotifications` for mentions** filtered by `reason: "mention"` instead of `searchPosts`, which returns false positives from partial text matches.

4. **`wc -m` for length validation** as codepoint approximation of Bluesky's 300-grapheme limit. Conservative (codepoints >= graphemes), so posts may be shorter than allowed but never over-length.

5. **`--platform` flag on `engage` sub-command** so user explicitly selects between X/Twitter and Bluesky. Cursor-based pagination state stored in `.soleur/bsky-engage-cursor`.

6. **Brand guide channel notes** with Bluesky-specific guardrails: smaller community = lower reply cadence (5 vs 10), no hashtags, anti-bot sensitivity.

## Key Insight

AT Protocol is significantly simpler than X's OAuth 1.0a — the setup script is ~160 lines vs X's 326 lines, and the community script is ~280 lines vs X's 577 lines. The protocol is free with no access tiers, eliminating the entire free-tier fallback path that X requires. When adding new platform integrations, verify the target API's auth model and access restrictions live before speccing to avoid overscoping (the X integration was overscoped 3x per prior learning `2026-03-09-external-api-scope-calibration.md`).

## Prevention

- **Platform integration checklist:** Verify API endpoints live before speccing. Follow the two-script pattern (setup + community). Use the narrowest API for mentions (notifications, not search).
- **Defer abstraction:** 4 platform scripts share patterns but aren't abstracted (#470). Extract shared helpers only when the same logic exists in 3+ scripts AND has been stable for 2+ iterations.
- **Rate limit handling:** Bluesky uses `ratelimit-reset` header (Unix timestamp), not body JSON like X. Each platform script handles its own format.
- **Do not parse AT Protocol JSON with grep/sed.** URIs contain colons, slashes, and dots that break regex. Use `jq` exclusively.

## Related

- `2026-03-09-shell-api-wrapper-hardening-patterns.md` — 5-layer defense adapted for AT Protocol
- `2026-03-09-depth-limited-api-retry-pattern.md` — max 3 retries with depth guard
- `2026-03-09-external-api-scope-calibration.md` — X was overscoped 3x; Bluesky avoided this
- `2026-03-11-multi-platform-publisher-error-propagation.md` — exit code conventions for platform-not-configured vs real failures
- #139 — this feature
- #470 — platform adapter interface (follow-up refactor)

## Tags
category: integration-issues
module: plugins/soleur/skills/community
