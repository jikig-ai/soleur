# Tasks: LinkedIn API Scripts

## Phase 1: Setup

- [ ] 1.1 Create `plugins/soleur/skills/community/scripts/linkedin-community.sh` with shebang, header comment block, `set -euo pipefail`
- [ ] 1.2 Create `plugins/soleur/skills/community/scripts/linkedin-setup.sh` with shebang, header comment block, `set -euo pipefail`
- [ ] 1.3 Add API base URL constant and version constant (`LINKEDIN_API="https://api.linkedin.com"`, `LINKEDIN_API_VERSION="202602"`)

## Phase 2: Core Implementation — linkedin-community.sh

- [ ] 2.1 Implement `require_jq()` dependency check
- [ ] 2.2 Implement `require_credentials()` — check `LINKEDIN_ACCESS_TOKEN` (required), `LINKEDIN_CLIENT_ID`, `LINKEDIN_CLIENT_SECRET` (required for introspection), `LINKEDIN_PERSON_URN` (optional, for person posting)
- [ ] 2.3 Implement `handle_response()` — 2xx JSON validation, 401 expired token message, 403 permission error, 429 depth-limited retry, default error extraction (`.message // .code // "Unknown error"`)
- [ ] 2.4 Implement `get_request()` — Bearer token auth with LinkedIn-specific headers (`X-Restli-Protocol-Version`, `Linkedin-Version`), curl stderr suppression, depth parameter
- [ ] 2.5 Implement `post_request()` — same headers as GET, JSON body support, depth parameter
- [ ] 2.6 Implement `cmd_post_content()` — parse `--text`, `--visibility` (default: PUBLIC), `--author` (default: person). Build Posts API request body. Extract post URN from `x-restli-id` response header.
  - [ ] 2.6.1 Handle person posting: use `LINKEDIN_PERSON_URN` env var as author URN
  - [ ] 2.6.2 Handle organization posting: use `LINKEDIN_ORGANIZATION_ID` env var, format as `urn:li:organization:{id}`
  - [ ] 2.6.3 Validate `--visibility` is `public` or `connections` (map to `PUBLIC` or `CONNECTIONS`)
- [ ] 2.7 Implement `cmd_fetch_metrics()` — stub that prints gated message and exits 1
- [ ] 2.8 Implement `cmd_fetch_activity()` — stub that prints gated message and exits 1
- [ ] 2.9 Implement `main()` — command dispatch, usage output, `require_jq` + `require_credentials` before dispatch
- [ ] 2.10 Add source guard: `if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then main "$@"; fi`

## Phase 3: Core Implementation — linkedin-setup.sh

- [ ] 3.1 Implement `require_jq()` dependency check
- [ ] 3.2 Implement `require_client_credentials()` — check `LINKEDIN_CLIENT_ID`, `LINKEDIN_CLIENT_SECRET`
- [ ] 3.3 Implement `cmd_validate_credentials()` — POST to `/oauth/v2/introspectToken` with client_id, client_secret, token. Parse response: `active`, `expires_at`, `scope`. Calculate days remaining. Output JSON to stdout, status message to stderr.
- [ ] 3.4 Implement `cmd_check_expiry()` — call validate_credentials internally. Parse `--threshold` arg (default: 14). If days remaining < threshold, send Discord webhook notification. If `DISCORD_WEBHOOK_URL` not set, print warning to stderr only. Exit 0 on success, exit 1 if token expired.
- [ ] 3.5 Implement `cmd_generate_token()` — check if `agent-browser` CLI is available. If yes, launch Playwright script to drive LinkedIn token generator. If no, print manual URL and instructions. Capture token and call `cmd_write_env()`.
- [ ] 3.6 Implement `cmd_write_env()` — require `LINKEDIN_CLIENT_ID`, `LINKEDIN_CLIENT_SECRET`, `LINKEDIN_ACCESS_TOKEN` in env. Remove existing LINKEDIN_ vars from `.env`, chmod 600, append new vars.
- [ ] 3.7 Implement `cmd_verify()` — source `.env`, check required vars, call `cmd_validate_credentials()`.
- [ ] 3.8 Implement `main()` — command dispatch with `require_jq` before dispatch (no `require_openssl` needed — no OAuth signing).

## Phase 4: SKILL.md Updates

- [ ] 4.1 Update Platform Detection table — add `LINKEDIN_CLIENT_ID`, `LINKEDIN_CLIENT_SECRET` as additional required vars for full functionality
- [ ] 4.2 Update Scripts list — add `linkedin-community.sh` and `linkedin-setup.sh` entries with descriptions
- [ ] 4.3 Update `platforms` sub-command setup instructions — reference `linkedin-setup.sh` commands
- [ ] 4.4 Verify LinkedIn is correctly listed in all sub-command sections (digest, health, engage)

## Phase 5: Testing & Validation

- [ ] 5.1 Run `shellcheck plugins/soleur/skills/community/scripts/linkedin-community.sh` — zero warnings
- [ ] 5.2 Run `shellcheck plugins/soleur/skills/community/scripts/linkedin-setup.sh` — zero warnings
- [ ] 5.3 Test `linkedin-community.sh` with no credentials set — verify error message format
- [ ] 5.4 Test `linkedin-community.sh post-content` with valid credentials — verify post creation
- [ ] 5.5 Test `linkedin-setup.sh validate-credentials` — verify token introspection output
- [ ] 5.6 Test `linkedin-setup.sh check-expiry` — verify threshold logic and Discord notification
- [ ] 5.7 Verify SKILL.md changes render correctly in platform detection
- [ ] 5.8 Test source guard — `source linkedin-community.sh` should not execute main
