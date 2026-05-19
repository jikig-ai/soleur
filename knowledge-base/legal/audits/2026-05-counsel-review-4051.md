---
title: "Counsel review audit — #4051 (LIA + Privacy Policy + DPD)"
type: counsel-review
date: 2026-05-19
issue: 4051
pr: TBD
status: PENDING-COUNSEL-REVIEW
---

# Counsel review audit — #4051 (LIA + Privacy Policy + DPD)

This audit file is the load-bearing evidence under acceptance criterion **AC-Legal-1** of plan `knowledge-base/project/plans/2026-05-19-feat-legal-linkedin-page-4051-plan.md`. The three primary artifacts below must each be reviewed by legal counsel (Soleur policy: no merge of a legal-track PR without counsel sign-off). Each row below is to be filled in by counsel — date, identifier (name or firm + matter number), channel (email / PandaDoc / verbal-confirmed-followup-email), and substantive comments if any.

The PR is held in draft state until all three rows below are signed off.

---

## Artifact 1 — Legitimate Interest Assessment

**File:** `knowledge-base/legal/legitimate-interest-assessments/2026-05-19-linkedin-org-page-lia.md`

**Scope of review:** the Art. 6(1)(f) three-part test (purpose / necessity / balancing) for processing LinkedIn Page-follower / engager personal data surfaced by LinkedIn Page Insights, and the explicit scope-out of the K-bis transfer (which is Art. 6(1)(c)). Particular attention requested on the three outstanding counsel-review items at `## Outstanding counsel-review items`:

1. Joint-controller assessment under Art. 26 + C-210/16 *Wirtschaftsakademie* — whether the LIA's deferral to a follow-up issue at first Page Insights call is acceptable.
2. K-bis transfer lawful-basis confirmation — Art. 6(1)(c) framing vs alternatives.
3. Art. 17 carve-out wording — sufficiency under EDPB Guidelines 5/2019.

| Counsel | Date | Channel | Sign-off | Substantive comments |
|---------|------|---------|----------|----------------------|
| TBD     | TBD  | TBD     | ☐        | TBD                  |

---

## Artifact 2 — Privacy Policy

**File:** `docs/legal/privacy-policy.md`

**Scope of review:** the diff in PR #4051 (see PR body for direct link). Affected sections: §4.10 (new), §5.12 (new), §5.13 (new), §6 (extended with LinkedIn-Page dual-basis paragraph), §7 (extended with LinkedIn-Page retention bullet), §8.1 (extended with LinkedIn-published-content carve-out paragraph), §10 (extended with LinkedIn / Microsoft Ireland international-transfers paragraphs). Particular attention requested on:

1. Art. 13(1)(e) recipient disclosure completeness for LinkedIn Ireland Unlimited Company and Microsoft Ireland Operations Ltd.
2. Art. 17 carve-out paragraph wording — is "cannot guarantee removal from LinkedIn's cached or replicated systems" sufficient, or should stronger wording be used?
3. Dual-basis framing in §6 — clarity on which sub-activities rest on Art. 6(1)(f) vs Art. 6(1)(c).

| Counsel | Date | Channel | Sign-off | Substantive comments |
|---------|------|---------|----------|----------------------|
| TBD     | TBD  | TBD     | ☐        | TBD                  |

---

## Artifact 3 — Data Protection Disclosure (DPD)

**File:** `docs/legal/data-protection-disclosure.md`

**Scope of review:** the diff in PR #4051. Affected sections: §2.3(p) (new activity row), §4.2 (extended Web Platform Processors table with LinkedIn Ireland + Microsoft Ireland rows), §6.4 (extended international-transfers), §10.3 (extended with Art. 17 LinkedIn-cache carve-out paragraph). Particular attention requested on:

1. Mirror consistency with Privacy Policy edits above (no factual drift between the two surfaces).
2. Joint-controller posture for Page Insights — is the LinkedIn Subscription Agreement + Pages Terms reference sufficient under EDPB Guidelines 07/2020, or should a separate joint-controller arrangement annex be referenced?
3. Microsoft Ireland controller-to-controller framing for the K-bis transfer — is "separate controller for the document-custody role" the right characterisation?

| Counsel | Date | Channel | Sign-off | Substantive comments |
|---------|------|---------|----------|----------------------|
| TBD     | TBD  | TBD     | ☐        | TBD                  |

---

## Post-sign-off operator actions

After all three rows are signed off:

1. Update PR body `## Counsel review` section — tick all three checkboxes referencing this audit file.
2. Update `knowledge-base/legal/compliance-posture.md` — move the `#4051 | IN-PROGRESS` row from Active Compliance Items to Completed Compliance Work with the merge-day completion date.
3. Mark PR ready: `gh pr ready <PR-number>`.
4. Auto-merge: `gh pr merge --squash --auto <PR-number>`.

After merge, proceed with the post-merge operator runbook in PR body (Cloudflare token scope expansion, ruleset apply, LinkedIn Developer app URL update, K-bis appeal submission).
