---
title: "fix(kb): restore manual sync affordance + harden reconcile self-heal"
type: fix
date: 2026-06-03
branch: feat-one-shot-kb-sync-affordance-reconcile
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
status: draft
related_prs: [4810, 4846]
---

# 🐛 fix(kb): restore manual sync affordance + harden server reconcile self-heal

## Enhancement Summary

**Deepened on:** 2026-06-03
**Sections enhanced:** Overview, Research Reconciliation, User-Brand Impact, Acceptance
Criteria (Fix B), Phase 2.3, Files to Edit, Domain Review, Open Code-Review Overlap, Sharp Edges.

### Key Improvements

1. **Falsified the core Fix B safety premise (verify-the-negative pass).** "Workspace clone
   is a read-only mirror" is FALSE — `session-sync.ts` (`syncPull`/`syncPush` via
   `agent-runner.ts`) auto-commits + pushes `knowledge-base/**` agent-session changes into
   the SAME clone. A blind `git reset --hard` would destroy un-pushed agent work. Self-heal
   is now gated on `hasLocalCommits` (`git rev-list --count @{u}..HEAD == 0`), reusing the
   exact precedent probe at `session-sync.ts:200-208`.
2. **Caller-sweep correction.** `syncWorkspace` has FOUR production callers, not two — added
   `app/api/kb/file/[...path]/route.ts:66,:308` (delete/rename). Plus the sibling inline-pull
   bug at `kb/upload/route.ts:234` (AC-B9), which aligns with open issue #2244 → fold-in
   candidate.
3. **UI-wireframe produced + committed** (`wg-ui-feature-requires-pen-wireframe`):
   `knowledge-base/product/design/kb-viewer/kb-viewer-wireframes.pen` — three rail states
   (synced / empty-tree "Workspace ready" / desync "out of sync" + recovery callout).
4. **Precedent-diff (Phase 4.4):** the local-commit-guard + best-effort-Sentry recovery
   shape is precedented in `session-sync.ts`; only the `reset --hard` verb is novel.

### New Considerations Discovered

- The "stale KB" failure is NOT fully silent today (it records `ok:false` + Sentry); the real
  gaps are (a) `non_fast_forward` is mislabeled `sync_failed`, (b) no recovery. Scope narrowed
  accordingly.
- `ERROR_CLASS_NON_FAST_FORWARD` exists, is fixtured in tests, but has NO producer — Fix B
  makes `syncWorkspace` the first one.

---

Two bundled fixes for `apps/web-platform`, both rooted in the same incident: an Owner's
platform Knowledge Base view is stale — the post-mortem
`knowledge-base/engineering/operations/post-mortems/chat-rls-workspace-id-outage-postmortem.md`
(merged 2026-06-02 21:10 UTC, PR #4846) is absent from the platform server's workspace
clone even though it is present on `origin/main`. The KB tree is a fresh filesystem walk
on every load (`apps/web-platform/server/kb-reader.ts:197` `buildTree` — no view-time
cache), so the file is genuinely missing from disk: a sync/reconcile failure, not a cache
bug.

- **Fix A** — restore a manual "Sync now" affordance that is reachable WITHOUT first
  opening a file (the self-recovery valve that PR #4810's nav refactor removed).
- **Fix B** — harden the server reconcile so a diverged workspace clone classifies its
  failure correctly (`non_fast_forward`) and self-heals, instead of silently leaving the
  KB stale.

## Overview

### Root cause (two layers)

1. **UI regression (PR #4810).** `KbSyncStatus` (the merged badge+button "Sync now"
   control, `apps/web-platform/components/kb/kb-sync-status.tsx`) is rendered ONLY inside
   `KbContentHeader` (`apps/web-platform/components/kb/kb-content-header.tsx:105`), which is
   mounted ONLY by the file-open route
   `apps/web-platform/app/(dashboard)/dashboard/kb/[...path]/page.tsx`. After PR #4810
   ("single nav rail — drill-in", merged 2026-06-02 19:15 UTC) lifted the file tree into
   the rail's secondary slot and removed the KB collapse axis, the rail
   (`KbSidebarShell`), the empty-content placeholder (`DesktopPlaceholder`, "Select a file
   to view"), and the KB landing all have NO sync affordance. Net: a user can only sync by
   first opening a file; on a fresh/empty KB landing there is no way at all — exactly the
   self-recovery path needed to recover from this incident.

2. **Server reconcile is silent on divergence + mislabels the failure (the deeper bug).**
   `syncWorkspace` (`apps/web-platform/server/kb-route-helpers.ts:293`) runs
   `git pull --ff-only` (line 305, 30 s timeout). If the workspace clone has DIVERGED from
   `origin/<default>` (non-fast-forward), the pull fails. The codebase ALREADY defines and
   re-exports `ERROR_CLASS_NON_FAST_FORWARD = "non_fast_forward"`
   (`apps/web-platform/server/session-sync.ts:313`) and the `KbSyncStatus` desync state
   already keys on it — **but it is never produced anywhere.** Both failure call sites hard-
   code `ERROR_CLASS_SYNC_FAILED`:
   - manual: `apps/web-platform/app/api/kb/sync/route.ts:138` (with a comment: "syncWorkspace
     cannot today distinguish non-fast-forward");
   - reconcile: `apps/web-platform/server/inngest/functions/workspace-reconcile-on-push.ts:311`.
   So a diverged clone DOES record an `ok:false` row to `users.kb_sync_history` (good — the
   forensic trail exists) and DOES mirror to Sentry via `reportSilentFallback` (good — the
   silent-fallback rule is already satisfied), but it labels every failure
   `sync_failed`, never recovers, and the KB stays stale forever because `--ff-only` cannot
   make progress against a diverged HEAD on its own.

### What is already done (do NOT re-build)

- `kb_sync_history` already records failures with `ok:false` at all three call sites
  (manual route, reconcile sync-fail, reconcile skip-not-ready) via `appendKbSyncRow`.
- Sentry mirroring already exists at every failure site via
  `reportSilentFallback`/`warnSilentFallback` (`cq-silent-fallback-must-mirror-to-sentry`
  is satisfied).
- `KbSyncStatus` already renders a `desync` (`ok:false`) state and already POSTs
  `/api/kb/sync` + calls `onSynced`/`onError`. The component needs NO behavioral change for
  Fix A — only a new mount point.
- `KbContext` already exposes `lastSync`, `refreshTree` (= `fetchTree`, which re-fetches
  `/api/kb/tree` → updates tree + lastSync + needsReconnect), and `needsReconnect`
  (`apps/web-platform/components/kb/kb-context.tsx`). `useKbLayoutState` already populates
  all three. So Fix A requires NO new server route, NO new hook state, NO new prop
  plumbing through the layout — just consume `useKb()` from an always-mounted shell.

### Scope of change

- **Fix A:** mount `<KbSyncStatus>` (reading `lastSync` + `refreshTree` from `useKb()`) in
  the always-mounted `KbSidebarShell` (the rail), so it is reachable regardless of whether a
  file is open or the tree is empty. Primary surface = rail; the empty-content
  `DesktopPlaceholder` is a secondary surface (see Phase 1 decision). Pure client wiring;
  no server change.
- **Fix B:** (1) classify the git failure in `syncWorkspace` (return a typed `errorClass`
  alongside the error); (2) propagate the real class to both `kb_sync_history` rows; (3)
  add a gated, observable self-heal that recovers a diverged clone **without destroying
  un-pushed local work**, so the next reconcile (or manual "Sync now") recovers the missing
  file.

> **DEEPEN-PLAN CORRECTION (verify-the-negative pass).** The original premise — "the
> workspace clone is a READ-ONLY mirror, so `reset --hard origin/<default>` only discards
> phantom drift" — is **FALSE**. `apps/web-platform/server/session-sync.ts:437-465`
> (`syncPull`) and `:505-543` (`syncPush`), called from `agent-runner.ts`, auto-COMMIT
> `knowledge-base/**` changes from agent sessions (`git add` + `git commit`, allowlisted to
> `ALLOWED_AUTOCOMMIT_PATHS = [/^knowledge-base\//]`, #2905) into the SAME workspace clone
> and `git push` them. So the clone legitimately holds **un-pushed local commits**. A blind
> `reset --hard` would DESTROY agent-session KB work. The self-heal MUST therefore branch on
> `hasLocalCommits` (the existing `git rev-list --count @{u}..HEAD` probe at
> `session-sync.ts:200-208`): reset ONLY when there are zero local commits ahead of upstream
> (true phantom divergence — upstream force-push, corrupted ref); otherwise attempt a
> non-destructive recovery (merge pull) or bail loudly. See Phase 2.3 + Risks.

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality (verified) | Plan response |
| --- | --- | --- |
| "reconcile likely leaves the KB silently stale" | Partly: it records `ok:false` + mirrors to Sentry, but never recovers and mislabels as `sync_failed`. Not fully silent — but not self-healing and not correctly classified. | Fix B narrows to: classify + self-heal. Do NOT re-add Sentry/history writes (already present). |
| "ensure kb_sync_history records the failure" | Already recorded at all 3 sites via `appendKbSyncRow`. | No-op for history-write; only the `error_class` VALUE changes (sync_failed → non_fast_forward when detected). |
| "KbSyncStatus has a desync/ok:false state" | Confirmed (`kb-sync-status.tsx:61-62`); already keys on `ok:false`. The desync label is generic ("Workspace out of sync") and does NOT branch on `error_class`. | Reuse as-is. (Optional: a `non_fast_forward`-specific hint is OUT OF SCOPE unless Fix B surfaces a need; see Non-Goals.) |
| "ERROR_CLASS_NON_FAST_FORWARD … KbSyncStatus already has the state" | The constant exists, is in the `error_class` union, is re-exported by the reconcile fn, and the existing test fixtures a `non_fast_forward` row — but NO code path EVER produces it. | Fix B makes `syncWorkspace` the producer. |
| "KbSyncStatus rendered ONLY inside KbContentHeader" | Confirmed (`kb-content-header.tsx:8,105`); only consumer. | Fix A adds a second mount in `KbSidebarShell`. |
| "reuse refreshTree from use-kb-layout-state" | `refreshTree` is `fetchTree`; exposed via `useKb()` context (NOT imported from the hook directly by leaf components). | Fix A consumes `useKb()`, not the hook. |
| Root-cause: did reconcile run? non_fast_forward? | Cannot read `kb_sync_history` (Supabase MCP query tools not surfacing). | Phase 0 pulls the class from Sentry + Inngest run history (read-only) to decide whether the self-heal path is load-bearing vs. classification-only. |
| "workspace clone is a read-only mirror; `reset --hard` only discards phantom drift" (plan v1 premise) | FALSE — `session-sync.ts` (`syncPull`/`syncPush` via `agent-runner.ts`) auto-commits + pushes `knowledge-base/**` agent-session changes into the same clone; it can hold un-pushed local commits. | Self-heal gated on `hasLocalCommits` (`@{u}..HEAD` count); `reset --hard` ONLY when zero. Caught by deepen-plan verify-the-negative pass. |

## User-Brand Impact

**If this lands broken, the user experiences:** their Knowledge Base permanently missing
documents they merged (e.g. a post-incident report), with no in-product way to recover —
the Owner sees a stale tree and concludes the platform silently drops their data.

**If this leaks, the user's data/workflow is exposed via:** Fix B's self-heal can run
`git reset --hard` on the workspace clone. The clone is **NOT a read-only mirror** — the
`session-sync.ts` agent-session path auto-commits + pushes `knowledge-base/**` changes into
it (verified, see Overview correction). A `reset --hard` run while the clone holds un-pushed
agent-session commits would DESTROY that work — the worst-case Fix B regression. The
mitigation is mandatory and load-bearing: the self-heal MUST check `hasLocalCommits`
(`git rev-list --count @{u}..HEAD`) and reset ONLY when zero local commits are ahead of
upstream; a non-zero count means real local work → non-destructive recovery or loud bail,
never reset.

**Brand-survival threshold:** single-user incident — one Owner's KB silently losing a
merged document, or a self-heal that wipes a workspace, is a per-user trust-ending event.

> CPO sign-off required at plan time before `/work` begins. Invoke CPO (or confirm CPO has
> reviewed) per the threshold. `user-impact-reviewer` runs at review time (review/SKILL.md
> conditional-agent block).

## Acceptance Criteria

### Pre-merge (PR)

**Fix A — manual sync affordance**

- [x] AC-A1: `KbSyncStatus` is rendered from `KbSidebarShell`
  (`apps/web-platform/components/kb/kb-sidebar-shell.tsx`), reading `lastSync` +
  `refreshTree` from `useKb()`. Verify: `git grep -n "KbSyncStatus" apps/web-platform/components/kb/kb-sidebar-shell.tsx`
  returns ≥1 line.
- [x] AC-A2: On the empty-tree rail branch (`isEmpty === true`) the sync affordance is
  STILL rendered (the affordance must survive the "No documents yet" CTA branch — that is
  the exact stale/empty landing the incident hit). Verify via component test: render
  `KbSidebarShell` with an empty tree and assert `getByRole("button", { name: /sync now/i })`.
- [x] AC-A3: Clicking "Sync now" from the rail POSTs `/api/kb/sync` and, on success, calls
  `refreshTree` (re-fetches `/api/kb/tree` → updates tree + lastSync). Verify via test on
  the rail wrapper: mock fetch, assert URL `/api/kb/sync` + method POST + that the
  context `refreshTree` was invoked on success.
- [x] AC-A4: `error_class`-driven desync label still renders (`ok:false` row →
  "out of sync") from the rail mount — no regression to the existing
  `kb-sync-status.test.tsx` discriminator cases (all existing tests still pass).
- [x] AC-A5: Decision recorded (Phase 1) on whether `DesktopPlaceholder` ALSO gets the
  affordance. If yes, the placeholder test asserts the button; if no, a one-line rationale
  is in the plan body and the rail mount alone satisfies "reachable without opening a file".
- [x] AC-A6: The rail mount matches the committed wireframe
  `knowledge-base/product/design/kb-viewer/kb-viewer-wireframes.pen` (three states: synced
  "Synced Nm ago", empty-tree "Workspace ready", desync "Workspace out of sync") — the
  affordance is pinned to the rail footer above-the-fold and renders in ALL three rail
  branches.

**Fix B — reconcile classification + self-heal**

- [x] AC-B1: `syncWorkspace` returns a discriminated failure carrying a typed
  `errorClass: KbSyncErrorClass` (at minimum `non_fast_forward` vs `sync_failed`), derived
  from the git stderr/exit signature — NOT hard-coded. Verify via
  `test/kb-route-helpers.test.ts`: mock `gitWithInstallationAuth` to reject with a stderr
  containing the non-fast-forward signature and assert the returned `errorClass === "non_fast_forward"`;
  reject with an auth/IO error and assert `errorClass === "sync_failed"`.
- [x] AC-B2: Both `appendKbSyncRow` call sites
  (`app/api/kb/sync/route.ts`, `server/inngest/functions/workspace-reconcile-on-push.ts`)
  write the REAL `error_class` from `syncResult`, not a hard-coded literal. Verify:
  `git grep -n "ERROR_CLASS_SYNC_FAILED" app/api/kb/sync/route.ts server/inngest/functions/workspace-reconcile-on-push.ts`
  no longer shows it as the only/hard-coded value on the failure path (the value flows from
  `syncResult.errorClass`).
- [x] AC-B3: On a detected `non_fast_forward`, `syncWorkspace` attempts the gated self-heal
  via `gitWithInstallationAuth`: `git fetch origin <default>`, then check local commits
  (`git rev-list --count @{u}..HEAD`). If ZERO → `git reset --hard origin/<default>` and
  return `{ ok: true, recovered: true }`. If NON-ZERO → do NOT reset; return
  `{ ok: false, errorClass: "non_fast_forward" }` (real local work diverged; surface to the
  user via the desync state, do not destroy). Verify via test: (a) non-FF + zero local
  commits → assert fetch+rev-list+reset argv with resolved default branch + `{ok:true,
  recovered:true}`; (b) non-FF + non-zero local commits → assert NO reset argv + `{ok:false}`;
  (c) self-heal git error → `{ok:false}` + fail_loud.
- [x] AC-B4: The self-heal is OBSERVABLE: a successful self-heal emits a distinct Sentry
  breadcrumb/event AND records a `kb_sync_history` row distinguishing "recovered via
  reset" from a clean pull (e.g. `ok:true` with a `recovered: true`/trigger annotation or a
  dedicated breadcrumb). A FAILED self-heal mirrors to Sentry with `fail_loud` and records
  `ok:false`. Verify: tests assert the observability call fired on both branches.
- [x] AC-B5: The default branch is resolved, not assumed `main`. Verify the resolution
  source in `Files to Edit` (Phase 2 decides: `git symbolic-ref refs/remotes/origin/HEAD`,
  the reconcile event's `defaultBranch`, or `workspaces`/`users` column). Test asserts the
  reset targets the resolved ref, not a literal `main`.
- [x] AC-B6: Self-heal NEVER destroys un-pushed local commits. The `hasLocalCommits` guard
  (`git rev-list --count @{u}..HEAD`, reusing the exact probe at `session-sync.ts:200-208`)
  gates the `reset --hard`. Verify: the test in AC-B3(b) asserts a diverged clone WITH local
  commits is NOT reset. (This is the mandatory replacement for the falsified "read-only
  mirror" premise — see Overview correction.)
- [x] AC-B7: `tsc --noEmit` clean for `apps/web-platform` (union widening of the
  `syncWorkspace` return shape threads to all callers — `cq-union-widening-grep-three-patterns`
  / `hr-type-widening-cross-consumer-grep`).
- [x] AC-B8: Full enumeration of `syncWorkspace` callers updated for the new return shape.
  Verified at deepen-plan time: FOUR production call sites consume the return —
  `app/api/kb/sync/route.ts:116` (manual), `server/inngest/functions/workspace-reconcile-on-push.ts:289`
  (reconcile), AND `app/api/kb/file/[...path]/route.ts:66` + `:308` (delete/rename file
  route — TWO sites the original Files-to-Edit list missed). Each must handle the new
  `errorClass`/`recovered` shape. Verify: `git grep -n "syncWorkspace(" apps/web-platform`
  + `tsc --noEmit`.
- [x] AC-B9: The SIBLING inline-pull surface `app/api/kb/upload/route.ts:234`
  (`gitWithInstallationAuth(["pull","--ff-only"])`, NOT routed through `syncWorkspace`) has
  the IDENTICAL latent non-fast-forward bug. Decide at `/work` time: route it through the
  hardened `syncWorkspace` (preferred — closes the bug class), or scope it out with a
  tracked follow-up. Do NOT silently leave one of two upload paths unhardened.

### Post-merge (operator → automated where feasible)

- [ ] AC-P1 (restore service): trigger a re-sync for the affected Owner's workspace so the
  missing PIR appears. Automation path (Phase 3): fire the reconcile Inngest event via
  `/soleur:trigger-cron` (POST `/api/internal/trigger-cron`, allowlisted, no SSH) OR the
  manual `/api/kb/sync` path on the user's behalf. NOT operator-SSH (`hr-no-ssh-fallback-in-runbooks`).
  Verify the file then renders in the KB tree (Playwright MCP against the KB route, or a
  `/api/kb/tree` read asserting the PIR path is present).
- [ ] AC-P2: confirm post-deploy that a real `non_fast_forward` now records the correct
  `error_class` (pull the row via the same Sentry/observability path used in Phase 0, not
  a dashboard eyeball; `hr-no-dashboard-eyeball-pull-data-yourself`).

## Implementation Phases

### Phase 0 — Root-cause trace (read-only; decides Fix B shape)

Pull the reconcile root cause WITHOUT reading `kb_sync_history` directly (Supabase MCP
query tools are not surfacing):

1. **Sentry:** search the `kb-route-helpers` / `WORKSPACE_RECONCILE_SENTRY_FEATURE`
   features for `workspace sync failed` / `op:sync` events around 2026-06-02 21:10 UTC for
   this Owner's installation. Confirm: did a reconcile fire for PR #4846's push? What is the
   git stderr (non-fast-forward vs auth/IO/timeout)?
2. **Inngest run history** for `workspace-reconcile-on-push`: did the function run for that
   delivery? Did it reach the `reconcile-<ws.id>` step? Outcome
   (`synced`/`no-workspace-synced`/`sync` failure)?
3. **Decision gate:**
   - If the error is genuinely `non_fast_forward` (diverged clone) → the self-heal path
     (Phase 2.3) is LOAD-BEARING; build it.
   - If the error is auth/IO/timeout (not divergence) → the self-heal would not have helped;
     scope Fix B down to classification + correct labeling + a tracked follow-up for the
     real cause, and re-confirm with the user. (Still ship classification: the
     `non_fast_forward` class being unreachable is a latent bug regardless.)
   - If reconcile NEVER fired (webhook/dispatch gap) → that is a THIRD root cause; file it
     and re-scope (the manual affordance in Fix A still restores self-recovery).

Record the Phase 0 finding verbatim in a `## Phase 0 Findings` note appended to this plan
before `/work` proceeds past Phase 0.

### Phase 1 — Fix A: manual sync affordance in the rail (TDD)

**Tests first** (`cq-write-failing-tests-before`):

- Extend `apps/web-platform/test/kb-sync-status.test.tsx` (jsdom project — matches
  `test/**/*.test.tsx`) OR add `apps/web-platform/test/kb-sidebar-shell.test.tsx` to wrap
  `KbSidebarShell` in a `KbContext` provider with: (a) empty tree, (b) populated tree, (c)
  `ok:false` lastSync. Assert the "Sync now" button renders in all three and that a
  successful POST invokes the context's `refreshTree`.

**Implementation:**

- `apps/web-platform/components/kb/kb-sidebar-shell.tsx`: consume `lastSync` + `refreshTree`
  (+ `onError` handling consistent with the existing content-header usage) from `useKb()`;
  render `<KbSyncStatus lastSync={lastSync} onSynced={refreshTree} onError={…} />` in a
  fixed footer/header region of the shell so it is visible on BOTH the populated `FileTree`
  branch AND the `RailEmptyState` ("No documents yet") branch (AC-A2). Match the rail's
  existing spacing/typography (reuse the `KbSyncStatus` styling; do not restyle the
  component).
- **Decision (AC-A5):** primary surface is the rail (always mounted via the
  `RailSlotPortal` in `kb/layout.tsx`, present even on the empty/error full-width branch).
  Evaluate whether `DesktopPlaceholder` ("Select a file to view") ALSO needs it: the rail
  already covers the "no file open" and "empty tree" cases, so the placeholder mount is
  likely redundant. Record the chosen answer + 1-line rationale here at `/work` time.

> Wireframe note (`wg-ui-feature-requires-pen-wireframe`): this is a UI surface. Phase 2.5
> Product/UX Gate determines whether a `.pen` wireframe is required (the change reuses an
> existing component in an existing shell — likely ADVISORY, but the gate decides).

### Phase 2 — Fix B: classify + self-heal in `syncWorkspace` (TDD)

Phase order is load-bearing: the CONTRACT change (Phase 2.1, `syncWorkspace` return shape)
ships BEFORE the CONSUMER changes (Phase 2.2) so the consumer code is never dead/uncompiled
(`2026-05-10-plan-phase-order-load-bearing-when-contract-changes`).

**2.1 — Classify (contract change).**
- Add a classifier that maps a failed-git error to `KbSyncErrorClass`. The non-fast-forward
  signature in `git pull --ff-only` stderr is `fatal: Not possible to fast-forward, aborting.`
  (and/or `Not possible to fast-forward`). **`/work` MUST verify the exact stderr string
  against the installed git in the platform container before freezing the matcher** (run
  `git pull --ff-only` against a diverged fixture clone and capture stderr) —
  Sharp Edge: do not hard-code a string from memory.
- Widen `syncWorkspace`'s return to
  `{ ok: true; recovered?: boolean } | { ok: false; error: unknown; errorClass: KbSyncErrorClass }`.
  Reuse the existing `KbSyncErrorClass` union from `session-sync.ts` (do not invent a new
  one). `tsc --noEmit` + `git grep -n "syncWorkspace(" apps/web-platform` enumerate the
  callers (AC-B7/B8).

**2.2 — Propagate to history rows (consumer change).**
- `app/api/kb/sync/route.ts:130-145`: write `error_class: syncResult.errorClass`; remove the
  hard-coded `ERROR_CLASS_SYNC_FAILED` + the now-stale comment.
- `server/inngest/functions/workspace-reconcile-on-push.ts:304-316`: same — write
  `syncResult.errorClass`.

**2.3 — Gated, observable self-heal (only if Phase 0 confirms divergence is the cause).**
- On `non_fast_forward`, inside `syncWorkspace`, via `gitWithInstallationAuth` (same
  auth/cwd/timeout envelope as the pull):
  1. `git fetch origin <default>`.
  2. **Local-commit guard (mandatory, AC-B6):** `git rev-list --count @{u}..HEAD` (reuse the
     EXACT probe shape from `session-sync.ts:200-208` `hasLocalCommits`). 
     - count == 0 → phantom divergence (upstream force-push / corrupted ref). Safe to
       `git reset --hard origin/<default>`; return `{ ok: true, recovered: true }`.
     - count > 0 → REAL un-pushed agent-session work (`session-sync` auto-committed
       `knowledge-base/**`). Do NOT reset. Return `{ ok: false, errorClass:
       "non_fast_forward" }` so the desync state surfaces; page via fail_loud. (A future
       enhancement could attempt `git pull --no-rebase --autostash` like `session-sync`, but
       that is OUT OF SCOPE here — the safe-by-default behavior is bail-without-destroy.)
- **Default-branch resolution (AC-B5):** decide source at `/work` time —
  `git symbolic-ref --short refs/remotes/origin/HEAD` (robust, no schema dep) is preferred;
  the reconcile event already carries `defaultBranch` (usable for the reconcile path but NOT
  the manual route, which has no event). Do NOT assume `main`.
- **Precedent (Phase 4.4 precedent-diff):** the destructive-recovery + local-commit-guard
  pattern has a direct in-repo precedent — `session-sync.ts` already (a) detects local
  commits via `git rev-list --count @{u}..HEAD` (`:200-208`), (b) auto-stashes on pull
  (`--autostash`, `:462`), (c) wraps every git op in best-effort try/catch + Sentry. The
  self-heal MUST mirror this guard shape rather than inventing a new one. The `reset --hard`
  verb itself is novel (no existing call site — `git grep "reset --hard" apps/web-platform`
  → none), so it is the one verb to scrutinize; the GUARD around it is precedented.
- **Observability (AC-B4, `cq-silent-fallback-must-mirror-to-sentry`, `hr-observability-layer-citation`):**
  - self-heal SUCCESS → Sentry breadcrumb/event (e.g. `op:self-heal-reset`, info/warning)
    + `kb_sync_history` row marked recovered (`ok:true` + `recovered: true` or a distinct
    trigger/annotation) so the forensic trail shows a reset happened, not a clean pull.
  - self-heal FAILURE → `reportSilentFallback(..., fail_loud)` with `op:self-heal-failed`
    + `ok:false` row with `errorClass`.
- **Precedent (novel pattern):** no existing `git reset --hard` precedent in the repo's git
  helpers (`git grep -n "reset --hard" apps/web-platform/server` → only the
  credential-helper-reset comment). Closest philosophy precedent:
  `knowledge-base/project/learnings/bug-fixes/2026-05-30-inngest-cron-desync-regression-needs-runtime-self-heal-not-ci-guard.md`
  — "liveness ≠ plan integrity; a desync needs a RUNTIME self-heal, not a build-time guard,
  and the self-heal must be observable + cooldown-gated against loops." deepen-plan Phase 4.4
  precedent-diff should weigh whether a recovery cooldown (mirror of that watchdog's
  restart-survivable cooldown) is needed here, or whether the per-push/per-click idempotence
  of `reset --hard origin/<default>` makes a cooldown unnecessary (a reset to an already-
  matching ref is a no-op).

**Tests** (`test/kb-route-helpers.test.ts` + `test/server/inngest/workspace-reconcile-on-push.test.ts`
+ `test/server/kb-sync-route.test.ts`): mock `gitWithInstallationAuth` (the harness already
mocks it as `mockGitWithAuth`). Drive the assertion path through DIRECT `syncWorkspace`
invocation and captured git argv — NOT through any LLM/natural-language path. Cases:
non-FF → self-heal success (assert fetch+reset argv + `{ok:true, recovered:true}`); non-FF →
self-heal failure (assert `fail_loud` Sentry + `ok:false` row); auth error → `sync_failed`,
no self-heal attempted; clean pull → no reset, `ok:true`.

### Phase 3 — Restore service + verify (post-merge, automated)

- Trigger re-sync for the Owner's workspace via `/soleur:trigger-cron` (allowlisted reconcile
  event) or `/api/kb/sync` on their behalf — automation-feasible, NO SSH (AC-P1).
- Verify the PIR renders: Playwright MCP against `/dashboard/kb/...` OR a `/api/kb/tree` read
  asserting the PIR path is present in the tree (AC-P1).
- Pull the post-deploy `non_fast_forward` confirmation via Sentry/observability (AC-P2).

## Files to Edit

- `apps/web-platform/components/kb/kb-sidebar-shell.tsx` — mount `KbSyncStatus` from
  `useKb()` (Fix A).
- `apps/web-platform/server/kb-route-helpers.ts` — classify git failure; widen
  `syncWorkspace` return; add gated observable self-heal (Fix B core).
- `apps/web-platform/app/api/kb/sync/route.ts` — write real `error_class`; handle
  `recovered` (Fix B consumer).
- `apps/web-platform/server/inngest/functions/workspace-reconcile-on-push.ts` — write real
  `error_class`; handle `recovered` (Fix B consumer).
- `apps/web-platform/app/api/kb/file/[...path]/route.ts` — delete/rename file route; TWO
  `syncWorkspace` call sites (`:66`, `:308`) consume the widened return (Fix B consumer —
  deepen-plan caller-sweep addition).
- `apps/web-platform/app/api/kb/upload/route.ts` — inline `pull --ff-only` at `:234` has the
  same latent bug; route through hardened `syncWorkspace` or scope out (AC-B9).
- `apps/web-platform/server/session-sync.ts` — only if the row schema needs a `recovered`
  field (and the `KbSyncRow` type + `appendKbSyncRow`); otherwise no change. NOTE: this file
  is the precedent source for the `hasLocalCommits` guard (`:200-208`) — read, do not edit
  (unless adding `recovered` to the shared row type).
- `apps/web-platform/test/kb-sync-status.test.tsx` (or new
  `apps/web-platform/test/kb-sidebar-shell.test.tsx`) — Fix A tests (jsdom).
- `apps/web-platform/test/kb-route-helpers.test.ts` — `syncWorkspace` classify + self-heal
  tests (node).
- `apps/web-platform/test/server/kb-sync-route.test.ts` — manual route propagates real class.
- `apps/web-platform/test/server/inngest/workspace-reconcile-on-push.test.ts` — reconcile
  propagates real class + self-heal.
- **Caller sweep (AC-B8):** `git grep -n "syncWorkspace(" apps/web-platform` at `/work` time;
  add every additional caller (upload/delete/rename/push paths) to this list if the widened
  return shape touches them.

## Files to Create

- Possibly `apps/web-platform/test/kb-sidebar-shell.test.tsx` (if not extending the existing
  `kb-sync-status.test.tsx`). Must live under `test/**/*.test.tsx` (vitest jsdom glob —
  `vitest.config.ts:60`); a co-located `components/**/*.test.tsx` would be silently skipped.

## Open Code-Review Overlap

1 open scope-out touches a planned file:
- **#2244** (`refactor(kb): migrate upload route to syncWorkspace (finish PR #2235 scope)`)
  touches `server/kb-route-helpers.ts`. **Disposition: Fold in (candidate) — decide at
  `/work`.** #2244's exact ask ("migrate the upload route to `syncWorkspace`") IS this plan's
  AC-B9. Routing `kb/upload/route.ts:234`'s inline `pull --ff-only` through the hardened
  `syncWorkspace` simultaneously closes the upload-path non-fast-forward bug AND #2244. If
  folded, add `Closes #2244` to the PR body and `kb/upload/route.ts` to the consumer edits
  (already in Files to Edit). If `/work` finds the migration carries extra scope (#2235
  remnants) beyond the one-line pull swap, scope #2244 to Acknowledge and keep only the
  pull-hardening. Default: fold in.

## Domain Review

**Domains relevant:** Product (UI surface — Fix A), Engineering (data-integrity — Fix B
destructive `reset --hard`).

### Product/UX Gate

**Tier:** advisory (reuses an existing component `KbSyncStatus` inside an existing shell
`KbSidebarShell`; no NEW component file under `components/**/*.tsx`, no new `page.tsx`/
`layout.tsx` — the mechanical BLOCKING escalation does not fire). It IS a UI-surface change
(rail/sidebar chrome), so per `wg-ui-feature-requires-pen-wireframe` a committed `.pen` is
required.
**Decision:** auto-accepted (pipeline).
**Pencil available:** yes (Node v22.22.1).
**Wireframe:** `knowledge-base/product/design/kb-viewer/kb-viewer-wireframes.pen` —
committed; three rail states (populated+synced, empty-tree+"Workspace ready",
desync+"out of sync" with the non-fast-forward recovery callout). Verifier: file exists
non-empty on disk and is referenced in AC-A6.

### Engineering (data-integrity)

**Status:** flagged — `git reset --hard` is destructive AND the clone is read-WRITE (the
"read-only mirror" premise was falsified at deepen-plan; see Overview correction). The
self-heal MUST be gated on `hasLocalCommits == 0` (AC-B6) and a confirmed `non_fast_forward`
class.

**Precedent-diff (Phase 4.4):** the local-commit-guard + best-effort-Sentry recovery shape
has a direct precedent in `session-sync.ts` (`hasLocalCommits` `git rev-list --count
@{u}..HEAD` at `:200-208`; `--autostash` pull at `:462`; try/catch+`reportSilentFallback` at
every git op). Mirror it. The `reset --hard` verb is the only NOVEL element (no existing
call site in `apps/web-platform`) and is the focus of review scrutiny.

Pressure-test at `/work` / review: (a) the `@{u}..HEAD` guard correctly bails on un-pushed
agent-session commits; (b) default-branch resolution edge cases (detached HEAD, missing
`origin/HEAD`); (c) self-heal idempotence under the reconcile fan-out (multiple workspaces,
CEL-keyed concurrency, `concurrency limit:1` per installation already serializes);
(d) the four `syncWorkspace` callers + the inline `kb/upload` pull all benefit or are
explicitly scoped out.

## Observability

```yaml
liveness_signal:
  what: kb_sync_history row written per reconcile/manual sync (ok/error_class/recovered)
  cadence: per GitHub push (reconcile) + per "Sync now" click (manual)
  alert_target: Sentry (reportSilentFallback) for ok:false; existing kb-route-helpers + WORKSPACE_RECONCILE_SENTRY_FEATURE issues
  configured_in: apps/web-platform/server/observability.ts (reportSilentFallback/warnSilentFallback)
error_reporting:
  destination: Sentry via reportSilentFallback (failure) / breadcrumb (self-heal success)
  fail_loud: true — self-heal FAILURE uses reportSilentFallback (paging path); classification of every ok:false already mirrors
failure_modes:
  - mode: non_fast_forward (diverged clone)
    detection: git stderr "Not possible to fast-forward" → KbSyncErrorClass=non_fast_forward
    alert_route: kb_sync_history ok:false + Sentry op:sync; self-heal attempt logged
  - mode: self-heal reset fails (fetch/reset error)
    detection: gitWithInstallationAuth rejects in the reset arm
    alert_route: reportSilentFallback op:self-heal-failed (fail_loud) + ok:false row
  - mode: self-heal SUCCESS (recovered drift)
    detection: reset to origin/<default> resolves; result {ok:true, recovered:true}
    alert_route: Sentry breadcrumb op:self-heal-reset + kb_sync_history recovered row
  - mode: un-pushed local commits present (mirror invariant violated)
    detection: git rev-list origin/<default>..HEAD non-empty before reset
    alert_route: abort reset, reportSilentFallback op:self-heal-aborted-dirty (fail_loud)
logs:
  where: pino (Better Stack) at each syncWorkspace failure/self-heal site + Sentry
  retention: existing platform retention (Better Stack + Sentry defaults)
discoverability_test:
  command: "rg -n 'op:self-heal' apps/web-platform/server && vitest run test/kb-route-helpers.test.ts"
  expected_output: self-heal observability sites present; classify + self-heal tests pass (NO ssh)
```

## Test Scenarios

- Fix A: rail renders "Sync now" with empty tree, populated tree, and `ok:false` row;
  click → POST `/api/kb/sync` → `refreshTree` on success; existing discriminator tests green.
- Fix B classify: non-FF stderr → `non_fast_forward`; auth/IO stderr → `sync_failed`.
- Fix B self-heal: non-FF → fetch+reset argv (resolved default branch) → `{ok:true, recovered:true}`;
  reset fails → `fail_loud` + `ok:false`; clean pull → no reset; dirty clone (un-pushed) →
  abort + page.
- Fix B propagation: manual route + reconcile both write `syncResult.errorClass`.
- `tsc --noEmit` clean; caller sweep complete.

## Non-Goals / Out of Scope

- A `non_fast_forward`-specific desync HINT in `KbSyncStatus` copy (the generic "out of
  sync" + working "Sync now" is sufficient; a tailored message is a follow-up if Phase 0
  shows users need it). → file a deferral issue if cut.
- View-time caching of the KB tree (the fresh walk is correct; the bug is sync, not cache).
- Reworking the webhook→Inngest dispatch (only revisit if Phase 0 finds reconcile never
  fired — then re-scope).
- Migrating the upload/delete/rename routes' sync semantics (that is #2244's scope).

## Sharp Edges

- **The `## User-Brand Impact` section is load-bearing** — a plan whose section is empty or
  placeholder fails `deepen-plan` Phase 4.6. It is filled above (threshold: single-user
  incident).
- **`git reset --hard` is destructive AND the clone is NOT a read-only mirror.** The
  `session-sync.ts` agent path auto-commits + pushes `knowledge-base/**` into the SAME clone,
  so it can hold un-pushed local commits. The self-heal MUST gate `reset --hard` on
  `git rev-list --count @{u}..HEAD == 0` (reuse `session-sync.ts:200-208`); a non-zero count
  → bail-without-destroy. At single-user-incident threshold a wipe of agent-session KB work
  is worse than a stale KB. (This corrects the falsified plan-v1 "read-only mirror" premise —
  deepen-plan verify-the-negative pass.)
- **Default branch must be resolved, not assumed `main`** (AC-B5). `git symbolic-ref` is the
  robust source; the reconcile event's `defaultBranch` works only for the reconcile path.
- **Verify the exact non-fast-forward stderr against the installed git** before freezing the
  classifier matcher — capture it from a real diverged-fixture `git pull --ff-only`, do not
  hard-code from memory.
- **Test files must match the vitest globs** — `.tsx` under `test/**/*.test.tsx` (jsdom),
  `.ts` under `test/**/*.test.ts` (node). A co-located `components/**/*.test.tsx` is silently
  never run (`vitest.config.ts:60`). The web-platform runner is **vitest**, not bun
  (`bunfig.toml` blocks bun test discovery, #1469); run via `./node_modules/.bin/vitest run <path>`.
- **`ERROR_CLASS_NON_FAST_FORWARD` already exists and is fixtured in tests but never
  produced** — Fix B makes `syncWorkspace` the first producer; do not add a NEW constant.
- **Self-heal must be deterministically tested** — drive `syncWorkspace` directly with a
  mocked `gitWithInstallationAuth`; never assert the security/recovery invariant through an
  LLM/natural-language path.
- **`syncWorkspace` return widening is cross-consumer** — `tsc --noEmit` + a
  `git grep "syncWorkspace("` caller sweep are the enumerators (AC-B7/B8), not a count
  pasted into the plan.

## GDPR / Compliance

The `reset --hard` self-heal operates on a workspace clone whose path embeds a raw `userId`
(`workspacePath = <root>/<userId>`, already noted in `kb-route-helpers.ts:318-320`). No new
processing of regulated data is introduced (the file content is the user's own KB, already
processed). Observability payloads must continue to OMIT `workspacePath` (raw userId) per
the existing `reportSilentFallback` comment — new self-heal Sentry sites MUST follow the
same omission. The Phase 2.7 GDPR gate fires on (b) `single-user incident` threshold; run it
against the Fix B FRs to confirm no Art. 30 trigger from the new self-heal processing.

## Infrastructure (IaC)

None — pure code change against already-provisioned surfaces (`apps/web-platform/server`,
`components`, `app/api`). No new server, secret, vendor, cron, or persistent process. The
post-merge re-sync (Phase 3) uses the EXISTING allowlisted `/api/internal/trigger-cron` +
the EXISTING reconcile Inngest function; no new infra.

## Phase 0 Findings

Root-cause trace via Sentry/Inngest could NOT be pulled in this implementation
environment: no Sentry/Inngest MCP is surfaced here, and the Supabase MCP query tools are
not available either. Proceeding with the FULL Fix B (classification + gated self-heal)
because:

(a) the `ERROR_CLASS_NON_FAST_FORWARD` producer-gap is a latent bug regardless of this
    incident's exact cause — the constant exists, is fixtured in tests, keys the
    `KbSyncStatus` desync state, yet had NO producer; both failure sites hard-coded
    `sync_failed`, so a diverged clone could never surface correctly.
(b) the gated self-heal is safe-by-construction: it resets ONLY when
    `git rev-list --count @{u}..HEAD == 0` (zero un-pushed local commits), otherwise it
    bails WITHOUT destroying anything (AC-B6), and is idempotent (a `reset --hard` to an
    already-matching ref is a no-op).

Post-deploy AC-P2 verification must confirm the REAL `error_class` of the incident via the
observability path (Sentry/`kb_sync_history`), not a dashboard eyeball.

**Verified at /work time (not from memory):** the exact non-fast-forward stderr from the
installed git (2.53.0) is `fatal: Not possible to fast-forward, aborting.` — the classifier
matches the stable substring `Not possible to fast-forward`. `git symbolic-ref --short
refs/remotes/origin/HEAD` resolves to `origin/main` for a normal clone (used for default-
branch resolution, AC-B5).

### AC-A5 decision — DesktopPlaceholder mount

**Rail mount only; DesktopPlaceholder NOT additionally instrumented.** The rail
(`KbSidebarShell`) is always mounted via the `RailSlotPortal` and now renders the affordance
in BOTH the populated and empty-tree branches — covering "no file open" and "empty/fresh KB
landing", which is exactly the self-recovery path the incident needed. A second mount in
`DesktopPlaceholder` ("Select a file to view") would be redundant (the rail is on-screen
beside it) and risk double-affordance confusion. Rationale recorded; rail mount alone
satisfies "reachable without opening a file".

### AC-B9 / #2244 decision — upload route

**Folded in (Closes #2244).** The inline `gitWithInstallationAuth(["pull","--ff-only"])` at
`app/api/kb/upload/route.ts` was a clean one-line swap to the hardened `syncWorkspace`
(`op: "upload"`) — same bindings (`github_installation_id`, `workspace_path`, `user.id`)
were already in scope, no #2235 remnants or extra scope. This closes the identical latent
non-fast-forward bug on the second upload path AND #2244 in one change. The unused
`gitWithInstallationAuth` import was removed; `Sentry` import retained (still used by other
catch sites in the route).
