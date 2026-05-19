---
name: doppler-env-hot-reload-limitation
description: Doppler env values are baked into the prd container at start time via --env-file; flipping a flag in Doppler does not affect a running container until redeploy. Two-step op: set in Doppler, then redeploy.
metadata:
  type: learning
  category: integration-issues
  module: infra
  surfaced_date: 2026-05-19
  surfaced_during: PR-G POST-4→POST-5 flow (umbrella #3244)
---

# Learning: Doppler env values are baked at container start — flag flips need a redeploy

## Problem

POST-4 set `SOLEUR_FR5_ENABLED=true` in Doppler `prd`. POST-5 was about to fire a synthetic Stripe smoke against the running container to confirm the FR5 deny-by-default predicate at [app/api/webhooks/stripe/route.ts:437](../../../apps/web-platform/app/api/webhooks/stripe/route.ts) actually fired in prod. The smoke would have proven nothing: the predicate reads `process.env.SOLEUR_FR5_ENABLED`, but the env was baked into the running container's environment at `docker run` time. Flipping the value in Doppler did not propagate.

## Root Cause

`apps/web-platform/infra/cloud-init.yml` materialises env at container start:

```bash
doppler secrets download --no-file --format docker --project soleur --config prd > "$TMPENV"
docker run --env-file "$TMPENV" ...
```

`--env-file` is a one-shot snapshot. The container's `/proc/<pid>/environ` is frozen at exec time. There is no daemon, watcher, or sidecar pulling fresh Doppler values into the running process — Doppler's CLI is invoked exactly once per container lifecycle.

This is distinct from [2026-03-19-docker-restart-does-not-apply-new-images.md](2026-03-19-docker-restart-does-not-apply-new-images.md): that learning covers swapping the image tag; this one covers same-image, changed-env. Both require a fresh `docker run`.

## Solution

Trigger the deploy webhook to redeploy the **current image tag** so cloud-init re-runs `doppler secrets download` and starts a new container with the updated env:

```bash
doppler run -p soleur -c prd_terraform -- bash -c '
  TS=$(date -u +%s)
  BODY=""
  SIG=$(printf "%s" "$BODY" | openssl dgst -sha256 -hmac "$WEBHOOK_DEPLOY_SECRET" -hex | awk "{print \$2}")
  curl -sS -X POST https://deploy.soleur.ai/hooks/deploy \
    -H "CF-Access-Client-Id: $CF_ACCESS_CLIENT_ID" \
    -H "CF-Access-Client-Secret: $CF_ACCESS_CLIENT_SECRET" \
    -H "X-Soleur-Timestamp: $TS" \
    -H "X-Soleur-Signature: sha256=$SIG" \
    -H "Content-Type: application/json" \
    -d "$BODY"
'
```

Verified during PR-G POST-4 → POST-5:
- POST-4 (Doppler flip): 10:39:58Z
- Redeploy fired: 12:58:48Z
- POST-5 smoke confirmed FR5 predicate firing: 13:05:33Z

Once the new container is up, `process.env.SOLEUR_FR5_ENABLED` reads the fresh value.

## Key Insight

**Any Doppler flag flip on prd is a two-step operation.** Setting the value in Doppler is necessary but not sufficient — without a redeploy, the running container continues to see the pre-flip value. The 1h POST-X gate windows that assume "set and then verify within an hour" must account for the redeploy step before verification.

This applies to any infra where env is materialised at process start: `docker run --env-file`, k8s pod spec `env:` blocks, systemd `EnvironmentFile=`, PM2 ecosystem files. It does NOT apply to runtime-fetched secrets (Doppler SDK in-process, Vault Agent sidecar, AWS SSM parameter fetch on read) — those pick up changes without a process restart.

## Prevention

- Treat any `SOLEUR_*` flag flip in Doppler as a two-step PR/runbook step: `(1) doppler secrets set ...; (2) trigger deploy webhook`.
- POST-X gate runbooks that gate on a Doppler flag MUST include the redeploy step explicitly between the flip and the verification smoke.
- If a future capability needs runtime hot-reload of feature flags, route through the Doppler SDK (in-process fetch) rather than `--env-file`, or front the flag with a runtime store (Postgres row, ConfigCat, LaunchDarkly). Do not retrofit `--env-file`-based env to be "watched."

## Session Errors

This learning was surfaced as a *gap* during the PR-G POST gate sequence — not a direct error. Other session errors documented for completeness:

1. **Wrong initial diagnosis of PR-G all-35-auth-tests-fail** — Recovery: read [apps/web-platform/e2e/mock-supabase.ts](../../../apps/web-platform/e2e/mock-supabase.ts) and compared hardcoded `tc_accepted_version: "1.0.0"` against [apps/web-platform/lib/legal/tc-version.ts](../../../apps/web-platform/lib/legal/tc-version.ts) `TC_VERSION = "2.0.0"`. Fixed in commit 8f617bae by importing TC_VERSION into the mock. Prevention: when ALL N tests in a shared project fail identically, look at shared setup (mock-supabase.ts, globalSetup, fixtures) before triaging individual test bodies. Add a Sharp Edge to the e2e debugging runbook.

2. **Manual dashboard instructions in prose without Playwright-first attempt** (user flagged) — Recovery: pivoted to Playwright MCP, navigated to Supabase auth-rate-limits page, bumped token verifications + sign-ups from 30→150/5min directly. Prevention: already covered by `hr-exhaust-all-automated-options-before` and `hr-never-label-any-step-as-manual-without`. Reinforced by Phase 1.5 Deviation Analyst's "manual browser steps in prose output" scan — no new rule needed; user-facing handoff text MUST treat MCP attempts as the default.

3. **Runbook PR #4037 had wrong Supabase setting names** ("Rate limit for sending magic links" — that's SMTP, not the verifyOtp ceiling) — Recovery: Playwright MCP inspection of the actual auth-rate-limits page revealed correct names; PR #4040 corrected the runbook. Prevention: when documenting external-vendor dashboard settings, verify setting names via Playwright snapshot of the live UI before writing prose — do not infer from product-area names.

4. **Supabase MCP `authenticate` returned `{"message":"Invalid URL"}`** — Recovery: pivoted to Playwright MCP for the dashboard interaction. Prevention: file an issue against the Supabase MCP integration if this is reproducible; treat MCP OAuth failures as "try Playwright MCP next" not "ask the user to do it manually."

5. **cla-evidence check transient ETIMEDOUT** during Doppler CLI setup — Recovery: rerun cleared. Prevention: none warranted (transient network).

6. **PR #4050 enforce check failure: `fatal: origin/main...HEAD: no merge base`** from shallow checkout + advancing main — Recovery: merged main into branch (3293a95b). Prevention: covered by existing CI patterns; merge-main-into-branch is the documented recovery.

7. **Auto-close of #3947 despite `Ref #3947`** (not `Closes`) in PR body — Recovery: documented in [knowledge-base/legal/compliance-posture.md](../../legal/compliance-posture.md). Prevention: this is GitHub's intended behavior when the PR title or body uses any close-keyword variant; covered by `wg-use-closes-n-in-pr-body-not-title-to`.

## Related

- [2026-03-19-docker-restart-does-not-apply-new-images.md](2026-03-19-docker-restart-does-not-apply-new-images.md) — orthogonal case (same env, different image)
- [2026-03-20-doppler-secrets-manager-setup-patterns.md](2026-03-20-doppler-secrets-manager-setup-patterns.md) — baseline Doppler patterns
- [2026-03-25-doppler-secret-audit-before-creation.md](2026-03-25-doppler-secret-audit-before-creation.md)
- [2026-03-21-async-webhook-deploy-cloudflare-timeout.md](2026-03-21-async-webhook-deploy-cloudflare-timeout.md) — deploy webhook semantics
- `apps/web-platform/infra/cloud-init.yml` — the `--env-file` site
- `plugins/soleur/skills/postmerge/references/deploy-status-debugging.md` — deploy webhook runbook
- Umbrella issue: [#3244](https://github.com/jikigai-ai/soleur/issues/3244)
- Compliance posture record: [knowledge-base/legal/compliance-posture.md](../../legal/compliance-posture.md) (PR #4050)

## Tags

category: integration-issues
module: infra/doppler
module: infra/deploy
