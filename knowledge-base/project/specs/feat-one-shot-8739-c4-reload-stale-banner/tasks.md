# Tasks — fix(c4) #8739: reload diagram + clear stale banner on Concierge edit_c4_diagram

lane: cross-domain
Plan: `knowledge-base/project/plans/2026-09-25-fix-c4-reload-on-concierge-edit-plan.md`

All file contents are cited from `origin/main` — this branch's HEAD predates PR #8853 (`9279de9`), which introduced the `ZERO_VIEW_DIAGNOSTIC*` copy. Phase 0 is a hard prerequisite.

## Phase 0 — Branch sync (prerequisite)

- [ ] 0.1 `git merge origin/main` (or `git pull --ff-only origin main`) — HEAD is 23 behind, 0 ahead; a clean fast-forward. Confirm `ZERO_VIEW_DIAGNOSTIC` now greps in `apps/web-platform/app/api/kb/c4/project/route.ts`.

## Phase 1 — Wire contract (write failing schema/guard tests first)

- [ ] 1.1 `apps/web-platform/lib/types.ts`: add `| { type: "c4_diagram_saved"; dirPath: string; rerendered: boolean; diagnostic?: string | null }` to the `WSMessage` union, with the doc comment from the plan (ADR-025 family; NOT buffered per ADR-059).
- [ ] 1.2 `apps/web-platform/lib/ws-known-types.ts`: add `"c4_diagram_saved"` to `KNOWN_WS_MESSAGE_TYPES` (the `_Exhaustive` type forces this — compile fails without it).
- [ ] 1.3 `apps/web-platform/lib/ws-zod-schemas.ts`: add `c4DiagramSavedSchema = z.strictObject({ type: z.literal("c4_diagram_saved"), dirPath: z.string(), rerendered: z.boolean(), diagnostic: z.string().nullable().optional() })` and append it to `flatTypeSchema`.
- [ ] 1.4 `apps/web-platform/test/ws-known-types-guard.test.ts`: add `"c4_diagram_saved"` to the exact-match `expected` array.
- [ ] 1.5 `apps/web-platform/test/ws-zod-schemas.test.ts`: add parse tests — valid frame accepted; missing `dirPath`, non-boolean `rerendered`, and unknown extra keys rejected (strictObject).

## Phase 2 — Server emit

- [ ] 2.1 `apps/web-platform/server/c4-concierge-tools.ts`: extend `BuildC4ConciergeToolsOpts` with `onDiagramSaved?: (info: { dirPath: string; rerendered: boolean; diagnostic: string | null }) => void`.
- [ ] 2.2 Same file, tool handler: after `result.ok`, call `opts.onDiagramSaved?.({ dirPath: args.relativePath.slice(0, args.relativePath.lastIndexOf("/")), rerendered: result.rerendered, diagnostic: result.rerenderDiagnostic ?? null })`. Do NOT fire on `ok:false`. Wrap in try/catch so a notify throw cannot break the tool response; mirror via `reportSilentFallback(null, { feature: "c4-concierge-tools", op: "diagram-saved-notify" })` imported DYNAMICALLY (`await import("@/server/observability")`) — the file's static graph must stay free of server-only chains for vitest (same reason `writeC4Diagram` is a dynamic import at line ~130).
- [ ] 2.3 `apps/web-platform/test/c4-concierge-tools.test.ts`: failing test — `onDiagramSaved` spy called once with `{ dirPath: "engineering/architecture/diagrams", rerendered, diagnostic }` on `ok:true`; NOT called on `ok:false`.
- [ ] 2.4 `apps/web-platform/server/cc-dispatcher.ts`: at the `buildC4ConciergeTools({...})` call site, pass `onDiagramSaved` wrapping `defaultSendToClient(userId, { type: "c4_diagram_saved", dirPath, rerendered, diagnostic })`; a thrown emit mirrors via `reportSilentFallback(null, { feature: "cc-dispatcher", op: "c4-saved-notify", extra: { dirPath } })` — `null` first arg, never a real `Error` (the pino mirror captures a passed Error first and Sentry drops the tagged second capture, #8629). A `false` return (no live socket) is benign — do not mirror it.

## Phase 3 — Client dispatch + workspace listener

- [ ] 3.1 `apps/web-platform/lib/ws-client.ts`: export `C4_DIAGRAM_SAVED_EVENT = "soleur:c4DiagramSaved"`; add `case "c4_diagram_saved":` to the onmessage switch → `window.dispatchEvent(new CustomEvent(C4_DIAGRAM_SAVED_EVENT, { detail: { dirPath: msg.dirPath, rerendered: msg.rerendered, diagnostic: msg.diagnostic ?? null } }))` under `typeof window !== "undefined"`, then `break`. Keep the `_exhaustive: never` tail green.
- [ ] 3.2 `apps/web-platform/test/c4-workspace.test.tsx`: failing component test — dispatch `window` `C4_DIAGRAM_SAVED_EVENT` with matching `dirPath` + `rerendered:true` → project refetches and a stale banner for that dir clears; `rerendered:false` + diagnostic → banner set; foreign `dirPath` → no refetch/no state change. Follow the file's existing mock pattern (`KbChatContent` stub, flag snapshot). MUST stub `globalThis.fetch` (file-level reassignment): happy-dom ships a real `fetch` and `useC4Project` hits `/api/kb/c4/project` on mount — unmocked it flakes `ECONNREFUSED 127.0.0.1:3000` (`2026-05-20-happy-dom-ws-fetch-blockade`).
- [ ] 3.3 `apps/web-platform/components/kb/c4-workspace.tsx`: add the `useEffect` listener from the plan — `dirPath` match → `await reload()` + `setStaleSave` mirroring `onSaved` (`rerendered ? clear-own-dir : set { dirPath, diagnostic }`). Listener lives in `C4Workspace` (always mounted), NOT inside the concierge window (unmountable).

## Phase 4 — Copy sweep

- [ ] 4.1 `route.ts`: `ZERO_VIEW_DIAGNOSTIC` → `ZERO_VIEW_PREFIX + "ask the Concierge to re-render this diagram."` (drop `, then reload the page.`). Update the comment above the constants: remove the "stays until #8739" note from the DIAGNOSTIC line and record on OTHER_DIR that the clause is retained because an out-of-app export emits no signal.
- [ ] 4.2 `route.ts`: `ZERO_VIEW_DIAGNOSTIC_OTHER_DIR` — keep `", then reload the page."` unchanged.
- [ ] 4.3 `c4-concierge-tools.ts` `C4_PROMPT_ADDENDUM`: replace `; then tell the user to reload the page.` with wording stating the open editor refreshes itself (e.g. ` — the open diagram editor refreshes itself when the save lands, so do not tell the user to reload`). CONSTRAINT: the new text must not contain `will update` (pinned count == 1) or `shortly` (banned), and must keep every existing `toContain` pin in `c4-concierge-copy.test.ts`.
- [ ] 4.4 `test/c4-project-route.test.ts`: re-pin the `ZERO_VIEW_DIAGNOSTIC` literal (line ~359); `ZERO_VIEW_DIAGNOSTIC_OTHER_DIR` literal stays.
- [ ] 4.5 `test/c4-concierge-copy.test.ts`: update the route-substring pin (line ~78) to `"ask the Concierge to re-render this diagram."`; add `expect(C4_PROMPT_ADDENDUM).not.toContain("tell the user to reload")`; refresh the now-stale "#8695: nothing on the page refreshes by itself" comment.

## Phase 5 — Verify

- [ ] 5.1 `cd apps/web-platform && npx vitest run test/c4-workspace.test.tsx test/c4-concierge-tools.test.ts test/c4-project-route.test.ts test/c4-concierge-copy.test.ts test/ws-zod-schemas.test.ts test/ws-known-types-guard.test.ts` → 0 failed.
- [ ] 5.2 `cd apps/web-platform && npx tsc --noEmit` (or the repo's standard typecheck script) → clean; the two `_Exhaustive`/`never` sites confirm union coverage.
- [ ] 5.3 `grep -rn "reload the page" apps/web-platform/app/api/kb/c4/project/route.ts apps/web-platform/server/c4-concierge-tools.ts` → exactly ONE match (`ZERO_VIEW_DIAGNOSTIC_OTHER_DIR`).
- [ ] 5.4 Full app test pass per repo convention (`npx vitest run` in `apps/web-platform`, or the narrower gate set CI runs).
