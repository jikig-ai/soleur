# Tasks: re-pin web-2 SSH host key (Ref #9372)

Plan: knowledge-base/project/plans/2026-10-06-infra-repin-web-2-ssh-host-key-after-replacement-plan.md

## Phase 1: Core change

- 1.1 Copy the captured file over apps/web-platform/infra/web-2-ssh-host-key.pub (cp, no edits)
- 1.2 Verify byte identity with cmp against the captured file; git diff --stat shows only the pin file
- 1.3 Verify ssh-keygen -lf prints SHA256:8cJIrIjqGvsIniYIh2caQBBFN0pykjVQBFnY+ubMIWQ

## Phase 2: Hermetic tests (offline)

- 2.1 bash scripts/capture-web-2-host-key.test.sh (expect 17 passed)
- 2.2 bash apps/web-platform/infra/web-2-host-key-local.test.sh (pin-shape check incl. H1; expect 23 passed)
- 2.3 bash apps/web-platform/infra/web-ghcr-deny.test.sh
- 2.4 bash apps/web-platform/infra/web-host-provisioner-parity-mutation.test.sh
- 2.5 bun test plugins/soleur/test/ship-deploy-pipeline-fix-gate.test.ts

## Phase 3: PR

- 3.1 PR body from the plan draft: fingerprint, capture vantage, weak cross-check, workflow stays paused, Ref #9372 only, Changelog
- 3.2 Confirm no Closes/Fixes/Resolves for #9372 and no LUKS/reborn/encrypted claim in diff or body
- 3.3 Do not dispatch/enable/disable workflows, write Doppler, mint tokens, apply Terraform, or reboot
