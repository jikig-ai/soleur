---
title: "Tasks — rundevoo.run zone onboarding (#12971)"
plan: knowledge-base/project/plans/2026-11-19-feat-rundevoo-run-zone-onboarding-plan.md
issue: 12971
branch: feat-rundevoo-run-test-app
lane: cross-domain
brand_survival_threshold: single-user incident
---

# Tasks

## Phase 0 — Bootstrap credential + TF root

- [x] 0.1 Dump local provider schema (pinned `~> 4.0` / 4.52.7); verify `cloudflare_record` accepts `content = "."` for `type = "MX"` and the `cloudflare_zone`/`cloudflare_zone_dnssec` shapes; derive nested-block surfaces for the jq filter (drop vacuous shrinkage clauses, document absence).
- [x] 0.2 Create `infra/rundevoo-run/`: `main.tf` (R2 backend key `rundevoo-run/terraform.tfstate`, `use_lockfile=false`, `api_token = var.cf_api_token_rundevoo`, retries block, `required_version >= 1.7`), `variables.tf` (`cf_api_token_rundevoo` sensitive no-default, SCOPE LEDGER description; `account_id` a literal in `zone.tf` bound to the literal zone id), `zone.tf` (`cloudflare_zone` full type, committed `import {}` block + failure-mode comment, `cloudflare_zone_dnssec`), `dns.tf` (null MX `0 .`, apex TXT `v=spf1 -all`, `_dmarc` TXT `v=DMARC1; p=reject`; literal FQDN names, `ttl = 1`), `.gitignore`, `README.md`.
- [x] 0.3 Create + run `bootstrap.sh`: operator pastes 1h admin token (`User → API Tokens → Edit` + `Zone → Zone → Read`); discover zone id; `POST /user/tokens` mints 3-group zone-scoped token; write `CF_API_TOKEN_RUNDEVOO` to Doppler `prd_terraform`; read-back verify **with the minted token** (`GET /zones/{id}`, `/dns_records`, `/dnssec`); retained-scope probe (`GET /zones/{soleur_ai_zone_id}` → 4xx); `trap`-EXIT self-revoke + revoke-minted-on-failure + revoke-on-remint. Sources `apps/cla-evidence/scripts/_cf-admin-token.sh` (README notes coupling).
- [x] 0.4 Commit `import { to = cloudflare_zone.rundevoo_run, id = "<zone_id>" }` with the literal zone id.
- [x] 0.5 `terraform init` + `plan -refresh=false` (placeholder vars) + commit `.terraform.lock.hcl`; one **real** `terraform plan` with the minted token before pushing. Push-ordering gate: Doppler write + lockfile land before/with `infra/rundevoo-run/**` push.

## Phase 1 — Workflow + guard wiring

- [x] 1.1 `.github/workflows/apply-rundevoo-infra.yml` mirroring `apply-sentry-infra.yml`: `pull_request:` unfiltered, `push` path-filtered (root + workflow + all 4 scripts), `merge_group:`, `workflow_dispatch`, `[skip-*]`, secret-free `detect-changes`, `plan_pr` fork-refusal + squash-ack call, apply guarded to main push/dispatch with `environment: infra-privileged`, `rundevoo-destroy-required` always-run aggregator, explicit `CLOUDFLARE_API_TOKEN` mapping from `CF_API_TOKEN_RUNDEVOO` (no broad-token fallback), per-ref concurrency.
- [x] 1.2 `scheduled-terraform-drift.yml`: 4th matrix leg `infra/rundevoo-run` + `rundevoo-dns-set-equality.sh` step gated `if: matrix.directory == 'infra/rundevoo-run'`.
- [x] 1.3 `scripts/`: `rundevoo-destroy-gate-verdict.sh`, `rundevoo-squash-ack-detect.sh`, `rundevoo-dns-set-equality.sh`.
- [x] 1.4 `tests/scripts/lib/destroy-guard-filter-rundevoo.jq`: delete + forget counting, `plan_ok` key, document `resource_creates` omission, shrinkage clauses only where schema shows nested surfaces.
- [x] 1.5 `tests/scripts/`: `test-destroy-guard-counter-rundevoo.sh` (`EXPECTED_TESTS -ne`), `test-rundevoo-destroy-gate-verdict.sh`, `test-rundevoo-squash-ack-detect.sh`, `test-rundevoo-dns-set-equality.sh`.
- [x] 1.6 `test-destroy-guard-regex-parity.sh`: `EXPECTED_SITES` rows (workflow + counter + squash-ack — NOT verdict script), header count 7→10, scope-pin loop.
- [x] 1.7 Required-check trio: `required-checks.txt` (ADR-139 justification block), `ci-required-ruleset-canonical-required-status-checks.json`, `infra/github/ruleset-ci-required.tf` context + comment.
- [x] 1.8 Registry rows: `pr-fanout-ledger.txt`, `required-check-wallclock-bounds.tsv` (seed = sentry bound), CODEOWNERS (`/infra/rundevoo-run/`, workflow, filter, counter → `@deruelle`).
- [x] 1.9 Registrations: `test-all.sh` `run_suite` rows ×4, regenerated `suite-shard-legs.tsv`/`suite-durations.tsv`, `test-affected-paths.sh` edges.
- [x] 1.10 `encryption-posture-ledger.json`: `cloudflare_zone` → `non_store_types`; `lint-encryption-posture.py` green.

## Phase 2 — Ledgers + compliance

- [x] 2.1 `domains.md` row (Cloudflare, renewal 2027-11-19, laila/lennon NS, parked + posture + #12971).
- [x] 2.2 `expenses.md` recurring $21.20/yr + one-time registration rows.
- [x] 2.3 `article-30-register.md` dated amendment: §0 scope conclusion, `CF_API_TOKEN_RUNDEVOO` posture (Tier-A-reachable, zone-write-only blast radius), PA-15 §(g)(4) precedent.
- [ ] 2.4 Update #12971 checklist state.

## Phase 3 — Post-merge verification

- [ ] 3.1 `apply-rundevoo-infra.yml` runs post-merge (imports zone via `import {}`, creates records + DNSSEC); `apply-github-infra.yml` applies ruleset — do not re-dispatch or race.
- [ ] 3.2 REST set-equality verify (`GET /zones/:id/dns_records` vs declared set); `dig` assertions (null MX, `v=spf1 -all`, `p=reject`, DNSSEC).
- [ ] 3.3 Drift leg plans green with refresh (expect transient red window between merge and first apply).
- [ ] 3.4 G1: `auto_renew` ON + registrant Jikigai SARL (API or dashboard attestation in `domains.md`).
- [ ] 3.5 Retroactive open-PR unblocking: synthetic `check-runs` POST `rundevoo-destroy-required` on each open PR's `headRefOid`; re-queue merge-queue entries.
- [ ] 3.6 Self-wedge recovery documented: `gh pr merge --admin`, or revert PR touching only `infra/github` + `scripts` (detect=false → synthetic PASS).
