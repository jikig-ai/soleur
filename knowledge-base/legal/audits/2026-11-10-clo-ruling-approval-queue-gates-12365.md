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
required_change_4_sha256: "8a2f6e6c0f00b9e9bf8d3c6c7ecd2be490ca95a21e16f301fa4af761fd515856"
---

# CLO agent ruling: approval-queue enabling gates and the published status statement (#12365)

> **What this is and is not.** The company has no external counsel. On the operator's instruction, the CLO agent's ruling (`soleur:legal:clo`) stands in for counsel on this matter. It is a v1 internal position, not a lawyer's opinion; no human lawyer has read it, and human-lawyer review is owed. Rulings 3 and 4 below are the CLO agent's reply of 2026-11-10, copied word for word by script, not retyped; `source_sha256` above is the sha256 of that block, from the heading "## Ruling 3" to the end of this file. They were measured against `origin/main` at `b258336eb5`, not against production. No version bump and no SHA move follow from this record.

## Required change 4, referenced by Ruling 4

> Placed here on 2026-11-10 (#12197, PR #12567). Ruling 4 says "(required change 4 below)", but the change was not copied when this record was made, and `source_sha256` covers everything from the heading "## Ruling 3" to the end of this file, so nothing can be added after Ruling 4 without breaking that hash. Read "below" in Ruling 4 as pointing here. The item is item 4 of "Required repo changes (specified, not made)" in the same CLO agent reply of 2026-11-10, copied word for word by script; `required_change_4_sha256` above is the sha256 of the copied item, from its line beginning "4. **Only if" to its last line. It is a conditional instruction: it applies only if the flag is narrowed or turned off, and nothing in PR #12567 narrows or turns off the flag: its state is unchanged; the PR changes what the flag gates (the founder card no longer reads it), which the CLO agent ruled is not a narrowing for this purpose (ruling D3(iv), 2026-11-10). The CLO reply itself is not committed; both hashes pin this record's own copy.

4. **Only if the flag is narrowed or turned off.** Edit all three documents and their mirrors together, re-pin `legal-doc-shas.ts`, add a dated `**Amended:**` entry to each document. No `TC_VERSION` bump. Try to date the start from the Flagsmith audit log, read-only; if it cannot be found, use the wording below.
   - Head notices (PP 4.15, GDPR 3.17, DPD 2.3(ah)):
     - OLD: `Status as of November 9, 2026: the approval queue is switched on in production for every workspace, including workspaces that Jikigai does not own.`
     - NEW: `Status as of <DATE>: the approval queue was switched on in production for every workspace, including workspaces that Jikigai does not own, from a date we have not established (no later than November 8, 2026) until <DATE>; since then it is switched on only for workspaces that Jikigai owns [or: switched off]. Approval requests recorded in that period are kept as described below.`
   - Also in those notices:
     - OLD: `…now applies to every workspace.`
     - NEW: `…applied to every workspace during that period and still applies to the requests recorded in it.`
   - Every sibling sentence beginning "As of November 9, 2026 the approval queue is switched on…" (PP §6 and §7, GDPR 5.3, 8.4, 9 and 10, DPD 5.3(a) and 10.3(j)) gets the same past-interval wording.

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
