---
title: "Fix: diverged-clone-with-un-pushed-commits permanent workspace dead-end (kb/sync self-heal recovery)"
type: bug
date: 2026-06-16
branch: feat-one-shot-kb-sync-diverged-clone-recovery
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
---

# 🐛 Fix: Concierge workspace permanently dead-ends on a DIVERGED clone with un-pushed local commits

## Enhancement Summary

**Deepened on:** 2026-06-16
**Plan-review applied:** DHH + Kieran + code-simplicity (3 reviewers; consensus changes applied)
**Deepen passes:** hard gates 4.6/4.7/4.8/4.9 (all PASS), precedent-diff (4.4), verify-the-negative (4.45),
learnings discovery.

### Key improvements from review + deepen
1. **Dropped the inline recovery-branch push (DHH P1 + code-simplicity YAGNI).** The non-destructive guarantee is
   carried entirely by the local `branch`-before-`reset` ordering; off-box durability for regenerable
   `knowledge-base/**`-only content is a clean follow-up, not part of this fix. This removed a whole op slug, an AC,
   a failure mode, and a test scenario.
2. **Added detached-HEAD handling (Kieran P1-2).** `rev-parse --abbrev-ref HEAD` returns the literal `"HEAD"` when
   detached; it now aborts with a distinct observable slug instead of being misclassified.
3. **Struck the false "allowlist" framing (Kieran P1-1).** `gitWithInstallationAuth` is unguarded; the restrictive
   list gates only `runConnectedRepoGit`. Verified live (see Research Insights).
4. **Anchored the design to the two on-point self-heal learnings** (2026-06-03 ×2) — this fix is the direct
   continuation of the abort-guard those learnings introduced; the branch-aside resolves the tension they flagged.

### New considerations discovered
- The recovery *makes a formerly do-nothing abort path act*. Learning `2026-06-03-self-heal-on-brand-path-only-acts-on-safe-symptom`
  says "prefer do-nothing-when-uncertain over clever repair" at single-user-incident threshold. The plan now
  explicitly justifies why branch-aside is the safe exception (it is non-destructive by construction — see
  Research Insights "Design lineage").
- Verify-the-negative confirmed all four safety claims (no application code runs `git gc`/`branch -D`/`clean`; a
  named branch ref is a gc-root even in a shallow clone).

## Overview

A connected Concierge workspace whose repo clone has **diverged from `origin/<default>` with one or more
un-pushed local commits** is permanently trapped. Every `POST /api/kb/sync` re-fires
`selfHealNonFastForward()`, which **aborts** the recovery (to protect agent work) the moment it sees
`git rev-list --count @{u}..HEAD > 0`, emits `op:self-heal-aborted-dirty`, and returns `non_fast_forward`.
Reconnect does not recover it (mechanism below), and the Concierge dispatch readiness gate keeps reporting
"workspace isn't ready". This is a single-user **brand-survival** incident on the core
onboarding → work path: the user's workspace silently stops syncing and there is no automated way out.

This is **distinct** from the "checkout missing / errored" case fixed by the concierge reconnect/self-heal
change merged 2026-06-16 (release `3c8849655`, PRs #5409/#5413/#5415). That fix recovers a `.git`-**absent**
workspace by re-cloning. The present bug is a `.git`-**present** clone that exists but has diverged — a state
neither the kb/sync self-heal nor the re-clone path will act on.

### Production signal (verbatim)

- **Error:** `self-heal aborted: un-pushed local commits present`
- **Route:** `POST /api/kb/sync`
- **Sentry op:** `self-heal-aborted-dirty` (feature `kb-route-helpers`)
- **When:** 2026-06-16 13:54 UTC, release `web-platform@0.140.0`, feature tag `pino-mirror`
- **Operator report:** workspace stuck; clicking **Reconnect** does NOT recover; dispatch readiness gate
  says "workspace isn't ready".

> Note: "Fix Issue 4826" in the operator's screenshot was an unrelated nav-rail task they tried that
> failed — **not** this bug. 4826 is not the target.

### Confirmed root cause (two recovery paths both refuse to act on a diverged-but-present clone)

1. **`apps/web-platform/server/workspace-sync.ts` → `selfHealNonFastForward()` (lines 165–255).**
   On a `non_fast_forward` pull it runs `git rev-list --count @{u}..HEAD`; when `localCommits > 0` it
   **aborts** the `reset --hard` (lines 198–218) to avoid destroying agent work, emits
   `reportSilentFallback("self-heal aborted: un-pushed local commits present", op:self-heal-aborted-dirty)`,
   and returns `{ ok:false, errorClass:"non_fast_forward" }`. **Nothing ever clears the divergence**, so
   every subsequent `/api/kb/sync` re-fires the same abort. This is gap #1 and the direct source of the Sentry error.

2. **The re-clone paths are `.git`-ABSENT gated**, so a clone that *exists* but has diverged is never re-cloned:
   - `apps/web-platform/server/repo-readiness-self-heal.ts:124` — `canRecover` requires
     `seams.gitDirExists(args.workspacePath) === false`. A diverged clone has `.git` present → never recovers
     → the dispatch readiness gate honest-blocks "workspace isn't ready".
   - `apps/web-platform/server/ensure-workspace-repo.ts:142` — `ensureWorkspaceRepoCloned` early-returns
     `"ok"` when `<workspacePath>/.git` exists ("NEVER touch an existing repo … could destroy un-pushed commits").

## Research Reconciliation — Spec vs. Codebase

The original bug description was accurate on gap #1 and on `repo-readiness-self-heal.ts` / `ensure-workspace-repo.ts`,
but **the Reconnect mechanism is more subtle than "`.git`-absent gated"** — the design must reflect the real flow.

| Claim in description | Codebase reality | Plan response |
| --- | --- | --- |
| Reconnect re-clone (`app/api/repo/setup/route.ts`, `use-reconnect.ts`) is `.git`-absent gated, so it's a no-op on a diverged clone. | `POST /api/repo/setup` → `provisionWorkspaceWithRepo` (`workspace.ts:151`) calls `removeWorkspaceDir` (`rm -rf`, line 185) **unconditionally** then a full `git clone` — it is NOT `.git`-absent gated; it *would* wipe-and-reclone a diverged clone. **But** `use-reconnect.ts → attemptResetup` only issues the setup POST when `options.repoStatus !== "ready"` (`use-reconnect.ts`, FIX 1b block). A diverged clone leaves `repo_status === "ready"` (the clone *succeeded*; only the sync diverged), so Reconnect short-circuits to the plain `onReconnected()` no-op and never reaches the wipe-and-reclone. **That** is the real Reconnect dead-end. | Primary fix is the server-side automated recovery in `selfHealNonFastForward` (no operator action at all). Reconnect remains a destructive last resort and is intentionally NOT the recovery path for un-pushed commits — wipe-and-reclone would *destroy* the very commits we must preserve. Document the `repo_status==="ready"` short-circuit so we don't "fix" the wrong layer. |
| The trigger is the 2026-06-16 post-clone auto-sync committing LOCALLY and never pushing. | Confirmed mechanism: `auto-sync-trigger.ts` fires `/soleur:sync --headless`; the sync path (`session-sync.ts syncPush`, lines 568–605) auto-commits allowlisted `knowledge-base/**` changes (`ALLOWED_AUTOCOMMIT_PATHS = [/^knowledge-base\//]`, line 28) onto the **checked-out default branch**, then does a bare `git push` (line 602). If the default branch is **protected**, the push is rejected; the local commit stays, and the clone is now diverged with an un-pushable local commit — trapping `/api/kb/sync` forever. | The recovery must treat default-branch auto-sync commits as **un-pushable orphans** and branch them aside (preserving them) rather than destroy them, then resync. This is the safe, non-destructive recovery. |
| There is an existing test for the `.git`-absent re-clone case. | Confirmed: `test/server/cc-dispatch-repo-self-heal.test.ts:120` asserts "`.git` present → honest block, NO clone". `test/kb-route-helpers.test.ts` (the `scriptGit` harness, line 550) covers ZERO-local-commit self-heal + the abort case. **No** test covers `localCommits > 0` *recovery*. | Add the diverged-with-un-pushed-commits **recovery** regression test in `kb-route-helpers.test.ts` using the existing `scriptGit` harness (extend it with a `branch` handler). |

## User-Brand Impact

**If this lands broken, the user experiences:** their Concierge workspace silently stops syncing the
knowledge base; "Sync now" returns a desync state, the Concierge dispatch says "workspace isn't ready",
and **Reconnect does nothing** — a non-technical user has no escape and the product appears dead.

**If this leaks, the user's data/workflow is exposed via:** N/A for confidentiality — the failure mode is
**availability/durability**, not disclosure. The durability risk is the inverse: a *careless* fix
(`reset --hard` over un-pushed commits) would **destroy** the user's un-pushed agent-session work. The fix
must be provably non-destructive (commits are branched aside, never discarded).

**Brand-survival threshold:** single-user incident.

> CPO sign-off required at plan time before `/work` begins. The brainstorm leaders did not pre-frame this
> (direct-to-plan path); confirm CPO has reviewed the recovery design (branch-aside vs. destroy) before work
> starts. `user-impact-reviewer` will be invoked at review time (review/SKILL.md conditional-agent block).

## Hypotheses

The bug is a logic gap, not a network outage (no SSH/firewall/handshake surface). The single open hypothesis
is the **trigger** — whether the protected-default-branch push rejection is what produces the un-pushed commit.
The Research Reconciliation table confirms the mechanism by code-reading (`session-sync.ts` bare `git push` on
the checked-out default branch + `ALLOWED_AUTOCOMMIT_PATHS` auto-commit). The recovery is correct regardless of
the exact trigger — any path that leaves an un-pushed local commit on the default branch is recovered.

## Design: safe, automated, non-destructive recovery

**Principle:** distinguish *un-pushable orphan auto-sync commits on the default branch* (which we may safely move
aside and resync) from *genuine agent-session work* (which must be preserved). The safe recovery preserves **both**
by branching the un-pushed commits aside before resetting the default branch — nothing is ever discarded.

Recovery sequence inside `selfHealNonFastForward`, on the `localCommits > 0` branch (replacing today's abort):

1. **Resolve the default branch** (already done — `resolveDefaultBranch`).
2. **Determine which branch HEAD is on.** Read `git rev-parse --abbrev-ref HEAD` (`.toString().trim()`, mirroring
   the `resolveDefaultBranch` trim at `workspace-sync.ts:69`). Three cases:
   - **HEAD == default branch** → the trapped state; proceed to step 3 (branch-aside + reset).
   - **HEAD == a feature branch** (any other named branch) → genuine agent work targeting a PR; **keep aborting**
     (preserve the existing `op:self-heal-aborted-dirty` behavior). The automated branch-aside applies ONLY to
     un-pushable commits stranded on the default branch.
   - **HEAD == `"HEAD"` (detached HEAD)** → `--abbrev-ref` emits the literal string `"HEAD"` when detached. This is
     neither a default- nor a feature-branch state; there is no checked-out branch to protect, but it is also not
     the known trapped auto-sync shape. **Abort, but with a DISTINCT observable op slug**
     (`op:self-heal-aborted-detached-head`) so it is queryable and never silently bucketed into the dirty abort.
     (Kieran P1-2: a misclassified detached HEAD would otherwise re-trap the very dead-end this fix removes.)
3. **Branch the un-pushed commits aside (preserve, don't destroy):** create a recovery branch pointing at the
   current HEAD — `git branch <recovery-branch> HEAD` — where `<recovery-branch>` is a deterministic,
   collision-resistant name, e.g. `soleur/recovered-kb-sync-<unix-ms>` (the timestamp avoids clobbering a prior
   recovery branch). The commit objects are now reachable from `<recovery-branch>` and recoverable without SSH.
4. **Reset the default branch to origin** — `git reset --hard origin/<default>` (now safe: the commits live on
   the recovery branch). The clone is no longer diverged.
5. **Emit observability** mirroring the existing recovered-path contract: a WARN-level `warnSilentFallback`
   (`op:self-heal-recovered-diverged`) recording `localCommits` and the recovery branch name. Keep
   `userIdHash`/pseudonymized userId + `sanitizeGitStderr` handling intact (no raw `workspacePath` in any payload —
   it embeds the raw userId, per the existing Recital 26 omission).
6. **Return `{ ok: true, recovered: true }`** so the kb/sync route writes a recovered row and the workspace unblocks.

**Pushing the recovery branch is DEFERRED, not part of this fix (plan-review consensus — DHH P1, code-simplicity
YAGNI).** The non-destructive guarantee is carried entirely by step 3 (local `branch` before step 4's `reset`); the
commits survive locally regardless of any push. Off-box durability for a recovery branch is speculative for content
that is `knowledge-base/**`-only auto-sync data — regenerable on the next successful sync and never present on origin
anyway. Pushing inline would add a remote-coupled failure surface (branch-protection/push-permission variance, a
token-blip tolerance branch, a second op slug) for a step the recovery does not depend on. If an operator later needs
the branch promoted off-box, that is a clean follow-up that layers on top of the existing local branch with no change
to the core reset/unblock logic.

**Why branch-aside over open-a-recovery-PR:** opening a PR requires GitHub API surface (title/body/base/head) and
runs into branch-protection/PR-template variance per user repo — a heavier failure surface. Branch-aside is pure git
plumbing on the local clone; the named branch is the durable, recoverable artifact, and a future PR-open follow-up can
promote it without changing the reset/unblock logic.

**Note on the git wrapper (Kieran P1-1):** these git verbs run through `gitWithInstallationAuth` (`git-auth.ts`),
which is **unguarded** — it has NO subcommand/flag allowlist. The restrictive `ALLOWED_GIT_SUBCOMMANDS` /
`FORBIDDEN_GIT_FLAGS` list in `session-sync.ts:39-91` gates only `runConnectedRepoGit` (the local shell-out path),
NOT this wrapper. Proof: the existing `git reset --hard origin/<default>` at `workspace-sync.ts:221-225` already runs
through `gitWithInstallationAuth` today — a `--hard` the `session-sync.ts` list would forbid. So `branch`,
`rev-parse`, and `reset` need **no permission change**; do NOT route the self-heal through `runConnectedRepoGit`
(that path WOULD reject `--hard`/`branch` and break the existing reset).

**Why this is provably non-destructive:** step 3 captures HEAD on a named branch BEFORE step 4's reset. The reset
moves only the default-branch ref; the commit objects remain reachable from `<recovery-branch>`. No `git gc`,
no `branch -D`, no `clean`. A unit test asserts the `branch` call precedes the `reset` call and targets `HEAD`.

## Files to Edit

- `apps/web-platform/server/workspace-sync.ts`
  Replace the unconditional `localCommits > 0` **abort** in `selfHealNonFastForward` with the
  branch-on-default-branch decision: (a) read `git rev-parse --abbrev-ref HEAD` (trim the output); (b) if HEAD is a
  feature branch (any named branch ≠ default), keep the existing abort + `op:self-heal-aborted-dirty` (genuine agent
  work); (c) if HEAD is `"HEAD"` (detached), abort with the distinct `op:self-heal-aborted-detached-head` slug;
  (d) if HEAD = default branch, run the branch-aside → reset → `{ok:true, recovered:true}` sequence. Add `branch`
  and `rev-parse` to the git verbs this function issues via the injected `gitWithInstallationAuth` (no allowlist
  change — see Design "Note on the git wrapper"). Preserve the existing `sanitizeGitStderr` usage and the
  no-raw-`workspacePath`-in-payload rule. Add the new op slugs (`self-heal-recovered-diverged`,
  `self-heal-aborted-detached-head`) — see Observability section for the emit-site registration sweep.
  The `localCommits === 0` (phantom-divergence) branch is UNCHANGED: it keeps emitting `op:self-heal-reset` and
  issues NO `branch` call.

- `apps/web-platform/test/kb-route-helpers.test.ts`
  Extend the `scriptGit` harness (line 550) with explicit `branch?` and `revParse?` handlers — the current
  fall-through returns an empty Buffer, so an unhandled `rev-parse` would yield `""`, and a feature-branch test
  could pass for the WRONG reason (`"" !== "main"` → abort) rather than because it detected a feature branch
  (Kieran P1-3). The new `revParse` handler must return a value the production code compares against the
  *resolved* default (e.g. `"main\n"` trimmed), not a hardcoded literal. Add the recovery regression tests
  (see Test Scenarios). RED-first: write the failing `localCommits > 0` → recovered test before editing
  `workspace-sync.ts`.

- `apps/web-platform/test/server/workspace-sync-no-pre-self-heal-error-mirror.test.ts`
  This source-guard asserts the `non_fast_forward` branch has no `reportSilentFallback` before the
  `selfHealNonFastForward` delegation. The branch structure is unchanged (the delegation still happens), so this
  guard should keep passing — verify it still holds after the edit; adjust the anchor strings only if the branch
  text moved.

## Files to Create

_None._ (All recovery logic lands in the existing `selfHealNonFastForward`; tests extend existing suites.)

## Observability

```yaml
liveness_signal:
  what: kb/sync recovery rate — `op:self-heal-recovered-diverged` warn events vs `op:self-heal-aborted-dirty`
  cadence: per POST /api/kb/sync on a diverged clone (event-driven, not polled)
  alert_target: Sentry (feature tag kb-route-helpers); Better Stack drain for the info breadcrumb
  configured_in: apps/web-platform/server/workspace-sync.ts (warnSilentFallback / reportSilentFallback emit sites)
error_reporting:
  destination: Sentry via reportSilentFallback (error) / warnSilentFallback (warn), pino → Sentry mirror (feature:pino-mirror)
  fail_loud: true — a genuine recovery FAILURE (branch/reset throws) keeps the existing error-level op:self-heal-failed mirror
failure_modes:
  - mode: HEAD on a feature branch with un-pushed commits (genuine agent work)
    detection: git rev-parse --abbrev-ref HEAD is a named branch ≠ default
    alert_route: op:self-heal-aborted-dirty (unchanged — preserved as the safe abort)
  - mode: detached HEAD with un-pushed commits (rev-parse → literal "HEAD")
    detection: git rev-parse --abbrev-ref HEAD == "HEAD"
    alert_route: op:self-heal-aborted-detached-head (distinct warn slug — observable, not silently bucketed)
  - mode: diverged on default branch, branch-aside + reset succeeds
    detection: warnSilentFallback op:self-heal-recovered-diverged (recovered:true)
    alert_route: Sentry warn (queryable recovery rate; does NOT page)
  - mode: branch-aside or reset git op throws (real failure)
    detection: catch → op:self-heal-failed (existing error path)
    alert_route: Sentry error (pages — genuine freeze)
logs:
  where: pino structured logs (log.warn/log.error) drained to Better Stack; Sentry for warn+
  retention: existing Better Stack + Sentry retention (unchanged)
discoverability_test:
  command: "Sentry issue search feature:kb-route-helpers op:self-heal-recovered-diverged (no ssh); vitest run apps/web-platform/test/kb-route-helpers.test.ts"
  expected_output: recovery events present after a diverged-clone sync; the recovery unit test passes
```

**Emit-site registration sweep (mandatory before adding new op slugs):** per the Sharp Edge on emit-site
coupling, before adding `self-heal-recovered-diverged` / `self-heal-aborted-detached-head`, grep for the
op-slug contract / alert filters that key on the existing self-heal slugs:
`grep -rn "self-heal-" apps/web-platform/infra/sentry/ apps/web-platform/**/*op-contract* 2>/dev/null` and any
`reportSilentFallback`/`warnSilentFallback` op registry. If an alert filters on a fixed set of self-heal op
slugs, add the new slugs there in the same PR (otherwise the new recovered/branch-unpushed events are dark).

## Acceptance Criteria

### Pre-merge (PR)

- [x] **AC1 — recovery, not abort, on a diverged default-branch clone with un-pushed commits.** With HEAD on the
  default branch and `git rev-list --count @{u}..HEAD` returning `> 0`, `selfHealNonFastForward` returns
  `{ ok:true, recovered:true }` (verified by the new `kb-route-helpers.test.ts` recovery test), NOT
  `{ ok:false, errorClass:"non_fast_forward" }`.
- [x] **AC2 — non-destructive ordering.** The unit test asserts the `git branch <recovery-branch> HEAD` call is
  issued BEFORE the `git reset --hard origin/<default>` call (branch-aside precedes reset), proving the un-pushed
  commits are preserved on a named ref before the default branch ref moves.
- [x] **AC3 — feature-branch work is still protected.** With HEAD on a NON-default *named* branch and
  `localCommits > 0`, `selfHealNonFastForward` still aborts (returns `{ ok:false }`, emits
  `op:self-heal-aborted-dirty`), and issues NO `branch`/`reset` — the branch-aside applies ONLY to default-branch
  divergence. The `revParse` harness handler MUST be explicit so this passes because a feature branch was detected,
  NOT via the empty-string fall-through (Kieran P1-3). Covered by a dedicated test row.
- [x] **AC4 — detached HEAD aborts observably.** With `rev-parse --abbrev-ref HEAD` returning the literal `"HEAD"`
  and `localCommits > 0`, `selfHealNonFastForward` aborts with the distinct `op:self-heal-aborted-detached-head`
  slug (NOT silently bucketed into `self-heal-aborted-dirty`), and issues no `branch`/`reset`. Covered by a test row.
- [x] **AC5 — observability preserved.** No raw `workspacePath` appears in any new `reportSilentFallback` /
  `warnSilentFallback` payload (it embeds the raw userId); the pseudonymized `userId`/`userIdHash` +
  `sanitizeGitStderr` handling is intact. Verified by a source grep in the test (no `workspacePath` key in the
  new emit payloads) AND by the no-pre-self-heal-error-mirror source guard still passing.
- [x] **AC6 — existing self-heal tests unchanged + zero-commit path issues no `branch`.** The ZERO-local-commit
  recovery, dirty-tree self-heal, and de-noise (no error mirror on recovered path) tests in
  `kb-route-helpers.test.ts` still pass, and the `localCommits === 0` scenario is asserted to keep emitting
  `op:self-heal-reset` and issue NO `branch` call (so the new branch-aside is never run on a benign phantom reset).
- [x] **AC7 — kb/sync route returns a recovered row.** `POST /api/kb/sync` on the recovered path appends a
  `kb_sync_history` row with `ok:true, recovered:true` (route already forwards `syncResult.recovered`; assert no
  regression via the existing `test/server/kb-sync-route.test.ts` or an added case).
- [x] **AC8 — emit-site sweep done.** Grep ran (`infra/sentry/`, op-contract tests). NO slug-keyed alert
  enumerates self-heal ops: `sentry_issue_alert.kb_sync_silent_failure` filters `op IS_IN ["kb-sync.unexpected"]`
  only, and both op-contract tests (`sentry-kb-sync-silent-failure-alert-op-contract`,
  `sentry-workspace-sync-health-alert-op-contract`) passed unchanged. The two new slugs
  (`self-heal-recovered-diverged`, `self-heal-aborted-detached-head`) mirror to Sentry via the
  `feature:kb-route-helpers` tag and are queryable; no filter darks them. No registration change needed.
- [x] **AC9 — typecheck + suite green.** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` passes, and
  `./node_modules/.bin/vitest run test/kb-route-helpers.test.ts test/server/workspace-sync-no-pre-self-heal-error-mirror.test.ts test/server/kb-sync-route.test.ts` passes.
- [x] **AC10 — GitHub issue filed.** Tracking issue #5425 filed (milestone "Post-MVP / Later", label `type/bug`);
  PR body uses `Closes #5425`.

### Post-merge (operator)

- [ ] **AC11 — production recovery confirmed.** After deploy, the trapped workspace's next `POST /api/kb/sync`
  (or the next auto-sync) emits `op:self-heal-recovered-diverged` and the workspace unblocks. Verify via Sentry
  issue search (feature:kb-route-helpers op:self-heal-recovered-diverged) — **no SSH**.
  `Automation: not feasible to assert in CI because it requires the live trapped workspace; verification is a
  read-only Sentry query, which the operator (or a one-shot Sentry MCP probe) runs post-deploy.`

## Test Scenarios

All in `apps/web-platform/test/kb-route-helpers.test.ts` (the `scriptGit` harness, line 550), RED-first:

1. **Recovery on default-branch divergence (AC1/AC2):** `scriptGit` with `pull → reject(NON_FF_STDERR)`,
   `revParse → "main\n"` (HEAD = default; the production code trims it), `revList → "2\n"` (un-pushed commits),
   `branch → resolve`, `reset → resolve`. Assert `{ ok:true, recovered:true }` AND assert call order: the
   `branch` invocation index < the `reset` invocation index (capture `mockGitWithAuth.mock.calls`). The `revParse`
   value must compare against the *resolved* default (returned by the `symbolic-ref` stub), not a hardcoded `"main"`,
   so the test passes for the right reason (Kieran P2-min).
2. **Feature-branch work still aborts (AC3):** same as (1) but `revParse → "feat-something\n"`. Assert
   `{ ok:false }` and that `reportSilentFallback` was called with `op:self-heal-aborted-dirty`; assert NO
   `reset`/`branch` was issued.
3. **Detached HEAD aborts observably (AC4):** same as (1) but `revParse → "HEAD\n"`. Assert `{ ok:false }`,
   that the abort emits `op:self-heal-aborted-detached-head`, and that NO `reset`/`branch` was issued.
4. **Observability payload has no raw workspacePath (AC5):** inspect the captured `reportSilentFallback` /
   `warnSilentFallback` args from scenarios (1)–(3); assert no `extra.workspacePath` key and that `userId`
   is present (pseudonymized at the helper boundary).
5. **ZERO-local-commit path unchanged + no branch (AC6):** the existing `revList → "0\n"` → reset → recovered test
   still passes verbatim, AND assert no `branch` call was issued and `op:self-heal-reset` was emitted (the new
   branch-aside is gated on `localCommits > 0`).

## Domain Review

**Domains relevant:** Engineering (CTO), Product (CPO — single-user-incident threshold)

### Engineering (CTO)

**Status:** to-be-assessed by the plan-review / deepen-plan engineering agents
**Assessment:** This is a server-side git-plumbing recovery in a single function with injected seams; no new
infra, no schema, no new vendor. The CTO-class concern is the **layer-mirroring** Sharp Edge: the new recovery
predicate (`localCommits > 0 && HEAD == default`) does NOT mirror an existing SQL/scheduler predicate, so the
load-bearing-sub-value question is moot here (this is the *only* layer that recovers a diverged-present clone).
The defense being relaxed is the abort-to-protect-work guard — the relaxation is **narrowed** (only default-branch
divergence, feature-branch work still protected) and adds a NEW preservation primitive (branch-aside), so it is a
safe, scoped relaxation per the defense-relaxation Sharp Edge.

### Product/UX Gate

**Tier:** none
**Decision:** N/A (no UI-surface file in Files to Create/Edit — pure server + test change). The UI impact is the
*removal* of a dead-end (the existing "Sync now" / Reconnect surfaces are unchanged in code; they simply stop
hitting the trap). No new page/component/modal. CPO sign-off is still required for the brand-survival threshold
(recovery-design review: branch-aside vs. destroy), but no `.pen` wireframe is needed — there is no new user-facing
surface.
**Agents invoked:** none (no UI surface)
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface)

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/placeholder text, or omits the
  threshold will fail `deepen-plan` Phase 4.6. (This plan's section is filled.)
- **Do NOT "fix" Reconnect to wipe-and-reclone a diverged clone.** That path is destructive — it would `rm -rf`
  the workspace and discard the un-pushed commits we must preserve. Reconnect's `repo_status==="ready"`
  short-circuit is correct *for this bug*; the recovery belongs in the kb/sync self-heal, not in Reconnect.
- **`git rev-parse --abbrev-ref HEAD` must be issued through `gitWithInstallationAuth`** (the injected seam) so the
  unit test can script it; do not shell out directly (breaks the seam + the test harness). **Trim the output**
  (`.toString().trim()`) before comparing — git appends a trailing newline. (Kieran P1-3.)
- **Detached HEAD returns the literal `"HEAD"`** from `--abbrev-ref`, not a branch name. Handle it as a distinct
  abort (`op:self-heal-aborted-detached-head`), never let it fall into the feature-branch or default-branch arm.
  (Kieran P1-2.)
- **The git wrapper has NO allowlist.** `gitWithInstallationAuth` is unguarded; the restrictive
  `ALLOWED_GIT_SUBCOMMANDS`/`FORBIDDEN_GIT_FLAGS` list in `session-sync.ts` gates only `runConnectedRepoGit`. Do
  NOT route the self-heal through `runConnectedRepoGit` — it would reject `--hard`/`branch` and break the existing
  reset. (Kieran P1-1.) The plan text must not call this an "allowlist."
- **Recovery branch name collisions:** use a timestamped name (`soleur/recovered-kb-sync-<unix-ms>`) so a second
  recovery on the same clone does not fail `git branch` with "already exists". A fixed name would re-trap on the
  second divergence.
- **Emit-site coupling:** adding new op slugs without the alert-filter sweep darks any `op IS_IN [...]` alert that
  enumerates self-heal slugs. Run the grep (Observability section) before adding the slugs.
- **Shallow-clone `@{u}` (Kieran P2-1):** the existing local-commit guard `rev-list --count @{u}..HEAD` (untouched
  by this fix) assumes the upstream tracking ref is configured (a normal `git clone` sets `branch.<default>.remote`
  / `merge`). If `@{u}` is unset, `rev-list` throws into the existing `catch` and emits `op:self-heal-failed`
  (fail-loud) rather than recovering — acceptable degradation, but note it: the new recovery covers the common
  trapped shape, not an upstream-less clone.
- **Pushing the recovery branch is deferred (DHH/code-simplicity).** The non-destructive guarantee is local
  (`branch` before `reset`); off-box durability for regenerable `knowledge-base/**`-only auto-sync content is a
  clean follow-up if an operator ever needs the branch promoted. Do not re-add the inline push or its second op
  slug without that requirement.

## Open Code-Review Overlap

None — verified no open `code-review`-labelled issue references `workspace-sync.ts`,
`repo-readiness-self-heal.ts`, or the kb/sync self-heal path (check at Step 2 file-list time with
`gh issue list --label code-review --state open --json number,title,body` + `jq --arg path ...`).

## Research Insights

### Design lineage — this fix continues the 2026-06-03 self-heal learnings

Two learnings are the direct lineage of the code this plan edits:

- **`knowledge-base/project/learnings/2026-06-03-self-heal-reset-must-gate-on-actual-repo-state-not-assumed-mirror.md`** —
  introduced the very `localCommits > 0 → abort` guard this plan extends. Its key insight: the workspace clone is
  NOT a read-only mirror (`session-sync.ts` auto-commits `knowledge-base/**` into it), so a blind `reset --hard`
  would destroy un-pushed work; the destructive op must gate on *runtime* state (`rev-list --count @{u}..HEAD`) and
  **fail-safe on ambiguity**. This plan keeps that gate and keeps the fail-safe for the genuinely-uncertain cases
  (feature branch, detached HEAD) — it only adds a recovery for the ONE case that is provably safe.
- **`knowledge-base/project/learnings/2026-06-03-self-heal-on-brand-path-only-acts-on-safe-symptom.md`** —
  "prefer do-nothing-when-uncertain over clever repair" at single-user-incident threshold; restrict a self-heal to
  the symptom whose "before" state holds no irrecoverable value. The rejected designs there were destructive
  (`rm .git` + re-clone, `checkout -f`).

**How this plan honors both while still recovering:** the do-nothing-when-uncertain principle is about *not
destroying* un-pushed work. Branch-aside (`git branch <recovery> HEAD` BEFORE `reset`) is **not** clever-repair of
the destructive class — it captures the un-pushed commits on a durable named ref *first*, so the subsequent
`reset --hard` discards nothing (the commit objects remain reachable from `<recovery-branch>`). The default-branch
gate + the feature-branch/detached-HEAD aborts preserve "do nothing when uncertain" for every case where the safe
move isn't provable. This is the narrow, scoped exception the learnings allow, not a regression of them.

### Precedent-diff (Phase 4.4) — the existing zero-commit self-heal is the canonical sibling

The codebase already has the canonical form for "gated `reset --hard origin/<default>` via the
installation-auth wrapper" at `workspace-sync.ts:221-225` (the `localCommits === 0` phantom-divergence reset). The
new recovery reuses that exact shape; the only additions are `git rev-parse --abbrev-ref HEAD` (branch detection)
and `git branch <recovery> HEAD` (preservation) BEFORE the reset. No novel git primitive is introduced. The
default branch is resolved via the existing `resolveDefaultBranch` (`git symbolic-ref --short refs/remotes/origin/HEAD`),
never assumed `main`.

### Verify-the-negative (Phase 4.45) — all four safety claims CONFIRMED (live grep)

| Claim | Verdict | Evidence |
| --- | --- | --- |
| `git branch <name> HEAD` keeps commits reachable after `reset --hard` (no gc risk) | **confirms** | No application code runs `git gc` / `git reflog expire` / `git branch -D` / `git clean` (zero hits in `apps/web-platform/server/*.ts`). A named branch ref is a gc-root even in a shallow `--depth 1` clone (`ensure-workspace-repo.ts:220`). The single diverged commit is preserved. |
| Current code has NO branch check — plan ADDS `rev-parse` | **confirms** | `workspace-sync.ts:191-217` aborts on `localCommits > 0` regardless of branch; no `rev-parse`/`symbolic-ref HEAD` today. |
| `gitWithInstallationAuth` is unguarded; allowlist gates only `runConnectedRepoGit` | **confirms** | `git-auth.ts:266-314` is a direct `execFileAsync("git", ...)` with no allowlist; `session-sync.ts:39-90` enforces `ALLOWED_GIT_SUBCOMMANDS`/`FORBIDDEN_GIT_FLAGS` only in `runConnectedRepoGit`. The existing `reset --hard` at `workspace-sync.ts:221` already uses `gitWithInstallationAuth`, proving `--hard` is permitted there. |
| Stranded auto-sync commits are `knowledge-base/**`-only | **confirms** | `session-sync.ts:28` — `ALLOWED_AUTOCOMMIT_PATHS = [/^knowledge-base\//]`; `syncPull`/`syncPush` only `git add --` the allowlisted subset (`getAllowlistedChanges`, lines 103-131, 500-516, 568-585). |

### Test-compatibility (Phase 4 enumeration)

The only test that pins the current behavior is `apps/web-platform/test/kb-route-helpers.test.ts` (the `scriptGit`
harness). No test currently asserts the `localCommits > 0 → {ok:false}` *abort outcome* as a hard contract (the
suite covers the ZERO-commit recovery, the dirty-tree self-heal, and the de-noise no-error-mirror cases). So the
behavioral change is additive — extend the harness + add the recovery scenarios; no existing assertion needs to be
inverted. (Confirmed by grep: `localCommits` / `self-heal-aborted-dirty` appear only in that one test file.)

## References

- `apps/web-platform/server/workspace-sync.ts:165-255` — `selfHealNonFastForward` (the abort to replace)
- `apps/web-platform/server/repo-readiness-self-heal.ts:120-130` — `.git`-absent `canRecover` gate
- `apps/web-platform/server/ensure-workspace-repo.ts:108-176` — `.git`-present re-clone no-op
- `apps/web-platform/server/session-sync.ts:568-605` — `syncPush` auto-commit + bare `git push` (trigger)
- `apps/web-platform/server/session-sync.ts:28` — `ALLOWED_AUTOCOMMIT_PATHS = [/^knowledge-base\//]`
- `apps/web-platform/components/repo/use-reconnect.ts` — `attemptResetup` `repo_status==="ready"` short-circuit
- `apps/web-platform/app/api/repo/setup/route.ts` + `apps/web-platform/server/workspace.ts:151` — wipe-and-reclone
- `apps/web-platform/app/api/kb/sync/route.ts` — `POST /api/kb/sync` → `syncWorkspace` → recovered-row write
- `apps/web-platform/test/kb-route-helpers.test.ts:550` — `scriptGit` harness (where recovery tests go)
- `apps/web-platform/test/server/cc-dispatch-repo-self-heal.test.ts:120` — existing `.git`-present honest-block test
- `apps/web-platform/server/git-auth.ts:211` — `sanitizeGitStderr`; `observability.ts:37` — `hashUserId`
- `apps/web-platform/server/git-auth.ts:266-314` — `gitWithInstallationAuth` (unguarded wrapper)
- `apps/web-platform/server/session-sync.ts:39-90` — `ALLOWED_GIT_SUBCOMMANDS`/`FORBIDDEN_GIT_FLAGS` (gates only `runConnectedRepoGit`)
- `knowledge-base/project/learnings/2026-06-03-self-heal-reset-must-gate-on-actual-repo-state-not-assumed-mirror.md` — the abort-guard this fix extends
- `knowledge-base/project/learnings/2026-06-03-self-heal-on-brand-path-only-acts-on-safe-symptom.md` — do-nothing-when-uncertain at single-user-incident threshold
