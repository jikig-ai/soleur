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

The probe emits one of six `failure_mode` values. Each maps to a
distinct triage path.

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

### `settings_provider_disabled`

`/auth/v1/settings` returned `external.<provider>: false`. Either an
operator toggled the provider off in the Supabase dashboard, or a
provider OAuth credential expired (Supabase auto-disables broken
providers). Re-enable in the Supabase Auth dashboard; if credentials
are stale, rotate the OAuth client secret.

## Diagnostic recipes

### Sentry — recent auth events

Sentry search syntax does **not** support `AND`/`OR`
(`sentry-api-boolean-search-not-supported-20260406.md`). Tag filters
are space-separated and AND'd implicitly:

```bash
curl -s --max-time 10 \
  -H "Authorization: Bearer $SENTRY_AUTH_TOKEN" \
  "https://de.sentry.io/api/0/projects/$SENTRY_ORG/$SENTRY_PROJECT/issues/?statsPeriod=24h&query=feature:auth"
```

For per-op slicing, run separate queries per `op:<verb>`.

### Sentry — alert rule status

```bash
curl -s --max-time 10 \
  -H "Authorization: Bearer $SENTRY_AUTH_TOKEN" \
  "https://de.sentry.io/api/0/projects/$SENTRY_ORG/$SENTRY_PROJECT/rules/" \
  | jq '.[] | {name, lastTriggered, status}'
```

Confirms the three rules (`auth-exchange-code-burst`,
`auth-callback-no-code-burst`, `auth-per-user-loop`) exist and shows
when each last fired.

### Re-run the probe on demand

```bash
gh workflow run scheduled-oauth-probe.yml
gh run watch
```

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
