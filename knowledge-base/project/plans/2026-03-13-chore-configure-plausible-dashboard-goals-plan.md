---
title: "chore: configure Plausible dashboard goals"
type: chore
date: 2026-03-13
semver: patch
---

# Configure Plausible Dashboard Goals

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

- **Plausible Goals API (`/api/v1/sites/goals`):** Available on all paid plans (Growth+). Uses the same API key as the Stats API. The PUT endpoint is idempotent (find-or-create).
- **Outbound link tracking:** Requires dashboard-level enablement (Growth plan) plus script URL update. The Sites API alternative requires Enterprise plan. The `Outbound Link: Click` goal is automatically created by Plausible when the extension is enabled, but pre-creating it via API is harmless.
- **Blog path wildcard:** Plausible pageview goals support `*` wildcards. `/blog/*` matches all blog article URLs.
- **Getting Started path:** The docs site renders `pages/getting-started.md` at `/pages/getting-started.html` (Eleventy default permalink).
- **No CI workflow needed:** Goal provisioning is a one-time setup, not a recurring task. Run the script manually or via `workflow_dispatch` once.

## Acceptance Criteria

- [ ] Shell script `scripts/provision-plausible-goals.sh` creates 4 goals via Plausible Goals API
- [ ] Script is idempotent (PUT find-or-create; safe to run multiple times)
- [ ] Script exits 0 with warning when API key is missing
- [ ] Script exits 1 on API errors (401, 429, 5xx)
- [ ] Script prints `[ok]` confirmation for each goal created/found
- [ ] Script follows shell conventions: `set -euo pipefail`, `# --- Section ---` headers, `jq // empty`
- [ ] Outbound link tracking steps documented (dashboard toggle + script URL update)
- [ ] No new GitHub secrets required (reuses `PLAUSIBLE_API_KEY` and `PLAUSIBLE_SITE_ID` from #575)

## Test Scenarios

- Given `PLAUSIBLE_API_KEY` and `PLAUSIBLE_SITE_ID` are set, when the script runs, then 4 goals are created and each prints `[ok]`
- Given `PLAUSIBLE_API_KEY` is empty, when the script runs, then it prints a warning and exits 0
- Given the Plausible API returns HTTP 401, when the script runs, then it prints a diagnostic to stderr and exits 1
- Given the script has already run once, when it runs again, then it completes successfully without creating duplicates (PUT is idempotent)
- Given the blog has no articles yet, when the `/blog/*` pageview goal is created, then it still succeeds (goals do not require matching pages to exist)

## Non-Goals

- **Weekly analytics changes:** The snapshot script (`weekly-analytics.sh`) already works. Goal data will appear in snapshots automatically once goals exist.
- **UTM conventions:** Tracked separately in #579.
- **Funnel analysis:** Plausible supports funnels but they require goals as prerequisites. Funnels can be configured after goals are proven useful.
- **Revenue tracking:** Not applicable for the current product stage.

## Dependencies and Risks

| Risk | Mitigation |
|------|-----------|
| API key lacks Sites API scope | Goals API uses the standard Stats API key; no special scope needed |
| Plausible changes API endpoint | v1 has no deprecation timeline; fix is a straightforward URL update |
| Outbound link script URL unknown until dashboard toggle | Document as a post-provisioning manual step; Playwright can automate if needed |
| Getting Started page path changes | Eleventy permalink conventions are stable; update goal if path changes |

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
