---
title: GitHub App drift-guard runbook
date: 2026-05-05
owners: engineering/ops
applies_to:
  - .github/workflows/scheduled-github-app-drift-guard.yml
  - apps/web-platform/scripts/verify-required-secrets.sh
related_issues: [3187, 3181, 2997]
related_prs: [3224]
brand_survival: single-user-incident
---

# GitHub App drift-guard runbook

Triage and rotation procedures for the hourly drift-guard at
`.github/workflows/scheduled-github-app-drift-guard.yml`. The guard
mints an RS256 JWT, calls `https://api.github.com/app`, and asserts
`response.id == GH_APP_DRIFTGUARD_APP_ID` AND
`response.client_id == OAUTH_PROBE_GITHUB_CLIENT_ID` byte-for-byte.

A failure surfaces under one of three label families — the title prefix
tells you which:

- `[ci/auth-broken] GitHub App drift-guard fired` — drift detected. The
  App backing OAuth was swapped, deleted, suspended, or its private key
  was rotated.
- `[ci/guard-broken] GitHub App drift-guard malfunctioned` — guard
  itself broke (PEM corrupt, network error, secret missing).
- `[security/leak-suspected] GitHub App drift-guard log-leak tripwire` —
  PEM-block header or JWT-shaped string was detected in the captured
  step output. Treat as a credential leak until proven otherwise.

## Bootstrap (first-time setup)

The guard depends on three secrets in Doppler `prd` and three GitHub
Actions secrets synced from them. Run this once when commissioning a
new environment.

### 1. Locate the App database ID

Two equivalent paths — pick whichever your environment supports.

**Via GitHub UI (operator):** the "App ID" displayed under
`https://github.com/organizations/jikig-ai/settings/apps/<slug>` is the
canonical numeric App database ID. It is NOT the client_id (`Iv23...`).
Both are needed; they are distinct values.

**Via `gh` CLI (operator OR agent):**

```bash
# When authenticated as a user with org-admin scope:
gh api /orgs/jikig-ai/installations \
  --jq '.installations[] | {id: .app_id, slug: .app_slug, app_db_id: .app_id}'

# Or, when already authenticated AS the App (chicken-and-egg avoided
# only when the App is partially bootstrapped — most useful for
# verifying the App ID matches what /app returns):
gh api /app
```

The `app_id` field of either response is the numeric App database ID.

### 2. Encode the PEM for transport

GitHub Actions secrets corrupt multi-line values silently — newlines in
PEM data round-trip through the secrets API as `\n` literals, producing
unparseable PEMs at decode time. Always base64-encode for transport:

```bash
# Encode (no wrap, single line):
base64 -w 0 < ./private-key.pem > ./private-key.pem.b64

# Verify the round-trip locally before storing:
base64 -d < ./private-key.pem.b64 | openssl rsa -check -noout
```

The verification step is load-bearing — if `openssl rsa -check` does
not print `RSA key ok`, the b64 file is corrupt and storing it will
trigger `pem_b64_decode_failed` or `pem_shape_invalid` at the next
hourly run.

### 3. Store in Doppler `prd`

```bash
doppler secrets set GH_APP_DRIFTGUARD_APP_ID -p soleur -c prd
# Paste the App database ID (e.g., 1234567), then Ctrl-D.

cat ./private-key.pem.b64 | doppler secrets set GH_APP_DRIFTGUARD_PRIVATE_KEY_B64 \
  --plain -p soleur -c prd
```

Verify Doppler holds them:

```bash
doppler secrets get GH_APP_DRIFTGUARD_APP_ID -p soleur -c prd --plain
doppler secrets get GH_APP_DRIFTGUARD_PRIVATE_KEY_B64 -p soleur -c prd --plain | base64 -d | head -1
# Last line should print: -----BEGIN ... PRIVATE KEY-----
```

### 4. Sync to GitHub Actions secrets

```bash
doppler secrets get GH_APP_DRIFTGUARD_APP_ID -p soleur -c prd --plain | \
  gh secret set GH_APP_DRIFTGUARD_APP_ID

doppler secrets get GH_APP_DRIFTGUARD_PRIVATE_KEY_B64 -p soleur -c prd --plain | \
  gh secret set GH_APP_DRIFTGUARD_PRIVATE_KEY_B64
```

The `OAUTH_PROBE_GITHUB_CLIENT_ID` secret is shared with the OAuth
probe and is presumed already set (see `oauth-probe-failure.md`).

### 5. Verify the live workflow

```bash
gh workflow run scheduled-github-app-drift-guard.yml
# Wait ~30s, then poll:
gh run list --workflow=scheduled-github-app-drift-guard.yml --limit 1 \
  --json databaseId,status,conclusion
```

A `conclusion: success` confirms both the JWT path and the assertion
path. A `failure` surfaces a tracking issue; follow Triage below.

## Triage

Use the failure `label` to pick a branch.

### `ci/auth-broken` — drift detected

The App backing OAuth differs from the bootstrapped sentinels. Possible
causes (most → least likely):

1. **An operator rotated the App's private key** without updating
   `GH_APP_DRIFTGUARD_PRIVATE_KEY_B64`. The /app call returns 401
   because the JWT was signed with the OLD key. **Fix:** follow the
   Rotation procedure below.
2. **The App was deleted/suspended.** GitHub returns 401. The
   user-facing OAuth flow is broken — every signup/sign-in 500s.
   **Action:** `[human-only: org owner via GitHub UI; App-suspend
   has no public REST endpoint, App-delete is unrecoverable]`
   restore the App in the GitHub UI, then re-run the guard.
3. **A new App was created and the OAuth probe's `OAUTH_PROBE_GITHUB_CLIENT_ID`
   was updated WITHOUT updating drift-guard's sentinels.** The guard's
   `id` assertion fails with `app_id_mismatch` (db ID still points to
   the old App). **Fix:** update both Doppler secrets to the new App
   AND verify the OAuth probe still passes.
4. **An attacker swapped the App.** Rare, but the guard's exact
   purpose. **Action:** treat as a security incident. Do NOT auto-roll
   the sentinels to match — investigate first. Pull `gh audit-log` for
   the org's App-management actions.

### `ci/guard-broken` — guard itself broke

The guard never reached the assertion. Common modes:

- `missing_app_id` / `missing_private_key` / `missing_expected_client_id`:
  the GitHub Actions secret is unset. Re-sync from Doppler (Bootstrap
  step 4).
- `app_id_not_numeric`: the secret stored in Doppler/GH is not a
  positive integer (e.g., the operator pasted the client_id `Iv23...`
  into the App ID slot). Replace with the App database ID.
- `pem_b64_decode_failed`: the b64 secret has whitespace, newline
  literals, or was truncated. Re-encode and re-store (Bootstrap step 2).
- `pem_shape_invalid`: the decoded value is not a valid RSA PEM
  (wrong key type, corrupt, or partial). Re-encode and re-store.
- `github_api_network`: GitHub's API was unreachable. Wait for the
  next hourly run; if it persists across two runs, check
  `https://www.githubstatus.com/`.
- `github_api_invalid_json` / `github_api_missing_fields`: GitHub
  returned an unexpected shape. File a separate issue tracking the
  upstream change before suppressing the guard.

**Important:** `ci/guard-broken` does NOT mean user-facing OAuth is
broken. Do not auto-escalate to red-paging the OAuth probe. The OAuth
probe is the user-facing source of truth; this guard is the integrity
layer beneath it. Human triage decides whether the OAuth probe also
needs to be greened.

### `security/leak-suspected` — credential exposure

The post-step grep matched `BEGIN [A-Z ]*PRIVATE KEY` or
`eyJ[A-Za-z0-9_-]{20,}` in the captured step output. **Treat as a real
leak until proven otherwise** — the false-positive rate of these
anchored patterns is near-zero in practice.

1. **Inspect the run log without re-leaking.** Both paths are
   equivalent — both go through GitHub's authenticated log API:

   ```bash
   # CLI path (agent or operator):
   gh run view <run-id> --log | \
     grep -E 'BEGIN [A-Z ]*PRIVATE KEY|LS0tLS1CRUdJTi[A-Za-z0-9+/]|eyJ[A-Za-z0-9_-]{20,}' | \
     head -n 5
   ```

   Or open the GitHub Actions UI for the same run.

   **Do NOT paste matched lines into the issue, ticket, PR body, or
   any other persistent surface** — the goal is to identify the leak
   vector, not to re-leak. Snippets in chat (e.g., for triage) are
   acceptable only if scrubbed of the actual key bytes.
2. **Identify what leaked.** Common modes:
   - PEM block: the masking step (`::add-mask::` per-line) failed,
     OR a `set -x`/`-e` was added to the drift-check step.
   - JWT segment: the `JWT=$(mint_jwt)` capture or the curl auth header
     bypassed the mask. Less common; usually means a future PR added
     `echo "$JWT"` somewhere.
3. **Rotate the GitHub App private key immediately.** Follow the
   Rotation procedure below. Do not wait for IR triage.
4. **Patch the leak vector.** Find the offending line in the workflow
   diff and add `::add-mask::` coverage or remove the echo. CODEOWNERS
   gates re-merge.
5. **Postmortem.** Document the leak class in
   `knowledge-base/project/learnings/best-practices/` so the next
   workflow author can avoid it.

GDPR Article 33 sets a 72-hour notification clock from the moment a
controller becomes "aware" of a breach. The leak tripwire is what
bounds the leak→awareness gap; if you suspend the tripwire (e.g., by
adding more `if: failure()` masking to the workflow), you extend that
gap. Don't.

## Rotation (key compromise OR routine rotation)

This section covers **private-key rotation only** — same App, new PEM.
For App-identity rotation (replacing the App entirely with a new
client_id / database ID), see **App-identity rotation** below.

Run this end-to-end without skipping steps. The order matters: revoke
on GitHub last so the new key is verified working before the old one
is decommissioned.

For shell-history hygiene during sync: run the Doppler/`gh secret set`
commands in a subshell that disables history (`bash --noprofile
--norc -c '… ; …'` or `set +o history` in your interactive shell).
Clipboard managers and session recorders (Warp's persistent session
log, asciinema, `script`) can capture stdout of intermediate pipes —
prefer process substitution (`gh secret set ... < <(doppler ...)`)
over `|` to avoid stdout buffers visible to ptrace on shared hosts.

1. **Generate new key.** `[human-only: GitHub web UI; no API endpoint
   exists for App-private-key generation]` GitHub UI → App settings →
   Private keys → "Generate a private key". Save the downloaded `.pem`
   file with mode 0600.
2. **Encode for transport.** `base64 -w 0 < new-key.pem > new-key.pem.b64`.
3. **Local round-trip check.** `base64 -d < new-key.pem.b64 | openssl rsa -check -noout`
   must print `RSA key ok`.
4. **Byte-count assertion** (defense against transport corruption):
   `[[ $(wc -c < new-key.pem.b64) -ge 2000 && $(wc -c < new-key.pem.b64) -le 4096 ]] && echo OK`.
   A 2048-bit RSA PEM in PKCS#8 is ~3000 chars when base64-encoded.
5. **Update Doppler.** `cat new-key.pem.b64 | doppler secrets set GH_APP_DRIFTGUARD_PRIVATE_KEY_B64 --plain -p soleur -c prd`.
6. **Sync to GitHub Actions.** `gh secret set GH_APP_DRIFTGUARD_PRIVATE_KEY_B64 < <(doppler secrets get GH_APP_DRIFTGUARD_PRIVATE_KEY_B64 -p soleur -c prd --plain)`.
   (Process substitution avoids the intermediate pipe stdout buffer.)
7. **Trigger the guard.** `gh workflow run scheduled-github-app-drift-guard.yml`.
8. **Verify GREEN.** `gh run list --workflow=scheduled-github-app-drift-guard.yml --limit 1 --json conclusion` must show `success`.
9. **Only now: revoke the old key on GitHub.** `[human-only: GitHub
   web UI; no DELETE /apps/{id}/keys/{key_id} REST endpoint]` App
   settings → Private keys → Delete. The window between step 1 and
   step 9 is the only time both keys are valid; keep it under 15 minutes.
10. **Securely delete local copies.** `rm -f new-key.pem new-key.pem.b64`.
    See "Cleanup model note" below for why `shred` adds nothing.

### App-identity rotation (replacing the App entirely)

If you are switching to a new GitHub App (different client_id and
database ID — not just rotating the existing App's key), the
**ordering REVERSES**. Sentinels MUST be updated AFTER the new App is
live and serving OAuth, not before.

The trap: drift-guard authenticates AS the App using its PEM. If you
update the Doppler sentinels to point at App-Y's identity ahead of
the GitHub-side OAuth switch, drift-guard mints JWTs for App-Y,
GitHub returns App-Y's metadata, and the byte-equality assertions
go GREEN — while users still hit App-X's consent screen and break
their sign-in. Up to 60 minutes of false-green coverage during which
real user sign-ins are broken.

The correct order:

1. Set up the new App on GitHub side. `[human-only: GitHub web UI]`
2. Update the OAuth-probe-side configuration (`OAUTH_PROBE_GITHUB_CLIENT_ID`)
   to point at the NEW App's client_id, deploy, and confirm the
   OAuth probe is GREEN against the new App. This proves users are
   actually landing on the new App.
3. ONLY NOW update `GH_APP_DRIFTGUARD_APP_ID` and
   `GH_APP_DRIFTGUARD_PRIVATE_KEY_B64` in Doppler `prd` and sync to
   GitHub Actions secrets via the steps above.
4. Trigger drift-guard and verify GREEN.
5. Revoke the old App on GitHub side. `[human-only: GitHub web UI]`

If you do these steps out of order, expect a `client_id_mismatch` or
`app_id_mismatch` failure routed to `ci/auth-broken` until the
sentinels are fully synchronized — the guard's design intentionally
fails LOUD on identity mismatch even if the cause is operator
sequencing, not adversarial drift.

### 401 triage (drift vs guard mis-bootstrap)

A 401 from `/app` defaults to `ci/auth-broken` (drift) but can also
mean the guard's own PEM is stale relative to GitHub-side rotation.
Disambiguation:

```bash
# If you suspect guard mis-bootstrap rather than App-side drift:
# 1. Confirm Doppler's PEM still decodes:
doppler secrets get GH_APP_DRIFTGUARD_PRIVATE_KEY_B64 -p soleur -c prd --plain | base64 -d | openssl rsa -check -noout
# 2. Confirm GitHub Actions has the latest:
gh secret list | grep GH_APP_DRIFTGUARD_PRIVATE_KEY_B64
# (the "Updated" timestamp should match your last Doppler→GH sync)
# 3. If both are current, the App was genuinely swapped/deleted/suspended.
# 4. If GH-secret-side is older than Doppler, re-run the sync (Bootstrap step 4).
```

## Cleanup model note (honest)

The workflow's "Cleanup PEM" step uses `rm -f`, not `shred -u`.
Rationale: GitHub Actions runners are ephemeral cloud VMs on
copy-on-write filesystems. `shred` overwrites on the COW *layer*, not
the underlying block — the original blocks remain readable until they
are reused. On the runner host, the storage is teardown'd at job
completion. Same reasoning applies on a developer workstation: modern
filesystems (ext4, APFS, btrfs) and SSDs make `shred` ineffective.
The honest model is "the runner disk is gone in seconds; the laptop's
journal will reuse the blocks within hours"; `shred` adds no security
and creates false confidence.

## Why this guard exists

The user-facing OAuth probe (`scheduled-oauth-probe.yml`, every 15
minutes) detects regressions at the request-level: callback URL drift,
provider-disabled, settings-misconfigured. It does NOT detect a silent
swap of the App itself — if an attacker (or a misconfigured operator)
points the GitHub App backing OAuth at a different App, every sign-in
goes to a different consent screen, but the user-facing probe still
sees a 302 to a valid GitHub authorize page.

This guard closes that gap. It runs hourly (not 15-min like the OAuth
probe) because App-database-level changes are rare; an hourly cadence
bounds the worst-case detection window at 60 minutes — well under the
GDPR 72-hour notification clock — without burning CI budget on data
that doesn't change.

### SLO

- **Detection latency target:** ≤60 minutes from the moment a drift
  occurs (App swap, key rotation out-of-band, identity mismatch) to
  the moment a `ci/auth-broken` issue is filed.
- **Alert latency target:** ≤5 minutes from issue file to ops email
  delivery (handled by the `notify-ops-email` composite action).
- **Out of scope:** GitHub Actions cron reliability itself. If GH
  Actions is degraded for >1 hour, this guard cannot fire — that
  is a "guard-itself-dark" failure mode tracked separately. See
  the follow-up issue linked from the plan's `## User-Brand Impact`
  section for cross-workflow heartbeat coverage.

## Cross-references

- `oauth-probe-failure.md` — sibling user-facing probe.
- `github-app-callback-audit.md` — App callback URL discipline.
- Learning `2026-05-05-workflow-jwt-mint-silent-failure-traps.md` —
  the three traps the workflow author must internalize.
- Learning `2026-04-18-drift-guard-self-silent-failures.md` — broader
  drift-guard self-silencing class.
- Spec `knowledge-base/project/specs/feat-3187-gh-app-drift-guard/spec.md`
- Plan `knowledge-base/project/plans/2026-05-05-feat-github-app-drift-guard-plan.md`
