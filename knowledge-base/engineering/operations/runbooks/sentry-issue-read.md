# Runbook: Reading a Sentry issue/event inline (no SSH)

**TL;DR:** `doppler run -p soleur -c prd -- scripts/sentry-issue.sh <issue-id>` reads a
production Sentry issue; add `--latest-event <issue-id>` for the actual stack/exception.
GET-only, read-only, zero SSH. Pull the error yourself — never eyeball the dashboard
(`hr-no-dashboard-eyeball-pull-data-yourself`).

## Diagnosis

The **first step** for any no-SSH Sentry diagnosis is the inline read — never `ssh`,
`docker exec`, or `journalctl`:

```bash
# Issue summary (culprit, counts, status):
doppler run -p soleur -c prd -- scripts/sentry-issue.sh 1234567890

# The real error — exception value + stack frames:
doppler run -p soleur -c prd -- scripts/sentry-issue.sh --latest-event 1234567890

# Mask obvious email/bearer values before pasting into a shared/persistent context:
doppler run -p soleur -c prd -- scripts/sentry-issue.sh --latest-event 1234567890 --redact
```

The real error lives at `exception.values[].value` (message) and
`exception.values[].stacktrace.frames[]` (stack) in the `--latest-event` JSON.

**Observability layer:** this reads the **Sentry** layer (issues/events the
`sentry-correlation` Inngest middleware + the pino→Sentry breadcrumb mirror ship). For
host/container **logs** over a time window, use the sibling **Better Stack** layer
(`scripts/betterstack-query.sh`, runbook `betterstack-log-query.md`) — the ClickHouse log
warehouse, a different signal source.

## The token trap (event:read)

The issue/event endpoints require an **`event:read`** scope. `SENTRY_API_TOKEN` /
`SENTRY_AUTH_TOKEN` carry Discover/ingest scope only and **403** on `/issues/<id>/`.

| Credential (Doppler `soleur/prd`) | Scope | Use for |
|---|---|---|
| `SENTRY_ISSUE_RO_TOKEN` | **`[event:read, org:read]`** (read-only) | this CLI — least-privilege |
| `SENTRY_ISSUE_RW_TOKEN` | `event:admin` (read+write) | GET-only fallback until RO is minted; postmerge auto-resolve |
| `SENTRY_API_TOKEN` / `SENTRY_AUTH_TOKEN` | Discover/ingest | **403 on issues** — cannot read an issue |

A **403** means "token lacks `event:read`" — swap to `SENTRY_ISSUE_RO_TOKEN`. A **401**
is a token-scope/membership signal, **not** proof the org is unowned (ADR-031 glossary).

## Host (EU)

`SENTRY_API_HOST=jikigai-eu.sentry.io` — the **org-subdomain**. NOT `eu.sentry.io` (it
rewrites `-eu`-suffixed slugs → 302/401 cascade) and NOT `de.sentry.io` (ingest-only;
404s on `/api/`). See ADR-031 `Cluster / Host Glossary`.

## Re-minting the read-only token (if lost/rotated)

The Sentry provider exposes **no Terraform token resource**, so the read-only token is
minted by Soleur automation, **not** an operator UI step.

**Primary path — same-origin API mint via the authenticated browser session.** The logged-in
`jikigai-eu.sentry.io` session (the org owner) already carries `org:admin` + `org:integrations`
— it *is* the bootstrap credential, so no separate org-admin token is needed. Drive it from
`browser_evaluate` so requests inherit the session cookies; read the CSRF token from the
`sentry-sc` cookie and send it as the `X-CSRFToken` header. This avoids the react-select
permission UI entirely (that UI is flaky under automation — the browser context closed
repeatedly mid-form-fill during the #5506 mint, which is what deferred AC7 in the first place).

1. **Create the internal integration** — POST the **global** collection, with `organization`
   in the body. (The org-scoped `/api/0/organizations/<org>/sentry-apps/` is **GET-only —
   POST returns 405**; creation lives on the global endpoint.)

   ```js
   // inside browser_evaluate on any jikigai-eu.sentry.io page (authenticated)
   const csrf = (document.cookie.split('; ').find(c => c.startsWith('sentry-sc='))||'').split('=').slice(1).join('=');
   await fetch('/api/0/sentry-apps/', { method:'POST', credentials:'include',
     headers:{ 'Content-Type':'application/json', 'X-CSRFToken':csrf },
     body: JSON.stringify({ name:'inline-read-prd', organization:'jikigai-eu', isInternal:true,
       verifyInstall:false, scopes:['event:read','org:read'], events:[], webhookUrl:'' }) });
   // → 201; response.slug is e.g. inline-read-prd-<hash>
   ```

2. **Mint the token** — `POST /api/0/sentry-apps/<slug>/api-tokens/` (empty body). **The raw
   token value is returned ONLY in this POST response** — the list endpoint
   (`GET .../api-tokens/`) masks it (`tokenLastCharacters` only), so capture it here, not later.
   Save it straight to a file with `browser_evaluate`'s `filename` param so it never prints to
   the transcript or renders in a screenshot. If you accidentally discard the value, `DELETE`
   the orphan token by id and mint a fresh one — never leave an uncaptured live token.

3. **Store** (value via stdin so it never lands in argv/history; never echo), then **shred**
   the temp file:

   ```bash
   printf '%s' "<token>" | doppler secrets set SENTRY_ISSUE_RO_TOKEN -p soleur -c prd --no-interactive
   ```

4. **Verify** end-to-end (200, and the RW-fallback warning is gone):

   ```bash
   doppler run -p soleur -c prd -- scripts/sentry-issue.sh <known-issue-id>
   ```

**Fallback — Playwright UI.** If the API path is unavailable, drive
`https://jikigai-eu.sentry.io` (NOT `eu.sentry.io` — it rewrites `-eu` slugs) → Settings →
Developer Settings → New Internal Integration. Name `inline-read-prd`; permissions
**Issue & Event = Read, Organization = Read, everything else No Access** (yields
`[event:read, org:read]`). Capture the token via `browser_evaluate` on the token field —
**never a screenshot**. Only a real MFA/CAPTCHA/passkey gate is a legitimate operator handoff
(record `playwright-attempt:` evidence).

Integration creation logs `sentry-app.add` to the Organization Audit Log (§5(2) evidence).

## PII caveat

Sentry's ingest scrub (`server/sentry-scrub.ts`) is **key-name only** — it does NOT
remove PII embedded in **values** (an email in an exception message, a free-text
breadcrumb, a `user.*` tag). This inline read is therefore **not** as scrubbed as Better
Stack (which passes Vector's 3-stage `pii_scrub`). Do not paste raw event bodies into
shared/persistent contexts; use `--redact` for obvious email/bearer masking. The read path
is recorded in the Article 30 register (PA-08).
