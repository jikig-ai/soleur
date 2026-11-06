# Tasks — feat-one-shot-web1-pg-deferral-repark

Derived from `knowledge-base/project/plans/2026-10-27-fix-web1-placement-group-deferral-repark-plan.md`.

## Phase 1: Revert and verify locally

- [ ] 1.1 `git revert 6f530d494a` (squash commit, one parent — no `-m` flag). Edit the commit body to add the re-park rationale paragraph (reboot deferred until web-2 serves traffic; #6027 takes it on the drained host; epic #11181 item 5 remains pending).
- [ ] 1.2 Verify all four files restored:
  - [ ] 1.2.1 `grep -F 'ignore_changes = [user_data, ssh_keys, image, placement_group_id]' apps/web-platform/infra/server.tf`
  - [ ] 1.2.2 `grep -F 'ignore_changes = [user_data, ssh_keys, image, placement_group_id]' .github/workflows/apply-web-platform-infra.yml`
  - [ ] 1.2.3 `grep -F 'placement_group_id stays in ignore_changes' plugins/soleur/test/terraform-target-parity.test.ts`
  - [ ] 1.2.4 `grep -F 'currently UNREACHABLE' tests/scripts/lib/web-host-birth-gate.sh`
  - [ ] 1.2.5 `git show <revert-sha> --stat` touches exactly the four files and nothing else
- [ ] 1.3 `bun test plugins/soleur/test/terraform-target-parity.test.ts` — green including `lifecycle.ignore_changes includes placement_group_id` (baseline verified 2026-10-27: 314 pass / 0 fail pre-revert)
- [ ] 1.4 `cd apps/web-platform/infra && terraform init -backend=false && terraform validate`
- [ ] 1.5 (optional, creds permitting) canonical read-form `terraform plan` per plan Phase 1 step 5 — assert no `placement_group_id` diff on `hcloud_server.web`

## Phase 2: PR

- [ ] 2.1 Push branch; open PR `revert: "feat(infra): remove placement_group_id from web-1 ignore_changes (GA maintenance window, ADR-068 #5887)"` — first body line answers "does merging THIS alone mutate production?" then `Ref #11181` and `Ref #6027` only; no `Closes`/`Fixes`/`Resolves` in title or body
- [ ] 2.2 Set `semver:patch` label (touches `plugins/soleur/test/`)
- [ ] 2.3 Post-merge: watch the next `apply-web-platform-infra.yml` run — the wedge-clear may expose a downstream red that was masked behind the HALT
