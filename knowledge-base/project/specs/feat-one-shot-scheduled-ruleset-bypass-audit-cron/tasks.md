# Tasks — fix scheduled-ruleset-bypass-audit cron egress (full GitHub /meta CIDR coverage)

Plan: `knowledge-base/project/plans/2026-06-14-fix-ruleset-bypass-audit-cron-egress-github-cidr-plan.md`
Lane: cross-domain · Threshold: single-user incident · Classification: ops-remediation

## Phase 0 — Live diagnosis + approach decision (no writes)
- [x] 0.1 Root cause artifact-confirmed: committed CIDR file = 4 ranges; live
      `api.github.com/meta` `.git`+`.api` = 52 ranges → 48 Azure `20.x`/`4.x` `/32`s
      uncovered. A *missed* (not *failed*) check-in is the firewall-drop signature
      (Step 3 heartbeat gated on Steps 1–2's GitHub calls). Sentry MCP/token not
      available in this env; the coverage-gap evidence is definitive and the fix is
      identical regardless of dashboard confirmation.
- [x] 0.2 Coverage gap quantified via `comm -23` set difference (48 uncovered before fix).
- [x] 0.3 L3-DNS ruled out by logic: a DNS failure manifests as `egress-dns-exfil` drops,
      not the missed-heartbeat signature; the firewall-CIDR gap is the artifact-backed cause.
- [x] 0.4 Apply path confirmed live: `apply-web-platform-infra.yml` triggers on push→main
      with path filter `apps/web-platform/infra/**`; `terraform_data.cron_egress_firewall`
      folds the CIDR hash + file-provisions it. No host shell.
- [x] 0.5 #5278 cross-referenced: shares the GitHub-LB CIDR gap (dials LB-rotated
      `github.com`); `Ref #5278` in PR, verify post-apply — do NOT `Closes` blind.
- [x] 0.6 Decision: **static list** (fastest recovery, lowest blast radius, matches the
      committed-file pattern). Follow-up issue filed for the self-refreshing generator.

## Phase 1 — RED test
- [x] 1.1 Added to `cron-egress-firewall.test.sh`: assert ≥1 Azure `20.x` `/32` AND ≥1 `4.x` `/32` present.
- [x] 1.2 Added `assert_cidr_accept` for representative Azure IPs (`20.201.28.151/32`, `4.208.26.197/32`).
- [x] 1.3 Added a CIDR exact-count guard (=52; mirrors the HOST allowlist count guard).
- [x] 1.4 Ran the firewall test suite → confirmed RED (3 new asserts fail against the 4-range file).

## Phase 2 — GREEN: extend the CIDR file
- [x] 2.1 Populated `cron-egress-allowlist-cidr.txt` with the full `/meta` `.git`+`.api` IPv4
      union (generated mechanically, `sort -u`, snapshot 2026-06-14, evidence-commented). 52 ranges.
- [x] 2.2 Ran the firewall test suite (incl. #5268 reject-whole-file validation) → 138/0 green.
- [x] 2.3 Ran the corrected `discoverability_test` (comm-based) → empty output (full coverage).
- [x] 2.4 `bash -n` on test + every line validated against strict IPv4-CIDR shape → no malformed line.
- [x] 2.5 NO `cloud-init.yml` edit (templated via `cron_egress_allowlist_cidr_b64` — verified).

## Phase 3 — Apply path (auto-on-merge)
- [x] 3.1 Confirmed `terraform_data.cron_egress_firewall` triggers_replace folds the CIDR hash (server.tf:729).
- [x] 3.2 Extended the server.tf post-apply assert (:827) to also require a `20.`/`4.` element (display-agnostic, expansion-safe).
- [x] 3.3 Verified `apply-web-platform-infra.yml` re-applies on merge (path filter `apps/web-platform/infra/**`).

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
