# Learning: a shared last-write-wins status slot's `.tag` is the last-ATTEMPT tag — resolve the ACTUALLY-RUNNING value from a per-resource endpoint instead

## Problem

`web_2_recreate`'s pin-gate (`apply-web-platform-infra.yml`) resolved web-1's
known-good image tag by reading `https://deploy.<domain>/hooks/deploy-status`
`.tag`. That endpoint is a **single last-write-wins JSON object** (`ci-deploy.sh`
`write_state`) stamped by *multiple independent writers* — a web-platform deploy,
an inngest watchdog restart, a git-lock sweep. When a non-web writer owned the
slot (an inngest restart stamping `{component:inngest,tag:latest,exit_code:0}`),
the gate read a non-semver `latest` and hard-aborted the recreate (`got 'latest'`)
even though web-1 was perfectly healthy. The recreate stayed blocked until the
next web-platform deploy re-stamped the slot (#6147).

## Solution

Resolve the running tag from the resource's **own** authoritative endpoint —
web-1's public `app/health` `.version` (the baked `BUILD_VERSION` of the
actually-running container) — and drop the shared-slot read entirely. This is the
exact pattern ADR-079 amendment #5955 already adopted for `apply-deploy-pipeline-fix.yml`.
It has no writer-contention surface, no `component` literal to get wrong, and no
`.tag`-vs-running-image skew. The resolved `v<version>` still flows through the
unchanged digest-resolution → coherence-preflight safety envelope
(abort-before-`-replace`), so the fix is a read-source swap, not a safety change.

Extract the decision logic (strict-semver validate + prepend `v`) into a **pure,
network-free** script (`resolve-web1-known-good-tag.sh`) so the load-bearing
`^v[0-9]+\.[0-9]+\.[0-9]+$` guard is fixture-testable, mirroring the
`deploy-status-fanout-verify.{sh,test.sh}` seam. Keep the curl retry loop in the
workflow.

## Key Insight

Two generalizable rules:

1. **`.tag` on a shared last-write-wins status slot is the last-ATTEMPT tag, not
   the running state.** Any reader that needs "what is actually running right now"
   must read the resource's own endpoint (a `/health .version`, a `docker inspect`,
   a live query), never a slot that unrelated writers can clobber. Treat every
   `.tag`/`.version`/`.state` read off a shared slot as "which writer stamped this
   last?" until proven otherwise.

2. **Sibling-reader sweep: classify each reader by what it DOES with the value,
   not by whether it touches the same field.** When fixing one contaminated
   reader, grep every other reader of the same slot — but a reader that feeds only
   a *positive-match poll* (`[[ "$TAG" != "$WANT" ]] → keep waiting`) or already
   tolerates the wedge value (`^(v…|latest)$`) is NOT the same bug: a wedge value
   causes at most a spurious retry, never a hard abort. The dangerous siblings are
   the ones that *resolve a deploy tag* from the slot. (In this PR the plan's
   disposition note cited the wrong line — `deploy-status-fanout-verify.sh:219`, a
   safe positive-match poll — when the actual tag-resolving sibling is `:180`;
   pattern-recognition review caught it. The "don't fold in" conclusion was still
   correct because `:180` already accepts `latest`.)

## Session Errors

- **Planning subagent's first `Write` targeted the main-repo path instead of the
  worktree** (forwarded from session-state.md) — Recovery: re-written to the
  worktree path immediately. Prevention: already covered by one-shot Step 0's
  subagent CWD-verification gate; self-correcting. One-off.
- **A file-reading review agent reported a "CRITICAL working-tree stub"
  overwriting the resolver** — Recovery: it was `test-design-reviewer`'s transient
  in-place RED mutation; verified the committed HEAD intact via `git status` +
  `git diff HEAD -- <file>` (empty) and re-ran the test (13/13). Prevention:
  already documented in `review/SKILL.md` ("Concurrent mutating agents contaminate
  the shared worktree — run `git diff HEAD` yourself before trusting the finding").
  One-off.

## Tags
category: best-practices
module: apps/web-platform/infra
issue: 6147
related: ADR-079 (#5955), #6090, #6136
