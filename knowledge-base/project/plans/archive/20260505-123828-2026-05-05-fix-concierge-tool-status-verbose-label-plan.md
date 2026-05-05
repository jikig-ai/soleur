---
type: bug-fix
classification: ui-bug
requires_cpo_signoff: false
---

# fix: Concierge tool-status chip shows raw "Read" instead of verbose "Reading <path>..."

## Enhancement Summary

**Deepened on:** 2026-05-05
**Sections enhanced:** Risks, Hypotheses, Files to Edit, Acceptance Criteria, Test Scenarios, Sharp Edges
**Research signals used:** static codebase verification (grep + Read), learning #2861 / #2428 cross-reference, test-fixture pattern check, sibling-emitter audit

### Key Improvements

1. **Risk #1 corrected** — original plan claimed `await fetchUserWorkspacePath(userId)` would be a relocation, not a new round trip. Code reading shows `realSdkQueryFactory:419-423` runs only on **cold-Query construction**, NOT every turn (per `realSdkQueryFactory` source comment + `getSoleurGoRunner` singleton wiring). Adding the resolution in `dispatchSoleurGo` introduces ONE Supabase RTT per turn (acceptable; symmetric with the existing `kb-document-resolver:113` call on text-inline path).

2. **Sibling-emitter audit clean** — `rg 'type:\s*"tool_use"' apps/web-platform/server/` returns exactly two emitters: `cc-dispatcher.ts:721` and `agent-runner.ts:1049`. The agent-runner already routes through `buildToolLabel`. After fix, both server-side `tool_use` emitters share identical label-building semantics — no third emitter to update.

3. **Test-fixture pattern locked in** — `cc-dispatcher.test.ts:1-30` uses `vi.mock("@/server/observability")` + `vi.hoisted` for Sentry mocking and `__resetDispatcherForTests`. The new RED test follows this pattern. The dispatcher test suite's `realSdkQueryFactory` path is stubbed (per the file header comment "real-SDK queryFactory path is stubbed (throws — runner's own reportSilentFallback fires)") — so the new test must inject a stub runner via `__resetDispatcherForTests` then drive `events.onToolUse` synthetically. Pattern source: `soleur-go-runner.test.ts` (the file's own header points there for end-to-end dispatch coverage).

4. **No conflicting test pins** — `ws-streaming-state.test.ts:307` already asserts `toolLabel` equals `"Reading file..."` (the FALLBACK path); `tool-use-chip.test.tsx` uses synthetic verbose labels (`"Routing via /soleur:go"`), not derived from `block.name`. Zero tests in the suite pin the BUGGY behavior (`label === "Read"`).

5. **No sensitive-path scope-out gap** — `cc-dispatcher.ts` matches the canonical sensitive-path regex (`apps/web-platform/server/`), so `## User-Brand Impact` carries an explicit `threshold: none, reason: ...` bullet per `hr-weigh-every-decision-against-target-user-impact` + `deepen-plan` Phase 4.6.

### New Considerations Discovered

- **`onText` narration also leaks raw paths.** `cc-dispatcher.ts:711-718` forwards `text` blocks verbatim from the model. If the model narrates "I'm reading /tmp/claude-XXXX/workspace/foo.pdf" before the tool_use fires, that absolute-path leak goes through `onText` → `stream` event → client-side `formatAssistantText` scrub. **Out of scope for this PR** — the client-side scrub (`lib/format-assistant-text.ts`) already covers this surface. Confirmed by `tool-labels.ts:34` re-export comment: "the client render scrub (`lib/format-assistant-text.ts`) shares the same regex table."

- **Bash verb allowlist gap (potential telemetry noise).** `BASH_VERB_LABELS` in `tool-labels.ts:108-121` covers 12 common verbs. cc_router skill paths can call `git`, `gh`, `find`, `rg`, `grep`, `cat`, `ls`, `npm`, `bun`, `doppler`, `terraform`, `tofu` — all already covered. Verbs NOT covered that cc_router could plausibly emit: `awk`, `sed`, `jq`, `head`, `tail`, `mkdir`, `cp`, `mv`. These would map to `"Working…"` and fire `reportSilentFallback`. **Mitigation:** monitor `feature: command-center, op: tool-label-fallback` Sentry events for one week post-merge; widen the allowlist iteratively if a single verb dominates. Not a blocker for this PR.

- **Test-pattern parity with `agent-runner` path.** The legacy `agent-runner.ts:1049` path covers Domain Leaders' tool_use events; the new cc-dispatcher path covers Concierge cc_router. After fix, both surfaces converge on `buildToolLabel`. This means **a single test on `tool-labels.ts` ground truth** (already covered by `build-tool-label.test.ts`) protects both surfaces.

## Overview

In the shared-doc Concierge thread (KB chat sidebar), the in-progress tool-status chip displayed beneath the "Soleur Concierge / Working" header shows only the **raw SDK tool name** (e.g., `Read`, `Bash`, `Grep`) instead of the human-readable activity label produced by `buildToolLabel` (e.g., `Reading Au Chat Potan - Presentation Projet-10.pdf...`).

The verbose label appears to "flash" briefly because the agent narrates intent in a `text` block first ("I'll read the PDF..."), which renders in `state: "streaming"`. As soon as the SDK emits the `tool_use` block, the bubble transitions to `state: "tool_use"` and `<ToolStatusChip label={toolLabel} />` renders the **bare tool name**, replacing the previous streaming text. Users see "Read" and cannot tell which file or what operation is in progress.

**Root cause:** `apps/web-platform/server/cc-dispatcher.ts:719-725` emits `label: block.name` (the raw SDK name like `Read`/`Bash`) while the legacy `apps/web-platform/server/agent-runner.ts:1041-1052` correctly routes the same event through `buildToolLabel(toolName, toolBlock.input, workspacePath)` which produces verbose, scrubbed activity labels (`Reading <relative-path>...`, `Searching for "<pattern>"...`).

The Concierge path was introduced in #2858 (Stage 2 SDK-as-router foundation) and has emitted the bare tool name since day one. The bug surfaced visibly only once the cc_router had a real bubble (post-stream-start) so the chip rendered through `MessageBubble.toolLabel` rather than the chip-message branch — and especially in PDF-summarization where the verbose label would have been most informative.

## User-Brand Impact

**If this lands broken, the user experiences:** an unreadable progress indicator in the Concierge thread chip — the user cannot tell whether the agent is reading a PDF, running a Bash command, searching code, or reading the wrong file. They lose trust that the agent is actually engaging with the document they opened.

**If this leaks, the user's data is exposed via:** N/A — fix removes a leak. The current bare-name path bypasses `stripWorkspacePath`. Once routed through `buildToolLabel`, sandbox/workspace paths are scrubbed via the canonical `SANDBOX_PATH_PATTERNS` table.

**Brand-survival threshold:** none — display-only UX bug; no credentials, payments, or user-owned data at risk.

- `threshold: none, reason: cc-dispatcher.ts is in apps/web-platform/server/ (sensitive-path regex hit) but the diff is a label-text routing change with zero credentials/auth/data-flow surface; the change incidentally tightens by adding sandbox-path scrub to a path that previously bypassed it, so net direction is more conservative, not less.`

## Hypotheses

Two explanations were considered:

1. **Two separate `tool_use` events**, one with verbose label then one with bare name, racing on the wire. **Rejected** — only one emitter (`cc-dispatcher.onToolUse`) fires per SDK `tool_use` block in the cc_router path; `agent-runner` would fire only for sub-agent spawns (separate `leaderId`).

2. **The "flash" is the agent's `text` block narration ("Reading the PDF...") rendered in `state: "streaming"`, immediately replaced when the SDK emits `tool_use` and the bubble transitions to `state: "tool_use"` rendering `<ToolStatusChip label={toolLabel} />` with the bare name.** **Confirmed by code reading** — `chat-state-machine.ts:362-367` overwrites `toolLabel: event.label` on every `tool_use` event, and the dispatcher is the source of `event.label`.

The fix targets hypothesis 2.

## Research Reconciliation — Spec vs. Codebase

| Initial framing | Codebase reality | Plan response |
| --- | --- | --- |
| Bug "lives in shared-doc concierge thread component" | Bug lives **server-side** in `cc-dispatcher.ts` `onToolUse` callback — the chip component (`message-bubble.tsx`'s inline `ToolStatusChip`) renders whatever `toolLabel` arrives. `kb-chat-content.tsx` and `chat-surface.tsx` are downstream of the WS event, not the source. | Fix in `apps/web-platform/server/cc-dispatcher.ts`. Verify by re-reading the screenshot's flow: server WS event → `chat-state-machine.ts:365 toolLabel: event.label` → `MessageBubble` → `ToolStatusChip`. |
| "Truncated 'Read'" suggests a string-truncation bug | Not truncation — `Read` is the **full raw SDK tool name**. The dispatcher never invokes `buildToolLabel` to expand it into the verbose label. | Plan invokes `buildToolLabel` server-side; no client-side change needed. |
| Recent PR #3225 (kb-concierge idle window) related | #3225 raised idle window 30s→90s and added per-block reset. Did **not** touch `onToolUse` or `tool_use` event shapes. The label bug pre-dates #3225 (introduced #2858). | Reference #3225 only as adjacent context; no carryover assumptions. |

## Files to Edit

- `apps/web-platform/server/cc-dispatcher.ts` — change `onToolUse` (line 719-725) to call `buildToolLabel(block.name, block.input, workspacePath)` and pass the result as `label`. Add `import { buildToolLabel } from "./tool-labels"` to the existing import block. Resolve `workspacePath` once at the top of `dispatchSoleurGo` via `await fetchUserWorkspacePath(userId)` (already imported at line 64). Wrap in try/catch with `reportSilentFallback({ feature: "command-center", op: "cc-dispatcher-workspace-resolve", extra: { userId } })` per `cq-silent-fallback-must-mirror-to-sentry`; on catch, set `workspacePath = undefined` so `buildToolLabel` still produces the verbose label (just unscrubbed).
- `apps/web-platform/test/cc-dispatcher.test.ts` — extend with a new `describe` block (e.g., `"dispatchSoleurGo onToolUse label routing (#<this-pr>)"`) using the existing `vi.hoisted` + `__resetDispatcherForTests` fixture pattern. Inject a stub runner that synchronously fires `events.onToolUse({ name: "Read", input: { file_path: "<stub-workspace>/Au Chat Potan.pdf" }, toolUseId: "t1" })`. Assert the captured WS `tool_use` event's `label` is `"Reading Au Chat Potan.pdf..."` AND does NOT contain the stub workspace prefix AND is NOT `"Read"`. Add a second test for the workspace-resolve fallback (mock `fetchUserWorkspacePath` to throw, assert label is verbose-but-unscrubbed AND `mockReportSilentFallback` was called once with `op: "cc-dispatcher-workspace-resolve"`).
- **Do NOT touch** `apps/web-platform/test/cc-dispatcher-real-factory.test.ts` — that file exercises the real `realSdkQueryFactory` cold-construction path; its `onToolUse` shape is downstream of the same fix and is covered by the `tool-labels.ts` ground-truth test (`build-tool-label.test.ts`). One fixture for the dispatcher's WS-emit shape is sufficient; double-coverage would create maintenance churn for a 1-line server change.

## Files to Create

- None.

## Open Code-Review Overlap

`gh issue list --label code-review --state open --json number,title,body --limit 200` returned 18 open issues. Cross-referencing the plan's edit list:

- `apps/web-platform/server/cc-dispatcher.ts` → `#2962: review: extract memoized getServiceClient() shared lazy singleton` mentions `cc-dispatcher` but is scoped to `getServiceClient()` memoization. Disposition: **acknowledge** — orthogonal concern (singleton extraction vs. label routing); fix would not benefit from coupling to this lifecycle change.
- `#2955: arch: process-local state assumption needs ADR + startup guard` mentions `cc-dispatcher` only in passing. Disposition: **acknowledge** — architectural ADR work, not a behavior fix.
- `apps/web-platform/test/message-bubble*.test.tsx` → `#2221: test(chat): replace TestBubble proxy with real MessageBubble in memo test` is scoped to memo-test plumbing. Disposition: **acknowledge** — test infrastructure refactor, unrelated to label-content correctness.

None: the bug fix touches different concerns than the open scope-outs; folding in would conflate unrelated cleanups with a P1 UX regression.

## Implementation Phases

### Phase 1 — RED: failing test exposing the bug

**Test-fixture pattern:** the `cc-dispatcher.test.ts` file's header comment explicitly defers end-to-end dispatch coverage to `soleur-go-runner.test.ts` ("real-SDK queryFactory path is stubbed (throws — runner's own reportSilentFallback fires)"). The new test must inject a stub runner via `__resetDispatcherForTests` then drive `events.onToolUse` synthetically — do NOT try to wire a real `realSdkQueryFactory` path. **Verify the existing `vi.mock("@/server/observability")` block + `mockReportSilentFallback` exposure (lines 1-10) are sufficient to assert Sentry mirroring on the workspace-resolve fallback case.**

Add a unit test in `apps/web-platform/test/cc-dispatcher.test.ts`:

```ts
// New test inside the existing dispatchSoleurGo describe block.
it("routes tool_use label through buildToolLabel (verbose, scrubbed)", async () => {
  // Stub runner that yields a synthetic SDKAssistantMessage with a tool_use block.
  const sentMessages: WSMessage[] = [];
  const sendToClient = (_userId: string, msg: WSMessage) => {
    sentMessages.push(msg);
    return true;
  };
  // Inject a stub workspace path resolver that returns a known sandbox path.
  // (Use the existing test plumbing for fetchUserWorkspacePath stubbing —
  //  confirm the pattern in cc-dispatcher-concierge-context.test.ts before
  //  picking a stub strategy.)
  const stubWorkspace = "/tmp/claude-XXXX/workspace";
  const stubRunner = makeStubRunner({
    onIterate: (events) =>
      events.onToolUse({
        name: "Read",
        input: { file_path: `${stubWorkspace}/Au Chat Potan.pdf` },
        toolUseId: "tool_use_1",
      }),
  });
  setSoleurGoRunner(stubRunner);

  await dispatchSoleurGo({
    userId: "u1",
    conversationId: "c1",
    userMessage: "Summarize this PDF",
    currentRouting: null,
    sessionId: "s1",
    sendToClient,
    persistActiveWorkflow: async () => {},
    artifactPath: "Au Chat Potan.pdf",
    documentKind: "pdf",
  });

  const toolUseEvent = sentMessages.find((m) => m.type === "tool_use");
  expect(toolUseEvent).toBeDefined();
  // Must NOT be the bare SDK tool name.
  expect(toolUseEvent?.label).not.toBe("Read");
  // Must be the buildToolLabel output, with workspace prefix scrubbed.
  expect(toolUseEvent?.label).toBe("Reading Au Chat Potan.pdf...");
});
```

Run: `bun run test apps/web-platform/test/cc-dispatcher.test.ts`. Confirm the new test fails with `Expected "Read" not to be "Read"` (current behavior emits the bare name).

### Phase 2 — GREEN: route onToolUse through buildToolLabel

Edit `apps/web-platform/server/cc-dispatcher.ts`:

1. Import `buildToolLabel`:

   ```ts
   import { buildToolLabel } from "./tool-labels";
   ```

   (Append to the existing import block; the file already imports `fetchUserWorkspacePath` and `reportSilentFallback`.)

2. In `dispatchSoleurGo`, resolve `workspacePath` once before constructing `events`:

   ```ts
   const workspacePath = await fetchUserWorkspacePath(userId);
   ```

   Place after the `getSoleurGoRunner` call (~line 708) so the resolution is visible to the `events` closure. **Failure mode:** if `fetchUserWorkspacePath` throws or returns `undefined`, fall back to `undefined` — `buildToolLabel` already handles `workspacePath: undefined` (path stays absolute but is still verbose). Wrap in try/catch with `reportSilentFallback({ feature: "command-center", op: "cc-dispatcher-workspace-resolve", ... })` per `cq-silent-fallback-must-mirror-to-sentry`.

3. Update `onToolUse`:

   ```ts
   onToolUse: (block) => {
     sendToClient(userId, {
       type: "tool_use",
       leaderId: CC_ROUTER_LEADER_ID,
       label: buildToolLabel(block.name, block.input, workspacePath),
     });
   },
   ```

Run the failing test from Phase 1 and confirm it passes. Run the full `bun run test apps/web-platform/test/cc-dispatcher*.test.ts` suite to verify no regressions.

### Phase 3 — Manual QA on the actual screen

1. Start the dev server: `bun run dev:web-platform`.
2. Open a KB document that is a PDF (the Au Chat Potan PDF or any PDF in `knowledge-base/`).
3. Open the Concierge sidebar, ask "Can you please summarize this document?" (the exact prompt from the screenshot).
4. Watch the chip beneath "Soleur Concierge / Working":
   - **Before fix:** the chip reads `Read`.
   - **After fix:** the chip reads `Reading <pdf-filename>.pdf...`.
5. Also exercise `Bash` (e.g., a workflow that triggers a shell command) and `Grep` (e.g., "search this doc for X") — confirm verbose labels (`Searching code` / `Searching for "..."...`) instead of bare names.
6. Take a Playwright screenshot via MCP and attach to the PR for visual diff.

### Phase 4 — Verification grep (sentinel)

Confirm no other WS-event emitters in the codebase emit `label: block.name` or equivalent raw-tool-name shortcuts:

```bash
rg -n 'label:\s*block\.name|label:\s*toolName(?!\b.*buildToolLabel)' apps/web-platform/server/
```

Expected: zero matches after Phase 2. If any survive, route them through `buildToolLabel` in the same PR (do not defer).

Also `rg -n 'type:\s*"tool_use"' apps/web-platform/server/` to enumerate every `tool_use` emitter and confirm each invokes `buildToolLabel`.

## Acceptance Criteria

### Pre-merge (PR)

- [x] New unit test in `cc-dispatcher.test.ts` asserts `tool_use` event `label` equals `buildToolLabel(name, input, workspacePath)` output for at least the `Read` case, with verbose path-aware label and absolute workspace prefix scrubbed.
- [x] `cc-dispatcher.ts` `onToolUse` invokes `buildToolLabel(block.name, block.input, workspacePath)` instead of `block.name`.
- [x] `workspacePath` is resolved once per `dispatchSoleurGo` invocation and reused in the `onToolUse` closure (no per-tool-use `fetchUserWorkspacePath` call — that would be N×DB round trips).
- [x] `fetchUserWorkspacePath` failure is mirrored to Sentry via `reportSilentFallback` per `cq-silent-fallback-must-mirror-to-sentry`; fallback path uses `workspacePath: undefined` (still verbose, just unscrubbed prefix).
- [x] Phase 4 grep returns zero matches for `label: block.name` style shortcuts in `apps/web-platform/server/`.
- [x] `vitest run test/cc-dispatcher*.test.ts` passes (56/56).
- [x] `tsc --noEmit` passes.
- [ ] Screenshot attached to PR showing the Concierge chip reading `Reading <pdf>.pdf...` (NOT `Read`) on the same flow as the bug screenshot. *(deferred to QA phase)*
- [ ] `Closes #<issue-number>` in PR body (issue to be filed at session end if not already tracked). *(set in ship phase)*

### Post-merge (operator)

- [ ] **Sentry watch (week 1)** — monitor `feature: command-center, op: tool-label-fallback` events for one week post-merge. If a single Bash verb dominates the fallbacks (e.g., `awk`, `sed`, `jq`, `head`, `tail` — all currently uncovered in `BASH_VERB_LABELS`), file a follow-up to widen the allowlist. Threshold: more than 50 events/day on a single uncovered verb → file follow-up.
- [ ] **Sentry watch (week 1)** — monitor `feature: command-center, op: cc-dispatcher-workspace-resolve` events. If Sentry shows the workspace-resolve fallback firing at all, the `users.workspace_path` row is missing or the Supabase service-role key is misconfigured — investigate before treating it as benign telemetry.
- [ ] No infra apply, no migration. Vercel deploys on merge to `main`.

## Domain Review

**Domains relevant:** none

This is a server-side bug fix that swaps one already-existing function call (`block.name`) for another already-existing function call (`buildToolLabel(block.name, block.input, workspacePath)`). No new architecture, no new user-facing surface, no new dependencies, no privacy/security implications beyond an incidental tightening (sandbox-path scrub now applies to cc_router events too — strict win). Product domain is NONE per the gate's mechanical-escalation rule (no new files in `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx`).

## Test Scenarios

1. **Read with relative path** — `tool_use { name: "Read", input: { file_path: "<workspace>/foo.pdf" } }` → label `"Reading foo.pdf..."`.
2. **Read without input** — `tool_use { name: "Read", input: undefined }` → label `"Reading file..."` (FALLBACK_LABELS path).
3. **Bash with known verb** — `tool_use { name: "Bash", input: { command: "rg foo" } }` → label `"Searching code"`.
4. **Bash with unknown verb** — `tool_use { name: "Bash", input: { command: "weird-verb args" } }` → label `"Working…"` (`reportSilentFallback` fires; verified by spy on the observability mock).
5. **Workspace-resolution failure** — `fetchUserWorkspacePath` throws → `workspacePath` is `undefined` → label is verbose but unscrubbed (`"Reading /tmp/claude-XXXX/workspace/foo.pdf..."`); Sentry mock receives one call.
6. **Multiple sequential tool_use events** — three consecutive `Read` calls on different paths → three sequential WS events with three distinct verbose labels (no caching of label across events).

## Risks

- **Hot-path async** — `await fetchUserWorkspacePath(userId)` adds one Supabase RTT per `dispatchSoleurGo` call. **Correction from initial plan:** this IS a new round trip on warm-Query turns. `realSdkQueryFactory:419-423` runs only at **cold-Query construction** (the runner caches the live Query per conversation; subsequent turns reuse the existing Query and never re-enter `realSdkQueryFactory`). Per the runner's streaming-input semantics, only the FIRST turn of a conversation pays the realSdkQueryFactory's resolution; turns 2..N currently pay zero. Adding the resolution to `dispatchSoleurGo` makes every turn pay one RTT. Acceptable cost: this is the same shape as `kb-document-resolver:113`'s text-inline path (which also fires per-turn for non-PDF documents). Wrap in try/catch with `reportSilentFallback({ feature: "command-center", op: "cc-dispatcher-workspace-resolve", ... })` per `cq-silent-fallback-must-mirror-to-sentry`; fallback to `workspacePath: undefined` so `buildToolLabel` still produces the verbose label (just unscrubbed). **Do NOT plumb `workspacePath` through `DispatchSoleurGoArgs` in this PR** — that's a wider refactor (ws-handler caller, `dispatchSoleurGoForConversation`, `resolveConciergeDocumentContext` all currently resolve independently). File a follow-up issue with re-evaluation criteria "if Sentry shows >1k/day cc-dispatcher-workspace-resolve fallbacks OR p95 cc_router turn-latency regression >50ms".
- **Test-fixture drift** — the dispatcher test suite already mocks `fetchUserWorkspacePath`. Confirm the existing mock returns a path that exercises `stripWorkspacePath` (i.e., contains a `/workspaces/` or `/tmp/claude-` prefix); if it returns a bare `/home/...` path, `buildToolLabel` will still produce the absolute path in the label, the test will assert against an absolute path, and the test passes vacuously. Add an explicit assertion that `label` does NOT contain the `workspacePath` prefix.
- **Telemetry noise** — `buildToolLabel` invokes `reportSilentFallback` for unknown Bash verbs. cc_router's allowed Bash verbs are constrained but not statically enumerable here. Risk: a flood of `tool-label-fallback` Sentry events the first time this lands. Mitigation: pre-flight check the Bash verb allowlist (`BASH_VERB_LABELS` in `tool-labels.ts:108-121`) against the cc_router's typical Bash usage; widen the allowlist in this same PR if a common verb (e.g., `ls`, `cat`, `git`) is missing. (Spot-check: `ls`, `find`, `rg`, `grep`, `cat`, `npm`, `bun`, `git` are already covered.)

## Sharp Edges

- **Do not refactor `onToolUse` to call `buildToolLabel` lazily inside the closure** — the closure runs per `tool_use` event; `workspacePath` resolution must happen ONCE outside and be captured.
- **Do not change `block.name` to anything else** — `block.name` is the SDK's authoritative tool name and is what `buildToolLabel`'s `switch` keys on. Renaming it (e.g., to "tool" or "kind") breaks the label mapping silently.
- **Verify both `tool_use_chip` and `MessageBubble.toolLabel` paths render the new label** — `chat-state-machine.ts:316` routes the FIRST cc_router `tool_use` (no active stream) to a chip (`type: "tool_use_chip"`), and subsequent ones to `MessageBubble.toolLabel`. Both sides of the branch read `event.label`, so a single fix at the emitter covers both. The screenshot's chip is the second branch (real bubble exists). Manual QA must exercise both: first turn (chip-only render before any text) and follow-up turn (bubble exists).
- **A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.** This plan's threshold is `none` with rationale; section is filled. Sensitive-path scope-out bullet added because `apps/web-platform/server/cc-dispatcher.ts` matches the canonical sensitive-path regex.
- **`event.label` shape on the wire is fixed by the WS Zod schema.** Per `apps/web-platform/lib/ws-zod-schemas.ts:236-241`, `tool_use` events have a `label: string` field; the schema is permissive (no max length, no shape guard). No schema change is needed for the fix — verbose labels (already up to ~80 chars from `MAX_BASH_CMD_LENGTH = 60` + verb prefix) flow through the existing wire format. **Do not add a schema change in this PR.**
- **Reducer assertion to verify after fix lands.** `chat-state-machine.ts:362-367` overwrites `toolLabel: event.label` on every `tool_use` event without coalescing or transforming it. After fix, manual-QA verification step #4 (Phase 3) is the load-bearing check that the WS event reaches the chip text node verbatim. If verbose label appears on the wire (verifiable by browser DevTools → Network → WS frames) but NOT on the chip, the bug is in the reducer/component path — not in this fix. Open a separate issue.

## Resume Prompt (for `/clear` after plan completion)

```text
/soleur:work knowledge-base/project/plans/2026-05-05-fix-concierge-tool-status-verbose-label-plan.md

Context: branch feat-one-shot-concierge-tool-status-label, worktree .worktrees/feat-one-shot-concierge-tool-status-label/. Plan written + deepened. Bug: cc-dispatcher onToolUse emits raw block.name as label; fix routes through buildToolLabel(block.name, block.input, workspacePath). RED test in cc-dispatcher.test.ts, GREEN edits in cc-dispatcher.ts, manual QA on Concierge PDF read.
```
