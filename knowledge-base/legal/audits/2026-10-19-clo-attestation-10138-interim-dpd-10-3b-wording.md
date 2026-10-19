---
title: "CLO attestation — interim wording for DPD 10.3(b) and the T&C 14.1b pointer (#10138 / #6897, draft PR #10528)"
type: clo-attestation
date: 2026-10-19
issue: 10138
also_addresses: [6897]
pr: 10528
attestation-authority: clo
status: "SIGNED-OFF WITH CONDITIONS C1-C3 (CLO-agent-attested, Soleur-as-tenant-zero v1). DRAFT legal wording: owner review is required before merge."
tier_classification: "DPD Tier 1 (Tier 1 MINOR dissent for the T&C held; consequence identical). T&C Tier 2 PATCH, TC_VERSION 2.6.0 to 2.6.1."
signed_off_at: 2026-10-19
signed_off_by: "CLO agent (attestation authority for the Soleur-as-tenant-zero v1 posture; the operator retains an optional veto)"
disposition: "Attests the FINAL diff at 000258f17a plus condition C1 (applied in the following commit). Any later byte change to a published surface invalidates this attestation until the CLO re-attests."
scope: "the wording in this PR only. NOT a finding that the residue exists, how much there is, that it is gone, or what Hetzner keeps after a volume is destroyed. Does not discharge the 2026-10-24 CLO re-ruling."
re_evaluation_triggers: "(1) the merge falls after 2026-10-20 (refresh the as-of date from fresh plain reads; DPD and register only); (2) GIT_DATA_STORE_ENABLED or the cutover stamp is set, or any wipe, wipe_finish or snapshot_clear run exists, before merge; (3) 2026-10-24 CLO re-ruling; (4) 2026-11-12 passes with the retired volume present; (5) any measurement of the residue or of Hetzner snapshot retention."
---

# CLO attestation: interim DPD 10.3(b) and T&C 14.1b wording

Draft material; v1 internal sign-off, not external counsel review.

## Verdict

SIGNED-OFF WITH CONDITIONS. The published DPD 10.3(b) bullet equals the CLO-ruled text, byte-identical on the canonical document and the Eleventy mirror. The T&C 14.1b pointer is one new paragraph with no obligation language. None of the words the rulings forbid appears in published text. Only "has not been destroyed" is stated as fact, anchored to the as-of date of 19 October 2026; every other residue claim is hedged and the text says what has not been measured.

## The 12 November 2026 date

The brief's fragment said "scheduled for destruction by 12 November 2026". The published text says 12 November 2026 is the latest date by which we intend to destroy the retired volume. Repo evidence re-checked on 2026-10-19: `WIPE_OUTER_DATE="2026-11-12"` in `apps/web-platform/infra/git-data-cutover.sh` (an outer date, not a retention end); ADR-239 Amendment 2026-10-12 ("at the latest"); the ledger `expires_on` for `hcloud_volume.git_data`; `git-data-cutover.yml` is `workflow_dispatch` only, with no schedule. No wipe, wipe_finish or snapshot_clear run exists. So nothing is scheduled, and "scheduled" is not used.

## Conditions

- C1 (applied): the Art. 30 PA-36 (f) end marker also supersedes the derived "before 2026-10-23" date in the 2026-10-09 marker.
- C2: if the merge falls after 2026-10-20, repeat the three plain reads and refresh the as-of date (DPD bullet, DPD Last Updated entry, register markers, `legal-doc-shas.ts`; no T&C change).
- C3: merging is the owner's production-mutating authorisation (the TC_VERSION bump forces every existing user to re-accept the Terms and closes live sessions). No agent marks the PR ready, enqueues it or merges it. The Delete Account dialog, Privacy Policy and GDPR Policy follow-ups stay outside this PR.

## Open items (named, not discharged)

1. Existence and count of the residue: not measured on any limb.
2. Hetzner snapshot or backup retention of the retired volume: not measured.
3. The volume read showed delete protection off. This changes no published sentence; it is an owner and CTO note.
4. The 2026-10-24 re-ruling is not discharged by this wording.
