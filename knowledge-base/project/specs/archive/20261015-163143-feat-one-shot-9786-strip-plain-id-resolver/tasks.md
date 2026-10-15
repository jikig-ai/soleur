# Tasks - strip the dead PLAIN_ID resolver arm (Ref #9786, PARKED)

Plan: knowledge-base/project/plans/2026-10-12-chore-strip-inngest-plain-id-resolver-plan.md
Ship phase STOPS at a reviewed DRAFT PR (#10081). No merge, no apply, no replace, no dispatch.

## Phase 0 - Read-only preconditions
- 0.1 HARD STOP: latest first-boot `stage=resolve` row reads `mode=pointer pointer=106903269` (Better Stack, read-only). STOP if not.
- 0.1b Latest `SOLEUR_INNGEST_LUKS_CUTOVER` row reads `flag=done`.
- 0.2 Re-run the replace-window check (job census for `inngest_host_replace`, open issues/PRs/plans).
- 0.3 Record baselines: `inngest-userdata-budget.sh --json` (stored 19,680 B), AC5 key count (18), suite floors.

## Phase 1 - Tests first (red before the cloud-init edit)
- 1.1 inngest-redis-luks.test.sh: absence assertions (PLAIN_ID, inngest_volume_id, INNGEST_LUKS_PLAIN_VOLUME_ID, STAGING_*, reopen_skip_plaintext, mount_ext4) per reader, comment-stripped; `DEV=` derived from LUKS_ID.
- 1.2 inngest-host.test.sh: D1 v2' (zero inngest_volume_id assignments), delete v3, update rows.
- 1.3 inngest-boot-emitter.test.sh: map + anchor `{ inngest_luks_volume_id=`; floor 17 / bound 17.
- 1.4 loopback UNP3-UNP5 written first (ext4 refuses; reopen unit; raw + prd config refuses).

## Phase 2 - cloud-init-inngest.yml (two regions only)
- 2.1 Region A (boot-reopen script): drop PLAIN_ID/STAGING_DEV, DEV from LUKS_ID, allowlist LUKS_ID only, non-LUKS fails reopen_not_luks, delete staged-volume block.
- 2.2 Region B (first-boot stage): drop PLAIN_ID/STAGING_*, volume_ids check, resolve case (D2), volumes-file ADDITIVE line only (D3), delete ARM 1, delete staging block, simplify verify.
- 2.3 Pointer arm byte-identical to origin/main; run T1.13/T1.14 and templatefile-bare-dollar-guard.

## Phase 3 - Terraform + measurement consumers
- 3.1 inngest-host.tf: drop key + `inngest_retired_plaintext_volume_id` local; no other change.
- 3.2 rehearsal.tf: drop one map line.
- 3.3 inngest-userdata-budget.sh: drop stub + header bullet; re-measure.
- 3.4 inngest-boot-emitter.test.sh: RENDER_EXPR key, anchor, history comment.
- 3.5 variables.tf: description-only edit marking `inngest_expect_luks` inert. (Superseded in review fix round 3: the variable, template key and telemetry field are retired instead; AC5 key set 16.)

## Phase 4 - Suites
- 4.1 luks suite: seds, T1.10, T1.8a (4->3), delete T1.8a2, G1.a floor 6->4 with accounting, G1.b STAGING_MAPPER, G4.e needle, recount floor 64.
- 4.2 loopback suite: delete ARM1/REG/ST1-3/pre-cutover BOOT2, re-key ARM0/2/3/4 + PTR3/PTR4 fixtures to the LUKS_ID alias, add UNP3-5, floor from first CI run.
- 4.3 host suite: D1 rewrite, recount floor 99.
- 4.5 Ledger rehearsal rows + lint-encryption-posture.
- 4.4 Sweep sibling suites listed in the plan (grep-q-pipe-guard row stays 4, lint-encryption-posture, c4-count-parity, user-data-size).

## Phase 5 - Architecture record
- 5.1 Amend ADR-142 addendum D1 (status adopting, a few lines) + ADR-199 superseded-by pointer. 5.2 No C4 change. 5.3 Runbook live-reference sweep.

## Phase 6 - Review and park (STOP HERE)
- 6.1 Targeted local suites only; CI authoritative.
- 6.2 `soleur:review`; resolve findings.
- 6.3 Commit with "Ref #9786" and Co-Authored-By trailer; push.
- 6.4 PR #10081: retitle PARKED, DO-NOT-MERGE body block, stays draft, no auto-merge.
- 6.5 File ONE combined tracker (inert `inngest_expect_luks`; N2 rollback arm + image release + pin bump; rehearsal unused plain volume), criterion: when #10081 unparks. Add `parked` label; verify autonomous merge paths skip drafts/label.

## Phase 7 - Unpark checklist (documented, not executed)
- Rebase, rehearsal dispatch, pointer check, ready + merge inside approved window, replace dispatch, post-replace Better Stack verification, fold sibling `user_data` PRs deliberately.
