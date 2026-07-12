# Tasks — fix(infra) webhook.service ReadWritePaths `/var/lib/inngest` 226/NAMESPACE deadlock (#6090)

Plan: `knowledge-base/project/plans/2026-07-12-fix-webhook-readwritepaths-inngest-namespace-deadlock-plan.md`
Lane: cross-domain (TR2 fail-closed default — no spec.md on branch; change is genuinely single-domain infra)

## Phase 1 — RED: regression test (lock the invariant before fixing)
- [ ] 1.1 Add assertions to `apps/web-platform/infra/inngest.test.sh` (confirm exact host at /work):
  - [ ] 1.1.1 `cloud-init.yml` webhook.service `ReadWritePaths` contains `-/var/lib/inngest` and NOT the bare ` /var/lib/inngest ` token
  - [ ] 1.1.2 standalone `webhook.service` `ReadWritePaths` contains `-/var/lib/inngest`
  - [ ] 1.1.3 lockstep parity: the two `ReadWritePaths=` token lists are byte-identical (modulo YAML indent)
- [ ] 1.2 Run the test; confirm it FAILS on the current mandatory form (`cq-write-failing-tests-before`)

## Phase 2 — GREEN: apply the `-` prefix + comment alignment (both lockstep copies)
- [ ] 2.1 `apps/web-platform/infra/cloud-init.yml:245` → `-/var/lib/inngest`; update comment L239-244 to the "optional; becomes real ReadWritePath once inngest-bootstrap creates it" rationale
- [ ] 2.2 `apps/web-platform/infra/webhook.service:45` → `-/var/lib/inngest`; fold inngest into the existing vector `-`-optional rationale (L32-34 + L40-44), cite #4257 + #6090
- [ ] 2.3 Re-run Phase 1 test → GREEN

## Phase 3 — Comment-accuracy sweep (severed causal chain)
- [ ] 3.1 `apps/web-platform/infra/soleur-host-bootstrap.sh:191-193` — annotate the 226/NAMESPACE clause as severed by the `-`-optional fix (keep GHCR rationale)
- [ ] 3.2 `apps/web-platform/infra/soleur-host-bootstrap-observability.test.sh:526` — same annotation

## Phase 4 — Verify death-stage emit coverage (observability, no SSH)
- [ ] 4.1 Confirm the `226/NAMESPACE` abort at the webhook enable step (`cloud-init.yml:578`) still surfaces a named baked-DSN emit (L581 `webhook_bound` beacon fires, or add a named emit at L578); no anonymous abort

## Phase 5 — Full-suite + AC verification (pre-merge)
- [ ] 5.1 `bash apps/web-platform/infra/inngest.test.sh` passes; `infra-config-apply.test.sh` + `infra-config-install.test.sh` still pass
- [ ] 5.2 Walk AC1–AC8 (see plan); PR body `Closes #6090`

## Phase 6 — Post-merge: fresh web-2-recreate + off-host green (automated)
- [ ] 6.1 `gh workflow run apply-web-platform-infra.yml -f apply_target=web-2-recreate -f reason='#6090 verify webhook RWP inngest -optional'`
- [ ] 6.2 Off-host acceptance step (`apply-web-platform-infra.yml:1209`): web-1 deploy-status `reason` flips `ok_peer_fanout_degraded` → `ok`; web-2 `:9000` bound (AC10)
- [ ] 6.3 No `stage=webhook_bound` fatal in Sentry for the recreate boot (AC11)
