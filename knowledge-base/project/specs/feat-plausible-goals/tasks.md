# Tasks: Configure Plausible Dashboard Goals

## Phase 1: Setup

- [ ] 1.1 Verify branch is `feat/plausible-goals` (not main)
- [ ] 1.2 Verify `scripts/weekly-analytics.sh` exists as reference for shell conventions

## Phase 2: Core Implementation

- [ ] 2.1 Create `scripts/provision-plausible-goals.sh`
  - [ ] 2.1.1 Shebang, `set -euo pipefail`, section headers
  - [ ] 2.1.2 `SCRIPT_DIR` / `REPO_ROOT` resolution (match `weekly-analytics.sh` pattern)
  - [ ] 2.1.3 Environment variable declarations (`PLAUSIBLE_API_KEY`, `PLAUSIBLE_SITE_ID`, `PLAUSIBLE_BASE_URL`)
  - [ ] 2.1.4 Credential check with early `exit 0` on missing vars
  - [ ] 2.1.5 `api_put()` helper: curl with Bearer auth, HTTP status validation (401/429/5xx), JSON body
  - [ ] 2.1.6 `create_event_goal()` function: PUT with `goal_type: "event"`, `event_name` param
  - [ ] 2.1.7 `create_page_goal()` function: PUT with `goal_type: "page"`, `page_path` param
  - [ ] 2.1.8 Create goal: Newsletter Signup (custom event)
  - [ ] 2.1.9 Create goal: Getting Started pageview (`/pages/getting-started.html`)
  - [ ] 2.1.10 Create goal: Blog article pageviews (`/blog/*`)
  - [ ] 2.1.11 Create goal: Outbound Link: Click (custom event)
  - [ ] 2.1.12 Print `[ok]` confirmation for each goal
  - [ ] 2.1.13 Make script executable (`chmod +x`)

## Phase 3: Testing

- [ ] 3.1 Dry-run test: verify script exits 0 with warning when `PLAUSIBLE_API_KEY` is empty
- [ ] 3.2 Dry-run test: verify script exits 0 with warning when `PLAUSIBLE_SITE_ID` is empty
- [ ] 3.3 Run `shellcheck scripts/provision-plausible-goals.sh` (if available)
- [ ] 3.4 Verify script follows constitution conventions (`set -euo pipefail`, section headers, `jq // empty`)

## Phase 4: Documentation

- [ ] 4.1 Add inline comments documenting the outbound link manual steps (dashboard toggle + script URL update)
- [ ] 4.2 Verify no version files are bumped (frozen sentinels)

## Phase 5: Ship

- [ ] 5.1 Run compound
- [ ] 5.2 Commit and push
- [ ] 5.3 Create PR with `Closes #578` in body
