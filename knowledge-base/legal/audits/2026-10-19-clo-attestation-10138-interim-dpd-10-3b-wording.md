---
title: "CLO attestation — interim wording for DPD 10.3(b) and the T&C 14.1b pointer (#10138 / #6897, draft PR #10528)"
type: clo-attestation
date: 2026-10-19
issue: 10138
also_addresses: [6897]
pr: 10528
attestation-authority: clo
status: "SIGNED-OFF on a byte-match to the texts in the review-round rulings (CLO-agent-attested, Soleur-as-tenant-zero v1). DRAFT legal wording: owner review is required before merge."
tier_classification: "DPD Tier 1 (Tier 1 MINOR dissent for the T&C held; consequence identical). T&C Tier 2 PATCH, TC_VERSION 2.6.0 to 2.6.1; T&C bytes are unchanged by the review round."
semver: "TC_VERSION 2.6.1 (Tier 2 PATCH). TC_DOCUMENT_SHA covers the T&C as edited in the first implementation commit; the DPD pin in legal-doc-shas.ts is recomputed after the review-round DPD edits."
brand_survival_threshold: single-user incident
written_against: "The PR head after the review-round fixes (the DPD bullet, the DPD Last Updated entry, the banner label and the register, ADR-239, attestation-9066 and posture markers as ruled on 2026-10-19), plus the replacement texts in the review-round rulings recorded in decision-challenges.md. Cited by content, not by branch commit, because a squash merge drops branch commits."
signed_off_at: 2026-10-19
signed_off_by: "CLO agent (attestation authority for the Soleur-as-tenant-zero v1 posture; the operator retains an optional veto)"
disposition: "Lapses on any later byte change to the DPD, its Eleventy mirror or the T&C, and on any change to the banner label, until the CLO re-attests. The T&C and its mirror are byte-unchanged by the review round."
scope: "the wording in this PR only. NOT a finding that the residue exists, how much there is, that it is gone, or what Hetzner keeps after a volume is destroyed. Does not discharge the 2026-10-24 CLO re-ruling."
re_evaluation_triggers: "(1) the merge falls after 2026-10-20 (refresh the as-of date from fresh plain reads in the DPD canonical and mirror, the register (f) marker and the DPD pin; no T&C change); (2) the merge falls on or after 2026-11-12 (the published latest intended date has passed; back to the CLO); (3) GIT_DATA_STORE_ENABLED or the cutover stamp is set, or any wipe, wipe_finish or snapshot_clear run exists, before merge; (4) 2026-10-24 CLO re-ruling; (5) any measurement of the residue or of Hetzner snapshot retention."
---

# CLO attestation: interim DPD 10.3(b) and T&C 14.1b wording

> **DRAFT — AI-generated, requires professional legal review. Not legal advice.**

Draft material; v1 internal sign-off, not external counsel review.

## Verdict

SIGNED-OFF on a byte-match to the review-round texts. The published DPD 10.3(b) bullet, its Last Updated entry and the banner label equal the CLO-ruled texts of 2026-10-19; the bullet is byte-identical on the canonical document and the Eleventy mirror. The T&C 14.1b pointer is one new paragraph with no obligation language and the T&C is unchanged since the first implementation commit. None of the words the rulings forbid appears in published text. Only "has not been destroyed" is stated as fact, anchored to the as-of date of October 19, 2026; every other residue claim is hedged and the text says what has not been measured.

## Facts (evidence class)

| Claim | Class |
|---|---|
| The earlier storage volume has not been destroyed as of October 19, 2026 | Inferred from the volume read and the workflow run list of 2026-10-19 (one volume, id not published, no wipe-family run) |
| The volume was created 2026-09-14 and the LUKS volume serves instead | Inherited (ADR-239 amendments; ledger) |
| November 12, 2026 is the latest intended destruction date | Inherited (ADR-239 Amendment 2026-10-12, the outer-date constant in the cutover script, the ledger `expires_on`); no job is scheduled |
| Lock files whose names carry an account identifier may remain | Inferred (earlier wrappers wrote them); existence not measured |
| A progress marker can hold the identifier of an account's repository | Inferred (the gc script writes `<id>.git`); presence not measured |
| Whether Hetzner keeps a copy of the volume after it is destroyed | Not measured |
| The flag and stamp read empty on 2026-10-19 | Printed for the flag (flip precheck `flag=unset`, run log); the stamp is a Doppler read recorded in the working session record |

## The 12 November 2026 date

The brief's fragment said "scheduled for destruction by 12 November 2026". The published text says that, as of October 19, 2026, the earlier volume has not been destroyed and that we intend to destroy it no later than November 12, 2026. Repo evidence re-checked on 2026-10-19: the outer-date constant in `apps/web-platform/infra/git-data-cutover.sh`, ADR-239 Amendment 2026-10-12 ("at the latest"), the ledger `expires_on` for `hcloud_volume.git_data`; `git-data-cutover.yml` is `workflow_dispatch` only, with no schedule. No wipe, wipe_finish or snapshot_clear run exists. Nothing is scheduled, so "scheduled" is not used, and "retired" is not used either (no evidence row: the volume is still attached).

## Conditions

- C1 (superseded by the review-round rulings B2 and B5): the derived "before 2026-10-23" date is marked in ADR-239, attestation 9066 and the register end marker.
- C2: if the merge falls after 2026-10-20, repeat the three plain reads and refresh the as-of date in the DPD canonical bullet and Last Updated entry, the DPD mirror body bullet, body Last Updated entry and hero, the register (f) marker as-of literal and read date, the DPD pin in `legal-doc-shas.ts`, and the DPD row date in `compliance-posture.md`. No T&C change. A merge on or after 2026-11-12 returns to the CLO.
- C3: merging is the owner's production-mutating authorisation (the TC_VERSION bump forces every existing user to re-accept the Terms and closes live sessions). No agent marks the PR ready, enqueues it or merges it. The Delete Account dialog, Privacy Policy, GDPR Policy, the agent tool `account_delete_initiate` and the login erasure-pending notice follow-ups stay outside this PR (see the posture row).

## Open items (named, not discharged)

1. Existence and count of the residue: not measured on any limb.
2. Hetzner snapshot or backup retention of the earlier volume: not measured.
3. The volume read showed delete protection off. This changes no published sentence; it is an owner and CTO note.
4. The 2026-10-24 re-ruling is not discharged by this wording.
5. Input to the 2026-10-24 re-ruling (Art. 13(2)(a)): the text states a destruction date for the earlier volume only, with no retention criterion and no contact route for any marker or lock files on other storage. The under-claim is by design (no promise to update is published) and is accepted for the interim only.
6. Later DPD 10.3(b) edits move the T&C 14.1b qualification without a TC_VERSION bump; each needs a CLO tier call that also asks whether 14.1b still reads correctly.
