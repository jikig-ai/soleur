---
title: "CLO recommendation (awaiting the owner): disclosure of the git-data pending-erasure ledger (#9066 / #8211)"
type: clo-recommendation
date: 2026-11-02
issue: 9066
also_addresses: [8211]
pr: "disclosure PR #11889 that carries this file (Ref #9066, Ref #8211; no Closes)"
attestation-authority: "clo (v1 internal recommendation by the CLO agent; NOT external counsel)"
status: "RECOMMENDATION ONLY, AWAITING THE OWNER'S #9066 DECISION. NOT SIGNED OFF. NOT an attestation. NOT an Art. 17 attestation."
disposition: "OPEN. Nothing in this file decides the #9066 posture, records that the owner accepted anything, or authorises marking the PR ready, merging or enabling auto-merge."
tier_classification: "DPD Tier 1 (no version constant). Privacy Policy and GDPR Policy: no version constant. T&C and its mirror: unchanged; TC_VERSION stays 2.6.1; TC_DOCUMENT_SHA unchanged. No forced re-acceptance, no session closure."
brand_survival_threshold: single-user incident
written_against: "The working tree of the disclosure PR #11889, checked against the bodies and code of PR #11866 (migration 182; merged as e30e50e89a and applied to production by the release migrate job of 2026-11-03T00:04:50Z) and of open PR #10905 (write path and re-drive cron; not merged or deployed) and against main at c2b0f75f38 (refreshed 2026-11-03 against 227b367902). Cited by function and constant name, never by line number, because later edits shift lines under a signed record."
re_evaluation_triggers: "(1) any change to the bytes of PR #11866 or #10905 that alters the fields, the retry cadence, the resolve-on-confirm rule, the counter bands or the Sentry/Inngest carriers described here; (2) the owner's #9066 decision on `.gc-cursor` and the lock files; (3) the deployment of PR #10905 (the sentences that say nothing is recorded as of the date then describe live processing and must be removed in a follow-up; the processing is not tied to `GIT_DATA_STORE_ENABLED`); the application of migration 182 FIRED on 2026-11-03 and is recorded below; (3b) the merge of #11898 / #10914 (paging rules), which makes the register statement that no paging rule exists false; (4) any measurement of Supabase backup retention or of the Inngest event/run state for the manual seed; (5) a CLO re-ruling of the Art. 6(1)(c) characterisation; (6) first arms-length user, EEA-out subject or regulated-industry subject (external counsel)."
---

# CLO recommendation: pending-erasure ledger disclosure

> **DRAFT. AI-generated, requires professional legal review. Not legal advice.**

Draft material; v1 internal recommendation by the CLO agent, not external counsel. It is a recommendation to the owner. It is not a sign-off, not an attestation and not a discharge of anything.

## What this PR is, and what it does not do

It discloses, ahead of the processing, the `git_data_erasure_pending` ledger of PR #11866 (merged; migration 182 applied to production on 2026-11-03) and of open PR #10905 (write path, not deployed): the Art. 30 entry (new PA-39, a Qualified marker on PA-36 (f), an Added marker on PA-8 (c)), the DPD, Privacy Policy and GDPR Policy text and their Eleventy mirrors, the SHA pins, the posture rows and this file.

It does **not**: decide the #9066 posture; record the Art. 17 attestation; say or imply that the owner accepted anything; change any code, payload, migration or workflow; align the Delete Account dialog or the agent tool (items below); touch the T&C; or say that the lock files, the `.gc-cursor` progress marker, the volume or any repository copy is erased, purged or gone.

## Evidence class of the facts the wording rests on

| Claim in the published text | Class |
|---|---|
| On account deletion `deleteAccount` calls `removeGitDataRepo`; any status other than `erased` or `skipped`, or a throw, leaves the deletion complete and reports it as pending | Inferred from main (read of `account-delete.ts`, not run) |
| From PR #10905, the same arms call `record_git_data_erasure_pending`, best effort, and a 15-minute cron re-drives each row at most once an hour until `erased` | Inferred from the draft PR body and the cron header comment (not merged, not run) |
| The ledger holds `workspace_id`, `requested_at`, `attempts`, `last_attempt_at`, `last_outcome`; no name or email; the counter holds month, bucket, count | Read from the migration file of PR #11866 (merged); migration 182 applied to production by the release migrate job of 2026-11-03T00:04:50Z (read by the review seats; not re-verified by the CLO) |
| The row is removed, and the counter incremented, in one statement on `erased`; no timer purge; no tombstone | Inferred (same sources) |
| The Sentry event of the existing non-confirmed arm carries the raw workspace id in `extra.gitDataRepoId`, retained 90 days | Inferred from main (`account-delete.ts`; PA-8 (f) for the 90 days) |
| Supabase backups may hold removed rows; retention window | Not measured |
| Inngest event and run state of the manual seed (`data.ids`) | Inferred from the PR #10905 body; retention not measured for this event |
| Once PR #10905 is deployed the ledger write is live whenever the removal host is armed (`GIT_REMOVE_SSH_PRIVATE_KEY`, or the provision key / `GIT_DATA_SSH_HOST` when the remove key is absent), independent of `GIT_DATA_STORE_ENABLED`; prd has those names set; rows are written only when an erasure did not complete or threw; a row can exist for a user whose repository never existed and resolves on the first successful host call; the table exists since 2026-11-03 but nothing writes to it until #10905 is deployed; no paging rule until #10914 (PR #11898 is draft and unmerged); the 20/28-day escalations key on the age of rows whose owner is gone (a row whose owner still exists only gets a 3-day warn) | Binding CTO technical ruling of 2026-11-02, from code and secret-name listings (values not read); not re-verified by the CLO. Supersedes this file's earlier 'the store is not serving' premise |
| Art. 6(1)(c) as the basis | Inherited from the CLO amendment of 2026-10-23 as quoted in the bodies of #10901 and #10905; the amendment text is not in the repository and is not quoted |

## Owner direction, and what it is not

On 2026-11-03 the owner directed that the disclosure PR be readied and shipped, in these words: "ready the CLO disclosure PR for #9066" and "ship the remaining PRs". Recorded here as given, from session context.

- This is **NOT an Art. 17 attestation** and **NOT an adoption of the #9066 posture** on `.gc-cursor` and the `.<id>.init.lock` files. Nothing in this file or in the published wording states either as adopted.
- The ADR-239 hold on Privacy Policy and GDPR Policy wording is **NOT separately lifted by any recorded ruling**. Flagged for the owner: if the hold applies to this wording, the direction above is the only authority in the record.
- The 2026-10-24 CLO re-ruling, the 2026-10-23 CLO amendment and the 2026-11-02 CTO ruling are cited from session context and PR bodies; **they are not stored in the repository** and are not quoted here.
- Follow-up: when #11898 / #10914 (Sentry paging rules) merges, the register statement that no paging rule exists (PA-39 scope note and (f), Register Maintenance item 16(d), the posture row) must be updated.

## Post-review corrections, 2026-11-03

A five-seat review found, and this revision corrects: the stale premise that the table does not exist (migration 182 merged and applied); the Sentry event and the pino log line carrying the raw workspace id, which operate on main today and were presented as future and as `userIdHash` only; the raw-id exception not carried into the sibling Recital 26 / Art. 17 statements and the Art. 6(1)(c) basis of the telemetry; the overstatement that the record is guaranteed (the write is best effort and bounded to 5 s); the missing temporal qualifier on the passages only #10905 makes true; and the missing companion text (GDPR Section 9 and 5.3, DPD 5.3(a), Privacy Policy Section 6). C1 to C5 are unchanged.

## Coverage of the five requested items

1. **Art. 30 register.** New PA-39 (purposes, subjects, data, basis, recipients, transfers, retention to confirmed `erased` with no timer, TOMs and recorded gaps, DSAR, DPIA, status), plus a PA-36 (f) Qualified marker for "will be erased on account deletion" and a PA-8 (c) Added marker for the raw id in the Sentry event, which no register or published document recorded before. Register Maintenance item 16 lists the open counsel questions.
2. **GDPR Policy.** New Section 3.18 with a provisional necessity-and-balance paragraph (the Art. 6(1)(f) fallback and its owed LIA are stated, not claimed), a Section 8.4 paragraph and item 14 of the Section 10 processing list.
3. **Privacy Policy and DPD wording.** DPD 2.3(ai), 10.3(b) cross-reference to a new 10.3(k), and the 4.2 Sentry row; Privacy Policy 4.16, the Section 5.10 exception to pseudonymisation, and a Section 7 bullet. The DPD 10.3(k) and the Section 7 bullet say "until the store confirms the removal, we cannot say the copy has been deleted" and carry the retry-and-ledger qualifier. The overdue Privacy Policy Section 7 and GDPR Policy Section 8.4 alignment is addressed in this PR because the ledger is the content of the qualifier; the posture row records them as addressed, not closed, since the account-deletion text elsewhere in those documents is unchanged.
4. **Dialog and agent tool.** Neither is docs. Both are product code in `apps/web-platform`. Not changed here. See "Follow-ups" below.
5. **Tier call.** None. See below.

## Per-artifact recommendation

| Artifact | Recommendation |
|---|---|
| Art. 30 PA-39, PA-36 (f) marker, PA-8 (c) marker | RECOMMEND, subject to C1 to C5 |
| DPD 2.3(ai), 10.3(b) cross-reference, 10.3(k), 4.2 Sentry row | RECOMMEND, subject to C1 to C5 |
| Privacy Policy 4.16, 5.10, 7 | RECOMMEND, subject to C1 to C5 |
| GDPR Policy 3.18, 8.4, 10 item 14 | RECOMMEND, subject to C1 to C5 |
| T&C and mirror | NO CHANGE (tier call below) |
| Delete Account dialog, agent tool, login notice | NOT IN THIS PR (follow-ups) |

## The T&C and TC_VERSION tier call: none

The T&C is not edited, so the bump policy's tiers are not engaged. Section 14.1b already states that its deletion bullet "is subject to Section 10.3(b) of the Data Protection Disclosure", and 10.3(b) now says it is subject to 10.3(k), so the chain from the T&C to the qualification holds without a T&C change. The ledger is an internal operational record that completes an obligation the user has already exercised; it creates no new user obligation. A TC_VERSION bump would force every existing user to re-accept the Terms and close live sessions, to disclose processing that is not yet switched on. Disproportionate. A Tier 2 PATCH argument exists (name 10.3(k) in 14.1b); I do not recommend it now and recommend revisiting it at the real flip, when the ledger can first hold rows.

## Follow-ups that are code, not done and not filed

- **Agent tool.** `apps/web-platform/server/account-tools.ts`, the `account_delete_initiate` handler: it calls `deleteAccount(userId, input.confirmEmail)` and then returns `textResponse({ success: true, message: "Account deletion cascade complete." })` without reading `result.gitDataErasurePending`. The message is false when the repository removal is pending. Its description string also says it "deletes all account data ... workspace files". Fix is a CTO code change (return the pending state; qualify the description).
- **Dialog.** `apps/web-platform/components/settings/delete-account-dialog.tsx`, the paragraph "All your data, API keys, conversations, and workspace files will be permanently deleted." A qualifier that mentions retry would describe behaviour that does not exist until PR #10905 is deployed, and this disclosure PR is required to land first. A qualifier that avoids the retry would have to be rewritten at #10905. Therefore bundle the dialog with the tool fix and ship them with or after #10905. Suggested copy for that PR (DRAFT, not adopted): "...will be deleted. If our repository store cannot confirm the removal of your workspace copy straight away, we keep your workspace identifier and try again until it does (Privacy Policy, section 4.16)."
- **Login notice** (`app/(auth)/login/page.tsx`, `ErasurePendingNotice`): already hedges the repository; re-read it against 4.16 in the same PR.

## Conditions (all must hold before the PR is marked ready)

- C1. Re-verify every behavioural statement against the final bytes of #11866 and #10905 (fields, "at most once an hour", resolve on `erased`, counter bands, no tombstone, Sentry and Inngest carriers). Any divergence changes the text, not the code.
- C2. **Trigger partly fired on 2026-11-03.** Migration 182 (PR #11866) merged and was applied to production on 2026-11-03, ahead of this disclosure, so the earlier published sentence that the table does not exist became false; the published text now says that the table exists and nothing writes to it. The remaining gate is **before #10905 merges**: the sentences that say nothing is recorded "as of the date" (DPD 2.3(ai), Privacy Policy 4.16, GDPR Policy 3.18 and the three Last Updated notes) become false on the deployment of #10905, which makes a row possible. A follow-up PR must remove them at that time, as for the approval queue. The published text no longer ties the processing to the store flag or to the store serving: it applies whenever the removal host is configured to be called.
- C3. No agent marks the PR ready, merges it or enables auto-merge. Merging publishes these documents at soleur.ai/legal/. **2026-11-03 note:** the owner's direction recorded under "Owner direction" is what authorises readying and shipping; this file does not.
- C4. Hold if a fresh read finds a published sentence that says the lock files, the progress marker, the volume or a repository copy is erased, purged or gone; canonical and mirror differ; any past-tense claim about a merge that has not happened.
- C5. Standing condition 1 of `2026-10-counsel-attestation-9066.md` stays intact: nothing here says the `.gc-cursor` or `.<id>.init.lock` files are erased or purged.

## Open decisions (none taken here)

Owner:

1. The #9066 posture on `.gc-cursor` and the lock files, including whether a hash-bound payload fix must precede the first flip. Nothing in this PR decides or presupposes it.
2. Whether to mark this PR ready and when relative to #11866 and #10905, both of which state that this disclosure lands first. [2026-11-03: #11866 has merged and been applied ahead of this disclosure; the owner has directed that this PR be readied and shipped (see "Owner direction"); the remaining gate is before #10905 merges.]
3. Whether the ledger and the 20/28-day Sentry events may exist before the paging rule of #10914 does. The deployment of #10905 alone makes the write live wherever the removal host is armed, so this is not deferrable to the flip.
3a. **Privacy-minimisation dissent (CTO), unreconciled.** A privacy-minimising view says no UUID should be stored for a user when `GIT_DATA_STORE_ENABLED` was never on, because there is then no repository to find. It is unreconciled because a flag-on window (the rehearsals) may have created a repository in prd for a real user. It would flip if the owner can show that the git-data host never held a real user's repository. Evidence of that is an owner decision and is OPEN; the published text is written to the ruled behaviour, which stores an identifier whenever the removal host is armed and an erasure does not complete.
4. Ranking of the dialog and agent-tool follow-ups.

Outside counsel (reserved by the v1 posture for the listed triggers; a recommended question set, not a request made):

5. Whether Art. 6(1)(c) is the right characterisation for retaining an identifier to complete an Art. 17 erasure, against Art. 6(1)(f) with an LIA.
6. Whether the raw workspace id in the Sentry event needs a shorter retention than 90 days.
7. Measurement of Supabase backup retention and of the Inngest event and run state for the manual seed (engineering measurement, then CLO).

## Quoted DRAFT owner text (NOT ADOPTED, NOT THE OWNER'S WORDS)

> **DRAFT. Prepared by the CLO agent for the owner to edit or discard. Not adopted. The owner has not said any of this.**
>
> On #9066, my position on the `.gc-cursor` progress marker and the `.<id>.init.lock` files is: [ACCEPT the disclosure in DPD 10.3(b) as the handling for now and proceed to the first flip without the payload fix | REQUIRE the hash-bound payload fix (rung-2 two-PR sequence) before the first flip | OTHER: (state it)]. My reasons: (state them). I [do | do not] want this recorded as the Art. 17 attestation for the residue. Date: (the owner fills this in).

No Art. 17 attestation is recorded by this file.

## Checks run for this PR (scoped)

`lint-legal-mirror-drift-baseline.sh --base origin/main` (within baseline), `lint-legal-scope-block-placement.sh --base origin/main` (0 violations), `check-tc-document-sha.sh` (exit 0), `legal-doc-consistency.test.ts` (37 pass), `legal-doc-shas-guard.test.ts` (6 pass), `lint-legal-registers.sh` (all assertions passed), `probe_legal_corpus_truth.py` (CORPUS-OK), markdownlint on the changed documents, and a secret scan before the push.
