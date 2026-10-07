---
title: "fix: broad /workspaces deny on the vendored SDK's deny-then-restore ordering — closes the ADR-075 tenant-isolation TOCTOU"
type: fix
date: 2026-10-07
slug: fix-vendored-sdk-bwrap-argv-reorder
branch: feat-one-shot-5862-bwrap-argv-reorder
issue: 5862
closes: 5862
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
refs: [5862, 5863, 5733, 5848, 5864, 5913, 5875, 8623, 8752, 9595, 9601, 9614, 9618]
---

# fix: broad /workspaces deny on the vendored SDK's deny-then-restore ordering — closes the ADR-075 tenant-isolation TOCTOU

## Enhancement Summary

**Deepened on:** 2026-10-07 (deepen-plan, sequential-fallback — no Task fan-out in this harness)
**Sections enhanced:** Proposed Solution (fixture-diff expectation), Technical Considerations, Phase 3 audit, Dependencies & Risks, References
**Research basis:** installed-binary builder inspection (`claude-agent-sdk-linux-x64` 2.1.284 embedded JS), ADR-075/ADR-079, capture/projection source, committed fixture, live `gh` issue/PR verification, `lint-guard-contract.py` + Scope-Check gate runs.

### Key Improvements

1. Substituted the issue's patch-mechanism prerequisite with the verified
   vendored-builder ordering at 2.1.284 (cut, pending Phase-3 audit).
2. Identified and closed the readOnly (support-persona) regression: broad
   deny without an `allowRead` restore would blind support sessions.
3. Corrected the dispatch's "token-order-only" fixture-diff expectation to
   the additive shape a covering `--tmpfs` landing produces.
4. Phase-3 audit broadened from `/dev/null` masks to ALL pre-tmpfs
   ws-internal mounts (`.claude` self-binds, `.cc-writes`) — same shadow class.

### New Considerations Discovered

- The vendor's per-landing restore loop also emits `--ro-bind` restores for
  `allowWithinDeny` paths — the readOnly arm reuses that, not a new mechanism.
- The production bwrap shim preserves `--args` fds but never inspects argv
  content — a contingency argv-rewrite would change that contract (flagged,
  not planned).

## Overview

ADR-075 is `accepted` with a bounded residual TOCTOU: the agent sandbox hides
sibling tenant workspaces by enumerating them at dispatch
(`enumerateSiblingDenyPaths` → per-sibling `denyRead`), so a sibling created
*after* a session's bwrap namespace is built stays read-only-visible via the
base `--ro-bind / /` (exploitable via Bash only, under adversarial steering).

The vendored SDK stack has since moved to
`@anthropic-ai/claude-agent-sdk@0.3.284` spawning the CLI 2.1.284 native
binary, whose embedded bwrap builder implements the ADR-075 Option-C ordering
natively: for each `denyRead` landing it emits `--tmpfs <landing>` **then
re-binds every covered `allowWrite` path read-write** (the binary's own
`[Sandbox Linux] Re-bound write path wiped by denyRead tmpfs:` restore
branch), and `allowRead` paths re-bind read-only as
`Re-allowed read access within denied region`. The writable-within-deny
expressibility gap that forced per-sibling enumeration in July is closed in
the vendored bytes.

This plan reverts `buildAgentSandboxConfig` to the structural shape —
`denyRead: [workspacesRoot(), …]` (the parent tmpfs masks present **and
future** siblings; no dispatch-time `readdirSync`, no TOCTOU) — adds the
readOnly persona's `allowRead` restore, re-captures the committed argv fixture
through the in-image capture path, and pins the ordering invariant with a
structural assertion so a future SDK drift cannot silently re-invert it.

**Terminology note (dispatch-argument disambiguation):** the dispatch asks to
"move the sibling-tenant deny mounts before the workspace rw bind." Taken
literally — reordering per-sibling deny mounts while keeping per-sibling
enumeration — the residual TOCTOU would NOT close (a sibling created after
namespace build is never enumerated, so no mount order can deny it). The
ordering property that closes it is the issue's own Option C: the
**parent-deny `--tmpfs` precedes the workspace's surviving rw `--bind`**
(vendor re-bind after tmpfs). This plan implements the property, not the
literal token-move; the fixture-diff shape section below records what the
argv diff actually looks like under that reading (it is not token-order-only
— see "Expected fixture diff").

## Research Reconciliation — Spec vs. Codebase

| Spec/issue claim | Codebase reality (verified this session) | Plan response |
|---|---|---|
| "the SDK is pinned at `0.2.85`" (issue) | `@anthropic-ai/claude-agent-sdk@0.3.284` + `@anthropic-ai/claude-code@2.1.284`; the spawned binary is `node_modules/@anthropic-ai/claude-agent-sdk-linux-x64/claude` (bun-compiled ELF) | All ordering claims re-derived against 2.1.284's embedded builder, not the 0.2.85 one |
| "no `patch-package`, no `patchedDependencies`… landing a vendored patch needs its own review" (issue scope item 1) | Still true — no patch machinery exists — **but** the builder inside the vendored binary already does tmpfs-then-restore (`jV` emits `--tmpfs <landing>` then `--bind` rw restores for covered `allowWrite` paths; `readAllowPaths` get `--ro-bind` restores) | Cut the patch-mechanism prerequisite (Phase 0.6b Cut List); the reorder is vendored already |
| "the ONLY post-tmpfs re-bind the SDK offers (`allowRead`) is READ-ONLY" (ADR-075 context) | At 2.1.284 the builder re-binds **write** paths rw after the deny tmpfs — verified by reading the binary's embedded builder + its log strings | Broad `denyRead:["/workspaces"]` + `allowWrite:[ws]` becomes expressible |
| "Update the drift-guard + `agent-sandbox-sibling-deny.test.ts`" (issue scope) | Both exist (`agent-runner-helpers.test.ts` drift guard asserts the exact enumerated set; `agent-sandbox-sibling-deny.test.ts` pins `enumerateSiblingDenyPaths`) | Both rewritten against the new constant-deny contract |
| "the capture gate is now trustworthy — fixture fresh at 0.3.284, replay-precondition-safe" (dispatch) | Verified: fixture `status: captured`, `sdkVersion: 0.3.284`, canonical projection with replay preconditions (`prepDirs`); capture gate fires on `agent-runner-sandbox-config.ts` changes (`.github/workflows/ci.yml` `sandbox-canary-capture-gate`) | Re-capture via `SANDBOX_CANARY_MODE=capture` + `--verify` is a merge-blocking step |

## Problem Statement / Motivation

Per-sibling deny enumeration has three standing costs:

1. **TOCTOU (the residual):** a workspace created between a session's
   namespace build and that session's end is visible read-only. Bounded, but
   structurally unclosable by enumeration — you cannot enumerate a directory
   that does not exist yet.
2. **Dispatch-time `readdirSync` + fail-closed complexity:** every agent
   dispatch pays a directory read and carries a `degraded` arm whose failure
   posture (broad deny → read-only strand) is itself a strand-the-agent path.
3. **Telemetry honesty:** the `op:"sibling-deny"` log reports the *computed*
   deny set, not the *realized* mount state (ADR-075 Consequences — the
   intent-vs-effect gap).

The durable closer the ADR names is a deny ordering where the parent tmpfs
lands before the write re-bind. That ordering is now in the vendored binary;
what remains is the config flip and its verification.

## Proposed Solution

```ts
// apps/web-platform/server/agent-runner-sandbox-config.ts — target shape
filesystem: {
  allowWrite: opts?.readOnly ? [] : [workspacePath],
  // Broad parent deny: the vendored builder (CLI 2.1.284) emits
  // `--tmpfs /workspaces` and then re-binds each covered allowWrite/allowRead
  // path after it — writable-own AND future-sibling-safe, no enumeration.
  denyRead: [
    workspacesRoot(),
    c4StagingRoot,
    "/proc",
    ...(opts?.denyReadExtra ?? []),
  ],
  // readOnly persona (ADR-113 support): restore the workspace READ-ONLY
  // inside the masked parent — `allowRead` maps to the builder's
  // allowWithinDeny and re-binds `--ro-bind` after the tmpfs. Absent without
  // it the support session loses its workspace entirely under a broad deny.
  ...(opts?.readOnly ? { allowRead: [workspacePath] } : {}),
}
```

Concretely:

1. **Delete** `enumerateSiblingDenyPaths`, its `degraded`/`ENOENT` fail-closed
   arm, and the per-dispatch `readdirSync`. Under a constant deny list none of
   them exist. (`workspacesRoot()` stays — env-overridable for tests/capture.)
2. **Emit** `denyRead = [workspacesRoot(), c4StagingRoot, "/proc",
   ...denyReadExtra]` (deduped) and the readOnly `allowRead` restore arm.
3. **Re-capture** the argv fixture in-image (the gate fires on this file's
   diff — `agent-runner-sandbox-config.ts` is a declared capture input).
4. **Pin** the ordering invariant structurally in the canary unit suite.
5. **Amend** ADR-075: exit criterion met; status `accepted` (residual
   closed); record the vendored-builder mechanism + version pins.
6. **Sweep** stale per-sibling documentation (`cc-dispatcher.ts` comments at
   the credential-egress + workspace-read notes, `sandbox-canary.mjs`
   zero-sibling comments where they describe enumeration-era invariants).

### Expected fixture diff (correcting the dispatch hypothesis)

Not token-order-only. Under the broad deny the capture root becomes a deny
landing, so the committed fixture gains:

- `--tmpfs /tmp/soleur-sandbox-canary` — the hermetic capture root is a
  **deterministic literal** (`computeCanaryPaths` builds fixed paths under
  `/tmp` — `CANARY_ROOT_BASE`, `CANARY_WORKSPACE_UUID` are constants), so no
  new placeholder is needed; it lands in `literalPrepDirs` automatically.
- A restore `--bind ${CANARY_WS} ${CANARY_WS}` emitted **after** that tmpfs
  (the vendor's re-bind), in addition to the early `allowOnly` bind.
- `prepDirs` gains the literal capture root.

If the captured argv instead shows token-order-only (vendor moved the whole
deny block), that is also acceptable — the acceptance gate is the ordering
invariant + `verify_ok`, not a specific diff shape.

## Technical Considerations

- **bwrap mount semantics (verified ADR-075 EXP2 + fixture comments):** mounts
  apply left-to-right; a later mount shadows an earlier one at the same or a
  covering path. `--tmpfs /workspaces` masks the whole host tree; a subsequent
  `--bind /workspaces/<uuid>` re-exposes only own. A sibling created after the
  namespace build lives under the masked host dir — invisible, permanently.
  This is the structural TOCTOU close.
- **Vendor evidence:** `node_modules/@anthropic-ai/claude-agent-sdk-linux-x64/claude`
  embedded builder (`qV`/`jV`): `filesystem.denyRead` → `denyOnly` landings →
  `--tmpfs`, then restores `allowedWritePaths` (`--bind` rw, log:
  `Re-bound write path wiped by denyRead tmpfs:`) and `readAllowPaths`
  (`--ro-bind`, log: `Re-allowed read access within denied region`). Field
  mapping verified: `denyRead`→`denyOnly`, `allowWrite`→`allowOnly`,
  `allowRead`→`allowWithinDeny`, `denyWrite`→`denyWithinAllow`.
- **Non-existent deny paths:** the SDK skips them (`Skipping non-existent
  read deny path`), so a dev host with no `/workspaces` degrades to no-deny —
  the same posture today's benign-ENOENT arm produces, with less code.
- **readOnly persona:** support sessions pass `readOnly: true` and a
  `workspacePath` under `/workspaces`; without `allowRead` restore the broad
  deny would blind them. Unit-tested shape + binary-verified restore loop.
- **SDK-internal write-protection masks** (the `--ro-bind /dev/null <dotfile>`
  set): the capture audit must confirm they still land in a position that
  survives the workspace restore (see Risks — the mask-shadowing fork).
- **`enableWeakerNestedSandbox`, `credentials.envVars`, network allowlist:**
  untouched. The bwrap PATH shim's fd sweep + seccomp injection (#8752) are
  unchanged — the argv vocabulary is the same, only mount order/token set
  changes.
- **NFRs:** removes a `readdirSync` per dispatch (latency), removes a
  fail-closed strand mode (availability), hardens confidentiality
  (cross-tenant). Security > the other two.

### Attack Surface Enumeration

Every path that reaches the agent sandbox's filesystem boundary:

- `buildAgentSandboxConfig` — the single emit point; both consumers
  (`agent-runner-query-options.ts` legacy+cc paths via one helper) get the new
  shape automatically. drift-guarded.
- `denyReadExtra` (ADR-113 KB obscure) — merged unchanged.
- The bwrap PATH shim (`infra/bwrap-shim/bwrap`) — unchanged; it transports
  argv via `--args <fd>` without inspecting content, so a token-reorder is
  fully inside its contract.
- The runtime `createSandboxHook` realpath containment — covers file tools,
  never Bash; unchanged and still layered under bwrap.
- `test/helpers/sandbox-isolation-fixtures.ts` `spawnBwrap` — already models
  tmpfs-parent + re-bind ordering ("Matches the captured SDK argv at
  /workspaces") — the direct-bwrap isolation FRs exercise the target shape
  already.

## Research Insights

**Relevant file paths:**

- `apps/web-platform/server/agent-runner-sandbox-config.ts` — the config emit
  point (`enumerateSiblingDenyPaths`, `buildAgentSandboxConfig`, module header
  documenting the write-first/read-last ordering rationale).
- `apps/web-platform/scripts/sandbox-canary.mjs` — capture/projection/replay
  (`doCapture`, `normalizeCapturedArgv`, `computeCanaryPaths` — fixed paths,
  `prepDirs` rules, `SHIM_SOURCE`).
- `apps/web-platform/scripts/sandbox-canary-verify-in-image.sh` — in-image
  capture/verify driver (`SANDBOX_CANARY_MODE={verify,capture}`).
- `apps/web-platform/infra/sandbox-canary-argv.json` — committed fixture
  (`status: captured`, `sdkVersion: 0.3.284`, 112-token setup argv).
- `apps/web-platform/test/agent-runner-helpers.test.ts` — drift guard
  (exact-set `denyRead` assertion; `allowRead` absence pin).
- `apps/web-platform/test/agent-sandbox-sibling-deny.test.ts` — enumerator
  unit tests (symlink safety, fail-closed arm) — rewritten to the new
  contract.
- `apps/web-platform/test/sandbox-canary.test.ts` — projection tests +
  committed-fixture census (the ordering pin lands here).
- `apps/web-platform/test/sandbox-isolation.test.ts` +
  `helpers/sandbox-isolation-fixtures.ts` — direct-bwrap FRs already model
  `--tmpfs parent` + re-bind.
- `.github/workflows/ci.yml` `sandbox-canary-capture-gate` — capture-input
  trigger list already includes `server/agent-runner-sandbox-config.ts`.
- `knowledge-base/engineering/architecture/decisions/ADR-075-…md` — the ADR
  whose residual this closes.
- Test-compatibility audit (deepen §4, tunable-semantic sweep): every
  `denyRead` reference under `test/` was enumerated —
  `agent-runner-query-options.test.ts` (`toContain` on the KB deny path —
  compatible), `cc-dispatcher-real-factory.test.ts` /
  `cc-dispatcher-warm-presandbox-mkdir.test.ts` /
  `cc-dispatcher-prefill-guard.test.ts` (mock fixtures already carrying the
  broad `["/workspaces","/proc"]` shape — compatible, and evidence the shape
  is well-formed), `server/git-worktree-validity.test.ts` (comment only).
  Only `agent-runner-helpers.test.ts`, `agent-sandbox-sibling-deny.test.ts`,
  and `sandbox-canary.test.ts` pin the enumerated-set contract and need
  updates.

**Premise validation (Phase 0.6):** issue #5862 OPEN (`gh issue view` —
verified); every cited artifact exists on this branch (`agent-runner-sandbox-config.ts`,
`sandbox-canary.mjs`, the fixture, the sibling-deny test, ADR-075). One stale
premise: "SDK pinned at 0.2.85" — now 0.3.284 / CLI 2.1.284, and the newer
builder supplies the ordering the issue assumed needed a patch. The issue's
scope item 1 (patch mechanism) is thereby re-scoped, not silently dropped —
recorded below and in the ADR amendment.

**Property List (Phase 0.6b):**

| # | Property (observable outcome) | Mechanism that buys it |
|---|---|---|
| P1 | A sibling workspace created after a session's namespace build is never readable inside it | Parent-root `denyRead` tmpfs — masks the whole tree at namespace build |
| P2 | The agent keeps read+write of its own `/workspaces/<uuid>` | Vendor restore: `--bind` rw re-emitted after the covering tmpfs |
| P3 | readOnly (support) sessions keep read-only workspace access | `allowRead:[workspacePath]` → allowWithinDeny `--ro-bind` restore |
| P4 | No dispatch-time filesystem enumeration | Constant deny list; `enumerateSiblingDenyPaths` deleted |
| P5 | The committed argv fixture reflects the new ordering and CI byte-verifies it | `SANDBOX_CANARY_MODE=capture` + `--verify` (existing gate) |
| P6 | A future SDK that re-inverts the ordering fails loudly before merge | New structural ordering pin on the committed fixture |

**Cut List (Phase 0.6b):**

- *Dependency-patch mechanism (patch-package / vendored binary patch)* — buys
  the deny-then-restore ordering; the vendored 2.1.284 binary already provides
  it (`jV` restore branch, quoted above). Cut contingent on the Phase-3 capture
  audit proving the emitted order; if the audit falsifies it, the mechanism is
  un-cut and re-scoped (see Dependencies & Risks).
- *Per-sibling enumeration (`enumerateSiblingDenyPaths`, `degraded` arm,
  sibling-census tests)* — P1 makes it dead code: the parent tmpfs covers the
  enumerated set and the future set identically.
- *bwrap-shim argv rewriting* — possible fallback layer but duplicates what
  the vendor emits; rejected unless the capture audit fails (contingency, not
  a plan item).

**External research decision (Phase 1.6):** skipped. The change is bounded by
repo-internal mechanisms (config shape, capture gate, ADR), the bwrap ordering
semantics are already measured in-repo (ADR-075 EXP2, bwrap 0.11.1), and the
SDK-side evidence is the installed binary itself — the most authoritative
source available. High-risk-domain caution is already satisfied by the
empirical capture-audit gate rather than by web research.

**Community discovery (1.5) / functional overlap (1.5b):** skipped. Stack is
TypeScript/bash (covered); no community artifact plausibly overlaps a
repo-specific SDK-argv-ordering fix. (No Task spawn capability in this
harness — sequential-fallback note applies.)

**Related learnings applied:**

- `learnings/2026-04-15-gh-jq-does-not-forward-arg-to-jq.md` — overlap check
  uses standalone `jq --arg`.
- ADR-079 / #4932 — the fixture is never hand-edited; capture-emitted bytes
  only.
- `learnings/2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md`
  — the ordering pin ships with a mutation matrix (Guard Contract).
- `learnings/best-practices/2026-07-01-blind-surface-needs-structured-probe-before-nth-fix.md`
  — the affected surface is the agent sandbox (blind to host-side gates);
  observability failure modes name in-surface probes (canary replay verdicts,
  in-sandbox probes).

## Implementation Phases

### Phase 1 — Failing tests (contract first, `cq-write-failing-tests-before`)

1. `test/agent-runner-helpers.test.ts`: rewrite the drift-guard's
   filesystem assertions — `denyRead` is exactly `[workspacesRoot(),
   c4StagingRoot, "/proc"]` (+ `denyReadExtra` when passed), **independent of
   sibling dirs present**; `allowWrite=[own]`; `allowRead` absent when not
   readOnly, `[own]` when readOnly. (RED — current code enumerates siblings.)
2. `test/agent-sandbox-sibling-deny.test.ts` → rename to
   `test/agent-sandbox-tenant-deny.test.ts` and rewrite: the deny set is the
   parent root (not per-sibling); a newly created sibling dir does NOT appear
   in `denyRead` yet is still covered (assert via membership of the parent —
   the structural cover); `enumerateSiblingDenyPaths` no longer exported.
   Keep the symlink-canonicalization scenario only insofar as
   `workspacePath`'s own placement under the root matters.
3. `test/sandbox-canary.test.ts`: new committed-fixture ordering pin —
   *every `--tmpfs` token whose target is an ancestor-or-equal of
   `${CANARY_WS}` precedes at least one `--bind … ${CANARY_WS}`* (see Guard
   Contract). Update the committed-fixture census row to expect the new
   literal root tmpfs + prepDirs membership. (RED until Phase 3 re-capture.)
4. `test/sandbox-isolation.test.ts` (+ fixtures): add the TOCTOU regression
   case — spawn sandboxed `ls <parent>` (or cat probe), create a sibling dir
   on the host **while the sandboxed process lives**, re-probe inside → the
   new sibling is absent. `spawnBwrap` already emits the tmpfs+re-bind shape;
   the case pins the semantics the vendored ordering must satisfy.

### Phase 2 — Config rewrite

`server/agent-runner-sandbox-config.ts`:

- `denyRead: [workspacesRoot(), c4StagingRoot, "/proc", ...denyReadExtra]`
  (deduped via the existing `Set` spread).
- `allowWrite` unchanged (`[]` when `readOnly`); `allowRead: [workspacePath]`
  only when `readOnly`.
- Delete `enumerateSiblingDenyPaths`, `safeRealpath` (if orphaned),
  `degraded` computation, and the `reportSilentFallback` enumeration arm.
- Structured log: rename `op:"sibling-deny"` → `op:"tenant-deny"` (the old op
  name describes deleted machinery; prior `sibling-deny` events stay queryable
  in the log store), keep `feature:"agent-sandbox"`, `workspacesRoot`,
  `workspace`, `deniedCount`, `c4StagingRootReady`; drop `degraded`.
- Rewrite the module header: the write-first/read-last constraint + the
  per-sibling workaround are gone; document the deny-then-restore contract
  this config now depends on (and that the fixture ordering pin guards).

Doc sweep (comment-only edits, no behavior): `cc-dispatcher.ts` comments at
the egress-token note (~line 225) and the workspace-read note (~lines
2045–2046, 2620–2622) that describe per-sibling deny; `sandbox-canary.mjs`
zero-sibling comments (~lines 518, 1127–1139) that describe the
enumeration-era invariant.

### Phase 3 — In-image re-capture + audit (merge-blocker)

1. `ANTHROPIC_API_KEY="$(doppler secrets get ANTHROPIC_API_KEY --project
   soleur --config ci --plain)" SANDBOX_CANARY_MODE=capture bash
   apps/web-platform/scripts/sandbox-canary-verify-in-image.sh` → fixture
   rewritten through `/out`.
2. **Audit the diff before accepting** — never hand-edit (#4932 trap):
   - `--tmpfs /tmp/soleur-sandbox-canary` present;
   - at least one `--bind ${CANARY_WS} ${CANARY_WS}` after it (the restore);
   - **every** ws-internal mount from the prior fixture still lands in a
     position that survives the workspace restore bind — that means the
     `/dev/null` file-mask set AND the `${CANARY_WS}/.claude` /
     `${CANARY_WS}/.claude/.cc-writes` ro self-binds. Any pre-tmpfs ws-internal
     mount emitted only before the covering tmpfs is shadowed by the restore
     `--bind` (e.g., a ro-pinned `.claude` would silently become writable
     inside the sandbox). Each must be re-emitted post-restore or confirmed
     intentionally shadowed — STOP → contingency below;
   - `prepDirs` includes the literal root;
   - `droppedForDeterminism` changes are audit-only.
3. `SANDBOX_CANARY_MODE=verify` → `{"verdict":"verify_ok","reason":"ok"}`.

**Contingency (only if the audit falsifies the premise):** if the vendored
builder does not produce deny-then-restore for this config (e.g., it skips the
restore, or file-masks inside the workspace get wiped by the restore bind and
cannot be re-expressed), do NOT ship a broken isolation shape. Re-scope: the
fallback is argv rewriting at `infra/bwrap-shim/bwrap` (read the `--args` fd
payload, reorder mount ops, re-emit on a fresh fd) — a materially different
diff requiring plan revision and re-review, not an inline improvisation.

### Phase 4 — ADR-075 amendment + docs

Append a dated amendment to
`knowledge-base/engineering/architecture/decisions/ADR-075-agent-sandbox-tenant-read-isolation.md`:
exit criterion met at SDK 0.3.284 / CLI 2.1.284 via the vendored
deny-then-restore builder; per-sibling enumeration removed; status →
`accepted` (drop `accepted-with-residual`); record that the re-evaluate-when
trigger fired (dependency-patch infrastructure became unnecessary, not merely
introduced).

### Phase 5 — Full green + gate self-proof

- `cd apps/web-platform && npx vitest run test/agent-runner-helpers.test.ts
  test/agent-sandbox-tenant-deny.test.ts test/sandbox-canary.test.ts
  test/sandbox-isolation.test.ts` (isolation suite honors its own skip gates).
- On the PR, `sandbox-canary-capture-gate` reaches `canary --verify OK`
  without an `sdk-bump-verified:` trailer (no dependency bump occurs here —
  the lockfile is untouched).

## Files to Edit

- `apps/web-platform/server/agent-runner-sandbox-config.ts` — config rewrite
  (deny list, readOnly `allowRead` arm, delete enumerator, log op rename,
  module header).
- `apps/web-platform/server/cc-dispatcher.ts` — comment sweep only
  (per-sibling references, ~lines 225, 2045–2046, 2620–2622).
- `apps/web-platform/scripts/sandbox-canary.mjs` — comment sweep only
  (zero-sibling/enumeration-era comments; no projection change expected — the
  capture root is a deterministic literal).
- `apps/web-platform/test/agent-runner-helpers.test.ts` — drift-guard rewrite.
- `apps/web-platform/test/agent-sandbox-sibling-deny.test.ts` → renamed
  `test/agent-sandbox-tenant-deny.test.ts` — rewritten to the constant-deny
  contract.
- `apps/web-platform/test/sandbox-canary.test.ts` — ordering pin + census
  updates.
- `apps/web-platform/test/sandbox-isolation.test.ts` — TOCTOU regression case
  (+ fixture helper if a hook point is needed).
- `apps/web-platform/infra/sandbox-canary-argv.json` — regenerated via
  in-image capture only.
- `knowledge-base/engineering/architecture/decisions/ADR-075-agent-sandbox-tenant-read-isolation.md`
  — amendment + status flip.

## Files to Create

- None. (`test/agent-sandbox-tenant-deny.test.ts` is a rename, not a new file.)

## Alternative Approaches Considered

| Approach | Verdict | Reason |
|---|---|---|
| Vendor/patch the SDK builder (patch-package, binary patch) | Unnecessary | The vendored 2.1.284 binary already emits deny-then-restore; patch machinery adds supply-chain + per-bump surface for a property already bought (issue's own scope item 1 — cut, pending Phase-3 audit) |
| Keep per-sibling enumeration + reorder mounts (literal dispatch reading) | Rejected | Cannot close the TOCTOU — an unenumerated sibling has no mount to reorder; only a parent-level deny covers future siblings |
| bwrap-shim argv rewrite (read `--args` payload, reorder, re-emit) | Contingency only | Achievable (the shim is the established interception point, #8752) but duplicates vendor behavior and adds fd-juggling complexity; reserved for the audit-failure fork |
| Per-tenant volume/container isolation (ADR-075 Option B) | Out of scope | Unbuilt infra; tracked separately at #5863 — this plan closes the residual, B remains the end-state |
| Add `/sys` to denyRead while here (#1285) | Defer | One-line change mechanically, but it is a separate hardening decision with its own blast radius (tools reading /sys); note filed under Open Code-Review Overlap |
| Upstream `allowReadWriteWithinDeny` option request | Out of scope | Not needed — the vendor's own restore semantics already express the ordering |

## User-Brand Impact

- **If this lands broken, the user experiences:** agent sessions fail to
  write their own workspace (`read-only file system`/`not a git repository`
  strands — the #5848 shape) or, worse, a tenant's agent session reads another
  tenant's workspace files via Bash with no tool-layer guard covering it.
- **If this leaks, the user's data is exposed via:** a sibling workspace made
  visible inside another tenant's sandbox — the exact class ADR-075 exists to
  prevent; the unit of harm is one tenant's repo/secrets read by another
  tenant's agent.
- **Brand-survival threshold:** `single-user incident` — one tenant's secret
  readable by another tenant's agent session is a breach the brand cannot
  absorb (same tier as the #8752 sibling-hardening plan's precedent).
- **Threshold decision (challengeable):** cross-tenant isolation's unit of
  harm is a single leaked workspace — it is not an aggregate-pattern property.

CPO sign-off is required at plan time before `soleur:work` begins
(frontmatter `requires_cpo_signoff: true`). At review time
`soleur:engineering:review:user-impact-reviewer` enumerates failure modes
against the diff (review-skill conditional agent; headless note for the
pipeline).

**GDPR gate (Phase 2.7, fired via trigger (b) — threshold `single-user
incident`; inline advisory, Task spawn unavailable in this harness):** no new
processing of personal data. The change REMOVES a per-dispatch directory
enumeration (fewer tenant identifiers read) and keeps the same log fields
(`workspacesRoot`, own-workspace basename, counts). No new sink, no new
payload, no Art. 9 category, no Art. 30 trigger. The committed argv fixture
carries only fixed canary paths — no tenant data.

## Observability

```yaml
liveness_signal:
  what: "per-dispatch structured log `feature=agent-sandbox op=tenant-deny` (denied set size + staging-root readiness) + faithful sandbox-canary replay verdict at each deploy"
  cadence: "per agent dispatch / per deploy"
  alert_target: "Sentry (silent-fallback mirror) + deploy pipeline gate (canary verdict)"
  configured_in: "apps/web-platform/server/agent-runner-sandbox-config.ts; apps/web-platform/infra/ci-deploy.sh (canary replay call site)"

error_reporting:
  destination: "Sentry web-platform project (SENTRY_DSN) — reportSilentFallback on c4-staging mkdir failure; canary FAIL fires a Sentry event per ADR-079"
  fail_loud: "log line `agent-sandbox: computed … denyRead` with unexpected deniedCount; canary verdict `sandbox_broken`/`canary_infra_error`; `bwrap-shim:` stderr markers on shim refusal"

failure_modes:
  - mode: "SDK bump re-inverts mount ordering (deny lands after the write bind with no restore)"
    detection: "in-surface: committed-fixture ordering pin (test/sandbox-canary.test.ts) reddens + capture gate byte-diffs the argv on any capture-input change; deploy canary replay EPERMs if the namespace can't be built"
    alert_route: "PR blocking (CI gate) + Sentry canary event"
  - mode: "own workspace rendered read-only (the #5848 regression shape)"
    detection: "in-surface: agent session write failure on `.git`/workspace write surfaces the session error + `sdk-startup` telemetry; the ordering pin on the fixture catches the static shape pre-merge"
    alert_route: "CI (pin + capture gate); runtime session error → Sentry"
  - mode: "broad deny silently skipped (workspaces root absent on host — dev/CI)"
    detection: "in-surface: `op=tenant-deny` log carries the emitted deny set; fixture census asserts the root tmpfs present"
    alert_route: "CI; log query on `op=tenant-deny`"
  - mode: "support (readOnly) persona loses workspace read access under the masked parent"
    detection: "unit pin on `allowRead:[workspacePath]` when readOnly + binary-verified allowWithinDeny restore; `sandbox-credential-deny-runtime`-class runtime suites exercise the shape"
    alert_route: "CI"
  - mode: "SDK-internal dotfile masks (`--ro-bind /dev/null <file>`) shadowed by the workspace restore bind"
    detection: "in-surface: Phase-3 capture audit compares mask-set presence AND position vs the ws restore bind; fixture census"
    alert_route: "merge-blocker at capture audit; CI on the fixture pin"

logs:
  where: "web-platform docker logs (stdout JSON) → Better Stack; canary verdict → deploy-state + Sentry"
  retention: "existing platform retention (Better Stack); Sentry per project settings"

discoverability_test:
  command: "python3 -c \"import json;a=json.load(open('apps/web-platform/infra/sandbox-canary-argv.json'))['bwrapSetupArgv'];t=[i for i,x in enumerate(a) if x=='--tmpfs'];b=[i for i,x in enumerate(a) if x=='--bind'];print('deny-before-restore' if t and b and max(b)>min(t) else 'check-failed')\""
  expected_output: "deny-before-restore"
```

## Architecture Decision (ADR/C4)

### ADR

Amend `ADR-075-agent-sandbox-tenant-read-isolation.md` **in this PR** (the
exit criterion is the ADR's own — `wg-architecture-decision-is-a-plan-deliverable`):
record that Option C shipped via the vendored builder's deny-then-restore
ordering (no patch machinery — the SDK bump itself delivered the reorder),
per-sibling enumeration removed, status `accepted-with-residual` →
`accepted`, and the residual-undetectability consequence retires with it (the
committed-fixture ordering pin + capture gate now cover the intent-vs-effect
gap the ADR flagged). No new ADR — this is a recorded extension of an existing
decision, not a new boundary.

Status-flip sweep (sharp edge — a flipped record must sweep the legal
registers for the mechanism's nouns): `git grep` over `knowledge-base/legal/`
for `sibling`, `denyRead`, `tenant-read-isolation`, `tenant isolation` finds no
claim about this mechanism — the residual was never disclosed in legal
surfaces, so the status flip carries no legal-record tail. Recorded here so
the sweep is auditable, not asserted.

### C4 views

No C4 impact. Enumeration checked against all three model files
(`model.c4`, `views.c4`, `spec.c4`):

- **External human actors:** none new — the sandbox boundary sits between
  already-modeled workspace-owning users; no actor added or re-scoped.
- **External systems/vendors:** none new — bwrap is an in-container OS
  mechanism, not an external system; `@anthropic-ai/claude-agent-sdk` remains
  a library dep of the same container, not a modeled node.
- **Containers/data-stores:** unchanged — `platform.infra.workspacesVolume`
  already models the shared `/workspaces` mount; this changes mount *order*
  inside an existing namespace, not topology.
- **Actor↔surface relationships:** unchanged — no edge added, moved, or
  re-scoped; the tenant-read-isolation property is internal to the existing
  webapp container element.

## Guard Contract

The deliverable includes one new guard: the committed-fixture ordering pin.

### Guard 1 — deny-before-restore ordering pin (`test/sandbox-canary.test.ts`)

**Property.** In the committed fixture's `bwrapSetupArgv`, every `--tmpfs`
whose target is an ancestor-or-equal of the workspace mount destination must
be followed by at least one rw `--bind` of that workspace destination (the
deny can never be the last word on the agent's own workspace — and its absence
entirely is equally fatal).

**Assembly.** Every captured SETUP argv token produced by
`buildAgentSandboxConfig` → vendored SDK builder → `normalizeCapturedArgv` —
the committed fixture is the single chokepoint the property quantifies over
(the capture gate byte-diffs it on every capture-input change, so a drift that
reorders mounts lands here first). One chokepoint only; `--args`-fd transport
in the shim is argv-transparent by construction.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Move the covering `--tmpfs <root>` token after the last `--bind ${CANARY_WS} ${CANARY_WS}` | RED — deny shadows the write bind |
| 2 | Delete every `--bind ${CANARY_WS} ${CANARY_WS}` that follows the covering tmpfs (keep the early ones) | RED — restore missing while deny present (the "property holds implies restore" row: deny satisfied, restore absent) |
| 3 | Guard-dispatch vacuity: run the assertion against an argv with NO covering tmpfs at all | RED — a fixture missing the deny landing must fail, not vacuously pass |
| 4 | Add a SECOND covering-class deny (`--tmpfs` on another ancestor of the ws dst) after the last ws bind | RED — the check quantifies over every covering deny, not the first |
| 5 | Harness row: append a NON-covering `--tmpfs` (e.g. `/proc`-class path unrelated to the ws) after the last ws bind | PASS — ordering of unrelated denies is unconstrained; proves the guard does not reject everything |

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed (inline — no Task spawn in this harness;
`Reviewed-Coverage: sequential-fallback` per the sibling-run convention)

**Assessment:** Security-boundary change to the agent sandbox's bwrap config.
The architectural judgement the change needs (deny ordering semantics,
fail-closed posture, blind-surface observability) is carried by the plan's
Research Insights, the binary-level vendor evidence, and the ADR amendment.

### Product/UX Gate

Mechanical UI-surface scan of Files to Edit/Create against
`plugins/soleur/skills/brainstorm/references/ui-surface-terms.md` glob
superset: `server/*.ts`, `test/*.ts`, `scripts/*.mjs`, `infra/*.json`,
`knowledge-base/**` — **no matches**. Tier: NONE. Skipped.

Other domains (Marketing, Operations, Product, Legal, Sales, Finance,
Support): no cross-domain implications detected — infrastructure/security
change. Legal note: no new public-facing isolation claim is made by this
change; existing security posture statements are strengthened, not invented.

## Open Code-Review Overlap

None. 88 open `code-review` issues queried; no issue body references any
planned file path.

Adjacent (non-code-review) issues for awareness:

- **#5863** (per-tenant volume/container isolation, ADR-075 Option B) —
  acknowledge: the end-state architecture; this PR closes the TOCTOU residual
  and does not subsume B.
- **#1285** (sec: add `/sys` to sandbox denyRead) — defer: becomes a one-line
  change on the new constant deny list, but is a separate hardening decision
  (tools may legitimately read `/sys`); re-evaluate after this lands.
- **#7043** (canary-verify failure should redden the sdk-bump gate) —
  acknowledge: gate-hardening concern, out of scope; this plan relies on the
  gate as-is (in-image re-capture is merge-blocking for this diff either way).

## Non-Goals / Out of Scope

- No dependency-patch machinery (patch-package, vendored binary patching,
  bunfs surgery) — deliberately cut; the vendored builder supplies the
  ordering.
- No bwrap-shim argv rewriting (contingency only).
- No SDK or CLI version bump — the fix runs on the currently pinned
  `0.3.284`/`2.1.284`.
- No per-tenant containerization (#5863).
- No upstream contribution of the ordering (the vendor already implements it).
- No changes to `credentials.envVars`, network allowlists, or the shim's
  fd/seccomp layer.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Introduce a dependency-patch mechanism (`patch-package` or equivalent) — this is the load-bearing prerequisite" [issue #5862] | — | descoped — justification: the vendored CLI 2.1.284 binary already emits deny-then-restore (`jV` restore branch); the prerequisite exists to create a property the vendor now provides; verified via Phase-3 capture audit (contingency documented if falsified) |
| 2 | "Patch the SDK bwrap builder so an `allowWrite` path within a `denyRead` region is re-bound **read-write after** the deny `--tmpfs` (EXP2 ordering), OR add an upstream/vendor `allowReadWriteWithinDeny`-style option" [issue #5862] | Phase 2 config revert + Phase 3 capture audit (the vendored builder IS the patched surface) | mapped |
| 3 | "Revert `agent-runner-sandbox-config.ts` to the simpler broad `denyRead:[\"/workspaces\"]` + `allowWrite:[workspacePath]` … dropping the per-sibling enumeration + its `readdirSync`-per-dispatch cost" [issue #5862] | Phase 2 (`denyRead:[workspacesRoot(), c4StagingRoot, "/proc", …]`, enumerator deleted) | mapped |
| 4 | "Update the drift-guard + `agent-sandbox-sibling-deny.test.ts`" [issue #5862] | Phase 1 items 1–2 | mapped |
| 5 | "move the sibling-tenant deny mounts before the workspace rw bind so sibling paths are bound (and denied) before the workspace that could shadow them" [dispatch args] | Phases 2–3 — realized as parent-deny tmpfs before the workspace's surviving rw bind (the only ordering that closes the TOCTOU; literal per-sibling mount move would not) | mapped |
| 6 | "re-capture via SANDBOX_CANARY_MODE=capture + verify-in-image" [dispatch args] | Phase 3 | mapped |
| 7 | "confirm the structural prepDirs test still holds on the reordered argv" [dispatch args] | Phase 1 item 3 + Phase 3 audit | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `agent-runner-sandbox-config.ts` rewrite | "Revert `agent-runner-sandbox-config.ts` to the simpler broad `denyRead`" | asked |
| `agent-runner-helpers.test.ts` drift-guard rewrite | "Update the drift-guard" | asked |
| `agent-sandbox-sibling-deny.test.ts` → tenant-deny rewrite | "`agent-sandbox-sibling-deny.test.ts`" | asked |
| `sandbox-canary-argv.json` re-capture | "re-capture via SANDBOX_CANARY_MODE=capture + verify-in-image" | asked |
| `sandbox-canary.test.ts` ordering pin + census | "confirm the structural prepDirs test still holds on the reordered argv" | asked |
| `sandbox-isolation.test.ts` TOCTOU regression case | — | inferred — justification: the exit criterion is the post-build-sibling property; without an executable pin the close is asserted, not demonstrated |
| readOnly `allowRead` restore arm | — | inferred — justification: broad deny without it blinds the ADR-113 support persona (safety regression) |
| ADR-075 amendment | — | inferred — justification: `wg-architecture-decision-is-a-plan-deliverable`; the exit criterion is the ADR's own |
| Comment sweeps (`cc-dispatcher.ts`, `sandbox-canary.mjs`) | — | inferred — justification: stale per-sibling rationale would mis-document the new contract (the config module header is rewritten for the same reason) |

### Split Assessment

- Subsystems touched: 2 — `apps/web-platform`, `knowledge-base`
- Planned files: 9 | Estimated changed lines: ~350 (mostly comment/test rewrites; the functional diff is ~30 lines)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] AC1: `buildAgentSandboxConfig` emits `filesystem.denyRead` equal to
  `[workspacesRoot(), c4StagingRoot, "/proc"]` (+ `denyReadExtra` when
  provided), **independent of sibling directories present** — a test that
  creates sibling dirs under a stubbed `WORKSPACES_ROOT` asserts they do not
  appear as individual `denyRead` entries.
- [ ] AC2: `enumerateSiblingDenyPaths` and its `degraded` arm are deleted; no
  `readdirSync` remains in the dispatch path
  (`grep -n readdirSync apps/web-platform/server/agent-runner-sandbox-config.ts`
  returns nothing).
- [ ] AC3: `readOnly` configs emit `allowWrite: []` + `allowRead:
  [workspacePath]`; non-readOnly configs carry no `allowRead` key.
- [ ] AC4: the committed fixture is regenerated via
  `SANDBOX_CANARY_MODE=capture` in-image (capture-emitted bytes only — never
  hand-edited), and `SANDBOX_CANARY_MODE=verify` returns
  `{"verdict":"verify_ok"}`.
- [ ] AC5: the committed fixture's `bwrapSetupArgv` satisfies the ordering
  pin — a `--tmpfs` covering `${CANARY_WS}`'s parent exists AND at least one
  rw `--bind` of `${CANARY_WS}` follows it — asserted by the new structural
  test in `test/sandbox-canary.test.ts`.
- [ ] AC6: `prepDirs` structural tests pass on the reordered argv, including
  the literal capture-root prepDir (the covering tmpfs target must pre-exist
  at replay).
- [ ] AC7: `sandbox-isolation.test.ts` carries a TOCTOU regression case — a
  sibling created on the host *after* the sandboxed spawn is not readable
  inside it (direct-bwrap layer; honors the suite's existing skip gates).
- [ ] AC8: ADR-075 amendment committed: exit criterion recorded as met,
  `accepted-with-residual` → `accepted`, mechanism + version pins cited.
- [ ] AC9: all touched vitest files green
  (`cd apps/web-platform && npx vitest run …`).
- [ ] AC10: on the PR, `sandbox-canary-capture-gate` reaches
  `canary --verify OK` without an `sdk-bump-verified:` trailer (no dependency
  bump — lockfile untouched).

## Test Scenarios

- Given sibling dirs exist under `WORKSPACES_ROOT`, when
  `buildAgentSandboxConfig(own)` is called, then `denyRead` contains the root
  and no sibling paths (unit).
- Given the support (`readOnly`) mode, when the config is built, then
  `allowWrite` is empty and `allowRead` restores the workspace (unit).
- Given a sandboxed process, when a sibling workspace is created on the host
  mid-session, then `cat`/`ls` of it inside the sandbox fails (regression).
- Given the committed fixture, when the ordering pin runs, then every covering
  `--tmpfs` precedes a `--bind` restore of the workspace (structural).
- Given the mutated fixtures in the Guard Contract matrix, when each is run
  through the ordering pin, then rows 1–4 are RED and row 5 passes.
- Given the in-image capture, when `--verify` diffs the fixture, then the
  verdict is `verify_ok` and the diff is capture-emitted only.

## Success Metrics

- `deniedCount` in the `op=tenant-deny` log becomes constant (3 + extras) —
  the enumeration cost and variance are gone.
- `sandbox-canary-capture-gate` green on this PR without a bump-ack trailer.
- ADR-075 no longer carries `accepted-with-residual`.
- Zero new Sentry `agent-sandbox` silent-fallback events attributable to
  workspace enumeration post-deploy.

## Dependencies & Risks

- **Vendor-ordering premise falsified at capture** (the real risk): if the
  2.1.284 binary does not emit the restore for this config shape, or emits
  file-masks in an order the restore wipes, the diff stalls at the Phase-3
  audit — the contingency (shim argv rewrite) is a materially different
  change requiring re-planning, not inline improvisation. Mitigation: the
  binary evidence is direct (the `jV` restore branch was read this session),
  and `spawnBwrap`'s fixture comment says the same ordering was captured from
  the SDK previously.
- **readOnly restore semantics** — `allowRead` → `allowWithinDeny` restore is
  binary-evidenced and unit-pinned, but the capture path exercises only the
  non-readOnly config; residual risk lives in the support arm until an SDK
  probe or runtime suite covers it (flagged in Test Scenarios).
- **Non-existent `/workspaces` on hosts without the volume** — SDK skips the
  deny path; identical posture to today's benign-ENOENT arm.
- **Config-shape drift in other consumers** — both factories share the helper;
  the drift guard pins the new shape.
- **Sharp Edges entry (per Phase 2.6 step 4):** a plan whose `## User-Brand
  Impact` section is empty or omits the threshold fails deepen-plan Phase 4.6
  — filled above; `requires_cpo_signoff` set.
- **Sharp Edges:** (a) the fixture must never be hand-edited (#4932);
  (b) the ordering pin must assert on *covering* tmpfs landings only —
  asserting "all tmpfs before all binds" would false-fail on legitimately
  unconstrained denies; (c) renaming the log `op` keeps prior `sibling-deny`
  events queryable but splits the series — dashboards/alerts on the old op
  name need awareness (none found — `grep` sentry/tf for `sibling-deny`
  returns no alert definitions); (d) `denyRead` on a missing path is silently
  skipped by the SDK — prod `/workspaces` exists (volume bind in
  `ci-deploy.sh`), but a prod arm where the mount is absent degrades to
  no-deny; the `op=tenant-deny` log is the detection surface.

## References & Research

- Issue: #5862 (OPEN). ADR: `knowledge-base/engineering/architecture/decisions/ADR-075-agent-sandbox-tenant-read-isolation.md`
  (exit criterion = Option C) and `ADR-079-faithful-sandbox-canary-and-profile-redeploy-verification.md`
  (capture/verify contract). ADR-113 (support persona), ADR-272 (credential
  env deny), ADR-068 (workspaces volume).
- Emit point: `apps/web-platform/server/agent-runner-sandbox-config.ts` —
  `buildAgentSandboxConfig`, `enumerateSiblingDenyPaths`, module header.
- Vendored builder evidence:
  `node_modules/@anthropic-ai/claude-agent-sdk-linux-x64/claude` embedded JS —
  `jV`/`qV` (`--tmpfs <landing>` then `--bind`/`--ro-bind` restores; logs
  `Re-bound write path wiped by denyRead tmpfs` / `Re-allowed read access
  within denied region`); field mapping `denyRead`→`denyOnly`,
  `allowWrite`→`allowOnly`, `allowRead`→`allowWithinDeny`.
- Capture path: `apps/web-platform/scripts/sandbox-canary.mjs` (`doCapture`,
  `computeCanaryPaths` — deterministic `/tmp/soleur-sandbox-canary/<uuid>`),
  `apps/web-platform/scripts/sandbox-canary-verify-in-image.sh`
  (`SANDBOX_CANARY_MODE`), `.github/workflows/ci.yml`
  `sandbox-canary-capture-gate` trigger list (already includes the config
  file).
- Sibling landed work: #8752/#9595 (bwrap PATH shim + shared seccomp),
  #9614/#9618/#9636 (capture projection placeholders + fresh fixture),
  #5913/#5928 (first in-image capture), #5864 (per-sibling deny).
- Related: #5863 (Option B end-state), #1285 (`/sys` deny — deferred),
  #7043 (gate hardening — acknowledged).
- Session precedent: `knowledge-base/project/specs/feat-one-shot-9614-9618-canary-capture-fixture/`
  (same capture/verify workflow this plan reuses).
