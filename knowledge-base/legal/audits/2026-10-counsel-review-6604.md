---
title: "Counsel review audit — #6604 step 7 / PR #9348 (PR B: the destruction record, Art. 30 PA-1 (g)(17) and PA-2 (g)(21), the #6588 counsel-review addendum, the plaintext-exception ledger re-scope)"
type: counsel-review
date: 2026-10-01
issue: 6604
related_issues: [6588, 6931, 6897, 5274, 8625, 6964]
pr: 9348
plan: knowledge-base/project/plans/2026-10-01-feat-workspaces-plaintext-wipe-pr-b-convergence-plan.md
parent_review: knowledge-base/legal/audits/2026-07-counsel-review-6588.md
adr: knowledge-base/engineering/architecture/decisions/ADR-119-luks-at-rest-for-the-live-workspaces-volume.md
brand_survival_threshold: single-user incident
status: BLOCKED (evidence pending)
attests_at_commit: PENDING-EVIDENCE(evidence-fill-commit)
signed_off_at: none
signed_off_by: none
disposition: "BLOCKED (evidence pending). The draft cannot be attested: the destructive dispatch and the state forget have not run, so every fact only they can supply is a PENDING-EVIDENCE marker. The CLO's plan-time ruling holds: SIGNED-OFF is possible only at the evidence-fill commit (Resume step 3 of the plan), never on this draft. The per-artifact review below checks the draft's wording against the plan-time CLO constraints so the re-attestation reads values, not phrasing."
attests: []
reviewed_in_draft:
  - "knowledge-base/legal/audits/workspaces-plaintext-destruction-record.md — the Art. 5(2) record (status stays template)"
  - "knowledge-base/legal/article-30-register.md — PA-1 (g)(17) and PA-2 (g)(21), one superseded marker each"
  - "knowledge-base/legal/audits/2026-07-counsel-review-6588.md — banner, status_on_attestation_6604 (status: kept verbatim), superseded_by (appended), re_evaluation_triggers, residual_cured, addendum_2026_10_01, §A3.5, §A3.6 and the dated addendum"
  - "scripts/encryption-posture-ledger.json — the hcloud_volume.workspaces plaintext-exception row, re-scoped to web-2"
read_for_consistency:
  - "knowledge-base/engineering/architecture/nfr-register.md — the Compute encryption row's superseded marker"
  - "knowledge-base/engineering/architecture/decisions/ADR-119-luks-at-rest-for-the-live-workspaces-volume.md — the PR B addendum (status stays adopting)"
re_evaluation_triggers: "(1) The evidence-fill commit: re-attest every artifact below against the D and forget runs' own output; flip this file to SIGNED-OFF (CLO-agent-attested, Soleur-as-tenant-zero v1) with attests_at_commit set, before the destruction record reads complete. (2) D prints plaintext_only greater than 0: each workspace is dispositioned by COUNT in the record before complete, the run's logs are deleted after capture, and the deletion is recorded here. (3) Any as-run arm other than first_wipe (re_zero, detached): every n/a field must name its arm and run id. (4) Step 7 is abandoned or D has not run by 2026-10-15: this draft is void; the plan's abandon branch extends the existing ledger row instead, and the registers quoting expires_on 2026-10-22 are swept by that separate PR."
---

# Counsel review audit — #6604 step 7 / PR #9348 (PR B convergence)

This file is the evidence for the ship Phase 5.5 Counsel-Review CLO-Attestation Gate on PR #9348
(issue #6604, step 7, "PR B"). The plan declares `brand_survival_threshold: single-user incident`,
and the diff touches `knowledge-base/legal/**`. The CLO agent is the v1 attestation authority; the
operator holds an optional veto.

**Status: BLOCKED (evidence pending).** This is the draft-time file the plan requires (task 5.6). It
is not an attestation. It is re-attested at Resume step 3, at the commit that replaces every
PENDING-EVIDENCE marker, and only then may the destruction record read `status: complete` and,
in a later commit, ADR-119 read `status: accepted`.

## Scope and limit check

- **In scope:** the four artifacts listed under `reviewed_in_draft`, and the two read for
  consistency.
- **Out of scope, and untouched (AC-B9):** `docs/legal/**`, `plugins/soleur/docs/pages/legal/**` and
  `knowledge-base/legal/audits/2026-09-counsel-review-8248.md`. Measured 2026-10-01 on the draft:
  `git diff --name-only origin/main...HEAD` over those three paths returned 0 lines, and
  `git status --short` over the same paths returned 0 lines. The negative attestation is repeated at
  the evidence-fill commit.
- **Published text.** No published legal sentence mentions the retained copy (CLO, plan time), so no
  published sentence changes. The LUKS clause re-scoped by #6938 is unchanged.

## Why the draft is BLOCKED

The destructive dispatch D (`workspaces-luks-cutover.yml`, `wipe_plaintext=true dry_run=false`) and
the forget (`workspaces-plaintext-forget.yml`) have not run. Both are dispatched from `main`, where the
wipe inputs, the `wipe` job and the forget workflow exist until PR #9348 merges; PR #9348's branch has
already deleted them, which is why it stays a draft until both have run. What exists, read 2026-10-01 from the run
logs:

- Rehearsal run `36769782488` (`workflow_dispatch` on `main` at `59abf6a76c`, `success`): one
  `result=rehearsal_ok arm=first_wipe volume_id=105149570` row with `target=/dev/sdb`,
  `backing=/dev/sdc`, `label=none`, `plaintext_dev=/dev/sdb`,
  `plaintext_fs_uuid=4cc6a724-f3b7-4c96-b607-af174f82169d`, `holders=0 dependents=0 device_units=7`,
  `magic=53ef`, `plaintext_only=0`; evidence rows `last_mount=Mon Jul 20 22:42:07 2026` and
  `last_write=Thu Jul 23 09:40:34 2026`.
- Baseline run `36770448813` (`success`): `ready=true workspace_count=9 expected=8`.
- Cutover run `29995956562`: `persisted workspace inventory baseline: WORKSPACES_COUNT=8` at
  2026-07-23T09:40:33Z.

Nothing in that set evidences a zero, a read-back, a detach, a delete or a state change. A record that
asserted any of them now would be the "justification drafted after the act" the destruction record's
own preamble rules out, inverted: an assertion drafted before the act.

## Per-artifact review of the draft

| Artifact | Draft check | Draft verdict |
|---|---|---|
| Destruction record | Rehearsal, baseline and cutover fields carry real values, each labelled with its run, never "at wipe time". The two rows the template pre-filled with a result (signature after the zero; recoverability) are now markers. Personal data is COUNTS only: 8 workspaces on the copy, `plaintext_only_count` 0 at the rehearsal, the erasure bound stated as the owners of those 8. No workspace id, name or email appears. The `io.max` figure is corrected to `150000000` bytes/s. The sentinel consequence and the durability limits are stated. `status: template`. | BLOCKED — 26 markers (23 distinct fields) outstanding at drafting |
| PA-1 (g)(17) | One in-cell `[Superseded PENDING-EVIDENCE(D-date) (#6604) …]` marker. Names `hcloud_volume.workspaces["web-1"]` / `105149570`; never says `hcloud_volume.workspaces` no longer exists (web-2's instance stays, #6931). States the zero, read-back and deletion only as taking effect after D concludes with `delete_issued=true`, each behind its marker; carries "logically zeroed, verified by read-back; physical media reclamation per the Hetzner DPA" as the wording proposed for attestation, behind PENDING-EVIDENCE(recoverability-clo-attestation); neither "erased" nor "physically destroyed". The Terraform protection reads "Terraform declares", with the Hetzner-side delete protection effective only after the post-merge SSH-stage apply. The #6808 clause reads "as recorded 2026-08-02; #6808 closed 2026-08-06; soak passed 2026-09-24". Merge-only facts read "on the merge of PR #9348". The ACTIVE measure is not amended. Table pipe count unchanged. | BLOCKED |
| PA-2 (g)(21) | The twin marker, same wording constraints, same checks. | BLOCKED |
| #6588 counsel review | Superseded markers on the CURRENT DISPOSITION banner, §A3.5 and §A3.6, each conditional on D concluding with `delete_issued=true` and carrying its own markers; `status:` kept verbatim (SIGNED-OFF WITH ACCEPTED RESIDUAL), with the post-attestation wording held in a new `status_on_attestation_6604` key that opens with PENDING-EVIDENCE(clo-attestation-6604); `superseded_by` carries an appended, marked clause naming the addendum as controlling as to DC-1 only; `re_evaluation_triggers` carries a marker for (1) and (2); new keys `residual_cured` (opens with a marker; scoped "DC-1 (web-1 retained copy, volume 105149570) only"; triggers (2)–(5) and the claim-decay trigger stand) and `addendum_2026_10_01` (same shape as the sibling `addendum_2026_09_21`); a dated addendum at the end; `accepted_residual` kept as history. Trigger (2) is dispositioned, not fired: the copy was frozen 2026-07-23, before the first arm's-length onboarding on 2026-08-06 (tester #1, `knowledge-base/engineering/operations/runbooks/alpha-tester-onboarding.md`). | BLOCKED |
| Ledger re-scope | `store` stays byte-exact `hcloud_volume.workspaces`; `device_binding` unchanged; prose fields re-scoped to web-2's instance; evidence is a content anchor (`resource "hcloud_volume" "workspaces"`), not a line number; `tracking_issue: "#6931"`; `expires_on: 2026-12-29` (89 days from 2026-10-01). `disclosed_as: not-publicly-claimed` unchanged. The retired web-1 instance is described conditionally ("PR #9348 merges only after the wipe dispatch D concludes with delete_issued=true"), with PENDING-EVIDENCE(D-run-id), PENDING-EVIDENCE(forget-run-id) and PENDING-EVIDENCE(D-date); web-2's volume reads "intended to be empty … contents unprobed", matching its `live_verification`. `lint-encryption-posture.py --repo-sweep` PASS on the draft. This change takes effect on the merge of PR #9348. | BLOCKED (it rides the same merge) |
| NFR register Compute row (read only) | Its superseded marker repeats the register's facts and wording; consistent. | n/a — not attested |

## Wording constraints carried forward to the re-attestation

1. Erasure wording is "logically zeroed, verified by read-back; physical media reclamation per the
   Hetzner DPA". Never "erased", never "physically destroyed".
2. The retired instance is always named (`hcloud_volume.workspaces["web-1"]`, Hetzner `105149570`).
   `hcloud_volume.workspaces` as a resource still exists for web-2.
3. Facts that fire only on merge (the narrowing, the deleted code, the Terraform protection, the
   ledger re-scope) say "on the merge of PR #9348". The protection reads "Terraform declares"; the
   Hetzner-side `delete_protection` is effective only after the post-merge SSH-stage apply.
4. Facts only D or the forget can make true (the zero, the read-back, the deletion, the cure) are
   stated conditionally ("after D concludes with `delete_issued=true`") and behind a marker, never in
   the past tense, until the evidence-fill commit.
5. Every personal-data field is a count. `plaintext_only_name` rows are never copied. The approver is
   a GitHub handle.
6. A field the as-run arm cannot produce reads `n/a (<arm>, run <id>)`, never a marker, never an
   invented value.
7. Order: this file SIGNED-OFF at the evidence-fill commit, then the destruction record `complete`,
   then ADR-119 `accepted`, each in its own commit, and both SHAs cited in the PR body.

## What the re-attestation must read

`gh run view <D> --log` and `gh run view <forget> --log` (the host step's `wiped` row, the API step's
detach, `DELETE` and final `GET`, the forget's `forgot=` row and state diff), the post-dispatch
`workspaces-luks-verify.yml` run, and
`doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since <D-start-ISO-Z> --grep SOLEUR_WORKSPACES_LUKS_WIPE --limit 500`
(`<D-start-ISO-Z>` is D's `gh api repos/jikig-ai/soleur/actions/runs/<D>/attempts/1 --jq .run_started_at`; a
`1d` window returns nothing, without error, once the fill runs more than a day after D).
If D printed `plaintext_only` greater than 0, record here that run's log deletion after capture.

This remains draft material requiring professional legal review.
