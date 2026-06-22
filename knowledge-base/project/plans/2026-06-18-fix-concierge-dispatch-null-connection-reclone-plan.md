---
date: 2026-06-18
type: fix
status: draft
branch: feat-one-shot-concierge-dispatch-null-connection-reclone
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
adr_refs: [ADR-044, ADR-038, ADR-029]
related_pr: 5546
---

# 🐛 fix: Concierge dispatch silently spawns a repo-less agent when a genuinely-connected shared workspace resolves a null install/repoUrl

## Enhancement Summary

**Deepened on:** 2026-06-18
**Sections enhanced:** design crux, ADR amendment, Phase 2/3, Acceptance Criteria, Test Scenarios, Sharp Edges, Research Reconciliation
**Research agents used:** verify-the-negative (security claims), precedent-diff (seam/op/alert shapes), architecture-strategist (ADR-044 invariants), repo-research-analyst, learnings-researcher

### Key Improvements
1. **P0 design correction (architecture-strategist):** the divergence helper must NOT persist
   `repo_status=error` (the original "mirror `failHonestly`" plan). `failHonestly` persists because
   it observed a real failed clone; the divergence path attempted no clone — persisting `error` on
   the shared `workspaces` row would corrupt a healthy team workspace for its Owners and convert a
   transient RPC blip into a sticky failure. Helper now performs **zero `workspaces` writes**; the
   Sentry op is the only durable record. New AC1b + tightened T1/T5 enforce this.
2. **Precedent-pinned infra:** `frequency = 20` (verified free), exact
   `-target=sentry_issue_alert.repo_resolver_divergence` line for `apply-sentry-infra.yml`, and the
   destroy-guard confirmed to need NO sweep for an addition.
3. **Emit-site distinctness:** clarified the new dispatch-time op is distinct from the existing
   catch-block `self-heal-failed` emit at `cc-dispatcher.ts:1843` (no double-fire).
4. **CTA copy:** membership-deny-aware message replaces the unactionable "reconnect" CTA.
5. **Verify-the-negative:** all 5 security claims (RPC credential gate, no service-role, no
   migration, sanitized `extra`, untouched fast path) confirmed against code.

### New Considerations Discovered
- The two-read asymmetry (RPC credential read vs RLS non-credential read) is the deep cause; the fix
  must disambiguate at the **caller** via `repoUrl`, never by widening the credential RPC (ADR-044).
- Storm-bounding is Sentry-side (frequency throttle + issue grouping), NOT the process-local dedupe
  `Set`.

## Overview

A Concierge dispatch into a `repo_status='ready'` **shared/team** workspace whose physical `.git`
is gone spawns the agent into a workspace with **no git repository**. The `/soleur:go` Step 0.0
readiness probe then reports "no git repository" (`git rev-parse` exit 128), and the state
**persists across reconnects**. The same-day PR **#5546** ("repo-scope non-push founder resolver +
deterministic re-clone for ready-but-`.git`-gone shared workspaces", merged 2026-06-18) added the
ready-but-`.git`-absent graft but **did not close this** for the reporting user.

**Root cause (verified, see Premise Validation below).** The agent **was** spawned (it ran the
Step 0.0 probe and flailed), which proves the server-side dispatch gate
`resolveRepoReadinessWithSelfHeal` (`apps/web-platform/server/repo-readiness-self-heal.ts`, called
from `cc-dispatcher.ts:1795`) returned `{ ok:true }` **without the clone running** — had the graft
run and failed, the dispatch would have thrown `RepoNotReadyError` and shown "Repository setup
failed: … Reconnect" instead of a running agent.

The gap is the **FAST PATH** at `repo-readiness-self-heal.ts:134-140`: when `decision.ok` is true
it returns `decision` **without grafting** whenever `hasConnection` is false, where
`hasConnection = args.installationId !== null && !!args.repoUrl` (`:128`). So a
`repo_status='ready'`-but-`.git`-absent workspace whose dispatch resolves `effectiveInstallationId`
(`cc-effective-installation.ts`) or `repoUrl` (`getCurrentRepoUrl`, `current-repo-url.ts`) as
null/empty — **despite a connected repo visible in the UI** — falls into the not-connected fast
path, the graft is skipped, the fire-and-forget `ensureWorkspaceRepoCloned` at `cc-dispatcher.ts:1882`
**no-ops** (`ensure-workspace-repo.ts:138`: `if (installationId === null || !repoUrl) return "ok"`),
and the agent spawns repo-less.

**Why install/repoUrl diverge for a genuinely-connected workspace (the deep cause).** The two
reads use **different access paths against the post-ADR-044 source of truth**:

- `repoUrl` / `repo_status` are **non-credential** columns read via a **direct, RLS-gated
  `.select()`** on `workspaces` (`current-repo-url.ts:58-62`, `:132-136`; RLS
  `workspaces_select_for_members`) — a member **can** read them non-null.
- `installationId` is the **credential** column `workspaces.github_installation_id`, **revoked**
  from the `authenticated` grant, read **only** via the `resolve_workspace_installation_id`
  **SECURITY DEFINER RPC** (`resolve-installation-id.ts:38-41`). Migration 079's own function
  comment is explicit: it **"Returns NULL for non-members (no raise — deny is indistinguishable
  from 'not connected')."**

So a member of a connected team workspace can read `repo_url` (RLS pass) while
`resolve_workspace_installation_id` returns NULL (membership-deny / transient RPC blip) →
`installationId` null while `repoUrl` non-null → `hasConnection === false` →
**graft silently skipped → doomed agent.** This is the **same ADR-044
multi-workspace-per-installation theme** PR #5546 / #5437 addressed on the **WEBHOOK** path, now
surfacing on the **dispatch READ** path.

**There is currently NO Sentry signal** at the dispatch path for this state. (`op:ready-null-installation`
exists ONLY in the daily CRON `cron-workspace-sync-health.ts:139` — a periodic safety net, not the
synchronous dispatch signal.) The member's live cold-dispatch into a connected-but-null-resolving
workspace is **silently repo-less**.

**The fix direction is constrained by ADR-044** (see Architecture Decision section): widening the
RPC to return the install on membership-deny re-opens the exact credential-leakage surface ADR-044
closed. So we do **NOT** "correct" the resolution to force a non-null install. Instead we
**distinguish** the two NULL meanings at the gate and **fail honestly** (a real
"couldn't resolve your repository connection" message + a queryable+paging Sentry signal) rather
than fast-pathing into a doomed spawn.

## Premise Validation

Verified against worktree HEAD before research (all citations confirmed by Read/grep):

- **FAST-PATH skip confirmed** — `repo-readiness-self-heal.ts:128` (`hasConnection`), `:134-140`
  (`if (decision.ok) { if (!hasConnection || gitDirExists) return decision; … }`). A `ready`
  (`decision.ok`) + `!hasConnection` workspace returns `decision` (ok) with **no graft**.
- **No-op fallback clone confirmed** — `ensure-workspace-repo.ts:138`:
  `if (installationId === null || !repoUrl) return "ok"; // not connected → nothing to ensure`.
- **Dispatch enters the self-heal block** for the headline case — `cc-dispatcher.ts:1781-1784`:
  `needsSelfHeal = !repoReadiness.ok || !existsSync(.git)`; the `.git` is absent so the block runs,
  but it passes `installationId: effectiveInstallationId` (`:1800`) which can be null.
- **Two-read asymmetry confirmed** — `resolve-installation-id.ts:22-23` ("indistinguishable from
  'not connected'") + migration `079_workspace_repo_ownership_schema.sql` function COMMENT ("Returns
  NULL for non-members … deny is indistinguishable from 'not connected'") vs. `current-repo-url.ts:58-62`
  (direct RLS `.select` on the non-credential `repo_url`).
- **`effectiveInstallationId` passes null through** — `cc-effective-installation.ts:64`:
  `if (installationId === null || !connectedOwner) return installationId;`.
- **Candidate #2 (workspacePath vs sandbox-bind-cwd mismatch) RULED OUT** — the bwrap sandbox cwd is
  bound via `buildAgentQueryOptions({ workspacePath, … })` (`cc-dispatcher.ts:2247-2248`) using the
  **same** `workspacePath` local that the graft (`:1882`), `gitDirExists` seam (`:1823`), and
  `needsSelfHeal` `existsSync` (`:1783`) all use — all from
  `fetchUserWorkspacePath(args.userId, activeWorkspaceId)` (`:1570`, the unified ADR-044
  `activeWorkspaceId`). They are the same path **by construction** within a dispatch; the
  same-path claim at `cc-dispatcher.ts:1739-1754` holds for shared workspaces.
- **No external premises stale** — related PR **#5546** confirmed merged (`git log` 48a441dd9,
  2026-06-18). GitHub issue **4826** referenced in the evidence is an **UNRELATED P3 nav-rail
  feature** and is **NOT** the work target (the bug surfaced in a conversation titled "Fix Issue
  4826"); not treated as the target. No `#N` from this plan is cited as a blocker.

## Research Reconciliation — Spec vs. Codebase

| Claim (from the report / hypothesis) | Reality (verified) | Plan response |
|---|---|---|
| Graft skipped because `hasConnection` false on a connected workspace | TRUE — `repo-readiness-self-heal.ts:128,134-140` | Fix: distinguish member-deny-null from not-connected; fail honestly + clone-if-recoverable. |
| `installationId` can be null while repo is genuinely connected | TRUE — RPC deny returns NULL (mig 079 comment), `repoUrl` read via separate RLS path can be non-null | Treat (`!installationId` && `repoUrl` present && `repo_status==ready`) as a **divergence**, not "not connected". |
| "Fix the resolution so install is non-null" | **REJECTED by ADR-044** — RPC deny-NULL is the credential gate; widening leaks the credential surface | Direction is **fail honestly + distinguish**, NOT widen the RPC. |
| Workspace-path vs sandbox-cwd mismatch (candidate #2) | FALSE — same `workspacePath` local everywhere | No change; documented as ruled-out. |
| No Sentry signal at dispatch for this state | TRUE — `ready-null-installation` op is CRON-only (`cron-workspace-sync-health.ts:139`) | Add a dispatch-time op via `reportRepoResolverDivergence` + the missing `repo-resolver-divergence` alert rule. |
| Fire-and-forget clone at `:1882` would catch it | FALSE — it **no-ops** on null install/repoUrl (`ensure-workspace-repo.ts:138`) | The honest gate must own the observation; do not rely on the discarded fire-and-forget outcome. |
| Divergence helper should mirror `failHonestly` (persist `repo_status=error`) | **REJECTED at deepen-plan (P0)** — `failHonestly` persists because it observed a real failed clone; divergence attempted no clone. Persisting `error` on the shared `workspaces` row corrupts a healthy team workspace for its Owners + turns a transient RPC blip into a sticky failure (`getCurrentRepoStatus` is fail-open by design) | `failConnectionUnresolved` performs **zero `workspaces` writes**; the Sentry op is the only durable record; a transient blip self-recovers next dispatch. |

## User-Brand Impact

**If this lands broken, the user experiences:** a Concierge that accepts their message, spawns an
agent, and then has `/soleur:go` immediately fail with "no git repository" — with **no recovery**:
reconnecting the repo does not fix it, and there is no honest error explaining why. The operator's
own dogfood workspace is **currently unusable** end-to-end.

**If this leaks, the user's data/workflow is exposed via:** N/A for data — the fix must NOT widen
the `resolve_workspace_installation_id` credential gate (doing so would expose
`workspaces.github_installation_id`, a GitHub App token grant, to non-members — the precise
cross-tenant surface ADR-044 closed). The brand exposure is **workflow**: a team member silently
denied all Concierge work with a wrong CTA ("reconnect") they cannot act on.

**Brand-survival threshold:** single-user incident.

> CPO sign-off required at plan time before `/work` begins. The CPO domain leader is invoked in
> Phase 2.5 below (Product is relevant — this changes the member-facing not-ready copy). At review
> time, `user-impact-reviewer` is invoked by the review skill's conditional-agent block (threshold =
> single-user incident).

## Problem Statement

```text
Member of connected team workspace → cold Concierge dispatch
  ↓
cc-dispatcher Promise.all:
  getCurrentRepoUrl(activeWorkspaceId)        → "https://github.com/acme/widgets"  (RLS .select OK)
  getCurrentRepoStatus(activeWorkspaceId)     → repo_status="ready"                 (RLS .select OK)
  resolveInstallationId(activeWorkspaceId)    → null    (resolve_workspace_installation_id RPC deny)
  ↓
effectiveInstallationId = null  (cc-effective-installation.ts:64 passthrough)
  ↓
needsSelfHeal = !ok(false) || !existsSync(.git)(true) = true   → enter self-heal block
  ↓
resolveRepoReadinessWithSelfHeal({ installationId: null, repoUrl: "…", status: "ready" })
  hasConnection = (null !== null) && !!"…"  = false
  decision.ok = true (ready)
  → `if (!hasConnection || gitDirExists) return decision`  ← FAST-PATH SKIP, no graft
  ↓
healed.ok === true → NO throw → dispatch proceeds
  ↓
ensureWorkspaceRepoCloned({ installationId: null, … })  → no-op "ok" (ensure-workspace-repo.ts:138)
  ↓
Agent spawns into a `.git`-less workspace → /soleur:go Step 0.0: "no git repository", exit 128
  ↓
NO Sentry event.  Reconnect does not help (install still RPC-denies for the member).
```

## Goals

1. **Make the silent state observable** — a member cold-dispatch into a connected
   (`repo_status='ready'` or `repoUrl` present) workspace that resolves a **null install/repoUrl**
   at dispatch emits a **queryable + paging** Sentry signal (currently zero).
2. **Stop spawning doomed agents** — a genuinely-connected workspace whose dispatch-time
   install/repoUrl resolves null is **never** treated as "not connected" by the fast path. Either it
   recovers (when the inputs are sufficient to clone) or it **fails honestly** with a real
   "couldn't resolve your repository connection" message + the existing not-ready client surface.
3. **Regression test** the ready-but-`.git`-absent + dispatch-resolves-null-connection case.
4. **Preserve ADR-044 invariants** — do NOT widen the credential RPC; cc-dispatcher stays OFF the
   service-role allowlist; the common `ready`+`.git`-present zero-await fast path is untouched.

## Non-Goals

- **Widening `resolve_workspace_installation_id`** to return the install on membership-deny
  (re-opens the ADR-044 credential surface — explicitly rejected).
- Changing the **CRON** `op:ready-null-installation` detection (it is a separate, already-shipped
  safety net; this plan adds the *dispatch-time* signal it cannot provide).
- Reworking `resolveActiveWorkspace` / membership resolution itself (PR #5437/#5546 already unified
  the id; this plan acts on the *consequence* — a legitimately-null install for a connected repo).
- The always-enforce-workspace north star / personal-workspace-guarantee backfill (ADR-044 Decision
  5, tracked separately).

## Distinguishing the two NULL meanings (the design crux)

At the readiness gate we now have three observable facts for a `decision.ok` workspace with `.git`
absent:

| `installationId` | `repoUrl` | `repo_status` | Meaning | New behavior |
|---|---|---|---|---|
| non-null | present | ready | genuinely connected, recoverable | **graft (existing Bug-2 lock-free path)** — unchanged |
| **null** | **present** | ready/cloning/error | **connected but install RPC-denied/blipped** (the bug) | **fail honestly, NO `repo_status` write** + Sentry divergence op; NO doomed spawn |
| null | empty | not_connected | genuinely not connected | fast-path return (unchanged) |

The load-bearing predicate is **"`repoUrl` present (or `repo_status` indicates a connection) AND
`installationId` null"** → this is a **resolver divergence**, not "not connected". `repoUrl` (a
non-credential, RLS-readable column) is the honest signal that a connection *exists*; a null
`installationId` against a present `repoUrl` means the credential read denied, not that the repo is
absent. We cannot clone without the install, so we **fail honestly** (we have nothing to clone with)
and surface the real reason.

> **DESIGN CORRECTION (deepen-plan P0 — architecture-strategist).** The divergence helper MUST
> **NOT** mirror `failHonestly`'s `setRepoStatus(workspaceId, "error", …)` write. `failHonestly`
> persists `error` because it observed a **real, attempted clone that failed**; the divergence path
> attempted **nothing** (it has no install to clone with). Persisting `repo_status=error` on the
> divergence path is a **category error with two failure modes**:
>
> 1. **Cross-tenant corruption.** `repo_status`/`repo_error` live on the **shared `workspaces` row**.
>    A removed/transient member (or a member whose install merely *blipped*) whose
>    `set_repo_status` RPC passes its membership check would flip a **healthy team workspace to
>    `error` for every legitimate Owner** — the next Owner dispatch reads `error` and falls into the
>    recoverable-error branch.
> 2. **Sticky transient.** `installationId` is null on *any* RPC error (`resolve-installation-id.ts:43-51`
>    returns null + Sentry on a blip), and `getCurrentRepoStatus` is deliberately **fail-open**
>    (`current-repo-url.ts:108,122,144`) so a blip never poisons state. Writing `error` here converts
>    a self-recovering transient into a sticky failure the next dispatch reads.
>
> **Resolution:** `failConnectionUnresolved` returns
> `{ ok:false, code:"error", message, errorCode:"repo_setup_failed" }` (so the dispatch throws
> `RepoNotReadyError` and the member sees an honest message) and emits the divergence Sentry op as
> the **only durable record** — it performs **zero `workspaces` writes**. A transient blip then
> self-recovers on the next dispatch (next `resolveInstallationId` succeeds → non-null → graft path).
> The AC/test matrix asserts `setRepoStatus` is **NOT** called on the divergence path.

## Architecture Decision (ADR/C4)

### ADR

**Amend ADR-044** (status: accepted) with a new dated amendment:
**"2026-06-18 — dispatch readiness must distinguish membership-deny NULL install from not-connected."**
**Lineage:** anchor it as a **consequence-level extension of the existing 2026-06-18 "Bug 2 /
dispatch readiness" amendment** (ADR-044 ~`:552-617`, which made dispatch readiness require
`repo_status`-ok AND physical `.git` present) — same dispatch-readiness theme, extended from
"`.git` presence" to "credential-read divergence." Cite that subsection in the new amendment so the
lineage is traceable. The amendment records the decision (and its rejected alternative):

- **Decision:** At the Concierge dispatch readiness gate, a `decision.ok` + `.git`-absent workspace
  with **`repoUrl` present but `installationId` null** is a **resolver divergence**, surfaced as an
  honest `RepoNotReadyError` (real "couldn't resolve your repository connection" copy) + a paging
  `repo_resolver_divergence` Sentry op, performing **zero `workspaces` writes** — it is NEVER
  fast-pathed into a repo-less agent spawn, and NEVER persists `repo_status=error` (a non-member /
  transient-blip dispatch must not corrupt a healthy team workspace's readiness for its Owners).
- **Considered Options (amendment) — add to the NEW amendment's own `### Considered Options
  (amendment)` block, NOT ADR-044's original Option A/B/C table** (which is about the schema
  relocation, a different decision): *Widen `resolve_workspace_installation_id` to return the install
  on membership-deny* — **REJECTED**: re-opens the credential-leakage surface the RPC's deny-NULL
  gate closes (mig 079); the NULL ambiguity is inherent to membership-gated secrets and must be
  disambiguated by the **caller** using the non-credential `repoUrl`/`repo_status` signals, not by
  the credential read. *Persist `repo_status=error` on divergence (mirror `failHonestly`)* —
  **REJECTED**: cross-tenant corruption + sticky-transient (see Design Correction above).
- Authored via `/soleur:architecture` (the workflow edits the ADR file directly and commits in this
  feature's lifecycle — not a deferred issue, per `wg-architecture-decision-is-a-plan-deliverable`).

### C4 views

**No C4 impact** — verified against ALL THREE model files
(`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`). Enumeration
checked and found already-modeled:

- **External human actors:** the `founder` actor (`model.c4:8-10`) already documents multi-Owner
  ADR-038 team workspaces; the affected member is a workspace Owner — no new actor.
- **External systems:** `github` (`model.c4:171-174`) and the `engine -> github "Git operations"` /
  `claude -> github` edges already model the repo clone; `supabase` (`:139`) and `api -> supabase`
  already model the installation RPC read. No new external system.
- **Containers / data stores:** the fix lives entirely inside the existing `api` container's
  dispatch logic (`cc-dispatcher` → readiness gate); no new container or datastore. The
  `api -> claude "Spawns agent sessions"` edge's *condition* changes (block-vs-spawn) but the
  *topology* does not.
- **Actor↔surface access relationships:** unchanged — the member↔workspace access is already
  ADR-038/044 multi-Owner; this fix corrects *behavior* on an existing edge, adds no new access
  relationship.

A "no C4 impact" conclusion is therefore supported by the explicit enumeration above (not an
unsupported "None").

### Sequencing

The ADR amendment describes the target state shipped in this same PR (status: accepted amendment) —
no soak gate; it is a behavioral correction, not a destructive migration.

## Implementation Phases

> **Phase ordering is load-bearing:** the contract-changing edits (readiness-self-heal decision +
> new Sentry op) come BEFORE the dispatcher consumer wiring and the alert rule. RED tests precede
> GREEN (`cq-write-failing-tests-before`).

### Phase 0 — Preconditions (verify, do not assume)

- [x] Confirm vitest is the runner and the include glob: `apps/web-platform/vitest.config.ts`
      `unit` project collects `test/**/*.test.ts` (the regression test lands under `test/server/`).
- [x] Confirm the regression-test seam scaffold exists:
      `apps/web-platform/test/server/cc-dispatch-repo-self-heal.test.ts` (`makeSeams()` + `baseArgs()`
      already accept `installationId`/`repoUrl` overrides).
- [x] Confirm the typecheck form: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`
      (NOT `npm run -w`).
- [x] Confirm the existing op `ready-null-installation` is CRON-only:
      `git grep -n "ready-null-installation" apps/web-platform/` returns only
      `cron-workspace-sync-health.ts` + `issue-alerts.tf` (proves the dispatch path is dark).
- [x] Confirm `RepoResolverDivergenceOp` union members and the dedupe seam
      (`repo-resolver-divergence.ts:27-29,23`).
- [x] `git grep -n "repo-resolver-divergence\|repo_resolver_divergence" apps/web-platform/infra/sentry/`
      to confirm there is **no** existing `repo-resolver-divergence` alert rule (the divergence file
      comment calls it a "fast-follow") — this plan ships it.

### Phase 1 — RED: failing regression test

- [x] In `apps/web-platform/test/server/cc-dispatch-repo-self-heal.test.ts` add cases (these FAIL
      against current code, which fast-path-returns ok):
  - `"ready + .git ABSENT + installationId NULL + repoUrl present → divergence: NO spawn, returns { ok:false, errorCode:'repo_setup_failed' }, emits repo-resolver-divergence op"`
  - `"ready + .git ABSENT + repoUrl EMPTY + repo_status not_connected → genuinely not connected: fast-path return { ok:true }, NO divergence emit"` (the must-not-over-fire control)
  - `"ready + .git ABSENT + installationId present + repoUrl present → existing Bug-2 graft path"` (regression guard that the legitimate graft is unchanged)
- [x] Run the file with vitest; confirm the new divergence cases RED.

### Phase 2 — GREEN: distinguish + fail honestly in the readiness gate

- [x] `apps/web-platform/server/repo-readiness-self-heal.ts` — in the `decision.ok` branch
      (`:134-140`), before the current `if (!hasConnection || gitDirExists) return decision;`, add the
      **divergence** discrimination:
  - Compute `connectionAsserted = !!args.repoUrl /* repoUrl is the non-credential honest signal */`
    (optionally also treat a non-`not_connected` `args.status` as asserted).
  - When `connectionAsserted && args.installationId === null && gitDirExists === false`:
    - emit the dispatch-time Sentry divergence op via the injected `reportDivergence` seam (Phase 3),
    - return an honest `{ ok:false, code:"error", message: repoErrorMsg(<reason>), errorCode:"repo_setup_failed" }`
      via a small `failConnectionUnresolved(args, seams)` helper. **CRITICAL (deepen-plan P0):
      `failConnectionUnresolved` does NOT call `setRepoStatus` — it performs ZERO `workspaces`
      writes.** (Unlike `failHonestly`, which persists `error` *after a real clone attempt failed*,
      this path attempted no clone — persisting `error` on the shared workspace row would corrupt a
      healthy team workspace for its Owners and turn a transient RPC blip into a sticky failure. The
      Sentry op is the only durable record; a transient blip self-recovers next dispatch.) Reason
      copy (membership-deny-aware, NOT an unactionable "reconnect" — see CPO carry-forward):
      `"we couldn't verify your access to this repository. If you recently joined this workspace, ask the workspace owner to confirm the connection."`
  - Otherwise fall through to the existing `if (!hasConnection || gitDirExists) return decision;`
    (genuinely-not-connected and `.git`-present cases unchanged).
  - The existing `graftReadyButGitAbsent` path (install present, repoUrl present, `.git` absent) is
    **unchanged**.
- [x] Mirror the same **observability emit** into the **recoverable error/cloning** branch lower in
      the file (`:142-151`): a `decision.ok===false` workspace with `connectionAsserted && installationId
      null` falls into `!canRecover → return decision` (honest block already — `hasConnection` false
      so `canRecover` is false by construction); add ONLY the `reportDivergence` emit there so the
      cause is queryable (today it blocks honestly but **silently** on the cause). Keep the existing
      honest block; **no new `setRepoStatus` write here either.**
- [x] Verify `repoErrorMsg` / `sanitizeGitStderr` reuse (`repo-readiness.ts:32-34`,
      `git-auth.ts sanitizeGitStderr`) — no new copy primitive. (`sanitizeGitStderr` still wraps the
      reason for the client `repoErrorMsg`, even though it is no longer persisted.)

### Phase 3 — GREEN: dispatch-time observability

- [x] `apps/web-platform/server/repo-resolver-divergence.ts` — extend `RepoResolverDivergenceOp`
      (`:27-29`) with a new member, e.g. `"connected-null-install-at-dispatch"`. Dedupe fingerprint
      (`${op}:${userId}:${activeClaimWorkspaceId}`) and the `extra` shape (two workspace ids only, no
      `repoUrl`/`installationId`/raw-userId — security P2) are reused unchanged. Pseudonymization to
      `userIdHash` happens at the `reportSilentFallback` boundary (ADR-029) — verify by reading the
      emit.
- [x] Wire the emit into the readiness-self-heal **module** via an **injected seam** — add a
      **required** seam `reportDivergence: (op: RepoResolverDivergenceOp, userId, workspaceId) => void`
      to `RepoSelfHealSeams`, wired in `cc-dispatcher.ts`'s inline seam object (`:1805-1824`) as
      `reportDivergence: (op, userId, workspaceId) => reportRepoResolverDivergence({ userId, op, activeClaimWorkspaceId: workspaceId, resolvedWorkspaceId: workspaceId })`.
      Seams are passed as an **inline literal** (not a defaults-merge), so the new seam must be added
      to that object explicitly. Keeping the module DB/Sentry-free preserves the AC4 "decision is
      DB/IO-free in unit test" contract.
  - **Emit-site clarification (precedent-diff finding):** the existing
    `reportRepoResolverDivergence` call at `cc-dispatcher.ts:1843` is in the **catch block** and fires
    on `op:"self-heal-failed"` (an orchestration-infra crash). It is a **different op + different
    trigger** from the new dispatch-time `connected-null-install-at-dispatch` op, which fires from
    INSIDE the module on the recognized divergence (not a crash). The new emit lives in the module via
    the seam; the catch-block emit stays as-is. No double-fire (the divergence return is a clean
    `{ ok:false }`, not a thrown error, so it never reaches the catch).
- [x] `apps/web-platform/infra/sentry/issue-alerts.tf` — add the missing
      `sentry_issue_alert "repo_resolver_divergence"` rule (the divergence file's documented
      fast-follow). Scope: `feature == "repo-resolver-divergence"` (feature-only filter, mirroring
      the `workspace_sync_health` rule shape at `:508-542` and its rationale at `:491-497` — the
      feature tag is dedicated and every event is operator-actionable). `action_match="any"`,
      `filter_match="all"`, `conditions_v2 = [{first_seen_event={}},{reappeared_event={}},{regression_event={}}]`,
      a single `tagged_event` filter on `feature == "repo-resolver-divergence"`,
      `actions_v2` = `notify_email` IssueOwners/ActiveMembers, `lifecycle { ignore_changes = [environment] }`.
      **`frequency = 20`** — verified free (taken set in-file: 5,10,11,12,13,14,15,16,17,18,19,30,60,61,62;
      re-grep `grep -E 'frequency *=' issue-alerts.tf` at /work to confirm 20 is still free).
- [x] **Op-contract test** — add/extend a `test/sentry-*-op-contract.test.ts` (mirroring the 8
      existing `*-op-contract.test.ts` orphan suites) that pins: every emitted
      `feature=repo-resolver-divergence` op is covered by the new alert rule's filter (feature-only,
      so this is the cross-artifact contract that a new op cannot dark the alert). This is the
      "removing/adding an emit site must not dark a filtering monitor" guard.

### Phase 4 — Wire the dispatcher consumer

- [x] `apps/web-platform/server/cc-dispatcher.ts:1795-1825` — confirm the new
      `failConnectionUnresolved` `{ ok:false }` return is honored by the existing
      `if (!healed.ok) throw new RepoNotReadyError(healed.code, healed.message, healed.errorCode)`
      (`:1852-1858`) and that the catch at `:3531` surfaces it to the client (same path as the
      existing not-ready copy; **no** Sentry double-mirror — the gate already emitted the divergence
      op). Pass the new `reportDivergence` seam default here.
- [x] Confirm the common `ready`+`.git`-present zero-await fast path (`needsSelfHeal===false`,
      `cc-dispatcher.ts:1781-1784`) is untouched — no `getFreshTenantClient`, no new probe (AC7).

### Phase 5 — ADR + verification

- [x] Author the ADR-044 amendment via `/soleur:architecture` (Phase 2.10 deliverable).
- [x] Full typecheck + the affected vitest files green; the RED cases from Phase 1 now GREEN.

## Acceptance Criteria

### Pre-merge (PR)

- [x] **AC1** — `resolveRepoReadinessWithSelfHeal` with `{ status:"ready", installationId:null,
      repoUrl:"https://github.com/acme/widgets" }` and `gitDirExists:()=>false` returns
      `{ ok:false, code:"error", errorCode:"repo_setup_failed" }` (NOT `{ ok:true }`), calls the
      injected `reportDivergence` seam exactly once, AND **does NOT call `setRepoStatus`** and **does
      NOT call `ensureWorkspaceRepoCloned`** (zero writes, no clone attempt — deepen-plan P0).
      (vitest, `cc-dispatch-repo-self-heal.test.ts`)
- [x] **AC1b** — the divergence path performs **zero `workspaces` writes**: assert
      `seams.setRepoStatus` and `seams.claimCloneLock` are both called 0 times on the divergence input
      (proves a removed/transient member cannot corrupt a healthy team workspace's `repo_status`).
- [x] **AC2** — the genuinely-not-connected control (`installationId:null, repoUrl:"",
      status:"not_connected", gitDirExists:false`) still returns `{ ok:true }` and does **NOT** call
      `reportDivergence` (no over-fire).
- [x] **AC3** — the legitimate Bug-2 graft (`installationId:INSTALL, repoUrl:REPO,
      status:"ready", gitDirExists:false`, clone seam → "ok") still returns `{ ok:true }` and calls
      `ensureWorkspaceRepoCloned` once (no regression of PR #5546's path).
- [x] **AC4** — `RepoResolverDivergenceOp` includes the new op; `reportRepoResolverDivergence`
      `extra` carries ONLY `{ userId→hash, activeClaimWorkspaceId, resolvedWorkspaceId }` — assert no
      `repoUrl`/`installationId` keys present. (vitest, repo-resolver-divergence test)
- [x] **AC5** — `apps/web-platform/infra/sentry/issue-alerts.tf` contains
      `sentry_issue_alert "repo_resolver_divergence"` with `filter_match="all"`,
      a `feature == "repo-resolver-divergence"` filter, and a `frequency` value **unique** within the
      file. Verify: `grep -c 'frequency *=' issue-alerts.tf` values have no duplicate of the new one.
- [x] **AC6** — op-contract test asserts every `feature=repo-resolver-divergence` op (the full
      `RepoResolverDivergenceOp` union) is matched by the new feature-only alert filter (a new op
      cannot dark the alert).
- [x] **AC7** — zero-await fast path proven untouched: a `ready`+`.git`-present case still returns
      `{ ok:true }` touching only `gitDirExists` (no `claimCloneLock`/`setRepoStatus`/clone) — the
      existing `cc-dispatch-repo-self-heal.test.ts` "AC7" case still passes.
- [x] **AC8** — `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean.
- [x] **AC9** — ADR-044 has the new dated amendment (lineage cited to the 2026-06-18 "Bug 2 /
      dispatch readiness" subsection) with a `### Considered Options (amendment)` block containing
      BOTH rejected alternatives (widen-RPC; persist-error-on-divergence); C4 unchanged with the
      enumerated "no C4 impact" justification recorded.
- [x] **AC10** — `resolve_workspace_installation_id` RPC is **unmodified** AND **no new migration is
      added** (`ls apps/web-platform/supabase/migrations/` shows no file newer than 113 touching the
      RPC or `set_repo_status`) — proof the credential gate was not widened and the fix is TS-only.

### Post-merge (operator)

- [ ] **AC11** — apply the new `issue-alerts.tf` resource. `Automation:` handled by the existing
      `apply-sentry-infra.yml` auto-apply-on-merge pipeline (sentry infra root is auto-applied;
      confirm via `.github/workflows/apply-sentry-infra.yml` in Phase 0). No operator SSH/dashboard
      step. The workflow IS `-target=`-scoped (verified `apply-sentry-infra.yml:196-254`) — add the
      single line `-target=sentry_issue_alert.repo_resolver_divergence` to the targets block. The
      destroy-guard (`destroy-guard-filter-sentry.jq`) already handles all `sentry_issue_alert`
      resources via its `select(.type == "sentry_issue_alert")` clause and triggers only on
      deletions/block-shrinks — **a resource ADDITION needs no destroy-guard sweep** (verified).

## Test Scenarios

| # | Input (seams/args) | Expected |
|---|---|---|
| T1 | ready · install=null · repoUrl present · `.git` absent | `{ ok:false, errorCode:"repo_setup_failed" }`, 1× divergence emit, **0× setRepoStatus, 0× claimCloneLock, 0× clone** (P0 — no write, no clone attempt) |
| T2 | not_connected · install=null · repoUrl="" · `.git` absent | `{ ok:true }`, 0× divergence emit, 0× clone |
| T3 | ready · install=INSTALL · repoUrl present · `.git` absent · clone→ok | `{ ok:true }`, 1× clone, 0× setRepoStatus (already ready) |
| T4 | ready · install=INSTALL · repoUrl present · `.git` PRESENT | `{ ok:true }`, only `gitDirExists` touched (AC7 fast path) |
| T5 | error · install=null · repoUrl present · `.git` absent | honest block `{ ok:false }` + 1× divergence emit, **0× setRepoStatus** (cause now queryable; no error-state persist) |

## Files to Edit

- `apps/web-platform/server/repo-readiness-self-heal.ts` — add divergence discrimination +
  `failConnectionUnresolved` helper; add `reportDivergence` seam to `RepoSelfHealSeams`.
- `apps/web-platform/server/repo-resolver-divergence.ts` — extend `RepoResolverDivergenceOp` with
  the new dispatch-time op.
- `apps/web-platform/server/cc-dispatcher.ts` — pass the `reportRepoResolverDivergence` default seam
  into `resolveRepoReadinessWithSelfHeal` (`:1805-1824`); confirm catch/throw wiring unchanged.
- `apps/web-platform/infra/sentry/issue-alerts.tf` — add `sentry_issue_alert
  "repo_resolver_divergence"` (frequency=20, feature-only filter).
- `.github/workflows/apply-sentry-infra.yml` — add
  `-target=sentry_issue_alert.repo_resolver_divergence` to the `-target=`-scoped plan/apply block.
- `apps/web-platform/test/server/cc-dispatch-repo-self-heal.test.ts` — RED→GREEN regression cases.
- `apps/web-platform/test/<sentry-repo-resolver-divergence-op-contract>.test.ts` — new op-contract
  suite (or extend an existing divergence test).
- `knowledge-base/engineering/architecture/decisions/ADR-044-workspace-repo-ownership.md` — new
  amendment.

## Files to Create

- Possibly `apps/web-platform/test/sentry-repo-resolver-divergence-alert-op-contract.test.ts` (if no
  divergence-op-contract suite exists to extend).

## Open Code-Review Overlap

None — to be confirmed at /work via
`gh issue list --label code-review --state open --json number,title,body --limit 200` then
`jq --arg path …` over each Files-to-Edit path (two-stage form per
`2026-04-15-gh-jq-does-not-forward-arg-to-jq`).

## Observability

```yaml
liveness_signal:
  what: "repo_resolver_divergence Sentry issue (op=connected-null-install-at-dispatch)"
  cadence: "on-occurrence (per member cold-dispatch resolving null-install on a connected ws)"
  alert_target: "Sentry issue-alert repo_resolver_divergence → email IssueOwners/ActiveMembers"
  configured_in: "apps/web-platform/infra/sentry/issue-alerts.tf"
error_reporting:
  destination: "Sentry via reportRepoResolverDivergence → reportSilentFallback (feature=repo-resolver-divergence)"
  fail_loud: true
failure_modes:
  - mode: "member cold-dispatch into connected ws, install RPC-denies → null"
    detection: "new dispatch-time divergence op (this PR); CRON ready-null-installation as backstop"
    alert_route: "repo_resolver_divergence issue-alert"
  - mode: "self-heal orchestration infra failure (tenant mint/RPC)"
    detection: "existing reportSilentFallback op=repo-readiness-self-heal (cc-dispatcher.ts:1830)"
    alert_route: "existing cc-dispatcher Sentry"
logs:
  where: "Sentry (pseudonymized userIdHash, ADR-029); Better Stack drain for reportSilentFallback"
  retention: "Sentry default project retention"
discoverability_test:
  command: "git grep -n 'connected-null-install-at-dispatch' apps/web-platform/server apps/web-platform/infra/sentry && grep -c 'sentry_issue_alert \"repo_resolver_divergence\"' apps/web-platform/infra/sentry/issue-alerts.tf"
  expected_output: "op referenced in emitter + alert rule present (count 1); NO ssh"
```

## Domain Review

**Domains relevant:** Engineering, Product

### Engineering (CTO)

**Status:** carry-forward from ADR-044 brainstorm (`2026-06-16-adr-044-workspace-owned-connection-brainstorm.md` §Engineering)
**Assessment:** The divergence is the confirmed dual-resolver class (#4767 / ADR-044). CTO direction:
prefer the canonical membership-verified resolver and do not introduce a second resolve; here the
unified id already exists (PR #5437/#5546) — the residual gap is the *consequence* (legit-null
install for a connected repo). The architecturally-correct response is to **disambiguate at the
caller** using the non-credential `repoUrl` signal and fail honestly, NOT to widen the credential
RPC. Route any migration change through data-integrity-guardian — but this plan adds **no**
migration (AC10).

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline) — no new user-facing page/flow/component (no path under
`components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`). The only user-visible change is the
*copy* of an existing not-ready error surface (reusing `repoErrorMsg`). CPO sign-off is required by
the single-user-incident threshold (frontmatter `requires_cpo_signoff: true`); the member-facing
copy direction (honest "couldn't resolve your repository connection" instead of a wrong "reconnect"
CTA) carries forward the ADR-044 brainstorm CPO finding ("role-branch the copy; members get a real
signal, not a useless reconnect"). No `.pen` required (no new surface).
**Agents invoked:** cpo (carry-forward), none new
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface)

#### Findings

The fix improves the member experience from "silent doomed spawn" to "honest, queryable failure."
No new emotional/persuasive copy; reuses the existing `repoErrorMsg` template with a connection-
specific reason.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or omits the threshold will fail
  `deepen-plan` Phase 4.6 — this plan's section is filled (threshold: single-user incident).
- **Do NOT widen `resolve_workspace_installation_id`.** The deny-NULL is the credential gate; the
  disambiguation MUST live in the caller using `repoUrl`/`repo_status`. Widening leaks
  `workspaces.github_installation_id` to non-members (the exact ADR-044 surface).
- **P0 — NEVER persist `repo_status=error` on the divergence path.** The divergence helper performs
  zero `workspaces` writes (AC1/AC1b/T1/T5). Persisting `error` would (a) let a non-member/transient
  dispatch corrupt a healthy team workspace's readiness for its Owners, and (b) turn a transient RPC
  blip into a sticky failure. This is the deepen-plan architecture-strategist P0 — the single most
  important deviation from the `failHonestly` precedent (which DOES persist, because it observed a
  real clone failure).
- **Over-fire risk:** the genuinely-not-connected path (`repoUrl` empty, `not_connected`) MUST NOT
  emit the divergence op (AC2/T2 guards this). The discriminator keys on `repoUrl` present, not on
  `!hasConnection`.
- **Alert-rule darking:** a new `RepoResolverDivergenceOp` member must be covered by the
  feature-only alert filter; AC6 op-contract test guards that adding an op cannot dark the alert.
- **Storm-bounding is Sentry-side, not the process Set.** The dedupe `Set` in
  `repo-resolver-divergence.ts:19` is process-local (a fresh process / replica re-emits once per
  fingerprint by design). The real paging-volume backstop is the Sentry issue-alert `frequency`
  throttle + issue grouping (first_seen/reappeared/regression lifecycle). The fingerprint
  `(op,userId,activeClaimWorkspaceId)` is correct as-is; keep `extra` to the two workspace ids only
  so Sentry grouping is not defeated by a high-cardinality field.
- **Sentry `frequency` uniqueness:** the new issue-alert uses `frequency = 20` (verified free; taken
  set in-file 5,10,11,12,13,14,15,16,17,18,19,30,60,61,62). Re-grep `grep -E 'frequency *=' issue-alerts.tf`
  at /work to confirm 20 is still free.
- **`-target=` allow-list:** `apply-sentry-infra.yml` IS `-target=`-scoped — add
  `-target=sentry_issue_alert.repo_resolver_divergence` to its targets block. The
  `destroy-guard-filter-sentry.jq` already covers all `sentry_issue_alert` resources and fires only
  on deletions/block-shrinks, so a resource **addition** needs **no** destroy-guard sweep (verified).
- **Emit-site distinctness:** the existing `reportRepoResolverDivergence` call at
  `cc-dispatcher.ts:1843` is the catch-block `self-heal-failed` op (an orchestration crash). The new
  `connected-null-install-at-dispatch` op fires from inside the module via the `reportDivergence`
  seam on the clean `{ ok:false }` divergence return — a different op + trigger; no double-fire.
- **Seam-injected emit:** keep the Sentry emit behind an injected (required) seam so the readiness
  module stays DB/IO-free in unit tests (AC4 contract from PR #5546). The seam is wired in
  cc-dispatcher's inline seam literal (`:1805-1824`), not a defaults-merge.

## Resume prompt (copy-paste after /clear)

```text
/soleur:work knowledge-base/project/plans/2026-06-18-fix-concierge-dispatch-null-connection-reclone-plan.md
Branch: feat-one-shot-concierge-dispatch-null-connection-reclone.
Worktree: .worktrees/feat-one-shot-concierge-dispatch-null-connection-reclone/.
Context: fix the readiness-self-heal FAST-PATH (repo-readiness-self-heal.ts:128-140) so a
connected (repoUrl present) but install-null shared workspace fails honestly + emits a
repo-resolver-divergence Sentry op instead of spawning a repo-less agent. Plan written, RED tests
next. Do NOT widen the resolve_workspace_installation_id RPC (ADR-044 credential gate).
```
