# Tasks — fix(infra) webhook.service ReadWritePaths `/var/lib/inngest` 226/NAMESPACE deadlock (#6090)

Plan: `knowledge-base/project/plans/2026-07-12-fix-webhook-readwritepaths-inngest-namespace-deadlock-plan.md`
Lane: cross-domain (TR2 fail-closed default — no spec.md on branch; change is genuinely single-domain infra)

## Phase 1 — RED: regression test (lock the invariant before fixing)
- [x] 1.1 Add assertions to `apps/web-platform/infra/inngest.test.sh` (confirmed host; CI-registered infra-validation.yml:299):
  - [x] 1.1.1 `cloud-init.yml` webhook.service `ReadWritePaths` contains `-/var/lib/inngest` and NOT the bare ` /var/lib/inngest ` token
  - [x] 1.1.2 standalone `webhook.service` `ReadWritePaths` contains `-/var/lib/inngest`
  - [x] 1.1.3 lockstep parity: the two `ReadWritePaths=` token lists are byte-identical (modulo YAML indent)
- [x] 1.2 Ran the test; confirmed 4 FAILs on the current mandatory form (`cq-write-failing-tests-before`)

## Phase 2 — GREEN: apply the `-` prefix + comment alignment (both lockstep copies)
- [x] 2.1 `apps/web-platform/infra/cloud-init.yml` webhook.service RWP → `-/var/lib/inngest`; comment updated with the "optional; becomes real ReadWritePath once inngest-bootstrap creates it" rationale (#6090)
- [x] 2.2 `apps/web-platform/infra/webhook.service` RWP → `-/var/lib/inngest`; folded inngest into the vector `-`-optional rationale, cited #4257 + #6090
- [x] 2.3 Re-ran Phase 1 test → GREEN (86/86)

## Phase 3 — Comment-accuracy sweep (severed causal chain)
- [x] 3.1 `apps/web-platform/infra/soleur-host-bootstrap.sh` — annotated the 226/NAMESPACE clause as severed by the `-`-optional fix (kept GHCR rationale)
- [x] 3.2 `apps/web-platform/infra/soleur-host-bootstrap-observability.test.sh` — same annotation (69/69 still green)

## Phase 4 — Verify death-stage emit coverage (observability, no SSH)
- [x] 4.1 Confirmed: `cloud-init.yml:581` `soleur-wait-ready port 9000 webhook_bound || exit 1` fires immediately after the webhook enable (:578) — a named baked-DSN beacon already covers the abort; no anonymous abort, no new emit needed

## Phase 5 — Full-suite + AC verification (pre-merge)
- [x] 5.1 `inngest.test.sh` 86/86; `infra-config-apply.test.sh` 63; `infra-config-install.test.sh` 29; observability 69; firewall-9000 1; cron-egress-firewall 197 + 6 more sibling infra suites — all green (0 failures). cloud-init schema failure is pre-existing (Terraform template; origin/main fails identically)
- [ ] 5.2 Walk AC1–AC8 (see plan); PR body `Closes #6090`

## Phase 6 — Post-merge: fresh web-2-recreate + off-host green (automated)
- [ ] 6.1 `gh workflow run apply-web-platform-infra.yml -f apply_target=web-2-recreate -f reason='#6090 verify webhook RWP inngest -optional'`
- [ ] 6.2 Off-host acceptance step (`apply-web-platform-infra.yml:1209`): web-1 deploy-status `reason` flips `ok_peer_fanout_degraded` → `ok`; web-2 `:9000` bound (AC10)
- [ ] 6.3 No `stage=webhook_bound` fatal in Sentry for the recreate boot (AC11)
