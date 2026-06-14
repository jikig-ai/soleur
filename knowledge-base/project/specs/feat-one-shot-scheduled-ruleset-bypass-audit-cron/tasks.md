# Tasks — fix scheduled-ruleset-bypass-audit cron egress (full GitHub /meta CIDR coverage)

Plan: `knowledge-base/project/plans/2026-06-14-fix-ruleset-bypass-audit-cron-egress-github-cidr-plan.md`
Lane: cross-domain · Threshold: single-user incident · Classification: ops-remediation

## Phase 0 — Live diagnosis + approach decision (no writes)
- [ ] 0.1 Confirm via Sentry API (read-only) that the 2026-06-14 06:13 UTC fire is a
      *missed* check-in (no `?status=error` event) on monitor 5ccb1e67-fb90-4863-97d3-f8fd23287b37.
- [ ] 0.2 Search Sentry `egress-blocked` events for GitHub `DST=20.`/`DST=4.` around 06:13 UTC 06-14.
- [ ] 0.3 **L3-DNS artifact (gap to close):** confirm the `cron-egress-resolve` monitor was
      GREEN at 06:13 UTC 06-14 (a red there changes the diagnosis).
- [ ] 0.4 Confirm last infra apply convergence via the deploy webhook
      (`deploy.soleur.ai/hooks/deploy-status`); do not use a host shell.
- [ ] 0.5 Verify #5278 (OAuth probe) blocked DST before asserting shared cause.
- [ ] 0.6 Decision: static list (lean) vs generated; record. File follow-up issue for the
      generated/self-refreshing approach.

## Phase 1 — RED test
- [ ] 1.1 Add to `cron-egress-firewall.test.sh`: assert ≥1 Azure `20.x` `/32` AND ≥1 `4.x` `/32` present.
- [ ] 1.2 Add `assert_cidr_accept` for a representative Azure IP (e.g. `20.201.28.151/32`).
- [ ] 1.3 Add a CIDR line-count guard (precedent: existing count-guard at :338-341).
- [ ] 1.4 Run the firewall test suite → confirm RED.

## Phase 2 — GREEN: extend the CIDR file
- [ ] 2.1 Populate `cron-egress-allowlist-cidr.txt` with the full `/meta` `.git`+`.api` IPv4
      union (`sort -u`, snapshot-dated, evidence-commented). ~52 ranges.
- [ ] 2.2 Run the firewall test suite (incl. #5268 reject-whole-file validation) → all green.
- [ ] 2.3 Run the corrected `discoverability_test` (comm-based) → empty output.
- [ ] 2.4 `bash -n` + shellcheck the loader; confirm no malformed line trips the #5268 validator.
- [ ] 2.5 NO `cloud-init.yml` edit (templated from the file — verified).

## Phase 3 — Apply path (auto-on-merge)
- [ ] 3.1 Confirm `terraform_data.cron_egress_firewall` triggers_replace folds the CIDR hash.
- [ ] 3.2 Extend the server.tf post-apply assert (:827) to also require a `20.`/`4.` element.
- [ ] 3.3 Verify `apply-web-platform-infra.yml` re-applies on merge (path filter `apps/web-platform/infra/**`).

## Phase 4 — Post-merge verification (automatable)
- [ ] 4.1 Trigger cron via `/soleur:trigger-cron` (`cron/ruleset-bypass-audit.manual-trigger`).
- [ ] 4.2 Confirm a fresh `?status=ok` check-in on the Sentry monitor (poll Sentry API).
- [ ] 4.3 Confirm Sentry incident 5516336 recovered (recovery_threshold=1).
- [ ] 4.4 Confirm no new GitHub-DST `egress-blocked` events in the 24h after apply.
- [ ] 4.5 Check whether #5278 recovers; `gh issue close` it iff confirmed.
- [ ] 4.6 PR body: `Ref #<tracking>` + `Ref #5278` (NOT `Closes` — ops-remediation recovers post-apply).

## Notes
- Spec lacks valid `lane:` (no spec.md) — defaulted to `cross-domain` (TR2 fail-closed).
- CPO sign-off required before `/work` (brand_survival_threshold: single-user incident).
