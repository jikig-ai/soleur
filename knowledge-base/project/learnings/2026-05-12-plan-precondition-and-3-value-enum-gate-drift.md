---
date: 2026-05-12
category: workflow-patterns
module: chat
issue: "#3603"
pr: "#3653"
tags: [plan-verification, react-state-machine, multi-agent-review, predicate-placement]
---

# Plan precondition drift + 3-value enum gate slip — PR-B cohort marker

## Problem

PR-B (cohort missing-reply marker, text-only `<aside role="note">` mounted in
`chat-surface.tsx`) was scoped at plan time as "30-LoC text-only marker + mount
+ 4 tests + one-line spec annotation." Work-phase execution surfaced **two
plan-versus-codebase drifts** and the 11-agent review surfaced **one P1 gate
slip** that the plan's own §FR2 refinement was supposed to address. All three
were caught and fixed inline, but each is a class of mistake that compounds if
the workflow doesn't learn from it.

## Drift 1 — Plan claimed `conversation.created_at` was accessible at the mount scope; it wasn't

**Plan §Phase 0.1:** "Read `chat-surface.tsx` lines 570-740 to confirm … (d)
`conversation.created_at` (or equivalent) is accessible from the surrounding
scope of the mount point."

**Reality:** `ChatSurface` takes `conversationId: string` (a prop, not an
object). `useWebSocket(conversationId)` returns a flat record of slices
(`messages`, `streamState`, `workflowEndedAt`, etc.) but neither
`conversationCreatedAt` nor any per-message `created_at` is exposed — the
hydration mapper at `ws-client.ts:957-1016` strips DB row timestamps when
producing `ChatMessage[]`. The `/api/conversations/:id/messages` server route
also did not select or return `conversations.created_at`.

**Cost:** ~3 boundary edits to plumb the field (`api-messages.ts` select +
response; `ws-client.ts` slice + hydration; `chat-surface.tsx` destructure).
All three followed the existing `workflowEndedAt` precedent exactly, so the
edits were small and consistent — but the plan's precondition check was
satisfied by reading the file, not by grepping for the slice.

**Generalizable lesson:** Plan precondition checks for "X is accessible at
scope Y" must include a **grep for X in the file that exposes scope Y**, not
just a read of the consuming code. The consuming code may name a variable
optimistically (`conversation.created_at` reads as if it's a property of an
in-scope object) when the producing scope only has `conversationId: string`
and a flat hook return.

**Routes to:** `plugins/soleur/skills/plan/SKILL.md` — Phase 0.1 precondition
checks should require a grep against the producing-scope source file, not just
a read of the mount site. Add Sharp Edges entry.

## Drift 2 — Plan architecture vs. plan-authored test list were incompatible

**Plan §1.1.2 test list (parametrized):**

```text
test.each([healed, postFix, preWindow, streaming, postSunset])(
  "AC2-AC6 — hides marker when {label}",
  ({ fixture, expectHidden }) => { ... }
)
```

Each row needs `messages`, `createdAt`, and `isStreamingAssistant` as inputs
to the component under test.

**Plan §1.3.2 mount architecture (IIFE-at-mount):**

```tsx
{(() => {
  const textMessages = messages.filter((m) => m.type === "text");
  const isCohortMissingReply = ... // 5 inline gates
  return isCohortMissingReply ? <CohortMissingReplyMarker createdAt={...} /> : null;
})()}
```

The component takes **only** `createdAt`. The predicate lives in
`chat-surface.tsx`. The tests cannot exercise the predicate without rendering
`<ChatSurface>` itself.

**Resolution:** moved predicate **into** the component (props become
`createdAt`, `messages`, `isTurnInFlight`). Tests now drive the component
directly without ChatSurface scaffolding. Plan's IIFE-at-mount design was
overspecified for testability.

**Generalizable lesson:** When a plan specifies both (a) a component
architecture and (b) a parametrized test list, cross-check that the test
signatures' inputs match the component's prop boundary. If the test list's
fixtures span predicate state that the architecture pushes outside the
component, one of the two must change. Architecture > tests if the tests can
be rewritten to drive through a higher-level mount; tests > architecture if
the test inputs are the load-bearing requirement (which they were here — the
brainstorm's failure-mode enumeration owns the test list).

**Routes to:** `plugins/soleur/skills/plan/SKILL.md` — add to Sharp Edges:
"When the plan specifies a parametrized test list (`test.each`), verify the
proposed component prop boundary can receive every parameter row's inputs."

## Slip — 3-value enum gate covered only 2 values

**Plan §FR2 refinement (Research Reconciliation):** marker hides when
`!isStreamingAssistant`. Plan Risk R1 mitigation: "Phase 0.1 reads
chat-surface to confirm the exact state name."

**Implementation (work phase):** `isStreamingAssistant={streamState === "streaming"}`.

**Codebase:** `StreamState = "idle" | "streaming" | "stopping"` (`ws-client.ts:47`).

The plan named one of the three values in the FR2 refinement. The
implementation honored the plan. Both missed that `"stopping"` is a
distinct in-flight state that mid-aborts traverse for some hundreds of
milliseconds. A Stop click on a cohort thread could flash the marker during
that window.

**Caught by:** `user-impact-reviewer` at PR review time — only because the
review-spawn prompt explicitly asked the agent to "walk the predicate against
`streamState === 'stopping'`." Without the prompt, the agent likely produces
the same false-pass as the plan and the work phase did. The signal that
prevented this from shipping was a **review prompt that named the 3-value
enum**, not the agent's pattern-matching by default.

**Resolution:** renamed prop to `isTurnInFlight`, bound to
`streamState !== "idle"`. AC5b test added.

**Generalizable lesson:** Whenever a plan FR conditions on a single enum
value (`!isStreamingAssistant`, `status === "completed"`, etc.), the FR text
must enumerate every value of the enum at the predicate boundary. If the enum
has N values, the FR must explicitly classify all N as include/exclude.
Single-value FRs hide the same class of bug under any future schema widening.

**Routes to:** `plugins/soleur/skills/plan/SKILL.md` — enum-gate enumeration
rule; `plugins/soleur/skills/review/SKILL.md` — when reviewing a gate
conditioned on `X === <literal>` where `X` is a union/enum, prompt the
user-impact-reviewer to enumerate every union member.

## Multi-agent review value asymmetry (confirmed)

The 11-agent review on PR #3653 surfaced 3 P1 findings:
1. `streamState === "stopping"` gap (user-impact)
2. Seed-once `conversationCreatedAt` shows stale date on sidebar conversation switch (data-integrity)
3. Missing `"use client"` directive (code-quality)

Findings #2 and #3 would NOT have been caught by single-agent review. Finding
#2 required tracing the `useWebSocket` hook lifetime across `realConversationId`
changes in the sidebar variant — a multi-file lifecycle trace. Finding #3
required cataloging sibling files for parity.

Confirms `knowledge-base/project/learnings/2026-04-15-multi-agent-review-catches-bugs-tests-miss.md`:
even on a "verbatim prose-plan execution" with 4071/0 green tests, multi-agent
review catches load-bearing bugs.

## Session Errors

1. **Initial `git` ops from bare repo root failed** — `git branch` returned
   "fatal: this operation must be run in a work tree" because the repo is
   `core.bare=true`. **Recovery:** cd into `.worktrees/<branch>/`.
   **Prevention:** at session start when a worktree is named in the invocation,
   the first Bash call must cd into the worktree absolute path before any git
   ops. PreToolUse hook proposal in Phase 1.5 below.

2. **Bash CWD non-persistence** — `cd apps/web-platform` succeeded, but a later
   call invoked `./node_modules/.bin/vitest` without re-cd'ing and failed with
   "No such file or directory." **Recovery:** chain `cd ... && ./node_modules/.bin/...`
   in a single Bash call. **Prevention:** AGENTS.md `hr-the-bash-tool-runs-in-a-non-interactive`
   already covers this; the omission was my error.

3. **Plan `conversation.created_at` precondition false-pass** — see Drift 1.
   **Recovery:** plumbed the field through 3 boundaries. **Prevention:** plan
   skill Phase 0.1 should require a grep against the producing scope, not just
   a read of the consuming code.

4. **Plan architecture vs test list mismatch** — see Drift 2. **Recovery:**
   moved predicate into the component, kept the test list verbatim.
   **Prevention:** plan skill Sharp Edges entry on parametrized test lists.

5. **`sed` enumeration suffix loss** — `sed 's/- \[ \] 1\.2\.[1-6]/- [x] 1.2./g'`
   stripped the trailing digit. **Recovery:** awk-with-counter restore from
   `/tmp/`. **Prevention:** use awk-with-counter or per-line Edit for
   ID-bearing substitutions in markdown checkboxes. Sed's `\1` capture isn't
   reliable in this idiom across busybox/GNU.

6. **`bun lint` interactive ESLint config prompt** — `next lint` is deprecated
   and the project hasn't migrated. **Recovery:** documented + skipped lint in
   the work-phase gate; tsc + vitest covered the surface. **Prevention:**
   separate PR to migrate `next lint` → ESLint CLI per Next.js deprecation
   notice.

7. **3-value enum gate slip** — see Slip section above. **Recovery:** prop
   renamed + bound to `!== "idle"` + AC5b test. **Prevention:** plan + review
   skill updates to enumerate every union member at gate boundary.

## Tags

- category: workflow-patterns
- module: chat
- compound-source: feat-cc-transcript-hardening-prb-3603
- pr: #3653
