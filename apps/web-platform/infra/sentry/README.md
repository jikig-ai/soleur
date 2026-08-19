# Sentry IaC root

Manages Sentry-hosted infrastructure for `app.soleur.ai`:

- **23 issue alerts** — a mix of import-only auth/observability rules (mirrored
  from rules created by `apps/web-platform/scripts/configure-sentry-alerts.sh`)
  and **apply-created** rules that terraform fully owns from real
  `conditions_v2`/`filters_v2`/`actions_v2`. The apply-created set includes the
  BYOK-delegations rules (`byok-art-33-breach`, `byok-cap-exceeded`, #4364).
  `byok-art-33-breach` uses `action_match = "any"` over three event-lifecycle
  conditions (`first_seen_event` + `reappeared_event` + `regression_event`) so a
  recurring cross-tenant breach re-pages and re-starts the Art. 33 72h clock
  (#4656 item 1 — the only rule here using `"any"`). After every apply,
  `apply-sentry-infra.yml` runs a read-only `assert-byok-rules-exist.sh` liveness
  check asserting both BYOK rules still exist by name (#4656 item 5).
- **50 cron monitors** — vendor-hosted heartbeat for the scheduled GitHub
  Actions workflows that touch secrets (closes #3236). Auto-applied on
  push-to-main via `.github/workflows/apply-sentry-infra.yml`. A monitor for
  `scheduled-cf-token-expiry-check` is deferred until that workflow's
  `schedule:` block is re-enabled (currently manual-dispatch only).
- **4 uptime monitors** — vendor-hosted HTTP checks, auto-applied on the same
  push-to-main path.

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

# All three creds live in Doppler prd_terraform — no personal-token mint needed.
# The provider reads SENTRY_AUTH_TOKEN; source it from the IaC token that CI uses
# (SENTRY_IAC_AUTH_TOKEN). Export each individually — `doppler secrets get` on the
# installed CLI does NOT support the `--no-quote`/`--format env` combo.
export SENTRY_AUTH_TOKEN="$(doppler secrets get SENTRY_IAC_AUTH_TOKEN --plain -p soleur -c prd_terraform)"
export AWS_ACCESS_KEY_ID="$(doppler secrets get AWS_ACCESS_KEY_ID --plain -p soleur -c prd_terraform)"
export AWS_SECRET_ACCESS_KEY="$(doppler secrets get AWS_SECRET_ACCESS_KEY --plain -p soleur -c prd_terraform)"

terraform init -input=false
terraform plan
```

## First-time import — COMPLETE, runbook retired (#7590)

First-time adoption of the issue-alert rules is done: this root declares 29
`sentry_issue_alert` resources and plans clean against the full root. The
step-by-step import runbook that stood here was retired for two reasons, both
of which made it actively misleading rather than merely obsolete:

1. It was stale by 25 resources — it described importing "the 4 issue-alert
   rules" created by the legacy `configure-sentry-alerts.sh`.
2. It extracted rule ids from an `<!-- ids: ... -->` manifest that the audit
   script no longer emits. Sentry removed the project-scoped rules API the
   manifest was built from, and its replacement (`organizations/{org}/workflows/`)
   uses a DISJOINT identifier space — so a manifest repointed at the new
   endpoint would have kept its name and shape while silently changing
   meaning.

If a future rule ever does need adopting, read its id from the Sentry API or
from the Terraform provider directly, not from an audit report:

```bash
doppler run --project soleur --config prd --command '
  curl -s -H "Authorization: Bearer $SENTRY_IAC_AUTH_TOKEN" \
    "https://${SENTRY_API_HOST}/api/0/organizations/${SENTRY_ORG}/workflows/" \
  | jq -r ".[] | \"\(.id)\t\(.name)\""'
```

Note `SENTRY_IAC_AUTH_TOKEN`, not `SENTRY_AUTH_TOKEN`: Doppler `prd` holds
both, they are different credentials, and CI feeds the former into an env var
named after the latter.

## Cron monitors are net-new (no import)

The 8 `sentry_cron_monitor` resources do not exist in Sentry yet. The first
`terraform apply` (or, in CI, the first run of `apply-sentry-infra.yml` after
push to main) creates them. Per-workflow grace periods (`checkin_margin_minutes`,
`max_runtime_minutes`) come from observed run durations + 2x safety margin —
re-tune via subsequent PRs after the operator has 30 days of check-in history.

## Drift detection

Existing `scheduled-terraform-drift.yml` walks `apps/web-platform/infra/`. The
matrix needs to be extended to also scan `apps/web-platform/infra/sentry/` —
tracked separately as a follow-up (NOT in scope for #3814).
