# Tasks — feat-one-shot-11445-web2-ci-ssh-preauth (#11445)

Plan: `knowledge-base/project/plans/2026-10-28-infra-web2-ssh-preauth-after-rebirth-plan.md`

## Phase 1 — Record correction + probe artifact

- [x] 1.1 Comment on #11445 with the root-cause correction (run 40744937376 `apply` log: `Host key for web-2 has changed and you have requested strict checking. / Host key verification failed.` — stale pin, not auth rejection). (AC6)
- [x] 1.2 Create `scripts/probes/web2-ssh-pin-current.sh`: asserts exactly one non-comment `ecdsa-sha2-nistp256` key line in `apps/web-platform/infra/web-2-ssh-host-key.pub` AND the `# fingerprint:` header ≠ `SHA256:prjbMlCCSCqiA/C03Ww4VZK1jcB+fx8/wG3Dp4rfZhE`; prints `PIN_CURRENT`, exits 1 with named reason otherwise. Pure bash/grep/awk (Check-10 sandbox). (AC2)
- [x] 1.3 Verify the probe reds on the CURRENT stale pin before proceeding. (AC2)

## Phase 2 — Operator steps (admin-IP egress)

- [x] 2.1 Operator executes `bash scripts/capture-web-2-host-key.sh <web-2-public-ipv4>` in this worktree (egress ∈ `var.admin_ips`; `/soleur:admin-ip-refresh` first if not allowlisted). Commit the regenerated `apps/web-platform/infra/web-2-ssh-host-key.pub`. (AC1) — ran from this session's egress `82.67.29.121` (∈ `ADMIN_IPS`); wrote `SHA256:OB3/…`, cross-check `no prior known_hosts entry`
- [x] 2.2 Cross-check: regenerated `# fingerprint:` header equals `SHA256:OB3/fH+fWhoTolCCx9rNMtuW0shPUONHNbhYxRFyqic` (the key web-2 offered in run 40744937376). (AC1) — byte-identical
- [x] 2.3 Operator read-only diagnostic session to web-2 over the admin-IP tcp/22 rule: (a) `/root/.ssh/authorized_keys` vs `terraform output -raw ci_ssh_public_key_openssh`; (b) `journalctl -u ssh` window grep for `Failed publickey` vs `[preauth]` closes; (c) `cloud-init status --long`. Record all three on #11445. (AC4) — pubkey EXACT_MATCH (root auth via DEPLOY_SSH_PRIVATE_KEY succeeded); `[preauth]` closes only; cloud-init `status: done`

## Phase 3 — Conditional: IaC twin (only if 2.3 shows pubkey absent)

- [ ] ~~3.1–3.6~~ **NOT TAKEN — evidence arm not reached.** Phase B proved the CI pubkey present and working (exact authorized_keys match + successful root auth); per the plan's decision rule, ship Phase A alone. Ruling: decision-challenges.md row 4, `Ruled by CTO agent, 2026-10-28` (pin-only on proven presence).

## Phase 4 — Verify + close

- [x] 4.1 Run the C4 three-file read (`model.c4`, `views.c4`, `spec.c4`) and cite the checked actors/systems/relationships (plan §ADR/C4). Read: `model.c4` (actors: founder/owner, third-party emailers, untrusted contributors; systems: CLI/Desktop + Devin Cloud surfaces — no infra host-key material modeled), `views.c4`, `spec.c4` — zero web-2/ssh/bastion/admin elements in any. No actor, system, container, data-store, or relationship added → no C4 impact.
- [ ] 4.2 Merge the PR; confirm `apply-web-platform-infra.yml` merge-run passes `SSH forward to web-2` + runs `Terraform apply (SSH-provisioned resources, over the bridge)` non-skipped. (AC3)
- [ ] 4.3 Confirm `apply-deploy-pipeline-fix.yml` merge-run delivers `terraform_data.deploy_pipeline_fix_web2` (pin-hash re-fire). (AC3)
- [ ] 4.4 Close #11445 with the verification evidence; leave #10585/#6406/#11402 open (context issues, out of scope).
