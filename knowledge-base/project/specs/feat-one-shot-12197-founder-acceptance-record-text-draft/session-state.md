# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-11-07-feat-founder-acceptance-record-text-draft-plan.md
- Status: complete
- cto_spawns=2

### Errors
- plan-sharp-edges.md is about 250 KB; targeted sections only were read.
- The separate plan-review panel was folded into deepen-plan's agents.
- CI_DRAFT_LIGHT=on makes the `test` aggregator red by design on a draft PR; CTO ruling: "CI green" means every light-set check green, aggregator red by design, local vitest and markdownlint output cited.
- First `gh issue create` blocked (body file missing); retry succeeded (#12344).
- technical-ruling-gate.sh flagged class names in decision-challenges.md; rewritten to the closed category list.

### Decisions
- Text `founder-acceptance-record.md`: no in-file DRAFT marker; the unresolved retention placeholder is the in-file marker. Snapshot sha256 acd38414ce35e9aff7ccb1a0fee3719f9f65628cbfe4097d1a30dcffe465c9db (3556 bytes), not pinned until sign-off. **[SUPERSEDED 2026-11-08: the placeholder is replaced and the text is pinned; the current sha256 is in the Review round 1 section below.]**
- New structural test file plus a CI-only guard that fails while a bracketed placeholder remains; SQL 1000-literal leg in cross-layer-limits.test.ts. **[SUPERSEDED 2026-11-08: the CI-only guard was deleted; the unfinished-marker check is always on.]**
- HOLD: counsel sign-off and merge are Operator-reserved; draft PR #12342 is never marked ready, merged or enqueued. **[SUPERSEDED 2026-11-08: counsel sign-off is met by the CLO-agent stand-in (v1, human review owed); merge, enqueue and the flag stay Operator-reserved; the end state is DRAFT with the `parked` label per CTO T1.]**
- Merge preconditions: #12344 (card copy "these terms") and the global `approval-queue` flag. **[SUPERSEDED 2026-11-08: #12344 is fixed in this PR; the founder gate limits the surface to the founder.]**

### Components Invoked
soleur:plan, soleur:deepen-plan, soleur:gdpr-gate; agents cto x2, clo x2, cpo, user-impact-reviewer, spec-flow-analyzer, code-simplicity-reviewer, test-design-reviewer.

## Review ledger (dedup, findings -> fix)

- Panel (13 seats, c68d93cde0) -> cb4be7e07c: ack-marker sentence factually wrong (marker is written after the Sentry flush); guard missed the card notice with the same retention placeholder; unfinished shapes (TBD/TODO/XX/___) and wrapped brackets; byte audit too narrow; stated-limit parity; column set not pinned; duplicate .proposed.md deleted.
- Fix round 1 (10 seats, 48a019e06c): column pin type list and single migration; migration loop without control; plan sentences about .proposed.md and the guard turning green by itself; shared forbidden list; TAB/ESC rows; version date check; registry tripwire; real-data control.
- Verification seat (1 seat, 48a019e06c) -> 8719c96396: tableColumns/alteringMigrations read literals; quoted schema prefix; constraint ALTERs; <= limits; number words in retention test.
- Structural cause: a fact stated on several surfaces was guarded on one; extractors over SQL were not lexer-based and read one migration.
- Tally: seats=24 ci_cycles=3 fix_rounds=2 agent_rounds=3.

## Pipeline state (HOLD)

**[SUPERSEDED 2026-11-08 by the Review round 1 section at the end of this file.]** Draft PR #12342 open, HOLD for counsel. Not marked ready, not merged, not enqueued. Stopped before ship's merge phase by design.

## Sign-off planning phase (2026-11-07)
- Plan file: knowledge-base/project/plans/2026-11-07-feat-founder-acceptance-record-text-draft-signoff-plan.md (supersedes the draft-phase plan's holds)
- Status: planned and deepened; no product code changed.
- CLO (stand-in for counsel, operator ruling): retention 5 years from the date of the decision, extended only while a legal claim, complaint or inquiry is open; two-kind card deck; 12 residual risks.
- CTO: kind map in the pure leaf, no default (fail-closed render), `registry-pins.test.ts`, dispatch `ci.yml` for the full battery then ready, `parked` label merge barrier, server-side founder gate.
- Errors: none blocking. plan-sharp-edges.md (about 250 KB) was not re-read in full; the separate plan-review panel was folded into deepen-plan.

## Work phase (2026-11-08)
- Status: phases 0 to 6 of tasks.md done (text and notices, kind-keyed deck and consumers, founder gate, null-kind guard, tests, records, holds, hold mechanism). Not run: soleur:review (6.5), merge of origin/main, CI dispatch, the `parked` label, ready (phase 7).
- Commits: 2be52e2190 (text, notices, deck, pins), 2be03a905c (consumers, founder gate, null-kind guard), 0289d64358 (records), ce632723e2 (old-plan holds, decision rows), 535a41b254 (parked barrier).
- Text sha256: 43eef1162d0c8148b7fe5d62adaa116d0102249794163302592453ce9ce983f1 (5480 bytes), pinned in `registry-pins.test.ts`.
- Filed: #12365 (published trio), #12366 (terms wording, code lifetime wording, base-SHA pin guard); commented on #12080.
- Verified locally: the three node-only files, routes, surface, ops contract, card, card-ack and page suites one file at a time (single worker), the hook suite (59 rows) and the drain-prs suite (54 assertions); 18 mutation rows on the app suites and 4 on the hook all RED.
- Unverified locally: full tsc, the repo-wide ratchet suites, the full CI battery, the Sentry `accepted` count.

## Review round 1 (2026-11-08)
- Status: 13-seat review of a22578f5ad done (no P1 in the text; one P1 on the merge barrier, ruled by the CTO), CTO rulings T1-T5 and CLO rulings L1-L8 applied (rows in decision-challenges.md; table in the sign-off plan).
- Commits: 771b43e130 (hook, triage, hold-gate-eval), bacb389d16 (text, notices, surface, tests), f29e061bb1 (records).
- Text sha256: 10d283e02d4543d291468750655bbaf4375f807a585cd5138724a362b993a287 (6496 bytes), pinned in `registry-pins.test.ts`; version `2026-11-07` unchanged (never on main).
- Verified locally, one file at a time: hook suite 102 rows (25 mutants killed), drain-prs 58, hold-gate-eval 2028 assertions (wa-kind mutants killed), 31 app mutation rows killed.
- Unverified locally: the repo-wide ratchet suites, the full CI battery, full tsc, the Sentry `accepted` count.
- Next: phase 7 of tasks.md (merge origin/main, push, CI dispatch with a watch, the `parked` label added and verified BEFORE any ready flip, end state DRAFT per CTO T1), then compound and ship. Merge, enqueue and the flag stay Operator-reserved.
