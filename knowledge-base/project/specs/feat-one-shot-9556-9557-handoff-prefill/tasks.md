# Tasks: support_handoff repoConnected + command-palette ?q= prefill (#9556, #9557)

Plan: `knowledge-base/project/plans/2026-10-06-feat-support-handoff-repo-connected-chat-prefill-plan.md`

One PR, both issues (`closes: [9556, 9557]`). Hard constraint: do NOT touch
`apps/web-platform/server/agent-runner-sandbox-config.ts` or any sandbox-canary capture
input (#9618 gate). `lib/types.ts` / `ws-zod-schemas.ts` / `use-shortcuts.tsx` stay
untouched by design.

## Phase 1: Server plumbing — repoConnected rides the deny→emit registry (#9556)

- [ ] 1.1 RED: add failing tests in `test/support-handoff.test.ts` —
      `consumeSupportEscalation` returns `{ source, repoConnected }`; a deny recorded with
      `deps.repoConnected === false` yields a `support_handoff` frame carrying
      `"repoConnected":false` before the terminal frame.
- [ ] 1.2 `server/support-escalation.ts`: registry values become
      `{ source: SupportEscalationSource; repoConnected?: boolean }`; widen
      `recordSupportEscalation`, `consumeSupportEscalation` (new
      `SupportEscalationRecord` type), and `denySupport(opts.repoConnected?)` (FR-1).
- [ ] 1.3 `server/permission-callback.ts`: `CanUseToolDeps.repoConnected?: boolean`;
      closure-local `deny(opts)` wrapper injecting `deps.repoConnected`; rename all 8
      `denySupport(` call sites (`:282,:292,:493,:593,:1031,:1065,:1090,:1227`) to
      `deny(` (FR-2). Census: post-change `grep -c 'denySupport('` == 1.
- [ ] 1.4 `server/cc-dispatcher.ts`: `ccDeps` gains `repoConnected: repoUrl !== null`
      with the provenance comment (FR-3). `getCurrentRepoUrl(` call-site count stays 1.
- [ ] 1.5 `app/api/support/route.ts`: consume the record shape; emit
      `{ type:"support_handoff", task, conversationId, repoConnected }`; add
      `repoConnected` to the `support-handoff-emitted` log fields (FR-4 server half).

## Phase 2: Frame + copy (#9556)

- [ ] 2.1 RED: failing tests in `test/support-sse.test.ts` — the `support_handoff` arm
      passes `msg.repoConnected` to the copy builder.
- [ ] 2.2 `lib/support-sse.ts`: union member gains `repoConnected?: boolean` (optional;
      additive-safe across the JSON parse boundary); reducer passes it (FR-4 client
      half). Do NOT touch `lib/types.ts`/`ws-zod-schemas.ts` (the `_SchemaCovers` pin is
      why the frame is support-local).
- [ ] 2.3 `lib/support-handoff.ts`: `buildSupportHandoffMarkdown(task, repoConnected?)`
      tri-state + `SUPPORT_CONNECT_REPO_HREF = "/connect-repo"` (FR-5). `false` →
      connect-repo link + "Connect a repository to hand this task to an agent →";
      `true` → clean `?msg=` link (caveat drops); `undefined` → current copy
      byte-identical. Reuse the existing `encodeURIComponent` + `!~*'()` percent-encoding.

## Phase 3: ?q= consumer (#9557)

- [ ] 3.1 RED: new `test/chat-prefill.test.tsx` — `?q=` seeds the composer (latched,
      once), never auto-sends, strips via `router.replace`; `?msg=`+`?q=` → msg wins;
      `?q=` on non-`new`/non-`full` ignored; non-empty draft never clobbered.
- [ ] 3.2 `components/chat/chat-input.tsx`: `prefill?: string` prop + latched effect
      (`prefillAppliedRef`), apply only when `value` is empty, then focus (FR-6).
- [ ] 3.3 `components/chat/chat-surface.tsx`: `qParam = searchParams.get("q")`; pass
      `prefill` gated on `variant === "full" && conversationId === "new" && !msgParam`;
      latched strip effect with `router.replace(pathname, { scroll: false })` (FR-7/8).

## Phase 4: Docs + verify

- [ ] 4.1 `knowledge-base/engineering/architecture/decisions/ADR-113-support-persona-scoped-concierge.md`:
      addendum frame shape becomes `{task, conversationId, repoConnected?}` + one-line
      provenance note (FR-9).
- [ ] 4.2 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` green;
      `./node_modules/.bin/vitest run test/support-handoff.test.ts test/support-sse.test.ts
      test/chat-prefill.test.tsx` green.
- [ ] 4.3 Clean-diff greps: `git diff --name-only origin/main...HEAD | grep -E
      'agent-runner-sandbox-config\.ts|lib/types\.ts|ws-zod-schemas\.ts|use-shortcuts\.tsx'`
      returns empty; `git ls-files --error-unmatch
      knowledge-base/product/design/support/support-handoff-repo-connected-prefill.pen`
      exits 0.
