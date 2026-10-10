# Decision challenges: feat-one-shot-8285-6894-pr-b-retire-wipe-apparatus

Taste and challenge items from the planning pass (2026-10-09). The brief's direction is the default in every case; none of
these changes it. Ref #8285, Ref #6894.

## 2026-10-09 - Taste: delete the dispatch enum option outright (no hard-retired stub)

The `workspaces-luks-recut` precedent keeps an exit-1 stub so an old dispatch fails loud. This plan deletes the
`inngest-backstop-retire` option and job entirely: GitHub refuses an unknown `choice` value at dispatch (loud, before any
job exists), and the workflow file is 505 bytes under its size gate. Choice if disagreeing: keep a stub job whose first step
exits 1 (cost: bytes in the near-gate file, one more job to keep out of the census lists).

## 2026-10-09 - Taste: retire `op=luks-rollback` on the dispatch side only

The baked on-host `rollback)` arm stays. Editing it needs an image release, pin bump and host replace (the same reasons ADR-142's
2026-10-08 addendum rejected an on-host wipe). PR A pinned its refusal (`rollback-no-backstop`). The dead arm joins #9786's
next-replace removal list. Choice if disagreeing: schedule the image change with the next planned replace and delete the arm then.

## 2026-10-09 - User-Challenge candidate: brief step 4 versus brief step 6 on the property probe

Step 4 says keep the probe until the dead-probe feeder (#9703) is armed. Step 6 says end tracker 8285 after merge. The probe is
enrolled by a directive in #8285's body, and the sweeper stops running it when #8285 closes, so as written the probe would be kept
but silent. Plan default: re-home the directive to #9703 (label + directive line) so the report continues until #9703 arms; the
probe never exits 0 or 1, so it cannot end #9703. Alternatives: (a) leave #8285 open until #9703 arms (contradicts step 6);
(b) accept the gap (contradicts the intent of step 4). The operator's direction is honoured in both letter and intent by the default.

## 2026-10-09 - Taste: leave the wrong-volume alert's `incident_cause` unchanged

The text is true with or without the backstop; editing it is an in-place Better Stack update applied by the merge. Only comments change.

## 2026-10-09 - Taste: #8316 stays open, re-scoped

PR A removed the recut job; what remains is the suite-only `inngest_host_dark_gate` entry point, which shares helpers with the live
`inngest_execute_registry_gate`. Deleting it is a separate refactor with its own mutation battery. The two stale comments on #8316's
list that sit in files this PR edits are folded in.

## 2026-10-09 - Deferred: sole-copy protection of the LUKS volume

Filed as #9879 (delete protection, edge pins, key-loss posture). Not in PR B because `delete_protection` is an in-place update of a
live volume applied by the merge (a production write), and host replace legitimately replaces the attachment, so the web-1 pin set
does not copy over.
