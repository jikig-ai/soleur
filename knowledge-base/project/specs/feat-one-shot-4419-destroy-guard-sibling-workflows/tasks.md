---
type: chore
lane: single-domain
related_plan: knowledge-base/project/plans/2026-05-25-chore-destroy-guard-sibling-workflows-plan.md
closes: 4419
---

# Tasks — Destroy-guard widening for apply-sentry-infra + apply-web-platform-infra (#4419)

Derived from `knowledge-base/project/plans/2026-05-25-chore-destroy-guard-sibling-workflows-plan.md`. Status flows: `[ ]` → `[~]` (in progress) → `[x]` (done).

## Phase 0 — Preconditions

- [ ] 0.1 Verify CWD equals `/home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-4419-destroy-guard-sibling-workflows`.
- [ ] 0.2 Probe tooling: `command -v jq actionlint shellcheck terraform`.
- [ ] 0.3 Capture `.yml.orig` snapshots of both sibling workflows for AC10 byte-identical regex diff.
- [ ] 0.4 Re-read `tests/scripts/lib/destroy-guard-filter.jq` to lift `_count($side)` value-arg shape verbatim.
- [ ] 0.5 Confirm `.github/CODEOWNERS:81` glob `/tests/scripts/fixtures/tfplan-*.json` covers new fixtures.

## Phase 1 — RED (failing tests + filter stubs)

### 1.1 Sentry synthesized fixtures

- [ ] 1.1.1 Create `tests/scripts/fixtures/tfplan-sentry-resource-delete.json` — single `sentry_cron_monitor` with `change.actions = ["delete"]`.
- [ ] 1.1.2 Create `tests/scripts/fixtures/tfplan-sentry-no-changes.json` — empty `resource_changes`.

### 1.2 Web-platform synthesized fixtures

- [ ] 1.2.1 Create `tfplan-cf-ruleset-rule-removal.json` — `cloudflare_ruleset.seo_page_redirects` update; before.rules length=13, after.rules length=12 (model on ACME carve-out shape).
- [ ] 1.2.2 Create `tfplan-cf-tunnel-ingress-removal.json` — config[0].ingress_rule 3 → 2 (SSH removed).
- [ ] 1.2.3 Create `tfplan-cf-zone-settings-header-removal.json` — settings[0].security_header 1 → 0 (HSTS off).
- [ ] 1.2.4 Create `tfplan-cf-notification-integration-removal.json` — email_integration 1 → 0.
- [ ] 1.2.5 Create `tfplan-cf-access-policy-include-removal.json` — include 1 → 0.
- [ ] 1.2.6 Create `tfplan-web-platform-no-changes.json` — empty.
- [ ] 1.2.7 Create `tfplan-cf-ruleset-resource-delete.json` — resource-level delete on cloudflare_ruleset.
- [ ] 1.2.8 Create `tfplan-web-platform-mixed.json` — 1 resource-delete + 1 nested removal in same plan.
- [ ] 1.2.9 Create `tfplan-cf-ruleset-rule-addition.json` — before=12, after=13 (verifies `select(. > 0)` filters additions).

### 1.3 Test files (RED state)

- [ ] 1.3.1 Create `tests/scripts/test-destroy-guard-counter-sentry.sh` with cases T1–T5 from AC5. Mirror shape of `test-destroy-guard-counter.sh` (same `_run_gate`, `_report` helpers).
- [ ] 1.3.2 Create `tests/scripts/test-destroy-guard-counter-web-platform.sh` with cases T1–T12 from AC6.
- [ ] 1.3.3 Run both new tests — confirm RED (filter files don't exist yet).

## Phase 2 — GREEN (filters + workflow wiring)

### 2.1 Create filter files

- [ ] 2.1.1 Create `tests/scripts/lib/destroy-guard-filter-sentry.jq` with `{resource_deletes, nested_deletes: 0}` and the "extension point" comment block.
- [ ] 2.1.2 Create `tests/scripts/lib/destroy-guard-filter-web-platform.jq` with the 5 path-specific clauses (cloudflare_ruleset.rules, tunnel.config[0].ingress_rule, zone_settings.settings[0].security_header, notification.email_integration, access_policy.include).

### 2.2 Wire workflows

- [ ] 2.2.1 Edit `.github/workflows/apply-sentry-infra.yml` "Terraform plan (cron monitors only)" step — replace single-line destroy_count with two-counter shape pointing at destroy-guard-filter-sentry.jq. Update error message literal to two-counter form. Preserve byte-identical `[ack-destroy]` regex.
- [ ] 2.2.2 Edit `.github/workflows/apply-web-platform-infra.yml` "Terraform plan (allow-list, non-SSH resources only)" step — same shape, pointing at destroy-guard-filter-web-platform.jq. Update error message. Preserve `[ack-destroy]` regex.

### 2.3 CODEOWNERS

- [ ] 2.3.1 Edit `.github/CODEOWNERS` — add 4 rows after line 81 for new filter + test paths.

### 2.4 Capture real fixtures

- [ ] 2.4.1 Capture `tfplan-sentry-real-baseline.json` via documented Doppler+terraform sequence; redact `del(.variables)`; verify AC12 sentinel grep.
- [ ] 2.4.2 Capture `tfplan-web-platform-real-baseline.json` via canonical Doppler triplet (`2026-05-09-drift-runbook-canonical-tf-invocation-and-fresh-plan.md`); redact `del(.variables) | del(.. | .secret_b64?) | del(.. | .private_key_pem?)`; verify AC12 sentinel.

### 2.5 Verify GREEN

- [ ] 2.5.1 Run `bash tests/scripts/test-destroy-guard-counter-sentry.sh` — exits 0.
- [ ] 2.5.2 Run `bash tests/scripts/test-destroy-guard-counter-web-platform.sh` — exits 0.
- [ ] 2.5.3 Run `bash tests/scripts/test-destroy-guard-counter.sh` — exits 0 (regression check on github filter).
- [ ] 2.5.4 Run `shellcheck -x` on both new tests — exits 0.
- [ ] 2.5.5 Run `actionlint` on both modified workflows — exits 0.

## Phase 3 — Pre-ship sanity

- [ ] 3.1 AC9 grep: `git grep -nE 'resource_changes\[\?\]\?.*delete.*length' .github/workflows/apply-sentry-infra.yml .github/workflows/apply-web-platform-infra.yml` → 0 matches; `destroy_count=\$\(\(` → exactly 2 matches.
- [ ] 3.2 AC10 diff: byte-identical `[ack-destroy]` regex across both `.yml.orig` snapshots.
- [ ] 3.3 AC11 grep: CODEOWNERS contains the 4 new rows.
- [ ] 3.4 AC12 grep: sentinel regex returns no matches against the two captured fixtures.
- [ ] 3.5 Draft PR body with `Closes #4419` and Test Plan section enumerating all AC5 + AC6 cases.

## Phase 4 — Post-merge (operator / automation)

- [ ] 4.1 AC13: `gh issue close 4419 --comment "..."` per AC13 template in plan.

## Verification

- `bash tests/scripts/test-destroy-guard-counter-sentry.sh` — passes.
- `bash tests/scripts/test-destroy-guard-counter-web-platform.sh` — passes.
- `bash tests/scripts/test-destroy-guard-counter.sh` — passes (regression).
- `actionlint .github/workflows/apply-sentry-infra.yml .github/workflows/apply-web-platform-infra.yml` — passes.
- `shellcheck -x tests/scripts/test-destroy-guard-counter-sentry.sh tests/scripts/test-destroy-guard-counter-web-platform.sh` — passes.
