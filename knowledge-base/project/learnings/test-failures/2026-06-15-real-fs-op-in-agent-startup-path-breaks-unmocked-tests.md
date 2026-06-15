---
title: "Adding a real FS op to the agent-startup path breaks every unmocked startup test"
date: 2026-06-15
category: test-failures
module: apps/web-platform/server
pr: feat-one-shot-warm-reprovision-ensure-dir-presandbox
related_issue: 5240
tags: [vitest, mocking, workspace-resolver, agent-runner, cc-dispatcher, blast-radius]
---

# Learning: a new unconditional FS operation in a hot startup path has a test-env blast radius the size of "every suite that exercises that path unmocked"

## Problem

The fix added an **unconditional** `await ensureWorkspaceDirExists(workspacePath, …)` →
`mkdir(workspacePath, { recursive: true })` at both SDK `query()`-construction sites
(`realSdkQueryFactory` in `cc-dispatcher.ts`, `startAgentSession` in `agent-runner.ts`),
to guarantee the bwrap-sandbox CWD exists before construction.

The new helper passed its own unit tests, but the **full vitest run went from green to 95
failures across 17 `agent-runner-*` suites** — with errors that looked unrelated to the
change (`No "purgeWorkspaceLogoObjects" export…`, `release_conversation_slot` instead of
`increment_conversation_cost`). None mentioned `mkdir`.

## Root cause

In the test env, `workspacePath` resolves (via the real `resolveActiveWorkspacePath` /
`fetchUserWorkspacePath`) to `/workspaces/<uuid>` — the default `WORKSPACES_ROOT` is the
literal `/workspaces`, a **root-owned mount that is not writable on dev/CI**. The
unconditional `mkdir('/workspaces/…', {recursive:true})` therefore threw `EACCES` → the
helper's fail-loud throw → `startAgentSession` aborted into its error/cleanup branch
(`release_conversation_slot`, generic-error sanitization, the `purgeWorkspaceLogoObjects`
mock gap in the cleanup path). The *visible* failures were all downstream of the abort.

Why it was invisible before: the only prior `mkdir` on this path lived **inside**
`realGraftRepoClone`, reached only PAST `ensureWorkspaceRepoCloned`'s not-connected /
`.git`-present early-returns. Unmocked startup tests are all not-connected, so the gated
mkdir never ran — no FS write, no EACCES. Making the mkdir **unconditional** removed that
accidental protection.

This is the same class as the **id-shape-guard fixture blast-radius** learning
(`2026-06-15-id-shape-guard-test-fixture-blast-radius-and-syntactic-sast.md`): adding a
real side-effect (FS write / throwing guard) to a shared hot path breaks every test that
reaches it without mocking the new dependency. A "3-file source change" had a ~17-file
test blast radius.

## Solution

A node-project vitest **setup file** that defaults `WORKSPACES_ROOT` to a writable temp dir:

```ts
// apps/web-platform/test/setup-node.ts
process.env.WORKSPACES_ROOT ||= join(tmpdir(), "soleur-vitest-workspaces");
```

wired via `vitest.config.ts` `projects[unit].setupFiles`. `||=` only fills an unset/empty
value, so tests that set their own `WORKSPACES_ROOT` (or `delete` it to assert the
`/workspaces` default) are unaffected (their file-top assignment runs after the setup).
This fixed 92 of 95. The remaining 3 (`agent-runner-chapter-chunked.test.ts`) **partial-mock
`node:fs/promises` with `readFile` only** — so the newly-imported `mkdir` resolved to
`undefined` and threw; fixed by adding `mkdir: vi.fn(async () => undefined)` to that mock.

Why a global setupFile rather than a 16-file per-test sweep: verified no node test asserts a
*resolved* default `/workspaces/<id>` path, `resolveCronWorkspaceRoot()` reads a separate
`CRON_WORKSPACE_ROOT`, and the literal `/workspaces/x` references elsewhere are passed-in
args or mocked-resolver returns — so the single-point fix is safe and was confirmed by a
full-suite run (10,133 passed).

## Key Insight

When you add a real, unconditional **side-effect** (FS write, network call, throwing guard)
to a shared agent-startup path, the test blast radius is **{every suite that exercises that
path} − {suites that mock the new dependency}**. Before coding, ask: what does this side
effect do against the *test-env* resolution of its inputs? For workspace-pathed FS ops the
answer is "tries to mkdir the unwritable `/workspaces` default and aborts startup." Size that
first; the cheapest fix is usually a writable test-env default (one setup file), not a
many-file mock sweep — but verify no test asserts the production default before changing it.

## Session Errors

1. **95-test blast radius from the unconditional mkdir** — Recovery: `test/setup-node.ts`
   defaulting `WORKSPACES_ROOT` to a writable temp. Prevention: treat a new FS op on a hot
   startup path as a test-env side-effect to size up-front (this learning).
2. **Residual suite from a partial `node:fs/promises` mock missing `mkdir`** — Recovery:
   added `mkdir` to the mock. Prevention: a newly-imported node-builtin function must be
   added to every partial mock of that builtin that loads the importing module (sibling of
   the existing work-skill "partial node-builtin mock" guidance).
3. **Mock-sweep grep missed `../server/`-relative specifiers** — `git grep
   '@/server/ensure-workspace-repo'` found only alias-form mocks; agent-runner tests mock via
   `../server/`. Recovery: re-grep both forms. Prevention: when sweeping mock specifiers,
   grep BOTH the `@/`-alias and relative-path forms.
4. **Initial root-cause hypothesis was wrong** ("fire-and-forget ordering race"); deepen-plan
   agents (architecture-strategist + spec-flow-analyzer) re-diagnosed it to "the conditional
   mkdir skips not-connected workspaces AND the sandbox binds the factory's OWN resolved
   `workspacePath`, not `args.workspacePath`." One-off for this bug; caught at plan time, no
   recurrence vector beyond "trust deepen-plan to falsify the routing-phase hypothesis."
