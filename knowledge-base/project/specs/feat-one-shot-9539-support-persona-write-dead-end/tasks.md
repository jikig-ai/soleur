# Tasks: fix: support-persona sessions dead-end on write-requiring tasks (#9539)

Plan: `knowledge-base/project/plans/2026-10-05-fix-support-persona-write-dead-end-plan.md`

Execution order: Phase 1 (detection + wire contract) → Phase 2 (Bash channel) → Phase 3 (emit + render) → Phase 4 (tests + ADR amendment). The escalation flag and WSMessage member are the contracts every consumer depends on — they land first.

## Phase 0: Preconditions

- [x] 0.1 Re-verify the anchors the plan binds to still exist on this branch's merge-base:
      `resolveWorkspaceMode` in `apps/web-platform/server/workspace-mode.ts`;
      the `ctx.persona === "support" && toolName === "Skill"` deny branch and the Bash
      `isBashCommandSafe` allow block in `apps/web-platform/server/permission-callback.ts`;
      `SUPPORT_TERMINAL_FRAME_TYPES` / `enqueue` in `apps/web-platform/app/api/support/route.ts`;
      `reduceSupportFrame` in `apps/web-platform/lib/support-sse.ts`; the `WSMessage` union in
      `apps/web-platform/lib/types.ts`; `SUPPORT_SYSTEM_DIRECTIVE` in
      `apps/web-platform/server/support-directive.ts`.
- [x] 0.2 Confirm the test runner is vitest (`package.json` `scripts.test`; `bunfig.toml`
      `pathIgnorePatterns = ["**"]`) — all test commands use
      `cd apps/web-platform && ./node_modules/.bin/vitest run <path>`.
- [x] 0.3 Confirm `dashboard/chat/new?msg=<text>` still auto-sends the first message
      (`apps/web-platform/components/chat/chat-surface.tsx` `msgParam` consumer).

## Phase 1: Detection + wire contract

- [x] 1.1 Write `apps/web-platform/server/support-escalation.ts`: `recordSupportEscalation(
      conversationId, source: "skill" | "bash")`, `consumeSupportEscalation(conversationId):
      boolean` (consume-on-read), `clearSupportEscalation(conversationId)`; bounded Map
      (evict oldest at ~1000 entries).
- [x] 1.2 In `apps/web-platform/lib/support-sse.ts`: `export type SupportSseMessage =
      WSMessage | { type: "support_handoff"; task: string; conversationId: string }`;
      widen `formatSupportSseFrame`/`parseSupportSseChunks`/`reduceSupportFrame`; move+
      export `SUPPORT_TERMINAL_FRAME_TYPES`. `lib/types.ts`/`ws-zod-schemas.ts` UNTOUCHED
      (bidirectional `_SchemaCovers` drift guard — a bare union member is a compile error).
- [x] 1.2b `permission-callback.ts` `AskUserQuestion` branch: support-persona deny with
      ask-in-text message, NO escalation record. `SUPPORT_EXTRA_DISALLOWED_TOOLS` +=
      `"AskUserQuestion"`, `"TodoWrite"`, `"ExitPlanMode"`.
- [x] 1.2c Shared copy module in `lib/`: `SUPPORT_AGENT_SESSION_HREF` +
      `buildSupportHandoffMarkdown(task)` (angle-bracket destination, `encodeURIComponent`
      + `!~*'()` escaping, canonical "Ask an agent" naming + repo precondition).
- [x] 1.3 In `permission-callback.ts`, inside the `ctx.persona === "support" &&
      toolName === "Skill"` deny branch: call `recordSupportEscalation(ctx.conversationId,
      "skill")` before returning, and extend the deny `message` to name the concrete next
      surface ("Ask an agent" / agent session).
- [x] 1.4 Run `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` — every TS2322
      "not assignable to never" is an exhaustiveness rail to widen (the compiler enumerates
      them; do not pre-derive a site list by grep).

## Phase 2: Bash channel short-circuit

- [x] 2.1 Write the RED test first: support persona + non-safe Bash → deny, no
      `review_gate`/`bash_approval`/`autonomous_disclosure` frame on `deps.sendToClient`,
      `recordSupportEscalation(convId, "bash")` called.
- [x] 2.2 In `permission-callback.ts` Bash branch — after the blocklist deny and the
      `isBashCommandSafe` allow (keep the near-miss telemetry block firing), before
      `deps.bashAutonomous`/cache/review-gate — add `if (ctx.persona === "support")`:
      `recordSupportEscalation(ctx.conversationId, "bash")` + return `deny` with a
      user-relayable message that this chat is read-only app help and an agent session
      can take the task.
- [x] 2.3 Verify `persona !== "support"` Bash behavior is byte-neutral (gate path
      untouched for command_center).

## Phase 3: Emission + render

- [x] 3.1 In `app/api/support/route.ts` `enqueue`: when
      `SUPPORT_TERMINAL_FRAME_TYPES.has(msg.type)` and
      `consumeSupportEscalation(conversationId)` is true, enqueue
      `{ type: "support_handoff", task: message.slice(0, 500) }` BEFORE forwarding the
      terminal frame; call `clearSupportEscalation(conversationId)` in stream teardown.
- [x] 3.2 In `apps/web-platform/lib/support-sse.ts` `reduceSupportFrame`: `support_handoff`
      case sets `state.handoffMarkdown` (separate field — never merged into `state.text`,
      which `stream` replaces wholesale). In `components/support/use-support-chat.ts`
      compose `state.text + handoffMarkdown` at patch time INCLUDING the `error`/`fallback()`
      branch (emitted-then-discarded fix). Blocklist-deny (`isBashCommandBlocked`) also
      records for support. `route.ts`: `clearSupportEscalation` at stream open AND teardown
      (+ `support-handoff-cleared-unconsumed` log).
- [x] 3.3 In `apps/web-platform/server/support-directive.ts` `SUPPORT_SYSTEM_DIRECTIVE`:
      update the engineering-redirect instruction to one sentence + the bare
      `[Open an agent session](/dashboard/chat/new)` link (no model-side query params).
- [x] 3.4 Do NOT create or edit any `components/**/*.tsx` — the affordance rides the
      existing MarkdownRenderer (a `.tsx` touch fires the BLOCKING UX wireframe gate).

## Phase 4: Tests + ADR amendment

- [x] 4.1 `apps/web-platform/test/support-handoff.test.ts` (new, matches vitest's
      `include: ["test/**/*.test.ts"]` node-env glob): (a) Skill deny records + message
      names the agent surface; (b) Bash deny emits no gate frame; (c) command_center
      unaffected; (d) reducer appends the encoded link; (e) `support_handoff` precedes
      the terminal frame; (f) no flag → no frame.
- [x] 4.2 Run the existing support suites green:
      `cd apps/web-platform && ./node_modules/.bin/vitest run test/permission-callback-support-skill-allowlist.test.ts test/support-route.test.ts test/support-sse.test.ts test/support-directive.test.ts test/single-replica-assertion.test.ts`
      plus the workspace-mode tests pinning `sandboxWrite: "none"` / `allowWrite: []`.
- [x] 4.3 Amend `knowledge-base/engineering/architecture/decisions/ADR-113-support-persona-scoped-concierge.md`:
      Decision addendum ("deny → escalate" channel) + `## Alternatives Considered` entries
      for silent intent re-routing and the opt-in write grant (both rejected, reasons
      recorded) + a note on the support-Bash review-gate short-circuit.
- [x] 4.4 Full lint/format/typecheck pass per repo convention; markdownlint any edited docs.

## Verification commands

- `cd apps/web-platform && ./node_modules/.bin/vitest run test/support-handoff.test.ts` — new suite green.
- `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` — union widening clean.
- `rg -n "support_handoff" apps/web-platform/lib/types.ts apps/web-platform/lib/support-sse.ts` — wire contract present.
