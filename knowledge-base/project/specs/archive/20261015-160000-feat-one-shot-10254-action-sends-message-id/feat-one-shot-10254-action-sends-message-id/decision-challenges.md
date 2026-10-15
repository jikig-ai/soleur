# Decision Challenges — feat-one-shot-10254-action-sends-message-id

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| Fix shape for `action_sends.message_id` Art-17 wedge (option (a) tombstone-messages vs (b) nullable+SET NULL+row-level carve-out vs narrower RESTRICT variant) | technical | Ruled by CTO agent, 2026-10-15: option (b) — `message_id` nullable + `ON DELETE SET NULL` + row-level WORM carve-out - mirrors mig 161 precedent family; cascade admitted on every deletion path; no saga change (recorded as comment on #10254, review of main@084a5b0d) |
| `TG_LEVEL='ROW'` gate inside the carve-out branch | technical | Ruled by CTO agent, 2026-10-15: Concur — `TG_OP='UPDATE' AND TG_LEVEL='ROW'` gate required as designed - the shared function serves two statement-level triggers (064, 051) where OLD/NEW are unassigned records; an ungated branch raises `record "old" is not assigned yet` instead of clean P0001; `TG_OP='UPDATE'` retained as forward-insurance against a future row-level DELETE attach |
| `action_sends.grant_id` same-class anchor | operator (scope) | Descoped by dispatch brief — dormant (scope_grants rows survive user deletion); recorded on #10379's audit item, not this PR |
| Extend `preflight-worm-cascade-contradiction.sh` envelope to table-to-table FKs | operator (scope) | Deferred — already filed as #10379; scheduling it is the operator's call |
| Legal-doc parity edits (disclosure §2.3(r) ×2 + Art-30 register rows) in the same PR | technical | Ruled by CTO agent, 2026-10-15: Concur — in-PR, do not defer - the published Art-30 register and disclosure text are already false today (they cite `session_replication_role`, dead since 087); shipping the carve-out without them actively misstates a statutory surface; the Art-30 edit must preserve the "carve-out is transition-bound, not role-bound" distinction |
| `account-delete.cascade.integration.test.ts` extension (seeded action_sends row) | technical | Ruled by CTO agent, 2026-10-15: Required — elevated from recommended - the suite is the named behavioural backstop for this defect class (teardown-only coverage is `afterAll` noise); fixture needs scope_grants + messages ancestor seeds; assertion mirrors audit_byok_use shape (row survives, `message_id IS NULL`) |
| `NOT VALID` + `VALIDATE CONSTRAINT` FK form | technical | Ruled by CTO agent, 2026-10-15: Confirm — adopt - the lock-window reduction accrues to parent `messages` (validating ADD CONSTRAINT would hold SHARE ROW EXCLUSIVE write-blocking the child scan); canonical zero-downtime default, keep the comment so it is not "simplified" back |
| Brand-survival threshold `single-user incident` + `requires_cpo_signoff: true` | taste | Signed off 2026-10-15 — CPO agent 44a0175a: `SIGN-OFF: APPROVE` (threshold correct, merge now, 5 non-blocking conditions relayed to work) + user-impact-reviewer aa2f5c27: `SIGN-OFF: APPROVE` (all role-enumerated failure modes covered) |

## Notes

- No pending technical rulings — the design decision was ruled upstream on the
  issue; remaining technical choices were ruled by one batched CTO spawn in this
  session (agent afab5140, all 4 concurred, 1 elevated to required).
- Operator-actionable items: none beyond the standing CPO sign-off row.
