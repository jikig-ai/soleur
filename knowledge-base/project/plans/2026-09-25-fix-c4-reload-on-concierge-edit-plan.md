---
title: "fix(c4): reload the diagram and clear the stale banner when a Concierge edit_c4_diagram completes for the open folder"
type: fix
date: 2026-09-25
slug: fix-c4-reload-on-concierge-edit
branch: feat-one-shot-8739-c4-reload-stale-banner
issue: 8739
closes: 8739
priority: p3
domain: engineering
brand_survival_threshold: none
lane: cross-domain
---

# fix(c4): reload the diagram and clear the stale banner when a Concierge edit_c4_diagram completes for the open folder

## Overview

In the C4 diagram editor (`apps/web-platform/components/kb/c4-workspace.tsx`), a Concierge `edit_c4_diagram` tool call that finishes while the editor is open changes nothing on screen: the workspace has no listener for Concierge tool results, the precomputed diagram (`useC4Project`) is not refetched, and a stale-save banner (when showing) keeps its old reason even after the Concierge edit re-rendered successfully (#8739, deferred out of the #8695/#8696 plan).

This plan wires a single server→client WS notification, `c4_diagram_saved`, emitted from inside the `edit_c4_diagram` tool handler on a successful `writeC4Diagram`, translated client-side in `lib/ws-client.ts` into a `window` CustomEvent that `C4Workspace` turns into the same `reload()` + stale-banner transition the Code panel's `onSaved(rerendered, diagnostic)` already performs. The same change removes the now-false "then reload the page" clauses from the three copies the member comment on #8739 enumerates — keeping the clause only in `ZERO_VIEW_DIAGNOSTIC_OTHER_DIR`, where an out-of-app `likec4 export` genuinely still needs a manual reload (no event exists for external pushes).

## Research Reconciliation — Spec vs. Codebase

No spec.md exists for this branch (fresh one-shot). One material divergence from the issue's implied state:

| Spec/issue claim | Reality | Plan response |
|---|---|---|
| `ZERO_VIEW_DIAGNOSTIC` / `ZERO_VIEW_DIAGNOSTIC_OTHER_DIR` exist in `app/api/kb/c4/project/route.ts` | TRUE on `origin/main` (added by PR #8853, commit `9279de9`), but **this branch's HEAD predates that merge** — worktree is 23 commits behind `origin/main`, 0 ahead | Phase 0 fast-forwards the branch onto `origin/main` before any edit; all file contents below are cited from `origin/main` |

## Research Insights

**Premise validation (Phase 0.6):** Issue #8739 is OPEN. Referenced issues #8695 and #8696 are CLOSED; PR #8853 is MERGED into `origin/main` (`9279de94fe`). All four cited artifacts verified on `origin/main`: `ZERO_VIEW_DIAGNOSTIC`/`ZERO_VIEW_DIAGNOSTIC_OTHER_DIR` at `route.ts:64-67`, `C4_PROMPT_ADDENDUM` at `server/c4-concierge-tools.ts:64`, pinning tests at `test/c4-project-route.test.ts:357-361` and `test/c4-concierge-copy.test.ts:78`. No stale premises beyond the branch-vs-main skew above.

**Property list (Phase 0.6b):**

1. When a Concierge `edit_c4_diagram` returns `ok` for the folder shown in the open `C4Workspace`, the diagram data refetches with no user action.
2. The stale-save banner tracks Concierge saves exactly as it tracks Code-panel saves: cleared on `rerendered`, set with the server diagnostic on a non-rerendered save.
3. No surviving copy instructs a manual reload after a Concierge re-render; the out-of-app export path keeps its reload instruction because it produces no signal the page can hear.
4. Component test covers the event → reload + banner transition.

**Cut list (Phase 0.6b):** no mechanism from the ask was cut. The ask names no machinery beyond "wiring from the chat stream to the KB workspace"; every chosen piece is an extension of an existing mechanism (WSMessage variant per ADR-025's lifecycle-notice family; `window` CustomEvent per `OPEN_UPGRADE_MODAL_EVENT`/`WORKSPACE_LOGO_CHANGED_EVENT`; `onSaved` transition logic already in `C4Workspace`). Alternatives evaluated and rejected in *Alternative Approaches Considered*.

**Repo findings:**

- `useC4Project(dirPath)` (`components/kb/c4-shared.tsx:78`) returns `{ data, error, loading, reload }`; `reload` is endpoint-guarded (`currentEndpoint` ref) so a stale-folder reload cannot clobber the current view.
- `C4Workspace` owns `staleSave` state keyed by `dirPath` (`c4-workspace.tsx:72-77`) and already implements the exact transition needed — the Code panel's `onSaved` callback (`c4-workspace.tsx:205-215`): `await reload()` then `setStaleSave` keyed on `rerendered`.
- The raw SDK tool name is deliberately withheld from the wire (#2138): `buildToolUseWSMessage`/`buildToolProgressWSMessage` route names through `buildToolLabel`. Open issue #3242 documents that `tool_use` lacks a structured name field — so **client-side tool-name matching is not available** and is a rejected mechanism.
- The dispatcher's `onToolResult` (`server/cc-dispatcher.ts:3800`) is **Bash-only**: `soleur-go-runner.ts` correlates `tool_use_result` only for commands recorded in `bashToolUses` (`soleur-go-runner.ts:2130-2141, 2262-2276`). Extending it to MCP tools would widen the callback's block shape across consumers — heavier machinery than needed.
- `buildC4ConciergeTools` (`server/c4-concierge-tools.ts:115`) closes over `userId/installationId/owner/repo/workspacePath` and returns the tool whose handler already has the authoritative result (`result.ok`, `result.rerendered`, `result.rerenderDiagnostic`, `args.relativePath`). An optional notify callback on `BuildC4ConciergeToolsOpts` is the narrowest correct emit point — it fires exactly on completion, with the real outcome, and is spy-injectable in `c4-concierge-tools.test.ts` (whose `opts` fixture is already a literal object).
- `sendToClient(userId, msg)` (`server/ws-handler.ts:728`) is userId-keyed — the frame reaches every live session socket for the user, not just the Concierge's own conversation socket. `defaultSendToClient` is already imported in `cc-dispatcher.ts` (line 234) and passed at line 2526.
- New wire types require four coordinated edits: `lib/types.ts` WSMessage union member, `lib/ws-known-types.ts` `KNOWN_WS_MESSAGE_TYPES` (compile-time `_Exhaustive` forces it), `lib/ws-zod-schemas.ts` strictObject + `flatTypeSchema` member, and a `case` in `lib/ws-client.ts` onmessage (its `_exhaustive: never` tail forces it). `test/ws-known-types-guard.test.ts` holds an **exact-match** expected array that must gain the type.
- `dirPath` on the wire equals `dirname(relativePath)`; under the current `isC4DiagramPath` scope that is always `engineering/architecture/diagrams` (`C4_DIAGRAMS_DIR`), which is exactly what `c4DirPath` resolves to on the diagram page (`page.tsx:49,217`). Derive it — do not hardcode — so a future scope widening stays correct.
- The frame should NOT join `BUFFERED_FRAME_TYPES` (`server/stream-replay-buffer.ts:53`): a replayed `c4_diagram_saved` would cause a spurious-but-benign extra refetch, and a remounting workspace refetches on mount anyway. Live-only is the honest semantic.
- `rerenderDiagnostic` "can quote a file path chosen by whoever pushed to the tenant repo" (`c4-concierge-tools.ts` comment) — it already reaches the user via the tool result and the PUT save response's banner; relaying it on the user-scoped WS frame is the same disclosure class.

**Relevant learnings/ADRs:** ADR-025 (WS lifecycle-notice family: server-emit-only, idempotent per fire, zod-parsed); ADR-059 (buffered family — deliberately not joined); `cq-silent-fallback-must-mirror-to-sentry` (emit failure must mirror via `reportSilentFallback`); `cq-write-failing-tests-before`.

**External research:** skipped — strong local precedent for every piece (frame family, CustomEvent bridge, `onSaved` contract).

**Community/functional overlap:** assessed inline (no Task subagent available in this pipeline context). No uncovered stacks (Next.js/TS covered); no community artifact can cover a repo-internal WS→component contract. Nothing installed.

## Open Code-Review Overlap

Four open `code-review` issues touch planned files:

- **#3374** `emit slot_reclaimed WS frame so agent clients can react in-band` — **acknowledge**: same mechanism (a new server→client frame on the same wire), different trigger and payload; precedent, not a conflict.
- **#3242** `tool_use WS event lacks raw name field for agent consumers` — **acknowledge**: this plan deliberately does NOT resolve it; the dedicated frame sidesteps the withheld-name problem rather than exposing raw names (#2138 tension is why).
- **#3280** `refactor useWebSocket history-fetch into reducer-driven state machine` — **acknowledge**: our `onmessage` addition is one `case`, compatible with that later refactor.
- **#3243** `decompose cc-dispatcher.ts into focused modules` — **acknowledge**: the emit wiring adds ~15 lines to `cc-dispatcher.ts`; a decomposition can move it later.

## Problem Statement

When the Concierge edits the C4 diagram the user is looking at, the screen does not change. `useC4Project` fetched once at mount and nothing tells it the server just committed a new `.c4` and re-rendered `model.likec4.json`. If the stale-save banner (#8695) is up, it keeps showing the old save's reason even though a newer save just re-rendered. Three copies compensate for the gap with a "then refresh the page" clause — copy that becomes false the moment this lands.

## Proposed Solution

Add one WS message variant end-to-end:

```ts
// lib/types.ts — WSMessage union
| {
    type: "c4_diagram_saved";
    /** dirname of the written KB-relative path (currently always C4_DIAGRAMS_DIR). */
    dirPath: string;
    /** Mirrors onSaved(rerendered, diagnostic): true = the model re-rendered. */
    rerendered: boolean;
    diagnostic?: string | null;
  }
```

Server emit (inside `buildC4ConciergeTools` handler, after `result.ok`):

```ts
opts.onDiagramSaved?.({
  dirPath: args.relativePath.slice(0, args.relativePath.lastIndexOf("/")),
  rerendered: result.rerendered,
  diagnostic: result.rerenderDiagnostic ?? null,
});
```

`cc-dispatcher.ts` passes `onDiagramSaved` that wraps `defaultSendToClient` and mirrors a thrown emit via `reportSilentFallback` (`feature: "cc-dispatcher", op: "c4-saved-notify"`). A `false` return from `sendToClient` (no live socket) is benign — no open page can be stale when no client is connected.

Client bridge in `ws-client.ts` onmessage:

```ts
case "c4_diagram_saved": {
  if (typeof window !== "undefined") {
    window.dispatchEvent(
      new CustomEvent(C4_DIAGRAM_SAVED_EVENT, {
        detail: { dirPath: msg.dirPath, rerendered: msg.rerendered, diagnostic: msg.diagnostic ?? null },
      }),
    );
  }
  break;
}
```

`C4Workspace` listener (page-level — load-bearing placement, see Sharp Edges):

```ts
useEffect(() => {
  const h = (e: Event) => {
    const d = (e as CustomEvent<{ dirPath: string; rerendered: boolean; diagnostic: string | null }>).detail;
    if (d?.dirPath !== dirPath) return;
    void (async () => {
      await reload();
      setStaleSave((cur) =>
        d.rerendered
          ? cur?.dirPath === dirPath ? null : cur
          : { dirPath, diagnostic: d.diagnostic ?? null },
      );
    })();
  };
  window.addEventListener(C4_DIAGRAM_SAVED_EVENT, h);
  return () => window.removeEventListener(C4_DIAGRAM_SAVED_EVENT, h);
}, [dirPath, reload]);
```

This mirrors `onSaved` verbatim, which means a Concierge save that did NOT re-render now also *sets* the banner with the server's diagnostic — a small honesty gain that falls out of reusing the contract rather than new machinery.

### Files to Edit

| File | Change |
|---|---|
| `apps/web-platform/lib/types.ts` | Add `c4_diagram_saved` to `WSMessage` union |
| `apps/web-platform/lib/ws-known-types.ts` | Add type to `KNOWN_WS_MESSAGE_TYPES` |
| `apps/web-platform/lib/ws-zod-schemas.ts` | `c4DiagramSavedSchema` strictObject + `flatTypeSchema` member |
| `apps/web-platform/lib/ws-client.ts` | Export `C4_DIAGRAM_SAVED_EVENT`; new `case` dispatching the CustomEvent |
| `apps/web-platform/server/c4-concierge-tools.ts` | `BuildC4ConciergeToolsOpts.onDiagramSaved?`; handler invoke on `result.ok`; `C4_PROMPT_ADDENDUM` zero-view sentence loses "then tell the user to reload the page" |
| `apps/web-platform/server/cc-dispatcher.ts` | Pass `onDiagramSaved` wrapping `defaultSendToClient` + `reportSilentFallback` on throw |
| `apps/web-platform/components/kb/c4-workspace.tsx` | `useEffect` listener → `reload()` + `setStaleSave` (`onSaved` semantics) |
| `apps/web-platform/app/api/kb/c4/project/route.ts` | `ZERO_VIEW_DIAGNOSTIC` drops `, then reload the page.`; comment above constants updated; `ZERO_VIEW_DIAGNOSTIC_OTHER_DIR` **keeps** the clause |
| `apps/web-platform/test/c4-project-route.test.ts` | Re-pin `ZERO_VIEW_DIAGNOSTIC` string |
| `apps/web-platform/test/c4-concierge-copy.test.ts` | Re-pin route substring (line ~78); add `not.toContain("tell the user to reload")`-class pin; refresh the stale "#8695 nothing refreshes by itself" comment |
| `apps/web-platform/test/ws-known-types-guard.test.ts` | Add `"c4_diagram_saved"` to expected array |
| `apps/web-platform/test/ws-zod-schemas.test.ts` | Parse test: valid frame ok; missing `dirPath`/non-boolean `rerendered` reject |
| `apps/web-platform/test/c4-concierge-tools.test.ts` | Spy `onDiagramSaved`: fires on `ok` with `{dirPath, rerendered, diagnostic}`; NOT fired on `ok:false` |
| `apps/web-platform/test/c4-workspace.test.tsx` | New component test: matching-dir event → refetch + banner cleared; `rerendered:false` → banner set with diagnostic; foreign dir → no-op |

### Files to Create

None.

## Technical Considerations

- **Listener placement is load-bearing.** The Concierge panel unmounts on collapse (`conciergeOpen && isDesktop` gate; `KbChatFullScreen` returns null when closed), so a listener inside the chat tree would miss a frame emitted by an in-flight turn whose panel closed mid-flight. `C4Workspace` stays mounted for the diagram page's life, and `sendToClient` is userId-keyed — ANY live session socket (this chat, Command Center, another tab) translates the frame into the DOM event the workspace hears. Residual edge: zero live sockets → no frame lands → next mount refetches anyway (`useC4Project` fetch-on-mount). Acceptable; note it.
- **`dirPath` match is the scoping filter.** Because the frame is user-scoped (all sessions), the workspace must compare `detail.dirPath === dirPath` before reloading — a C4 page embedded for a different folder (only canonical `C4_DIAGRAMS_DIR` is concierge-writable today, but derive-don't-assume) must not refetch.
- **`rerendered:false` handling mirrors `onSaved`.** The banner becomes the in-app surface for a Concierge save that failed to re-render — previously visible only in chat text.
- **Wire hygiene per ADR-025/ADR-059.** Server-emit-only, one emission per tool completion, zod-parsed, excluded from the buffered/replay family, no `seq`.
- **Type-widening rule (`hr-type-widening-cross-consumer-grep`).** `BuildC4ConciergeToolsOpts` gains one optional field — additive, not a union widening. `WSMessage` gains a member — the union is exhaustive-checked in exactly two places (`_Exhaustive` in ws-known-types, `never` tail in ws-client switch), both updated in the same change.
- **GDPR (Phase 2.7 advisory).** Diff touches `app/api/` + `server/` (canonical-regex surfaces). Frame payload is a KB dir path + server diagnostic delivered to the owning user's authenticated socket — data already disclosed via `GET /api/kb/c4/project`. No new processing activity, no special-category data, no new third-party transfer. No `compliance-posture.md` item.
- **Copy constraint.** `C4_PROMPT_ADDENDUM` and `C4_TOOL_DESCRIPTION` share pinned bans: `/shortly/` forbidden; `will update` must appear exactly once (inside the existing negation). New wording must use neither token — e.g. "the open diagram editor refreshes itself when the save lands" — and must keep the existing `toContain` pins (`asks you to re-render a diagram`, `For any other folder you cannot re-render it`, …).

## Alternative Approaches Considered

| Approach | Why rejected |
|---|---|
| Client keys on `tool_use` label for `edit_c4_diagram` | Wire labels are humanized by design (#2138); open issue #3242 documents there is no structured name; and `tool_use` fires at tool *start*, not completion |
| Extend `onToolResult` (`soleur-go-runner`) to MCP tools | Widens a Bash-correlated callback (`bashToolUses`, `command`/`output` shape) across consumers for a payload it doesn't carry — heavier than the tool-handler emit point |
| Poll `/api/kb/c4/project` on an interval | Polls for an event the server already knows; adds load and latency for a worse UX |
| Reuse `debug_event`/`reasoning_narration` | `debug_event` is dev-cohort team-only; `reasoning_narration` carries display text, not structured side-effects |
| Drop the reload clause from `ZERO_VIEW_DIAGNOSTIC_OTHER_DIR` too | An out-of-app `likec4 export` + push emits no `c4_diagram_saved`; the open page genuinely cannot learn of it — the member comment's "keep if still needed" condition holds |

## User-Brand Impact

- **If this lands broken, the user experiences:** the open C4 diagram editor keeps showing a stale diagram after a Concierge edit — i.e. the status quo the issue reports — or the stale banner lingers/clears wrongly. Worst realistic defect class is cosmetic staleness that a manual reload still fixes.
- **If this leaks, the user's [data / workflow / money] is exposed via:** the `c4_diagram_saved` frame carries a KB directory path and the server's re-render diagnostic to the owning user's authenticated WebSocket — the same disclosure class as `GET /api/kb/c4/project` responses. No cross-user channel exists: `sendToClient` is userId-keyed.
- **Brand-survival threshold:** `none`
- *Scope-out override:* `threshold: none, reason: the touched server/app-api files are copy strings plus a user-scoped WS notification of an event the user's own session already observes; no authz, credential, or tenant-boundary logic changes`

## Observability

```yaml
liveness_signal:
  what: "c4_diagram_saved frame emitted once per successful edit_c4_diagram; emit-path failures surface as Sentry events (feature=cc-dispatcher, op=c4-saved-notify)"
  cadence: "per edit_c4_diagram completion"
  alert_target: "Sentry issue stream (web-platform project)"
  configured_in: "apps/web-platform/server/cc-dispatcher.ts (onDiagramSaved closure passed to buildC4ConciergeTools)"
error_reporting:
  destination: "Sentry via reportSilentFallback"
  fail_loud: "a thrown sendToClient/emit produces a Sentry event; a dropped frame on an old client produces the existing ws-unknown-event breadcrumb (isKnownWSMessageType)"
failure_modes:
  - mode: "emit throws inside dispatcher closure"
    detection: "reportSilentFallback → Sentry op=c4-saved-notify"
    alert_route: "Sentry web-platform"
  - mode: "frame reaches a stale/older client bundle"
    detection: "isKnownWSMessageType miss → ws-unknown-event Sentry breadcrumb (existing machinery)"
    alert_route: "Sentry web-platform"
  - mode: "no live socket for the user"
    detection: "sendToClient returns false; benign — no open page can be stale, next mount refetches"
    alert_route: "none (by design)"
logs:
  where: "reportSilentFallback Sentry breadcrumb/issue (server); console/Sentry breadcrumb ws-unknown-event (client)"
  retention: "per existing Sentry/log retention"
discoverability_test:
  command: "grep -n c4_diagram_saved apps/web-platform/lib/types.ts apps/web-platform/lib/ws-known-types.ts apps/web-platform/lib/ws-zod-schemas.ts"
  expected_output: "c4_diagram_saved"
```

## Architecture Decision (ADR/C4)

- **ADR:** none. The change extends ADR-025's established lifecycle-notice wire family (server-emit-only, idempotent, zod-parsed) and stays outside ADR-059's buffered family by deliberate choice — no new substrate, boundary, or tenancy decision is made.
- **C4 views:** no model change. Enumerated per the completeness mandate: (a) external human actors — only `founder`, already modeled (`founder -> webapp "Interacts via browser"`); (b) external systems/vendors — none introduced; (c) containers/data-stores — `webapp`/`api`/`engine` unchanged; (d) access relationships — the frame rides the existing `webapp -> engine "Thin view/control layer" { technology "WebSocket" }` edge and the existing `api -> github` diagram-editor re-render edge. No element description is falsified by this change.
- **Sequencing:** N/A.

## Acceptance Criteria

- [ ] AC1: With a C4 diagram page open, a Concierge `edit_c4_diagram` that returns `ok` for that folder triggers a refetch of `/api/kb/c4/project` with no user action.
- [ ] AC2: When that save reports `rerendered: true`, a stale-save banner showing for that folder clears; when `rerendered: false`, the banner shows for that folder carrying the server's `rerenderDiagnostic` (mirroring `onSaved`).
- [ ] AC3: A `c4_diagram_saved` frame whose `dirPath` differs from the open folder causes no refetch and no banner change.
- [ ] AC4: `ZERO_VIEW_DIAGNOSTIC` reads `"...ask the Concierge to re-render this diagram."` (no reload clause); `ZERO_VIEW_DIAGNOSTIC_OTHER_DIR` retains `", then reload the page."`; `C4_PROMPT_ADDENDUM`'s zero-view sentence no longer instructs telling the user to reload, and states the open editor refreshes itself.
- [ ] AC5: `grep -rn "reload the page" apps/web-platform/app/api/kb/c4/project/route.ts apps/web-platform/server/c4-concierge-tools.ts` returns exactly ONE match — the retained `ZERO_VIEW_DIAGNOSTIC_OTHER_DIR` clause.
- [ ] AC6: `c4_diagram_saved` parses through `parseWSMessage`, appears in `KNOWN_WS_MESSAGE_TYPES`, and the exact-match `ws-known-types-guard.test.ts` array is updated.
- [ ] AC7: New/updated tests pass: `c4-concierge-tools.test.ts` (notify spy), `c4-workspace.test.tsx` (component), `ws-zod-schemas.test.ts`, `ws-known-types-guard.test.ts`, `c4-project-route.test.ts`, `c4-concierge-copy.test.ts`.

## Domain Review

**Domains relevant:** engineering, product

### Engineering

**Status:** reviewed
**Assessment:** Implementation domain. WS protocol extension + dispatcher wiring + React listener — all in-repo surfaces with established precedents (ADR-025 frame family, `OPEN_UPGRADE_MODAL_EVENT` CustomEvent bridge, `onSaved` contract).

### Product/UX Gate

**Tier:** advisory — edits an existing component's behavior (`components/kb/c4-workspace.tsx` matches the mechanical UI-surface glob, forcing Product relevance); creates no new page/flow/component file, so the BLOCKING escalation does not fire.
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none — Task-subagent spawn is unavailable in this pipeline context; the assessment was performed inline. No new interactive surface, copy is strictly a removal of a stale instruction.
**Skipped specialists:** none required at advisory tier
**Pencil available:** N/A (no UI surface)

#### Findings

The user-visible delta is positive honesty: the diagram refreshes on its own and the stale banner reflects Concierge saves with the same semantics as Code-panel saves.

## Test Scenarios

- Given a C4 workspace open on `engineering/architecture/diagrams`, when a `c4_diagram_saved` CustomEvent with matching `dirPath` and `rerendered:true` fires, then `useC4Project`'s fetch runs again and any stale banner for that dir clears.
- Given the same workspace with `staleSave` unset, when the event arrives with `rerendered:false` + a diagnostic, then the banner renders for that dir with the diagnostic (parity with `onSaved`).
- Given the same workspace, when the event's `dirPath` is another folder, then no refetch and no state change occur.
- Given `writeC4Diagram` resolves `ok:true`, when the tool handler returns, then `onDiagramSaved` was called once with `{ dirPath: "engineering/architecture/diagrams", rerendered, diagnostic }`; given `ok:false`, it is never called.
- Given a `c4_diagram_saved` frame, `parseWSMessage` accepts a valid payload and rejects missing `dirPath` / non-boolean `rerendered` / extra keys (strictObject).
- **Verify:** `cd apps/web-platform && npx vitest run test/c4-workspace.test.tsx test/c4-concierge-tools.test.ts test/c4-project-route.test.ts test/c4-concierge-copy.test.ts test/ws-zod-schemas.test.ts test/ws-known-types-guard.test.ts` expects `0 failed`.

## Dependencies & Risks

- **Prerequisite:** branch must be synced to `origin/main` first (23 behind, 0 ahead — fast-forward) because all three copy sites exist only post-#8853.
- **Rolling-deploy skew:** a new frame reaching an older client bundle drops inertly via `isKnownWSMessageType` + breadcrumb — safe by design.
- **Risk — copy pin drift:** `c4-concierge-copy.test.ts` pins several `toContain` substrings plus a `will update` count and `/shortly/` ban; new wording must be composed against all four pins, not just the removed clause.

## Sharp Edges

- Write failing tests first (`cq-write-failing-tests-before`): the `c4-workspace.test.tsx` event test and the `onDiagramSaved` spy test should be red before the implementation lands.
- `ws-client.ts`'s switch ends in `_exhaustive: never` — the build fails until the `case` is added; conversely the `case` without the union member fails too. Land wire contract + client case in one commit.
- `ws-known-types-guard.test.ts` is an exact-match set — update its expected array in the same commit as the type addition, or it fails both ways.
- Do NOT add `c4_diagram_saved` to `BUFFERED_FRAME_TYPES` — replayed reloads are spurious; remount already refetches.
- Do NOT key client behavior on `tool_use` `label` — it is a humanized display string, not a stable identifier (#2138).
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6 — it is filled above.
- The listener must live in `C4Workspace`, not inside the concierge window — the panel unmounts on collapse while an in-flight turn can still complete.
- `dirPath` is derived with `slice(0, lastIndexOf("/"))`, not hardcoded to `C4_DIAGRAMS_DIR`, so the payload stays honest if `isC4DiagramPath` ever widens.

## References & Research

- Issue: #8739 (+ member comment enumerating the three copy sites)
- Prior art: #8695 (stale-banner semantics), #8696 (render hardening), PR #8853 (zero-view diagnostic copy), #2138 (raw tool names withheld), #3242 (no structured tool name on the wire), #3374 (precedent: emit a WS frame for in-band client reaction)
- ADR-025 (WS lifecycle-notice family), ADR-059 (replay buffer; frame excluded)
- Files: `components/kb/c4-workspace.tsx`, `components/kb/c4-shared.tsx` (`useC4Project`), `server/c4-concierge-tools.ts`, `server/cc-dispatcher.ts`, `server/ws-handler.ts` (`sendToClient`), `lib/{types,ws-known-types,ws-zod-schemas,ws-client}.ts`, `app/api/kb/c4/project/route.ts`
