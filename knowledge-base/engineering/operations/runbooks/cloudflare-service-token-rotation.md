---
category: infrastructure
tags: [cloudflare, service-token, rotation, terraform]
date: 2026-03-21
---

# Cloudflare Access Service Token Rotation

The `github-actions-deploy` service token in `apps/web-platform/infra/tunnel.tf` authenticates GitHub Actions deploys through the Cloudflare Tunnel. It expires after 8760 hours (~1 year). When expired, deploys fail with HTTP 403 from Cloudflare Access.

## Monitoring

Two layers of monitoring are in place:

1. **Terraform notification policy** (`cloudflare_notification_policy.service_token_expiry`) sends an email alert 7 days before expiry. This is the primary alert. A notification policy covers only its own account's tokens, so the Soleur account has its own copy, `cloudflare_notification_policy.service_token_expiry_soleur` (#12937).
2. **Inngest function** `event-cf-token-expiry-check` (`apps/web-platform/server/inngest/functions/event-cf-token-expiry-check.ts`) checks the Cloudflare API and creates a GitHub issue when the token is within 30 days of expiry. This is the backup. It lists tokens in Doppler `CF_ACCOUNT_ID`, which is still the legacy account, so it does not see the Soleur-account tokens until the teardown follow-up repoints it (before #12931's flip).

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

## Soleur-account tokens (#12937)

Since #12937 the tunnel's Access gate lives in the Soleur Cloudflare account that owns the `soleur.ai` zone; the reason is
[ADR-330](../../architecture/decisions/ADR-330-tunnel-and-access-gate-live-in-the-zone-owning-account.md). The legacy-account tokens
stay until the teardown follow-up, but no hostname routes to them. Ref #12937.

**Deploy pair (minted outside Terraform).** Mint and delete it in the account `local.cf_soleur_account_id` names in
`apps/web-platform/infra/tunnel.tf`, never in Doppler `CF_ACCOUNT_ID` (still the legacy account): `POST` and `DELETE`
`/accounts/<that id>/access/service_tokens[/<id>]`, with Doppler `soleur/prd_terraform` `CF_API_TOKEN` (it needs Access: Service Tokens Edit on that account) passed as the bearer through `curl --config -`. The procedure above still applies, with two changes. The admitted id list is
`local.deploy_service_token_ids_soleur` in `apps/web-platform/infra/tunnel.tf`, not `local.deploy_service_token_ids`, which now only
admits the legacy app. Step 3 writes the pair to every copy below from one in-memory value, in one script run, with the values on stdin:

| Copy | Names | How it is checked |
|---|---|---|
| GitHub repo secrets, written with the infra GitHub App installation token (never a PAT) | `CF_ACCESS_CLIENT_ID`, `CF_ACCESS_CLIENT_SECRET` | Cannot be read back. The deploy arm's `deploy.soleur.ai/hooks/deploy-status` call passing Access proves it |
| Doppler `soleur-infra-privileged/prd` | `CF_ACCESS_CLIENT_ID`, `CF_ACCESS_CLIENT_SECRET` | sha256 equal to the minted value (never printed) |
| Doppler `soleur/prd_terraform` (the TF var source for the `server.tf` `push-infra-config.sh` local-exec) | `CF_ACCESS_CLIENT_ID`, `CF_ACCESS_CLIENT_SECRET` | sha256 equal to the minted value (never printed) |

**`registry_push_soleur` (Terraform-managed).** Rotate it by bumping `client_secret_version` on
`cloudflare_zero_trust_access_service_token.registry_push_soleur` in a PR. The merge apply rotates the secret in place, and
`doppler_secret.registry_push_access_token_{id,secret}` carry no `ignore_changes`, so the same apply writes the new pair to Doppler
`soleur/prd`. After the apply, compare the Doppler value's sha256 with the state value's, then run
`doppler run -p soleur -c prd_terraform -- bash scripts/check-cloudflare-token-drift.sh` and expect `REGISTRY_PUSH_ACCESS_TOKEN` LIVE
in every config. Do not rotate it through Cloudflare's `/rotate` endpoint: state keeps the old secret and the next apply writes it back to
Doppler. Do not adopt a `_soleur` token with `import {}`: an imported token reads its secret empty, so the apply would publish an empty
value.

**`ci_ssh_soleur` (Terraform-managed).** Rotation stays the `apply_target=ci-ssh-token-replace` dispatch of
`apply-web-platform-infra.yml`, repointed at the `_soleur` addresses by #12937. The pair reaches Doppler `soleur/prd_terraform` through
the apply's CI-SSH sync step, which fails when this run creates the token but its outputs are empty.

## Verification

After any rotation method, trigger a test deploy:

```bash
gh workflow run web-platform-release.yml
```

Confirm the deploy step completes with HTTP 200 (not 403).

## Key Details

- **Token name:** `github-actions-deploy`
- **Resource:** none (forgotten from Terraform state by #9294; the token itself lives in Cloudflare)
- **Admitted ids:** `local.deploy_service_token_ids_soleur` (Soleur account, live) and `local.deploy_service_token_ids` (legacy account, unrouted) in `apps/web-platform/infra/tunnel.tf`
- **Secrets:** Doppler `soleur-infra-privileged/prd` `CF_ACCESS_CLIENT_ID` / `CF_ACCESS_CLIENT_SECRET` (the Tier-A and repo-secret copies are deleted in a later owner-named step). Corrected 2026-11-19 (#12937): those copies are still read, by the GitHub repo secrets and Doppler `soleur/prd_terraform`, so every copy is in the table under "Soleur-account tokens (#12937)"
- **Default lifetime:** 8760h (~1 year)
- **Created:** 2026-03-21
- **Expected expiry:** ~2027-03-21
- **Parent issue:** #974; **re-homed by:** #9294
- **Originating PR:** #963 (token); server-side provisioning #971 / #967

## Related: CLA Evidence R2 token rotation

The CLA evidence sidecar uses a separate Doppler config (`prd_cla`) and surfaces an R2 object-write API token to GitHub Actions via `DOPPLER_TOKEN_CLA`. Rotation of that token follows the Cloudflare R2 token rotation procedure (regenerate via Cloudflare dashboard or `terraform apply` against `apps/cla-evidence/infra/`, sync to Doppler `prd_cla`, no GitHub-secret edit required because the workflow reads via Doppler at run-time).

For end-to-end retrieval and inspection of the evidence layer (and the GDPR Art. 17 admin-override + tombstone protocol), see `cla-signature-evidence-retrieval.md`.
