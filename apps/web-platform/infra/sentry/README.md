# Sentry IaC root

Manages Sentry-hosted infrastructure for `app.soleur.ai`:

- **4 issue alerts** (auth observability stack) — imported from existing
  rules created by `apps/web-platform/scripts/configure-sentry-alerts.sh`.
- **9 cron monitors** — vendor-hosted heartbeat for the scheduled GitHub
  Actions workflows that touch secrets (closes #3236). Auto-applied on
  push-to-main via `.github/workflows/apply-sentry-infra.yml`.

ADR: [ADR-031 — Sentry alert and cron monitor configuration as IaC](../../../../knowledge-base/engineering/architecture/decisions/ADR-031-sentry-as-iac.md)

Plan: [feat-sentry-monitors-alerts-adapt-plan.md](../../../../knowledge-base/project/plans/2026-05-15-feat-sentry-monitors-alerts-adapt-plan.md)

## Authentication

Unlike the main `apps/web-platform/infra/` root (which uses Doppler `prd_terraform`
for HCloud/Cloudflare/Resend tokens), Sentry secrets live in **GitHub repository
secrets**:

- `SENTRY_AUTH_TOKEN` — auth-token for the provider (project:write scope for apply,
  project:read for plan-only).
- `SENTRY_INGEST_DOMAIN`, `SENTRY_PROJECT_ID`, `SENTRY_PUBLIC_KEY` — DSN-derived,
  consumed by the workflow check-in steps. Not read by Terraform.

R2 backend credentials (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`) come from
Doppler `prd_terraform` via `doppler secrets get --plain` — same pattern as
`scheduled-terraform-drift.yml` extracts them. See ADR-031 §secret-store-divergence.

## Local invocation

```bash
cd apps/web-platform/infra/sentry

# Auth token: personal user token from
# https://de.sentry.io/settings/account/api/auth-tokens/
# scope: project:read (for plan), project:write (for import + apply)
export SENTRY_AUTH_TOKEN=...

# R2 backend creds — same pattern as the main infra root.
export DOPPLER_TOKEN=...
eval "$(doppler secrets get AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY \
  --no-quote --plain --format env -p soleur -c prd_terraform | sed 's/^/export /')"

terraform init -input=false
terraform plan
```

## First-time import (operator step, run BEFORE `terraform apply`)

The 4 issue-alert rules already exist in Sentry — they were created by the
legacy `configure-sentry-alerts.sh` script. Import each into state matching
the rule id from the migration audit report:

```bash
# Get the rule ids from the most recent audit report:
ids=$(grep -oE '<!-- ids: \[(.*)\] -->' \
  knowledge-base/legal/audits/sentry-migration-audit-*.md | \
  tail -1 | sed -E 's/.*\[//;s/\].*//' | tr -d '"' | tr ',' ' ')
echo "Rule ids from audit: $ids"

# Map to resource names — ORDER must match issue-alerts.tf:
# auth_exchange_code_burst, auth_callback_no_code_burst,
# auth_per_user_loop, auth_signout_burst.
# Determine which id is which by name:
SENTRY_ORG=jikigai
SENTRY_PROJECT=web-platform
for id in $ids; do
  name=$(curl -fSs -H "Authorization: Bearer $SENTRY_AUTH_TOKEN" \
    "https://de.sentry.io/api/0/projects/${SENTRY_ORG}/${SENTRY_PROJECT}/rules/${id}/" | \
    jq -r .name)
  case "$name" in
    auth-exchange-code-burst)    res=auth_exchange_code_burst ;;
    auth-callback-no-code-burst) res=auth_callback_no_code_burst ;;
    auth-per-user-loop)          res=auth_per_user_loop ;;
    auth-signout-burst)          res=auth_signout_burst ;;
    *) echo "unknown rule: $name ($id)"; continue ;;
  esac
  terraform import "sentry_issue_alert.${res}" "${SENTRY_ORG}/${SENTRY_PROJECT}/${id}"
done

# Verify clean plan (modulo lifecycle-ignored v2 drift):
terraform plan
```

## Import rollback (partial-failure recovery)

If `terraform import` fails on rule N of 4, the state file holds N-1 rules.
**Do not proceed to apply.** Recover via:

```bash
for resource in sentry_issue_alert.auth_exchange_code_burst \
                sentry_issue_alert.auth_callback_no_code_burst \
                sentry_issue_alert.auth_per_user_loop \
                sentry_issue_alert.auth_signout_burst; do
  terraform state rm "$resource" 2>/dev/null || true
done
terraform state list | grep sentry_issue_alert   # expect empty
# Re-run audit (rule ids may have changed):
SENTRY_AUTH_TOKEN=... bash apps/web-platform/scripts/sentry-monitors-audit.sh
# Retry import from a clean state with the refreshed ids.
```

If 3+ retries fail, fall back to the ADR-031 escape hatch: leave
`configure-sentry-alerts.sh` as source of truth, mark ADR-031 `status: rejected`,
and revert this directory.

## Cron monitors are net-new (no import)

The 9 `sentry_cron_monitor` resources do not exist in Sentry yet. The first
`terraform apply` (or, in CI, the first run of `apply-sentry-infra.yml` after
push to main) creates them. Per-workflow grace periods (`checkin_margin_minutes`,
`max_runtime_minutes`) come from observed run durations + 2x safety margin —
re-tune via subsequent PRs after the operator has 30 days of check-in history.

## Drift detection

Existing `scheduled-terraform-drift.yml` walks `apps/web-platform/infra/`. The
matrix needs to be extended to also scan `apps/web-platform/infra/sentry/` —
tracked separately as a follow-up (NOT in scope for #3814).
