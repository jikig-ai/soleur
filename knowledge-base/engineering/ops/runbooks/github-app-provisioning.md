---
title: "GitHub App provisioning (manifest-prefilled)"
status: stable
applies_to: ["operator"]
related: ["#4115", "#3187", "#4066"]
---

# GitHub App provisioning runbook

Provision the Soleur GitHub App from a committed manifest, then paste the
3 identity credentials into Doppler. The manifest pre-fills GitHub's 12-field
App-create form so the operator clicks one button instead of typing 12 values.

**Operator-only.** Single manual gate: the click on GitHub's App-create form
(OAuth-consent-class carve-out per
[operator-only canonical list](../../../project/learnings/2026-05-15-operator-only-step-canonical-list.md)
case b). Everything else is automated.

## When to run this

- First-time prd setup (Soleur-as-tenant-zero).
- Future `stg` setup once a staging GitHub App is provisioned.
- App re-creation after a major permission change that requires a new App
  (rare; usually `terraform apply -replace` on the webhook secret + a
  manifest update is enough).
- Follow-up to a `permission_drift` alert from
  [`cron-github-app-drift-guard.ts`](../../../../apps/web-platform/server/inngest/functions/cron-github-app-drift-guard.ts).

## The 4-step operator flow

### Step 1 — Visit the init page and click **Create GitHub App**

Navigate to `https://app.soleur.ai/internal/github-app-init`. The page is
behind dashboard auth (middleware redirects unauth visitors to `/login`).
Click the **Create GitHub App** button.

The page submits a hidden `<input name="manifest">` POST to
`https://github.com/settings/apps/new`. GitHub renders its App-create form
with every field pre-filled from
`apps/web-platform/infra/github-app-manifest.json`.

### Step 2 — Click **Create GitHub App** on GitHub's side

Review the pre-filled values. Click GitHub's **Create GitHub App** button.
GitHub creates the App and lands on the App's settings page.

The manifest pre-fills:
- Name: `Soleur AI`
- Homepage: `https://soleur.ai`
- Description: as committed in the manifest
- Permissions: every key in the manifest's `default_permissions` (canonical
  source — see `apps/web-platform/infra/github-app-manifest.json`). The
  parity test in `apps/web-platform/test/github-app-manifest-parity.test.ts`
  locks the expected set so an in-band manifest mutation is caught at CI.
- Callback URLs: 3 entries (Flow A Supabase + custom domain + Flow B App-direct)
- Setup URL: `https://app.soleur.ai/dashboard/repos`
- Webhook URL: `https://app.soleur.ai/api/webhooks/github`
- `public: false`, `setup_on_update: true`
- Webhook secret: **NOT** pre-filled (Soleur-managed via `random_id` in
  `apps/web-platform/infra/github-app.tf` — see Step 4).

### Step 2.1 — Re-accept App installation when permissions widen

If a Soleur PR adds a new key to `default_permissions` in
`apps/web-platform/infra/github-app-manifest.json`, the founder MUST
re-accept the App installation. GitHub has no API for this — it is a
one-time UI click per installation per permission widening (operator-only
carve-out per the [operator-only canonical
list](../../../project/learnings/2026-05-15-operator-only-step-canonical-list.md),
vendor-authorization-scope class).

Symptom of a missing re-acceptance: `terraform apply` against
`apps/web-platform/infra/` fails with `403 Resource not accessible by
integration` on any endpoint the new permission gates (e.g.,
`actions/secrets/public-key` when `secrets:write` is the missing grant).

Procedure:

1. Navigate to `https://github.com/organizations/jikig-ai/settings/installations/130018654`
   (the App was reinstalled; the current installation ID is `130018654`, was
   `122213433`). Note: the #4189 fix widened `issues: read → write` — that
   single re-consent click ALSO clears the dropped-`members:read` drift (a
   manifest-LOWERED permission needs no re-grant; only manifest-RAISED
   permissions like `issues:write` surface the banner).
2. GitHub renders a "Soleur AI is requesting an update to its permissions"
   banner with a "Review request" link when any declared permission exceeds
   the installation's current grants. Click **Review request** then
   **Accept new permissions**.
3. Verify the installation now grants the new key:

   ```bash
   gh api /orgs/jikig-ai/installations \
     --jq '.installations[] | select(.app_slug=="soleur-ai") | .permissions'
   ```

   Expected: the new key is present at the listed level (e.g.,
   `"secrets": "write"`).

4. The next hourly run of `cron-github-app-drift-guard.ts` (Inngest cron
   substrate, TR9 PR-4) will re-check the installation grant against the
   committed manifest via the `installation_permission_drift` failure mode
   (#4179). Any open tracking issue labeled `ci/auth-broken` titled
   "GitHub App drift-guard..." will auto-close once the run is green
   (existing auto-close-stale logic in the handler). To force immediate
   verification instead of waiting up to an hour:
   `inngest send cron/github-app-drift-guard.manual-trigger --data '{}'`.

   To confirm auto-close fired:

   ```bash
   gh issue list --state closed --label ci/auth-broken \
     --search 'in:title "GitHub App drift-guard"' \
     --limit 1 --json number,closedAt
   ```

### Step 3 — Paste 3 identity credentials into Doppler `prd`

From the App's settings page, copy each value into Doppler. **Prefer the
CLI form** below (no leak via clipboard / no Doppler-UI surviving-secrets
table) over the Doppler UI:

```bash
# Read each value from GitHub, then for each key:
doppler secrets set GITHUB_APP_ID --silent --no-interactive \
  -p soleur -c prd <<< "$value" >/dev/null 2>&1
```

The trailing `>/dev/null 2>&1` prevents the
[Leak-2](../../../project/learnings/2026-05-18-supabase-custom-access-token-hook-discriminator.md)
hazard where Doppler echoes the new value back via the surviving-secrets
table.

#### Key mapping

| GitHub field | Doppler key (project: `soleur`, config: `prd`) |
|---|---|
| App ID | `GITHUB_APP_ID` |
| Private Key (download `.pem`; base64-encode — see below) | `GITHUB_APP_PRIVATE_KEY` |
| Webhook Secret (Soleur-managed — see Step 4) | `GITHUB_APP_WEBHOOK_SECRET` |

Note: GitHub's App settings page also surfaces `Client ID` and `Client Secret`,
but the codebase no longer reads them (PR #4150 deleted both as dead plumbing
with zero TS consumers). Skip them when copying — they're authoritative on
GitHub's side but unused in Soleur.

#### PEM base64 encode — cross-platform one-liner

`base64 -w0` is GNU coreutils; `base64 -i ... -o ...` is BSD on macOS.
Use `openssl base64 -A` to avoid the divergence:

```bash
openssl base64 -A -in app.pem -out app.pem.b64
doppler secrets set GITHUB_APP_PRIVATE_KEY --silent --no-interactive \
  -p soleur -c prd <<< "$(cat app.pem.b64)" >/dev/null 2>&1
shred -u app.pem app.pem.b64
```

### Step 4 — Wire the Soleur-managed webhook secret into GitHub

The 6th paste step. The webhook secret is generated by Terraform's
`random_id.github_webhook_secret` resource (see `apps/web-platform/infra/github-app.tf:76-87`),
NOT by GitHub. The operator must paste the Terraform-generated value INTO
GitHub's App settings page → Webhook → Secret field. Without this step,
GitHub's webhook signature header does not match what the
[webhook handler](../../../../apps/web-platform/app/api/webhooks/github/route.ts)
computes; signature verification silently fails-closed 401 on every delivery.

Two options:

**Option A — Manual paste (fallback)**:

```bash
doppler secrets get GITHUB_APP_WEBHOOK_SECRET --plain \
  -p soleur -c prd
```

Paste into GitHub: App settings → Webhook → Secret. Save.

**Option B — Automated via App-JWT** (preferred for re-provisioning loops):

The JWT mint logic is duplicated between `bin/snapshot-github-app.sh` (which
prints `GET /app` JSON) and the CI workflow (which calls the same endpoint).
Until a `bin/mint-app-jwt.sh` helper lands (deferred), the simplest path is
inline JWT mint:

```bash
# 1. Fetch the PEM and App ID:
doppler secrets get GITHUB_APP_PRIVATE_KEY --plain -p soleur -c prd \
  | base64 -d > /tmp/app.pem
chmod 600 /tmp/app.pem
APP_ID=$(doppler secrets get GITHUB_APP_ID --plain -p soleur -c prd)

# 2. Mint a 10-min App-JWT inline (the runtime handler uses
#    `createAppJwtOctokit()` at
#    apps/web-platform/server/github/probe-octokit.ts;
#    this operator-only mint mirrors that contract):
b64url() { base64 -w 0 | tr '+/' '-_' | tr -d '=\n'; }
now=$(date +%s)
header=$(printf '%s' '{"alg":"RS256","typ":"JWT"}' | b64url)
payload=$(jq -nc \
  --argjson iss "$APP_ID" \
  --argjson iat "$((now - 60))" \
  --argjson exp "$((now + 540))" \
  '{iss: $iss, iat: $iat, exp: $exp}' | b64url)
unsigned="${header}.${payload}"
signature=$(printf '%s' "$unsigned" | \
  openssl dgst -sha256 -sign /tmp/app.pem -binary | b64url)
JWT="${unsigned}.${signature}"

# 3. PATCH the App's webhook secret. Use process-substitution for the
#    Authorization header so the JWT never appears in `curl` argv:
webhook_secret=$(doppler secrets get GITHUB_APP_WEBHOOK_SECRET --plain \
  -p soleur -c prd)
curl -sS --fail \
  -X PATCH https://api.github.com/app/hook/config \
  --header @<(printf 'Authorization: Bearer %s' "$JWT") \
  -H 'Accept: application/vnd.github+json' \
  -d "$(jq -nc --arg secret "$webhook_secret" '{secret: $secret}')"

shred -u /tmp/app.pem
unset JWT webhook_secret
```

After the PATCH, Step 4 is complete without ever opening GitHub's UI a
second time. Note: `gh api -X PATCH /app/hook/config` would be simpler, but
the `gh` CLI sends `Authorization: token`, not `Bearer`, so it cannot
authenticate as an App. The inline curl is the load-bearing form.

### Step 5 — `terraform apply` against `apps/web-platform/infra/`

```bash
cd apps/web-platform/infra
terraform init
terraform apply
```

The `doppler_secret` resources have `ignore_changes = [value]` so this
apply does NOT overwrite the values pasted in Step 3 / 4. Subsequent
rotations via Doppler UI / CLI remain invisible to `terraform plan`.

## Manifest-drift discipline

When the live App's permissions or events change (e.g., GitHub adds a new
permission key, or the operator grants an additional permission via the
GitHub dashboard for any reason), the operator MUST commit a corresponding
update to `apps/web-platform/infra/github-app-manifest.json` in a
follow-up PR within ~1 hour, OR the
[drift-guard cron](../../../../apps/web-platform/server/inngest/functions/cron-github-app-drift-guard.ts)
will file a `ci/auth-broken` issue on the next hourly tick.

**Suppression window for planned changes**: when the manifest-touching PR
merges, commit `apps/web-platform/infra/MANIFEST_DRIFT_SUPPRESS_UNTIL`
containing a UTC ISO timestamp roughly 24 hours after merge. The
drift-guard step will detect drift, emit a visible `::warning::`
annotation, and SKIP `record_failure` until the timestamp passes. Delete
the file once the live App is reconciled. Malformed timestamps are
ignored (fail-loud, no silent pass).

## Snapshot the live App (for re-authoring the manifest)

After a permission change (Soleur-side OR GitHub-side rename), re-snapshot
to refresh the manifest:

```bash
doppler secrets get GITHUB_APP_PRIVATE_KEY --plain -p soleur -c prd \
  | base64 -d > /tmp/app.pem
chmod 600 /tmp/app.pem
APP_ID=$(doppler secrets get GITHUB_APP_ID --plain -p soleur -c prd)
export APP_ID
bash bin/snapshot-github-app.sh > /tmp/github-app-snapshot.json
shred -u /tmp/app.pem
```

Then diff `jq --sort-keys .permissions /tmp/github-app-snapshot.json`
against `jq --sort-keys .default_permissions apps/web-platform/infra/github-app-manifest.json`
and PR any divergence.

## What this runbook does NOT cover

- **`dev` App provisioning** — the codebase does not provision a dev App
  today. If a future `dev` App ships, this runbook's flow applies with
  `-c dev` instead of `-c prd` and `APP_DOMAIN=app.dev.soleur.ai`.
- **App rotation post-incident** — see
  [`github-app-drift.md`](./github-app-drift.md) and
  [`github-app-callback-audit.md`](./github-app-callback-audit.md).
- **Approach B (downloadable artifact callback)** — deferred to #4145.
- **Synthetic-replay attestation cron** — deferred to #4146.
