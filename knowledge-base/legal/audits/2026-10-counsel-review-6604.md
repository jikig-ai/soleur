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
status: SIGNED-OFF (CLO-agent-attested, Soleur-as-tenant-zero v1)
attests_at_commit: 611051949cbe3539385a68ed8ac5609c699dce13
signed_off_at: 2026-10-08
signed_off_by: "CLO agent (attestation authority for the Soleur-as-tenant-zero v1 posture; the operator retains an optional veto). Re-attestation performed 2026-10-08 at the evidence-fill commit, against the dispatch and forget evidence as committed in the destruction record; external counsel re-review reserved for the re-evaluation triggers below."
disposition: "DISCHARGED. SIGNED-OFF at the evidence-fill commit 611051949cbe3539385a68ed8ac5609c699dce13 (Resume step 3). Dispatch D (workspaces-luks-cutover.yml run 37801674740, head 57cc8494d58626f02c47f35f15e1b7219133c9b7) logically zeroed web-1's retained plaintext volume 105149570 (blkdiscard -z), read all 21474836480 bytes back as zero (readback=zero), detached it (action 660248143891602) and deleted it (DELETE 204, final GET 404, web-1 left holding only 106443278), with plaintext_only=0; the forget (run 37803274724, head 425ea0fc1fda3624e53c46771d76580c43d36e90) removed exactly hcloud_volume.workspaces[\"web-1\"] and hcloud_volume_attachment.workspaces[\"web-1\"] (serial 1762 -> 1763, lineage unchanged). Both heads show no diff from the rehearsed 59abf6a76c over the wipe and forget code. The DC-1 residual is recorded as CURED as to web-1's copy ONLY; #6931 (web-2) and #6897 (git_data) stay open. Wording is 'logically zeroed, verified by a full-device direct-IO read-back; physical media reclamation per the Hetzner DPA'; physical erasure of the underlying network-volume media is NOT attested. Accepted residuals R1-R6 are in the body. Order from here: this file, then the destruction record -> status: complete, then ADR-119 -> accepted, each its own commit, both SHAs cited in the PR body."
attests:
  - "knowledge-base/legal/audits/workspaces-plaintext-destruction-record.md — the Art. 5(2) record as amended by this review (E1-E6), including the Recoverability cell; status flips template -> complete in the next commit"
  - "knowledge-base/legal/article-30-register.md — PA-1 (g)(17) and PA-2 (g)(21), one past-tense superseded marker each, as amended"
  - "knowledge-base/legal/audits/2026-07-counsel-review-6588.md — banner, status_on_attestation_6604, residual_cured, superseded_by, re_evaluation_triggers, addendum_2026_10_01, §A3.5, §A3.6 and the Addendum (2026-10-01, #6604), as amended; the cure is scoped to DC-1 / web-1's copy only"
  - "scripts/encryption-posture-ledger.json — the hcloud_volume.workspaces plaintext-exception row re-scoped to web-2 (takes effect on the merge of PR #9348), as amended"
blocking_findings: []
applied_in_review:
  - "E1 — 'zero completed 15:41:41Z' replaced by 'zero verified by read-back 15:41:41Z' (readback_start 15:39:16Z) in the record, the #6588 review, Article 30 PA-1/PA-2 and the NFR row."
  - "E2 — the record's 'at D' cells for W3, W4, W5 and W12 relabelled as inference from the Stage-3 gate, with the unprinted value in the n/a (first_wipe, run 37801674740) form."
  - "E3 — the record's 'Other copies' row: web-2's volume 'empty' -> 'intended empty, contents unprobed'."
  - "E4 — #6588 re_evaluation_triggers (1): the 'upgrades to unqualified' limb is superseded; DC-1 only."
  - "E5 — the record's Art. 17 cell: whole-workspace evidence (plaintext_only=0) stated; file-level deletions stated as not evidenced."
  - "E6 — Recoverability cell finalised (never 'erased')."
accepted_residuals:
  - "R1 — Physical erasure of the underlying network-volume media is not attested; a zero on a network block volume is logical only. Hetzner DPA reclamation."
  - "R2 — Sole copy: LUKS volume 106443278 is the only copy of every workspace; no backup or snapshot (#5274, #8625); a web-1 rebirth that strands it is #6964. Terraform prevent_destroy/delete_protection are declared only on the merge of PR #9348, and the Hetzner-side delete protection is effective only after the post-merge SSH-stage apply (read 2026-10-08: protection.delete=false)."
  - "R3 — Art. 17 deletions between 2026-07-23 and 2026-10-08 (77 days) are bounded to the owners of the 8 workspaces frozen on the copy (count only). Whole-workspace erasures: none held by the copy at D (plaintext_only=0). File-level deletions inside a surviving workspace: not evidenced, not remediable now."
  - "R4 — Third-party commit-author names/emails in the zeroed history: no separate residual; the same data remains in the live repositories under the existing PA-1/PA-2 basis."
  - "R5 — Not cured and outside DC-1: web-2's plaintext, intended-empty (contents unprobed) volume (#6931, rebirth #9372, ledger expires_on 2026-12-29) and the plaintext git_data volume (#6897)."
  - "R6 — Evidence basis: the run values are transcribed in the record; the CLO re-verified the procedure against the script and git, not against the raw logs or Better Stack. The single-wiped-row check is a pre-complete step."
does_not_attest:
  - "Engineering correctness of the workflow, the script and the Terraform protections (CTO)."
  - "Physical erasure of the underlying media (R1), web-2's volume contents (R5), or the durability of the sole copy (R2)."
  - "docs/legal/** and the Eleventy mirrors: untouched (0 lines, measured at 611051949c)."
art_33_triggered: false
art_34_triggered: false
reviewed_in_draft:
  - "knowledge-base/legal/audits/workspaces-plaintext-destruction-record.md — the Art. 5(2) record (status stays template)"
  - "knowledge-base/legal/article-30-register.md — PA-1 (g)(17) and PA-2 (g)(21), one superseded marker each"
  - "knowledge-base/legal/audits/2026-07-counsel-review-6588.md — banner, status_on_attestation_6604 (status: kept verbatim), superseded_by (appended), re_evaluation_triggers, residual_cured, addendum_2026_10_01, §A3.5, §A3.6 and the dated addendum"
  - "scripts/encryption-posture-ledger.json — the hcloud_volume.workspaces plaintext-exception row, re-scoped to web-2"
read_for_consistency:
  - "knowledge-base/engineering/architecture/nfr-register.md — the Compute encryption row's superseded marker"
  - "knowledge-base/engineering/architecture/decisions/ADR-119-luks-at-rest-for-the-live-workspaces-volume.md — the PR B addendum (status stays adopting)"
re_evaluation_triggers: "(1) SATISFIED 2026-10-08 at 611051949cbe3539385a68ed8ac5609c699dce13: every artifact re-attested against the D and forget runs' own output; this file is SIGNED-OFF before the destruction record reads complete. (2) NOT FIRED: D printed plaintext_only=0 (host row and field=plaintext_only evidence row), so no workspace is dispositioned and no run-log deletion is required or recorded. (3) NOT FIRED: the as-run arm was first_wipe (run 37801674740); no re_zero, no detached; no n/a field names another arm. (4) NOT FIRED: D ran 2026-10-08, before 2026-10-15. (5) STANDING: if PR #9348 closes unmerged, the amendments to the #6588 review, the Article 30 register, the ledger and the NFR row do not reach main (the destruction itself is a fact of 2026-10-08 either way) and this attestation is re-run; a web-1 rebirth (#6964), any decision to restore from a snapshot, or a first read of web-2's volume contents (#6931) re-opens R2/R5; the #6588 audit's triggers (3)-(5) and claim-decay trigger stand, and external counsel re-review is reserved for them."
---

# Counsel review audit — #6604 step 7 / PR #9348 (PR B convergence)

This file is the evidence for the ship Phase 5.5 Counsel-Review CLO-Attestation Gate on PR #9348
(issue #6604, step 7, "PR B"). The plan declares `brand_survival_threshold: single-user incident`,
and the diff touches `knowledge-base/legal/**`. The CLO agent is the v1 attestation authority; the
operator holds an optional veto.

**Status: SIGNED-OFF (CLO-agent-attested, Soleur-as-tenant-zero v1) at the evidence-fill commit
`611051949cbe3539385a68ed8ac5609c699dce13`, 2026-10-08.** The draft-time file of 2026-10-01 (task 5.6)
was BLOCKED (evidence pending); that verdict is superseded by the section "Attestation at the
evidence-fill commit" below. With this file committed, the destruction record may read
`status: complete` (its own commit) and, in a later commit, ADR-119 `status: accepted`.

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

> **Superseded 2026-10-08 (#6604), as to "have not run" and "Nothing in that set evidences a zero, a
> read-back, a detach, a delete or a state change":** D (run 37801674740) and the forget (run
> 37803274724) ran on 2026-10-08 and print each of them; see "Attestation at the evidence-fill
> commit" below. The 2026-10-01 reasoning is kept as history.

## Per-artifact review of the draft

| Artifact | Draft check | Draft verdict |
|---|---|---|
| Destruction record | Rehearsal, baseline and cutover fields carry real values, each labelled with its run, never "at wipe time". The two rows the template pre-filled with a result (signature after the zero; recoverability) are now markers. Personal data is COUNTS only: 8 workspaces on the copy, `plaintext_only_count` 0 at the rehearsal, the erasure bound stated as the owners of those 8. No workspace id, name or email appears. The `io.max` figure is corrected to `150000000` bytes/s. The sentinel consequence and the durability limits are stated. `status: template`. | BLOCKED — 26 markers (23 distinct fields) outstanding at drafting |
| PA-1 (g)(17) | One in-cell `[Superseded 2026-10-08 (#6604) …]` marker. Names `hcloud_volume.workspaces["web-1"]` / `105149570`; never says `hcloud_volume.workspaces` no longer exists (web-2's instance stays, #6931). States the zero, read-back and deletion only as taking effect after D concludes with `delete_issued=true`, each behind its marker; carries "logically zeroed, verified by read-back; physical media reclamation per the Hetzner DPA" as the wording proposed for attestation, behind the `recoverability-clo-attestation` marker; neither "erased" nor "physically destroyed". The Terraform protection reads "Terraform declares", with the Hetzner-side delete protection effective only after the post-merge SSH-stage apply. The #6808 clause reads "as recorded 2026-08-02; #6808 closed 2026-08-06; soak passed 2026-09-24". Merge-only facts read "on the merge of PR #9348". The ACTIVE measure is not amended. Table pipe count unchanged. | BLOCKED |
| PA-2 (g)(21) | The twin marker, same wording constraints, same checks. | BLOCKED |
| #6588 counsel review | Superseded markers on the CURRENT DISPOSITION banner, §A3.5 and §A3.6, each conditional on D concluding with `delete_issued=true` and carrying its own markers; `status:` kept verbatim (SIGNED-OFF WITH ACCEPTED RESIDUAL), with the post-attestation wording held in a new `status_on_attestation_6604` key that opens with the `clo-attestation-6604` marker; `superseded_by` carries an appended, marked clause naming the addendum as controlling as to DC-1 only; `re_evaluation_triggers` carries a marker for (1) and (2); new keys `residual_cured` (opens with a marker; scoped "DC-1 (web-1 retained copy, volume 105149570) only"; triggers (2)–(5) and the claim-decay trigger stand) and `addendum_2026_10_01` (same shape as the sibling `addendum_2026_09_21`); a dated addendum at the end; `accepted_residual` kept as history. Trigger (2) is dispositioned, not fired: the copy was frozen 2026-07-23, before the first arm's-length onboarding on 2026-08-06 (tester #1, `knowledge-base/engineering/operations/runbooks/alpha-tester-onboarding.md`). | BLOCKED |
| Ledger re-scope | `store` stays byte-exact `hcloud_volume.workspaces`; `device_binding` unchanged; prose fields re-scoped to web-2's instance; evidence is a content anchor (`resource "hcloud_volume" "workspaces"`), not a line number; `tracking_issue: "#6931"`; `expires_on: 2026-12-29` (89 days from 2026-10-01). `disclosed_as: not-publicly-claimed` unchanged. The retired web-1 instance is described conditionally ("PR #9348 merges only after the wipe dispatch D concludes with delete_issued=true"), with run 37801674740, run 37803274724 and 2026-10-08; web-2's volume reads "intended to be empty … contents unprobed", matching its `live_verification`. `lint-encryption-posture.py --repo-sweep` PASS on the draft. This change takes effect on the merge of PR #9348. | BLOCKED (it rides the same merge) |
| NFR register Compute row (read only) | Its superseded marker repeats the register's facts and wording; consistent. | n/a — not attested |

> **Superseded 2026-10-08 (#6604), as to the "Draft verdict" column:** each BLOCKED verdict above is
> replaced by the attested verdict in the table under "Attestation at the evidence-fill commit".

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
   *Superseded 2026-10-08 (#6604): at 611051949c the facts D and the forget made true (the zero, the
   read-back, the detach, the deletion, the state forget, the DC-1 cure as to web-1's copy) are stated in
   the past tense. Facts only the merge of PR #9348 makes true stay conditional on that merge (rule 3).*
5. Every personal-data field is a count. `plaintext_only_name` rows are never copied. The approver is
   a GitHub handle.
6. A field the as-run arm cannot produce reads `n/a (<arm>, run <id>)`, never a marker, never an
   invented value.
7. Order: this file SIGNED-OFF at the evidence-fill commit, then the destruction record `complete`,
   then ADR-119 `accepted`, each in its own commit, and both SHAs cited in the PR body.

## Attestation at the evidence-fill commit

**Verdict: SIGNED-OFF at `611051949cbe3539385a68ed8ac5609c699dce13`, 2026-10-08, with accepted
residuals R1-R6 (frontmatter).** The ship Phase 5.5 Counsel-Review CLO-Attestation gate for PR #9348 is
DISCHARGED by this file once committed. The operator retains an optional veto; external counsel
re-review is reserved for the re-evaluation triggers.

**What was read.** The seven artifacts of this review as they stand at 611051949c; the wipe job's API
step (detach, `DELETE` accepting only 204, `delete_issued`, final `GET` 404, server volume set) and the
host script's W3, W11 and W12 gates at `59abf6a76c`; and, locally, `git diff --quiet` of `59abf6a76c`
against D's head `57cc8494d58626f02c47f35f15e1b7219133c9b7` and the forget's head
`425ea0fc1fda3624e53c46771d76580c43d36e90` over `apps/web-platform/infra/workspaces-cutover.sh`,
`.github/workflows/workspaces-luks-cutover.yml` and `.github/workflows/workspaces-plaintext-forget.yml`
(exit 0 for both: the procedure as run is the rehearsed one). The raw run logs and Better Stack were
not re-pulled by this review (R6).

**Facts attested (counts and ids only).** Volume 105149570 on server 123931471 was the pinned target
(`target=/dev/sdb` differs from `backing=/dev/sdc` at the rehearsal; D's `wiped` row carries
`volume_id=105149570`, `bytes=21474836480`). It was zeroed with `blkdiscard -z` under the `io.max` cap,
read back in full as zero (`readback=zero`, `readback_start` 15:39:16Z, `wiped` row 15:41:41Z), detached
(action 660248143891602) and deleted (`DELETE` 204; final `GET` 404 at 15:42:04Z; an independent
read-only re-read returned 404 for the volume while web-1 answered 200; web-1 holds only 106443278).
`plaintext_only=0` at the rehearsal and at D; 8 workspaces were frozen on the copy; no workspace
existed only there. The forget removed exactly two addresses (serial 1762 -> 1763, lineage unchanged).
The post-dispatch verify run 37804427597 read `ready=true`, `workspace_count=9` (= the same-day
baseline 9), `crypto_LUKS` on `/dev/mapper/workspaces`, `escrow=ok header=readable`, `/health` 200. The
approver is the handle `deruelle`; each action had its own per-command go-ahead. Better Stack holds the
same rows off-host.

**Attested verdicts.**

| Artifact | Verdict |
|---|---|
| Destruction record | SIGNED-OFF as amended (E1-E3, E5, E6, and E7 if taken); flips to `complete` in the next commit |
| PA-1 (g)(17) and PA-2 (g)(21) | SIGNED-OFF as amended (E1; past tense for D and the forget; merge-only facts conditional) |
| #6588 counsel review | SIGNED-OFF as amended (E1, E4); `status:` kept verbatim, cure scoped to DC-1 / web-1's copy only |
| Ledger re-scope | SIGNED-OFF as amended; takes effect on the merge of PR #9348; `lint-encryption-posture.py --repo-sweep` must still PASS |
| NFR Compute row, ADR-119 addendum (read only) | Consistent once their conditional sentences are put in the past tense; not attested |

**Wording constraints 1-7 at this commit.** (1) Met: no "erased", no "physically destroyed". (2) Met:
the retired instance is always `hcloud_volume.workspaces["web-1"]` / `105149570`; the resource still
exists for web-2. (3) Met: merge-only facts read "on the merge of PR #9348"; the protection reads
"Terraform declares"; the Hetzner-side protection is effective only after the post-merge SSH-stage
apply. (4) Discharged here (past tense for D and the forget). (5) Met: counts only, no workspace ids,
approver a handle; the UUIDs present are an ext4 fs UUID and a LUKS header UUID. (6) Met: unprinted
values at D read `n/a (first_wipe, run 37801674740)`; none invented. (7) Order below.

**Negative attestation (AC-B9), repeated.** Measured at 611051949c: `git diff --name-only
origin/main...HEAD` over `docs/legal`, `plugins/soleur/docs/pages/legal` and
`knowledge-base/legal/audits/2026-09-counsel-review-8248.md` returned 0 lines; `git status --short` over
the same paths returned 0 lines. No published legal sentence mentions the retained copy, so none
changes; the five `docs/legal/**` CI gates are not engaged.

**Order and conditions before `status: complete`.** (a) Commit 1: this file plus the verbatim edits in
this review (the record stays `status: template`). (b) Commit 2: the record flips to `complete`, only
after: `gh run list --workflow workspaces-luks-cutover.yml` and the Better Stack query show exactly one
`result=wiped` row for 105149570 and no other `wipe_plaintext=true` dispatch; `grep -rn
"PENDING-EVIDENCE[(]"` over the five legal and ledger files returns nothing (the draft-history table rows
of this file describe the old markers without the literal form); the record's D and forget statements are in the past tense while merge-only statements stay
conditional. (c) Commit 3: ADR-119 `status: accepted`. (d) PR body cites both SHAs. (e) Both apply
workflows stay disabled until PR #9348 merges, by 2026-10-10T15:46:43Z (F7).

## What the re-attestation must read

`gh run view <D> --log` and `gh run view <forget> --log` (the host step's `wiped` row, the API step's
detach, `DELETE` and final `GET`, the forget's `forgot=` row and state diff), the post-dispatch
`workspaces-luks-verify.yml` run, and
`doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since <D-start-ISO-Z> --grep SOLEUR_WORKSPACES_LUKS_WIPE --limit 500`
(`<D-start-ISO-Z>` is D's `gh api repos/jikig-ai/soleur/actions/runs/<D>/attempts/1 --jq .run_started_at`; a
`1d` window returns nothing, without error, once the fill runs more than a day after D).
If D printed `plaintext_only` greater than 0, record here that run's log deletion after capture.

This remains draft material requiring professional legal review.
