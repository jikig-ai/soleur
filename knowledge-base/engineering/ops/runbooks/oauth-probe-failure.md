---
title: OAuth probe failure runbook
date: 2026-04-29
owners: engineering/ops
applies_to:
  - .github/workflows/scheduled-oauth-probe.yml
  - apps/web-platform/scripts/configure-sentry-alerts.sh
related_issues: [2997, 2979, 2982, 3001]
related_prs: [2975, 2994, 3007]
---

# OAuth probe failure runbook

Triage steps for `[ci/auth-broken] Synthetic OAuth probe failed` issues
or `[Soleur Ops] OAuth probe failure: ...` emails fired by
`.github/workflows/scheduled-oauth-probe.yml`. The probe runs every
15 minutes from a GitHub-hosted runner against the prod public auth
surface (`app.soleur.ai/login`, `api.soleur.ai/auth/v1/...`).

## L3-first triage gate

Before any L7 hypothesis (redeploying the web container, rotating
Supabase secrets, editing Cloudflare rules), confirm L3/network
health. Per `hr-ssh-diagnosis-verify-firewall`, network-layer drift
masquerades as application failure more often than the reverse.

The gate:

```bash
# L3/DNS
dig +time=5 +tries=2 +short CNAME api.soleur.ai
dig +time=5 +tries=2 +short A app.soleur.ai

# Cloudflare reachability (look for cf-ray header)
curl -sI --max-time 10 https://app.soleur.ai/ | grep -iE '^(cf-ray|server):'
curl -sI --max-time 10 https://api.soleur.ai/auth/v1/settings | grep -iE '^(cf-ray|server):'
```

If both `cf-ray` headers are present and DNS resolves, **L3 is healthy
— go L7**. Otherwise, follow `admin-ip-drift.md` (and Cloudflare/DNS
operational runbooks) before mutating application state.

## Failure modes

The probe emits one of eight `failure_mode` values. Each maps to a
distinct triage path.

### `network_error`

Curl itself failed before getting an HTTP response (DNS lookup failed,
TLS handshake error, TCP connect timeout). Most often:

- **Cloudflare incident** affecting the soleur.ai zone — check
  <https://www.cloudflarestatus.com> first.
- **GitHub-hosted runner egress disruption** — check
  <https://www.githubstatus.com>.
- **DNS drift** — `dig +time=5 +tries=2 +short A app.soleur.ai`.

If only one of `app.soleur.ai` / `api.soleur.ai` is unreachable, the
issue is typically scoped to that hostname's CDN config; both unreachable
points to a network-layer issue rather than application state.

### `login_unreachable`

`https://app.soleur.ai/login` returned non-200. Most often a deploy
broke the web container or Cloudflare proxying drifted.

Diagnose:

```bash
gh run list --workflow=web-platform-release.yml --limit 5
ssh prod-web -- 'docker ps --format "table {{.Names}}\t{{.Status}}"'
ssh prod-web -- 'docker logs --tail 200 web-platform | tail -100'
```

Remediation: roll back the most recent web-platform deploy via
`gh workflow run web-platform-release.yml --ref <known-good-sha>` if
the deploy is the cause. **SSH is read-only diagnosis; fixes ship via
Terraform/CI.**

### `google_authorize` / `github_authorize`

`api.soleur.ai/auth/v1/authorize?provider=<X>` did not 302 to the
expected provider host (`accounts.google.com` / `github.com`). Two
common root causes:

1. **`NEXT_PUBLIC_SUPABASE_URL` placeholder leaked into the build**
   — the regression class fixed by PR #2975. Check:

   ```bash
   gh secret view NEXT_PUBLIC_SUPABASE_URL --repo jikig-ai/soleur
   ```

   If the value contains `placeholder`, `example`, or any
   non-canonical hostname, this is the cause. Remediation: re-set the
   secret to the prod Supabase project URL and trigger a redeploy.

2. **`SUPABASE_AUTH_EXTERNAL_<PROVIDER>_REDIRECT_URI` allow-list drift
   in Supabase Auth.** Check the Supabase dashboard auth settings; the
   redirect URI list must contain `https://app.soleur.ai/callback`.

### `settings_http`

`api.soleur.ai/auth/v1/settings` returned non-200. Usually the
Supabase Auth gateway is degraded or the API hostname/CNAME drifted.

Diagnose:

```bash
dig +time=5 +tries=2 +short CNAME api.soleur.ai
curl -sv --max-time 10 https://api.soleur.ai/auth/v1/settings 2>&1 | tail -30
```

Cross-link: <https://status.supabase.com>.

### `settings_invalid_json`

Settings endpoint returned 200 but non-JSON (typically a Cloudflare
edge HTML page or a rate-limit response). Treat as transient unless
it persists across two probe runs.

### `settings_misconfigured`

The workflow's `SUPABASE_ANON_KEY` env (sourced from
`secrets.NEXT_PUBLIC_SUPABASE_ANON_KEY`) is empty. `/auth/v1/settings`
requires the anon `apikey` header — without it, the endpoint returns
401. This failure mode means the secret is unset on the workflow,
NOT that auth is broken. Set the secret with:

```bash
doppler secrets get NEXT_PUBLIC_SUPABASE_ANON_KEY -p soleur -c prd --plain \
  | tr -d '\r\n' \
  | gh secret set NEXT_PUBLIC_SUPABASE_ANON_KEY
# `--body-file` does not exist on `gh secret set`; `--body -` would set the
# literal '-'. Omit `--body` entirely so gh reads the JWT from stdin without
# exposing it on the process command line. Verified: gh secret set --help (gh 2.92.0).
```

### `settings_provider_disabled`

`/auth/v1/settings` returned `external.<provider>: false`. Either an
operator toggled the provider off in the Supabase dashboard, or a
provider OAuth credential expired (Supabase auto-disables broken
providers). Re-enable in the Supabase Auth dashboard; if credentials
are stale, rotate the OAuth client secret.

### `callback_error_passthrough`

`GET https://app.soleur.ai/callback?error=access_denied` did not
redirect to `/login?error=oauth_cancelled`. The probe asserts that
provider-side OAuth errors (specifically the user-cancel signal
`access_denied`) are classified by the callback route and routed to
the dedicated `oauth_cancelled` error copy — NOT conflated with
generic `auth_failed`.

Two common root causes:

1. **Regression in `app/(auth)/callback/route.ts`** — someone removed
   or moved the `classifyProviderError` branch that runs before the
   `if (code)` block. Check the most recent diff:

   ```bash
   git log --oneline -- apps/web-platform/app/\(auth\)/callback/route.ts | head -5
   git show <suspect-sha> -- apps/web-platform/app/\(auth\)/callback/route.ts
   ```

   The branch is load-bearing: without it, every user who cancels at
   the OAuth consent screen sees the misleading "try email instead"
   copy from `auth_failed`. Roll back the offending change or restore
   the branch.

2. **Edge / proxy stripped the `error=` query param** — Cloudflare
   Workers, redirect rules, or a CDN cache key normalizer can drop
   query params it doesn't recognize. Verify the inbound URL reaches
   the route with `error=access_denied` intact:

   ```bash
   curl -sI --max-time 10 \
     "https://app.soleur.ai/callback?error=access_denied" \
     -H 'Cache-Control: no-cache'
   # Expect: HTTP/2 307, location: .../login?error=oauth_cancelled
   ```

   If the response is `307 .../login?error=auth_failed`, the param
   was stripped at the edge — check Cloudflare Page Rules / Transform
   Rules / Workers in the soleur.ai zone for routes matching
   `/callback*`.

Cross-link: PR that introduced the classifier — check `git log` for
the `provider-error-classifier.ts` add commit. The Sentry op for this
class is `feature:auth, op:callback_provider_error` (queryable
without re-deployment).

## Diagnostic recipes

All recipes assume `SENTRY_API_HOST` is set to the org's Sentry region
hostname (`sentry.io` for US, `de.sentry.io` for EU). Default is EU for
the Soleur org as of 2026-04-29; export the variable explicitly if you
want to target a specific region:

```bash
export SENTRY_API_HOST="${SENTRY_API_HOST:-de.sentry.io}"
```

The configurator script (`apps/web-platform/scripts/configure-sentry-alerts.sh`)
auto-detects the region — it prints `[info] Using Sentry API host: <host>`
on startup. Mirror that value into recipes below if your org migrates regions.

### Sentry — recent auth events

Sentry search syntax does **not** support `AND`/`OR`
(`sentry-api-boolean-search-not-supported-20260406.md`). Tag filters
are space-separated and AND'd implicitly:

```bash
curl -s --max-time 10 \
  -H "Authorization: Bearer $SENTRY_AUTH_TOKEN" \
  "https://${SENTRY_API_HOST}/api/0/projects/$SENTRY_ORG/$SENTRY_PROJECT/issues/?statsPeriod=24h&query=feature:auth"
```

For per-op slicing, run separate queries per `op:<verb>`.

### Sentry — alert rule status

```bash
curl -s --max-time 10 \
  -H "Authorization: Bearer $SENTRY_AUTH_TOKEN" \
  "https://${SENTRY_API_HOST}/api/0/projects/$SENTRY_ORG/$SENTRY_PROJECT/rules/" \
  | jq '.[] | {name, lastTriggered, status}'
```

Confirms the three rules (`auth-exchange-code-burst`,
`auth-callback-no-code-burst`, `auth-per-user-loop`) exist and shows
when each last fired.

### Reconcile alert rules (rule drift / missing rule)

If a rule is missing from the GET output above, or someone edited a
rule via the Sentry UI and it has drifted from the configurator's
canonical config, re-run the idempotent configurator:

```bash
SENTRY_AUTH_TOKEN=$(doppler secrets get SENTRY_AUTH_TOKEN -p soleur -c prd --plain) \
SENTRY_ORG=$(doppler secrets get SENTRY_ORG -p soleur -c prd --plain) \
SENTRY_PROJECT=$(doppler secrets get SENTRY_PROJECT -p soleur -c prd --plain) \
bash apps/web-platform/scripts/configure-sentry-alerts.sh
```

The script is idempotent: re-running produces zero net changes when
state is already correct. It fails closed if a rule name has been
duplicated in the UI (resolve the duplicate manually before re-running).

#### Accepted Sentry alert intervals

The Sentry `EventFrequencyCondition.interval` field accepts only:
`1m | 5m | 15m | 1h | 1d | 1w | 30d`. **`10m` is rejected** with HTTP
400. If the 60-day ratchet table below is updated to a new interval,
verify it is in this set first.

### Sentry config drift cleanup (`extra.*` field renames)

When a server-side change renames a Sentry `extra.*` extra-context key
(e.g., PR #3127 renamed `extra.text` → `extra.shape` for
`op:tool-label-scrub`), saved Sentry artifacts that filter or group on
the old key silently stop matching post-deploy. Run the audit script
in dry-run mode against prod Sentry to enumerate stale references
across all four artifact classes (issue alert rules, issue saved
searches, Discover saved queries, dashboard widgets):

```bash
doppler run -p soleur -c prd -- bash apps/web-platform/scripts/audit-sentry-extra-text-references.sh
```

Required token scope: `org:read`, `project:read`, `project:write`,
`event:read`. The Doppler `prd` `SENTRY_AUTH_TOKEN` may be a narrow
`sntrys_` org-auth token scoped only to releases — if the script exits
with `cannot read /organizations/.../`, override using the
broader-scoped `SENTRY_API_TOKEN`:

```bash
doppler run -p soleur -c prd -- bash -c \
  'SENTRY_AUTH_TOKEN="$SENTRY_API_TOKEN" \
   bash apps/web-platform/scripts/audit-sentry-extra-text-references.sh'
```

If zero matches: close the tracking issue with the dry-run output.
If non-zero matches: re-run with `--apply` (replace) or
`--apply --add-or-clause` (additive deploy-window posture, query
strings only — `fields[]` always replaces). The script self-verifies
on `--apply` and exits non-zero if any references remain.

**Sharp edge — tag vs. extra namespace.** The Sentry UI's issue-stream
search bar searches **tags** (`Sentry.setTag()`), not extra-context
(`Sentry.setExtra()`). Searching the issue stream for `extra.text`
returns zero results regardless of how many extra-context fields
exist. Saved searches and Discover/dashboard query strings DO
reference `extra.*` in free-text Sentry search syntax — the audit
script is the only complete inventory path. Do not skip the script.

### Re-run the probe on demand

`gh run watch` requires interactive selection (no TTY in agent
shells); the agent-friendly form is to dispatch and poll the latest
run:

```bash
gh workflow run scheduled-oauth-probe.yml
sleep 5
RUN_ID=$(gh run list --workflow=scheduled-oauth-probe.yml --limit 1 --json databaseId --jq '.[0].databaseId')
gh run view "$RUN_ID" --json status,conclusion --jq '"\(.status) \(.conclusion)"'
```

Repeat the `gh run view` until `status` is `completed`.

### External provider status (machine-readable)

When triaging `*_authorize` failures, distinguish "us vs them"
programmatically before mutating Soleur state:

```bash
# Google Cloud (covers Google OAuth)
curl -s --max-time 10 https://status.cloud.google.com/incidents.json \
  | jq '[.[] | select(.end == null)] | length' # number of open incidents

# GitHub
curl -s --max-time 10 https://www.githubstatus.com/api/v2/status.json \
  | jq -r '.status.indicator,.status.description'
```

If either reports an active incident touching identity / OAuth / login,
the probe failure is upstream — comment on the tracking issue with
the upstream incident link and wait, do not redeploy.

## Cross-references

- PR #2975 — `NEXT_PUBLIC_SUPABASE_URL` build-arg guardrail (most
  common `*_authorize` root cause).
- PR #2994 — Sentry mirroring on five auth ops (`feature:auth`,
  `op:<verb>`); the alert rules filter on these tags.
- PR #3007 — anon-key JWT-claims guardrail.
- Issue #2982 — provider-disabled UI gating (probe only checks
  google + github; Apple/Microsoft are out of scope).
- Issue #3001 — stale `code-verifier` cookie sweep (related but not
  detected by this probe).
- `admin-ip-drift.md` — L3 firewall allow-list runbook (referenced
  from the L3-first triage gate above).

## Re-evaluation criteria

When auth flows have been stable for **60 days** post-merge AND
sign-in MAU exceeds **100 users**, ratchet alert thresholds down:

| Rule                         | Current threshold | Ratcheted threshold |
| ---------------------------- | ----------------- | ------------------- |
| `auth-exchange-code-burst`   | 5 / 15m           | 3 / 15m             |
| `auth-callback-no-code-burst`| 3 / 15m           | 2 / 15m             |
| `auth-per-user-loop`         | 3 / 5m            | 2 / 5m              |

Schedule a calendar reminder via `/soleur:schedule` after merge so
the ratchet review fires automatically.

## Known limitations

- **Geographic isolation.** GitHub-hosted runners typically egress
  from US/Europe Azure regions. A regional Supabase/Cloudflare
  outage affecting only one geography may be invisible to the probe.
  Future hardening: Cloudflare Workers scheduled trigger for EU
  coverage.
- **External provider outages.** Google or GitHub OAuth degradation
  trips the probe and pages ops via the same path as our own
  regressions. Distinguish via <https://status.cloud.google.com>
  and <https://www.githubstatus.com> before mutating Soleur state.
