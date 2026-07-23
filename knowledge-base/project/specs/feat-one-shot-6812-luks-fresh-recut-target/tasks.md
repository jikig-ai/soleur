# Tasks — gated `workspaces-luks-recut` fresh-target mechanism (#6855, ref #6812)

Plan: `knowledge-base/project/plans/2026-07-23-feat-workspaces-luks-recut-fresh-target-plan.md`
Lane: single-domain · Threshold: single-user incident (CPO sign-off + user-impact-reviewer at /review)

## Phase 0 — Preconditions (verify, no code)
- [ ] 0.1 `git show origin/main:apps/web-platform/infra/workspaces-luks.tf` — confirm no `format` attr; attachment refs `hcloud_volume.workspaces_luks.id`.
- [ ] 0.2 Re-read `apply-web-platform-infra.yml` `git_data_host_replace` (:1654) + `workspaces_luks_cutover` (:1877) + `tests/scripts/lib/workspaces-luks-cutover-gate.sh`.
- [ ] 0.3 Confirm `plugins/soleur/test/terraform-target-parity.test.ts:453-469` strip pattern + `:616-619` exclusions.

## Phase 1 — Destroy-guard gate lib (test first)
- [ ] 1.1 Create `tests/scripts/test-workspaces-luks-recut-gate.sh` — synthesized plan-JSON fixtures; GREEN (volume+attachment replace) + RED mutations (a)-(j) per plan Phase 1.
- [ ] 1.2 Create `tests/scripts/lib/workspaces-luks-recut-gate.sh` — `workspaces_luks_recut_gate <plan-json>`; require `luks_volume_replaced` (delete AND create) + `luks_attachment_created`; forbid `old_volume_touched`/`old_attachment_touched`/`web1_server_touched`/`luks_passphrase_touched` (4-verb incl. create)/`out_of_scope`; `resource_deletes` excludes the volume+attachment; parse-validate all counters; fail-closed on bad JSON.
- [ ] 1.3 `bash tests/scripts/test-workspaces-luks-recut-gate.sh` GREEN.

## Phase 2 — Gated apply_target job
- [ ] 2.1 `apply-web-platform-infra.yml`: add `workspaces-luks-recut` to the `apply_target` choice `options:` + a `confirm` string input (`RECUT-WORKSPACES-LUKS`).
- [ ] 2.2 New `workspaces_luks_recut` job: mirror `workspaces_luks_cutover` scaffolding; add `environment: workspaces-luks-cutover`, `concurrency: web-1-swap`, a `confirm`-token preflight step.
- [ ] 2.3 Plan step: `terraform plan -replace='hcloud_volume.workspaces_luks' -target='hcloud_volume.workspaces_luks' -target='hcloud_volume_attachment.workspaces_luks'` → `show -json` → source recut gate → abort on fail.
- [ ] 2.4 Apply step: `terraform apply tfplan` + post-apply jq backstops (live vol/attachment/web-1 = 0 actions; LUKS volume delete+create; attachment create) + Dispatch summary. No SSH, no reboot.
- [ ] 2.5 `actionlint` the workflow; `bash -c` the extracted recut `run:` snippets.

## Phase 3 — Parity-test registration
- [ ] 3.1 `plugins/soleur/test/terraform-target-parity.test.ts`: add `workspaces_luks_recut` strip clause (mirror git-data/registry, :453-469).
- [ ] 3.2 Run the parity suite (vitest per package config) — GREEN.

## Phase 4 — Docs (ADR + runbook + C4 check)
- [ ] 4.1 ADR-119: add 2026-07-23 addendum (recut-after-orphaned-volume; crypto_LUKS no-op explanation; passphrase reuse; discards accepted window). Keep `status: adopting`.
- [ ] 4.2 Runbook `workspaces-luks-cutover-6604.md`: add Sequence **Step 0 (recut)** with the exact `gh workflow run … -f apply_target=workspaces-luks-recut -f confirm=RECUT-WORKSPACES-LUKS` invocation; correct the "re-cut luksFormats that device" wording for the already-LUKS case.
- [ ] 4.3 Read `diagrams/{model.c4,views.c4,spec.c4}`; confirm no new actor/system/store/relationship; cite the enumeration in the ADR addendum.

## Phase 5 — Full-suite gate
- [ ] 5.1 `test-all.sh` (incl. any orphan `-target` scope-guard suite) GREEN.
- [ ] 5.2 AC sweep against plan §Acceptance Criteria (Pre-merge AC1-AC8).

## Out of scope (operator, downstream, gated — NOT this PR)
- Dispatching `apply_target=workspaces-luks-recut` (the destructive replace) — operator approves the environment gate.
- The freeze (`workspaces-luks-cutover.yml`), the verify, and closing #6812.
- The 7-day soak + plaintext wipe (blocked on #6808).
