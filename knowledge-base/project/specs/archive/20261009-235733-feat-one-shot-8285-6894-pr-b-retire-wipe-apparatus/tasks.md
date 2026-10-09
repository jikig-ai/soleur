# Tasks: PR B, retire the Inngest backstop wipe apparatus and converge the records (#8285, also #6894)

Plan: `knowledge-base/project/plans/2026-10-09-chore-pr-b-retire-inngest-backstop-wipe-apparatus-plan.md`

PR title, body and every commit message use `Ref #8285` / `Ref #6894` only. No closing keyword anywhere. The trackers are
ended after merge with an explicit `gh issue close` (task 8.5). Deadline: merge by 2026-10-21 (ledger row expires 2026-10-22).

## Phase 0 - Re-pull evidence and census (read-only)

- 0.1 Re-read Hetzner (volume 404; `servers/169426216` volumes; no wipe-labelled server; snapshots and backups 0/0), Doppler
  pointer and flag, newest `host_role=dedicated` probe row, the alert (`paused=false`), the first post-destroy drift run, and that
  #8285 / #6894 are still OPEN. Status codes and non-secret fields only.
- 0.2 Re-run the `dt` / `ingest_time` measurement on the wipe rows; if aged out, use the plan's Research Insights values and say so.
- 0.3 Census by identifier (id `106261946`, addresses, names, labels, flag values, pointer name, `luks-rollback`,
  `rollback-no-backstop`, `_g4_retire_read`); record a disposition per hit in the PR checklist.
- 0.4 Run the baselined-file lints before editing (credential Rule E/D/base `--changed`, infra-no-human-steps, grep-q-pipe guard,
  fixture baselines, kb-consumers baseline); record current numbers.
- 0.5 Record pre-change `wc -c` of `apply-web-platform-infra.yml` (489,495) and guard-vacuity `n_fires` (ratchet 51).

## Phase 1 - Delete the wipe apparatus

- 1.1 `git rm` the five files (wipe `.tf`, wipe cloud-init, wipe suite, retire gate lib, retire gate suite).
- 1.2 `apply-web-platform-infra.yml`: delete job, option, five inputs, prose; revert the "never untargeted ... retire window"
  qualifier at four sites (also `apply-deploy-pipeline-fix.yml`, `scheduled-terraform-drift.yml`). Net byte decrease.
- 1.3 `variables.tf`: delete the four `inngest_backstop_*` variables and past-tense the neighbouring comments.
- 1.4 Registry and ratchets, in order: `test-all.sh`, both `*.tsv`, `guard-vacuity-floor.test.sh` (PROMOTED_FILES; ratchet only if
  measured), `inngest-probe-row.test.sh` ALLOW entry, Rule E baseline (measured), `terraform-target-parity.test.ts`,
  `web-host-escrow-preflight-census.test.ts`, `stock-preflight-coverage.test.ts` (run), `inngest-redis-luks.test.sh` G4.b2 and
  floor, `test-infra-privileged-tier-census.sh` `INTENDED_DESTROYS`, gate-lib and harness comments, `infra-credential-tiers-8209.md` row,
  job-rationale runbook section.
  - 1.4.1 Write Guard 1's negative rows first and see each mutation row RED (cq-write-failing-tests-before).
- 1.5 Comment-only edits: `inngest-arm-write-token.tf`, `inngest-host.tf`, `inngest-redis-luks.tf`, `betterstack-logs-alerts.tf` (comments
  only; `incident_cause` and the query unchanged), `uptime-alerts.tf`, `inngest-userdata-budget.sh`, `inngest-server-probe-heartbeat.test.sh`.

## Phase 2 - Retire `op=luks-rollback` (dispatch side only)

- 2.1 `cutover-inngest.yml`: header, choice, both ternaries, G3.7 comment.
- 2.2 `scripts/cutover-inngest.sh`: arm label, rollback branches, NEXT/warning lines, `luks-cutover` G1 `done` wording, stale comment. Lint first (baselined file).
- 2.3 `cutover-inngest-workflow.test.sh`: block to `luks-cutover` only; rows flip to assert absence (Guard 1); lower `_EXACT_FLOOR` by measurement, itemised.
- 2.4 `inngest-luks-property-8296.test.sh`: delete the AC-32 block; lower `MIN_PASSES` by measurement; keep the 5a-heading assertion; do not edit the probe script.
  - 2.4b Deleted-assertion ledger in the PR checklist (mutation each row killed, what kills it now).
- 2.5 Runbook: rewrite 5a under a heading matching `^## 5a\. .*op=luks-rollback`; turn 5b into a past-tense record carrying the revert recipe; fix 1-6, Related, `inngest-server.md`; lint-infra-no-human-steps on every touched runbook.
- 2.6 Comment on #9786: the dead on-host `rollback)` arm joins the next-replace removal list.

## Phase 3 - Ledger

- 3.1 Remove the `hcloud_volume.inngest_redis` row. 3.2 Correct the LUKS row (`does_not_defend`, `live_verification`). 3.3 `lint-encryption-posture.py --repo-sweep` PASS and its `.test.sh`.

## Phase 4 - Probe and stale prose

- 4.1 Keep the property probe, its test and its `run_suite` line; record the days-to-expiry pre-deletion note (3.4a) in the PR checklist.
- 4.2 `followthroughs/inngest-luks-cutover-6894.sh`: change the final NEXT echo to past tense.

## Phase 5 - Records (counts and identifiers only)

- 5.1 Complete the destruction record from the Research Insights table (per-phase process rows, `dt` finding, Terraform 1.10.5 note, times), keeping the Superseded markers.
- 5.2 Article 30 PA-13 (e), PA-21 (f), PA-22 (f): dated brackets, "logical, guest-side, self-attested", both times; never `docs/legal/**`.
- 5.3 `compliance-posture.md` Completed row (model: #8734 row) and `last_updated`.
- 5.4 ADR-142 landed addendum (via `soleur:architecture`); `model.c4` inngestRedis description + `bash scripts/regenerate-c4-model.sh`; C4 tests + count parity.
- 5.5 `expenses.md` (backstop row retired; LUKS row past tense). 5.6 roadmap L31 to Done. 5.7 older template keeps its Superseded banner.
- 5.8 Learning (only what is new). 5.9 CLO attestation: commit X (record final) -> `soleur:legal:clo` at X -> attestation file -> commit Y flips `status: complete`; both SHAs in the PR body.

## Phase 6 - Verify locally (CI is the authority)

- 6.1 File-selected suites and repo-global ratchets listed in the plan; workflow parse + actionlint + `wc -c` under the gate.
- 6.2 Rollback rehearsal in a scratch detached worktree; record the red suites in runbook 5b.
- 6.3 Pre-merge infra-validation plan JSON shows zero changes. Hetzner 404 re-read at ship time.

## Phase 7 - Review and ship

- 7.1 `soleur:review`, `soleur:qa`, `soleur:compound`, `soleur:ship` (Phase 5.5 CLO gate). PR body first line: no hand-written production change; merge triggers the routine per-merge apply (no changes expected) and the container release.

## Phase 8 - Post-merge (from a detached `origin/main` worktree)

- 8.1 Per-merge apply concluded success with zero changes; release job state recorded (unrelated `sandbox_broken` canary tracked separately if it recurs).
- 8.2 Ledger lint PASS; live-code grep clean; `gh workflow view` shows no retire option.
- 8.3 Hetzner 404 and server volumes; newest probe row on 106903269; alert `paused=false`; post-18:00Z drift run green.
- 8.4 #9703: add `follow-through` label and the probe directive; post the deletion-site list. #9786 and #8316 comments (D10); #9879 already filed.
- 8.5 `gh issue close 8285` and `gh issue close 6894`, each with the PR link, the three run URLs and the 404 read-back; dated note superseding #8285's Follow-through paragraph.
