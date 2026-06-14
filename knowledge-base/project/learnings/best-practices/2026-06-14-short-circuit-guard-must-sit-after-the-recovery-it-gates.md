# Learning: an honest "X is gone" short-circuit must sit AFTER the recovery that lives inside the path it skips

## Problem

feat-durable-session-resume v1 (#5240) planned FR2/FR3: on resume, probe the
workspace for a `.git` directory; if absent, emit a deterministic honest
"workspace reclaimed — resume with context?" message and **branch around the
agent dispatch** so the SDK agent never produces its misleading fresh-session
greeting. The plan placed the probe *before* dispatch (off the existing
`persistUserMessage` read in `cc-dispatcher.ts`), returning early when `.git`
was absent.

The plan's placement was traced to be a **regression**: the mechanism that
*recovers* a `.git`-absent workspace — `ensureWorkspaceRepoCloned` (the
re-clone self-heal) — runs **inside** the cold dispatch
(`realSdkQueryFactory`), gated on the ~80-line `effectiveInstallationId`
entitlement-promotion chain. A pre-dispatch probe that skips dispatch when
`.git` is absent therefore skips the very re-clone that would fix it. For
exactly the case the probe targets (a resumed, *connected*-repo conversation
whose clone is gone), it converts today's transparent re-clone into a permanent
dead-end: every subsequent message re-trips the probe, and the `[Resume]`
affordance ("send a message", AC8) becomes un-deliverable because the message
that should trigger the self-heal is intercepted before dispatch.

## Solution

Reverted FR2/FR3, shipped FR1 (the load-bearing rebind) + FR4 (the honest
status copy), and deferred the honest reclaimed-message to a follow-up (tracked
on #5240) with the correct design: **emit the honest message only AFTER a
failed self-heal re-clone** (a signal threaded out of `realSdkQueryFactory`,
keyed on the clone result), suppressing the agent greeting at that point — not
before dispatch.

The decision was surfaced to the operator (the descope changes PR scope on a
single-user-incident brand-survival surface) rather than silently shipping the
regression or silently dropping two of five FRs.

## Key Insight

**A short-circuit guard that returns early to skip a code path must be placed
*downstream* of any recovery mechanism that lives inside that path — otherwise
the guard amputates the recovery.** Before adding a "detect bad state → skip
the expensive path → show a fallback" branch, grep for where the *recovery* for
that bad state runs. If recovery is entangled inside the path you're skipping,
the honest fallback belongs *after recovery fails*, not before recovery is
attempted.

Corollary for "honest fallback" UX: a "the thing is gone" message is a
**post-recovery-failure** concept. Placing it pre-recovery makes the message a
lie in exactly the recoverable case, and the more specific your gate (here:
`repo_url present` → "connected, so it's the recoverable case"), the more
precisely you target the cases recovery would have handled.

This is the placement-time companion to the existing work-skill rule "trace the
ACTUAL producer before coding": here, trace the actual *recovery* before
placing a guard that bypasses it.

## Session Errors

- **Bash CWD non-persistence** — a `cd <worktree>` in one Bash call did not
  carry to a later relative `cd`, which failed `No such file or directory`.
  Recovery: absolute paths / `cd` in the same compound command. Prevention:
  already covered by the AGENTS bash-CWD rule; treat every Bash call as a fresh
  CWD.
- **vi.mock factory referenced a top-level spy** — FR1 RED test threw `Cannot
  access 'rpcSpy' before initialization`. Recovery: move the spies into
  `vi.hoisted(() => ({...}))`. Prevention: already documented in the work
  skill's vitest notes; default to `vi.hoisted` for any spy a `vi.mock` factory
  closes over.
- **tsc errors in the new test** — a `vi.fn(async () => ({error:null}))` spy's
  inferred return type rejected an error-object `mockResolvedValueOnce`, and
  `session.ws.send.mock` was untyped (ws typed as `WebSocket`). Recovery:
  explicit `Promise<{error: {...}|null}>` return type + a cast to read `.mock`.
  Prevention: type mock spies at the union they will return, not just the
  default-case shape.
- **FR2/FR3 pre-dispatch-probe regression** — see Problem/Key Insight above.
  Recovery: trace the recovery location, revert, descope with operator
  sign-off. Prevention: the Key Insight (guard sits after the recovery it
  gates); routed as a bounded bullet to the work skill's plan-tracing notes.

## Tags
category: best-practices
module: cc-dispatcher / ws-handler / resume
related: [[2026-06-14-verify-the-read-paths-source-field-not-the-setter-when-fixing-a-binding]] [[2026-06-14-verify-storage-topology-before-accepting-durability-framing]]
