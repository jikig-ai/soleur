---
title: a listener that survives the collapse is dead if the collapse killed its channel
date: 2026-09-25
category: ui-bugs
tags: [c4, websocket, concierge, mount-lifecycle, stale-banner, event-channel]
module: apps/web-platform
symptoms: [stale-diagram-after-concierge-save, dropped-frame-on-collapse, wrong-mount-lifetime-reasoning]
issue: "#8739"
pr: "#8892"
---

# Listener survival is not channel survival

## Problem

#8739: a Concierge `edit_c4_diagram` completing while the C4 workspace was open changed nothing on screen — nothing refetched the precomputed `model.likec4.json`, and the stale-save banner kept its old reason. Three copy sites compensated with "then reload the page."

The fix pushed a server→client `c4_diagram_saved` WS frame (tool-handler `onDiagramSaved` opt → `sendToClient` → ws-client → `window` CustomEvent → `C4Workspace` listener). The plan deliberately mounted the listener on `C4Workspace` — which survives for the page's life — because the concierge window unmounts on collapse.

Two independent review seats then found the flaw in that justification: **the concierge panel owns the page's only WebSocket.** Collapsing it unmounts `ChatSurface`/`useWebSocket` → client `ws.close()` → server `sessions.delete(userId)` → the save completing mid-collapse emits to no session (`sendToClient` returns `false`, frame dropped). The listener survives; the channel it listens to does not. "Still heard" was never true — the same reasoning error one level down.

## Solution

Keep the long-lived listener (it is still correct — a listener on the concierge window would die mid-turn even with the socket alive), and add the second half the first design missed:

1. **Reopen recovery:** `C4Workspace` refetches silently (`reload({ silent: true })`) on the `conciergeCollapsed: true→false` transition — the in-page recovery point for any save that landed while the socket was gone, regardless of the 30s disconnect-grace expiry.
2. **`silent` reload option** in `useC4Project` so unsolicited refetches don't flip `loading` and unmount `C4Canvas` for a spinner flash.
3. **`.c4`-only emit:** `.md` view-embed saves never re-render; reporting them `rerendered:true` would clear a stale banner while the rendered model still predates the `.c4` source — silent staleness with no race required.
4. **Honest comments:** "still heard on collapse" and "no open page can be stale when no client is connected" were both falsified by `supersedeExistingUserSocket` + `sessions.delete` on close — fixed.

**Not done (measured, deferred):** joining the ADR-059 buffered family is the wrong tool — the replay ring is **per-conversation** (`EvictInfo.conversationId`, `BufferedFrame` requires `conversationId`) while the frame is deliberately user-scoped; threading a conversationId would cost more than the residual hole (a dropped `rerendered:false` frame can't resurrect the client-side banner on reopen) is worth.

## Key Insight

When a notification path is `producer → transport → DOM event → mounted component`, the mount-lifetime question has **three** lifetimes to check — listener, transport, producer — and "the listener survives" says nothing about the other two. The review question that caught it: *"what owns the socket, and what happens to it when the thing I was protecting against happens?"*

## Session Errors

1. **Orphaned gate run after killing the commit wrapper.** `git commit` blocked on `test-all.sh --affected` queueing behind a sibling's lock; killing the wrapper left the `test-all` child alive holding a queue ticket, and the sibling session reported us as the lock holder. **Prevention:** kill the whole process group / wait for the queued run, never just the wrapper; check `ps --ppid` for survivors after any kill.
2. **`npx tsc` instead of the pinned `./node_modules/.bin/tsc`.** Caught by the work SKILL.md pinned-binary rule before it could produce version-drift false errors. **Prevention:** existing rule — comply.
3. **Copy reword contained its own banned substring.** The test pinned `not.toContain("tell the user to reload")` and my negation clause "do not tell the user to reload" contained it. **Prevention:** when a pin bans a phrase, write the replacement *positively* — a negated instruction still teaches the phrase.
4. **Fixture dirPath drift timed out new tests.** Changed event fixtures to the production shape (`engineering/architecture/diagrams`) but the render helper defaulted to the old `knowledge-base/` shape — the dirPath gate filtered every event. **Prevention:** when normalizing a fixture, trace BOTH producers of the compared value (prop source AND event payload).
5. **Edits under a live gate run produced a false FAIL.** `operator-ack-guard`'s tree-isolation check saw uncommitted `M` files mid-run. **Prevention:** run the affected gate on the final committed tree, or never edit while it runs — the runner reads the live worktree.
6. **Forwarded from session-state:** bare-root CWD drift (`pathspec did not match`), plan-artifact read from the wrong directory, plan/deepen-plan subagent fan-outs unavailable (sequential-fallback), plan commit's first `lint-infra-no-human-steps` rejection on "reload the page" prose.

## Review-evidence note

Panel: 10 seats (design-validity pass: code-simplicity + architecture-strategist; then git-history, pattern-recognition, security-sentinel, performance-oracle, data-integrity, agent-native, code-quality, test-design). `Reviewed-Coverage: sequential-fallback` — this environment has no plugin-agent spawn path; all seats ran as generic subagents with the agent definitions inlined as prompts.
