# Decision Challenges: feat-one-shot-8296-pr2-ledger-flip

These came up during plan-review for PR-2 of #8296. The run is headless, so they were written down
here instead of being asked. `soleur:ship` puts them into the PR body and files them as
`action-required`. The plan went ahead on the default shown for each one. The operator can
overrule any of them.

## DC-1 (User-Challenge): cut the property probe entirely

**Current direction.** Parent task 5.10 asks for a follow-through probe that checks whether the
ledger's claim still matches the device the Inngest store is on. It gets enrolled on #8285.

**The challenge (DHH).** PR-1's wrong-volume alert already fires when the store moves. The new
`NEXT (not automatic)` line on the `op=luks-rollback` path of `scripts/cutover-inngest.sh` already
flags the ledger as out of date at the one moment a sanctioned rollback happens. On top of that,
the probe brings:

- a test suite and a `run_suite` registration;
- a retirement clause;
- roughly 30 daily comments on #8285.

**Why the plan keeps it.** CPO, code-simplicity, architecture-strategist and spec-flow-analyzer
all keep it:

- It is the only mechanism that catches the **record** disagreeing with the **device**. The alert
  only watches the device. The NEXT line only reaches someone who reads that dispatch's log.
- It also catches the claim being withdrawn while the store is still encrypted, and the backstop
  outliving `expires_on`.

**Operator may veto:** yes. Cutting it removes Guard 3, AC-29, AC-29b, AC-29d, AC-30 and
Post-merge step 1.

## DC-2 (Taste): enroll later to cut comment noise

**Current direction.** `earliest=<merge date+1d>`.

**The challenge (CTO devex).** Set `earliest` to about 2026-10-12. Until then, PR-1's alert and
the rollback NEXT line already cover a store move. The probe matters most close to the
2026-10-22 expiry. This change cuts about 20 "NOT YET" comments on #8285. The cost is about three
weeks without a daily check of the record.

**Default kept:** merge+1d. The claim is new and a regulator reads it, so the plan prefers to
check it from day one. D12 tracks the root cause, which is that the sweeper comments on every run
and has no way to suppress repeats.

## DC-3 (Taste): trim the Guard 3 mutation matrix further

**The challenge (code-simplicity).** Drop the under-claim arm and its row 2, because P1–P5 only
forbid over-claiming. Also drop row 7 as covered by the static scan.

**Default kept.**

- The under-claim arm is the same single equivalence (`claims_luks == on_luks_mapper`), so it
  adds no code.
- Row 8 is the second-member row the plan skill's Guard Contract gate requires.
- Row 7 now also covers the fall-through and unset-variable escapes, which the static scan cannot
  see.
