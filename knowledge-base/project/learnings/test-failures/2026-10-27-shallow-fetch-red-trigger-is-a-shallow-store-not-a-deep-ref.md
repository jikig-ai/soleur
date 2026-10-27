---
title: A shallow-fetch RED trigger needs a SHALLOW store, not a ref below the client's boundary — and the refusal is quiet
date: 2026-10-27
category: test-failures
component: apps/web-platform/test/git-data-remote-url-wrapper.test.ts
tags:
  - git-shallow
  - update-shallow
  - red-trigger
  - fixture-design
  - git-data
related:
  - https://github.com/jikig-ai/soleur/issues/8211
  - https://github.com/jikig-ai/soleur/pull/11342
  - knowledge-base/project/plans/2026-10-27-fix-git-data-store-shallow-push-plan.md
  - knowledge-base/project/learnings/best-practices/2026-10-27-exec-line-pinned-by-live-host-probe-forces-conditional-branch.md
---

# Learning: a shallow-fetch RED trigger needs a SHALLOW store, not a ref below the client's boundary — and the refusal is quiet

## Problem

The #8211 plan's R-FETCH-OVERLAY scenario originally specified its RED trigger as
"a store ref whose tip is BELOW the fetcher's shallow boundary" — the intuition
that fetching a ref whose history crosses the client's `.git/shallow` line makes
`git fetch` refuse without `--update-shallow`. Measured during implementation:
that is not what the protocol does. When the store holds FULL history the server
can cut the pack at the client's advertised shallow boundary (or send only the
objects above it), so the fetch completes, the ref lands, and the pre-fix
codepath goes GREEN — a vacuous pass, the worst shape for a RED-first test.

## Solution

The reliable trigger is a SHALLOW STORE. Seed the bare fixture repo with
`git config receive.shallowUpdate true` and drive a real `--depth 1` push through
the wrapper — the store's own `.git/shallow` gains a root, which is exactly the
state the production `-c receive.shallowUpdate=true` flag produces. When a second
`--depth 1` clone holding none of those objects fetches the ref, the server cuts
the pack at ITS shallow root, and the client MUST update `.git/shallow` to accept
it — the precondition `--update-shallow` exists to lift. That is the fixture
R-FETCH-OVERLAY ships (`apps/web-platform/test/git-data-remote-url-wrapper.test.ts`,
the `overlay-pusher`/`overlay-fetcher` pair).

Second fact in the same fixture: the refusal is QUIET. Without the flag
`git fetch` exits 0, prints `shallow roots are not allowed to be updated` as a
warning, and lands no ref. The RED assertion must therefore be on the landed
post-condition — `refs/remotes/git-data/<branch>` resolving to the pushed sha —
never on fetch's exit code: an `expect(status != 0)` arm reads the refusal as a
pass.

## Key Insight

When a test's RED arm depends on a protocol peer refusing, make the SERVER the
party that cannot satisfy the request. "Client wants an object it cannot
represent" is client-side reasoning the transport negotiates around; "server
cannot send the objects without renegotiating shallowness" is a state only the
flag lifts. And assert the post-condition (the ref landed), because git protocol
refusals ride warnings at exit 0.

## Session Errors

- **`CLAUDE_PLUGIN_ROOT` unset in the subagent's exec shells** (forwarded from the
  plan phase; recurred in the QA+compound phase — the token-efficiency script's
  first invocation 127'd on the empty var) — Recovery: resolved the plugin root by
  IDENTITY (manifest `grep -l '"name".*"soleur"'`), per the cloud-mode fallback. —
  **Prevention:** always resolve `CLAUDE_PLUGIN_ROOT` by identity in exec shells
  rather than assuming the export; the fallback block in every SKILL.md is the
  procedure.
- **No Task/Skill/agent-spawn capability in the subagent harness** (forwarded) —
  plan's research fan-out, plan-review panel, advisor consult and deepen-plan
  spawns could not run; in-process gates ran instead and the plan's Enhancement
  Summary disclosed it — Recovery: parent discharged CPO/CTO consults via its
  two-spawn allowance. — **Prevention:** harness capability is a plan-phase
  precondition; check spawn capability before prescribing agent fan-outs.
- **None in the QA phase itself** — all four suites green on first run.

## Tags

category: test-failures
module: apps/web-platform
