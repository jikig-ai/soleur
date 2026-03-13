# Tasks: Bluesky Community Presence

## Phase 1: Account Setup and Credentials

- [ ] 1.1 Claim `@soleur.bsky.social` handle (manual — browser)
- [ ] 1.2 Generate app password via Bluesky settings
- [ ] 1.3 Create `plugins/soleur/skills/community/scripts/bsky-setup.sh`
  - [ ] 1.3.1 `write-env` command — append credentials to `.env` with `chmod 600`
  - [ ] 1.3.2 `verify` command — create session, fetch profile, confirm identity
- [ ] 1.4 Add `BSKY_HANDLE`, `BSKY_APP_PASSWORD` to `.env.example` (if exists)

## Phase 2: AT Protocol API Wrapper

- [ ] 2.1 Create `plugins/soleur/skills/community/scripts/bsky-community.sh`
  - [ ] 2.1.1 Header, dependency checks (`curl`, `jq`), credential validation
  - [ ] 2.1.2 `create_session` — fresh session per invocation, no caching
  - [ ] 2.1.3 `handle_response` — JSON validation on 2xx, 429 retry (max 3, depth-limited, read `ratelimit-reset` header), 401 fail, error extraction from `{error, message}` format
  - [ ] 2.1.4 `get_request` / `post_request` helpers with Bearer token
  - [ ] 2.1.5 `create-session` command
  - [ ] 2.1.6 `post` command — plain text (no facets), codepoint length validation via `wc -m`, optional `--reply-to-uri/cid --root-uri/cid` flags for replies. Returns `{uri, cid}` JSON.
  - [ ] 2.1.7 `get-metrics` command — fetch profile stats
  - [ ] 2.1.8 `get-notifications` command — fetch `listNotifications` filtered by `reason: "mention"`, cursor-based pagination

## Phase 3: Agent + Skill Wiring

- [ ] 3.1 Update `plugins/soleur/agents/support/community-manager.md`
  - [ ] 3.1.1 Add `### Bluesky (optional)` prerequisites
  - [ ] 3.1.2 Add `bsky-community.sh` and `bsky-setup.sh` to Scripts
  - [ ] 3.1.3 Update Capability 1 (Digest) with `bsky-community.sh get-metrics`
  - [ ] 3.1.4 Update Capability 2 (Health) with Bluesky metrics display
  - [ ] 3.1.5 Add Bluesky to Capability 4 (Mention Engagement) — `get-notifications`, brand-voice replies, 300-char limit, cursor state file, headless mode
  - [ ] 3.1.6 Add `## Bluesky Metrics` to digest heading contract
  - [ ] 3.1.7 Update agent description to include Bluesky
- [ ] 3.2 Update `plugins/soleur/skills/community/SKILL.md`
  - [ ] 3.2.1 Add Bluesky to Platform Detection table
  - [ ] 3.2.2 Add `bsky-community.sh` and `bsky-setup.sh` to Scripts (markdown links)
  - [ ] 3.2.3 Update `platforms` sub-command display
  - [ ] 3.2.4 Add `--platform` flag to `engage` sub-command (prompt if not specified)
  - [ ] 3.2.5 Update skill description to mention Bluesky

## Phase 4: Brand Guide

- [ ] 4.1 Add `### Bluesky` to `knowledge-base/marketing/brand-guide.md` Channel Notes
