# Tasks — feat-one-shot-11445-web2-ci-ssh-preauth (#11445)

Plan: `knowledge-base/project/plans/2026-10-28-infra-web2-ssh-preauth-after-rebirth-plan.md`

## Phase 1 — Record correction + probe artifact

- [ ] 1.1 Comment on #11445 with the root-cause correction (run 40744937376 `apply` log: `Host key for web-2 has changed and you have requested strict checking. / Host key verification failed.` — stale pin, not auth rejection). (AC6)
- [ ] 1.2 Create `scripts/probes/web2-ssh-pin-current.sh`: asserts exactly one non-comment `ecdsa-sha2-nistp256` key line in `apps/web-platform/infra/web-2-ssh-host-key.pub` AND the `# fingerprint:` header ≠ `SHA256:prjbMlCCSCqiA/C03Ww4VZK1jcB+fx8/wG3Dp4rfZhE`; prints `PIN_CURRENT`, exits 1 with named reason otherwise. Pure bash/grep/awk (Check-10 sandbox). (AC2)
- [ ] 1.3 Verify the probe reds on the CURRENT stale pin before proceeding. (AC2)

## Phase 2 — Operator steps (admin-IP egress)

- [ ] 2.1 Operator executes `bash scripts/capture-web-2-host-key.sh <web-2-public-ipv4>` in this worktree (egress ∈ `var.admin_ips`; `/soleur:admin-ip-refresh` first if not allowlisted). Commit the regenerated `apps/web-platform/infra/web-2-ssh-host-key.pub`. (AC1)
- [ ] 2.2 Cross-check: regenerated `# fingerprint:` header equals `SHA256:OB3/fH+fWhoTolCCx9rNMtuW0shPUONHNbhYxRFyqic` (the key web-2 offered in run 40744937376). (AC1)
- [ ] 2.3 Operator read-only diagnostic session to web-2 over the admin-IP tcp/22 rule: (a) `/root/.ssh/authorized_keys` vs `terraform output -raw ci_ssh_public_key_openssh`; (b) `journalctl -u ssh` window grep for `Failed publickey` vs `[preauth]` closes; (c) `cloud-init status --long`. Record all three on #11445. (AC4)

## Phase 3 — Conditional: IaC twin (only if 2.3 shows pubkey absent)

- [ ] 3.1 Add `terraform_data.root_authorized_keys_web2` to `apps/web-platform/infra/ci-ssh-key.tf` (web-2 host, `local.web_2_ssh_host_key`, `private_key`/`agent` dual-mode, `%RAND%` script_path, 15m timeout, `triggers_replace` = pubkey hash + server_id). (AC5)
- [ ] 3.2 Update `plugins/soleur/test/terraform-target-parity.test.ts` (`EXCLUSION_ALLOWLIST` + census). (AC5)
- [ ] 3.3 Update `apps/web-platform/infra/web-host-provisioner-parity.test.sh` EXT_RESIDENCE entry. (AC5)
- [ ] 3.4 Update `apps/web-platform/infra/server.tf` census/recovery-note comments. (AC5)
- [ ] 3.5 Run the parity + target-parity suites; `terraform plan` shows the twin create-only. (Test Scenario 3)
- [ ] 3.6 Operator step: `cd apps/web-platform/infra && doppler run -p soleur -c prd_terraform --name-transformer tf-var -- terraform apply -target=terraform_data.root_authorized_keys_web2 -input=false`; capture authorized_keys grep output on #11445. (AC5)

## Phase 4 — Verify + close

- [ ] 4.1 Run the C4 three-file read (`model.c4`, `views.c4`, `spec.c4`) and cite the checked actors/systems/relationships (plan §ADR/C4).
- [ ] 4.2 Merge the PR; confirm `apply-web-platform-infra.yml` merge-run passes `SSH forward to web-2` + runs `Terraform apply (SSH-provisioned resources, over the bridge)` non-skipped. (AC3)
- [ ] 4.3 Confirm `apply-deploy-pipeline-fix.yml` merge-run delivers `terraform_data.deploy_pipeline_fix_web2` (pin-hash re-fire). (AC3)
- [ ] 4.4 Close #11445 with the verification evidence; leave #10585/#6406/#11402 open (context issues, out of scope).
