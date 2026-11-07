---
title: "feat: approval card names the requester; reattach withholds action text from other members"
date: 2026-11-07
slug: approval-card-requester-and-reattach-redaction
branch: feat-one-shot-9601-approval-card-requester
issue: 9601
closes: []
type: feat
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# feat: approval card names the requester; reattach withholds action text from other members

Ref #9601 (agent security hardening epic). No closing keyword anywhere; `closingIssuesReferences` stays `[]`. No Standing Delegation.

Spec lane note: the branch has no `spec.md` (no brainstorm preceded this plan), so `lane:` defaults to `cross-domain` (fail-closed).

## Enhancement Summary

**Deepened on:** 2026-11-07
**Passes:** halt gates 4.6 to 4.13 (all green, mechanical), plan-review panel (DHH, Kieran, simplicity, architecture), sharp-edges verification, security-sentinel, user-impact-reviewer, test-design-reviewer, CTO / CLO / CPO / spec-flow / UX rulings (see `decision-challenges.md`).

### Key improvements
1. Security: the requester email now comes from the authoritative auth record (`auth.admin.getUserById`), not `public.users.email`, which any member can overwrite (migrations 006 and 178); the labeler proves the viewer is an Owner of the ROW's workspace inside one membership query; one 2 second deadline per lookup; `isUuid` before every filter.
2. Correctness: workspace-keyed memoisation, `requester` appended last in the first-send object (Guard-1 anchors G1-PL4, G1-PL5, G1-R9 stay intact, checked with the battery's `--check-anchors`), null-tenant role read now reports, `approved` rows are not re-sent to viewers who cannot see the action, a failed role read for a non-requester sends no frame.
3. Honest scope: attach is creator-only today, so limb (ii) is recorded as defence in depth; stale-tab, timeout, confusable-address, departed-requester and role-failure outcomes are accepted limitations (a) to (n) in the ADR addendum and named in User-Brand Impact.
4. Test design: fail-open stubs so Phase 0 is red on assertions, one strict PostgREST fake, injectable abort signal, ordering barriers instead of fixed sleeps, a role-classified sink scan, split and extended mutation rows M1 to M20 executed once in a sandbox.

### New considerations discovered
- The Team settings page reads the same member-writable `public.users.email` (pre-existing; recorded as residual (n), not edited).
- Sentry Replay and DOM capture are not configured (AC17 pins it).
- Landing-page label can sit in the browser Router Cache for up to 30 seconds (accepted).

## Overview

ADR-309 flip-checklist item 1 gates the `approval-queue` flag for any workspace with more than one member on three limbs: (i) the Owner card names the requester, (ii) `reattach` stops sending full action text to non-Owners, (iii) the decide path out of the agent process is closed or the sentinel gap is re-accepted. The CTO ruling of 2026-11-07 delivers limbs (i) and (ii) as ONE PR; limb (iii) stays open and the single-member cohort rule stays in force. This plan does exactly that and nothing else: no flag is created or flipped, no migration, no cohort widening.

Behaviour after the change:

- `reemitLiveApprovals` (session attach) sends the full `view` only when the attaching user is a verified Owner or the verified `requested_by_user_id` of that row. Everyone else gets, for `pending` rows, a redacted waiting frame: `view: null`, `toolName: "redacted"`, no `requester` key, no field value anywhere in the serialized frame; `approved` rows are not re-sent to a viewer who cannot see the action (plan-review simplification: an approved request is not a waiting card, and it removes a copy matrix that the server could never reach).
- An Owner card carries a minimised `requester` label: the literal `"you"` when the Owner is the requester, the requester's email when the requester is a current member of that workspace, `"a workspace member"` when `requested_by_user_id` is NULL (Art. 17 erasure) or the requester left. A failed lookup omits the key. A member who is the requester gets only the literal `"you"` and the full view; no other member ever gets a label.
- Surfaces carrying the label: the first send (`gate-flow.ts`), the reattach send, and the away-user landing page (CTO ruling: that is the surface a non-requester Owner actually uses). The stored inbox title (what push and email use) stays content-free (ADR-085); the Owner-only in-product enriched row (`inbox-enrich.ts`) names the action but is not a card and links to the landing page, which carries the label; it is untouched.
- ADR-309 item 1 and its archived `flag-create-handover.md` copy record limbs (i) and (ii) as implemented by this PR (tense conditional on merge) and limb (iii) as open.

## Research Reconciliation — Spec vs. Codebase

| Task claim | Reality (verified on this branch) | Plan response |
|---|---|---|
| "wire type already supports a read-only member card" | `viewerRole: "owner" \| "member"` exists, but `approval_request.view` is REQUIRED in `lib/types.ts` and non-nullable in the strict zod `approvalRequestSchema`; a member card today still carries the full view. | Make `view` nullable on the wire (CTO fork 1, option A) in `lib/types.ts`, `lib/ws-zod-schemas.ts`, `ChatApprovalMessage`, and the reducer. |
| "approval-request-card.tsx already tolerates view === null" | Half true: it accepts `view: ApprovalCardView \| null`, but computes `detailsRemoved: view === null`, so a null view on a PENDING member card renders the "Details removed" retention-scrub state, and `chat-state-machine.ts` reads `event.view.title` (a TypeError on null). | Card: `detailsRemoved = view === null && viewerRole !== "member"`; reducer: null-safe `content` fallback. Both pinned by tests. |
| "first send (gate-flow near line 397) ... carry a requester label" | The first send goes only to `a.userId`, the session user whose own agent proposed the action. For an Owner who is the requester the label is `"you"` with no read; it differs only when an identical live request was first raised by another member (the create RPC finds the existing live row). | Label derived from `submitted.approval.requested_by_user_id` against the viewer; the lookup runs only for an Owner viewer who is not the requester. |
| "Owner card names the requester" (limb i) | An Owner who is not the requester sees the card through the push -> away-user landing page (`app/(dashboard)/dashboard/approvals/[id]/page.tsx`), not through the first send. That page selects no `requested_by_user_id` today. | Landing page IN scope (CTO fork 4); otherwise limb (i) would be over-claimed. Inbox row stays out (its stored title is content-free by ADR-085 and the enriched in-product row links to the landing page). |
| "redacted waiting card ... approval-request-card.tsx tolerates it" | `reattach` can send `approved` rows; a redacted approved card would derive `released` copy ("Released to your agent"). Status frames (`approval_status`) go only to the decider and the requester (ws-handler), so a withheld card never sees a status change. | `reattach` skips `approved` rows when the viewer cannot see the action; the card test covers the withheld card in `pending` only, plus one defensive case: a withheld card handed a non-pending status never renders a bound block or the words "your agent". |
| "A member attaches to the conversation of the member whose agent asked" (the leak premise) | All three attach sites filter `conversations.user_id = userId` (resume_stream, resume_session, context_path resume in `server/ws-handler.ts`), so today the attacher is always the conversation's creator; a non-requester, non-Owner viewer arises only when `requested_by_user_id` is NULL or the live row was first raised by someone else in a conversation the viewer owns. | Limb (ii) is implemented as a defence-in-depth invariant that fires as soon as conversation sharing exists; the ADR addendum and the User-Brand Impact say so (no over-claim). The end-to-end handler test seeds a conversation owned by the member whose row has a NULL or different requester, otherwise `resume_stream` returns no conversation and the test is vacuous. |
| "NO new migration" | `list_live_approvals` returns `to_jsonb(row)`, so `requested_by_user_id` is already on `ApprovalRow`. `public.users` has `email` and no display name; RLS gives an Owner no read of other members' users rows. | Label comes from a service-role read scoped through `workspace_members` (the viewer must be an Owner and the requester a member of the ROW's workspace) and from the authoritative auth email (`auth.admin.getUserById`), NOT `public.users.email`, which any authenticated member can overwrite (migrations 006 and 178). New file `server/approval/requester-label.ts` goes on the CODEOWNERS-pinned `.service-role-allowlist`. |

## Research Insights

### Premise validation (Phase 0.6)

- #9601 is OPEN (`type/security`, epic). PR 12336 is this branch's own draft PR; the collision pre-check reported only that PR and an unrelated worktree's test run.
- ADR-309 item 1 and the handover copy: the item-1 blocks are byte-identical today (`diff` of the two `1. **Cohort rule` blocks printed SAME), so "edit both together" is a verifiable invariant.
- Proposed mechanism vs the ADR corpus: ADR-309 itself names this work as the cohort precondition; no ADR rejects redaction-by-null-view or a message-level requester label. The only adjacent decision is ADR-085 (push/email/inbox stay content-free), which this plan respects.
- Cited paths all exist on this branch: `server/approval/{reattach,gate-flow,render,view-model}.ts`, `lib/types.ts`, `lib/ws-zod-schemas.ts`, `components/chat/approval-request-card.tsx`, `test/chat-surface-approval.test.tsx`, migration 180.

### Property List and Cut List (Phase 0.6b)

Properties:

- P1. A member who is neither an Owner nor the row's requester receives no field value, action title, recipient, repository, branch, document path or real tool name on a session attach.
- P2. The Owner can tell which member's agent is asking, on every surface an Owner uses to decide (in-thread first send, reattach, away-user landing page).
- P3. An erased or departed requester never shows as a person; a failed lookup never shows a false statement.
- P4. The requester's email is read only for an Owner viewer, never stored, cached across attaches, logged, or sent to Sentry, push or email.
- P5. Client and server wire contracts change together and stay pinned by the strict schema and the wire-parity test.

Mechanisms in the ask and what already covers them: redaction by `viewerRole` alone (rejected in the ask itself: it would strip the requester's own details); a new migration or RPC for the label (cut: `requested_by_user_id` already rides `to_jsonb(row)`; the single-id read goes through the existing service client); a pseudonym label (cut: the ADR-029 pepper cannot ship to the browser, learning 2026-05-12). Cut List: no new RPC, no new table, no new column, no new Sentry alert rule (the new op is a warn-level degraded-display condition and rides the existing `approval-queue` feature tag).

### Institutional learnings applied

- `2026-05-07-typed-optional-field-wire-drop-caught-by-user-impact-reviewer.md`: an optional field is dropped silently at any explicit destructure hop (the reducer builds `card` field by field). Plan: copy `requester` explicitly in `chat-state-machine.ts` and assert it at the reducer, the card and the chat surface.
- `2026-10-06-i-claimed-a-mechanism-from-an-outcome-and-my-guards-pinned-the-builder-not-the-wire.md`: assert on the frame the client receives (serialized JSON of the real `send` argument), not on a helper's return value.
- `2026-09-19-my-fix-for-the-unpinned-wire-injected-the-seam-under-test.md`: the redaction tests drive the real `reemitLiveApprovals`, injecting only the DB/labeler seams, never a redactor.
- `2026-09-25-a-no-raw-id-claim-tested-at-the-call-args-missed-three-sinks-on-the-same-event.md` and `2026-06-04-redaction-fix-must-sweep-all-render-sinks-not-just-new-path.md`: the canary-absence check runs over the serialized frame AND over every mocked Sentry/logger call argument; the sink scan covers every caller of `renderApprovalView` under `server/`.
- `2026-10-29-hitl-approval-queue-the-fixes-were-the-defective-part-and-six-ci-guards-no-local-suite-selects.md`: run the service-role allowlist gate and the userId diff-grep before the first push; local vitest stays green while they fail.
- `2026-05-12-type-widening-cascades-and-write-boundary-sentinels.md`: widening `view` to `| null` needs the three-pattern consumer grep (AC below).
- `2026-05-25-closed-field-list-must-classify-at-value-shape-not-column-name.md`: the label is classified by the value sent (an email), not by the column name.

### Constraint facts from the code (for the work phase)

- Guard-1 mutation battery (`apps/web-platform/test/approval-guard1-mutation.test.sh`, 356 rows, `MIN_CHECKS=763`, run in CI only) anchors on exact source lines: gate-flow.ts `view: renderApprovalView(action),` (row G1-6); reattach.ts `isApprovalQueueEnabled({ userId: a.userId, workspaceId: w })` (G1-F6), `}) === approval.action_sha256;` (G1-D4) and `reportApprovalOp("keyUnavailable", null, {` (G1-KU2). This plan keeps all four lines byte-identical, renames no existing test, and adds no battery row, so the 356/763 literals are untouched and stay equal to the real counts. Per-file test floors in that script are minimums, so adding tests to the pinned files is allowed; existing test names a row relies on are not edited.
- `ops.test.ts` requires unique op names and messages across `APPROVAL_OPS`; `ops-sink.test.ts` iterates every key.
- `.service-role-allowlist` is per file and CODEOWNERS-pinned; gate: `bash apps/web-platform/scripts/service-role-allowlist-gate.sh`.

## Open Code-Review Overlap

Open `code-review` issues naming planned files: #3374 (`lib/ws-zod-schemas.ts`, `server/ws-handler.ts`: slot_reclaimed frame), #3242 (`lib/ws-zod-schemas.ts`, `lib/types.ts`: tool_use raw name), #2191 (`server/ws-handler.ts`: clearSessionTimers refactor), #2224 (chat polish) and #2220 (inject `idFactory` into `applyStreamEvent`), the last two naming `lib/chat-state-machine.ts` (JSX/idFactory purity, not the `approval_request` arm). Disposition: Acknowledge all five. Each concerns a different frame or a different ws-handler concern; this plan touches ws-handler.ts at one call site (the reattach argument list) and adds one optional field to a different message. They stay open.

## User-Brand Impact

**If this lands broken, the user experiences:** a workspace member's pending email, push or workflow request (recipient, subject, body, branch) re-sent in full to a colleague who attached to the same conversation; or an Owner approving a request with no idea whose agent raised it, or a member's own card replaced by a "Details removed" message while the agent waits. Concrete degraded outcomes, each an accepted limitation in the ADR addendum: a tab opened before the deploy drops the Owner-requester's own card (agent stalled until expiry or the landing page); a lookup timeout or error leaves the Owner deciding with no requester line; a failed role read leaves the requester with a read-only card or a non-requester Owner with no frame (inbox and landing page are the fallback); a redacted member card goes stale until expiry once the request is decided.

**If this leaks, the user's data / workflow is exposed via:** (data) the `approval_request` action text on the `approval_request` WebSocket frame sent by `reemitLiveApprovals` to an attaching member who is neither an Owner nor the requester (reachable today only for a NULL or foreign `requested_by_user_id`, and for any shared-conversation feature added later); (data) the requester's email shown to a non-Owner, to a user who is not in the workspace, in a Sentry event, a log line, a push or an email body; (workflow) an Owner approving an outward action raised by an unknown party.

**Brand-survival threshold:** single-user incident. CPO sign-off recorded at plan time (Domain Review: approved with conditions, all adopted except one noted decline); `soleur:engineering:review:user-impact-reviewer` runs at review time.

## Architecture Decision (ADR/C4)

Detection: the plan adds a cross-cutting invariant every consumer of the approval wire must honour (the withheld frame) and extends an existing ADR's flip checklist. The ADR write and the C4 edit are deliverables of THIS plan.

### ADR

Amend ADR-309 (no new ordinal, so no collision risk): (1) rewrite flip-checklist item 1 (conditional-on-merge tense, see Phase 5 for the exact text) and copy it verbatim into the archived handover; (2) add `### Addendum 2026-11-07 (Ref #9601): requester label and reattach redaction` recording the decision, the invariants and the accepted limitations:

- Decision: `view: null` on the wire is the only representation of "withheld" (option A). Rejected alternative (B): a server-built redacted `ApprovalCardView` of the same type, because a later change passing `renderApprovalView(action)` to a member would still compile and pass type checks; under A it must break the type and the tests.
- Decision: the requester label is message-level (`requester?: string`), not part of `ApprovalCardView`, because `ApprovalView` is built from the hashed canonical action alone and pinned by the wire-parity test.
- Invariants: strict-equality verified-requester comparison (`canSeeAction`), `viewerRole` read failure never widens access, the label is derived per attach and never stored, cached or logged, and only an Owner viewer can receive a label.
- Accepted limitations: (a) `approval_status` frames are not broadcast to other members and reattach skips `approved` rows for them, so a redacted member card stays "waiting" until expiry even across a reattach once the request is decided (reducer test for the sequence); its copy only says it is waiting and never asserts a decision; (b) a second member who re-asked an identical action is not the row's requester and is redacted on reattach; (c) a failed `viewerRole` read for a viewer who is not the verified requester sends no frame (reported by the existing `viewerRoleFailed` op, which now also covers the null-tenant path) and the next attach recovers; the inbox row and the landing page remain the fallback surfaces (Ruled by CTO agent, 2026-11-07, amending R2: a redacted waiting card shown to an Owner who could not be identified is misleading); (d) the redacted frame still discloses `requestCount`, `expiresAt` and `agentWaiting` (counts and times, no action text); (e) attach is conversation-creator-only today (`conversations.user_id = userId` at all three attach sites), so the reattach redaction is a defence-in-depth invariant that becomes reachable with shared conversations, not a closed live leak; (f) a browser tab opened before the deploy keeps the old strict schema and drops an `approval_request` frame carrying `requester` or `view: null` (signal `ws-zod-parse-failure`; the inbox row and the landing page are the fallback surfaces; revisit if the flag widens); (g) `requester-label.ts` is a service-role email-by-id read living in the agent-shared process, so who may import it is pinned by a test (gate.ts, ws-handler.ts and the landing page only) and recorded under "Residual risk: sentinel discipline"; (h) the new guard's mutation rows are proven by the new tests in this PR but are not added to the Guard-1 battery (356 rows, `MIN_CHECKS=763` stay untouched, equal to the real counts); adding battery rows is a named residual, not an issue (net issue flow 0). (i) an Owner can decide with no requester line when the lookup times out or errors (indistinguishable from the feature being absent; the card still shows the full action and Approve/Deny); a timeout trips the labeler instance so later lookups in the same attach omit immediately instead of costing 2 seconds each; (n) the Team settings page reads the same self-writable `public.users.email` for its member list (pre-existing, not edited here, recorded as residual); (j) confusable addresses between two current members (a homoglyph domain or a lookalike local part) are not disambiguated, the shape check only rejects whitespace, control characters and more than one `@`; (k) a requester who has left the workspace and attaches to their own conversation sees their own action (they proposed it, `consume_approval` still refuses with `requester_not_member`), by design, with no membership requirement in `canSeeAction`; (l) "a workspace member" covers erasure, departure and an unusable stored email alike; (m) a requester whose role read failed keeps the full view with `viewerRole: "member"` and the "Waiting for an Owner's approval" copy even if they are an Owner, until the next attach, with the landing page and inbox as the fallback.
- Open under the CLO ruling (not edited here): the PA-38 (c)/(d) sentence and the LIA extension stay owed under item 6 before the flag leaves the canary.

### C4 views

Read in full for this section: `knowledge-base/engineering/architecture/diagrams/model.c4` (1094 lines), `views.c4`, `spec.c4`. Enumeration: (a) external human actors: the workspace Owner is modelled (`founder`, description already says workspaces may have multiple Owners); a non-Owner workspace member is NOT modelled as an actor anywhere in the model, and adding one would model every member capability, which is outside this slice; recorded, not added. (b) external systems: none added (the Supabase edge `webapp -> supabase` already covers service-role reads of `users` / `workspace_members`). (c) data stores: `approvalStore` already modelled; no new store (nothing is persisted). (d) actor-to-surface access relationship that changes: the edge `webapp -> approvalStore` (model.c4, "Durable approval requests" block) describes the Owner decide path; it will gain one clause: card frames to a non-Owner non-requester member carry no action text (ADR-309 addendum 2026-11-07) and the requester label is read at render time, not stored. Edit that edge description directly in this PR, and append the same kind of clause to the `engine -> approvalStore` edge (model.c4, the next line: the gated branch runs in the agent process and now reads the requester label there): "requester label read at render time from users and workspace_members (service role, membership-scoped, not persisted)". No element, no relationship, no view change. Validate with `apps/web-platform/test/c4-code-syntax.test.ts`, `apps/web-platform/test/c4-render.test.ts` and `bash plugins/soleur/test/c4-count-parity.test.sh` (no derived count moves; the run proves it).

### Sequencing

The ADR describes the target state with merge-conditional tense; limb (iii) and the flag lifecycle are unchanged.

## Implementation Phases

Tests first (`cq-write-failing-tests-before`): Phase 0 lands red; every later phase turns named tests green. Run from `apps/web-platform`.

### Phase 0 — RED tests (no source change)

Seams that must exist before the tests can mean anything: `test/server/ws-handler-approval.test.ts` mocks `createServiceClient()` as `{ rpc, from: vi.fn(), auth }`, so `from()` returns `undefined` and a never-throwing labeler would silently produce no `requester` key; add a hoisted `h.serviceFrom` returning the membership and users rows. The handler wires the labeler as `createRequesterLabeler(() => supabase as unknown as RequesterQueryClient)`, reusing the file's existing lazy `supabase` proxy (the same shape as the adjacent `client: () => supabase` line). The end-to-end cases seed a conversation owned by the viewing member (attach is `conversations.user_id`-scoped).

Write the new test files and the additions below; run them against the unchanged tree and record which fail (expected: all new assertions on redaction, label, wire nullability, card states, reducer, scan) in the PR test plan.

1. `test/approval/reattach-redaction.test.ts` (new; drives the real `reemitLiveApprovals`, injecting only `client`, `viewerRole`, `isEnabled`, `send` and the `requesterLabel` seam; builds rows with the real `canonicalizeAction` / `computeActionHash` like `ws-handler-approval.test.ts`; canary strings in `subject`, `body`, recipient, repository and branch fields; synthesized `@example.com` addresses only).
2. `test/approval/card-visibility.test.ts` (new; the synchronous truth table for `canSeeAction` and `requesterKind`, including `undefined` and non-string inputs at runtime because `parseApprovalRow` only casts).
3. `test/approval/requester-label.test.ts` (new; the labeler against a fake query client).
4. `test/approval/render-sink-scan.test.ts` (new; whole-`server/` caller scan, see Guard Contract).
5. `test/approval/gate-flow-requester.test.ts` (new; first send, reuses the `gate-flow.test.ts` harness pattern; a new file so no existing named test is touched).
6. Additions: `test/approval/wire-parity.test.ts` (nullable view, requester field, strict-object rejections), `test/chat-state-machine-approval.test.ts` (null view, requester copy-through, redacted -> full upgrade, full -> redacted replacement), `test/components/approval-request-card.test.tsx` and `test/chat-surface-approval.test.tsx` (Owner label variants, withheld member card per status, requester "You requested this", no mailto, bidi-revealed label, no "Details removed"), `test/approval/landing-page.test.tsx` (requester line, leaver, erased, lookup failure, details-removed hides it, a row object without the `requested_by_user_id` key omits the label instead of showing the fallback), `test/server/ws-handler-approval.test.ts` (end-to-end attach as non-requester member and as Owner, with the `h.serviceFrom` seam above), `test/ws-zod-schemas.test.ts` (round-trip with `view: null` and a valid `requester`; the forged-field rejection test keeps passing for an unknown key), `test/approval/gate-flow-payload.test.ts` (the first-send frame has no `requester` key when no label applies), `test/approval/gate-deps.test.ts` (`createApprovalGateDeps(...).requesterLabel` is a function, which pins both the agent-runner and cc-dispatcher construction sites), `test/approval/approval-ops-real-sink.test.ts` (pass the now-required `requesterLabel` stub to `reemitLiveApprovals`; no named test edited), `test/feature-map.md` (add `data-testid="approval-requester"` to the `/dashboard/approvals/[id]` selectors), and `test/approval/copy-deck.test.ts` untouched but green with the new copy. One more reducer line: two redacted cards share `toolName: "redacted"`, so `hasNewerPendingRequest` can match them; the newer-request banner renders only in `pending_owner`, which a withheld card never is.

**Test strategy refinements (deepen-plan, test-design review).**

- Red for the right reason: the first Phase 0 commit adds signature-only, deliberately fail-open stubs (`canSeeAction = () => true`, the labeler returns `undefined`, `RequesterLabelFn` exported, `ReemitArgs.requesterLabel` optional until Phase 2) so the new tests fail on assertions, not at collection; AC1 lists the failures by test name.
- One strict PostgREST fake in `test/approval/fixtures.ts`: a phase-typed builder (`select`, `eq*`, `abortSignal`, `maybeSingle`) that throws a distinct `FakeContractError` on an unknown or out-of-order method and records `{table, columns, filters[], signalPresent, signalAborted}`. Used by `requester-label.test.ts`, the landing test (real labeler against the fake at the `@/lib/supabase/service` seam, not a mocked labeler), the `h.serviceFrom` seam and `gate-deps.test.ts` (which calls `deps.requesterLabel(otherUser)` and asserts the membership query's `workspace_id` equals `args.workspaceId`). Every omit or fallback test asserts the recorded chain reached `maybeSingle` and that the report's `extra.code` is the injected code, never `TypeError`. A type test (`expectTypeOf<ReturnType<typeof createServiceClient>>().toExtend<RequesterQueryClient>()`) bridges the `as unknown as` casts.
- Determinism: the timeout tests inject an `AbortController` through `opts.signal` (abort, await, assert `undefined`, one report, no email) and a separate `vi.spyOn(AbortSignal, "timeout")` case pins 2000 once per query; the `gate-flow` deadline goes through `boundedByAbort`'s `setTimeout`, so it uses `vi.useFakeTimers` plus a labeler that resolves late and must not mutate the frame already sent. The handler tests never assert absence behind the fixed 30 ms `settle()`: seed the skipped row first and a visible row second and `vi.waitFor` the visible frame before asserting the absence of the first; the null-tenant case is produced by making the tenant mint return null for that test; the new cases live in a NEW top-level `describe`, not inside `reattach re-send` / `describe.each(ATTACH_SITES)`.
- Battery names: new test titles must not contain any substring the Guard-1 rows name as a kill (for example `reattach re-send attach site: resume_stream flag on: the live card is re-sent`); AC6 adds a local `bash apps/web-platform/test/approval-guard1-mutation.test.sh --only 'G1-(F6|D4|RA[0-9]|KU[0-9])|G1-PL|G1-R9'` run for the rows on the three touched files.
- Sink scan: resolve each import edge to a file path (every in-tree importer uses `"./render"`, so a substring match on `approval/render` finds none), classify each hit by role (`import`, `call`, `reexport`, `namespace-member`, `other` = the red `unclassified` bucket), keep type-only imports out of the importer pin, split the census into a pure function with inline-source self-tests (aliased import, `export {..} from`, `export *`, `import * as R` with `R.renderApprovalView(`, dynamic `import()`, `require`, a call inside a string literal or after a regex containing `//`) and the filesystem walk, extend `test/approval/source-scan.ts` rather than importing helpers from `decide-boundary.test.ts`, and record computed-name access as a named residual.
- Detector sensitivity (H1 as a test): the same `expectNoLeak(frame, canaries)` helper must throw on a deliberately leaky stub frame and on an empty-fixture frame; a fixture precondition test asserts every canary is at least 12 ASCII-alphanumeric characters, distinct from every key name and non-empty. Leak absence runs as `it.each(CANARIES)` so a failure names the field; the key-set test uses `Object.keys` and `Object.hasOwn(frame, "requester") === false`.
- Execute the matrix once: run M1-M19 in an allocated sandbox (`scripts/soleur-sandbox.sh new test-design`, one restored copy per row, content-anchored with an exact occurrence count, pristine tree first as the instrument control) and paste the KILLED/SURVIVED table in the PR; no battery row is added.
- Trim: split scenario 4 and scenario 9 into separate tests; `chat-surface-approval` keeps one `requester` pass-through case (the label matrix lives in the card test); assert `dynamic === "force-dynamic"` with a whitespace-tolerant source match instead of importing `page.tsx`.

### Phase 1 — Wire, copy and state (client-reachable, no `@/server/*` imports)

- `lib/types.ts`: `approval_request` gains `view: ApprovalCardView | null` and `requester?: string`; comment states `null` means withheld from this viewer and nothing else on the wire.
- `lib/ws-zod-schemas.ts`: `view: approvalCardViewSchema.nullable()`, `requester: z.string().min(1).max(320).optional()` (320 = RFC 5321 path bound); stays a `z.strictObject`.
- `lib/approval-copy.ts`: add `REQUESTER_SELF = "you"`, `REQUESTER_FALLBACK = "a workspace member"`, `APPROVAL_COPY.requestedBy(label)` = "Requested by {label}", `APPROVAL_COPY.memberWaitingRedacted` = "An action in this conversation is waiting for an Owner's approval." (CPO wording), `APPROVAL_COPY.memberWaitingOwn` = "You requested this. Waiting for an Owner's approval." (CPO wording). No outcome words (copy-deck test).
- `lib/approval-card-state.ts`: no signature change; the card computes the new `detailsRemoved`. If a table test shows a clearer home, the helper `isViewWithheld(view, viewerRole)` lives here.

### Phase 2 — Server

- `server/approval/card-visibility.ts` (new, pure and synchronous): `canSeeAction(viewerUserId, isOwner, requestedBy)` returns true when `isOwner === true` OR (both ids satisfy `typeof id === "string" && id.length > 0` and `viewerUserId === requestedBy`, strict `===`; `undefined` counts as absent); `requesterKind(viewerUserId, isOwner, requestedBy)` returns `"self"` when the verified-requester comparison passes (any role), `"lookup"` for an Owner who is not the requester, `"none"` otherwise. Each call site does the single `await` itself (`"self"` -> `REQUESTER_SELF`, `"lookup"` -> the labeler, `"none"` -> no key), so the truth table stays synchronous. Export one shared type `RequesterLabelFn = (workspaceId: string, viewerUserId: string, requestedBy: string | null | undefined) => Promise<string | undefined>`, used by `ReemitArgs` and `ApprovalGateDeps`; the workspace is the ROW's `workspace_id` (reattach passes `approval.workspace_id`, gate-flow passes `submitted.approval.workspace_id`), never the attaching session's workspace, and a test drives the real `reemitLiveApprovals` with `a.workspaceId` = A and a row in B and asserts the labeler received B.
- `server/approval/requester-label.ts` (new): `createRequesterLabeler(getClient?: () => RequesterQueryClient)` (a small interface matching the REAL call chain `from(table).select(cols).eq(col, v)[.eq(col, v)].abortSignal(sig).maybeSingle()`, and `createRequesterLabeler(getClient?, opts?: { signal?: () => AbortSignal })` with the default `() => AbortSignal.timeout(2000)` so tests can inject an `AbortController`; the default resolves `createServiceClient()` on the FIRST `label()` call, never at construction or import) returns `label(workspaceId, viewerUserId, requestedBy)`: every id passes `isUuid` (`lib/is-uuid.ts`) before any query (a non-uuid requester -> `REQUESTER_FALLBACK` with no query and no report; a non-uuid viewer or workspace -> `undefined`); NULL, `undefined` or empty requester -> `REQUESTER_FALLBACK`; ONE `workspace_members` query for `(workspace_id = w) AND user_id in (viewer, requester)` selecting `user_id, role`: the labeler proceeds only if the VIEWER row has `role = 'owner'` (otherwise `undefined`, so the Owner-only property is proven inside the labeler, not left to caller discipline) and the requester row exists (otherwise `REQUESTER_FALLBACK`); then the email comes from the AUTHORITATIVE auth record, `client.auth.admin.getUserById(requestedBy)` -> `data.user.email` (precedent `server/notifications.ts`, `lib/supabase/tenant.ts`), NOT `public.users.email`, because migrations 006 and 178 grant `UPDATE (email)` on `public.users` to `authenticated`, so any member can write that column and make the Owner's card say "Requested by <colleague or a persuasive sentence>"; the value is returned only when it is a string of 1 to 320 characters with exactly one `@` and no whitespace or control characters (the zod cap and the guarantee that a real label can never collide with the in-band `"you"` and `"a workspace member"`), else fallback; any error -> report `requesterLabelFailed` (ids only, never the email) and return `undefined` (the key is omitted, because the fallback would assert a membership fact the code could not check). Memoises success AND failure per labeler instance (one instance per attach / per landing render) keyed by `${workspaceId}:${requestedBy}` (a conversation's rows can sit in different workspaces; an id-only key would show a member's email on another workspace's row), so a repeated pair is one read and one report. Never throws. One overall deadline of 2 seconds per `label()` call covers both reads: the PostgREST read carries `.abortSignal(<that signal>)` (precedent `lib/feature-flags/identity.ts`) and the `auth.admin` call, which has no abort support, is raced against a 2 second timer cleared on settle, so reattach's sequential row loop and the landing page's server render are bounded; a timeout takes the report-and-omit path and trips the labeler instance (later lookups in the same instance omit at once, so reattach's sequential loop costs at most one 2 second wait per attach; test rows: a never-resolving client that honours the abort signal, a reattach with three distinct requesters under one total deadline, a landing render that times out and still renders Approve and Deny, a gate-flow timeout through `boundedByAbort`, a homoglyph address and a quoted-local-part address handled per the shape rule). Both failure paths route through ONE report helper. A contract comment states the labeler is Owner-only by caller discipline; the importer-pin test below enforces who may call it.
- `server/approval/ops.ts`: add `requesterLabelFailed` = `{ op: "approval-requester-label-failed", message: "Approval card: the requester label could not be read; the card shows no requester line", level: "warn" }`.
- `server/approval/reattach.ts`: `ReemitArgs` gains REQUIRED `requesterLabel: RequesterLabelFn` (called as `a.requesterLabel(approval.workspace_id, a.userId, approval.requested_by_user_id)`; ws-handler is the only production caller, so a site that stops passing it fails type-check instead of silently dropping limb (i)). After the existing `viewerRole` block (the Guard-1 anchor lines untouched), the shape (whitespace-tolerant structural pins in the scan, behaviour pinned by the tests) is one `canSeeAction(` call whose result gates both `toolName: ... : "redacted"` and `view: ... renderApprovalView(action) : null`, with the single `renderApprovalView(` call occurring after the `canSeeAction(` call. The call text `renderApprovalView(` must not appear in comments in the scanned files.
- `server/approval/gate-types.ts` + `gate.ts`: `ApprovalGateDeps.requesterLabel?: RequesterLabelFn` (optional so existing harnesses compile); `createApprovalGateDeps` builds it from `createRequesterLabeler`; gate-flow calls it with the row's `workspace_id`, `a.userId` and `submitted.approval.requested_by_user_id` and takes a NEW `requesterQueryClient?: () => RequesterQueryClient` seam in `CreateApprovalGateDepsArgs` (the existing `serviceClient` seam is typed `() => ApprovalRpcClient`, rpc-only, and a never-throwing labeler would swallow the TypeError from a client without `from`, so a test using it would pass vacuously); `gate-deps.test.ts` injects a fake that has `from` and asserts `requesterLabel` is a function.
- `server/approval/gate-flow.ts`: first send keeps `view: renderApprovalView(action),` byte-identical (the viewer's own agent proposed this exact action) and adds a conditional `requester` key as the LAST property of the send object, after `agentWaiting: true,` (the battery rows G1-PL4 and G1-PL5 anchor on the neighbouring `expiresAt` / `requestCount` / `viewerRole` lines; the `viewerRole = "member"; // read-only card is the safe default` line of G1-R9 is also untouched). The key comes from `requesterKind` on `submitted.approval.requested_by_user_id`; the `"lookup"` case (Owner viewer, live row raised by another member) runs the labeler under a short deadline (about 2 seconds, through the existing `boundedByAbort` with a closure that captures the result) and omits the key on timeout, error or abort, so a hung read never delays the card while the agent waits.
- `server/ws-handler.ts`: pass `requesterLabel` (one labeler per `reattachApprovals` call, wired as `createRequesterLabeler(() => supabase as unknown as RequesterQueryClient)`) into `reemitLiveApprovals`; in the `viewerRole` closure replace `if (!tenant) return "member";` with `throw new Error("viewer role read failed")` so a null tenant is reported by the existing `viewerRoleFailed` op (behaviour stays fail-closed: the catch in reattach still yields `member`).
- `apps/web-platform/.service-role-allowlist`: one line for `apps/web-platform/server/approval/requester-label.ts` with a comment (what it reads, why it is scoped through `workspace_members`).
- `server/approval/view-model.ts`: export `interface StoredApprovalRowWithRequester extends StoredApprovalRow { requested_by_user_id: string | null }` (REQUIRED key, used by the landing page only; `inbox-enrich.ts` stays on the base type) so a `ROW_COLUMNS` that loses the column fails type-check, and a runtime row without the key omits the label instead of rendering the "left or erased" fallback.

### Phase 3 — Client

- `lib/chat-state-machine.ts`: `ChatApprovalMessage.view: ApprovalCardView | null` and `requester?: string`; the `approval_request` arm sets `content: event.view?.title ?? APPROVAL_COPY.memberWaitingRedacted` (the same string the card shows) and copies `requester: event.requester` explicitly (both in the fresh card and through the upsert spread). Server's latest word wins: no client-side guard that keeps an old non-null view when a later frame has `view: null` (decision recorded in `decision-challenges.md`).
- `components/chat/approval-request-card.tsx`: new prop `requester?: string`; `detailsRemoved: view === null && viewerRole !== "member"`; a `withheld` flag (`view === null && viewerRole === "member"`) renders no bound block. The pending member title is chosen in the `pending_member` case independently of `view`: `requester === REQUESTER_SELF` -> `APPROVAL_COPY.memberWaitingOwn` (the requester's own card keeps its full bound block), else `withheld` -> `APPROVAL_COPY.memberWaitingRedacted`, else `APPROVAL_COPY.nonOwnerWaiting`. A withheld card is only ever `pending` (the server skips `approved` rows and sends no status frames to it); the one defensive case, a withheld card handed a non-pending status, uses the neutral landing-style titles, the generic noun `request` and neutral badge/info strings, and never contains "your agent" or "continuing". The requester line is `<p data-testid="approval-requester">` with visible text `Requested by <span>{revealInvisible(label)}</span>`, outside the `aria-live` region and above the title; plain text node, `[overflow-wrap:anywhere]`, never truncated, never a link or markdown; hidden when the card is in `details_removed`. For `requester === "you"` and `viewerRole === "owner"` it reads "Requested by you".
- `components/chat/chat-surface.tsx`: pass `requester={msg.requester}`.
- `app/(dashboard)/dashboard/approvals/[id]/page.tsx` (the server component, the ONLY caller of the labeler on this surface; `approval-landing.tsx` is `"use client"` and must never import `requester-label.ts`, which would drag `lib/supabase/service` into the client bundle): add `requested_by_user_id` to `ROW_COLUMNS`, type the row as `StoredApprovalRowWithRequester`; after the Owner-RLS read succeeds (the `approval_request_owner_select` policy in migration 180 is `is_workspace_owner(workspace_id, auth.uid())`, pinned by a grep AC) compute `requester` (`"you"` when it equals `user.id`, else the labeler scoped to `row.workspace_id`, failure -> omitted, only when the view is non-null); `ApprovalLanding` receives a plain `requester?: string` prop and forwards it to the card, importing only `REQUESTER_SELF` from `lib/approval-copy`. The response must stay `Cache-Control: no-store` (`force-dynamic` plus the middleware's authenticated-document `no-store`; verified by a test reading `middleware.ts` behaviour or the existing header test, see Test Scenarios).

### Phase 4 — Wireframes, C4 and design artifacts

- `knowledge-base/product/design/approvals/approval-request.pen`: delta frames committed by the UX lead (Owner card with the three label variants in chat and landing layouts; redacted member waiting card; unchanged requester reference crop) and exported PNGs in `knowledge-base/product/design/approvals/screenshots/` (see Domain Review for the delivered paths).
- `knowledge-base/engineering/architecture/diagrams/model.c4`: the one edge-description edit described above.

### Phase 5 — ADR-309 and handover (edit both together)

Replace the item-1 block in `knowledge-base/engineering/architecture/decisions/ADR-309-durable-action-bound-approval-requests.md` and, byte for byte, the same block in `knowledge-base/project/specs/archive/20261029-164429-feat-hitl-approval-queue/flag-create-handover.md`. Target text (merge-conditional tense):

> 1. **Cohort rule: no workspace with more than one member gets the flag until limb (iii) is closed.** Limb (i) (the Owner card names the requester) and limb (ii) (`reattach` sends the full action text only to an Owner or the row's requester) are implemented by Ref #9601 PR #12336 and pinned by its tests; the statement holds from that PR's merge commit, not before. Limb (iii), the decide path out of the agent process (or the sentinel gap re-accepted), is open, so the flag stays limited to single-member workspaces. The label shown to the Owner is read at render time and not stored; the PA-38 (c)/(d) sentence and the LIA extension named by the CLO ruling of 2026-11-07 stay owed under item 6. Check the `workspace_members` count for the workspace before any per-workspace override, and **re-check it on every member invite**: inviting a second member to an enabled workspace takes it out of the cohort, so its override is removed first or in the same change.

Then the addendum described under Architecture Decision, as `## Addendum — 2026-11-07 (Ref #9601): requester label and reattach redaction` (H2 with an em dash, like the file's other addenda), placed before `## Ordinal history`.

Legal sweep (reported, not edited): other records carry the same "card goes to the attaching user" wording and stay accurate while limb (iii) is open and attach is creator-only: `knowledge-base/legal/compliance-posture.md` (the approval-queue row), `knowledge-base/legal/audits/2026-10-counsel-review-4672.md` (lines 74, 102, 112; line 74 says `reattach.ts` sends the card only to the attaching, requesting user, which this change makes more precise rather than false) and `knowledge-base/legal/audits/2026-10-29-approval-queue-b-canary-record.md` (lines 93, 102). No edit is owed; the CLO owns any rewording of line 74.

Run `bash scripts/markdown-lint.sh --repo-sweep` before committing the markdown (and `git add` the new files first: the script scopes to tracked files).

### Phase 6 — Verification

Targeted commands only (CI is the ship gate; the slow local `--affected` battery is not awaited and the PR test plan says so): the vitest files listed in Acceptance Criteria, `tsc --noEmit`, the service-role allowlist gate and self-test, the C4 tests, `python3 scripts/lint-guard-contract.py`, the markdown sweep, the `112xx` greps before every push.

## Files to Edit

- `apps/web-platform/server/approval/reattach.ts`
- `apps/web-platform/server/approval/gate-flow.ts`
- `apps/web-platform/server/approval/gate-types.ts`
- `apps/web-platform/server/approval/gate.ts`
- `apps/web-platform/server/approval/ops.ts`
- `apps/web-platform/server/approval/view-model.ts`
- `apps/web-platform/server/ws-handler.ts`
- `apps/web-platform/.service-role-allowlist`
- `apps/web-platform/lib/types.ts`
- `apps/web-platform/lib/ws-zod-schemas.ts`
- `apps/web-platform/lib/approval-copy.ts`
- `apps/web-platform/lib/chat-state-machine.ts`
- `apps/web-platform/components/chat/approval-request-card.tsx`
- `apps/web-platform/components/chat/chat-surface.tsx`
- `apps/web-platform/components/approvals/approval-landing.tsx`
- `apps/web-platform/app/(dashboard)/dashboard/approvals/[id]/page.tsx`
- `apps/web-platform/test/approval/wire-parity.test.ts`
- `apps/web-platform/test/chat-state-machine-approval.test.ts`
- `apps/web-platform/test/components/approval-request-card.test.tsx`
- `apps/web-platform/test/chat-surface-approval.test.tsx`
- `apps/web-platform/test/approval/landing-page.test.tsx`
- `apps/web-platform/test/server/ws-handler-approval.test.ts`
- `apps/web-platform/test/ws-zod-schemas.test.ts`
- `apps/web-platform/test/approval/gate-flow-payload.test.ts`
- `apps/web-platform/test/approval/gate-deps.test.ts`
- `apps/web-platform/test/approval/approval-ops-real-sink.test.ts`
- `apps/web-platform/test/feature-map.md`
- `knowledge-base/engineering/architecture/decisions/ADR-309-durable-action-bound-approval-requests.md`
- `knowledge-base/project/specs/archive/20261029-164429-feat-hitl-approval-queue/flag-create-handover.md`
- `knowledge-base/engineering/architecture/diagrams/model.c4`
- `knowledge-base/product/design/approvals/approval-request.pen`

Not edited, by instruction: migration 180, `apps/web-platform/server/dsar-export-allowlist.ts`, `docs/legal`, `.github`, `knowledge-base/legal/*` (the Art. 30 register wording is a legal-sign-off item), the `approval-guard1-mutation.test.sh` battery, any flag or environment.

## Files to Create

- `apps/web-platform/server/approval/card-visibility.ts`
- `apps/web-platform/server/approval/requester-label.ts`
- `apps/web-platform/test/approval/reattach-redaction.test.ts`
- `apps/web-platform/test/approval/card-visibility.test.ts`
- `apps/web-platform/test/approval/requester-label.test.ts`
- `apps/web-platform/test/approval/render-sink-scan.test.ts`
- `apps/web-platform/test/approval/gate-flow-requester.test.ts`
- `knowledge-base/product/design/approvals/screenshots/19-...` to `22-...` PNG exports (already committed by the UX lead in commit 395ead6761)
- `knowledge-base/project/specs/feat-one-shot-9601-approval-card-requester/tasks.md`
- `knowledge-base/project/specs/feat-one-shot-9601-approval-card-requester/decision-challenges.md`

No new suite reads outside `apps/web-platform` (the sink scan reads `server/` only), so nothing is added to `test/repo-wide-suites.ts`. No test adopts `gitFixtureEnv`.

## Guard Contract

### Guard 1 — approval-frame redaction and requester-label scope

**Property.** An `approval_request` WebSocket frame carries a field value, an action title or the real tool name only when its recipient is a verified Owner, the verified `requested_by_user_id` of that row, or (first send only) the socket user whose own agent proposed this exact action; and it carries a requester label only when the recipient is an Owner (or the literal `"you"` when the recipient is the verified requester).

**Assembly.** The property quantifies over every emit site of `type: "approval_request"` under `apps/web-platform/server/` (today `gate-flow.ts` first send and `reattach.ts`; `ws-handler.ts` only receives the type in a switch), every caller of `renderApprovalView(` under `apps/web-platform/server/` (`render.ts` definition, `view-model.ts` for the Owner-only landing page, `gate-flow.ts` exactly one, `reattach.ts` exactly one, pinned structurally: exactly one `canSeeAction(` call and exactly one `renderApprovalView(` call, the latter after the former), the single decision functions `canSeeAction` / `requesterKind` in `card-visibility.ts` that both emit sites share, the direct importers of `server/approval/requester-label` (exactly `server/approval/gate.ts`, `server/ws-handler.ts` and `app/(dashboard)/dashboard/approvals/[id]/page.tsx`), the strict client schema, and the reducer that copies the frame into `ChatApprovalMessage`. The chokepoint is `canSeeAction`; the first send is the one documented exception (`showAction` is true because the socket's own agent proposed that exact action), pinned by the scan rather than assumed. Members drift, assembly is structural: the scan walks `apps/web-platform/{server,app,lib,components}/**/*.{ts,tsx}` (non-test, recursive) and censuses the bare identifier `renderApprovalView`, the specifier `approval/render`, and `requester-label` in any quote form (static or dynamic import), each against an exact allow-list with counts and a red `unclassified` bucket, so a new module, an alias, a re-export or a client-tree import is covered without editing the test (Ruled by CTO agent, 2026-11-07).

**Mutation matrix.**

| # | Edit (must drive the named test RED) | Targets |
|---|---|---|
| M1 | reattach always renders: `mayView` replaced by `true` | non-requester canary test (frame contains the canary) |
| M2 | NULL `requested_by_user_id` treated as a match (`requestedBy == null \|\|`) | NULL-requester member test (redacted expected) |
| M3 | drop the non-empty guard so `"" === ""` passes | empty-string requester / empty attaching id test |
| M4a | `viewerRole` catch fallback changed from member to owner (or the owner test written as `viewerRole !== "member"`, so a runtime-garbage role such as `undefined` or `"admin"` counts as Owner) | role-failure tests and a garbage-role case: non-Owner |
| M4b | the `continue` after a failed role read for a non-requester deleted | role-failure test: unequal or NULL ids -> no frame |
| M5 | redacted frame keeps `toolName: approval.tool_name` | `toolName === "redacted"` assertion |
| M6 | second row after a compliant first: `mayView` computed once before the loop | two-row test (own row full, other member's row redacted in one attach) |
| M7 | a new `renderApprovalView(` caller added in `ws-handler.ts` (and a second caller added to `reattach.ts` outside the conditional) | the whole-`server/` sink scan |
| M8 | the Owner-viewer check inside the labeler removed (or the label resolver called for a non-Owner viewer) | labeler unit test: a member viewer produces zero `getUserById` calls and `undefined`; reattach spy: zero labeler calls for a member viewer |
| M20 | the label read from `public.users.email` instead of the auth record | labeler test: the `public.users.email` fake differs from the auth email and the card shows the auth email |
| M9 | label memo keyed by requester id only (workspace dropped from the key) or hoisted to module scope | cross-workspace test (same requester, member of workspace A and not of B, one labeler: B's row shows the fallback) and the two-attach test (the second attach re-reads) |
| M13 | a new value importer of `requester-label.ts` (for example a tool builder) | importer-pin test inside the sink scan |
| M10 | the email added to a `reportApprovalOp` `extra` | serialization test over every mocked report/logger call: email absent |
| M11 | scan walks zero files (path typo) | the scan's own floor: files scanned >= the count of known `server/approval/*.ts` files and every allowed caller found with its exact count |
| M12a | `requester` dropped from the reducer's fresh-card copy | reducer test: the field survives to `ChatApprovalMessage` and the rendered card |
| M12b | `requester` or `view` lost through the upsert spread | reducer tests: a later frame without `requester` clears the stale label; a full -> redacted replacement deep-equals a freshly built redacted card (no leftover `view`, `content` or `requester`) |
| M14 | the `approved && !mayView` skip deleted | scenario 8b |
| M15 | `requester` spread appended to the redacted frame | exact-key-set test (AC8) |
| M16 | gate-flow computes `requesterKind` with the owner flag hard-coded true | member viewer, row raised by another member: no `requester` key |
| M17 | `.abortSignal` dropped from one of the two labeler queries | the strict fake records `signalPresent` per call |
| M18 | the `@` / length / whitespace shape check removed | 321-character, no-`@`, quoted-local-part tests |
| M19 | fail-open on a membership error (return the email) | membership-error test: `undefined` plus one report |

**Harness rows.** H1 (edit the suite, must go RED): empty the canary from the fixture action so the Owner frame no longer contains it; the test named `canary is present in the Owner frame` must then fail, which proves an absence assertion on the redacted frame cannot pass on an empty fixture. H2 (must-PASS, non-canonical inputs): a Member who is the requester, and an Owner whose requester id differs from the viewer, both receive the full view (the Owner also a label); both differ from the canonical "Owner who is the requester" and prove the guard does not reject everything.

**Anchor.** No stored value is compared. The allowed-caller list in the scan is a literal in the test file, changed only in the same reviewed diff as the source it names, and the `.service-role-allowlist` line is CODEOWNERS-pinned; a weakening therefore needs a second reviewer's approval outside the commit.

## Observability

```yaml
liveness_signal:
  what: approval-requester-label-failed Sentry op (warn, feature=approval-queue); absence is the healthy state, and the op is the only runtime signal because the label is a display nicety
  cadence: per session attach and per landing render, deduplicated to one report per distinct requester id per attach
  alert_target: Sentry issue feed for feature=approval-queue (no new alert rule, deliberate: degraded display, the card still renders)
  configured_in: apps/web-platform/server/approval/ops.ts
error_reporting:
  destination: Sentry via reportApprovalOp (static message, ids only, never the email or database text)
  fail_loud: the card renders without the requester line and the failure is reported once; the lookup never denies or throws into the attach, and each of its two queries is bounded by a 2 second timeout (a timeout takes the same report-and-omit path)
failure_modes:
  - mode: requester lookup error (membership or users read fails)
    detection: approval-requester-label-failed op with extra {code, fn, errName}
    alert_route: Sentry issue, feature=approval-queue
  - mode: viewerRole read failure for a non-requester Owner on attach
    detection: existing approval-viewer-role-failed op (including the null-tenant path, which now throws into the same report)
    alert_route: Sentry issue, feature=approval-queue (no frame is sent to a non-requester viewer until the next attach; inbox and landing page remain)
  - mode: redaction regression (a future caller renders the view for a member)
    detection: render-sink-scan and reattach-redaction tests in the required CI test job (pre-merge; there is no runtime detector by design)
    alert_route: required CI check on the PR
logs:
  where: Sentry plus the pino warn mirror (ids only)
  retention: Sentry project default; no new log sink
discoverability_test:
  command: grep -c approval-requester-label-failed apps/web-platform/server/approval/ops.ts
  expected_output: "1"
  # second probe, same shape: grep -c requesterLabelFailed apps/web-platform/server/approval/requester-label.ts (both failure paths route through ONE report helper, so the count is the single known number 1; the first probe proves the op is defined, the second that the labeler emits it)
```

## GDPR / Compliance Gate

CLO ruling (2026-11-07): see `decision-challenges.md` row "Requester label form". Summary: no new Art. 30 processing activity (PA-38 covers the requester identity under Art. 6(1)(f)); full email taken from the authoritative auth record (not the member-writable `public.users.email`), membership-scoped (a former member shows the fallback), no masking (masked emails collide for jane@ / john@ and misattribution is the larger harm); nothing new stored; derived fresh per send, never cached across attaches, never in Sentry, logs, push, email, URLs or client storage; landing response `no-store`; Sentry Replay and DOM capture are not configured in the web app (checked: no replay or mask-all configuration in `sentry.client.config.ts`, `instrumentation*.ts` or `next.config.ts`), so no mask attribute is needed; AC17 keeps that grep at zero so enabling Replay later forces a decision; tests use `example.com` addresses only.

### soleur:gdpr-gate run (plan time, 2026-11-07, advisory)

**This is not legal review. Findings are heuristic. Consult `soleur:legal:clo` + `soleur:legal:legal-compliance-auditor` before merging.**

Trigger: the canonical regulated-path regex matches none of the planned files (checked against the Files to Edit and Files to Create lists), so the gate was invoked under extension trigger (b), brand-survival threshold `single-user incident`, plus the new processing of a member's email shown to the Owner. Corpus freshness: 12 days since `last-verified` (under the 30-day banner). The audit was a manual pass over the plan text with the five v1 checks; nothing was written to `compliance-posture.md`, no issue was opened, and nothing under `docs/legal` or `knowledge-base/legal` was edited.

| check_id | Result |
|---|---|
| `GDPR-Art-6` | No new schema column, so no `LAWFUL_BASIS` annotation is owed. The display of the requester identity to the Owner is the purpose PA-38 already records under Art. 6(1)(f) (CLO ruling). Severity: none. |
| `GDPR-Art-5e` | Nothing is stored: the label is derived at render time, memoised only for one attach, never persisted or cached. Severity: none. |
| `GDPR-Art-17` | `requested_by_user_id` is `ON DELETE SET NULL` and the Art. 17 anonymise RPC nulls it; NULL renders the fixed fallback and a departed member renders the same fallback, both tested. Severity: none (positive). |
| `GDPR-Chapter-V` | No new vendor, SDK or env var. The label and the redacted frames do not enter agent or model context; the plan adds no Anthropic-bound path. Severity: none. |
| `GDPR-Art-9` | No special-category column or value. Severity: none. |

Suggestions (no `Critical`, no `Important`):

- Art. 5(1)(c) minimisation: the CLO chose the full email scoped to current workspace members over a masked form (masked forms collide in small teams). Keep the membership scoping test (non-member -> fallback) as the load-bearing control.
- Art. 32 confidentiality: no email in Sentry/logs/push/email/URLs/client storage (AC8 plus the M10 mutation row), landing response `no-store`, plain-text rendering with `revealInvisible`. Replay and DOM capture are not configured today (AC17 pins it).
- Art. 13/14 transparency: a requester may not expect their email on an Owner's card; the CPO placed that disclosure in member/invite copy, and the PA-38 (c)/(d) sentence plus LIA extension remain owed before the flag leaves the canary (ADR item 1 and item 6 carry the debt; operator and CLO own the wording).
- DPIA: not triggered by this change on its own (no new large-scale or special-category processing); the surrounding feature's DPIA posture is unchanged.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "apps/web-platform/server/approval/reattach.ts: the attaching user gets the full `view` only if they are an Owner or the row's requested_by_user_id; every other member gets a redacted waiting card with no field values" | Phase 2 reattach.ts + card-visibility.ts; Phase 3 card | mapped |
| 2 | "The Owner card names the requester: both the first send (server/approval/gate-flow.ts, near line 397) and the reattach send carry a minimised requester label read from the existing requested_by_user_id column (migration 180; NO new migration), falling back to \"a workspace member\" when NULL" | Phase 2 requester-label.ts, gate-flow.ts, reattach.ts, gate.ts, ws-handler.ts | mapped |
| 3 | "Extend ApprovalCardView / approval_request in lib/types.ts and lib/ws-zod-schemas.ts with an optional requester field; card renders it; keep wire-parity test green." | Phase 1 types/zod; Phase 3 card; wire-parity additions | mapped (field placed on `approval_request`, not inside `ApprovalCardView`, by CTO ruling) |
| 4 | "Tests first (red then green): non-requester member reattach receives no action text (canary string absent from the payload); requester and Owner still receive the full view; NULL requester case; Owner card shows the requester." | Phase 0 and Test Scenarios | mapped |
| 5 | "ADR-309 item 1 and its archived flag-create-handover.md copy (edit both together) record limbs (i) and (ii) as discharged, limb (iii) open, single-member cohort rule still in force. Use tense that matches the evidence." | Phase 5 | mapped |
| 6 | "Plan must run the GDPR gate (member label shown to the Owner)." | GDPR / Compliance Gate section and the gate run | mapped |
| 7 | "Do not widen the cohort." | no flag or override work; ADR text keeps the cohort rule | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| reattach.ts, card-visibility.ts | "the attaching user gets the full `view` only if they are an Owner or the row's requested_by_user_id" (ask 1) | asked |
| gate-flow.ts, gate-types.ts, gate.ts, ws-handler.ts, ops.ts | "both the first send ... and the reattach send carry a minimised requester label" (ask 2) | asked |
| requester-label.ts | "minimised requester label read from the existing requested_by_user_id column" (ask 2) | asked |
| `.service-role-allowlist` line | — | inferred — justification: the new file reads `users` and `workspace_members` with the service client, and the CODEOWNERS-pinned allowlist gate rejects any unlisted importer |
| lib/types.ts, lib/ws-zod-schemas.ts, lib/approval-copy.ts | "Extend ApprovalCardView / approval_request in lib/types.ts and lib/ws-zod-schemas.ts with an optional requester field" (ask 3) | asked |
| `view: ... \| null` on the wire, chat-state-machine.ts, approval-card-state use | — | inferred — justification: a redacted frame needs a representation of "no values", and the reducer reads `event.view.title` (a TypeError on null); CTO ruling fork 1 |
| approval-request-card.tsx, chat-surface.tsx | "card renders it" (ask 3) | asked |
| landing page.tsx, approval-landing.tsx, view-model.ts | "The Owner card names the requester" (ask 2) | inferred — justification: the landing page is the surface a non-requester Owner decides on; leaving it unlabelled would over-claim limb (i) in the ADR; CTO ruling fork 4 |
| render-sink-scan.test.ts | "reattach ... every other member gets a redacted waiting card with no field values" (ask 1) | inferred — justification: a redaction rule without a pin on every `renderApprovalView` caller rots when the next caller is added (the leak class this gate exists for) |
| model.c4 edge edits (both approvalStore edges) | — | inferred — justification: the C4 completeness mandate of plan Phase 2.10; the gated branch (and now the requester-label read) runs in the agent process, so the `engine -> approvalStore` edge would otherwise misdescribe the card path |
| extra consumer test edits (ws-zod-schemas, gate-flow-payload, gate-deps, approval-ops-real-sink, chat-message-exhaustiveness, feature-map) and the requester-label importer pin | — | inferred — justification: each is a consumer of the widened `approval_request` type or of the new required argument (the three-pattern consumer grep), and the importer pin is the only control on who may call a service-role email read in the agent-shared process |
| `viewerRole` closure throws on a null tenant (ws-handler.ts) | — | inferred — justification: without it the fail-closed redacted card for a non-requester Owner is silent, contradicting the observability claim that the existing `viewerRoleFailed` op reports it |
| `approved` rows skipped for a viewer who cannot see the action | "every other member gets a redacted waiting card with no field values" (ask 1) | asked — a card for an approved request is not a waiting card; the skip removes a state matrix the server cannot reach |
| .pen delta frames and PNGs | — | inferred — justification: `wg-ui-feature-requires-pen-wireframe`; the card component is a UI surface |
| ADR-309 and handover edit | "ADR-309 item 1 and its archived flag-create-handover.md copy (edit both together)" (ask 5) | asked |
| decision-challenges.md, tasks.md | — | inferred — justification: the process contract persists every ruling as a row and the work phase derives from tasks.md |

### Split Assessment

- Subsystems touched: 5 — `apps/web-platform/server`, `apps/web-platform/lib`, `apps/web-platform/components`, `apps/web-platform/app`, `knowledge-base`
- Planned files: 26 edited + 10 created | Estimated changed lines: about 900 including tests
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — the CTO ruling of 2026-11-07 fixes the boundary ("deliver limbs (i) and (ii) as ONE PR"), and the strict zod wire object means the server and the client must change together or an Owner gets no card while the agent waits.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1. Red-first evidence: the Phase 0 tests were run on the unchanged tree and the failing names are listed in the PR test plan; the same files are green at the end.
- [ ] AC2. `cd apps/web-platform && ./node_modules/.bin/vitest run test/approval test/server/ws-handler-approval.test.ts test/chat-surface-approval.test.tsx test/components/approval-request-card.test.tsx test/chat-state-machine-approval.test.ts test/ws-zod-schemas.test.ts test/legal-acceptance/service.test.ts test/middleware.no-store.test.ts` exits 0 (`legal-acceptance/service.test.ts` asserts op and message uniqueness across `APPROVAL_OPS` plus `LEGAL_OPS`, so the new op can break it from outside the approval directory; `middleware.no-store.test.ts` gains a case for a document request to `/dashboard/approvals/<uuid>` and an assertion that the page exports `dynamic === "force-dynamic"`).
- [ ] AC3. `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` exits 0 (proves every `approval_request` consumer compiles with `view` nullable).
- [ ] AC4. Consumer grep for the widening (three patterns; `tsc --noEmit` in AC3 is the canonical enumerator and these are the cross-check): `git grep -nE "\b(event|msg|card|old|m|message)\.view\b" -- apps/web-platform/lib apps/web-platform/components apps/web-platform/hooks apps/web-platform/app` (today prints `chat-state-machine.ts` `event.view.title` / `view: event.view` and `chat-surface.tsx` `view={msg.view}`, plus `page.tsx`'s `read.view`), `git grep -n "ChatApprovalMessage" -- apps/web-platform`, `git grep -n "approval_request" -- apps/web-platform/lib apps/web-platform/hooks apps/web-platform/components`; every hit is null-safe or irrelevant, listed in the PR body.
- [ ] AC5. `git grep -n "renderApprovalView(" -- apps/web-platform/server` lists only `render.ts` (definition), `view-model.ts`, `gate-flow.ts` (1) and `reattach.ts` (1, inside `canSeeAction(`); the scan test enforces it.
- [ ] AC6. Battery anchors intact: `bash apps/web-platform/test/approval-guard1-mutation.test.sh --check-anchors` exits 0 (the script's own no-test-run mode: it applies every row's edit to a pristine copy and reports each anchor mismatch, so it covers the rows beyond the four below, for example G1-PL4, G1-PL5 and G1-R9 in the `gate-flow.ts` send object); plus `git grep -c -F 'view: renderApprovalView(action),' -- apps/web-platform/server/approval/gate-flow.ts` prints 1; `git grep -c -F 'isApprovalQueueEnabled({ userId: a.userId, workspaceId: w })' -- apps/web-platform/server/approval/reattach.ts` prints 1; `git grep -c -F '}) === approval.action_sha256;' -- apps/web-platform/server/approval/reattach.ts` prints 1; `git grep -c -F 'reportApprovalOp("keyUnavailable", null, {' -- apps/web-platform/server/approval/reattach.ts` prints 1; the `--only 'G1-(F6|D4|RA[0-9]|KU[0-9])|G1-PL|G1-R9'` subset run is optional locally (it runs vitest per row; CI runs the full battery and is the ship gate, so it is not awaited); `git diff origin/main...HEAD --stat -- apps/web-platform/test/approval-guard1-mutation.test.sh` prints nothing (battery untouched; 356 rows and `MIN_CHECKS=763` unchanged and still equal to the real counts).
- [ ] AC7. `bash apps/web-platform/scripts/service-role-allowlist-gate.sh`, `bash apps/web-platform/test/ci/service-role-allowlist-gate.test.sh` and `bash apps/web-platform/scripts/constraint-gates.sh` exit 0 (the last proves no client module, notably the `"use client"` `approval-landing.tsx`, reaches `lib/supabase/service`); `git grep -n -A4 'CREATE POLICY approval_request_owner_select' -- apps/web-platform/supabase/migrations/180_approval_request.sql` shows `is_workspace_owner(workspace_id, auth.uid())` (the landing page's label is gated on that Owner-only read).
- [ ] AC8. The redacted-frame wire test asserts the exact key set `{type, approvalId, conversationId, toolName, view, status, expiresAt, requestCount, viewerRole, agentWaiting}` with `toolName === "redacted"`, `view === null`, no `requester` key, and the canary (and every canonical field value, the requester uuid and the requester email) absent from `JSON.stringify(frame)`.
- [ ] AC9. No file under `apps/web-platform/supabase/` changed: `git diff origin/main...HEAD --name-only | grep -c 'apps/web-platform/supabase/'` prints 0 (`grep -c` exits 1 when it prints 0; read the printed number, do not chain on the exit code); `server/dsar-export-allowlist.ts`, `docs/legal` and `.github` untouched (same command with those paths prints 0).
- [ ] AC10. ADR lockstep: `diff <(sed -n '/^1\. \*\*Cohort/,/^2\. /p' knowledge-base/engineering/architecture/decisions/ADR-309-durable-action-bound-approval-requests.md) <(sed -n '/^1\. \*\*Cohort/,/^2\. /p' knowledge-base/project/specs/archive/20261029-164429-feat-hitl-approval-queue/flag-create-handover.md)` prints nothing; the text names limbs (i) and (ii) as implemented by the PR with merge-conditional tense, (iii) open, and the cohort rule in force; it contains no sentence saying the cohort is unblocked.
- [ ] AC11. C4: both edge descriptions (`webapp -> approvalStore`, `engine -> approvalStore`) carry the new clause; `apps/web-platform/test/c4-code-syntax.test.ts`, `apps/web-platform/test/c4-render.test.ts` and `bash plugins/soleur/test/c4-count-parity.test.sh` pass.
- [ ] AC12. `python3 scripts/lint-guard-contract.py knowledge-base/project/plans/2026-11-07-feat-approval-card-requester-and-reattach-redaction-plan.md` exits 0; `bash scripts/markdown-lint.sh --repo-sweep` exits 0 before committing markdown.
- [ ] AC13. Before every push both printed lists are empty: `git diff origin/main...HEAD -U0 | grep '^+' | grep -E '\b112[0-9]{2}\b' | grep -v 11258` and `git log origin/main..HEAD --format=%B | grep -E '\b112[0-9]{2}\b' | grep -v 11258`.
- [ ] AC14. Wireframe artifacts exist and are non-empty on disk (`.pen` plus the exported PNGs) and the paths are referenced in the PR body.
- [ ] AC15. PR body: "Ref #9601" only, a Changelog section, the test plan records that the slow local `--affected` battery was not awaited because CI is the ship gate, and `decision-challenges.md` rows are rendered; none of the prohibited words.
- [ ] AC16. Diff scope is a subset of the planned surface: `git diff origin/main...HEAD --name-only | grep -vE '^(apps/web-platform/(server|lib|components|app|test)/|apps/web-platform/\.service-role-allowlist$|knowledge-base/(INDEX\.md$|engineering/architecture/(decisions/ADR-309-|diagrams/model\.c4$)|product/design/approvals/|project/(plans/2026-11-07-feat-approval-card-requester|specs/(feat-one-shot-9601-approval-card-requester/|archive/20261029-164429-feat-hitl-approval-queue/flag-create-handover\.md$))))'` prints nothing (no `knowledge-base/legal`, `test/repo-wide-suites.ts`, battery script, migration or workflow file). Run after `git add` of the new files so the allowlist gate (which enumerates with `git ls-files`) sees `requester-label.ts`.
- [ ] AC17. `git grep -n -i -E 'replayIntegration|maskAllText|blockAllMedia' -- apps/web-platform/sentry.client.config.ts apps/web-platform/instrumentation.ts apps/web-platform/next.config.ts` prints nothing (Replay and DOM capture stay unconfigured, so the requester email reaches no capture; enabling it later requires masking `data-testid="approval-requester"`).

### Post-merge (operator)

- None. No flag, environment, migration, secret or deploy step is part of this change; the flag stays dark and the single-member cohort rule stays in force.

## Test Scenarios

Reattach (`reattach-redaction.test.ts`, real `reemitLiveApprovals`, rows hashed with the real canonical code):

1. Owner attaches, not the requester: full view, `viewerRole: "owner"`, `requester` equals the labeler's email; canary present (positive control).
2. Owner is the requester: full view, `requester === "you"`.
3. Member is the requester: full view, `viewerRole: "member"`, `requester === "you"`, labeler never called. Variant with `requested_by_user_id` absent (`undefined`) and a member viewer: redacted.
4. Non-requester member: `view === null`, `toolName === "redacted"`, no `requester` key; serialized frame lacks the canary, every canonical field value, the requester uuid and email; `agentWaiting`, `requestCount`, `expiresAt`, `status` present.
5. NULL requested_by: member -> redacted; Owner -> `requester === "a workspace member"`.
6. Empty-string requested_by with empty-string attaching id: member -> redacted.
7. `viewerRole` rejects: equal ids -> full view with `viewerRole: "member"`; unequal ids (including a NULL requester) -> no frame at all for that row; the `viewerRoleFailed` op is reported in both; the null-tenant path of the handler's `viewerRole` closure also reports it (it now throws instead of returning `member`).
8. Two rows in one attach (own row, then another member's row): first full, second redacted (M6).
8b. An `approved` row with a viewer who cannot see the action is skipped (no frame); a `pending` row for the same viewer is the redacted frame.
9. Labeler spy: zero calls for any member viewer; one call for two rows with the same workspace and requester (memoised); a second attach re-reads (no cross-attach cache); the same requester in two workspaces (member of one) gets the email for one row and the fallback for the other; labeler failure -> frame sent without the `requester` key, one report, no email in any report argument.
10. Hash-mismatch and key-unavailable behaviour unchanged (existing tests stay green).

First send (`gate-flow-requester.test.ts`): Owner requester -> `"you"` and no lookup; member requester -> `"you"`; Owner viewer where the existing live row was raised by another member -> labeler email; same row, member viewer -> full view and no `requester` key; labeler throws -> frame still sent, key omitted; `requesterLabel` dep absent -> no key (back-compat with every existing harness).

Labeler (`requester-label.test.ts`): a member viewer -> `undefined` with zero `getUserById` calls; a non-uuid requester -> fallback with no query; the email comes from `auth.admin.getUserById` and a differing `public.users.email` fake is ignored; the single membership query carries the row's workspace; requester not a member -> fallback; member with email -> the email; NULL/empty id -> fallback without a query; empty email -> fallback; membership or users error -> `undefined` plus one report with no email; a 321-character email and an email without `@` -> fallback; memoises success and failure keyed by workspace and requester; reports once per distinct pair per labeler; never throws on a malformed client; the default client is not created until the first `label()` call.

Pure (`card-visibility.test.ts`): synchronous truth table for `canSeeAction` (owner true; equal non-empty ids true; NULL, `undefined`, empty, unequal, case-differing ids false) and `requesterKind` (`self` / `lookup` / `none`).

Wire (`wire-parity.test.ts`): zod accepts `view: null` and a `requester`, rejects an unknown key, an empty or over-320 `requester`, and a missing `view`; `ApprovalView` keys have no `requester`.

Reducer: null view -> `content` is the fixed waiting copy and contains no action text; `requester` survives; a later full frame upgrades a redacted card to `pending_owner` with Approve/Deny; a later redacted frame replaces a full card (server's latest word wins; a role-read failure sends no frame, so it cannot downgrade a held card).

Card (happy-dom, no layout engine, so wrapping is asserted as the `[overflow-wrap:anywhere]` and `min-w-0` classes on the label element): Owner label variants ("Requested by jane@example.com", "Requested by you", "Requested by a workspace member"); label is a text node (no `a[href^="mailto:"]`), a bidi-override address is revealed, a 254-character address carries the wrap classes; the line sits outside the `aria-live` region; withheld member card in pending shows the CPO copy, no bound block, never "Details removed"; the defensive case (a withheld card handed a non-pending status) never contains "your agent" or "continuing" and shows no bound block; member requester card keeps its full bound block and reads "You requested this. Waiting for an Owner's approval."; `details_removed` hides the requester line; Owner with a null view (landing scrub) still derives `details_removed`.

Landing: requester email for a current member, "you" for the Owner, fallback for a leaver and for NULL, no line (and no 500) on a lookup failure, no line when the view is null; response headers `no-store` (assert against the repo's existing header test or middleware unit, not a new live request).

End-to-end through the handler (`ws-handler-approval.test.ts`): attach as a non-requester member over `resume_stream` -> the frame the socket receives has `view: null`; attach as Owner -> full view plus label.

Sink scan: whole-`server/` caller pin plus its own floors (M7, M11); the existing `decide-boundary` and `runner-census` suites stay green.

## Domain Review

**Domains relevant:** Engineering, Legal, Product

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Ruled by CTO agent, 2026-11-07, on six forks (full text in `decision-challenges.md`): nullable `view` (option A) with the member state derived in the card; message-level `requester?: string`; a shared labeler module for first send, reattach and landing; landing page in scope, inbox out; cohort rule unchanged; requester keeps the full view with fail-closed strict-equality guards (amended an earlier all-member-redaction note); redacted frame sends `toolName: "redacted"`; the literal `"you"` goes to any verified requester. Refinement of R5, confirmed by the CTO: no frame-builder module, because the Guard-1 battery anchors on exact emit-site lines; the shared pure functions plus the whole-`server/` scan carry the single-chokepoint property instead, the `canSeeAction` call goes after the hash-verification and key-unavailable lines, and every anchor string is `grep -F`-checked before pushing (AC6).

### Legal (CLO)

**Status:** reviewed
**Assessment:** Ruled by CLO agent, 2026-11-07: no new Art. 30 activity (PA-38 covers it); full email scoped to current workspace members; no masking; fresh per send, never cached or logged; no Critical findings; High item (membership scoping) adopted; moderate items (no-log, no-Sentry, `no-store`, example.com fixtures, Replay masking check) adopted. PA-38 (c)/(d) sentence and LIA extension stay owed under ADR item 6 and are not edited here.

### Product/UX Gate

**Tier:** blocking (mechanical override: `components/chat/approval-request-card.tsx` matches `components/**/*.tsx`)
**Decision:** reviewed
**Agents invoked:** soleur:product:spec-flow-analyzer, soleur:product:cpo, soleur:product:design:ux-design-lead
**Skipped specialists:** none
**Pencil available:** see Findings (wireframe delta delivered by the UX lead; paths recorded below)

#### Findings

- CPO sign-off: approved with conditions. Adopted: redacted-card wording, the Owner and requester wordings, same fallback for a removed member, plain-text email (no mailto, no markdown), no outcome words, flag stays dark and no sentence says the cohort is unblocked. Declined with reason: "truncate visually if long, full text on hover" conflicts with the card's rule that values are never truncated (a hidden tail defeats the bidi/lookalike defence); the label wraps instead (`taste` row in `decision-challenges.md`).
- spec-flow (12 gaps) resolved: gap 1 (details_removed ambiguity) by the new `detailsRemoved` predicate and neutral titles; gap 2 (reducer TypeError) by the null-safe `content`; gaps 3 and 4 (downgrade / upgrade) by server-latest-word-wins plus tests; gap 5 (no status broadcast) recorded as accepted limitation (a) in the ADR addendum; gap 6 (rollout skew on a strict schema) by shipping server, schema and client in one PR, a schema test, and accepted limitation (f) in the ADR addendum (a browser tab opened before the deploy keeps the old strict schema and drops frames carrying `requester` or `view: null`, which includes every Owner-requester first send; the flag is dark and the cohort single-member, so the cost is a card that does not appear until expiry or the next landing-page visit); gap 7 (label as a trust-boundary value) by `revealInvisible`, wrapping and no link; gap 8 (three causes, one string) by omitting the key on a lookup error; gap 9 (landing leaver) by the landing tests; gap 10 (screen reader) by the visible "Requested by" prefix outside the live region; gap 11 (other leak paths) by the exact-key-set wire test and recorded disclosure (d); gap 12 (first send cannot be redacted) by the shared pure functions and the documented first-send exception.
- Wireframes: delivered by the UX lead and committed on this branch (commit 395ead6761): four delta frames appended to `knowledge-base/product/design/approvals/approval-request.pen` (the 9 original frames untouched) and PNG exports `knowledge-base/product/design/approvals/screenshots/19-approval-owner-pending-requester-line-label-variants-desktop.png`, `20-approval-owner-pending-requester-line-mobile-landing.png`, `21-approval-member-waiting-redacted-no-action-details.png`, `22-approval-requester-member-own-card-unchanged-reference.png`. Not yet reviewed by a human (async review). Reconciliations: frame 21 shows the earlier title "Waiting for the workspace Owner" and keeps the countdown; the CPO wording "An action in this conversation is waiting for an Owner's approval." governs the title in code (`taste` row in `decision-challenges.md`), the countdown stays (`expiresAt` is time, not action text; accepted disclosure (d)); the thread transcript around the card is out of scope (attach is creator-only, limitation (e)).

## Sharp Edges

- The Owner's browser Router Cache (`staleTimes.dynamic: 30` in `next.config.ts`) is not governed by `Cache-Control`; it can hold the landing page's RSC payload, including the label, for up to 30 seconds. `no-store` covers HTTP caches and bfcache; the cross-user case is covered by the existing hard-navigation invariant. Accepted.
- `requester-label.ts` must never build filter strings (`.or()`, `.filter()`, template literals); only `.eq()` / `.in()` on ids that passed `isUuid`.
- The email comes from the auth record, not `public.users.email` (member-writable). Do not "simplify" it back to a single `users` select.
- A plan whose `## User-Brand Impact` section is empty, contains only filler text, or omits the threshold fails `deepen-plan` Phase 4.6; this one is filled (single-user incident).
- The strict zod object rejects unknown keys: if `requester` is emitted by the server before the schema accepts it, every Owner card is dropped by the client parse while the agent stays blocked. Server, schema and client change in one PR.
- `requested_by_user_id` is the stored requester; a second member re-asking an identical live action does not change it. The card therefore says who raised the live request, which can differ from the viewer's own agent; that is the stored fact and is what the ADR addendum states.
- Do not add a `112xx` issue number anywhere in this PR's diff or commit messages; `#11636`, `#4672` and `#9601` are fine, and the two guard greps run before every push.
- `.service-role-allowlist` is CODEOWNERS-pinned: the PR needs the code owner's approval for that one line; this is not an operator step beyond the normal review.
- The Art. 30 register and compliance posture are legal-wording documents: this PR does not edit them; the ADR text only records that the sentence and LIA extension remain owed.
