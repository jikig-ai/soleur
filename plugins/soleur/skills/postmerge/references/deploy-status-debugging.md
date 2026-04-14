# Deploy Status Debugging

When the release workflow's deploy step fails or times out, query `/hooks/deploy-status` to get the structured exit reason from ci-deploy.sh.

## Call Pattern

1. Fetch credentials from Doppler `prd_terraform`:

   ```bash
   WEBHOOK_SECRET=$(doppler secrets get WEBHOOK_DEPLOY_SECRET --project soleur --config prd_terraform --plain)
   CF_ACCESS_CLIENT_ID=$(doppler secrets get CF_ACCESS_CLIENT_ID --project soleur --config prd_terraform --plain)
   CF_ACCESS_CLIENT_SECRET=$(doppler secrets get CF_ACCESS_CLIENT_SECRET --project soleur --config prd_terraform --plain)
   ```

2. Sign and GET (read-only endpoint; HMAC is computed over the empty body):

   ```bash
   SIGNATURE=$(printf '' | openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" | sed 's/.*= //')
   curl -sf -X GET \
     -H "X-Signature-256: sha256=$SIGNATURE" \
     -H "CF-Access-Client-Id: $CF_ACCESS_CLIENT_ID" \
     -H "CF-Access-Client-Secret: $CF_ACCESS_CLIENT_SECRET" \
     https://deploy.soleur.ai/hooks/deploy-status
   ```

## Reason Taxonomy

| reason | exit_code | Meaning | Remediation |
|---|---|---|---|
| `ok` | 0 | Deploy succeeded | None |
| `running` | -1 | ci-deploy.sh is in progress | Poll again |
| `no_prior_deploy` | -2 | State file missing (fresh server) | Trigger deploy |
| `insufficient_disk_space` | 1 | Less than 5GB free on server | Run disk-monitor, consider pruning docker images earlier |
| `lock_contention` | 1 | Another ci-deploy.sh holds flock | Wait for prior run to finish; if stuck >10min, SSH to kill |
| `doppler_unavailable` | 1 | doppler binary missing on server | Re-run terraform apply to reprovision |
| `doppler_token_missing` | 1 | DOPPLER_TOKEN env var not set | Check `/etc/default/webhook-deploy` on server |
| `doppler_fetch_failed` | 1 | Transient Doppler API failure | Retry deploy |
| `command_missing` | 1 | Empty SSH_ORIGINAL_COMMAND | Check webhook -> ssh trigger wiring |
| `command_malformed` | 1 | Wrong arg count | Check CI payload shape |
| `action_unknown` | 1 | Unknown action verb in command | Fix CI workflow |
| `component_unknown` | 1 | Unknown component name | Check ALLOWED_COMPONENTS allowlist |
| `image_mismatch` | 1 | Image doesn't match component | Check ALLOWED_IMAGES mapping |
| `tag_malformed` | 1 | Tag doesn't match semver | Check CI tag format |
| `canary_sandbox_failed` | 1 | bwrap verification failed on canary | SSH -> `journalctl -u webhook` for bwrap stderr |
| `canary_failed` | 1 | Canary health-check failed 10x | Roll back; inspect canary container logs |
| `production_start_failed` | 1 | Production container didn't start post-swap | Check docker state; consider manual rollback |
| `no_handler` | 1 | Component has no case handler in ci-deploy.sh | Add handler (code change) |
| `unhandled` | 1 | EXIT trap fired; specific reason not instrumented | Check journalctl; consider adding explicit final_write_state call |
| `corrupt_state` | -3 | State file is unparseable JSON | Server-side disk issue; SSH to investigate |

## When NOT to SSH

Per AGENTS.md: SSH is for infrastructure provisioning (Terraform) only, never for logs. Use `/hooks/deploy-status` + Sentry API + Better Stack as the three observability layers. SSH is read-only last-resort diagnosis for `canary_sandbox_failed` only (bwrap capability errors live in journalctl).
