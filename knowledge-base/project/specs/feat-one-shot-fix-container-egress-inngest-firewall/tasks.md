# Tasks — fix: allow container egress to the dedicated Inngest host (:8288)

Plan: `knowledge-base/project/plans/2026-07-11-fix-container-egress-inngest-dedicated-host-firewall-plan.md`
Branch: `feat-one-shot-fix-container-egress-inngest-firewall` · Epic: #6178 (Ref, not Closes) · lane: single-domain

## Phase 1 — Add the egress accept rule (the fix)

- [x] 1.1 In `apps/web-platform/infra/cron-egress-nftables.sh`, insert immediately **after**
  line 150 (host-gateway `:8288` accept) and **before** line 151 (allowlist accept):
  `add rule ip filter SOLEUR-EGRESS ip daddr 10.0.1.40 tcp dport 8288 accept comment "soleur-egress: dedicated inngest host (#6178)"`
- [x] 1.2 Leave the existing host-gateway `:8288` rule unchanged (no pruning).

## Phase 2 — Extend the static egress test suite (assertions first)

- [x] 2.1 In `apps/web-platform/infra/cron-egress-firewall.test.sh`, add a positive
  `assert_grep` (after line 154) for the dedicated-host rule — **paren-safe** ERE pattern,
  stop before `(#6178)`, escape dots: `ip daddr 10\.0\.1\.40 tcp dport 8288 accept comment "soleur-egress: dedicated inngest host`.
- [x] 2.2 Add a line-order assertion (mirror `RESOLVE_LINE < DROP_LINE`, lines 142–148):
  dedicated-host accept line number `<` default-drop line number.
- [x] 2.3 Do NOT remove the existing generic `'tcp dport 8288 accept'` assertion (line 154).

## Phase 3 — Harden runtime post-apply enforcement

- [x] 3.1 In `apps/web-platform/infra/cron-egress-postapply-assert.sh`, add — inside the
  assertion block, before `echo host-egress-ok`, next to the existing `inngest-8288-accept`
  sentinel (line ~54):
  `nft list chain ip filter SOLEUR-EGRESS | grep -q '10.0.1.40 tcp dport 8288 accept' || { echo 'ASSERT-FAILED: dedicated-inngest-8288-accept'; exit 1; }`
- [x] 3.2 Confirm the new sentinel keeps `SENTINEL_COUNT >= 15` and passes the
  UNGUARDED-command meta-check (the new `nft list` line carries its own `ASSERT-FAILED`).

## Phase 4 — Run the full referencing test set (all must exit 0)

- [x] 4.1 `bash apps/web-platform/infra/cron-egress-firewall.test.sh` (new PASSes reported; ~195 → higher, green).
- [x] 4.2 `bash apps/web-platform/infra/cron-egress-enforce-probe.test.sh` (no regression).
- [x] 4.3 `bash apps/web-platform/infra/ci-deploy.test.sh` (unrelated `8288` refs; no edit).
- [x] 4.4 `bash apps/web-platform/infra/soleur-host-bootstrap-observability.test.sh` (no edit).
- [x] 4.5 Re-run `git grep -l cron-egress apps/web-platform/infra/*.test.sh` to confirm the set is fully covered.

## Phase 5 — Ship

- [ ] 5.1 PR body: "part of epic #6178" (**Ref, not Closes**) + **corrected** delivery-context
  paragraph (see plan Delivery Context + `decision-challenges.md`): merging **fires**
  `apply-web-platform-infra.yml` (path-glob `apps/web-platform/infra/**`), re-provisions
  **web-1** via `terraform_data.cron_egress_firewall` (config-hash trigger) and **restarts its
  live firewall** (zero-downtime — gap-free restart + inert rule); **web-2** gets the rule on
  recreate; MUST merge before cutover recreates; inert until #6348. Open **ready, not draft**.
- [ ] 5.2 `ship` surfaces `decision-challenges.md` (corrected delivery premise) as an
  `action-required` issue so the operator knows the merge touches the live web-1 firewall.
