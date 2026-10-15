# Learning: a correction PR's own register pointers used exclusivity words ("only", "no") that a code read cannot establish, and "some ... not yet" corrected the claim by implicature

## Problem

PR #10326 (#10136, Ref #10138) corrected two published sentences that said all transport was TLS-protected, because event
payloads to the self-hosted Inngest host cross a plain-HTTP private-network hop. The first implementation was green on every gate
(mirror drift, SHA guard, encryption-posture sweep, register lint, corpus probe, two vitest files) and a byte-level check against
`origin/main`. An 11-seat review then found, in the PR's OWN new text:

1. **Exclusivity words in a data-content claim.** The PA-16 pointer said the `agent.spawn.requested` event carries an
   "`action_sends` row identifier only"; the send route sends five fields. The PA-29 pointer said "cron runs carry no
   app-to-server payload"; two crons send events. A code read can establish what crosses, never that nothing else does.
2. **A fix for it that was under-inclusive in the same way.** The corrected PA-29 list named `actor_id` and caller data; the
   agent path sends `delegating_principal` instead, and the secret route is the only one that takes caller data.
3. **A sentence that corrected the claim by implicature only.** "Some server-to-server traffic ... is not yet TLS-encrypted"
   still lets a reader infer the rest is encrypted, and "not yet" implies a rollout the same sentence calls "evaluating". The
   register said the other links were "not asserted either way". Same defect class as the one being retracted.
4. **Scope that widened under a status word.** "FULFILLED as to encryption at rest" dropped the "(AES-256-GCM for API keys)"
   limit while the ledger records the git-data volume as a plaintext exception.
5. **A raw-versus-hashed key discrepancy** between the new register text and the public ledger.

## Solution

- Removed every exclusivity word from data-content claims; the one place that lists what crosses the hop (PA-13 (g)(14)) is
  the single source, and the per-activity pointers carry no field lists.
- Rewrote the published sentence to say what is NOT claimed ("We do not claim TLS for server-to-server traffic ..., and this
  notice does not say whether the other links are"), scoped the status to API-key encryption, and recorded the key
  discrepancy openly with a tracker.
- Routed every wording question to the CLO agent as a batch with the seat reports attached (eight items, one spawn), and the
  final diff back to it for attestation; the attestation file records the Tier 1 classification.
- Made the edits reproducible: a script of exact-once span replacements applied to a fresh `origin/main` export, a byte-level
  comparison with the working tree, and re-pinning the two SHA-256 values from the regenerated files. Three fix rounds then cost a
  re-run each instead of a hand edit.

## Key Insight

Ask of every sentence a correction ADDS what it implies in addition to what it says: an exclusivity word needs the enumeration
that earns it, a status word inherits the widest scope in its sentence, and "some X is not Y" asserts about the rest. A
byte-level check, a green gate run and a claim-to-source table for the sentences you remembered all certify agreement
with your own edit script, not the truth of the prose; the seats that read the code and the rest of the corpus found all five.

## Session Errors

1. **Ruling rows failed the technical-ruling gate on shape (two rows with a parenthesis between the date and the colon, one
   self-applied "Default applied")** — Recovery: reshaped the two, sent the third to the CTO agent — Prevention: the shape is
   already documented in `technical-ruling-delegation.md` and enforced by the gate; run the gate directly after the planning
   subagent returns (done here) and never write a default as a ruling.
2. **Attributed a mechanical fix to "Ruled by CTO agent" without spawning one** — Recovery: removed the row before commit —
   Prevention: only name an agent that actually ruled; a correction made from a code read is a fix, not a decision row.
3. **Dated the first pin from `date -u` while the operator's calendar had rolled forward** — Recovery: re-dated, re-pinned and
   re-checked both mirrors before the first panel returned — Prevention: take the document date from the operator's calendar
   (the session's stated date), and treat a UTC clock as a different day near midnight.
4. **A history seat's "overwritten entry" finding was an artifact of diffing against the panel SHA** — Recovery: measured that
   `origin/main` has no such entry (`git show origin/main:<doc> | grep -c`) and dismissed it — Prevention: when briefing fix-round
   seats, state that published-baseline claims are checked against `origin/main`, not the panel SHA.
5. **`fix-round-seats.sh` has no arm for legal diffs (`unknown-seat: legal-compliance-auditor`)** — Recovery: added the legal
   seat by judgment — Prevention: routed a bullet into the review reference (a legal diff adds the legal auditor by hand).
6. **The working directory drifted into `apps/web-platform` twice** — Recovery: absolute paths — Prevention: none beyond
   absolute paths in any compound command.
7. **The Stop hook fired twice on closing text that named a future action** — Recovery: a one-sentence `Paused:` line —
   Prevention: end any waiting turn with that line.

8. **Register pointers shipped with exclusivity words ("only", "no payload") and a "some ... not yet" implicature that three seats and the CLO falsified from the code and the rest of the corpus** — Recovery: three fix rounds, the second driven by the CLO's attestation — Prevention: before writing a data-content claim, list the producers (every send site of the event) and drop any exclusivity word the list does not earn; for a status or "some X" sentence, read what it implies about the rest.

## Tags

category: workflow-issues
module: legal corpus, review fix rounds, Article 30 register
