# Tasks: web-2 fresh-boot guest-side LUKS path (#6931)

Plan: `knowledge-base/project/plans/2026-10-01-feat-web-host-fresh-boot-luks-path-plan.md`
Write each phase's RED tests first (`cq-write-failing-tests-before`). Lane: cross-domain. Threshold: single-user incident.

## Phase 0: Preconditions and characterization (no production code)

- [x] 0.1 Re-read PR #9348 (PR B); settle merge order; rebase on it before touching lines it owns — PR #9348 is an empty draft (0 files); proceeded, textual conflict on the `for_each`/ledger lines resolved by whoever merges second
- [x] 0.2 FIRST (hard fork): confirm via provider docs (context7) that omitting `format` yields a raw volume and `format` is ForceNew — MEASURED: live `soleur-web-platform-data-web-2` (id 106466179) is `ext4`, attached; `workspaces_luks` volumes read format null. Provider fact CORRECTED: `format` is NOT ForceNew on hcloud 1.63.0 (in-place `ext4 -> null`; `ignore_changes` => No changes), tested offline
  - [x] 0.2.1 Read the live web-2 volume's `format` from the Hetzner API (read-only); re-scope D2/P7 if it is unformatted
- [x] 0.3 Characterize `luks-monitor.sh` on an empty-standby fixture; decide whether a `standby` profile switch is needed — characterized by reading the probe: the shared heartbeat push would mask a dead web-1 probe, so a `standby` profile (skip the push) was added; other arms hold on an empty standby
- [ ] 0.4 Verify the `destroy-guard-filter-web-platform.jq` allow-set facts; choose the P7 destroy mechanism from the measurement — MOVED to the P7 follow-up issue (the destroy mechanism is only needed for the rebirth operation)
  - [ ] 0.4.1 Fix the emptiness evidence (attached server + labels; Better Stack host_metrics used-bytes ceiling over 7 days; never pooled); confirm Vector ships the field — MOVED with 0.4
- [x] 0.5 Verify `luks-monitor-token-refresh.sh` line shape against the cloud-init-written `DOPPLER_TOKEN=` line
- [x] 0.6 Add the allowlist regression test (no entry matches `169.254.0.0/16`)
- [x] 0.7 Prove the `curl --aws-sigv4` escrow form against the real escrow bucket scope and Ubuntu 24.04's curl; pin the output — verified on Ubuntu 24.04's packaged curl 8.5.0 AND 8.22 against an independent SigV4 verifier (scope auto/s3): HEAD 404 -> PUT 200 -> HEAD 200 with matching length. NOT yet against R2 itself: the live proof is the P7 evidence `escrow=ok`
- [x] 0.11 Verify `workspaces-boot-unlock.test.sh` and `store-vs-data-mount-parity.test.sh` against the baked path (no mount-source resolution block in the provisioner)
- [ ] 0.9 Name the CI vehicle for the pre-merge no-change plan run and pin its artifact — MERGE-EFFECT measured offline instead (plan against a state shaped like the live volume: No changes with `ignore_changes`, in-place update without); the CI push-apply plan on merge is the live confirmation
- [ ] 0.10 Pass `image_tag` explicitly for the rebirth; add the image content-hash vs `host_scripts_content_hash` pre-dispatch check — MOVED to the P7 follow-up issue (the explicit `image_tag` + content-hash pre-dispatch check belong to the rebirth dispatch); the `image_tag` help text and error text were updated here
- [x] 0.8 Derive the allow-list work-list with `git grep` (`-target=`, `workspaces_luks_boot_token`) and extend Files to Edit

## Phase 1: The provisioner

- [x] 1.1 RED: `workspaces-luks-provision.test.sh` (raw, crypto_LUKS, ext4, GPT, foreign signature, blkid rc 4/8, empty key, Doppler down and retry ladder, second run, xtrace, no `isLuks`, crash-after-luksFormat intent-file recovery, blank mapper without intent file, device state change before luksFormat, escrow PUT/HEAD failures non-fatal)
- [x] 1.2 `workspaces-luks-provision.sh`: config, device, discriminate, format, open, escrow, wire, result arms
  - [x] 1.2.1 `_may_format()` and `_may_format_fs()` chokepoints re-run immediately before each destructive call
  - [x] 1.2.3 Intent file `/var/lib/soleur/workspaces-luks-formatting` before luksFormat, removed after mkfs; 300 s device wait; ~5 min Doppler retry ladder; escrow non-fatal
  - [x] 1.2.2 Canonical crypttab/fstab/drop-in lines byte-identical to `local.workspaces_boot_unlock_*`
- [x] 1.3 Canonical-lines byte parity as a section of `fresh-boot-parity.test.sh`
- [x] 1.4 Guard 1 mutation matrix rows 1-10 driven RED/GREEN

## Phase 2: Wiring (bake, bootstrap, cloud-init)

- [x] 2.1 `soleur-host-bootstrap.sh`: install baked files, replace the structural-gate crypttab write, tighten `soleur-fresh-boot-ready` (`luks=` gated, `luks_arm=`, `escrow=`)
- [x] 2.2 `cloud-init.yml`: env-file write + one helper call + hard gate BEFORE `mkdir -p /mnt/data/workspaces` (and the plugin seed); state the byte budget; `DOPPLER_TOKEN=` line (fresh-host token) in `/etc/default/luks-monitor`
- [x] 2.3 `server.tf` `host_script_files` + `Dockerfile` COPY; user_data map `workspaces_luks_fresh_boot_token` (new `doppler_service_token.workspaces_luks_fresh_boot`, no create_before_destroy)
- [x] 2.4 Extend `fresh-boot-parity.test.sh`, `fresh-boot-ready.test.sh`; re-baseline `cloud-init-user-data-size.test.ts`

## Phase 3: Terraform topology and the #6964 invariant

- [x] 3.1 `hcloud_volume.workspaces`: drop `format`, add `ignore_changes = [format]`, keep `prevent_destroy`; test pins both halves
- [ ] 3.2 Plan run with the push-apply `-target` set against live state shows no change to any `hcloud_volume`/`hcloud_server` address — measured offline (see 0.9); no change to any hcloud_volume address is planned
- [x] 3.3 `web-host-birth-gate.sh`: raw-volume requirement arm + named `web-1` refusal; fixtures from a real `terraform show -json`
- [x] 3.4 Guard 2 mutation matrix rows 1-7; update `image_tag` help text (required for a fresh birth)

## Phase 4: Verification vehicle

- [x] 4.1 Bake the `luks-monitor` family on fresh hosts (profile switch only if 0.3 requires it); add `boot_id` to probe and readiness rows — profile switch was required and added; boot_id on probe and readiness rows; host= on the readiness row
- [ ] 4.3 Ledger row `luks` + `live_verification: available`, `live_coverage_floor` 3; `lint-encryption-posture.py` green; bump `BASELINE_DECLARED_PROBES` — DEFERRED with the live conversion: the ledger row stays a truthful `plaintext-exception` (evidence rewritten, no false `luks` claim), `live_coverage_floor` unchanged at 2; `BASELINE_DECLARED_PROBES` bumped 39 -> 40

## Phase 5: The marker writer

- [x] 5.1 `doppler_config` `prd_workspaces_luks_marker` + write-scoped token + GitHub secret in Terraform; add all new resources to the push allow-list and `terraform-target-parity.test.ts`
- [x] 5.2 `workspaces-luks-verify.yml` web-2 leg: positive-count green joined on `boot_id`, write-if-absent, delete on negative evidence, untouched + failing run on query failure
- [x] 5.3 Guard 3 mutation matrix rows 1-11 in the workflow test

## Phase 6: Records and wording

- [x] 6.1 ADR-263 (via `soleur:architecture`) carrying the supersession, one-line pointers in ADR-143 and ADR-119; re-verify the ordinal across every pushed branch AND origin/main
- [x] 6.2 `model.c4` prose (workspacesVolume, hetzner, doppler edge) + c4 tests
- [x] 6.3 `workspaces-luks.tf` / `server.tf` comments; stale-citation sweep ("ADR-141 D3", "ADR-142 D3"); reopen.service header — comments rewritten in workspaces-luks.tf / server.tf / reopen.service / lb-weight-gate.sh / apply workflow messages
- [x] 6.4 `web-host-replace.md` + replace-gate text; `nfr-register.md`; 2026-07-24 plan AC5 superseded marker
- [x] 6.5 Article 30 register + compliance posture rows (conditioned on the live event)

## Phase 7: Live conversion (post-merge, gated dispatches) — SPLIT OUT as its own PR/operation (follow-up issue); not part of this PR

- [ ] 7.1 Push apply creates the new token/secret; image from the merge commit published
- [ ] 7.2 Single-use web-2 volume rebirth (API delete first, then state removal; idempotent; delete the workflow after use); then `web-host-create` with the explicit new image tag
- [ ] 7.3 Evidence rows: `luks=1 luks_arm=formatted escrow=ok`; workflow-issued reboot -> new `boot_id`, `opened`/`noop`; file a tracking issue for the populated-volume replace proof
- [ ] 7.4 Follow-through: `scripts/followthroughs/web2-luks-live-6931.sh` + tracker directive; re-capture the web-2 host-key pin

## Deferrals (filed)

- #9356 populated-volume replace proof; #9357 T2 keyed migration; #9358 marker sourcing in the flip orchestrator
