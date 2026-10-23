---
category: infrastructure
tags: [cloudflare, service-token, rotation, terraform]
date: 2026-03-21
---

# Cloudflare Access Service Token Rotation

The `github-actions-deploy` service token in `apps/web-platform/infra/tunnel.tf` authenticates GitHub Actions deploys through the Cloudflare Tunnel. It expires after 8760 hours (~1 year). When expired, deploys fail with HTTP 403 from Cloudflare Access.

## Monitoring

Two layers of monitoring are in place:

1. **Terraform notification policy** (`cloudflare_notification_policy.service_token_expiry`) sends an email alert 7 days before expiry. This is the primary alert.
2. **GitHub Actions workflow** (`scheduled-cf-token-expiry-check.yml`) checks the Cloudflare API and creates a GitHub issue when the token is within 30 days of expiry. This is the backup.

## Rotation Procedures

> **#9294 / ADR-241 D10 — the token is no longer a Terraform resource.** `cloudflare_zero_trust_access_service_token.deploy`
> was forgotten from state (`removed { destroy = false }`) so its `client_secret` leaves the Tier-A-readable state, and the
> two root outputs that carried the pair are deleted. The older procedures that edited the resource (`duration`,
> `client_secret_version`) or ran `terraform apply -replace=...service_token.deploy` and piped `terraform output -raw
> access_service_token_client_*` into `gh secret set` NO LONGER APPLY and are removed: re-declaring the resource mints a
> brand-new token whose secret is in no Doppler project, and `-replace` of it is forbidden (tests/scripts/test-deploy-access-token-forget.sh
> pins both). Rotation is the two-PR sequence below. Each step is OWNER-NAMED: an agent runs a step only after the owner names
> the exact command; a menu answer is not authorization. Full chain and rationale: the archived plan
> `knowledge-base/project/plans/archive/20261019-163644-2026-10-15-feat-g1-webhook-trio-tier-b-plan.md`, §Owner-named command chain.

Where the pair lives: Doppler `soleur-infra-privileged/prd` (`CF_ACCESS_CLIENT_ID`, `CF_ACCESS_CLIENT_SECRET`), exported to every Tier-B job
by the loader (`.github/actions/infra-credentials`). The token's id (not secret) is the committed constant
`local.deploy_service_token_ids` in `apps/web-platform/infra/tunnel.tf`; the deploy application's policy admits exactly those ids.

1. **Mint** a new Access service token in Cloudflare, outside Terraform. Keep its id (a UUID); write the client id and secret straight into
   `soleur-infra-privileged/prd` without printing them. Do not delete the old token yet.
2. **PR-A — admit both.** Add the new id to `local.deploy_service_token_ids` (old and new, in one list). The apply changes the policy in
   place, so the merge commit message carries a line containing exactly `[ack-deploy-policy]` (`[ack-destroy]` does not count). The
   web-platform apply's deploy-policy gate (`tests/scripts/lib/deploy-policy-gate.sh`) refuses any other policy change.
3. **Switch the secrets.** Update both Tier-B copies (the privileged project and, once it exists, the narrow deploy-channel project) and verify
   them hash-equal. Then canary through the deploy path (a `mode=redeploy` dispatch of `git-data-cutover.yml` is its own named command).
4. **PR-B — drop the old id.** Remove the old id from the list, again with `[ack-deploy-policy]`, then delete the old token in Cloudflare.
5. **Probe.** The old pair must now be denied at Access (HTTP 403) and the new pair must deploy.

Standing hazards: never `-replace` or `destroy` the token, and never re-declare it; the deleted outputs may still sit in state after the
targeted apply (the apply job warns when they do — treat the old token as exposed and rotate it first).

## Verification

After any rotation method, trigger a test deploy:

```bash
gh workflow run web-platform-release.yml
```

Confirm the deploy step completes with HTTP 200 (not 403).

## Key Details

- **Token name:** `github-actions-deploy`
- **Resource:** none (forgotten from Terraform state by #9294; the token itself lives in Cloudflare)
- **Admitted ids:** `local.deploy_service_token_ids` in `apps/web-platform/infra/tunnel.tf`
- **Secrets:** Doppler `soleur-infra-privileged/prd` `CF_ACCESS_CLIENT_ID` / `CF_ACCESS_CLIENT_SECRET` (the Tier-A and repo-secret copies are deleted in a later owner-named step)
- **Default lifetime:** 8760h (~1 year)
- **Created:** 2026-03-21
- **Expected expiry:** ~2027-03-21
- **Parent issue:** #974; **re-homed by:** #9294
- **Originating PR:** #971 / #967

## Related: CLA Evidence R2 token rotation

The CLA evidence sidecar uses a separate Doppler config (`prd_cla`) and surfaces an R2 object-write API token to GitHub Actions via `DOPPLER_TOKEN_CLA`. Rotation of that token follows the Cloudflare R2 token rotation procedure (regenerate via Cloudflare dashboard or `terraform apply` against `apps/cla-evidence/infra/`, sync to Doppler `prd_cla`, no GitHub-secret edit required because the workflow reads via Doppler at run-time).

For end-to-end retrieval and inspection of the evidence layer (and the GDPR Art. 17 admin-override + tombstone protocol), see `cla-signature-evidence-retrieval.md`.
