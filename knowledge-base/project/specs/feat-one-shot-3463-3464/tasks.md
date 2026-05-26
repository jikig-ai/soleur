# Tasks: feat-one-shot-3463-3464

Bundle: disconnect-after-result race (#3463) + session_started.incomingTypes capability (#3464).

Plan: `knowledge-base/project/plans/2026-05-07-feat-disconnect-race-and-incoming-types-capability-plan.md`

## Phase 0 — Verification grep

- [ ] 0.1 Run grep for `session_started` emit sites: `git ls-files | xargs rg -l '"session_started"' apps/web-platform/`
- [ ] 0.2 Run grep for canonical `promptKinds` constant (or confirm inlined): `rg -l 'promptKinds' apps/web-platform/`
- [ ] 0.3 Enumerate all `session_started` test fixtures: `rg -l 'session_started' apps/web-platform/test/`
- [ ] 0.4 Verify cited line numbers (drift ≤ ±5 from plan): `rg -n 'updateConversationStatus.*"failed"' apps/web-platform/server/agent-runner.ts`
- [ ] 0.5 Verify second cited line range: `rg -n 'updateConversationStatus.*"waiting_for_user"' apps/web-platform/server/agent-runner.ts`
- [ ] 0.6 Find any cc-dispatcher or other module emitting `session_started`: `rg -n 'type.*session_started' apps/web-platform/server/`
- [ ] 0.7 Run union-widening consumer-pattern rails (per `cq-union-widening-grep-three-patterns`): three greps for `capabilities.{promptKinds,incomingTypes}` reads + `_exhaustive: never` near session_started.
- [ ] 0.8 If any cited line drifted by more than ±5, update the plan's line references in the same commit.

## Phase 1 — Conversation-writer extension (#3463 prerequisite)

- [ ] 1.1 Add `onlyIfStatusIn?: ReadonlyArray<Conversation["status"]>` field to `UpdateConversationOptions` in `apps/web-platform/server/conversation-writer.ts`.
- [ ] 1.2 In `updateConversationFor`, append `.in("status", options.onlyIfStatusIn)` to the base query when the option is provided.
- [ ] 1.3 RED: write failing tests in `apps/web-platform/test/conversation-writer-only-if-status.test.ts`:
  - 1.3.1 Given `onlyIfStatusIn: ["active"]` AND row at `status='active'`, the UPDATE applies.
  - 1.3.2 Given `onlyIfStatusIn: ["active"]` AND row at `status='waiting_for_user'`, the UPDATE is a 0-rows no-op AND `expectMatch: false` returns `{ ok: true }` silently.
  - 1.3.3 Given `onlyIfStatusIn` is omitted, the wrapper behaves identically to today.
- [ ] 1.4 GREEN: implement Phase 1 wrapper change.
- [ ] 1.5 REFACTOR: confirm `bun test apps/web-platform/test/conversation-writer-only-if-status.test.ts` passes.

## Phase 2 — Add helper + replace four call sites (#3463)

- [ ] 2.1 Add `updateConversationStatusIfActive(userId, conversationId, status)` helper in `apps/web-platform/server/agent-runner.ts` (sibling to existing `updateConversationStatus`). Implementation:
  - 2.1.1 Calls `updateConversationFor` with `expectMatch: false, onlyIfStatusIn: ["active"]`.
  - 2.1.2 Returns `Promise<void>` — never throws on 0-rows.
  - 2.1.3 Inline JSDoc names which call sites use it and why (per `2026-05-06-defense-in-depth-recovery-mirroring-sql-predicate-document-load-bearing-value.md`).
- [ ] 2.2 RED: write failing tests in `apps/web-platform/test/agent-runner-disconnect-after-result-race.test.ts`:
  - 2.2.1 AC1: result branch wrote `waiting_for_user`, then disconnect-abort fires; abort branch's UPDATE is a no-op (row stays `waiting_for_user`).
  - 2.2.2 AC2: disconnect-abort fires before any result emission; abort branch writes `failed` (today's behavior preserved).
  - 2.2.3 AC3: row already at `aborted` (concurrent user-stop), late disconnect-abort is a no-op.
  - 2.2.4 AC4: result-branch fallback `failed`-cascade at line 1646 is a no-op when row is at `aborted`.
  - 2.2.5 No Sentry mirror fires on the no-op outcomes (AC1, AC3, AC4).
- [ ] 2.3 GREEN: replace `updateConversationStatus` with `updateConversationStatusIfActive` at:
  - 2.3.1 Line ~1646 (result-branch fallback `failed`-cascade after `waiting_for_user` flip failure).
  - 2.3.2 Line ~1659 (result-branch fallback when `assistantPersisted = false`).
  - 2.3.3 Line ~1766 (abort branch's non-superseded write — primary site, value depends on `isUserRequested` ternary).
  - 2.3.4 Line ~1852 (non-abort thrown errors path).
- [ ] 2.4 KEEP `updateConversationStatus` (with `expectMatch: true`) at:
  - 2.4.1 Line ~1613 (result branch's primary `waiting_for_user` write).
  - 2.4.2 Line ~1640 (result-branch fallback's first attempt).
- [ ] 2.5 Confirm regression tests pass:
  - 2.5.1 `apps/web-platform/test/agent-runner-result-branch-finalization.test.ts`
  - 2.5.2 `apps/web-platform/test/abort-all-sessions.test.ts`
  - 2.5.3 `apps/web-platform/test/ws-abort.test.ts`

## Phase 3 — Capability extension (#3464)

- [ ] 3.1 Create `apps/web-platform/lib/ws-capabilities.ts`. Export `WS_INCOMING_TYPES = ["abort_turn"] as const`. If Phase 0.2 finds no canonical home for `promptKinds`, export `WS_PROMPT_KINDS` here too. Include header comment documenting curation criteria (stable agent contract only — feature-internal types excluded).
- [ ] 3.2 Extend `apps/web-platform/lib/ws-zod-schemas.ts:274-276` `capabilities` sub-schema with optional `incomingTypes: z.array(z.string()).readonly().optional()`.
- [ ] 3.3 Extend `apps/web-platform/lib/types.ts:242` `session_started` variant's `capabilities` shape: `{ promptKinds: readonly string[]; incomingTypes?: readonly string[] }`.
- [ ] 3.4 Update `apps/web-platform/server/ws-handler.ts:1194` (`start_session` emit) to thread `capabilities: { promptKinds: WS_PROMPT_KINDS, incomingTypes: WS_INCOMING_TYPES }`.
- [ ] 3.5 Update `apps/web-platform/server/ws-handler.ts:1252` (`resume_session` emit) to thread the same `capabilities` payload.
- [ ] 3.6 If Phase 0.6 surfaced any other emit site, thread the same payload there.
- [ ] 3.7 RED+GREEN: add `apps/web-platform/test/ws-handler-session-started-capabilities.test.ts`:
  - 3.7.1 AC5: `start_session` emit contains `capabilities.incomingTypes: ["abort_turn"]`.
  - 3.7.2 AC6: `resume_session` emit contains the same payload.
  - 3.7.3 AC7: zod schema parses `incomingTypes: ["abort_turn"]` successfully.
- [ ] 3.8 RED+GREEN: add type-level test `apps/web-platform/test/ws-handler-session-started-capabilities.test-d.ts`:
  - 3.8.1 AC8: `WSMessage` narrowing on `session_started` provides `capabilities?.incomingTypes` as `readonly string[] | undefined`.

## Phase 4 — Fixture sync

- [ ] 4.1 For each fixture in Phase 0.3, update the `session_started` shape so optional `capabilities` is consistent across tests.
- [ ] 4.2 No fixture pins `capabilities` as `undefined` unless explicitly testing legacy-server-build (E2 edge case).

## Phase 5 — Verification

- [ ] 5.1 `tsc --noEmit` clean from `apps/web-platform/`.
- [ ] 5.2 `bun test apps/web-platform/test/` green — including any `*.test-d.ts` exhaustiveness gates.
- [ ] 5.3 Local QA per Integration Verification: open Command Center, send "what is 2+2", close tab immediately on assistant reply, reopen — sidebar shows `waiting_for_user`, NOT `failed`.
- [ ] 5.4 WS frame inspection: confirm `session_started` carries `capabilities.incomingTypes: ["abort_turn"]`.

## Phase 6 — PR

- [ ] 6.1 PR body uses `Closes #3463` and `Closes #3464` on their own lines.
- [ ] 6.2 PR body includes `## Changelog` section with semver:patch label (bug fix + non-breaking optional-field add).
- [ ] 6.3 No DB migration, no infra change, no Doppler rotation — standard CI deploy.

## Sharp Edges Checklist

- [ ] No new Sentry mirror at the no-op site (success case, not a degraded fallback).
- [ ] `WS_INCOMING_TYPES` header comment names what is curated and what is excluded (feature-internal types).
- [ ] All four agent-runner guard sites use `onlyIfStatusIn: ["active"]` — the result branch's primary write at line 1613 is intentionally NOT guarded.
- [ ] Plan Phase 2 step 4 closes the typed-optional-field wire-drop loop on `promptKinds` (currently declared but not emitted) AND `incomingTypes` (newly added).
