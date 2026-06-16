---
title: "A no-op-gate test's emit-detector must match the gate's OWN output, not any frame of that type"
date: 2026-06-16
category: test-failures
module: apps/web-platform/test
tags: [vitest, test-design, gating-primitive, vacuous-assertion, repo-readiness-gate]
issue: 5399
pr: 5405
---

# Learning: scope a no-op-gate's emit-detector to the gate's own copy

## Problem

The wiring test for the legacy-leader repo-readiness gate (#5399) has two classes of case:

- **Block cases** (cloning / error): the gate emits `sendToClient({type:"error", message})` and early-returns.
- **No-op cases** (ready / not_connected / read-throws-fail-open): the gate must emit
  NOTHING and let dispatch proceed.

To assert "the gate emitted nothing" on the no-op cases I wrote a helper that filtered
`sendToClient` calls to `payload.type === "error"`. It false-failed AC5a/AC5b
(`expected [ [ … ] ] to have a length of +0 but got 1`): on the no-op path the dispatch
**proceeds** and a *downstream* failure (router/sandbox mock) emits its OWN
`{type:"error", …}` frame — which the broad helper miscounted as a gate block.

## Root cause

`type:"error"` is not unique to the gate. The gate shares the WS error-frame shape with
every other dispatch failure path. A detector keyed only on `type` cannot tell "the gate
blocked" from "something downstream of a *proceeding* dispatch errored." So:

- on a **no-op** case it FALSE-FAILS (counts a downstream frame as a gate emit), and
- on a **block** case the same broad detector could FALSE-PASS vacuously (a downstream
  error frame would satisfy it even if the gate itself never fired).

## Solution

Scope the emit-detector to the gate's OWN copy — the exact strings only the gate produces
(here `REPO_CLONING_MSG` and the `repoErrorMsg(...)` `"Repository setup failed:"` prefix,
imported from the REAL evaluator so they can't drift):

```ts
function gateErrorEmits() {
  return mockSendToClient.mock.calls.filter(([, payload]) => {
    if (!payload || typeof payload !== "object") return false;
    const p = payload as { type?: string; message?: string };
    if (p.type !== "error" || typeof p.message !== "string") return false;
    return p.message === REPO_CLONING_MSG || p.message.startsWith("Repository setup failed:");
  });
}
```

Block cases assert `gateErrorEmits()` has the gate frame AND `query`/`mockFrom` were never
called; no-op cases assert `gateErrorEmits()` is empty AND dispatch proceeded.

## Key Insight

When a gating primitive shares an output channel/shape with the code path it gates
(a WS error frame, an HTTP status, a log line, a metric), a test that detects the gate's
action by the SHARED shape is ambiguous in BOTH directions: it false-fails the no-op case
(downstream output counts as the gate) and can vacuously pass the block case (downstream
output satisfies the assertion without the gate firing). Key the detector on something only
the gate emits — its specific copy/code/tag — imported from the real source so it can't
drift. This is the emit-channel analogue of the existing "distinguish gate-absent from
gate-present" RED-verification discipline.

## Session Errors

1. **Planning subagent Write blocked at bare-repo path** (forwarded) — Recovery: retried at
   the worktree path. Prevention: already covered by `hr-when-in-a-worktree`; subagents must
   `cd <worktree> && pwd`-verify first (one-shot Step 0 already prescribes this).
2. **`gh pr view 5394` did not resolve** — one-off; #5394 is the issue, the gate merged as
   PR #5395. Prevention: none needed — issue-vs-PR number divergence is expected; the plan's
   Premise Validation already recorded it.
3. **Bash CWD drift on an AC9 `git grep`** — the tool CWD was inside `apps/web-platform`
   from a prior `cd`, so a repo-root-relative path errored `ambiguous argument`. Recovery:
   re-ran with the app-relative path. Prevention: already documented — chain
   `cd <abs> && <cmd>` in one Bash call; the Bash tool does not persist CWD.
4. **No-op-gate emit-detector too broad** — Recovery: scoped `gateErrorEmits()` to the
   gate's own copy. Prevention: this learning.
