---
title: "Fix: C4 Code-tab Save does not persist — model.c4 and the diagram revert after Save"
type: fix
date: 2026-06-12
lane: cross-domain
brand_survival_threshold: none
---

# Fix: C4 Code-tab Save does not persist — `model.c4` and the diagram revert after Save

## Enhancement Summary

**Deepened on:** 2026-06-12

### Key Improvements

1. **Verify-the-negative pass confirmed all 6 load-bearing claims** against live
   code, including the decisive one: on a 500 `SYNC_FAILED` the editor already
   throws BEFORE `onSaved` (`c4-shared.tsx:416`), shows the error inline
   (`:497-499`), and does NOT reload — so **F-B is already satisfied for the 500
   path**. The real silent-revert is the **200-but-stale-clone** case (H2), which
   F-A1 targets. This narrows the fix.
2. **Committed to F-A1 + F-B as the mandatory, hypothesis-independent fix**
   (DHH + Kieran + architecture-strategist all converged): keeping the client's
   just-saved `draft` instead of round-tripping through a stale `reload()` cures
   H1/H2/H4 the same way. **F-A2 demoted** from mandatory to a contingency
   (Alternatives) — the diagram half is already covered by the Layer-1 staleness
   banner (#4963). Phase 0 is narrowed to a dogfood-time confirmation that sizes
   the F-C deferral, not a gate that blocks the whole fix.
3. **Promoted H3 (concurrency) from open-question to a finding** with a concrete
   TOCTOU: `withWorkspacePermissionLock` exists but guards only
   `.claude/settings.json` — NO mutex serializes working-tree git ops, so the
   self-heal `rev-list→reset` (`workspace-sync.ts:191→221`) has a window where a
   concurrent `session-sync` commit can be destroyed, violating the
   "never destroy un-pushed work" invariant. Tracked alongside F-C.
4. **Scoped F-C as a workspace-wide liveness gap** (best-effort `session-sync`
   push leaves the clone perpetually un-fast-forwardable, degrading EVERY sync
   consumer — not C4-cosmetic), referencing the kb-sync-stale post-mortem.

### New Considerations Discovered

- **F-A1 alone converts silent-revert into persistent diagram-staleness** when
  the clone is diverged (source shows new text, diagram shows old layout). This
  is honest (Layer-1 banner) but split-brain; the strategic fix that resolves
  both at the authoritative read layer is F-A2-server (SHA-aware / canonical
  GitHub read on GET `/project`). Ship F-A1 as the correctness floor; reach for
  F-A2 only if dogfooding proves the banner insufficient.

## Overview

In the LikeC4 C4 visualizer Code-tab editor (web-platform), editing a `.c4`
source (e.g. changing `Founder` → `Founder TEST` in `model.c4`) and clicking
**Save** results in: (a) the diagram does not change, AND (b) the `.c4` source
itself **reverts to its prior state** — the editor reloads the old text. The
edit is lost.

This is materially different from the previously-shipped Layer-1/Layer-2 bug
(`2026-06-05-fix-likec4-code-editor-save-noop-plan.md`, PRs #4963 + #4965). That
bug was "the source persists but the *diagram* stays stale." The symptom here is
that **the source itself does not survive** — the Code tab shows the pre-edit
text after reload. That points at the **workspace-sync / reconcile layer**
clobbering or failing to advance the on-disk clone, not at the render layer.

> Sharp Edge (plan-time): A plan whose `## User-Brand Impact` section is empty,
> contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail
> `deepen-plan` Phase 4.6. This plan's section is filled below.

## Premise Validation

All cited artifacts verified live on the branch
`feat-one-shot-c4-save-not-persisting`:

- **The feature is built and previously fixed, not absent.** `git log` confirms
  the visualizer + Save shipped (#4883, #4925, #4926) and the save-noop bug was
  fixed in two layers: **#4963 (Layer 1 honest UX)** and **#4965 (Layer 2
  out-of-process re-render)**, hardened by **#4967** (empty-render honesty /
  atomic publish), **#4979** (render off-tree, stop reconcile dirty-tree churn),
  **#5007** (shared-link render), **#5027** (fullscreen). So this is a
  **regression / residual failure mode**, NOT a never-built feature and NOT the
  same diagram-staleness bug #4963/#4965 already closed.
- **The write/read paths exist and were read end-to-end:**
  `apps/web-platform/server/c4-writer.ts` (`writeC4Diagram` + `rerenderAndCommit`),
  `apps/web-platform/server/c4-render.ts` (`renderC4Model`, off-tree),
  `apps/web-platform/server/workspace-sync.ts` (`syncWorkspace` +
  `selfHealNonFastForward`),
  `apps/web-platform/app/api/kb/c4/[...path]/route.ts` (PUT),
  `apps/web-platform/app/api/kb/c4/project/route.ts` (GET project),
  `apps/web-platform/components/kb/c4-shared.tsx`,
  `apps/web-platform/server/session-sync.ts` (auto-commit/push into the same clone).
- **Falsified hypothesis (write-vs-read clone mismatch):** I initially suspected
  the PUT route wrote the *caller's own* clone while GET read the *active*
  workspace clone (ADR-044). **This is FALSE.** `authenticateAndResolveKbPath`
  (`kb-route-helpers.ts:98,120`) already resolves `ctx.userData.workspace_path`
  via `resolveActiveWorkspaceKbRoot`, the SAME resolver the GET `/project` route
  uses (`project/route.ts:48`). Both read and write operate on the active
  workspace clone. The revert is NOT a path mismatch.
- **Falsified hypothesis (render dirties the tree):** Also FALSE post-#4976/#4979.
  `renderC4Model` renders to a `mkdtemp` temp dir and RETURNS bytes
  (`c4-render.ts:155-205`); it never writes the tracked `model.likec4.json`. The
  per-save dirty-tree churn the in-place publish used to cause is gone.

**Conclusion of premise validation:** the revert is a **`syncWorkspace`
failure-or-abort on the shared active-workspace clone**, leaving the on-disk
`.c4` source un-advanced (so the editor's `reload()` re-reads the pre-edit text).
The exact trigger MUST be captured by a live reproduction (Phase 0) before
choosing the fix — see Hypotheses. Do not pin the cause without the repro
(`hr` write-path: "internally-consistent claim is a hypothesis to falsify").

## Research Reconciliation — Spec vs. Codebase

| Claim (from bug report) | Reality (code-verified) | Plan response |
|---|---|---|
| "edit the code … does not save even after clicking Save" | The PUT commits the `.c4` to GitHub (Contents API) and returns 200 with `commitSha`; the *editor reload* re-reads the **on-disk clone**, which is stale if `syncWorkspace` failed/aborted | Fix targets the sync/reconcile clone-advance, not the commit |
| "the diagram does not change" | Same root cause: GET `/project` reads `dump` + `sources` from the same clone; if the clone didn't advance, both are stale | One fix addresses both symptoms |
| "model.c4 reverts back to the previous state" | The Code tab is populated from GET `/project` `sources`, read from `<active-workspace clone>/knowledge-base/engineering/architecture/diagrams/*.c4`; a non-advanced clone returns the old text | Confirmed: revert = clone not advanced, NOT a discarded commit |
| Implied: "the commit was lost" | Unverified — the commit likely DID land on GitHub `origin`; the clone just never pulled it. Phase 0 repro confirms via `git log origin/<branch>` | Repro distinguishes "commit lost" from "clone stale" |

## Hypotheses (root cause — confirm via Phase 0 repro before fixing)

The save path is (`c4-writer.ts:113-163`): commit `.c4` to `origin` via Contents
API → `syncWorkspace(op:"manual")` → (for `.c4`) re-render → commit
`model.likec4.json` → `syncWorkspace(op:"manual")` again. The editor then
`reload()`s GET `/project`, which reads `sources` + `dump` from the **on-disk
clone**. The revert means the clone's working tree does NOT reflect the commit.
Ranked candidates:

1. **H1 — Diverged clone, self-heal aborts on un-pushed local commits
   (PRIME).** The active-workspace clone (`<WORKSPACES_ROOT>/<workspace_id>`) is
   **shared** with agent sessions: `session-sync.ts` auto-commits
   (`["commit",…]` at :513/:581) and pushes (`["push"]` at :602) into it. If a
   prior push failed (network, auth, race), the clone holds **un-pushed local
   commits**. Then the C4 save's `git pull --ff-only` (`workspace-sync.ts:107`)
   fails → `classifyGitSyncError` → `non_fast_forward` → `selfHealNonFastForward`
   computes `git rev-list --count @{u}..HEAD` (:191) > 0 → **aborts without
   resetting** (:198-218), returns `ok:false`. `writeC4Diagram` returns
   `SYNC_FAILED`. The on-disk `.c4` is never advanced → reload shows old text.
   **This is deterministic-per-save while the clone stays diverged**, matching
   "does not save even after editing" (every attempt fails the same way).
   *Verified (deepen-plan):* on a 500 `SYNC_FAILED`, `c4-shared.tsx:save()`
   throws at `:416` BEFORE `onSaved`, shows the error inline (`:497-499`), and
   does NOT call `reload()` — so the editor preserves the draft and F-B is
   **already satisfied for the 500 path**. The user-visible silent revert is
   therefore the **200-but-stale-clone** path (H2), not the 500 path.

2. **H2 — GitHub Contents API → fetch propagation lag (INTERMITTENT).** The
   commit lands on `origin`, but the immediately-following `git pull --ff-only`
   hits a replica whose branch ref does not yet include the commit. `--ff-only`
   succeeds as a no-op (already up to date with the stale ref) and the file is
   not advanced. No error is raised; the save reports success but the reload
   shows the old text. This is timing-dependent, not every-save, so it fits
   "sometimes" but not a hard deterministic revert. (Pairs with the
   Layer-2 double-commit: two commits + two pulls widen the lag window.)

3. **H3 — Concurrent working-tree git ops with NO mutex (FINDING, not just a
   hypothesis — confirmed in deepen-plan).** `withWorkspacePermissionLock`
   (`server/workspace-permission-lock.ts`) exists but its ONLY consumer is
   `agent-runner.ts patchWorkspacePermissions` (serializing `.claude/settings.json`)
   — it wraps **no** `git pull/reset/commit/push`. `syncWorkspace` and
   `session-sync` acquire no lock; `workspace-reconcile-on-push`'s Inngest
   `concurrency limit:1` (`workspace-reconcile-on-push.ts:402-405`) serializes
   only reconcile-vs-reconcile for the same installation and gives **zero**
   exclusion against the HTTP/WS git paths (those run in the Next/cc-dispatcher
   worker, outside the Inngest runtime). So THREE actors can mutate one working
   tree uncoordinated: (1) `writeC4Diagram`'s two `op:"manual"` syncs, (2)
   `session-sync` auto-commit/push, (3) reconcile-on-push `op:"push"`. **TOCTOU:**
   between the self-heal `git rev-list --count @{u}..HEAD` (`workspace-sync.ts:191`)
   and the `git reset --hard` (`:221`), a concurrent `session-sync` commit can
   make the "0 un-pushed commits" reading stale and the reset destroys a commit
   that did not exist at check-time — violating the "never destroy un-pushed
   work" invariant. This is a residual even after F-A1/F-B; track it with F-C
   (same shared-clone-invariant blast radius). The fix is to route all
   working-tree git mutations for a `workspacePath` through the existing
   `withWorkspacePermissionLock` primitive.

4. **H4 — `--ff-only` cannot advance because the clone's local HEAD is the
   Contents-API commit's *parent on a different ref*.** If the Contents API
   commits against the repo default branch but the clone tracks a different
   upstream, the pull is a no-op. Confirm the clone's `@{u}` matches the branch
   the Contents API writes to.

**Per the network-outage / git-diagnosis discipline:** the fix for H1 must NOT
propose an ungated `reset --hard` (would destroy un-pushed agent-session work —
see learning `2026-06-03-self-heal-reset-must-gate-on-actual-repo-state-not-assumed-mirror.md`).
The diverged-clone state is the *symptom*; the fix is to make the C4 save
**resilient to a stale/diverged clone** (e.g. read the just-committed bytes the
writer already holds, rather than depending on the clone pull), and/or to
**surface the failure honestly** instead of reverting silently.

## Proposed Solution

**The mandatory fix is F-A1 + F-B, committed now — it is hypothesis-independent**
(it cures H1/H2/H4 the same way: a successful write must not be invalidated by a
downstream cache-sync failure). It follows the same insight #4976 applied to the
re-render: **do not depend on the reconcile pull to make just-saved content
visible** — the GitHub commit is the source of truth, the on-disk clone is a
cache, and a cache-coherence failure must not present as data loss.

- **F-A1 (MANDATORY) — optimistic editor apply on a 200.** Have the client keep
  the saved source it just sent (its `draft`) instead of round-tripping through a
  possibly-stale `reload()` that re-reads the on-disk clone. On a successful PUT,
  the editor reflects the saved text regardless of whether the clone advanced.
  This removes the **200-but-stale-clone** revert (the actual user-visible bug).
  The diagram `dump` still depends on the clone advancing; when it lags, surface
  honestly via the **already-shipped Layer-1 staleness banner** (#4963) — do not
  build a new read path for the diagram half.
- **F-B (MANDATORY baseline; already partly satisfied).** On a non-2xx the editor
  MUST show a distinct, honest error and MUST NOT reload to a stale source.
  *Verified:* `c4-shared.tsx:save()` already throws at `:416` before `onSaved`,
  renders the error inline (`:497-499`), and does not `reload()` on failure — so
  the **500 path is already honest**. F-B's remaining work is only to ensure the
  F-A1 optimistic-apply change does not regress this (a vitest test pins it).
- **F-C (DEFERRED — file a tracking issue).** The true root cause of H1: a
  best-effort `session-sync` push that swallows failures leaves the shared clone
  with un-pushed commits, after which EVERY `git pull --ff-only` consumer (C4
  save, KB delete, webhook reconcile) aborts — a **workspace-wide liveness gap**,
  not a C4-cosmetic one. Plus the H3 `rev-list→reset` TOCTOU. Defer because it
  touches the shared reconcile invariant (largest blast radius) and the fix is a
  real reconciliation design (recover un-pushed commits, not blind-reset). The
  tracking issue MUST scope it workspace-wide and reference
  `kb-sync-stale-no-manual-recovery-postmortem.md`.

**F-A2 is NOT in the mandatory set** — see Alternatives. It is the *strategic*
read-layer fix (SHA-aware / canonical GitHub read on GET `/project`, resolving
both source AND diagram at the authoritative layer), but the diagram half is
already covered honestly by the Layer-1 banner, so F-A2 is a contingency reached
for only if dogfooding proves the banner insufficient.

**Phase 0 (narrowed):** capture the live git state to confirm the failure mode
and **size the F-C tracking issue** — it does NOT gate the F-A1/F-B fix (which is
correct for all hypotheses). Record: `git log origin/<branch>` shows the commit
landed; `git -C <clone> rev-list --count @{u}..HEAD` / `git status` shows why the
pull didn't advance; the returned `SyncWorkspaceResult`.

## User-Brand Impact

**If this lands broken, the user experiences:** the C4 Code-tab Save continues to
silently discard edits — the user types a change, clicks Save, and the editor
snaps back to the old text with no diagram update and (per H1) possibly no error,
making the entire editor feel non-functional.

**If this leaks, the user's data / workflow is exposed via:** N/A — no new data
surface. The write path already commits only within the `isC4DiagramPath`
scope-guarded diagrams dir; this fix touches the sync/visibility path and UI
copy, not auth, scope, or PII.

**Brand-survival threshold:** `none`

`threshold: none, reason: the touched paths (server/c4-writer.ts, server/workspace-sync.ts, app/api/kb/c4/*, components/kb/c4-shared.tsx) change clone-visibility/retry and editor-reload behavior on the existing isC4DiagramPath-scoped write path; they add no new data exposure, auth, scope, or PII surface.`

## Observability

```yaml
liveness_signal:
  what:            "logger.info event:c4_write (source committed) + event:c4_rerender (diagram regenerated) in c4-writer.ts; on sync failure the existing reportSilentFallback(op:workspace-sync-manual / self-heal-aborted-dirty) fires"
  cadence:         "per-save (user-triggered)"
  alert_target:    "Sentry web-platform issue (operator email on error spike) via existing reportSilentFallback mirror"
  configured_in:   "apps/web-platform/server/c4-writer.ts + apps/web-platform/server/workspace-sync.ts (existing logger + reportSilentFallback/warnSilentFallback)"

error_reporting:
  destination:     "Sentry web-platform via SENTRY_DSN; existing reportSilentFallback in workspace-sync.ts (self-heal-aborted-dirty / self-heal-failed / sync_failed) and c4-writer.ts (c4-rerender ops)"
  fail_loud:       "PUT returns non-2xx {error,code} (SYNC_FAILED/SHA_MISMATCH/GITHUB_API_ERROR); the fix MUST make the editor render that error distinctly and NOT reload to the stale source"

failure_modes:
  - mode:          "Diverged clone aborts self-heal (un-pushed local commits) → source committed but clone never advances → editor reverts"
    detection:     "existing reportSilentFallback op:self-heal-aborted-dirty in workspace-sync.ts; add an event tying it to the c4 save so it is greppable per-save"
    alert_route:   "Sentry issue -> operator email"
  - mode:          "GitHub Contents API commit not yet visible to the fetch replica (propagation lag) → pull --ff-only no-ops → stale clone"
    detection:     "new: after resync, assert the committed SHA is present on the clone (git rev-parse/cat-file); log+mirror when absent"
    alert_route:   "Sentry issue -> operator email"
  - mode:          "Editor silently reloads stale source on a non-2xx PUT (masks the SYNC_FAILED error)"
    detection:     "vitest on c4-shared.tsx save flow: a 500 SYNC_FAILED must show an error and NOT overwrite the editor with reloaded sources"
    alert_route:   "caught pre-merge by tests"

logs:
  where:           "pino structured logs (logger.info/error in c4-writer.ts + workspace-sync.ts) -> container stdout -> existing aggregator (Better Stack drain)"
  retention:       "per existing web-platform log retention"

discoverability_test:
  command:         "cd apps/web-platform && ./node_modules/.bin/vitest run test/c4-code-panel.test.tsx test/c4-writer-rerender.test.ts"
  expected_output: "tests assert: (a) on PUT 200 the editor reflects the saved source without depending on a stale clone reload; (b) on PUT 500 SYNC_FAILED the editor shows an error and does NOT revert to reloaded sources"
```

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **Phase 0 repro captured (sizes F-C, does NOT gate F-A1/F-B):** the PR body
      records which hypothesis (H1–H4) reproduces, with the observed git state
      (`git log origin/<branch>` shows the commit landed; `git -C <clone> rev-list
      --count @{u}..HEAD` / `git status` shows why the pull didn't advance) and the
      returned `SyncWorkspaceResult`. Drives the F-C tracking-issue scope.
- [ ] Editing a `.c4` source, clicking Save, and a **successful** PUT (200) leaves
      the **edited text visible in the Code tab** (not reverted) — verified by a
      vitest test that does NOT rely on the on-disk clone having advanced
      (optimistic apply of the saved content, or GitHub-canonical read).
- [ ] On a PUT that returns **500 `SYNC_FAILED`**, the editor shows a distinct,
      honest error and does **NOT** overwrite the editor with a stale reloaded
      source (no silent revert). Verified by a vitest test on `c4-shared.tsx`.
- [ ] No regression: the `.c4` source still commits to GitHub via
      `writeC4Diagram` within the `isC4DiagramPath` scope guard; the re-render +
      `model.likec4.json` commit path (#4965/#4967/#4976) is unchanged or
      improved, never weakened.
- [ ] **No ungated `reset --hard`** is added to any save/sync path — the
      diverged-clone guard (`@{u}..HEAD == 0`) is preserved; un-pushed
      agent-session work is never destroyed
      (learning `2026-06-03-self-heal-reset-must-gate-on-actual-repo-state-not-assumed-mirror.md`).
- [ ] `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean; vitest
      suite green (`c4-code-panel.test.tsx`, `c4-writer-rerender.test.ts`,
      `c4-workspace.test.tsx`, and any new sync-resilience test).

### Post-merge (operator)

- [ ] **Live dogfood** (the only manual step): on the dev-cohort deployment, open
      a C4 KB page → Code tab → change a label in `model.c4` → Save → confirm the
      edit persists in the editor AND (after re-render) the diagram updates; if a
      `SYNC_FAILED` is encountered, confirm the honest error renders.
      *Automation: not feasible because it exercises the live GitHub-clone
      reconcile against the operator's actual workspace clone state, which is the
      exact condition the bug depends on; a synthetic CI clone cannot reproduce a
      perpetually-diverged prod clone. Bounded to one human dogfood per the
      dev-cohort flag.*

## Test Scenarios

- Given an edited `.c4` source and a PUT that returns 200, when the save
  completes, then the Code tab shows the edited text (no revert), independent of
  whether the on-disk clone advanced.
- Given a PUT that returns 500 `SYNC_FAILED`, when the save completes, then the
  editor shows a distinct error and retains the user's edited text (does not snap
  to a reloaded stale source).
- Given a diverged clone with un-pushed local commits, when a C4 save runs, then
  `selfHealNonFastForward` still aborts without resetting (un-pushed work
  preserved) AND the save surfaces an honest error rather than a silent revert.
- Regression: given a clean fast-forwardable clone, when a `.c4` save runs, then
  the source commits, the diagram re-renders (#4965/#4967), and the editor + GET
  `/project` reflect the change.

## Dependencies & Risks

- **Risk:** the fix must not weaken the diverged-clone guard or introduce a path
  that destroys un-pushed agent-session work (shared clone invariant). Any
  retry-pull must be bounded (timeout/attempt cap) per the "pin a timeout on
  network calls in loops" learning.
- **Risk:** GitHub Contents API propagation lag is intermittent — F-A1 (make the
  save self-sufficient for the source) covers both H1 and H2 because it does not
  depend on the clone advancing at all. The diagram half remains eventually-
  consistent and is surfaced honestly by the Layer-1 banner.
- **Risk (residual, tracked in F-C):** even after F-A1/F-B, the H3 working-tree
  TOCTOU and the perpetual-divergence liveness gap persist — they are NOT closed
  by this PR and MUST be captured in the F-C tracking issue.
- **Risk:** F-A1 must not show edited text that did NOT commit — the optimistic
  apply fires ONLY on a confirmed 200 (commit landed on `origin`), never on a
  non-2xx. The vitest test pins both paths.
- **Dependency:** reuses the existing GitHub Contents API + `syncWorkspace` paths
  in `c4-writer.ts`; the optimistic-apply reuses the content the client already
  sent (no new network call).

## Network-Outage Deep-Dive

Phase 4.5 fired on the `timeout` / propagation-lag substrings, but this is a
**git-clone reconcile** issue, not an L3/L7 connectivity outage:

- **L3 firewall / egress IP:** N/A — the failure is an in-process `git pull
  --ff-only` against an already-authenticated GitHub remote on a healthy
  container, not a blocked connection. No firewall hypothesis applies.
- **L3 DNS / routing:** N/A — GitHub reachability is proven by the *successful*
  Contents API commit that immediately precedes the failing pull.
- **L7 TLS / proxy:** N/A — same auth/transport as the successful commit.
- **L7 application (the actual layer):** the `git pull --ff-only` aborts on a
  diverged/dirty clone (H1) or no-ops against a lagging replica ref (H2). The
  "timeout" references in this plan are the in-code `RENDER_TIMEOUT_MS=25s` ceiling
  and a (deferred) bounded retry budget — not a network handshake timeout. No
  connectivity verification artifact is required.

## Alternative Approaches Considered

| Approach | Mechanism | Verdict |
|---|---|---|
| **F-A1. Optimistic editor apply on 200** | Client keeps the saved source it sent; diagram staleness uses the Layer-1 banner if the clone lags | **MANDATORY (chosen).** Removes the source revert regardless of clone state; smallest blast radius; faithful to #4976 (cache-coherence failure ≠ data loss). |
| **F-B. Honest error, no silent revert** | On non-2xx, show the error and don't reload to a stale source | **MANDATORY baseline (already partly satisfied at `c4-shared.tsx:416`).** F-A1 must not regress it. |
| **F-A2. SHA-aware / canonical GitHub read on GET `/project`** | Server resolves sources+dump against the just-committed SHA or reads `origin` when the clone is stale | **Contingency, NOT mandatory.** The *strategic* read-layer fix (resolves source AND diagram at the authoritative layer), but the diagram half is already honest via the Layer-1 banner; adds GitHub-read latency / retry budget. Reach for it only if dogfooding shows the banner insufficient. |
| **F-C. Fix shared-clone divergence + working-tree git lock (session-sync recovery)** | Make failed-push state recoverable; route working-tree git ops through `withWorkspacePermissionLock` to close the `rev-list→reset` TOCTOU | **DEFER to a workspace-wide tracking issue.** True root cause of H1 + the H3 concurrency finding; largest blast radius (shared reconcile invariant); fix is a real reconciliation design, not a one-liner. |
| **Ungated `reset --hard` in the save sync** | Force the clone to `origin` on every save | **Rejected.** Destroys un-pushed agent-session work; violates the gated-self-heal invariant. |

**F-C deferral (required tracking issue):** file an issue scoping the shared-clone
divergence-recovery gap as a **workspace-wide liveness failure** (a clone left
with un-pushed commits by a best-effort `session-sync` push degrades EVERY
`git pull --ff-only` consumer — C4 save, KB delete/rename/upload, webhook
reconcile — not just C4), PLUS the H3 `rev-list→reset` TOCTOU (route working-tree
git ops through `withWorkspacePermissionLock`). Reference
`knowledge-base/engineering/operations/post-mortems/kb-sync-stale-no-manual-recovery-postmortem.md`
and the milestone from `knowledge-base/product/roadmap.md`. Re-evaluation
criterion: any Sentry `self-heal-aborted-dirty` recurrence or a second
clone-stuck report.

## Files to Edit

Committed to F-A1 + F-B, the edit surface collapses to the client save flow plus
tests (`workspace-sync.ts` and `project/route.ts` come OFF the list — they belong
to the deferred F-A2/F-C). Verify whether the PUT already echoes enough
(`commitSha`) for the client to apply optimistically before editing the route.

- `apps/web-platform/components/kb/c4-shared.tsx` — `C4CodePanel` save flow:
  on a 200, keep the client's `draft` (optimistic apply) instead of resetting it
  from a possibly-stale `reload()` (F-A1); preserve the existing non-2xx
  error-inline-no-reload behavior at `:416/:497-499` (F-B regression guard).
- `apps/web-platform/server/c4-writer.ts` — only if needed to return the written
  `content` to the route for the client to apply, and to tie a greppable
  observability event to the diverged-clone abort (the `SYNC_FAILED`/
  `self-heal-aborted-dirty` per-save signal). No retry loop here.
- `apps/web-platform/app/api/kb/c4/[...path]/route.ts` — only if the client needs
  the written content echoed back for optimistic apply (likely `commitSha`/the
  already-sent body suffices).
- `apps/web-platform/test/c4-code-panel.test.tsx` — assert no-revert on 200 and
  honest-error-no-revert on 500 `SYNC_FAILED`.
- `apps/web-platform/test/c4-writer-rerender.test.ts` — assert the writer returns
  the content needed for optimistic apply (if that edit is made).
- `apps/web-platform/test/c4-workspace.test.tsx` — regression on the workspace
  save flow.

## Files to Create

- None. (The deferred F-A2, if ever taken, would add a canonical GitHub-read
  helper under `apps/web-platform/server/` with a colocated test — out of scope
  for this PR.)

## Open Code-Review Overlap

To be populated at /work time: run
`gh issue list --label code-review --state open --json number,title,body --limit 200`
and grep the bodies for `c4-shared.tsx`, `c4-writer.ts`, `workspace-sync.ts`,
`app/api/kb/c4/`. Record matches with an explicit fold-in / acknowledge / defer
disposition; record `None` if the grep is empty.

## Domain Review

**Domains relevant:** Product (UI behavior)

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none
**Skipped specialists:** none — this fix modifies the existing C4 Code-tab Save
behavior (editor reload + error copy). It creates no new page, route, or
interactive surface (no new `components/**/*.tsx`, `app/**/page.tsx`, or
`app/**/layout.tsx`), so the mechanical UI-surface override resolves to ADVISORY.
**Pencil available:** N/A (no new UI surface)

**Wireframe gate (`wg-ui-feature-requires-pen-wireframe` / deepen-plan Phase
4.9):** The glob superset matches `components/kb/c4-shared.tsx`, but the change
renders **zero new pixels** — F-A1 changes only *when* the editor reloads its
`draft` (it stops resetting from a stale `reload()` on a 200), and F-B is an
already-shipped error-inline path. No new banner/overlay/modal/toast/component,
no layout change, no new interactive surface — squarely the gate's **Excluded**
"pure copy / behavior tweak, no structural/layout change" carve-out. This is the
**accepted precedent** set by `2026-06-05-fix-likec4-code-editor-save-noop-plan.md`,
which touched the same `c4-shared.tsx` Save flow and resolved via the same
carve-out with no `.pen`. If implementation deviates to a NEW visual component,
the gate re-fires and a `.pen` must be produced under
`knowledge-base/product/design/kb-viewer/`.

#### Findings

The change corrects when/whether the editor reloads its source and how a sync
failure is surfaced. UX risk is confined to the error-copy and the
optimistic-apply correctness (the editor must not show edited text that did NOT
commit) — covered by the both-outcomes (200 / 500) test requirement in the
Acceptance Criteria.

## Infrastructure (IaC)

**No infrastructure.** Pure code change against the already-provisioned
web-platform — edits `components/kb/c4-shared.tsx`, optionally
`server/c4-writer.ts` + `app/api/kb/c4/[...path]/route.ts`, and tests. No new
server, service, secret, vendor, or persistent process. The `likec4` CLI
re-render path (out-of-process) and `workspace-sync.ts` are unchanged by this PR.

## References & Research

### Internal References

- `apps/web-platform/server/c4-writer.ts` — `writeC4Diagram` (commit + sync +
  re-render), `rerenderAndCommit`
- `apps/web-platform/server/workspace-sync.ts` — `syncWorkspace` (`git pull
  --ff-only` at :107) + `selfHealNonFastForward` (gated reset at :221, abort on
  un-pushed commits at :198-218)
- `apps/web-platform/server/c4-render.ts` — `renderC4Model` (off-tree, returns
  bytes, #4976)
- `apps/web-platform/app/api/kb/c4/[...path]/route.ts` — PUT route
- `apps/web-platform/app/api/kb/c4/project/route.ts` — GET project (reads
  sources/dump from the on-disk clone at :69,:118)
- `apps/web-platform/server/kb-route-helpers.ts:98,120` — `workspace_path`
  resolves via `resolveActiveWorkspaceKbRoot` (same as GET — falsifies the
  path-mismatch hypothesis)
- `apps/web-platform/server/session-sync.ts:513,581,602` — auto-commit/push into
  the SAME active-workspace clone (the divergence source for H1)
- `apps/web-platform/components/kb/c4-shared.tsx` — `C4CodePanel`, `useC4Project`,
  reload/`onSaved`

### Related Work / Learnings

- `knowledge-base/project/plans/2026-06-05-fix-likec4-code-editor-save-noop-plan.md`
  — the prior (diagram-staleness) fix; this plan is the residual source-revert
  failure mode.
- `knowledge-base/engineering/operations/post-mortems/c4-empty-render-clobber-and-silent-success-postmortem.md`
  — #4967 empty-render clobber (exit-0-not-proof); related save path.
- `knowledge-base/project/learnings/best-practices/2026-06-05-render-off-tree-return-bytes-and-drop-toctou-with-the-reread.md`
  — #4979 render off-tree (the insight this fix extends: don't depend on the
  reconcile pull to make just-saved content visible).
- `knowledge-base/project/learnings/2026-06-05-report-error-on-final-recoverability-not-first-failure.md`
  — `syncWorkspace` error-by-recoverability reporting.
- `knowledge-base/project/learnings/2026-06-03-self-heal-reset-must-gate-on-actual-repo-state-not-assumed-mirror.md`
  — gated reset; un-pushed work must be preserved (bounds the fix).
- `knowledge-base/engineering/operations/post-mortems/kb-sync-stale-no-manual-recovery-postmortem.md`
  — diverged-clone classification + gated self-heal (the H1 mechanism).
- #4883, #4925, #4926, #4963, #4965, #4967, #4979, #5007, #5027 — the C4
  visualizer + Save lineage.
