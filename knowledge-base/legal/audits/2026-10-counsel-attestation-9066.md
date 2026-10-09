---
title: "Counsel attestation — #9066 (git-data lock files keep the user id after Art. 17 erasure: retention end of the plaintext-volume residue)"
type: counsel-review
date: 2026-10-09
issue: 9066
status: SIGNED-OFF (CLO-agent-attested, Soleur-as-tenant-zero v1)
signed_off_at: 2026-10-09
signed_off_by: "soleur:legal:clo (v1 internal attestation authority); operator retains optional veto"
disposition: DISCHARGED
re_evaluation_triggers: "(1) 2026-10-22 passes with hcloud_volume.git_data still present (ledger expires_on; re-opens ADR-239, the ledger exception and the CLO; date not extended quietly); (2) the 2026-10-24 CLO re-ruling on DPD §10.3(b); (3) Hetzner snapshot retention of the volume is measured; (4) first arms-length user, EEA-out subject, or regulated-industry subject (external counsel)"
---

# Counsel attestation — #9066

Scope: wording only. This PR changes no payload, performs no purge and no wipe. DPD and GDPR Policy are not touched; the DPD §10.3(b) disclosure question belongs to the 2026-10-24 re-ruling. Draft material; v1 internal sign-off, not external counsel review.

## Facts re-verified against the tree (not taken on trust)

- Both `git-data-provision.sh` and `git-data-remove.sh` open one constant `${REPO_ROOT}/.init.lock` (PR #9226, a96d123938). The pre-#9226 remove wrapper opened `.${workspace_id}.init.lock` BEFORE its `[ ! -e "$repo_path" ]` check, so completed and "not present" erasures both left a name-only file. The register marker's "completed and 'not present' erasures included" is accurate.
- Ledger `scripts/encryption-posture-ledger.json`, store `hcloud_volume.git_data`: tracking `#6897`, `expires_on: 2026-10-22`, mechanism `plaintext-exception`.
- The ADR's "in-freeze purge (2026-09-30 amendment)" and "D2 never writable" references exist in ADR-239.
- No wording in the three artifacts states that the lock files or the volume are erased or purged.

## Artifact 1 — Art. 30 register PA-36 (f), appended `[Superseded 2026-10-09 (#9066) ...]` marker

**File:** `knowledge-base/legal/article-30-register.md`

Verdict: APPROVED. Append-only, original sentence untouched. Scope widened correctly to name-only `.<id>.init.lock` files whose name is `auth.users.id`. End is event-bound (Hetzner volume delete after the DL-2 wipe, #6897) with outer bound 2026-10-22; slip consequence stated; "never mounted to remove in place" preserved; snapshot retention kept unmeasured; closes with "does not say the files are gone", so no erased/purged claim. Condition: none.

## Artifact 2 — ADR-239 `## Amendment 2026-10-09`

**File:** `knowledge-base/engineering/architecture/decisions/ADR-239-git-data-serves-from-luks-at-birth.md`

Verdict: APPROVED. Requirement 1 is stated as already true on main with the running host explicitly excluded until its next `git_data_host_replace`; requirement 3 is event-bound, with "The date is a target, not a fact" and the re-open clause matching the register marker. The three-state input list for the 2026-10-24 re-ruling is neutral. Condition: none. Note (not a change): the 2026-10-22 target leaves the residue, which is personal data, outliving the Art. 17 request by weeks; Art. 17(1) "without undue delay" is carried by the ledger expiry plus the re-open clause, not a stronger claim. That is acceptable only because the bound is hard and CI-enforced.

## Artifact 3 — Runbook `git-data-luks-cutover-5274.md` (three edits)

**File:** `knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md`

Verdict: APPROVED. Opening paragraph: event-bound end ("ends when that volume is destroyed by the DL-2 wipe, targeted no later than 2026-10-22"), never mounted to purge, points to the ADR amendment which carries the slip consequence. `not covered:` template addendum: separates the retained-volume limb (volume destroyed) from the served-store limb (freeze-window purge, counts only, no ids), so the two are not conflated. Step (d) qualifier: correctly says the per-id lock is what the running host serves until its next replace, and that main's constant lock carries no id. Condition: none; the runbook is a pointer and need not restate the slip clause because it cites ADR-239 in the same sentence.

## Standing conditions on the PR

1. The #5914 record gets a dated addendum drafted in the PR body only, not a rewrite of the record.
2. Any later wording that the files or the volume are "erased"/"purged" requires the Hetzner delete evidence first.
3. If the wipe PR lands, its evidence records the Hetzner volume delete and the register row gets a further append-only marker conditioned on that merge.

## Overall disposition

**DISCHARGED.** All three artifacts attested with no wording change.
