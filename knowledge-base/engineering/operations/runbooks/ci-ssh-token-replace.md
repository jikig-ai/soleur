# Runbook — `ci-ssh-token-replace`

Re-mint the `ci_ssh` Cloudflare Access service token when Cloudflare has stopped accepting it.

- **Dispatch target:** `apply-web-platform-infra.yml`, `apply_target=ci-ssh-token-replace`
- **Confirm token:** `REPLACE-CI-SSH-TOKEN`
- **Irreversible:** yes — Cloudflare will not re-issue the old secret
- **First real use:** 2026-08-01, run `30708675183` (#7095). Worked; `verdict: clean (1 verified)` — scoped to `prd_terraform`, which is the only config that run could read (see the halt-gate note below).
- **ADR:** [ADR-154](../../architecture/decisions/ADR-154-repair-the-credential-channel-not-the-host.md)

## When to fire this

Fire it when the CI-SSH credential is **measurably rejected by Cloudflare Access** — not merely when SSH is failing.

The signal that means yes:

```
CI_SSH_ACCESS_TOKEN_ID/_SECRET (HTTP 403 from ssh.soleur.ai, rejected by Access)  in  prd_terraform
```

Sources that produce it:

- The `cf-tunnel-ssh-bridge` composite fails with `::error::ci_ssh_access_denied` (any of its six call sites).
- `scheduled-terraform-drift.yml` reports `verdict: dead` and files the `action-required` + `priority/p0-critical` issue.
- `bash scripts/check-cloudflare-token-drift.sh --only CI_SSH_ACCESS_TOKEN` locally: `dead entries: 1`.

**Do NOT fire on these**, which look similar and have opposite remedies:

| Reason | Meaning | What to do instead |
|---|---|---|
| `ci_ssh_liveness_unverifiable` | The probe got no definite answer (timeout/DNS/TLS). **Nothing was measured.** | Re-run once the probe host is reachable. Re-minting a healthy credential is the #7127 failure mode. |
| `ci_ssh_liveness_unavailable` | The detector could not run, or its verdict was unreadable. | Fix the detector's preconditions. This is not a claim about the credential. |
| `connection reset by peer` with **no** drift verdict | Could be host-side, not Access. | Run the detector first and get a verdict. |

The whole point of the three-way split is that "Cloudflare rejected this" and "I learned nothing" must not share a remedy.

## Preconditions

1. **No bridge-consuming workflow in flight.** This destroys the credential their live SSH sessions authenticate with. The job takes the `web-1-swap` mutex, but check anyway:

   ```bash
   for wf in workspaces-luks-cutover.yml workspaces-luks-verify.yml git-data-cutover.yml \
             apply-deploy-pipeline-fix.yml apply-web-platform-infra.yml; do
     echo "$wf: $(gh run list --workflow=$wf --status in_progress -L 5 --json databaseId --jq 'length')"
   done
   ```

   A mid-cutover re-mint 403s the cutover's `cloudflared` on its next edge reconnect, which can leave a half-finished LUKS cutover on sole-copy user data.

2. **`DOPPLER_TOKEN_WRITE` must be usable.** The job verifies this with an authenticated round-trip *before* the irreversible apply, so a bad token aborts safely. You do not need to pre-check it.

## Fire it

```bash
gh workflow run apply-web-platform-infra.yml \
  -f apply_target=ci-ssh-token-replace \
  -f confirm=REPLACE-CI-SSH-TOKEN \
  -f reason="ci_ssh dead (403 from ssh.soleur.ai, run <RUN_ID>) — <why>"
```

All three inputs are required. `reason` is the audit trail and is echoed to the step summary.

## What it does, and what protects each step

| Step | Protection |
|---|---|
| Typo-guard | `confirm` must be exactly `REPLACE-CI-SSH-TOKEN` — deliberately distinct from every other target's token, so a string typed for a host birth cannot authorize a credential destroy |
| Verify publish channel | Authenticated Doppler round-trip **before** the destroy. A present-but-rotated write token fails here, not after |
| `terraform plan` | Two targets only (`…service_token.ci_ssh`, `…access_policy.ci_ssh_service_token`), one `-replace` |
| **Blast-radius gate** | Re-reads `terraform show -json` and refuses any address outside a 3-item allowlist — catches `module.x.hcloud_server.web`, which a prefix list would miss. Also requires the token to actually be replaced, so a `-replace` that silently did nothing fails instead of "succeeding" |
| `terraform apply` | ← the irreversible point. `create_before_destroy = true`, so the Access policy never references a nonexistent token |
| Sync to Doppler | Publishes to `prd_terraform`. **Errors** on empty outputs (unlike the routine `apply` job, which warns — there a `-target` run may legitimately skip these resources; here they are the entire point) |
| Halt gate | Asserts Access **admits** the new pair, positively (`live > 0`), with the same three-way ladder as the bridge gate |

## If it fails

**Before `Terraform apply`** — nothing changed. Read the error and fix the precondition.

**After `Terraform apply`, at the Doppler sync** — the new secret exists only in Terraform state. **Do NOT re-dispatch this arm**: that destroys a working credential to recover from a failed write. Instead re-run the publish:

```bash
gh workflow run apply-web-platform-infra.yml -f apply_target=manual-rerun -f reason="re-sync ci_ssh after a failed publish"
```

**At the halt gate with `ci_ssh_access_denied`** — the re-mint succeeded but Access still rejects the pair. This **falsifies the premise** that the credential was the fault. Stop and re-diagnose; do not re-mint again. Check whether a stale `CI_SSH_ACCESS_TOKEN_*` copy exists in a Doppler config other than `prd_terraform` — this arm publishes to `prd_terraform` only, so a sibling copy elsewhere is never cleared by re-minting.

> **Do not wait for a `dead` verdict to confirm that.** An earlier version of this step said a sibling copy "would keep the fleet-wide verdict `dead` forever", which is inverted: a scan whose credential reaches only `prd_terraform` never reads the other configs, so a stale sibling is **invisible** to it and the verdict reads `clean`. The scheduled scan is wired to run as a project-scoped Doppler service account — TARGET state, wired at merge, unobserved until the `web-platform-infra-apply` gate releases the Terraform apply that mints the credential. Until that apply runs the scan still reads one config, and after it runs the scan reads the siblings only when it says so. Treat a scheduled `clean` as scoped to `prd_terraform` unless the same run also reports `coverage: at-floor`; at `degraded` or `unknown` the credential did not reach every config the scan demanded, so check the others directly with a credential that reaches them (`doppler secrets get CI_SSH_ACCESS_TOKEN_ID -p soleur -c <cfg>`).

**At the halt gate with `unverifiable` / `unavailable`** — nothing was measured. The re-mint is **not** known to have failed and the new credential is already published. Do not re-dispatch; re-run the detector.

## After it succeeds

The credential is live, but nothing has been *delivered* to the host yet. If you are recovering a dark deploy path, continue with:

1. `apply-deploy-pipeline-fix.yml` (requires `-f reason=...`) — lands the config payload over the now-live bridge.
2. A release (`web-platform-release.yml -f bump_type=patch`) — `ci-deploy.sh` reads `/etc/default/soleur-doppler-token` at runtime, so no unit restart is needed for the deploy itself.
3. Verify by pulling `https://app.soleur.ai/health` directly: `version` ≥ expected **and** `uptime < 900` **and** `supabase == "connected"`. A green workflow run does not satisfy this — `status:"ok"` is hardcoded.

## Known residual

`vector` does not pick up a re-delivered credential: it is alive only because it holds pre-revocation secrets in memory, so it never re-execs, and no allowlisted webhook hook restarts arbitrary units. Tracked as R2 on #7103. Until that is closed, telemetry assertions that read through vector (notably "zero `Doppler Error: Invalid Auth token`") cannot distinguish "no errors" from "not shipping" — do not read silence there as an all-clear.
