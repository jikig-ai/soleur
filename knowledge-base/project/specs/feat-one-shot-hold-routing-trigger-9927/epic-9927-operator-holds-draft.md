# Draft record: the `## Operator Holds` section for epic 9927

RECORD, NOT A SOURCE. This file is archived by ship with the rest of the branch artifacts; the live copy is the appended section of the issue body, written post-merge (see the plan, Phase 4). The section sits inside one fenced block so that `hold-gate-eval.sh` and the go trigger both ignore it here (fenced lines are examples). Facts below were checked on 2026-10-29 against the live issue (comments of 2026-10-26 to 2026-10-28), ADR-282 (accepted, addenda of 2026-10-23 and 2026-10-28), `knowledge-base/engineering/operations/runbooks/inngest-server.md` (rows A1 and A6), `plugins/soleur/scripts/ci-head-verdict.sh` and the live follow-through directive of #10972.

```markdown
## Operator Holds

Added 2026-10-29 (Ref #9927). Nothing here is delegable and nothing here is discharged by this text: no `Delegation:` or `Envelope:` line is recorded. The class of each hold is on the line under it (`technical` = the CTO rules; `operator (<category>)` = only the owner; `waiting (<UTC time>)` = a date). The text above this section is unchanged.

- Hold: Operator-reserved: read-only Hetzner console check of the project's members, roles and sign-in protection (counts and roles only, no names, no values). The A6 "no known access" record is owner-signed and is filed under knowledge-base/legal/audits/ per the runbook's A6 row; no delegation covers either.
  Class: operator (third-party system)
- Hold: Operator-reserved: the written question to Hetzner support, sent from the owner's account: do delete-protected resources block a project delete, and what happens on account closure (text is in the PR body and the ADR-282 addendum of 2026-10-28).
  Class: operator (third-party system)
- Hold: Operator-reserved: decision on keeping an off-project copy of the volume ciphertext (header plus data). Deferred, not declined, by CTO ruling; re-evaluate at the earliest of 2027-01-08, a written Hetzner answer that delete protection does not survive a project delete or account closure, or the next planned apply_target=inngest-host-replace.
  Class: operator (money)
- Hold: Operator-reserved: closing #9927 (ends the epic; item 1b stays deferred, not declined).
  Class: operator (scope)
- Hold: Operator-reserved: authorizing apply_target=inngest-host-replace (sole-copy volume, user-facing scheduler); runbook row A1: in-session per-command go only, withheld from delegation.
  Class: operator (production-mutating)
- Hold: flip-token design for downgrading doppler_service_token.inngest (item 4): the on-host flag_set writes INNGEST_CUTOVER_FLIP under that token, so the downgrade needs a design before the host replace it rides on.
  Class: technical
- Hold: the ci-head-verdict.sh gap: the script reads only the ci.yml pull_request run for the head and no list of required contexts (checked 2026-10-29); a required context that never reported leaving a PR un-enqueued while the verdict reads green, and the dissent of the CONCUR gate on the proposed trigger, come from the 2026-10-29 resume brief and are not reproduced here.
  Class: technical
- Hold: correct item 7 of this body, which still lists the dropped scratch-volume proof (the proof was not started; comments of 2026-10-26 and 2026-10-28). Appended note, never an in-place edit.
  Class: technical
- Hold: reconcile where the A6 record lives: the runbook's A6 row says a record under knowledge-base/legal/audits/ linked from #10382 and #10136; the comment of 2026-10-26 calls the member list the pending A6 record.
  Class: technical
- Hold: follow-through re-look of #10972 (the orphan-sweeps monitor), from 2026-11-09T00:00:00Z; the tracker's own directive runs scripts/followthroughs/orphan-sweeps-relook-10972.sh.
  Class: waiting (2026-11-09T00:00:00Z)
```
