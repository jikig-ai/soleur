---
title: "CLO agent ruling on the approval-queue enabling gates and the published status statement (#12365): Rulings 3 and 4 of 2026-11-10"
type: legal-ruling
date: 2026-11-10
issue: 12365
related: [12197, 4672, 12366]
status: "CLO-AGENT V1 RULING, standing in for counsel on the operator's instruction. NOT a lawyer's opinion. Human-lawyer review owed."
ruled_by: "soleur:legal:clo agent (2026-11-10)"
measured_at_commit: "b258336eb5"
measured_against: "origin/main, not production"
source_sha256: "6217aeba088c1016e86be9054fcbf6ababcde80ac4a432ef9f0e4d219a84cb1e"
---

# CLO agent ruling: approval-queue enabling gates and the published status statement (#12365)

> **What this is and is not.** The company has no external counsel. On the operator's instruction, the CLO agent's ruling (`soleur:legal:clo`) stands in for counsel on this matter. It is a v1 internal position, not a lawyer's opinion; no human lawyer has read it, and human-lawyer review is owed. Rulings 3 and 4 below are the CLO agent's reply of 2026-11-10, copied word for word by script, not retyped; `source_sha256` above is the sha256 of that block, from its first heading to the end of this file. They were measured against `origin/main` at `b258336eb5`, not against production. No version bump and no SHA move follow from this record.

## Ruling 3: enabling gates for a non-canary ON

**Ruled by CLO agent, 2026-11-10:** No. The gates as a set cannot be discharged now, and a non-canary ON is still not permitted. Evidence is from the repository at `b258336eb5`, not from production.

| Gate | Evidence | Status |
|---|---|---|
| (a) real-SDK probe | `2026-10-counsel-review-4672.md` row (a): legacy-runner path only; the hosted ask lane and a run with the flag on are not measured; #9776 and #10111 are OPEN | Not discharged |
| (b) full CLO attestation | Verification step passes today: every "no plaintext" phrase carries its approval-queue qualifier (trio and mirrors), and no Sentry or Better Stack emitter sends `canonical_action`. Only the canary record exists, and it is void for a non-canary ON | Not discharged (the step is ready to cite) |
| (c) remove the qualifier sentences, re-pin, re-read | The "not switched on…" sentence survives only inside the October 29 amendment entries and the Superseded blockquotes quoting them. "It may be switched on… for testing" appears nowhere. #12438 re-pinned the SHAs and the "nothing here states…" sentences give no number | **Discharged as to text.** This changes the 11-09 finding; it allows nothing on its own |
| (d) `gdpr-gate` recorded | No gdpr-gate record for the approval queue in `knowledge-base/legal/audits/` (the 11-04 and 11-05 records cover the founder-acceptance work only) | Not discharged (can be done without production access) |
| (e) DSAR export path | `approval_request` is still in `DSAR_TABLE_EXCLUSIONS` (`dsar-export-allowlist.ts`); only the manual route exists | Not discharged |
| (f) DPIA screening, standalone LIA, outbound-email LIA re-read | None exist; the published notices say so | Not discharged |
| (g) counsel questions (item 15) | Open, and not covered by the questionnaire | Not discharged |
| (h) autonomous-run card copy | `AUTONOMOUS_CARD_COPY_PROVISIONAL.PROVISIONAL: true`, both sign-offs null. That provisional card is now shown in every workspace | Not discharged |
| (i) erasure and fingerprint conformance | No run recorded in audits | Not discharged |
| (j) cohort rule | Limbs (i) and (ii) are in PR #12336, which is in 0.403.0. Limb (iii) is open (ADR-309 checklist item 1), so the rule still means single-member workspaces only. A global ON fails this rule; how many multi-member workspaces exist is not measured | Not discharged, and failed in fact |
| (k) `SENTRY_USERID_PEPPER` in the running container | Cannot be checked from the repo | Not discharged |

One more ADR-309 precondition is also not met: checklist item 8(a). The web-egress toggle text still tells users agents "can't push to git remotes", while `github_push_branch` is registered under this flag.

## Ruling 4: the published "on for every workspace" statement

**Ruled by CLO agent, 2026-11-10:** It stays as published, unchanged, while the flag is on.
- It is the true, dated correction of a false statement. Taking it down while the flag is on would bring back an untrue notice (Art. 5(1)(a), 13 and 14).
- No wording change is needed now. The missing "Draft, pending counsel review." in DPD 2.3(ah) is a marking difference I have put to the reviewer, not an error.
- It must change in the same cycle as any change to the flag (required change 4 below).
