---
date: 2026-07-21
issue: 6781
pr: 6782
category: test-failures
module: email-triage / notifications
tags: [precedent-mirror, postgrest, dedup, fixture-fidelity, vacuous-green, compliance-docs]
---

# The guard I shipped could never have fired, and my own fake certified it

## Problem

#6781: the statutory-deadline repin cron dispatched with no idempotency guard, so a
double-fired scheduler sent duplicate statutory-deadline email **per user per tick,
indefinitely**. I added migration 135 (`statutory_repin_send`, PK `(item_id, tick_key)`),
inserted a marker immediately before dispatch, and skipped on `23505`.

Twenty tests passed. `tsc` was clean. The full suite was 12,450 green. The guard could not
have suppressed a single duplicate in production.

## Root cause

I wrote the insert as:

```ts
.insert({ item_id: row.id, tick_key: tickKey }).select("id").single()
```

cloned from the sibling `notifyInboxItem`. That sibling is correct **because `inbox_item` has
an `id uuid PRIMARY KEY` to return**. `statutory_repin_send` has no `id` column at all — its
PK is the composite `(item_id, tick_key)`.

PostgREST renders `.select("id")` as `INSERT … RETURNING id`, so the real statement fails
`42703 undefined_column` and the whole insert rolls back. No marker is ever written.

**The part that makes this worth its own learning:** `42703` is a *plan-time* error, so it
fires **before** the unique-constraint check. A genuine duplicate therefore also returns
`42703`, never `23505`. The suppression branch was unreachable by construction. Not "broken
under load" — unreachable. `repinSuppressed`, documented in the handler as "the signal that a
second scheduler is live", would have been permanently `0`, and the fail-open warn would have
fired once per statutory row per tick, normalizing the exact alert channel that exists to
catch a deploy race.

The correct precedent was `claimDedupRow` (`app/api/webhooks/github/route.ts`) — a plain
insert — and *its comment already explains why*. I mirrored the wrong sibling.

## Why nothing caught it

Four layers, each blind in a different way:

1. **The fake could not reject.** `builder.select` was `vi.fn(chain)` — a no-op that discarded
   the column argument. `resolveMarkerInsert` keyed purely off the insert payload. The harness
   was structurally incapable of modelling a column-projection error, so no mutation of the
   `.select()` argument could red anything. Tellingly, the fake's own success return was
   `{ item_id, tick_key }` — I knew there was no `id` while production asked for one.
2. **The type system is blind.** `createServiceClient` calls `createClient(...)` with no
   `<Database>` generic, so `.select("id")` on a table without `id` is not a compile error.
3. **The live-DB tier validated a call shape production never issued.** T7b existed *solely*
   to be ground truth for the mock, and it used a bare `.insert()`. It would have gone green
   against the broken code.
4. **My own mutation battery (M1–M8) reported all-caught.** It measured the mutations I
   thought of. The defect was not a mutation of the code — it was the code.

## Solution

- Plain `.insert({...})`, no projection. Nothing read the returned row.
- The fake now declares a per-table column set (`TABLE_COLUMNS`) and returns a real `42703`
  for an unknown column, so re-adding the bad select reddens T1/T2/T11. T13 states the
  invariant; T13b is its negative control, proving the fake can actually reject.

## Key insight

**A precedent transfers its GUARANTEE, not its SYNTAX.** Before cloning an insert/query
idiom, ask what the source table provides that makes the idiom valid, and check the target
provides it too. Here: "does the RETURNING projection name a column that exists **on the
target**?"

And the harness rule that generalizes: **a fake that cannot reject is not a test seam, it is a
rubber stamp.** If your fake answers every request the SUT makes, your tests measure that the
SUT made requests — not that the requests were valid.

## Session Errors

**1. `.select("id")` on a table with no `id` column — the guard was inert.**
Recovery: plain insert (the `claimDedupRow` precedent). Prevention: when cloning an insert
idiom, verify the RETURNING projection's columns exist on the *target* table. Cheapest gate:
`grep` the target's `CREATE TABLE` for each selected column.

**2. The test fake could not reject, so 20/20 certified an inert guard.**
Recovery: per-table column schema in the fake + a negative control (T13b). Prevention: every
hand-written PostgREST fake needs a column-existence check; a fake that never returns an error
cannot distinguish a valid call from an invalid one.

**3. A plan requirement was LOST, not deferred.** The plan required exposing the operator
release verb (no SSH, no prod SQL, citing two hard rules). Phase 4 was renumbered into seven
legal-doc tasks and the requirement vanished — every box checked.
Recovery: recovered at review; wired through the existing manual-trigger event. Prevention:
when a plan phase is renumbered or re-scoped in `tasks.md`, diff the plan's numbered steps
against the task list rather than assuming renumbering preserved content.

**4. Appending to a markdown table row after its closing pipe silently discarded the text.**
The Article 30 PA-27 limb amendments landed as a *third* cell in a two-column table; GFM drops
cells beyond the header count, so a regulator-facing statutory register rendered as unamended
while the text survived in raw markdown — and passed a grep-based AC for exactly that reason.
Recovery: merged the cells. Prevention: after editing a markdown table row, count pipes
against a sibling row (`awk '{n=gsub(/\|/,"|"); print NR, n}'`).

**5. A bare-token grep matched the EXPLANATION of an invariant as readily as a violation —
three times in one PR.** AC3 matched the migration header explaining why those functions are
*not* replaced; AC9 matched the test header stating it does *not* mock notifications; the
`search_path` DDL pin matched the header prose "the RPC pins SET search_path". The first two
returned non-zero against correct artifacts; the third would have stayed green with the real
`SET` deleted.
Recovery: all three re-anchored on syntax a comment cannot produce. Prevention: `cq-assert-anchor-not-bare-token`
already exists — the addition here is that the collision is **structural**. The moment a task
requires both "assert X" and "document why X", they collide by construction. Expect it and
anchor on syntax from the start.

**6. The paperwork outlived the defect and re-prescribed it.** After the P1 was fixed, the
plan's Risks table still listed `.select("id").single()` as a *live mitigation* and `tasks.md`
task 2.3 still mandated it — checked.
Recovery: both corrected with the reason. Prevention: when a review fixes a defect that a plan
or task file prescribed, grep those artifacts for the prescription in the same commit. A
checked box that instructs the next author to reintroduce the defect is worse than no box.

**7. Fabricated cross-reference in legal prose.** I cited `gdpr-policy §6.1.b`; that section
does not exist (the exclusion list is in the DPD §5.3(a)).
Recovery: corrected. Prevention: section anchors in legal prose are claims — verify them like
identifiers. No existing gate validates them.

**8. Limb (f) contradicted itself three sentences apart** — claimed Art. 17 erasure "cascades"
to the marker, when the Art. 17 path anonymises in place so the parent is never deleted and
the cascade never fires. The same cell said so correctly earlier.
Recovery: rewritten. Prevention: this is the "cascade will clean it up" framing the migration
header itself calls FALSE — check new prose against the artifact's own stated invariants.

**9. AC10 asserted a proof it never performed** ("T8 asserts the table is actually
discovered"). T8 is the fake-uniqueness negative control, and the table appears nowhere in the
DSAR completeness suite.
Recovery: AC reworded to what is actually verified. Prevention: an AC that names a test must
name what that test asserts, not what you wish it asserted.

**10. I marked 15 acceptance criteria `[x]` in a bulk `- [ ]` → `- [x]` replace, then found on
actual verification that AC13 was false.** The bulk edit converted "to be verified" into
"verified" for every AC at once, with no verification performed.
Recovery: ran each AC's verification command; AC13 failed and was fixed. Prevention: never
bulk-toggle acceptance checkboxes. Each `[x]` is a claim; run its command and paste the
result. This is the same class as the `session-state.md` decisions-are-intent rule, applied to
the author's own artifact in the same session.

**11. `vi.clearAllMocks()` clears calls but NOT implementations.** T9's clock-advancing
`resendSendSpy` leaked into T11, moving `runDateUtc` past UTC midnight and making a correctly
suppressed second run look like a duplicate send.
Recovery: explicit `mockImplementation` re-init in `beforeEach`. Prevention: documented class;
re-establish implementations, not just call history.

**12. My fixture helper used 30 days for a calendar-month rule.** `dsar-art15` due is one
calendar month from receipt, not 30 days, so rows drifted out of the band under test.
Recovery: rewritten to subtract a calendar month. Caught by an honest RED. One-off.

**13. My first RED failed for the WRONG reason.** Every test died on the handler's unrelated
`assert-probe-row` throw before reaching its own assertions, which reads exactly like a real
RED.
Recovery: routed the probe query in the fake, then re-verified RED showed genuine assertion
failures. Prevention: read RED failure *messages*, never just the red count — a RED for the
wrong reason proves nothing.

**14–18 (one-offs, no recurrence vector).** CWD drift between parallel Bash calls (used
absolute paths). `grep -oP` didn't match the SHA file's format, and `sed` correctly no-oped
rather than corrupting it. `--milestone 6` rejected — the flag takes a title. `infoSilentFallback`
arity, caught by `tsc`. Stray non-English characters typed into a code comment.

## Also worth recording

**Adding a dedup guard to a delivery path can DELETE an accidental self-heal.**
`sendPushNotifications` prunes HTTP-410 subscriptions, so before this change a failed push
simply retried on the next tick. With a marker written, nothing retries — a non-410 push
failure became *permanent silence* on a statutory clock while the step reported the item as
pinged. Mitigated with a `statutory-notify-zero-delivery` warning; the real fix is tracked in
#6802.

So: **when you add a dedup/idempotency guard, enumerate what retry behavior it silently
removes.** The guard is not purely additive — it deletes every recovery that depended on the
operation being repeated.

## Related

- `knowledge-base/project/learnings/best-practices/2026-06-30-precedent-mirror-for-new-role-breaks-fencing-token-monotonicity.md` — the same precedent-mirror class, at the guarantee level
- `knowledge-base/project/learnings/2026-07-16-a-mutation-battery-only-covers-what-you-mutate.md` — why M1–M8 reported all-caught
- `knowledge-base/project/learnings/2026-07-20-every-property-i-asserted-instead-of-measuring-was-wrong.md`
- Deferrals filed: #6798 (reliance framing), #6799 (T-7 equality fragility), #6800 (ADR ordinals), #6801 (60-day scan cliff), #6802 (non-410 push silence)
