---
feature: web-active-active-iac
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-07-24-feat-web-active-active-cluster-iac-plan.md
pr_split: "PR-1 = Phases 0-4; PR-2 = Phase 5 (gated on PR-1 soak)"
date: 2026-07-24
---

# Tasks: Active-Active Web Cluster via IaC

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- All infra routes through Terraform + cloud-init + gated workflow_dispatch (required-reviewer
     environments). "Maintenance-window" / "operator" = a gated dispatch, NOT SSH/manual provisioning.
     See the plan's ## Infrastructure (IaC) section. No ssh root@, no dashboard steps. -->

> Derived from the finalized (post 6-agent-review) plan. **PR-1 = Phases 0-4** (cluster + out-of-band
> web-2 standby + populated-volume disposability proof + rebuilt anti-pooling gate). **PR-2 = Phase 5**
> (de-pet web-1), gated on the PR-1 7-day soak. Concurrent serving + LB = Phase 6 (external, out of scope).

## PR-1 — Phase 0: ADR + live-stock + data-layer contract

- [x] 0.1 Author ADR-141 (`adopting`) — decided /workspaces failover mechanism (volume-preserving reprovision, D5); amends `hr-prod-host-config-change-immutable-redeploy` + ADR-103; extends ADR-068. Ordinal re-verified free 2026-07-24.
- [x] 0.2 Live Hetzner stock probe (2026-07-24) — **cx33 (id-115) and cax11 (id-45, ARM) unorderable in all 3 EU DCs**; **web-2 → cpx32** (4c/8g x86, orderable everywhere). Verdict recorded in ADR-141 §Live stock probe + §D1.
- [x] 0.3 C4 update — `model.c4` hetzner container carries the ADR-141 note (fleet stays single-host until web-2 born in Phase 3; no LB element); `model.likec4.json` regenerated; `c4-code-syntax.test.ts` + `c4-render.test.ts` green (23/23). NOTE: the full 2-host relabel of :186/:413 lands in **Phase 3** when web-2 is actually provisioned (editing them now would assert a live 2-host fleet that does not yet exist).

## PR-1 — Phase 1: Fresh-boot readiness gate (#6459 precondition)

- [x] 1.1 Fresh-boot readiness assertions — folded into the marker's `token` field (fail-loud, no silent Doppler/env fallback) + its behavioral test; user_data cap held via re-baseline (helper body baked, 0 user_data). Built against `main` baseline (the `feat-one-shot-6712-...` coherence-preflight is unmerged/unpushed — stayed architecturally compatible, no hard dep).
- [x] 1.2 `SOLEUR_FRESH_BOOT_READY` marker (`soleur-fresh-boot-ready`, baked) emitted as the LAST cloud-init item AFTER Vector; fields ready/stage/token/vector/volume/luks/reason; **900s** quantified boot-window (derivation in-helper); dual-channel Vector-INDEPENDENT (direct-curl Better Stack + Sentry); discoverability via `betterstack-query.sh` (NO ssh). Hybrid guard `fresh-boot-ready.test.sh` (structural + behavioral-extraction per reason branch), registered in `infra-validation.yml`. Commit 38b9bfe3c.

## PR-1 — Phase 2: Complete cattle cloud-init parity artifact (FORWARD of web-2 birth)

- [x] 2.1 Reconciled + pinned: **17 terraform_data siblings** (16 SSH + 1 local-exec); "11/12/7" all stale/partial (target-parity's "7" is a subset, dynamic floor 10, true count 16). **5-item fresh-boot gap**: private_nic_guard, zot_consumer_probe, git_data_probe, orphan_reaper, docker_seccomp_config sysctl-half. Security fork collapsed (scoped probe token adds zero exposure — host user_data already carries full-prd token). Full table + ADR-136 note: [phase-2-provisioner-reconciliation.md](phase-2-provisioner-reconciliation.md).
- [ ] 2.2 Author the complete cattle cloud-init encoding every reconciled provisioner + Phase-1 readiness assertions — the artifact web-2 is born from AND that rebuilds web-1.

## PR-1 — Phase 3: Birth fresh cattle web-2 (out-of-band standby, weight 0, replicas=1 held)

- [ ] 3.1 Add `web-2` to `var.web_hosts` (orderable type/DC from 0.2); rewrite retirement comments (`variables.tf:100-108`, `server.tf:115`, `inngest-host.tf:11`); confirm for_each fan-out (server/network/web-probe/volume); LUKS-backed volume.
- [ ] 3.2 Out-of-band `/health` probe (`web-2.app.soleur.ai/health`) asserts app-readiness + Vector-shipping depth (NOT port-open/200-from-proxy).
- [ ] 3.3 #6608 SEPARATE window: derive `inngest-host.tf` `web_host_private_ips` from `var.web_hosts` via `inngest-host-replace` dispatch; land BEFORE the Phase-4 soak.
- [ ] 3.4 Populate `WEB_HOST_PRIVATE_IPS` in `web-platform-release.yml`; confirm `fan_out_to_peers` reaches web-2.
- [ ] 3.5 **Rebuild the deleted #6575 anti-pooling gate** — fail-closed: web-2 serving-weight/rotation membership == 0 until Phase-3 flip. Unit-test the FAIL case.
- [ ] 3.6 Update the 2 roster-coupled parity guards (`inngest-host.test.sh §6b`, `web-hosts-fanout-parity.test.sh`) → green.

## PR-1 — Phase 4: Disposability proof (volume-preserving reprovision, non-prod data)

- [ ] 4.1 Rebuild a host with a POPULATED LUKS volume: detach → recreate host (same key) → reattach → `luksOpen` (never `luksFormat`) guarded by LUKS-header-presence check → data intact.
- [ ] 4.2 `prevent_destroy` on `hcloud_volume.workspaces`; off-host snapshot taken + restore-tested before any reprovision.
- [ ] 4.3 Enroll the web-2 out-of-band soak (N=7d): `scripts/followthroughs/web2-standby-soak-6459.sh` + directive + `follow-through` label on #6459 + wire secrets into `scheduled-followthrough-sweeper.yml`.

## PR-1 — Ship

- [ ] Verify all Pre-merge ACs (1-10) green; runtime proofs (11-15) enrolled as post-merge/gated-dispatch.
- [ ] `/soleur:review` → `/soleur:ship`.

## PR-2 — Phase 5: De-pet web-1 (gated on PR-1 soak; own PR)

- [ ] 5.1 Confirm Phase-2 cattle cloud-init reaches full parity for web-1 (verify each `file` provisioner target dir exists).
- [ ] 5.2 Precondition gate: write-quiesce/read-only window → off-host snapshot + restore-verify → assert `hcloud_volume.workspaces["web-1"]` preserved (snapshot-verified, NOT "count un-pushed"); failure path = abort + resume on un-reprovisioned web-1. **Dry-run test**: synthetic populated volume, prove reprovision refused until snapshot verified.
- [ ] 5.3 Ordered diffs: (a) drop `placement_group_id` from `ignore_changes` FIRST (drained-host reboot; `terraform-target-parity.test.ts` green); (b) reprovision `web["web-1"]` fresh cattle (volume detach→reattach→luksOpen, key RETAINED); (c) then drop `[user_data]` + provisioners together.

## Notes
- **web-1 `for_each` key is RETAINED** (29 refs/6 files) — de-pet is a lifecycle change, never a key rename.
- **The volume, not the host, is the SOLE COPY** — luksOpen-not-reformat + snapshot + `prevent_destroy` are load-bearing.
- Concurrent serving (Phase 6) is gated on #6570 (git-data root blocker) + ADR-068 Phase-3 — out of scope.
