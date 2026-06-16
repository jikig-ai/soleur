# Learning: a new parallel recovery path must reuse the SAME resource-selection as the self-heal it mirrors

## Problem

#5340 / #5240 added deterministic workspace re-provision on reconnect across two
divergent turn-start paths. The Concierge cold factory already self-healed a
missing repo via `ensureWorkspaceRepoCloned`, but it cloned with
`effectiveInstallationId` — the entitlement-PROMOTED repo-owner install computed
by a ~60-line self-heal (feat-one-shot-concierge-gh-403) that exists precisely
because the raw stored install can be a cross-account personal install that
`403`s on an org repo.

The new warm-query per-dispatch re-provision (`cc-reprovision.ts`) and the new
leader recovery (`agent-runner.ts`) each resolved the install with the RAW
`resolveInstallationId(userId)` — skipping the promotion. On a warm reconnect to
a cross-account ORG repo with a genuinely-gone `.git`, the raw clone `403`s →
`ReprovisionOutcome` `"failed"` → the user sees the honest "workspace reclaimed —
couldn't restore automatically" message for a repo a COLD turn would have
recovered with the promoted install. The message lies in exactly the case the
promotion logic was built to fix.

tsc was silent (raw vs promoted are both `number | null`); the unit tests passed
(each path tested in isolation); only the multi-agent review's
`architecture-strategist` (corroborated by `pattern-recognition-specialist`)
caught the cross-path divergence.

## Solution

Extract the SELECTION into one shared helper and route every path through it:
`resolveEffectiveInstallationId({ userId, installationId, repoUrl })` in
`cc-effective-installation.ts`. The cold factory, the cc per-dispatch resolve,
and the leader recovery all call it, so the credential selection cannot drift.
The extraction was behavior-preserving for the factory (verified by the existing
`cc-dispatcher-real-factory` / `cc-dispatcher-self-heal-observability` suites)
AND made the promotion branches unit-testable for the first time (the factory
was previously "impractical to invoke whole", so the promotion had no direct
test).

## Key Insight

When you add a SECOND code path that performs the same operation as an existing
self-heal (a parallel recovery, a warm-path mirror of a cold path, a leader
mirror of a Concierge path), the new path must reuse the original's
**resource/credential SELECTION**, not just its final primitive. Two paths that
call the same `doThing(resource)` but resolve `resource` differently are NOT
idempotent-equivalent — they diverge on exactly the edge case the original's
selection logic was built to handle. The cheapest guard: extract the selection
into a shared helper the moment a second caller appears, rather than re-resolving
"the obvious way" at the new call site. Comments that call the two paths
"idempotent" mask this — idempotent on the HAPPY path is not idempotent on the
selection edge case.

Corollary (placement, reinforced from
[[2026-06-14-short-circuit-guard-must-sit-after-the-recovery-it-gates]]): an
honest "it's gone" message gated on a recovery OUTCOME is only as honest as the
recovery is strong. A weaker recovery on one path makes the same message lie.

## Tags
category: best-practices
module: apps/web-platform/server (cc-dispatcher, cc-reprovision, agent-runner, cc-effective-installation)

## Session Errors

- **Review classification `set -uo pipefail` tripped the shell snapshot** (`ZSH_VERSION: unbound variable`). Recovery: re-ran the classification greps without `set -u`. Prevention: one-off / machine-specific (the host shell-snapshot references `ZSH_VERSION` under `set -u`); not a project-rule defect.
- **Anti-slop scanner inline python heredoc syntax error.** Recovery: wrote the scanner JSON to a file, parsed separately. Prevention: one-off command-construction slip; prefer writing tool output to a file before piping to a multi-line parser.
- **tsc type mismatch on the integration test's `sendToClient` passthrough** (`Mock` not assignable to `(userId, message) => boolean`). Recovery: cast at the `dispatchSoleurGo` call site. Prevention: expected TDD iteration; helper params typed as `ReturnType<typeof vi.fn>` need a cast when passed to a typed callback param.
- **`Monitor` deferred tool called before its schema was loaded** → InputValidationError. Recovery: used the inline-returned schema params. Prevention: one-off; ToolSearch a deferred tool before first call.
