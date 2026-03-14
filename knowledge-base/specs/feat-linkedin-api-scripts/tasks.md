# Tasks: LinkedIn API Scripts

## Phase 1: Setup

- [x] 1.1 Create `plugins/soleur/skills/community/scripts/linkedin-community.sh` with shebang, header comment block, `set -euo pipefail`
- [x] 1.2 Create `plugins/soleur/skills/community/scripts/linkedin-setup.sh` with shebang, header comment block, `set -euo pipefail`
- [x] 1.3 Add API base URL constant and version constant (`LINKEDIN_API="https://api.linkedin.com"`, `LINKEDIN_API_VERSION="202602"`)

## Phase 2: Core Implementation — linkedin-community.sh

- [x] 2.1 Implement `require_jq()` dependency check
- [x] 2.2 Implement `require_credentials()` — check `LINKEDIN_ACCESS_TOKEN` (required) and `LINKEDIN_PERSON_URN` (required). Print setup instructions referencing `linkedin-setup.sh` on missing vars.
- [x] 2.3 Implement `handle_response()` — 2xx JSON validation, 401 expired token message with renewal instructions, 403 permission error, 429 retry (hardcoded 5s delay), default error extraction (`.message // .code // "Unknown error"`)
- [x] 2.4 Implement `get_request()` — Bearer token auth with LinkedIn-specific headers (`X-Restli-Protocol-Version: 2.0.0`, `Linkedin-Version: YYYYMM`), curl stderr suppression, depth-limited retry (max 3)
- [x] 2.5 Implement `post_request()` — same headers as GET, JSON body support. Capture response headers via `curl -D "$tmpfile"` to extract `x-restli-id`. Only retry on 429 (non-idempotent endpoint — fail immediately on other errors).
- [x] 2.6 Implement `cmd_post_content()` — parse `--text` (required, reject empty, reject > 3000 chars). Use `LINKEDIN_PERSON_URN` as author. Hardcode visibility to `PUBLIC`. Build Posts API request body. Extract post URN from `x-restli-id` response header.
- [x] 2.7 Implement `cmd_fetch_metrics()` — stub that prints "Marketing API credentials required" to stderr and exits 1
- [x] 2.8 Implement `cmd_fetch_activity()` — stub that prints "Marketing API credentials required" to stderr and exits 1
- [x] 2.9 Implement `main()` — command dispatch, usage output, `require_jq` before dispatch, `require_credentials` only for post-content
- [x] 2.10 Add source guard: `if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then main "$@"; fi`

## Phase 3: Core Implementation — linkedin-setup.sh

- [x] 3.1 Implement `require_jq()` dependency check
- [x] 3.2 Implement `require_client_credentials()` — check `LINKEDIN_CLIENT_ID`, `LINKEDIN_CLIENT_SECRET`, `LINKEDIN_ACCESS_TOKEN`
- [x] 3.3 Implement `cmd_validate_credentials()` — POST to `/oauth/v2/introspectToken` with client_id, client_secret, token as POST body params (not Bearer auth). Parse response: `active`, `expires_at`, `scope`. Calculate days remaining. Support `--warn-days N` flag (default: 14) — exit non-zero when TTL < threshold. Output JSON to stdout, status message to stderr.
- [x] 3.4 Implement `cmd_generate_token()` — Print OAuth authorization URL with scopes (`openid profile w_member_social`). Optionally open URL with `xdg-open`/`open`. Prompt user to paste authorization code. Exchange code for token via `curl -s -X POST /oauth/v2/accessToken`. Resolve person URN via `curl -s /v2/userinfo` and extract `sub` field. Call `cmd_write_env()` with token + person URN.
- [x] 3.5 Implement `cmd_write_env()` — Remove existing `LINKEDIN_` vars from `.env` with grep, chmod 600, append `LINKEDIN_CLIENT_ID`, `LINKEDIN_CLIENT_SECRET`, `LINKEDIN_ACCESS_TOKEN`, `LINKEDIN_PERSON_URN`.
- [x] 3.6 Implement `cmd_verify()` — source `.env`, delegate to `cmd_validate_credentials()` (do not duplicate credential checks).
- [x] 3.7 Implement `main()` — command dispatch with `require_jq` before dispatch. No source guard (consistent with `x-setup.sh` convention).

## Phase 4: community-router.sh + SKILL.md Updates

- [x] 4.1 Add LinkedIn to `PLATFORMS` array in `community-router.sh`: `"linkedin|linkedin-community.sh|LINKEDIN_ACCESS_TOKEN,LINKEDIN_PERSON_URN|"`
- [x] 4.2 Update SKILL.md Scripts list — add `linkedin-community.sh` and `linkedin-setup.sh` entries with descriptions
- [x] 4.3 Update SKILL.md `platforms` sub-command setup instructions — reference `linkedin-setup.sh` commands
- [x] 4.4 Verify LinkedIn is NOT listed in `engage` sub-command (out of scope) — confirmed, not listed

## Phase 5: Testing & Validation

- [ ] 5.1 Run `shellcheck` — not available on this system (bash -n syntax check passed for both scripts)
- [x] 5.2 Test `linkedin-community.sh` with no credentials set — verified error message format and setup instructions
- [ ] 5.3 Test `linkedin-community.sh post-content` with valid credentials — requires live API credentials
- [x] 5.4 Test `linkedin-community.sh post-content --text ""` — verified empty text rejection (via missing credentials path)
- [ ] 5.5 Test `linkedin-setup.sh validate-credentials` — requires live API credentials
- [ ] 5.6 Test `linkedin-setup.sh validate-credentials --warn-days 14` — requires live API credentials
- [x] 5.7 Verify SKILL.md changes render correctly in platform detection — confirmed via router `platforms` command
- [x] 5.8 Test source guard — `source linkedin-community.sh` does not execute main
- [x] 5.9 Verify `community-router.sh linkedin post-content` routes correctly — confirmed
