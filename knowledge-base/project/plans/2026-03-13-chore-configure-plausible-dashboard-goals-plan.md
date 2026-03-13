---
title: "chore: configure Plausible dashboard goals"
type: chore
date: 2026-03-13
semver: patch
---

# Configure Plausible Dashboard Goals

## Enhancement Summary

**Deepened on:** 2026-03-13
**Sections enhanced:** 4 (Proposed Solution, Technical Considerations, Test Scenarios, Dependencies)
**Research sources:** Plausible Sites/Goals API docs, shell API wrapper hardening learnings, jq pitfall learnings, `weekly-analytics.sh` pattern analysis

### Key Improvements

1. Added 5-layer API wrapper hardening pattern from institutional learnings (curl stderr suppression, JSON validation on 2xx, jq fallback chains)
2. Added `require_jq` startup check for consistency with sibling scripts
3. Added verification step using `GET /api/v1/sites/goals` to confirm all 4 goals exist after provisioning
4. Clarified API response format (always 200, same structure for create and find)

## Overview

Create a shell script that provisions Plausible goals via the Goals API (`PUT /api/v1/sites/goals`), and enable outbound link click tracking. This completes the Plausible operationalization initiative started in #575.

## Problem Statement / Motivation

Plausible is deployed and weekly snapshots are automated (#575), but no conversion goals are configured. Without goals, the analytics snapshots show only aggregate traffic -- there is no visibility into whether visitors take high-value actions (newsletter signups, getting-started page visits, blog reads, outbound clicks to GitHub/Discord). The `Newsletter Signup` custom event is already instrumented in `base.njk:134` but Plausible ignores it until a matching goal exists in the dashboard.

## Proposed Solution

Two deliverables:

### Deliverable 1: Goal Provisioning Script

Create `scripts/provision-plausible-goals.sh` that uses the Plausible Goals API to create four goals idempotently (the `PUT` endpoint is find-or-create):

| Goal | Type | API Parameter |
|------|------|--------------|
| Newsletter Signup | Custom event | `goal_type: "event"`, `event_name: "Newsletter Signup"` |
| Getting Started pageview | Pageview | `goal_type: "page"`, `page_path: "/pages/getting-started.html"` |
| Blog article pageviews | Pageview | `goal_type: "page"`, `page_path: "/blog/*"` |
| Outbound Link: Click | Custom event | `goal_type: "event"`, `event_name: "Outbound Link: Click"` |

**Script requirements:**

- `#!/usr/bin/env bash` with `set -euo pipefail`
- `# --- Section Name ---` comment headers per constitution.md
- Environment variables: `PLAUSIBLE_API_KEY`, `PLAUSIBLE_SITE_ID`, optional `PLAUSIBLE_BASE_URL` (defaults to `https://plausible.io`)
- Early `exit 0` with warning if either required env var is empty (same pattern as `weekly-analytics.sh`)
- HTTP status validation on every API call (401 = bad key, 429 = rate limited, 4xx/5xx = error)
- Print `[ok] Created/found goal: <name>` for each successful goal
- Idempotent: safe to run multiple times (PUT is find-or-create)

**API call pattern (per goal):**

```text
PUT /api/v1/sites/goals
Authorization: Bearer <PLAUSIBLE_API_KEY>
Content-Type: application/json

For event goals:
  {"site_id":"<PLAUSIBLE_SITE_ID>","goal_type":"event","event_name":"<name>"}

For pageview goals:
  {"site_id":"<PLAUSIBLE_SITE_ID>","goal_type":"page","page_path":"<path>"}
```

**API response format (200 OK for both create and find):**

```json
{
    "domain": "soleur.ai",
    "id": "1",
    "display_name": "Newsletter Signup",
    "goal_type": "event",
    "event_name": "Newsletter Signup",
    "page_path": null
}
```

The API always returns 200 -- it does not distinguish between "created" and "found". The `[ok]` message should use neutral language: `[ok] Goal ready: <display_name>`.

### Research Insights: Shell API Wrapper Hardening

From learning `2026-03-09-shell-api-wrapper-hardening-patterns.md`, the `api_put()` helper must implement 5 defensive layers:

| Layer | Defense | Implementation |
|-------|---------|---------------|
| Input | Validate env vars before use | Early `exit 0` for missing, `exit 1` for malformed |
| Transport | Suppress curl stderr, check curl exit code | `curl ... 2>/dev/null` with `if !` wrapper to catch connection failures |
| Response status | HTTP status code validation | Case statement: 2xx = success, 401/429/4xx/5xx = error with diagnostic |
| Response body | Validate JSON before consuming | `jq . >/dev/null 2>&1` on 2xx responses |
| Error extraction | jq fallback chain | `jq -r '.error // "Unknown error"' 2>/dev/null \|\| echo "Unknown error"` |

From learning `2026-03-10-require-jq-startup-check-consistency.md`, add a `require_jq()` startup check matching the pattern in sibling scripts:

```bash
require_jq() {
  if ! command -v jq &>/dev/null; then
    echo "Error: jq is required but not installed." >&2
    echo "Install it: https://jqlang.github.io/jq/download/" >&2
    exit 1
  fi
}
```

From learning `2026-03-03-set-euo-pipefail-upgrade-pitfalls.md`, no grep pipelines exist in this script, but all jq commands that parse API responses need `2>/dev/null || echo "fallback"` to handle malformed JSON without crashing under `set -euo pipefail`.

### Research Insights: Verification Step

After provisioning all 4 goals, add a verification step using the list endpoint:

```text
GET /api/v1/sites/goals?site_id=<PLAUSIBLE_SITE_ID>
```

Count the returned goals and print a summary: `[ok] Verified: N goals configured for <PLAUSIBLE_SITE_ID>`. This follows the constitution.md principle: "Diagnostic scripts must print positive confirmation on success, not just absence of error."

### Deliverable 2: Enable Outbound Link Tracking

Outbound link tracking requires two changes:

**2a. Enable the extension in Plausible dashboard settings.**

The Sites API endpoint (`PUT /api/v1/sites/:site_id` with `tracker_script_configuration.outbound_links: true`) requires an Enterprise plan. Since we are on the Growth plan, this is a manual dashboard toggle: Site Settings > General > Site Installation > enable "Outbound Links".

However, creating the `Outbound Link: Click` goal via the Goals API (Deliverable 1) prepares the dashboard to display outbound link data. The dashboard toggle + script update is the remaining step.

**2b. Update the tracking script in `base.njk`.**

After enabling outbound links in the dashboard, the Plausible script URL changes (the proxied filename `pa-XXXX.js` is regenerated to include the extension). The new snippet must be copied from Site Settings > Site Installation and replaced in `plugins/soleur/docs/_includes/base.njk:69`.

**Automation boundary:** The script provisioning (Deliverable 1) is fully automatable. The outbound link dashboard toggle and script URL update require either Enterprise-tier API access or a Playwright session to the Plausible dashboard. The plan provisions the goal and documents the two manual steps.

### Deliverable 3: GitHub Secrets Setup

Document the required GitHub secrets for goal provisioning:

- `PLAUSIBLE_API_KEY` -- same key used by `weekly-analytics.sh`
- `PLAUSIBLE_SITE_ID` -- same value (e.g., `soleur.ai`)

No new secrets are needed if the weekly analytics secrets from #575 are already configured. The provisioning script uses the same environment variables.

## Technical Considerations

- **Plausible Goals API (`/api/v1/sites/goals`):** Available on all paid plans (Growth+). Uses the same API key as the Stats API. The PUT endpoint is idempotent (find-or-create). Always returns HTTP 200 with the goal object regardless of whether it was created or already existed.
- **Outbound link tracking:** Requires dashboard-level enablement (Growth plan) plus script URL update. The Sites API alternative (`PUT /api/v1/sites/:site_id` with `tracker_script_configuration`) requires Enterprise plan. The `Outbound Link: Click` goal is automatically created by Plausible when the extension is enabled, but pre-creating it via API is harmless.
- **Blog path wildcard:** Plausible pageview goals support `*` wildcards. `/blog/*` matches all blog article URLs.
- **Getting Started path:** The docs site renders `pages/getting-started.md` at `/pages/getting-started.html` (Eleventy default permalink).
- **No CI workflow needed:** Goal provisioning is a one-time setup, not a recurring task. Run the script manually or via `workflow_dispatch` once.
- **curl stderr token leakage:** All curl calls must use `2>/dev/null` to prevent the Bearer token from appearing in stderr during connection failures or redirects (learning: `2026-03-09-shell-api-wrapper-hardening-patterns.md`).
- **weekly-analytics.sh pattern divergence:** The existing script uses `api_get()` with `curl -s -o <tmpfile> -w "%{http_code}"` and manual HTTP status checks. The new script should follow the same pattern for consistency but add the JSON validation layer that the existing script lacks. The existing script also lacks `require_jq` -- do not add it retroactively in this PR (out of scope).

## Acceptance Criteria

- [x] Shell script `scripts/provision-plausible-goals.sh` creates 4 goals via Plausible Goals API
- [x] Script is idempotent (PUT find-or-create; safe to run multiple times)
- [x] Script exits 0 with warning when API key is missing
- [x] Script exits 1 on API errors (401, 429, 5xx)
- [x] Script prints `[ok]` confirmation for each goal created/found
- [x] Script prints verification summary after all goals are provisioned
- [x] Script includes `require_jq` startup check
- [x] Script suppresses curl stderr to prevent token leakage
- [x] Script validates JSON on 2xx responses before consuming
- [x] Script follows shell conventions: `set -euo pipefail`, `# --- Section ---` headers, `jq // empty`
- [x] Outbound link tracking steps documented (dashboard toggle + script URL update)
- [x] No new GitHub secrets required (reuses `PLAUSIBLE_API_KEY` and `PLAUSIBLE_SITE_ID` from #575)

## Test Scenarios

- Given `PLAUSIBLE_API_KEY` and `PLAUSIBLE_SITE_ID` are set, when the script runs, then 4 goals are created and each prints `[ok]`
- Given `PLAUSIBLE_API_KEY` is empty, when the script runs, then it prints a warning and exits 0
- Given `PLAUSIBLE_SITE_ID` is empty, when the script runs, then it prints a warning and exits 0
- Given the Plausible API returns HTTP 401, when the script runs, then it prints a diagnostic to stderr and exits 1
- Given the Plausible API returns HTTP 429, when the script runs, then it prints a diagnostic to stderr and exits 1
- Given the script has already run once, when it runs again, then it completes successfully without creating duplicates (PUT is idempotent)
- Given the blog has no articles yet, when the `/blog/*` pageview goal is created, then it still succeeds (goals do not require matching pages to exist)
- Given the Plausible API returns a 200 with malformed JSON body, when the script parses the response, then it exits 1 with a diagnostic rather than propagating garbage
- Given curl cannot connect to the API (network error), when the script runs, then it exits 1 with a connection error message and does not leak the Bearer token to stderr
- Given jq is not installed, when the script runs, then it exits 1 immediately with an install instruction

## Non-Goals

- **Weekly analytics changes:** The snapshot script (`weekly-analytics.sh`) already works. Goal data will appear in snapshots automatically once goals exist.
- **UTM conventions:** Tracked separately in #579.
- **Funnel analysis:** Plausible supports funnels but they require goals as prerequisites. Funnels can be configured after goals are proven useful.
- **Revenue tracking:** Not applicable for the current product stage.
- **Retroactive hardening of `weekly-analytics.sh`:** The existing script lacks `require_jq`, JSON validation, and curl stderr suppression. These are pre-existing issues that should be addressed in a separate PR, not in this one.

## Dependencies and Risks

| Risk | Mitigation |
|------|-----------|
| API key lacks Sites API scope | Goals API uses the standard Stats API key; no special scope needed |
| Plausible changes API endpoint | v1 has no deprecation timeline; fix is a straightforward URL update |
| Outbound link script URL unknown until dashboard toggle | Document as a post-provisioning manual step; Playwright can automate if needed |
| Getting Started page path changes | Eleventy permalink conventions are stable; update goal if path changes |
| Malformed JSON from API on 2xx | Validate JSON with `jq . >/dev/null 2>&1` before consuming (learning: shell-api-wrapper-hardening) |
| Bearer token leakage via curl stderr | Suppress with `2>/dev/null` on all curl calls (learning: shell-api-wrapper-hardening) |

## References

- Parent issue: #575 (Plausible analytics operationalization)
- Related issue: #579 (UTM conventions)
- Weekly analytics script: `scripts/weekly-analytics.sh`
- Newsletter Signup event: `plugins/soleur/docs/_includes/base.njk:134`
- Plausible tracking script: `plugins/soleur/docs/_includes/base.njk:69`
- Getting Started page: `plugins/soleur/docs/pages/getting-started.md`
- Blog directory: `plugins/soleur/docs/blog/`
- [Plausible Sites/Goals API](https://plausible.io/docs/sites-api)
- [Plausible Outbound Link Tracking](https://plausible.io/docs/outbound-link-click-tracking)
- Learning: `knowledge-base/project/learnings/integration-issues/2026-03-13-plausible-analytics-operationalization-pattern.md`
- Learning: `knowledge-base/project/learnings/2026-03-09-shell-api-wrapper-hardening-patterns.md`
- Learning: `knowledge-base/project/learnings/2026-03-10-require-jq-startup-check-consistency.md`
- Learning: `knowledge-base/project/learnings/2026-03-03-set-euo-pipefail-upgrade-pitfalls.md`
