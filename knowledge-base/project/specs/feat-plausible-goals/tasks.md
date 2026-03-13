# Tasks: Configure Plausible Dashboard Goals

## Phase 1: Setup

- [ ] 1.1 Verify branch is `feat/plausible-goals` (not main)
- [ ] 1.2 Verify `scripts/weekly-analytics.sh` exists as reference for shell conventions

## Phase 2: Core Implementation

- [ ] 2.1 Create `scripts/provision-plausible-goals.sh`
  - [ ] 2.1.1 Shebang, `set -euo pipefail`, section headers
  - [ ] 2.1.2 `SCRIPT_DIR` / `REPO_ROOT` resolution (match `weekly-analytics.sh` pattern)
  - [ ] 2.1.3 Environment variable declarations (`PLAUSIBLE_API_KEY`, `PLAUSIBLE_SITE_ID`, `PLAUSIBLE_BASE_URL`)
  - [ ] 2.1.4 `require_jq()` startup check (match sibling script pattern)
  - [ ] 2.1.5 Credential check with early `exit 0` on missing vars
  - [ ] 2.1.6 `api_put()` helper with 5-layer hardening:
    - [ ] 2.1.6a curl with Bearer auth and stderr suppression (`2>/dev/null`)
    - [ ] 2.1.6b `if !` wrapper to catch connection failures
    - [ ] 2.1.6c HTTP status validation (401/429/4xx/5xx case statement)
    - [ ] 2.1.6d JSON validation on 2xx responses (`jq . >/dev/null 2>&1`)
    - [ ] 2.1.6e jq fallback chain for error extraction (`jq ... || echo "fallback"`)
  - [ ] 2.1.7 `create_event_goal()` function: PUT with `goal_type: "event"`, `event_name` param
  - [ ] 2.1.8 `create_page_goal()` function: PUT with `goal_type: "page"`, `page_path` param
  - [ ] 2.1.9 Create goal: Newsletter Signup (custom event)
  - [ ] 2.1.10 Create goal: Getting Started pageview (`/pages/getting-started.html`)
  - [ ] 2.1.11 Create goal: Blog article pageviews (`/blog/*`)
  - [ ] 2.1.12 Create goal: Outbound Link: Click (custom event)
  - [ ] 2.1.13 Print `[ok] Goal ready: <display_name>` for each goal
  - [ ] 2.1.14 Verification step: GET `/api/v1/sites/goals` and print summary count
  - [ ] 2.1.15 Make script executable (`chmod +x`)

## Phase 3: Testing

- [ ] 3.1 Dry-run test: verify script exits 0 with warning when `PLAUSIBLE_API_KEY` is empty
- [ ] 3.2 Dry-run test: verify script exits 0 with warning when `PLAUSIBLE_SITE_ID` is empty
- [ ] 3.3 Dry-run test: verify `require_jq` fails with install instructions when jq is missing
- [ ] 3.4 Run `shellcheck scripts/provision-plausible-goals.sh` (if available)
- [ ] 3.5 Verify script follows constitution conventions (`set -euo pipefail`, section headers, `jq // empty`)
- [ ] 3.6 Verify curl stderr suppression on all curl calls (no token leakage)

## Phase 4: Documentation

- [ ] 4.1 Add inline comments documenting the outbound link manual steps (dashboard toggle + script URL update)
- [ ] 4.2 Verify no version files are bumped (frozen sentinels)

## Phase 5: Ship

- [ ] 5.1 Run compound
- [ ] 5.2 Commit and push
- [ ] 5.3 Create PR with `Closes #578` in body
