# Phase 0 scope probe — Sentry credential surface for the followthroughs

Statuses and scope names only. No token values, no hashes. Every reading below was taken with
`curl --disable --noproxy '*' -o /dev/null -w '%{http_code}'`, the bearer read from a header
file under an xtrace refusal, never printed. Ref #7946, #7993.

## Token scopes (`GET https://jikigai-eu.sentry.io/api/0/` → `.auth.scopes`), read 2026-09-11 pre-mint

| Credential | Store | Scopes |
|---|---|---|
| `inline-read-prd` (`SENTRY_ISSUE_RO_TOKEN`) | Doppler `soleur/prd` (byte-identical copy in `prd_terraform`) | `[event:read, org:read]` |
| `iac-terraform-prd` (`SENTRY_IAC_AUTH_TOKEN`) | GitHub repo secret; mirrored in Doppler `soleur/prd` | `[alerts:read, alerts:write, event:read, org:read, project:admin, project:read, project:write]` |
| personal (`SENTRY_AUTH_TOKEN`, Doppler `soleur/prd_terraform`) | Doppler `prd_terraform` only | `[alerts:read, alerts:write, event:admin, event:read, event:write, org:admin, org:integrations, org:read, org:write, project:admin, project:read, project:releases, project:write, team:admin, team:read, team:write]` |
| Doppler `soleur/prd` `SENTRY_AUTH_TOKEN` | a different value — the `web-platform-ci` runtime token | `[org:ci, org:read, project:read, project:releases, project:write]` |

## Per-consumer endpoint table, read 2026-09-11 pre-mint

| Endpoint (GET) | Callers | `inline-read-prd` on `jikigai-eu` | on `jikigai` (legacy slug) | Control `iac-terraform-prd` |
|---|---|---|---|---|
| `/api/0/organizations/{org}/` | 1 (`sync-health-residual-5689.sh`) | 200 | 403 | — |
| `/api/0/organizations/{org}/events/` | 9 | 200 | 403 | — |
| `/api/0/organizations/{org}/monitors/{slug}/checkins/` | 3 (`community-monitor-checkin-soak-5728.sh`, `ghcr-minter-live-6031.sh`, `sentry-checkins-3859.sh`) | **403** | 403 | 200 on `jikigai-eu`, 403 on `jikigai` |
| `/api/0/projects/{org}/{project}/issues/` | 1 (`sync-health-residual-5689.sh`) | 200 | 404 | 200 |
| `/api/0/projects/{org}/{project}/events/` — `fresh-host-boot-trail.sh` (not a followthrough) | 1 | **403** | — | 200 |

The check-in endpoint's `permission_classes = (ProjectAlertRulePermission,)` has
`scope_map["GET"] = [project:read, project:write, project:admin, alerts:read, alerts:write]`
(Sentry `src/sentry/monitors/endpoints/base.py` + `src/sentry/api/bases/project.py`, and the
public reference for `retrieve-checkins-for-a-monitor`). `event:read` is not among them. The
project-events endpoint requires one of `project:admin`, `project:read`, `project:write`.

**Derived minimum for the union of both consumer classes:** `[event:read, org:read, project:read]`.
`project:read` over `alerts:read` because it is the one scope satisfying both the check-in
endpoint and the boot-trail's project-events endpoint. Dashboard form: Issue & Event = Read,
Organization = Read, Project = Read, everything else No Access.

**The legacy org slug `jikigai` is dead for every credential** (403 / 404 above under both the
read-only and the IaC token). `sentry-checkins-3859.sh` and `sync-health-residual-5689.sh` move
to `jikigai-eu` in this PR.

## Post-mint readings (`actions-read-prd`, slug `actions-read-prd-fc548f`, minted 2026-09-11T16:12Z)

Minted in the dashboard through `agent-browser` (headed; the operator cleared login + 2FA — the
one interactive step; the form itself had no CAPTCHA/MFA/passkey). Form: name
`actions-read-prd`; Issue & Event = Read, Organization = Read, Project = Read; every other
resource No Access; no webhook. **Sentry did NOT auto-issue a token on creation here** (the
Tokens panel read "You haven't created any authentication tokens yet"; the vendor doc's claim
did not hold) — one token was created with *New Token*; the panel holds exactly one after a
reload (`************2dcf`, scopes `event:read, org:read, project:read`). Captured with
`agent-browser get value 'input[aria-label="Generated token"]'` into a 0700 trap directory and
shredded; stored on stdin; never on argv, never in a snapshot.

Integration list (`GET /api/0/organizations/jikigai-eu/sentry-apps/`, names and scopes only):
`actions-read-prd` is one of **five** internal integrations on the org
(`inline-read-prd`, `postmerge-issue-rw`, `iac-terraform-prd`, `web-platform-ci` are the others).

| Reading | Result |
|---|---|
| `.auth.scopes` (sorted) | `["event:read","org:read","project:read"]` — exactly the triple, no implied extra |
| `https://sentry.io/api/0/organizations/jikigai-eu/` | 200; `.links.regionUrl` = `https://de.sentry.io` (pinned) |
| `https://sentry.io/api/0/organizations/jikigai-eu/events/?field=…` | 200 |
| `https://jikigai-eu.sentry.io/api/0/organizations/jikigai-eu/events/?field=count()` (6297's host) | 200 |
| `https://de.sentry.io/api/0/organizations/jikigai-eu/monitors/scheduled-community-monitor/checkins/` (5728's host) | 200 |
| `https://sentry.io/api/0/organizations/jikigai-eu/monitors/<slug>/checkins/` ×8 (3859's slugs) | 200 ×8 |
| `https://sentry.io/api/0/organizations/jikigai-eu/monitors/scheduled-ghcr-token-minter/checkins/` (6031) | 404 — the monitor does not exist until that cutover; 6031 reports this as its own pre-cutover TRANSIENT; not a scope reading, and the same under the IaC control |
| `https://de.sentry.io/api/0/projects/jikigai-eu/web-platform/issues/` (5689) | 200 |
| `https://de.sentry.io/api/0/projects/jikigai-eu/web-platform/events/` (boot-trail) | 200 |

Two instrument corrections made while verifying, both in `scripts/rotate-sentry-actions-ro-token.sh`
and neither about the token: the org-events probe lacked the `field=` the endpoint requires
(HTTP 400 "No columns selected" — every real caller passes one), and `.links.regionUrl` is
served by the org endpoint, not by `/api/0/`.

Repo secret: `gh secret list | grep -c '^SENTRY_ACTIONS_RO_TOKEN'` = 1 (AC-7).
