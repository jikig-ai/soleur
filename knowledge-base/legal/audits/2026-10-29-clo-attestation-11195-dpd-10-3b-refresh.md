---
title: "CLO attestation — DPD 10.3(b) refresh after the 2026-10-27 plaintext-volume deletion (#11195 / #6897)"
type: clo-attestation
date: 2026-10-29
issue: 11195
also_addresses: [6897]
pr: "pending (DPD-refresh pull request; Ref #11195, Ref #6897)"
attestation-authority: clo
status: "PENDING: wording RULED by the CLO agent on 2026-10-29 as exact text; SIGNED-OFF only once the CLO agent verifies a byte-match of the merged PR head against the ruled text. DRAFT legal wording: owner review is required before merge."
tier_classification: "DPD Tier 1. T&C and its mirror unchanged; TC_VERSION stays 2.6.1; TC_DOCUMENT_SHA unchanged."
semver: "No version constant for the DPD. No re-acceptance and no session closure, because only a TC_VERSION bump forces those."
brand_survival_threshold: single-user incident
written_against: "The ruled replacement text for DPD 10.3(b) and the DPD Last Updated entry, returned by the CLO agent on 2026-10-29 and applied byte-exact to the canonical document and the Eleventy mirror. Cited by content, not by branch commit, because a squash merge drops branch commits."
signed_off_at: pending
signed_off_by: pending
disposition: "Lapses on any later byte change to the DPD or its Eleventy mirror until the CLO re-attests."
scope: "the wording in this PR only. NOT a finding on the volume's contents, on the residue (whether any exists, how much, or that it is gone), or on what Hetzner retains after a delete. Does not discharge #9066 or #11194."
re_evaluation_triggers: "(1) the merge falls after 2026-11-03: comment on #6897 (outer limit 2026-11-11); (2) any measurement of the residue or of Hetzner snapshot or backup retention; (3) #9066 remediation, or a #11194 host replace; (4) a data-subject request about the residue; (5) alignment of Privacy Policy section 7, GDPR Policy section 8.4 or the Delete Account dialog with 10.3(b); (6) any rebase that changes the bytes of the DPD or its mirror, including the sibling TLS-wording PR (#11487) merging first; (7) v1 external-counsel triggers: first arms-length user, EEA-out, or a regulated industry."
---

# CLO attestation: DPD 10.3(b) refresh

> **DRAFT — AI-generated, requires professional legal review. Not legal advice.**

Draft material; v1 internal sign-off, not external counsel review.

## Ruling

Ruled by CLO agent, 2026-10-29: APPROVED WITH EXACT TEXT. The text of the 10.3(b) bullet and of the DPD Last Updated entry is the text the CLO agent returned; it is applied byte-exact to `docs/legal/data-protection-disclosure.md` and `plugins/soleur/docs/pages/legal/data-protection-disclosure.md`. This file does not restate the text; the published bullet is the record.

## Facts (evidence class)

| Claim | Class |
|---|---|
| The volume `soleur-git-data-store` (Hetzner id 106867358) was deleted at the Hetzner Cloud API by a Terraform destroy, run 40478209838, dispatched 2026-10-27T09:05:55Z | Measured (run record; ADR-239 Amendment 2026-10-27) |
| A read-only API read-back on 2026-10-27 returned 404 by id and an empty list by name; the LUKS volume stayed attached to its server | Measured (ADR-239 Amendment 2026-10-27, item 2) |
| What the volume held before deletion | Not measured |
| Whether Hetzner keeps a copy of the volume after deletion, and for how long | Not measured |
| Whether any lock file or progress marker residue exists, or how much | Not measured |
| A retention period for the residue | None set; a retention criterion is still absent (open item 5 of the 2026-10-19 attestation) |

The published text states as fact only the first two rows. It does not use "destroyed", "erased", "gone" or "no personal data" as a claim about the volume or the residue; the two occurrences of "destroyed" in the DPD are quotations of the superseded sentences inside the amendment notes.

## Surfaces

Changed in the same pull request: DPD canonical (10.3(b) and Last Updated), Eleventy mirror (body bullet, body Last Updated, hero date), the DPD pin in `apps/web-platform/lib/legal/legal-doc-shas.ts`, Art. 30 register PA-36 (f) (Superseded marker), `compliance-posture.md` (DPD row date, `last_updated`, the 10.3(b) refresh row), ADR-239 (Amendment 2026-10-29), and the 2026-10-19 attestation (pointer key and Superseded markers).

Not changed: the T&C and its mirror (14.1b still reads correctly because the residue is still disclosed), the Privacy Policy, the GDPR Policy, and the posture row for the unqualified-deletion surfaces, which stays OPEN.

## Conditions

- C1: merge order. The sibling TLS-wording PR (#11487) edits the same DPD Last Updated line and the DPD pin. It merges first and this pull request rebases; the pin is recomputed from the final bytes after the rebase, never hand-merged. If #11487 is still unmerged on 2026-11-02, this pull request goes first and #11487 rebases.
- C2: the byte-final text is shown to the owner before the pull request is marked ready. No agent merges unprompted.
- C3: close #11195 only after the text is verified live at soleur.ai/legal/. #9066 and #11194 stay open.
- C4: hold the pull request if a fresh read finds the volume exists, any surface says "destroyed", "erased" or "no data" as a claim, canonical and mirror differ, the T&C bytes change, or any record cites code by line number or is written in the past tense before its own merge.

## Open items (named, not discharged)

1. Existence and count of the residue: not measured.
2. Hetzner snapshot or backup retention of the deleted volume: not measured.
3. A retention criterion for the residue: absent; the text says none is set.
4. Alignment of the Delete Account dialog, Privacy Policy section 7 and GDPR Policy section 8.4 with 10.3(b): posture row stays OPEN.
