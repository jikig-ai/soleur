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
- [x] 2.2 Cattle cloud-init parity — 5-item gap CLOSED. **Part 1 (commit 828a27f62):** orphan_reaper + bwrap-userns sysctl baked (image host_script_files + bootstrap install + cloud-init enable), byte-identical to retained SSH heredocs (fresh-boot-parity.test.sh, mutation-verified), baked-set 30→35, .dockerignore + size cap held. **Part 2 DONE:** the 3 probes (private_nic_guard, zot_consumer, git_data) — scripts+units baked (3 .sh + 6 units, baked-set 35→45 incl. the new `web-probe-envwrite.sh`); env files written on fresh boot by the baked `web-probe-envwrite.sh`, invoked by cloud-init with the per-host token/EXPECTED_IP/endpoints (SSH remote-exec RETAINED for web-1 until Phase 5). Env-file **key-set parity** across both writers guarded (fresh-boot-parity.test.sh §12, 77/0). Units byte-identical by construction (both paths deliver the same repo files via `provisioner "file"`). WEB_GZIP_BUDGET re-baselined 22,700→23,700 (measured 23,168; the env-writer invocation is irreducibly inline — bulk logic baked). Also fixed a latent `pipefail`+`grep -q` SIGPIPE flake in `journald-config.test.sh` (my baked-set additions widened the awk stream past the early match). Security settled (scoped token = zero marginal exposure).

## PR-1 — Phase 3: Birth fresh cattle web-2 (out-of-band standby, weight 0, replicas=1 held)

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- "out-of-band standby" is the ADR-141 architectural term for a weight-0 health-monitored host, NOT
     manual provisioning. All web-2 birth + inngest allowlist propagation route through gated
     workflow_dispatch (apply-web-platform-infra.yml / inngest-host-replace), never SSH/dashboard. -->
- [x] 3.1 Added `web-2` to `var.web_hosts` (`cpx32`/hel1/10.0.1.11 per 0.2); rewrote retirement comments (variables.tf `web_hosts`, server.tf fail2ban-scope + deleted-gate pointer, inngest-host.tf header). for_each fan-out confirmed via `terraform validate` (server/network/web-probe heartbeats+URLs/volume+attachment). **LUKS-backed volume DEFERRED to Phase-4** per ADR-141 R3 (CTO): web-2's for_each volume is plaintext-but-EMPTY pre-flip (holds no user data; the additive LUKS is a web-1 singleton, ADR-119); the fresh-boot LUKS path lands in the Phase-4 disposability-proof PR (#6931), made fail-CLOSED by the gate's WORKSPACES_LUKS precondition (coupling #2). **AC5 REFRAMED**.
- [x] 3.2 **AC9 REFRAMED (ADR-141 R1, CTO — binding parent ADR-068 §(c)(3)):** NO off-host `web-2.app.soleur.ai/health` monitor (web-2 has zero public ingress; off-host readyz architecturally rejected; a per-host external monitor was already deleted as false-521). Off-ingress health = the composite already in fan-out: 2 outbound heartbeats (`web_nic_guard`/`web_zot_consumer`, absence-alerted) + `SOLEUR_FRESH_BOOT_READY` marker depth fields (volume+luksOpen/vector-installed — app-readiness, not port-open) + Vector log-count>0 via `scripts/betterstack-query.sh`. On-host `/internal/readyz` deferred to the ADR-068 orchestrator.
- [x] 3.3 `inngest-host.tf` `web_host_private_ips` → `"10.0.1.10,10.0.1.11"` (§6b green). AC6-SAFE: the push-apply's explicit `-target=` allow-list excludes `hcloud_server.inngest`, so this `.tf` change forces no inngest replace at merge; the private-net allowlist reaches the live host through the `inngest-host-replace` gated `workflow_dispatch` (#6608), the IaC-routed path — before the Phase-4 soak.
- [x] 3.4 `WEB_HOST_PRIVATE_IPS` in `web-platform-release.yml` → `"10.0.1.10,10.0.1.11"` (deploy fan-out reaches web-2 so its container stays release-current + health-monitored — deploy-membership ≠ serving-membership).
- [x] 3.5 **Rebuilt the #6575 anti-pooling gate** as `lb-weight-gate.sh` + `.test.sh` (ADR-141 R2, CTO). Fail-closed serving-weight TOP-GUARD (weight==0/∉rotation PASSES — fixes the #6575 polarity flaw; weight>0 pre-flip runs Conditions A+B+the new WORKSPACES_LUKS precondition, FAILs = AC7) + static committed-HCL Condition C (dns.tf web-1-only, connector excludes web-2, no LB pools web-2). 100/0, mutation-verified (neutering coupling #2 or the weight guard → RED), registered in `infra-validation.yml`.
- [x] 3.6 Roster-coupled parity guards GREEN — the plan said "2" but the grep-enumerated work-list is **3**: `inngest-host.test.sh §6b` (41/0), `web-hosts-fanout-parity.test.sh` (1/0), AND `cutover-inngest-workflow.test.sh` H1 (`cutover-inngest.yml CUTOVER_HOSTS`, 227/0 — its comment already anticipated web-2).

## PR-1 — Phase 4: Disposability proof (volume-preserving reprovision, non-prod data)

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
- [~] 4.1 **DEFERRED to the Phase-4 disposability-proof PR (#6931)** per ADR-141 R3 (CTO). The populated-LUKS-volume reprovision proof (detach → recreate → reattach → `luksOpen`-never-`luksFormat` via `blkid -o value -s TYPE` discriminator → data intact) IS the guest-side fresh-boot LUKS path the CTO deferred — it is only exercised on POPULATED data in the de-pet rebuild, and touching the sole-copy boot path in this PR (already carrying the gate + cattle-parity) is the highest blast radius. #6931 also owns the two-mechanism topology reconciliation (additive singleton vs fresh-boot for_each). The defer is fail-CLOSED: the anti-pooling gate's WORKSPACES_LUKS precondition (coupling #2) blocks any flip to a not-yet-LUKS'd web-2.
- [x] 4.2 `prevent_destroy = true` on `hcloud_volume.workspaces` (per-host block volumes — pure safety, not in the push-apply `-target` allow-list, does not touch the boot path). **Sole-copy `hcloud_volume.workspaces_luks` prevent_destroy + the off-host snapshot/restore-test DEFERRED to #6931**: prevent_destroy on the LUKS singleton collides with the `apply_target=workspaces-luks-recut` `-replace` escape hatch, and the snapshot is part of the disposability-proof reprovision flow (topology-split-dependent).
- [x] 4.3 Enrolled the web-2 out-of-band soak (N=7d): `scripts/followthroughs/web2-standby-soak-6459.sh` (self-checking Better Stack heartbeats API — reads web-2's 2 per-host beats; PASS=both `up`, FAIL=dark #6538, TRANSIENT=not-yet-born; mirrors `l3-probe-armed-6438.sh`) + `<!-- soleur:followthrough … earliest=2026-08-14 secrets=BETTERSTACK_API_TOKEN -->` directive + `follow-through` label on #6459. `BETTERSTACK_API_TOKEN` was ALREADY wired into `scheduled-followthrough-sweeper.yml` (shared with l3-probe-armed).

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
