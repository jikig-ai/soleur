---
title: "Counsel review audit — #6107 / PR #10674 (Art. 35 DPIA re-evaluation of the Compound Promotion Loop, #2720)"
type: counsel-review
date: 2026-10-20
issue: 6107
pr: 10674
status: "SIGNED-OFF (CLO-agent-attested, Soleur-as-tenant-zero v1)"
signed_off_at: 2026-10-20
signed_off_by: "CLO agent, acting as a fresh reviewer who did not author the memo (attestation authority for the Soleur-as-tenant-zero v1 posture; the operator retains an optional veto). This is an internal CLO-agent attestation. Professional legal review remains pending; no external counsel has signed anything."
disposition: "DISCHARGED. The memo is an accurate, internally consistent and honestly conditional record. It claims no lawful basis it does not have, states that two Art. 6 balancings are currently unmet, states that its own determination is a draft position at current scale and not an empirical finding, and makes no public claim. The register note, the vendor pointer and the config comment do not overstate any control. Nothing under docs/ was edited. Discharge attests the accuracy and candour of the RECORD; it does not attest that the underlying processing has a recorded lawful basis (it does not, for two limbs), and it does not convert the memo from a draft."
blocking_findings: []
memo_status_unchanged: "The memo keeps status draft-requires-counsel-review and both DRAFT banners. This attestation does not clear them."
attested_blobs:
  - path: knowledge-base/legal/audits/2026-10-20-dpia-reeval-compound-promote-2720.md
    git_blob: 13cdf505653ecc2b8e40f4722b445408d49b963b
  - path: knowledge-base/legal/compliance-posture.md
    git_blob: d5dbbdd54f7b8aaa8f6af445b5b512d2e3a274bd
  - path: knowledge-base/legal/article-30-register.md
    git_blob: 23f055b778d74cf47c0d55f3eb2581e9d54e8a0c
  - path: knowledge-base/legal/data-processing-agreements/anthropic.md
    git_blob: fd6c981e3e332f701d3c99b2419e0328692ceac0
  - path: knowledge-base/project/promotion-config.yml
    git_blob: d212d5805c3d093f2a58a354c4f9ad283b9f2aab
blob_note: "Blobs were computed with git hash-object on the working-tree files at review time (working tree clean against HEAD). If any hash no longer matches, the attestation does not cover the changed text and the change must be re-reviewed."
conditions:
  - "C1 — Publication-limb balancing (limb (ii)): the operator records a short Arm A-style balancing for publication of a draft PR or skill-conflict comment BEFORE the first scheduled run that could open one (2026-10-25), or sets the loop kill switch (enabled: false in the loop config) until it exists. The loop has no gate that waits for this, so the control is the operator's decision, not the system. A PR or comment that appears without it must be recorded as a publication without a recorded basis (memo trigger 1). Currently UNMET."
  - "C2 — Named-persons balancing (limb (i)): the operator records the balancing for persons merely named in a learning by 2026-11-19 (tracker #10676 carries the dated action and owner). If missed, the acceptance of residual (a) lapses and the recommended state is the kill switch. Currently UNMET. The tracker is passive and notifies no one; the date is held by the operator."
  - "C3 — Adoption: the memo's position is the CLO draft position. It becomes the controller's position only on operator adoption. Until then the register, posture row and vendor pointer must keep their 'DRAFT position, pending operator adoption and counsel review' wording."
  - "C4 — The memo's structural basis carries two unverified premises (cohort-user data absent from the corpus with no enforcing control cited; Commercial-versus-Consumer Terms status of the Anthropic account). Neither may be restated as verified in any later record until the underlying check is done. Memo triggers 3 and 14 are the re-opening conditions."
  - "C5 — The Privacy Policy purpose gap (section 4.4 and the Art. 6(1)(f) paragraph in section 6 name only an awareness-of-community-activity purpose) stays referred to external counsel together with DEF-1 (#7120). No docs/legal edit may be made as a side effect of any follow-up to this PR without the Eleventy mirrors, the SHA re-pin and the five CI gates."
  - "C6 — The sweeper that closes #6107 closes on the existence of the memo file. That closure records filing only. It must not be cited later as counsel review or as an outcome."
re_evaluation_triggers: "Any of the memo's fourteen distinct triggers (first loop-opened draft PR or first posted skill-conflict comment; any change to what is sent to a processor; a move off single-operator scale; corpus made private or widened; auto-merge or reduced human gate; first observed identifying or special-category content; marker or log sinks gaining model free text; a recipient other than the operator; Anthropic retention terms change; PR #10673 merge; quarterly; counsel or an authority concludes otherwise; Anthropic account found on Consumer Terms; marker field-set change) OR a change to any attested blob above OR first arms-length user OR EEA-out data subject OR regulated-industry user. External counsel re-review is reserved for these."
---

# Counsel review audit — #6107 (PR #10674)

Internal v1 counsel-review attestation by the CLO agent. Gate fired because the diff touches `knowledge-base/legal/` and the plan declares `brand_survival_threshold: single-user incident`. Draft material. Professional legal review remains pending; external counsel is reserved for the frontmatter triggers.

**Reviewer independence.** The reviewer did not author the memo. Six review seats and two CLO fix rounds preceded this review (summarised in the work session state); their findings were not re-applied, the artifacts were read cold and checked against the implementing files.

**Scope of the legal change.** The diff over `knowledge-base/legal/` and the loop config is: the new memo; the posture file (header comment, two Superseded comments, one DPIA index row, the #2720 Active Items row rewritten in-cell, one new standing-trigger row); one dated note appended inside the PA-31 register cell; one pointer paragraph in the Anthropic vendor record; and a comment block in the loop config. The diff contains no file under `docs/`, `plugins/soleur/docs/pages/legal/` or `apps/web-platform/lib/legal/`, and no source code.

**Method.** Claims in the memo were checked against `apps/web-platform/server/inngest/functions/cron-compound-promote.ts` (the `collect-corpus` step, the `anthropic-cluster` step, `draftAdditiveEdit`, `newLinesCause`, `CREDENTIAL_RE`, `PII_REGEX`, `skillConflictDiffBody`, the skill-conflict comment branch, the week-cap search, `safeDetail`, and the constants `WEEK_CAP_DEFAULT`, `EDIT_TARGET_MAX_BYTES`, `DRAFT_EDIT_MAX_TOKENS`), `apps/web-platform/server/compound-promote-marker.ts` (`REFUSAL_DETAIL_CAP`, the one free-text field), `docs/legal/privacy-policy.md` sections 4.4 and 6, the register PA-31 cell, the vendor record, and live GitHub state (tracker issues, label, branch and title PR searches). Code is cited by function or constant name, never by line. Items not independently re-run are listed under Limits of this review.

## Per-artifact verdicts

| Artifact | Verdict | Basis |
|---|---|---|
| `knowledge-base/legal/audits/2026-10-20-dpia-reeval-compound-promote-2720.md` (memo) | DISCHARGED | Determination text, basis and limitations agree (check 1). Trigger set matches the posture rows (check 2). Balancing limbs split coherently and the unmet state is stated in four places (check 3). Draft banners and `draft-requires-counsel-review` status intact. |
| `knowledge-base/legal/compliance-posture.md` | DISCHARGED | #2720 row rewritten in-cell (the old text is preserved verbatim in a Superseded comment, not dropped), status cell corrected to the true GitHub state, fourteen distinct triggers carried, both unmet conditions and the lapse consequence carried, DPIA index row says draft and counsel review pending. The standing-trigger row is consistent with the tracker body. |
| `knowledge-base/legal/article-30-register.md` (PA-31 appended note) | DISCHARGED | Appended and dated; states nothing above is retracted and that `last_reviewed` is deliberately unchanged. Does not overstate controls (check 4). |
| `knowledge-base/legal/data-processing-agreements/anthropic.md` (pointer) | DISCHARGED | Pointer only; says the snapshot and review dates were not re-reviewed; carries the Commercial-Terms-unverified caveat and names the consequence (memo trigger 14). Does not claim the DPA applies. |
| `knowledge-base/project/promotion-config.yml` (comment) | DISCHARGED | Comment-only. Accurately widens the disclosure of what is sent and what is and is not screened. The kill switch semantics are unchanged. |
| `docs/legal/**` and Eleventy mirrors | NO AMENDMENT MADE; REFERRAL RECORDED | No docs file in the diff, so public wording is unchanged and no mirror, SHA re-pin or `EXPECTED_COUNT` obligation arises. The purpose gap is recorded as pre-existing and referred to counsel (check 5). |
| Sweeper `scripts/followthroughs/dpia-reeval-compound-promote-2720.sh` | PASS on the memo filename | Ran the script against this tree: it reports PASS on the memo path (check 6). |

## Check 1 — determination text and basis are internally consistent and conditional

The memo's frontmatter conclusion, its opening Determination paragraph, section 3, section 5 and section 7 all say the same thing, in the same register:

- the position is a **draft position**, a **determination at current scale**, **conditional**, and **not an empirical finding**, subject to operator adoption and counsel confirmation;
- the two empirical limbs (false-positive rate, operator merge ratio) are **0/0, undefined**, are never converted into a rate figure, and the verdict is stated not to rest on them;
- the basis is structural factors only, and two of them are labelled unverified wherever they are used (cohort-user data absent without an enforcing control; Commercial Terms status);
- the WP248 tally is stated honestly: criterion 8 engaged, 7 and 9 partial, 4 unassessed, so the presumption IS met, and displacement is "on stated reasons, not by the count" and requires counsel confirmation. The memo expressly refuses to rely on the fleet screening's "no public-output limb" reason because this member has one;
- the retrospective character is stated: no threshold determination existed on 2026-07-06, the memo is the first recorded one, and if counsel disagrees the interval is a timing failure the memo does not cure (trigger 13);
- lateness is stated without softening (overdue by 78 days; the date arithmetic reconciles: 2026-07-06 to 2026-08-03 is 28 days, 2026-08-03 to 2026-10-20 is 78, enablement to review is 106).

The empirical table separates Measured, Not measurable and Not derivable, and does not smuggle the work agent's log-query figures in as CLO-verified: they are labelled "not re-run by the CLO". The label search for the loop's PRs and the head-branch search were re-run by this reviewer on 2026-10-20 and each returned an empty list, which matches the memo. The audit-log header's stale wording ("every promotion proposal opened") is correctly identified as unreliable and the log is correctly treated as merged-only evidence. No inconsistency found.

## Check 2 — posture rows and memo carry the same trigger set

The memo numbers fifteen triggers and says fourteen are distinct because trigger 11 restates trigger 1. The posture #2720 row and the standing-trigger row list: first draft PR or comment; change to what is sent; move off single-operator scale; corpus made private or widened; auto-merge or reduced gate; identifying or special-category content; marker or sink free text; a recipient other than the operator; retention terms; the PR #10673 merge; quarterly; counsel or authority concludes otherwise; Consumer Terms; marker field-set change. That is the memo's list with 11 omitted, fourteen items, and the omission is stated in the row. The memo's sub-triggers inside trigger 2 (prefilter loosened, `EDIT_TARGET_MAX_BYTES` above 120,000, target set widened, new call site, processor or key change) and inside trigger 3 (second operator or reviewer, cohort or customer data, another repository) are reproduced in the standing row. "Repeat the empirical re-run at the fifth opened PR" is carried. The standing row correctly labels the 2026-11-19 balancing as a **dated action, not a trigger**. The tracker body (#10676, OPEN, labelled `keep-open`, no sweeper directive, no probe) matches the memo's and the posture row's description of it.

## Check 3 — the balancing precondition split, and the honest unmet statement

The split is coherent and has the right shape:

- **Limb (i), persons merely named in a learning.** Correctly identified as an ongoing transmission (every scheduled run, phase 1 and phase 2) with no first-PR deadline, outside Arm A of the fleet LIA (which covers already-published content of authors and contributors), and an Art. 14 population. Ruled an accepted conditional residual, not a stop, with a stated reason why a hard stop would not cure the past; owner the operator; dated action 2026-11-19; lapse consequence stated (kill switch). The code supports the factual premise: the corpus sent in phase 1 is the whole prefiltered set serialised after a `Corpus:` heading, and the prefilter is a shape match (`PII_REGEX`: email, IPv4, IBAN, key shapes) over file content, which does not match names.
- **Limb (ii), publication.** Correctly keyed to the first opened PR or posted comment and to the practical deadline 2026-10-25, with the kill switch as the alternative. The memo admits trigger 1 is post-hoc by construction and cannot enforce "before", and does not pretend otherwise.
- **Unmet, stated plainly:** "The conditions are currently unmet" (section 3), "currently unmet; if not recorded by that date the acceptance lapses" (residual (a)), "currently unmet and practically due before 2026-10-25" (residual (b)), "Both conditions are currently unmet, so the acceptance of residuals (a) and (b) is conditional and not yet earned" (section 7), and again in the frontmatter conclusion and the posture row. This is the correct candour: the memo accepts residuals on conditions it says are not met, and does not call them mitigated.

The memo claims no lawful basis for either limb and authors no LIA. That is correct: a CLO-agent memo should not backfill an Art. 6(1)(f) balancing the controller has not struck. See condition C1 and C2 for what remains.

## Check 4 — the PA-31 note and the vendor pointer do not overstate controls

The PA-31 note corrects, rather than inflates: it narrows measure (8) ("no PII scrub exists on Anthropic-bound content on this path") to the CLI members and says this member's prefilter is "best-effort ... not a guarantee and does not match names". Against the code: the draft-PR insertion screen applies `CREDENTIAL_RE` (credential shapes) plus line count, length, charset, render-hazard and rule-id class checks, and the email, IPv4 and IBAN alternatives of `PII_REGEX` are not applied to model output on that path; the skill-conflict comment path applies the full `PII_REGEX` via `skillConflictDiffBody`. The note says exactly this. It states that GitHub's host role for loop-published content is registered nowhere and that no Art. 6 basis is recorded for publication or for named persons, "filed for counsel, no draft PR has been opened". It does not claim a basis, does not say the DPA is verified, and says the PA-31 member count is unchanged (a second call site inside the same module). The note is inside the cell as a dated appended bracket, which is consistent with the register's own append convention; the earlier text is not rewritten.

The vendor pointer says it is a pointer only, that the file's snapshot and disposition review dates were not re-reviewed, that the Commercial Terms status is still unverified (open operator action 4 exists in the vendor record and is marked open), and that discovery of Consumer Terms fires memo trigger 14. It does not upgrade the DPA, retention or Zero-Retention status.

The config comment states what is sent, the cap, what the pre-pass does and does not cover, the second public surface, and the absence of a human gate on the comment path. Each assertion was checked against the code and is true.

## Check 5 — nothing under docs/ edited; referral recorded

`git diff origin/main...HEAD` over `docs/`, `plugins/` and `apps/` is empty. Privacy Policy section 4.4 does describe the repository processing as being "to generate summaries for our own awareness of community activity", and section 6 relies on Art. 6(1)(f) for "the awareness purpose described in Section 4.4"; neither names the loop's engineering purpose. The memo records the gap as pre-existing (dating from 2026-07-31), not caused or aggravated by the second phase, referred to counsel together with DEF-1 (#7120), and gives the reason for not editing (an edit would need mirrors, SHA re-pin and five CI gates and would publish wording no counsel has seen). That is a defensible CLO ruling; it is a deliberate deferral recorded as such, not a silent omission, and it is revisited at trigger 1. The memo and the posture row both say no public claim comes out of this record.

## Check 6 — sweeper

`scripts/followthroughs/dpia-reeval-compound-promote-2720.sh` matches `*dpia*compound-promote*.md` in the audits directory and requires a non-empty regular, non-symlink file. The memo path `2026-10-20-dpia-reeval-compound-promote-2720.md` satisfies all of it; the script was run in this tree and exited PASS. The memo itself, and the posture row, state that this closure records filing only (condition C6).

## Observations (non-blocking)

- **N1 — stale comment in the marker module.** The marker module's doc comment for the error text says "200-byte cap"; the implementing `safeDetail` slices 200 characters (UTF-16 code units). The memo correctly says 200 characters, not bytes, and is consistent with the code, not the comment. Engineering may wish to correct the comment. No legal effect.
- **N2 — no gate behind C1.** The memo is right that nothing in the loop waits for the publication-limb balancing. The 2026-10-25 run is five days from this review. The CLO recommendation, which the operator is free to override, is to either record the balancing or flip the kill switch before then; the memo already says this and it is the single most time-sensitive item in the record.
- **N3 — passive tracker.** #10676 notifies no one by design (a probe whose pass means "the trigger fired" would have closed it early). The 2026-11-19 date therefore depends on the operator seeing the tracker. The memo says so. If the operator wants an active reminder, that is a separate follow-through and a CTO/COO matter, not a legal defect.
- **N4 — engineering adequacy is out of scope.** Whether undelimited phase-1 prompting and the synthetic status of required checks on the draft PR are adequate engineering controls is for the CTO; the memo says so and limits itself to "no write or act authority beyond a draft PR or a comment exists", which the code supports.

## Limits of this review

Checked and found true against code or live state: the corpus collection and prefilter behaviour, the undelimited phase 1 prompt versus the nonce-delimited phase 2 prompt, the draft-PR and comment-path screens, the cap query, the 200-character cap, `REFUSAL_DETAIL_CAP`, the tracker issue state and body, the empty label and head-branch PR searches, the privacy-policy wording, the sweeper outcome, and the date arithmetic. **Not independently re-run, and so relied on only as the memo itself labels them:** the log-processor outcome rows for 2026-09-19 to 2026-10-18; the marker test suite (Guard 3); the merge dates of the second-phase change and of the marker change; the state of #10673, #10552 and #8443; the Sentry cron heartbeat; the Anthropic account's Commercial-versus-Consumer status. The memo labels each of these as unverified or not re-run; this review adds no verification the memo does not claim. This review makes no statement that the second-phase change works.

## Disposition

Reviewed artifacts: the memo, the posture file, the PA-31 note, the vendor pointer, the config comment (each DISCHARGED); the `docs/legal` surface (no amendment made, referral recorded); the sweeper (PASS).

The memo keeps its DRAFT banners and its `draft-requires-counsel-review` status. This is a CLO-agent attestation under the Soleur-as-tenant-zero v1 posture; professional legal review remains pending and no external counsel has signed. The operator retains an optional veto. Discharge here means the record is accurate and candid about what is and is not established; it is not a finding that the processing has a lawful basis for the two limbs named in C1 and C2.

DISPOSITION: DISCHARGED

> **Superseded 2026-10-26 (#10552; conditioned on the merge of PR #11157):** the Method and findings above that cite `skillConflictDiffBody` and the skill-conflict comment path describe the pre-merge loop. On the merge of PR #11157 the loop no longer posts that comment (the guard reads open PRs' changed files and records a refusal instead); the dated text above is unchanged. The comment already posted on PR #10812 is not removed by the merge. See the 2026-10-26 addendum in `knowledge-base/legal/audits/2026-10-20-dpia-reeval-compound-promote-2720.md`.
