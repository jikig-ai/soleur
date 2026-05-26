---
title: "feat: adapt Sentry integration to Monitors/Alerts split"
date: 2026-05-15
feature: sentry-monitors-alerts-adapt
status: draft
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
brainstorm: knowledge-base/project/brainstorms/2026-05-15-sentry-monitors-alerts-adaptation-brainstorm.md
spec: knowledge-base/project/specs/feat-sentry-monitors-alerts-adapt/spec.md
related_issues: [3814, 3815]
pr: 3811
---

# feat: Adapt Sentry integration to Monitors/Alerts split

## Overview

Sentry split "Alerts" into **Monitors** (detection, including the new Crons + Uptime tabs) and **Alerts** (routing only) in 2026. Vendor says "no action required" but Soleur cannot accept that: (a) auto-migration may have orphaned a Metric Alert from its paired routing rule — single missed page on production auth burst breaches the brand-survival threshold; (b) new monitor classes (log-condition, custom-metric) push past the current Article 30 §(c) inventory; (c) scheduled GitHub Actions workflows currently have zero "did this run?" detection.

This plan adopts the split deliberately, in one PR covering: migration audit (one-shot script with retained snapshot), legal corpus update (8 files with explicit "log ingestion NOT enabled" carve-out), Sentry Crons HTTP check-ins for a scoped subset of scheduled workflows, and Terraform onramp using the `jianyuan/sentry` provider with imported existing rules. The `configure-sentry-alerts.sh` deprecation is deferred to a follow-up PR after one release cycle (#TBD created at merge).

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality (verified) | Plan response |
|---|---|---|
| Terraform provider is `getsentry/sentry` | `getsentry/terraform-provider-sentry` is a stale fork (last push 2024-06-24). Canonical provider is `jianyuan/terraform-provider-sentry` v0.15.0-beta2 (2026-05-06, beta). | Use `jianyuan/sentry` source. **Document beta status** as an Open Question/Risk; consider pinning to v0.15.0-beta2 with a re-evaluation note. |
| Resource is `sentry_monitor` | Resource is `sentry_cron_monitor`. Also: `sentry_metric_monitor` replaces deprecated `sentry_metric_alert`; new beta unified `sentry_alert` binds monitors to actions. `sentry_issue_alert` still available. | Use `sentry_cron_monitor` for FR2 Crons. For the 4 existing issue-alert rules, import as `sentry_issue_alert` (still supported), defer migration to `sentry_alert` until v0.15 stabilizes. |
| New Terraform root at `terraform/sentry/` | Existing pattern is `apps/web-platform/infra/` (single root per app). R2 backend with locking disabled. | New root at **`apps/web-platform/infra/sentry/`** sibling to the main infra root. Same R2 backend, distinct key `web-platform/sentry/terraform.tfstate`. |
| `SENTRY_AUTH_TOKEN` flows through Doppler | Sentry secrets are **GitHub repository secrets**, not Doppler. Doppler is used for app-level secrets via `prd_terraform` config. | Keep Sentry secrets in GitHub repo secrets (no Doppler migration in this PR). Terraform reads them via env vars in CI. Note this divergence from spec TR2 in the ADR. |
| Audit script home: `plugins/soleur/skills/preflight/scripts/` | Style match for one-shot Sentry API enumerator is `apps/web-platform/scripts/configure-sentry-alerts.sh` (bash + curl + jq, 176 lines, env-var-driven). preflight is a skill, not a script repo. | Audit script at **`apps/web-platform/scripts/sentry-monitors-audit.sh`** + `.test.sh` sibling. Resolves spec OQ3. |
| Legal corpus = 4 files | 5 in spec + **Eleventy mirrors at `plugins/soleur/docs/pages/legal/`** for DPD, Privacy Policy, GDPR Policy → 8 files total. Per `2026-03-18-dpd-processor-table-dual-file-sync.md`, source + mirror must update in the same PR. | Phase 3 enumerates all 8 files explicitly. AC adds dual-file sync grep. |
| Scheduled workflows: digest + triage | **35** scheduled workflows present. Cron monitors for ALL is over-scope; for the 2 named is under-scope. | Phase 4 explicitly scopes to **9 workflows** (union: 4 #3236-named + 5 plan-named, all silent-failure-class). Other 26 stay un-monitored; tracking issue for future expansion. |
| `Sentry.checkIn()` SDK call | No Soleur workflow currently uses Sentry SDK. Crons HTTP API is the portable form (curl-based, DSN-derived endpoint). | Phase 4 uses **HTTP check-in form** (not SDK). Two-call pattern (`in_progress` + `ok|error`) for runtime detection. |
| Sentry alert idempotency by name | `2026-04-29-supabase-auth-probe-and-sentry-rule-api-quirks.md`: **two rules can share a name** — match-by-name idempotency picks arbitrarily. | Idempotency in audit script + Terraform import must match by **id**, never by name. Encode in AC. |
| Article 30 register Last Updated form | Uses **YAML `last_reviewed: 2026-05-13`** in frontmatter, not body. DPD/PP/GDPR use `**Last Updated:** May DD, 2026 (changelog note)` body form. | Phase 3 enumerates the two distinct date-update forms; AC9 uses two separate grep assertions. |

## User-Brand Impact

**If this lands broken, the user experiences:** a silent paging gap on production auth bursts (Sentry's auto-migration orphaned a Metric Alert from its routing rule; the operator never knows). Operator's only signal is a downstream user-reported symptom — at which point the brand-survival threshold has already breached.

**If this leaks, the user's authentication telemetry is exposed via:** Sentry payloads that crossed the scrub boundary because a new monitor type (log-condition or custom-metric) was enabled before `apps/web-platform/server/sentry-scrub.ts` was extended to cover its event channel. The plan explicitly forbids enabling those monitor types in this PR; Phase 6 GDPR-gate enforces.

**Brand-survival threshold:** `single-user incident`. A single missed page on a production auth burst, or a single PII-leaking log channel, breaches the threshold.

**CPO sign-off required at plan time** (carry-forward from brainstorm: CPO assessed and consented to the audit + Terraform + crons scope, deferred productization). `user-impact-reviewer` agent must run at PR review (handled by `plugins/soleur/skills/review/SKILL.md` conditional-agent block).

## Goals

- **G1.** Verify Sentry's auto-migration left every Metric Alert with a paired routing rule. Snapshot retained as Article 30 evidence at `knowledge-base/legal/audits/2026-05-15-sentry-migration-audit.md`.
- **G2.** Update the legal corpus (8 files) with explicit "we do not enable Sentry log ingestion" carve-out — present in source AND Eleventy mirror.
- **G3.** Wire Sentry Crons HTTP check-ins to 9 scoped scheduled GitHub Actions workflows (folds in #3236).
- **G4.** Migrate the 4 existing auth issue-alert rules to Terraform via `terraform import` (preserves dashboard-keyed `name` strings byte-for-byte).
- **G5.** Land ADR-031 documenting the Terraform onramp decision per `hr-every-new-terraform-root-must-include-an`.
- **G6.** Pass `/soleur:gdpr-gate` on the implementation diff with zero changes to `sentry-scrub.ts` or `sentry.client.config.ts` scrub logic.

## Non-Goals

(Inherited from spec NG1-NG8.) Additions surfaced during plan research:
- **NG9.** Migrating from `sentry_issue_alert` to the new beta `sentry_alert` unified resource. Defer until provider GA.
- **NG10.** Moving Sentry secrets from GitHub repository secrets to Doppler `prd_terraform`. Existing repo-secrets pattern is preserved.
- **NG11.** Wiring Crons check-ins on all 35 scheduled workflows. Scoped to 9 in Phase 4; remaining 26 tracked separately.
- **NG12.** Adding `sentry_uptime_monitor` resources. Soleur has no public uptime probes today; out of scope.

## Implementation Phases

### Phase 0: Preconditions & verification greps

Every claim the plan rests on must be verified before code lands. This phase has no code — it produces verified outputs.

0.1. **Verify `jianyuan/terraform-provider-sentry` v0.15.0-beta2 is current and importable.**
```bash
gh api repos/jianyuan/terraform-provider-sentry/releases/latest --jq '.tag_name'
```
Expected: `v0.15.0-beta2` or later. Record the SHA pin for the provider in `apps/web-platform/infra/sentry/versions.tf`. **If PR sits open >2 weeks, re-run this check** before merge — beta versions can be yanked or superseded.

0.1.5. **Verify DE region support against the provider (R2 mitigation).** Provider docs do not explicitly enumerate `de.sentry.io`; base_url override is inferred. Before committing the provider config, run a one-rule smoke test on a **scratch Sentry project** (operator creates a throwaway project on the DE org):

```bash
cd /tmp && mkdir sentry-de-probe && cd sentry-de-probe
cat > main.tf <<'EOF'
terraform {
  required_providers {
    sentry = { source = "jianyuan/sentry", version = "0.15.0-beta2" }
  }
}
provider "sentry" {
  base_url = "https://de.sentry.io/api/"
}
data "sentry_organization" "this" {
  slug = "jikigai"
}
output "org_id" { value = data.sentry_organization.this.internal_id }
EOF
export SENTRY_AUTH_TOKEN=<from Phase 0.9>
terraform init && terraform plan
```

Expected: `terraform plan` returns the org's internal_id non-empty. If it errors, DE region support is broken in v0.15.0-beta2 — fall back to ADR-031 escape hatch (defer Phase 5 entirely; keep `configure-sentry-alerts.sh`).

0.2. **Enumerate the 4 existing dashboard-keyed alert rule names byte-for-byte.** Source-of-truth is `apps/web-platform/scripts/configure-sentry-alerts.sh`. Run:
```bash
grep -nE '^\s*"?name"?\s*[:=]' apps/web-platform/scripts/configure-sentry-alerts.sh | head -20
```
Persist the exact strings (with punctuation, casing, trailing spaces if any) to `knowledge-base/legal/audits/2026-05-15-sentry-migration-audit.md` so the Terraform `name = "..."` declarations match byte-for-byte (per `2026-05-13-helper-migration-must-preserve-operator-dashboard-message-strings.md`).

0.3. **Confirm scheduled workflows inventory + select the 9 in scope.**
```bash
ls .github/workflows/scheduled-*.yml | wc -l   # expect 35
```
Scope FR2 cron monitors to these **9 workflows** (union of plan's original 6 + the 5 workflows named by #3236, of which 4 exist). All have silent-failure-as-failure-mode where absence breaches the single-user-incident threshold. Folding in #3236 (`Closes #3236` in PR body):

From #3236 ("review: cross-workflow heartbeat for scheduled secret-touching workflows"):
- `.github/workflows/scheduled-terraform-drift.yml` (drift detection)
- `.github/workflows/scheduled-oauth-probe.yml` (OAuth credentials probe)
- `.github/workflows/scheduled-cf-token-expiry-check.yml` (Cloudflare token expiry)
- `.github/workflows/scheduled-github-app-drift-guard.yml` (GitHub App drift)
- *(`scheduled-canary-bundle-claim-check.yml` named by #3236 does NOT exist on main — dropped from scope; document in PR body when closing #3236)*

Additional silent-failure-class workflows from plan's own analysis:
- `.github/workflows/scheduled-daily-triage.yml` (issue backlog rot if dark)
- `.github/workflows/scheduled-realtime-probe.yml` (monthly OAuth flow probe — distinct from oauth-probe.yml)
- `.github/workflows/scheduled-skill-freshness.yml` (Monday audits)
- `.github/workflows/scheduled-content-vendor-drift.yml` (weekly vendor drift)
- `.github/workflows/scheduled-community-monitor.yml` (daily community monitoring)

Update the list inline in this plan if any names differ from the live filesystem at /work time.

0.4. **Doppler invocation triplet sanity.** New Terraform root will use the canonical pattern from `scheduled-terraform-drift.yml:54-85` (`doppler secrets get --plain` for R2 backend creds + `doppler run -p soleur -c prd_terraform --name-transformer tf-var -- terraform <cmd>` for everything else). For Sentry: since secrets are GitHub repo secrets, NOT Doppler, the env vars (`SENTRY_AUTH_TOKEN`, `SENTRY_ORG`, `SENTRY_PROJECT`) are exported in the workflow step before `terraform plan` — outside the doppler-run wrapper. Document this divergence in ADR-031.

0.5. **Grep operator-dashboard message-string consumers.** Per `helper-migration-must-preserve-operator-dashboard-message-strings.md`:
```bash
git grep -nE 'auth-(exchange-code-burst|callback-no-code-burst|per-user-loop|signout-burst)' \
  -- knowledge-base/ docs/ apps/ plugins/
```
Any match outside `configure-sentry-alerts.sh` is an operator-keyed reference whose contract the Terraform import must preserve.

0.6. **Verify Eleventy legal mirror inventory.** The mirror dir contains more files than the 3 in this plan's scope; filter to just the 3 we touch:
```bash
for f in data-protection-disclosure.md privacy-policy.md gdpr-policy.md; do
  [ -f "docs/legal/$f" ] && [ -f "plugins/soleur/docs/pages/legal/$f" ] || \
    { echo "MISSING: $f"; exit 1; }
done
echo "All 3 source/mirror pairs present."
```
Per `2026-03-18-dpd-processor-table-dual-file-sync.md`, drift between source and mirror is a known failure mode.

0.7. **Confirm `sentry-scrub.ts` will NOT be touched.**
```bash
git diff --name-only main..HEAD | grep -E 'sentry-scrub|sentry\.(client|server)\.config'
```
Expected: empty. If non-empty at any point in the PR, GDPR-gate fires Critical.

0.8. **Provision the three new GitHub repo secrets** (`SENTRY_INGEST_DOMAIN`, `SENTRY_PROJECT_ID`, `SENTRY_PUBLIC_KEY`) BEFORE Phase 4 lands. Derivation from existing DSN (Sentry DSN format: `https://<public_key>@<ingest-domain>/<project-id>`):

```bash
# Read current DSN (from existing repo secret SENTRY_DSN or NEXT_PUBLIC_SENTRY_DSN):
DSN=$(gh secret list --json name | jq -r '.[].name' | grep -E '^(NEXT_PUBLIC_)?SENTRY_DSN$' | head -1)
# Operator: paste the DSN value when prompted (can read from Sentry UI → Settings → Projects → <proj> → Client Keys).
# Parse:
#   PUBLIC_KEY = part before '@'
#   INGEST_DOMAIN = host between '@' and final '/'
#   PROJECT_ID = path component after final '/'

# Set:
gh secret set SENTRY_INGEST_DOMAIN --body "<derived>"
gh secret set SENTRY_PROJECT_ID    --body "<derived>"
gh secret set SENTRY_PUBLIC_KEY    --body "<derived>"
```

The secrets are non-sensitive in the strict sense (DSN public key is intentionally exposed in client bundles) but storing as repo secrets keeps the wiring contract uniform. Verify after set: `gh secret list | grep -E '^SENTRY_(INGEST_DOMAIN|PROJECT_ID|PUBLIC_KEY)\b'` returns 3 lines.

0.9. **Local `SENTRY_AUTH_TOKEN` source for operator runs.** GitHub does not expose secret VALUES via API. For local execution of Phase 2.1 audit script + Phase 5 `terraform import`, the operator must either:
  (a) Use a personal Sentry user token from `https://de.sentry.io/settings/account/api/auth-tokens/` (scope: `project:read`, `org:read`, `monitor:read` — read-only is sufficient for the audit; import needs `project:write`).
  (b) Generate a short-lived internal integration token from `https://de.sentry.io/settings/integrations/internal-integrations/`.

Document the chosen path in ADR-031. Do NOT add the local token to Doppler or commit it anywhere.

### Phase 1: Migration audit script

Create `apps/web-platform/scripts/sentry-monitors-audit.sh` modeled on `configure-sentry-alerts.sh:1-176`. Single purpose: list every Sentry Monitor in the org, list every Alert Rule, join on `monitor_id`, flag orphans, write a Markdown report.

**File:** `apps/web-platform/scripts/sentry-monitors-audit.sh`

Skeleton:
```bash
#!/usr/bin/env bash
# Sentry Monitors/Alerts migration audit (one-shot, idempotent).
# Lists monitors, lists alerts, joins on id, flags orphans, writes dated report.
# Required env: SENTRY_AUTH_TOKEN, SENTRY_ORG (project optional — org-wide audit).
set -euo pipefail

# Region detection reuses the probe pattern from configure-sentry-alerts.sh:31-38
# (probe sentry.io and de.sentry.io with /users/me/ and pick the one that 200s).

# Endpoints (verified 2026-05-15 against docs.sentry.io/api):
#   GET /api/0/organizations/{org}/monitors/
#   GET /api/0/organizations/{org}/alert-rules/
#   GET /api/0/projects/{org}/{project}/rules/        (issue alerts, project-scoped)

# Output: knowledge-base/legal/audits/sentry-migration-audit-<YYYY-MM-DD>.md
# - inventory table: monitors (slug, type, schedule, project)
# - inventory table: alert rules (id, name, project, condition summary, action targets)
# - orphan list: monitors without paired routing
# - orphan list: alert rules referencing missing monitors
# - vendor DPA evidence link
```

**File:** `apps/web-platform/scripts/sentry-monitors-audit.test.sh`

Modeled on `plugins/soleur/skills/linear-fetch/scripts/assert-no-linear-telemetry.test.sh:1-105`. Bash + `set -eu` + run_assert helper. Tests:
- T1: missing `SENTRY_AUTH_TOKEN` exits non-zero with clear message
- T2: region probe succeeds against EU (`de.sentry.io`)
- T3: orphan join logic — fixture monitors + fixture alerts → expected orphan list (use tmpfile JSON fixtures, no live API)
- T4: report write is idempotent (re-run produces a new dated file, never mutates)
- T5: match-by-id (not by name) — two monitors with the same name resolve distinctly

The fixtures live inline in the test as heredocs (no `__fixtures__` dir, per repo convention).

### Phase 2: Run audit, capture report

The audit script is intended to run **in CI on PR-A merge** AND **locally during plan-work** to verify orphan state pre-merge. Two invocations:

2.1. **Local run during /work** (operator):
```bash
# Token source: Phase 0.9 (user token or internal integration token from Sentry UI).
SENTRY_AUTH_TOKEN=<paste-from-sentry-ui> \
  SENTRY_ORG=jikigai \
  bash apps/web-platform/scripts/sentry-monitors-audit.sh
```
The report writes to `knowledge-base/legal/audits/sentry-migration-audit-2026-05-15.md` for operator runs (Phase 2.1 default — `AUDIT_OUT_DIR` unset, script defaults to the tracked dir). CI release runs override `AUDIT_OUT_DIR` to `$RUNNER_TEMP/sentry-audit/` and upload the report as a release asset (Phase 2.2). Both paths produce Article 30 §5(2) evidence — see OQ1 for the dual-path rationale. The script MUST emit rule IDs in machine-readable form (JSON array at end of report, prefixed `<!-- ids: [...] -->`) so Phase 5 import can consume them without dashboard scraping.

2.1.5. **Orphan reconciliation runbook (if Phase 2.1 returns non-zero orphans).** The audit script may surface three kinds of orphan:

| Orphan class | Diagnosis | Remediation |
|---|---|---|
| Monitor without paired Alert (detection without routing) | Threshold breaches never page. Single-user-incident threshold breach on first occurrence. | Either (a) **delete monitor via API**: `curl -X DELETE -H "Authorization: Bearer $SENTRY_AUTH_TOKEN" "https://de.sentry.io/api/0/organizations/jikigai/monitors/<slug>/"`, OR (b) **pair with new Alert via Sentry UI** under Alerts tab → New Alert → Bind monitor. Document the choice in the audit report. |
| Alert referencing missing Monitor | Alert is dead; routing rule fires nothing. Cosmetic only — does not breach threshold. | **Delete alert via API**: `curl -X DELETE -H "Authorization: Bearer $SENTRY_AUTH_TOKEN" "https://de.sentry.io/api/0/organizations/jikigai/alert-rules/<id>/"`. Document. |
| Pre-2026 Metric Alert auto-migrated but routing missing | Sentry split surfaced an orphan that pre-existed. Single-user-incident threshold WAS already breached for that rule. | Treat as production incident: file a P1 issue, recreate the routing rule, post-mortem via `/soleur:incident`. |

**Hard rule:** the audit report MUST be committed with zero open orphans (every orphan documented with a remediation taken) before Phase 5 (Terraform import) begins. If a Class-3 orphan is found, this PR pauses and the incident path takes priority.

2.2. **CI run on PR-A merge**: add a single step in `.github/workflows/reusable-release.yml` (after release publish) that re-runs the audit and uploads the resulting Markdown as a release artifact. Provides an evergreen Article 30 evidence trail.

### Phase 3: Legal corpus update — 8 files

Synchronized edit. Each subsection lists exact line locations from Phase 0 verification.

3.1. **`docs/legal/data-protection-disclosure.md`** §2.3(m) — add carve-out paragraph: "Sentry monitor classes processed: aggregated span-attribute and custom-metric values (low PII risk). Sentry log ingestion is NOT enabled; no application log content is forwarded to Sentry." Bump `**Last Updated:**` line 12 to `May 15, 2026 (added monitor-class carve-out per §2.3(m))`.

3.2. **`docs/legal/privacy-policy.md`** §5.10 — mirror the carve-out, same exact wording. Bump `**Last Updated:**` (lines 11 + 51 — TWO occurrences, both must update).

3.3. **`docs/legal/gdpr-policy.md`** operational-telemetry entry — mirror the carve-out. Bump `**Last Updated:**` line 13.

3.4. **`plugins/soleur/docs/pages/legal/data-protection-disclosure.md`** — mirror of 3.1 (Eleventy source). Verify byte-for-byte sync via `diff docs/legal/data-protection-disclosure.md plugins/soleur/docs/pages/legal/data-protection-disclosure.md` returning zero output (the mirror may have additional Eleventy frontmatter; verify the body section is identical).

3.5. **`plugins/soleur/docs/pages/legal/privacy-policy.md`** — mirror of 3.2.

3.6. **`plugins/soleur/docs/pages/legal/gdpr-policy.md`** — mirror of 3.3.

3.7. **`knowledge-base/legal/article-30-register.md`** PA8 §(c) — add carve-out paragraph; bump YAML frontmatter `last_reviewed: 2026-05-15`. Link to the migration audit artifact (Phase 2.1 output path).

3.8. **`knowledge-base/legal/compliance-posture.md`** — add a row to Active Compliance Items table referencing the audit artifact and the GDPR-gate Phase 6 outcome.

**Verification:**
```bash
# Source/mirror body sync (excluding Eleventy frontmatter):
for f in data-protection-disclosure privacy-policy gdpr-policy; do
  diff <(awk '/^---$/{c++;next} c>=2' "docs/legal/${f}.md") \
       <(awk '/^---$/{c++;next} c>=2' "plugins/soleur/docs/pages/legal/${f}.md") || echo "DRIFT: $f"
done

# Last Updated body-form count (Kieran-verified 2026-05-15: each source file has exactly ONE Last Updated line):
grep -c '\*\*Last Updated:\*\* May 15, 2026' docs/legal/data-protection-disclosure.md   # expect 1
grep -c '\*\*Last Updated:\*\* May 15, 2026' docs/legal/privacy-policy.md                # expect 1
grep -c '\*\*Last Updated:\*\* May 15, 2026' docs/legal/gdpr-policy.md                    # expect 1

# Article 30 YAML form:
grep -E '^last_reviewed: 2026-05-15$' knowledge-base/legal/article-30-register.md         # expect 1
```

### Phase 4: Cron monitor wiring — 9 workflows

For each of the 9 scoped workflows from Phase 0.3, add **two HTTP check-in steps**: `in_progress` at job start, `ok|error` at job end (conditional on `if: success()` / `if: failure()`). This phase **closes #3236** by giving every secret-touching scheduled workflow a dead-man's-switch via Sentry Crons (a third option beyond #3236's two proposed shapes — neither in-repo polling nor external pinger, but vendor-hosted heartbeat reusing the existing Sentry trust boundary).

**Form (DSN-derived endpoint, verified against `docs.sentry.io/product/crons/getting-started/http/`):**
```yaml
- name: Sentry check-in (in_progress)
  if: always()
  env:
    SENTRY_INGEST_DOMAIN: ${{ secrets.SENTRY_INGEST_DOMAIN }}
    SENTRY_PROJECT_ID: ${{ secrets.SENTRY_PROJECT_ID }}
    SENTRY_PUBLIC_KEY: ${{ secrets.SENTRY_PUBLIC_KEY }}
    MONITOR_SLUG: scheduled-terraform-drift  # unique per workflow
  run: |
    curl --max-time 10 -fSs -X POST \
      "https://${SENTRY_INGEST_DOMAIN}/api/${SENTRY_PROJECT_ID}/cron/${MONITOR_SLUG}/${SENTRY_PUBLIC_KEY}/?status=in_progress" \
      -o /tmp/sentry-checkin-${MONITOR_SLUG}.json
    jq -r .id /tmp/sentry-checkin-${MONITOR_SLUG}.json > /tmp/sentry-checkin-id-${MONITOR_SLUG}
  continue-on-error: true   # never fail the workflow because of telemetry

# ... actual workflow steps ...

- name: Sentry check-in (ok)
  if: success()
  run: |
    CHECKIN_ID=$(cat /tmp/sentry-checkin-id-${MONITOR_SLUG} || true)
    [ -n "${CHECKIN_ID}" ] && \
      curl --max-time 10 -fSs -X PUT \
        "https://${SENTRY_INGEST_DOMAIN}/api/${SENTRY_PROJECT_ID}/cron/${MONITOR_SLUG}/${SENTRY_PUBLIC_KEY}/${CHECKIN_ID}/?status=ok"

- name: Sentry check-in (error)
  if: failure()
  run: |
    CHECKIN_ID=$(cat /tmp/sentry-checkin-id-${MONITOR_SLUG} || true)
    [ -n "${CHECKIN_ID}" ] && \
      curl --max-time 10 -fSs -X PUT \
        "https://${SENTRY_INGEST_DOMAIN}/api/${SENTRY_PROJECT_ID}/cron/${MONITOR_SLUG}/${SENTRY_PUBLIC_KEY}/${CHECKIN_ID}/?status=error"
```

Three secrets need adding to repo settings: `SENTRY_INGEST_DOMAIN`, `SENTRY_PROJECT_ID`, `SENTRY_PUBLIC_KEY`. Derived from the existing DSN; document the derivation in ADR-031.

The monitor itself is declared in Phase 5 (Terraform `sentry_cron_monitor` resource per workflow, schedule matching the workflow's cron expression).

### Phase 5: Terraform onramp + ADR-031

**New root:** `apps/web-platform/infra/sentry/`

Files:
- `apps/web-platform/infra/sentry/versions.tf` — `required_providers { sentry = { source = "jianyuan/sentry", version = "0.15.0-beta2" } }`. **Pinned to exact beta** with a Risk-section note about beta status.
- `apps/web-platform/infra/sentry/main.tf` — backend block (R2, key `web-platform/sentry/terraform.tfstate`), provider config (env-derived auth token, conditional base_url for DE region).
- `apps/web-platform/infra/sentry/variables.tf` — `sentry_org` (default `jikigai`), `sentry_project`, `sentry_region` (default `de`).
- `apps/web-platform/infra/sentry/issue-alerts.tf` — 4 `sentry_issue_alert` resources matching the 4 rules in `configure-sentry-alerts.sh`. `name` field MUST byte-match the Phase 0.2-captured strings. **Lifecycle: `ignore_changes = [conditions_v2, filters_v2, actions_v2, environment, frequency]`** (Kieran P1 — `environment` and `frequency` also recompute on import for some legacy rules per v0.15 release notes; widening the list now avoids a fix-up commit at /work).
- `apps/web-platform/infra/sentry/cron-monitors.tf` — 9 `sentry_cron_monitor` resources, one per scoped workflow. Each declares `schedule { type = "crontab", value = "<expr>" }` matching the workflow's cron, plus `checkin_margin_minutes` and `max_runtime_minutes` from the per-workflow fixture table (see below). Per-workflow grace-period derivation:

    | Workflow | Cron | Observed duration (median) | `checkin_margin_minutes` | `max_runtime_minutes` |
    |---|---|---|---|---|
    | scheduled-terraform-drift | `0 6,18 * * *` | ~5 min | 30 | 15 |
    | scheduled-oauth-probe | `0 7 1 * *` | ~3 min | 60 | 10 |
    | scheduled-cf-token-expiry-check | TBD-verify at /work | TBD | 30 | 10 |
    | scheduled-github-app-drift-guard | TBD-verify at /work | TBD | 30 | 10 |
    | scheduled-daily-triage | `0 4 * * *` | ~3 min agent-based | 60 | 15 |
    | scheduled-realtime-probe | `0 7 1 * *` | ~3 min | 60 | 10 |
    | scheduled-skill-freshness | `0 9 * * 1` | TBD | 60 | 10 |
    | scheduled-content-vendor-drift | `0 9 * * MON` | TBD | 60 | 10 |
    | scheduled-community-monitor | daily | TBD | 60 | 10 |

    Defaults are 2x observed median (margin = grace before "missed") and observed-95th-percentile + 50% (max_runtime = absolute upper bound). TBD values are captured at /work Phase 0.3 by reading workflow run history via `gh run list`.
- `apps/web-platform/infra/sentry/README.md` — invocation cheatsheet (env vars, doppler vs. github-secrets wiring, import procedure).

**Import procedure** (operator step, run BEFORE the first `terraform apply`):
```bash
cd apps/web-platform/infra/sentry
export SENTRY_AUTH_TOKEN=...   # from GH repo secret or local Doppler
terraform init -input=false
# For each of the 4 alert rules, get its id from the migration audit report and:
terraform import sentry_issue_alert.auth_exchange_code_burst jikigai/<project>/<rule-id>
# (repeat for the other 3)
# Cron monitors are net-new — no import; first apply creates them.
terraform plan   # MUST be a no-op for the 4 imports (modulo v2-attribute lifecycle-ignored drift)
```

**5.3. Import rollback (partial-failure recovery).** If `terraform import` fails on rule N of 4 (network blip, API quirk, drift on the imported rule), the state file now has N-1 rules. **Do not proceed to apply.** Recover via:

```bash
# Remove partial imports:
for resource in sentry_issue_alert.auth_exchange_code_burst \
                sentry_issue_alert.auth_callback_no_code_burst \
                sentry_issue_alert.auth_per_user_loop \
                sentry_issue_alert.auth_signout_burst; do
  terraform state rm "$resource" 2>/dev/null || true
done
# Verify clean slate:
terraform state list | grep sentry_issue_alert   # expect empty
# Diagnose the failing rule (most common cause: rule id changed after audit; re-run Phase 2.1 to refresh).
# Retry import from a clean state.
```

If 3+ retries fail, fall back to the ADR-031 escape hatch: leave `configure-sentry-alerts.sh` as source of truth, commit ADR-031 with `status: rejected`, and revert Phase 5 commits.

**5.5. Auto-apply on push-to-main.** A new workflow `.github/workflows/apply-sentry-infra.yml` modeled on the existing `apply-deploy-pipeline-fix.yml` pattern fires on push to `main` when files under `apps/web-platform/infra/sentry/cron-monitors.tf` change. It runs `terraform apply -auto-approve` for the cron-monitor resources only (issue-alert resources are import-only post-merge per AC13). This closes the window between Phase 4 check-in steps shipping and the monitors existing — the workflow auto-creates the 9 monitors within ~2 minutes of merge, before any check-in curl 404s would accumulate. Issue-alert imports remain operator-driven via AC13.

**ADR-031** at `knowledge-base/engineering/architecture/decisions/ADR-031-sentry-as-iac.md`:

YAML frontmatter (per ADR-030 precedent):
```yaml
---
title: "ADR-031 — Sentry alert and cron monitor configuration as IaC"
status: accepted
date: 2026-05-15
plan: knowledge-base/project/plans/2026-05-15-feat-sentry-monitors-alerts-adapt-plan.md
spec: knowledge-base/project/specs/feat-sentry-monitors-alerts-adapt/spec.md
brainstorm: knowledge-base/project/brainstorms/2026-05-15-sentry-monitors-alerts-adaptation-brainstorm.md
issue: 3814
supersedes: none
related: []
---
```
Sections: Context (the split + the script-as-code starting point), Decision (jianyuan provider + per-app root + GitHub-secrets auth + import-not-recreate), Consequences (provider-beta risk, secret-store divergence from spec, lifecycle-ignored v2 drift until follow-up), Escape Hatches (revert to `configure-sentry-alerts.sh` if beta blocks), Validation Gate (`terraform plan` no-op AC).

### Phase 6: GDPR-gate run

Run `/soleur:gdpr-gate` on the full PR diff. Expected output: **PASS** (no `sentry-scrub.ts` changes, no log-channel ingestion enabled). If the gate fires Critical on any disclosure surface, fold the recommended edit into Phase 3 in the same PR.

### Phase 7 (deferred follow-up): `configure-sentry-alerts.sh` deprecation

NOT in this PR. After PR-A merges AND one production release cycle ships (verified via the release workflow run that includes the Phase 2.2 audit artifact showing the 4 rules under Terraform management with no drift):

- Move `apps/web-platform/scripts/configure-sentry-alerts.sh` → `apps/web-platform/scripts/archive/configure-sentry-alerts.sh.archived`
- Remove the invocation step from `.github/workflows/reusable-release.yml`
- Add a header comment in the archived file pointing to `apps/web-platform/infra/sentry/`

**Trigger mechanic** (not operator memory): the deprecation tracking issue is filed AT Phase 5 commit time (not at PR-A merge) with label `blocked-on:next-release-cycle` and body: "Re-evaluate after the first `reusable-release.yml` run completes with `apply-sentry-infra.yml` having auto-applied at least once AND zero `terraform plan` drift on the imported issue-alert rules." A scheduled GH Action (`/soleur:schedule` weekly) checks: if PR-A merged AND ≥1 release run completed since merge AND `terraform plan` drift is zero, auto-comments on the deprecation issue with "Ready to proceed: AC16 conditions met". The comment is the operator's signal — no memory dependency.

## Files to Edit

Pre-PR-A:
- `.github/workflows/reusable-release.yml` — add Phase 2.2 audit-artifact step (one job step, no removals yet)
- `.github/workflows/scheduled-terraform-drift.yml` — add Phase 4 check-in steps (3 steps)
- `.github/workflows/scheduled-oauth-probe.yml` — add Phase 4 check-in steps (closes #3236 scope)
- `.github/workflows/scheduled-cf-token-expiry-check.yml` — add Phase 4 check-in steps (closes #3236 scope)
- `.github/workflows/scheduled-github-app-drift-guard.yml` — add Phase 4 check-in steps (closes #3236 scope)
- `.github/workflows/scheduled-daily-triage.yml` — add Phase 4 check-in steps
- `.github/workflows/scheduled-realtime-probe.yml` — add Phase 4 check-in steps
- `.github/workflows/scheduled-skill-freshness.yml` — add Phase 4 check-in steps
- `.github/workflows/scheduled-content-vendor-drift.yml` — add Phase 4 check-in steps
- `.github/workflows/scheduled-community-monitor.yml` — add Phase 4 check-in steps
- `docs/legal/data-protection-disclosure.md` (Phase 3.1)
- `docs/legal/privacy-policy.md` (Phase 3.2)
- `docs/legal/gdpr-policy.md` (Phase 3.3)
- `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` (Phase 3.4)
- `plugins/soleur/docs/pages/legal/privacy-policy.md` (Phase 3.5)
- `plugins/soleur/docs/pages/legal/gdpr-policy.md` (Phase 3.6)
- `knowledge-base/legal/article-30-register.md` (Phase 3.7)
- `knowledge-base/legal/compliance-posture.md` (Phase 3.8)

## Files to Create

- `apps/web-platform/scripts/sentry-monitors-audit.sh` (Phase 1)
- `apps/web-platform/scripts/sentry-monitors-audit.test.sh` (Phase 1)
- `apps/web-platform/infra/sentry/versions.tf` (Phase 5)
- `apps/web-platform/infra/sentry/main.tf` (Phase 5)
- `apps/web-platform/infra/sentry/variables.tf` (Phase 5)
- `apps/web-platform/infra/sentry/issue-alerts.tf` (Phase 5)
- `apps/web-platform/infra/sentry/cron-monitors.tf` (Phase 5)
- `apps/web-platform/infra/sentry/README.md` (Phase 5)
- `knowledge-base/engineering/architecture/decisions/ADR-031-sentry-as-iac.md` (Phase 5)
- `knowledge-base/legal/audits/2026-05-15-sentry-migration-audit.md` (Phase 2.1 output; commit the first version produced by the operator's local run)
- `.github/workflows/apply-sentry-infra.yml` (Phase 5.5; auto-applies cron-monitor resources on push to `main` when `apps/web-platform/infra/sentry/cron-monitors.tf` changes, modeled on `apply-deploy-pipeline-fix.yml`)

## Acceptance Criteria

### Pre-merge (PR)

- **AC1.** Phase 0 verification artifacts captured (provider version pinned, 4 dashboard-keyed name strings recorded, 6-workflow scope finalized, Doppler/GitHub-secret divergence documented in ADR-031).
- **AC2.** `apps/web-platform/scripts/sentry-monitors-audit.sh` + `.test.sh` exist; `bash apps/web-platform/scripts/sentry-monitors-audit.test.sh` exits 0.
- **AC3.** Audit report committed to `knowledge-base/legal/audits/2026-05-15-sentry-migration-audit.md` showing **zero orphan monitors** OR each orphan documented with remediation note (single-user-incident bar — cannot ship with unreconciled orphans).
- **AC4.** Phase 3 legal corpus edits applied to all 8 files. Verification:
  ```bash
  # Source/mirror sync:
  for f in data-protection-disclosure privacy-policy gdpr-policy; do
    diff <(awk '/^---$/{c++;next} c>=2' "docs/legal/${f}.md") \
         <(awk '/^---$/{c++;next} c>=2' "plugins/soleur/docs/pages/legal/${f}.md")
  done   # zero output expected
  # Last Updated body-form counts:
  grep -c '\*\*Last Updated:\*\* May 15, 2026' docs/legal/data-protection-disclosure.md         # 1
  grep -c '\*\*Last Updated:\*\* May 15, 2026' docs/legal/privacy-policy.md                       # 1
  grep -c '\*\*Last Updated:\*\* May 15, 2026' docs/legal/gdpr-policy.md                          # 1
  # Article 30 YAML form:
  grep -E '^last_reviewed: 2026-05-15$' knowledge-base/legal/article-30-register.md               # 1
  # Mirror Last Updated count (1:1 with source):
  grep -c '\*\*Last Updated:\*\* May 15, 2026' plugins/soleur/docs/pages/legal/data-protection-disclosure.md   # 1
  grep -c '\*\*Last Updated:\*\* May 15, 2026' plugins/soleur/docs/pages/legal/privacy-policy.md                # 1
  grep -c '\*\*Last Updated:\*\* May 15, 2026' plugins/soleur/docs/pages/legal/gdpr-policy.md                    # 1
  ```
- **AC5.** Nine scheduled workflows have `in_progress` + `ok` + `error` check-in step blocks. Verify via the **actual contract** (curl pattern) AND the human-readable name. Both must hold:
  ```bash
  for f in scheduled-terraform-drift scheduled-oauth-probe scheduled-cf-token-expiry-check \
           scheduled-github-app-drift-guard scheduled-daily-triage scheduled-realtime-probe \
           scheduled-skill-freshness scheduled-content-vendor-drift scheduled-community-monitor; do
    # Contract grep — the load-bearing one. Survives step name renames.
    n_curl=$(grep -cE 'cron/.*\$\{MONITOR_SLUG\}.*status=(in_progress|ok|error)' .github/workflows/${f}.yml)
    # Human-readable grep — sanity only.
    n_name=$(grep -cE 'Sentry check-in \((in_progress|ok|error)\)' .github/workflows/${f}.yml)
    echo "$f curl=$n_curl name=$n_name"
  done
  # Each line MUST show curl=3; name=3 is informational.
  ```
- **AC6.** Three new GitHub repo secrets exist: `SENTRY_INGEST_DOMAIN`, `SENTRY_PROJECT_ID`, `SENTRY_PUBLIC_KEY`. Verified at PR-A review time:
  ```bash
  gh secret list | grep -E '^SENTRY_(INGEST_DOMAIN|PROJECT_ID|PUBLIC_KEY)\b'
  ```
- **AC7.** `apps/web-platform/infra/sentry/` Terraform root exists with all 6 files. `terraform fmt -check` returns clean. `terraform init -backend=false; terraform validate` passes.
- **AC8.** ADR-031 committed at `knowledge-base/engineering/architecture/decisions/ADR-031-sentry-as-iac.md` with frontmatter `status: accepted` and `date: 2026-05-15`.
- **AC9.** `sentry-scrub.ts` and `sentry.client.config.ts` / `sentry.server.config.ts` are UNCHANGED:
  ```bash
  git diff --name-only main..HEAD | grep -E 'sentry-scrub|sentry\.(client|server)\.config' | wc -l   # 0
  ```
- **AC10.** `/soleur:gdpr-gate` invoked on full diff; outcome **PASS** or **PASS-with-non-Critical-advisory**. Critical findings block merge.
- **AC11.** PR body uses `Ref #3814` (NOT `Closes #3814`) because closure requires post-merge Terraform apply + one release-cycle observation. Manual `gh issue close 3814` after AC13 verifies.
- **AC12.** No regression in operator-keyed strings — Phase 0.5 grep output captured pre-PR matches an identical grep on `main` post-merge.

### Post-merge (operator)

- **AC13.** Operator runs `terraform import` for the 4 issue-alert rules and the first `terraform plan` shows no-op (modulo v2-attribute lifecycle-ignored drift). Apply succeeds idempotently.
- **AC14.** All 9 cron monitor `sentry_cron_monitor` resources created via first `terraform apply`. Confirm via Sentry API GET (not dashboard eyeball — per `hr-no-dashboard-eyeball-pull-data-yourself`):
  ```bash
  for slug in scheduled-terraform-drift scheduled-oauth-probe scheduled-cf-token-expiry-check \
              scheduled-github-app-drift-guard scheduled-daily-triage scheduled-realtime-probe \
              scheduled-skill-freshness scheduled-content-vendor-drift scheduled-community-monitor; do
    curl -fSs -H "Authorization: Bearer ${SENTRY_AUTH_TOKEN}" \
      "https://de.sentry.io/api/0/organizations/jikigai/monitors/${slug}/" | jq -r .slug
  done   # each must print its slug
  ```
- **AC15.** First scheduled run of each of the 9 workflows produces a recognized check-in (verify via Sentry API: `GET /api/0/organizations/jikigai/monitors/<slug>/checkins/` returns at least one entry within the monitor's `checkin_margin_minutes` window).
- **AC16.** One full production release cycle completes via `reusable-release.yml` with the Phase 2.2 audit artifact uploaded, showing the 4 alerts under Terraform management with zero drift.
- **AC17.** After AC13-AC16 verified, manually `gh issue close 3814` and file the deprecation follow-up issue (Phase 7).

## Domain Review

**Domains relevant:** Engineering, Product, Legal — carry-forward from brainstorm `## Domain Assessments`.

### Engineering (CTO)
**Status:** reviewed (carry-forward)
**Assessment:** Adapt now, narrow scope. Cron monitors for 6 scoped scheduled workflows is net-new free leverage. Terraform onramp is the right IaC home. Do not refactor silent-fallback helpers (split is server-side, app emit unaffected). Do not enable span/log monitors speculatively. Do not migrate qa/postmerge API queries pre-emptively. Trip-wire — orphaned monitor without paired routing alert — caught by Phase 1 audit script.

### Product (CPO)
**Status:** reviewed (carry-forward); plan-time CPO sign-off required per `requires_cpo_signoff: true`.
**Assessment:** Defer productization of Sentry-like observability for Soleur users to demand-signal (roadmap row 4.9 already gates on 10+ users). Revisit when 3+ Phase 4 founders pull for it. CPO consents to the audit + Terraform + crons scope as engineering-tier work, not product expansion.

### Legal (CLO)
**Status:** reviewed (carry-forward)
**Assessment:** Adapt with new safeguards. Verify auto-migration (XS, Phase 1+2). Update Art. 30 + DPD + Privacy Policy + GDPR Policy with explicit "log ingestion NOT enabled" carve-out (S, Phase 3). Multi-tenant DPA clause (M) deferred to #3815. Do not enable log-condition monitors before extending `sentry-scrub.ts` to cover the `logs` event channel (enforced by Phase 6 GDPR-gate + AC9). GDPR-gate required on implementation diff.

### Product/UX Gate
**Tier:** none — no `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx` files in scope. No user-facing UI surface added.

### Brainstorm-recommended specialists
None named by brainstorm leaders. Spec-flow-analyzer to run as Phase 3 of plan skill (not yet run as of plan draft).

## Risks

- **R1. Provider beta.** `jianyuan/terraform-provider-sentry` v0.15.0-beta2 is beta; field shapes (esp. `*_v2` attributes) may change. Mitigation: pinned version + `lifecycle.ignore_changes = [conditions_v2, filters_v2, actions_v2]` on imported issue-alerts + ADR-031 escape hatch.
- **R2. DE region support unverified.** Provider docs do not explicitly enumerate `de.sentry.io`; base_url override is inferred. Mitigation: Phase 0.1 test against DE org returns a non-empty resource list before committing the provider config. If it fails, fallback option is documented in ADR-031 (revert to script-as-code, defer Terraform).
- **R3. Crons grace-period required values.** `checkin_margin_minutes` and `max_runtime_minutes` have no documented Sentry defaults — Terraform schema marks both required. Mitigation: per-workflow values derived from observed workflow duration + 2x safety margin; document derivation in cron-monitors.tf comments.
- **R4. Operator-keyed message strings.** The 4 dashboard alerts' `name` fields are operator-keyed (per `helper-migration-must-preserve-operator-dashboard-message-strings.md`); byte-mismatch on import would silently re-key any operator dashboard query. Mitigation: Phase 0.2 captures the exact strings; AC12 grep verifies post-merge invariance.
- **R5. Duplicate-name idempotency trap.** Sentry rule API allows two rules to share a name (`2026-04-29-supabase-auth-probe-and-sentry-rule-api-quirks.md`). Mitigation: audit script + Terraform import match by **id**, never by name. Encoded in Phase 5 import procedure.
- **R6. Beta-provider drift on `_v2` attributes.** Importing existing rules may produce non-empty `terraform plan` due to provider-generated `*_v2` fields. Mitigation: `ignore_changes` lifecycle until the next provider GA; tracked as follow-up issue at deprecation time.
- **R7. Audit script orphan false-positives.** Sentry's API does not expose an `orphan` flag; join is client-side. A monitor created today and an alert routing to it created tomorrow could appear orphaned in the join window. Mitigation (encoded): audit runs **three times** — (a) Phase 2.1 local during /work, (b) Phase 2.2 CI re-run on PR-A merge, (c) one post-Phase-5-apply re-run after operator import. An orphan must appear in ALL THREE runs to count; transient artifacts of in-flight edits are filtered. The reconciliation is a Phase 2.1.5 step recorded in the audit report.

## Sharp Edges

- **SE1.** A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (Not applicable here — section is filled — but noted per plan-skill template requirement.)
- **SE2.** Provider name: **`jianyuan/sentry`** in versions.tf, NOT `getsentry/sentry`. The latter is a stale fork (2024-06-24).
- **SE3.** Resource name: **`sentry_cron_monitor`**, NOT `sentry_monitor`. The latter does not exist in v0.15.
- **SE4.** Sentry alert idempotency: **match by `id`**, never by `name`. Duplicate names are silently allowed by the API.
- **SE5.** Doppler invocation must include `--name-transformer tf-var` for Terraform vars AND a separate `doppler secrets get --plain` for R2 backend creds (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`). Per `2026-05-09-drift-runbook-canonical-tf-invocation-and-fresh-plan.md`.
- **SE6.** Re-run `terraform plan` **fresh** immediately before any `apply` to catch unrelated drift accumulated since the last `plan`. Drift snapshots can be stale within hours.
- **SE7.** `bash -n` on YAML workflow files is invalid — use `actionlint`/`yamllint` for YAML, `bash -c '<extracted snippet>'` for the embedded shell (per `2026-05-11-multi-word-required-check-exposes-strip-all-whitespace-bug.md`).
- **SE8.** Curl in CI MUST use `--max-time 10` (network bound) per `2026-04-28-anon-key-test-fixture-leaked-into-prod-build.md`. Encoded in Phase 4 step template.
- **SE9.** Use `Ref #3814` (not `Closes #3814`) in PR body — closure requires post-merge first-scheduled-run verification (AC15). Per `2026-05-11-plan-r6-closes-after-apply-deferral-pattern.md`.
- **SE10.** `EventFrequencyCondition.interval` Sentry API rejects `10m` — use 5m, 15m, 30m, 60m only. Pre-existing `configure-sentry-alerts.sh` uses 15m/30m/60m; Terraform import inherits these. Do not "tidy" the values during import.
- **SE11.** Eleventy mirror in `plugins/soleur/docs/pages/legal/` must be touched in the same PR as `docs/legal/` source — drift between source and mirror is the modal failure mode here per `2026-03-18-dpd-processor-table-dual-file-sync.md`.
- **SE12.** Sentry payload PII rule (`2026-04-28-sentry-payload-pii-and-client-observability-shim.md`): never forward `error.message`; only typed enum fields. Not in scope for this PR (no new emit sites), but `lib/client-observability.ts` posture stays intact — verified by AC9.
- **SE13.** Crons HTTP endpoint is **DSN-derived** (`<ingest-domain>/api/<project-id>/cron/<slug>/<public-key>/`), NOT org-API-derived. The three new secrets (`SENTRY_INGEST_DOMAIN`, `SENTRY_PROJECT_ID`, `SENTRY_PUBLIC_KEY`) are extracted from the existing DSN.
- **SE14.** Cron monitor `schedule.value` must match the workflow's cron expression. If a workflow's cron changes, the monitor's cron must change in the same PR (sibling-file-touch invariant).
- **SE15.** Per `hr-no-dashboard-eyeball-pull-data-yourself` — AC14/15 verify monitor existence + check-in receipt via API GET, NOT by clicking around the Sentry UI.

## Open Questions

- **OQ1. RESOLVED (dual-path; post-merge correction).** Audit-artifact home depends on caller, not a single location:
  - **Operator runs** (Phase 2.1 pre-import baseline, ad-hoc local re-runs) default `AUDIT_OUT_DIR` unset → write to `knowledge-base/legal/audits/sentry-migration-audit-<YYYY-MM-DD>.md` (tracked in git history). Produces the canonical pre-import snapshot.
  - **CI release runs** (Phase 2.2 — `reusable-release.yml` after each `gh release create`) override `AUDIT_OUT_DIR=${RUNNER_TEMP}/sentry-audit/` → write to ephemeral runner storage and upload the report as a GitHub release asset keyed by the release tag. Produces the per-release durable evidence record.

  Both paths satisfy Article 30 §5(2) accountability: operator runs land an immutable git-history snapshot; release-asset runs land a durable per-release artifact (GitHub release assets are non-expiring and tag-keyed). **Why dual-path vs. commit-back-from-CI:** committing from every release would generate a noisy commit-per-release, require a bot identity with branch-protection bypass, and open a write-to-main authorization surface that the `sentry-infra-apply` Environment gate (PR #3843) was designed to close on the apply side — symmetric posture matters.

  *(Originally OQ1 resolved single-path commit-back; post-merge 8-agent review of #3811 surfaced the inconsistency between the plan's single-path claim and the workflow's actual `RUNNER_TEMP` override at `reusable-release.yml:313`. This entry corrects the docs to match shipped reality — see PR #3811 review P1-H.)*
- **OQ2.** ADR-031 lists ADR-006 (initial Cloudflare infra) and ADR-030 (multi-tenant deploy substrate) as `related`? Confirm during ADR drafting.
- **OQ3.** Provider beta — pin to v0.15.0-beta2 exactly. The version-renovate workflow will surface upgrades; promote to GA pin when v0.15.0 ships.
- **OQ4. (DHH dissent — kept for re-evaluation).** DHH plan review recommended cutting scope significantly: drop Phase 5 (Terraform onramp + ADR) and Phase 7 entirely, cut Phase 4 from 9 workflows to 3, inline the audit script (drop `.test.sh`). Argument: replacing a working 176-line script for 4 unchanging rules with a beta-pinned provider + new TF root + `ignore_changes` workaround + ADR is ceremony; wait for a second Sentry change. **Decision: rejected for this PR** — user picked Approach C (full scope) at brainstorm time, multi-tenant DPA issue (#3815) assumes the IaC foundation, and the 9-workflow scope closes #3236 which is independently brand-survival material. **Re-evaluate trigger:** if Phase 0.1.5 DE region smoke test fails OR if `terraform plan` shows non-trivial drift after import on >1 of 4 rules, fall back to DHH's reframe (escape hatch in ADR-031).

## Open Code-Review Overlap

Three open `code-review`-labeled issues touch files in this plan's scope (queried 2026-05-15):

- **#3236** — *review: cross-workflow heartbeat for scheduled secret-touching workflows*. Touches `.github/workflows/scheduled-terraform-drift.yml` and four siblings.
  **Disposition: Fold in.** Phase 4 satisfies #3236's intent (heartbeat / dead-man's-switch for secret-touching scheduled workflows) using Sentry Crons as a third option beyond #3236's two proposed shapes. PR body uses `Closes #3236`. Plan scope widened from 6 to 9 workflows to cover the 4 (of 5) #3236-named workflows that exist; the 5th (`scheduled-canary-bundle-claim-check.yml`) does not exist on main and is dropped with a closing comment on #3236.

- **#3703** — *review: add client-pii-grep CI + lefthook gate (follow-up to #3696)*. Touches `apps/web-platform/sentry.client.config.ts`.
  **Disposition: Acknowledge.** Adjacent surface; this plan's NG4 + AC9 explicitly forbid touching `sentry.client.config.ts` to avoid scrub-boundary regression. #3703's CI-grep + lefthook gate is a distinct concern (boundary enforcement on FUTURE edits) and stays open for its own cycle. No file overlap in this PR.

- **#3739** — *review: extract reportSilentFallbackWithUser helper (collapse 11-site withIsolationScope+setUser duplication)*. Touches `apps/web-platform/server/sentry-scrub.ts` adjacencies.
  **Disposition: Acknowledge.** Helper-refactor concern in the `reportSilentFallback` family; this plan's NG4 + AC9 explicitly do NOT touch that family. Same reasoning as #3703 — different concern, different cycle. No file overlap in this PR.

## Test Strategy

- **Unit:** `bash apps/web-platform/scripts/sentry-monitors-audit.test.sh` (Phase 1, 5+ test cases including orphan join, region detection, match-by-id).
- **Integration:** Operator runs `sentry-monitors-audit.sh` against prd Sentry — produces the Phase 2.1 audit report.
- **Terraform:** `terraform fmt -check` + `terraform init -backend=false; terraform validate` (Phase 5 AC).
- **Post-merge contract verification:** API-GET each monitor (AC14) and each check-in (AC15) per `hr-no-dashboard-eyeball-pull-data-yourself`.
- **Legal corpus:** synchronized-edit grep counts (AC4); legal-compliance-auditor agent run after Phase 3 edits per `2026-03-18-legal-cross-document-audit-review-cycle.md`.

## References

- Brainstorm: `knowledge-base/project/brainstorms/2026-05-15-sentry-monitors-alerts-adaptation-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-sentry-monitors-alerts-adapt/spec.md`
- Issue: #3814; deferred multi-tenant DPA: #3815
- Provider docs: https://github.com/jianyuan/terraform-provider-sentry (v0.15.0-beta2 release notes)
- Sentry Crons HTTP form: https://docs.sentry.io/product/crons/getting-started/http/
- Sentry Alerts API index: https://docs.sentry.io/api/alerts/
- AGENTS.md rules invoked: `hr-weigh-every-decision-against-target-user-impact`, `hr-gdpr-gate-on-regulated-data-surfaces`, `hr-every-new-terraform-root-must-include-an`, `hr-all-infrastructure-provisioning-servers`, `hr-no-dashboard-eyeball-pull-data-yourself`, `cq-silent-fallback-must-mirror-to-sentry`, `wg-use-closes-n-in-pr-body-not-title-to`.
- Key learnings: `2026-05-13-helper-migration-must-preserve-operator-dashboard-message-strings.md`, `2026-05-09-drift-runbook-canonical-tf-invocation-and-fresh-plan.md`, `2026-04-29-supabase-auth-probe-and-sentry-rule-api-quirks.md`, `2026-04-28-sentry-payload-pii-and-client-observability-shim.md`, `2026-05-12-plan-time-api-contract-verification-and-pipeline-via-package-json.md`, `2026-05-11-plan-r6-closes-after-apply-deferral-pattern.md`, `2026-03-18-dpd-processor-table-dual-file-sync.md`, `2026-03-18-legal-cross-document-audit-review-cycle.md`.
