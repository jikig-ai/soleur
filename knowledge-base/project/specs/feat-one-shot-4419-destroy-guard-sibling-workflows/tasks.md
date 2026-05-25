---
type: chore
lane: single-domain
related_plan: knowledge-base/project/plans/2026-05-25-chore-destroy-guard-sibling-workflows-plan.md
closes: 4419
---

# Tasks — Destroy-guard widening for apply-sentry-infra + apply-web-platform-infra (#4419)

Derived from `knowledge-base/project/plans/2026-05-25-chore-destroy-guard-sibling-workflows-plan.md`. Status flows: `[ ]` → `[~]` (in progress) → `[x]` (done).

## Phase 0 — Preconditions

- [x] 0.1 Verify CWD equals `/home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-4419-destroy-guard-sibling-workflows`.
- [x] 0.2 Probe tooling: jq 1.8.1, actionlint 1.7.7, shellcheck 0.10.0, terraform present.
- [x] 0.3 Capture `.yml.orig` snapshots of both sibling workflows for AC10 byte-identical regex diff.
- [x] 0.4 Re-read `tests/scripts/lib/destroy-guard-filter.jq` to lift `_count($side)` value-arg shape verbatim.
- [x] 0.5 Confirm `.github/CODEOWNERS:81` glob `/tests/scripts/fixtures/tfplan-*.json` covers new fixtures.

## Phase 1 — RED (failing tests + filter stubs)

### 1.1 Sentry synthesized fixtures

- [x] 1.1.1 Create `tests/scripts/fixtures/tfplan-sentry-resource-delete.json`.
- [x] 1.1.2 Create `tests/scripts/fixtures/tfplan-sentry-no-changes.json`.

### 1.2 Web-platform synthesized fixtures

- [x] 1.2.1 Create `tfplan-cf-ruleset-rule-removal.json` (rules 13→12 — ACME carve-out shape).
- [x] 1.2.2 Create `tfplan-cf-tunnel-ingress-removal.json` (3→2 ingress; SSH removed).
- [x] 1.2.3 Create `tfplan-cf-zone-settings-header-removal.json` (HSTS 1→0).
- [x] 1.2.4 Create `tfplan-cf-notification-integration-removal.json` (email_integration 1→0).
- [x] 1.2.5 Create `tfplan-cf-access-policy-include-removal.json` (include 1→0).
- [x] 1.2.6 Create `tfplan-web-platform-no-changes.json`.
- [x] 1.2.7 Create `tfplan-cf-ruleset-resource-delete.json`.
- [x] 1.2.8 Create `tfplan-web-platform-mixed.json` (1 resource-delete + 1 nested removal).
- [x] 1.2.9 Create `tfplan-cf-ruleset-rule-addition.json` (verifies `select(. > 0)` filters additions).

### 1.3 Test files (RED state)

- [x] 1.3.1 Create `tests/scripts/test-destroy-guard-counter-sentry.sh` (5 cases).
- [x] 1.3.2 Create `tests/scripts/test-destroy-guard-counter-web-platform.sh` (12 cases).
- [x] 1.3.3 RED state confirmed (filter files don't exist yet → "filter does not exist" error).

## Phase 2 — GREEN (filters + workflow wiring)

### 2.1 Create filter files

- [x] 2.1.1 Create `tests/scripts/lib/destroy-guard-filter-sentry.jq` (literal `nested_deletes: 0` + extension-point comment).
- [x] 2.1.2 Create `tests/scripts/lib/destroy-guard-filter-web-platform.jq` (5 path-specific clauses).

### 2.2 Wire workflows

- [x] 2.2.1 Edit `.github/workflows/apply-sentry-infra.yml` "Terraform plan (cron monitors only)" step → two-counter shape pointing at `destroy-guard-filter-sentry.jq`.
- [x] 2.2.2 Edit `.github/workflows/apply-web-platform-infra.yml` "Terraform plan (allow-list, non-SSH resources only)" step → two-counter shape pointing at `destroy-guard-filter-web-platform.jq`.

### 2.3 CODEOWNERS

- [x] 2.3.1 Edit `.github/CODEOWNERS` — add 4 rows after the existing destroy-guard block (lines 79-81).

### 2.4 Capture real fixtures

- [x] 2.4.1 Capture `tfplan-sentry-real-baseline.json` via Doppler + `terraform plan` — no drift; AC12 sentinel grep PASS (87 KB).
- [x] 2.4.2 Capture `tfplan-web-platform-real-baseline.json` via canonical Doppler triplet + `terraform plan` — no drift (73 no-op changes); aggressive redaction on sensitive-type resources (`doppler_secret`, `tls_private_key`, `random_id`, `github_actions_secret`, `doppler_service_token`, `cloudflare_zero_trust_access_service_token`, `cloudflare_zero_trust_tunnel_cloudflared`, `betteruptime_heartbeat`); AC12 sentinel grep PASS (267 KB).

### 2.5 Verify GREEN

- [x] 2.5.1 `bash tests/scripts/test-destroy-guard-counter-sentry.sh` → 5/5 pass.
- [x] 2.5.2 `bash tests/scripts/test-destroy-guard-counter-web-platform.sh` → 12/12 pass.
- [x] 2.5.3 `bash tests/scripts/test-destroy-guard-counter.sh` → 7/7 pass (github filter regression).
- [x] 2.5.4 `shellcheck -x` on both new tests → exits 0.
- [x] 2.5.5 `actionlint` on both modified workflows → exits 0.

## Phase 3 — Pre-ship sanity

- [x] 3.1 AC9 grep: old single-line filter pattern returns 0 matches; new `destroy_count=$((...))` returns exactly 2 matches.
- [x] 3.2 AC10 diff: byte-identical `[ack-destroy]` regex preserved on both workflows (both diffs exit 0).
- [x] 3.3 AC11 grep: CODEOWNERS contains the 4 new rows.
- [x] 3.4 AC12 grep: sentinel regex returns no matches against the two captured fixtures.
- [ ] 3.5 Draft PR body with `Closes #4419` and Test Plan section enumerating all AC5 + AC6 cases. (Done at ship time.)

## Phase 4 — Post-merge (operator / automation)

- [ ] 4.1 AC13: `gh issue close 4419 --comment "..."` — automated by ship skill via PR-merge → auto-close.

## Verification

- `bash tests/scripts/test-destroy-guard-counter-sentry.sh` — 5/5 pass.
- `bash tests/scripts/test-destroy-guard-counter-web-platform.sh` — 12/12 pass.
- `bash tests/scripts/test-destroy-guard-counter.sh` — 7/7 pass (regression).
- `actionlint .github/workflows/apply-sentry-infra.yml .github/workflows/apply-web-platform-infra.yml` — exit 0.
- `shellcheck -x tests/scripts/test-destroy-guard-counter-sentry.sh tests/scripts/test-destroy-guard-counter-web-platform.sh` — exit 0.
