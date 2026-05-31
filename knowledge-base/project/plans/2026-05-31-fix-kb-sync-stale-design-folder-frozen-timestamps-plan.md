---
title: "fix: KB sync stale — design folder persists, timestamps frozen ~5w"
type: bug
status: draft
created: 2026-05-31
branch: feat-one-shot-kb-sync-stale-design-folder
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# 🐛 fix: Knowledge Base sync is stale — `design` folder persists and all timestamps frozen at ~5 weeks

> Spec lacks valid `lane:` — defaulted to `cross-domain` (TR2 fail-closed). No spec.md exists for this branch.

## Overview

The KB file tree in the Soleur web app shows stale content (screenshot Sun May 31 22:19): a top-level `design/` folder (containing `upgrade-modal-at-capa…`, modified "5w ago") that no longer exists in the source repo, and **every** directory/file entry (`INDEX.md`, `kb-categories.txt`, `kb-tags.txt`, all folders) reporting "5w ago" `modifiedAt` timestamps. The KB has not re-synced from source for ~5 weeks, and a prior fix attempt did not resolve it.

**Root-cause hypothesis (high confidence — to be confirmed in Phase 0):** This is a **path-resolution divergence introduced by ADR-044 (PR #4559, merged Sun May 25)**, the exact ~5-week-prior window (relative to the 2026-05-31 screenshot the bug is ~6 days; relative to the operator's actual last-good sync ~5w predates ADR-044 — see Hypotheses for the two-window distinction). The reconcile *write* path and the tree *read* path resolve the workspace directory differently:

- **Read path** (`/api/kb/tree` → `buildTree`) resolves `kbRoot` from **`users.workspace_path`** (legacy `<WORKSPACES_ROOT>/<user_id>` scheme). See `apps/web-platform/app/api/kb/tree/route.ts:13,35`.
- **Write path** (webhook push → `workspaceReconcileOnPush`) resolves the dir from **`workspacePathForWorkspaceId(ws.id)` = `<WORKSPACES_ROOT>/<workspace_id>`** (ADR-044 UUID scheme). See `apps/web-platform/server/inngest/functions/workspace-reconcile-on-push.ts:223` + `apps/web-platform/server/workspace-resolver.ts:26`.

If those two paths point at **different directories** for an existing operator (legacy `users.workspace_path` populated with a user-id path, while the reconcile targets a workspace-id path), then `git pull --ff-only` runs against a directory the tree never reads — the tree forever reflects the pre-ADR-044 on-disk state, the `design/` folder that was deleted upstream ~5w ago is never removed, and `mtime` stays frozen. The "Sync now" manual button (`/api/kb/sync`) shares the **read** path's `users.workspace_path` resolution, so it pulls into the dir the tree reads — meaning manual sync *should* work for legacy users but webhook reconcile writes to the wrong dir; OR (the inverse case for ADR-044-provisioned users) reconcile writes to the workspace-id dir but the tree reads a non-existent/empty legacy path and falls back to stale cache. The two on-disk schemes must be reconciled to a single source of truth.

**Secondary hypothesis (must be ruled out, not assumed):** the sync is silently failing — `syncWorkspace` runs `git pull --ff-only` (`kb-route-helpers.ts:304`); if the local working tree has divergent/auto-committed history, `--ff-only` aborts non-fast-forward and the error is swallowed by `reportSilentFallback` (best-effort contract). A `design/`-folder delete upstream + any local commit would produce exactly a non-fast-forward that freezes the tree. This is independent of the path divergence and may co-occur.

**Why prior fixes missed it:** the three recent reconcile PRs (#4623, #4666 debounce/Sentry-noise; #4546 installation-ID resolution) all addressed **observability and resolution of *which workspaces match a push*** — none touched the **path the matched workspace pulls into vs. the path the tree reads from**. The bug is downstream of "did we find the workspace" and upstream of "what does the user see"; it sits precisely in the read/write path-resolution seam that no prior fix inspected.

## Research Reconciliation — Spec vs. Codebase

| Claim (from bug report / inferred) | Reality (codebase) | Plan response |
|---|---|---|
| "A prior fix attempt did not resolve it" | #4623/#4666/#4546 fixed Sentry-noise + multi-user install-ID resolution, NOT the read/write path seam | Phase 0 confirms which dir each path resolves to for the affected operator before any code change |
| "KB not re-syncing from source" | `syncWorkspace` uses `git pull --ff-only`; failures swallowed by `reportSilentFallback` (best-effort) | Phase 1 adds structured failure classification + verifiable observability; Phase 2 fixes path resolution |
| Tree reads current on-disk state | `buildTree` reads `users.workspace_path/knowledge-base` (`tree/route.ts:35`); manual sync + reconcile may write elsewhere | Unify read+write path resolution through `workspace-resolver.ts` |
| `design/` folder is a render bug | `buildTree` faithfully reflects on-disk dirs (`kb-reader.ts:215-227`); the folder physically exists on disk in the dir the tree reads | Confirm on-disk presence in Phase 0; fix is to make the pull reach that dir |

## User-Brand Impact

- **If this lands broken, the user experiences:** the KB tree continues to show deleted folders (`design/`) and frozen "5w ago" timestamps — the product's core "your knowledge base, always current" promise is visibly false on every page load. A KB that silently stops reflecting the source repo is indistinguishable from a dead product to a non-technical operator.
- **If this leaks, the user's data/workflow is exposed via:** no data leak vector (read/write are same-tenant, RLS-scoped). The exposure is **workflow trust**: an operator making decisions off a 5-week-stale KB, and agents reading stale KB context into prompts (the workspace dir feeds both the tree AND agent sessions via `session-sync.ts`).
- **Brand-survival threshold:** single-user incident — a single operator seeing their KB frozen for 5 weeks is a brand-survival event for a knowledge-base product. CPO sign-off required (see frontmatter).

> CPO sign-off required at plan time before `/work` begins. Invoke CPO domain leader if not already covered by Phase 2.5 carry-forward. `user-impact-reviewer` will be invoked at review-time.

## Hypotheses

> Network/connectivity gate: this plan involves `git pull` over HTTPS to GitHub via installation auth. Per the network-outage checklist, before concluding "sync logic is broken," Phase 0 MUST verify the L3→L7 order: (1) the workspace dir's `git remote -v` resolves and the GitHub App installation token is valid (auth, not firewall — egress to api.github.com is the dependency); (2) `git pull --ff-only` actually executes and returns non-zero vs. silently no-ops. Do NOT propose a logic fix before confirming the pull command runs and its exit status. The `reportSilentFallback` swallow means a 30s timeout or auth-401 looks identical to "nothing to pull" in the current code.

**H1 — Path-resolution divergence (primary).** Read path (`users.workspace_path`) ≠ write path (`<WORKSPACES_ROOT>/<workspace_id>`). Confirm by resolving both for the affected operator and `ls`-ing both dirs: the one with the `design/` folder + 5w mtimes is the read dir; the one with current content (if any) is the write dir.

**H2 — Silent non-fast-forward.** `git pull --ff-only` aborts on divergence; `reportSilentFallback` swallows it. The `design/` delete upstream + a local auto-commit (`session-sync.ts` auto-commits `knowledge-base/` paths) creates divergence. Confirm via `git -C <readdir> status` + `git -C <readdir> log --oneline -5` + a dry-run `git pull --ff-only` to observe the actual exit/error.

**H3 — Webhook never dispatched.** The push that deleted `design/` (5w ago) predates the #4224 webhook-reconcile feature (merged later) OR predates ADR-044's v=2 schema. v=1 envelopes drain to `{ok:false}` via the schema-gate (`workspace-reconcile-on-push.ts:123-139`); a push from before the webhook existed never reconciled at all. Confirm: was webhook-reconcile live at the time the operator's last source change landed? If not, only the manual "Sync now" path could recover — test it explicitly.

**H4 — `repo_status`/`workspace_status` gate blocks the read.** `/api/kb/tree` 404s if `repo_status === "not_connected"` and 503s if `workspace_status !== "ready"` (`tree/route.ts:17,21`). Stale tree implies the gates pass, so the row IS `ready`/connected — but confirm the row's `repo_url` matches the repo the webhook fires for (ADR-044 `compose-before-normalize` parity, `workspace-reconcile-on-push.ts:144`), else the fan-out matches zero workspaces and silently skips.

## Files to Edit

- `apps/web-platform/server/workspace-resolver.ts` — make `resolveWorkspacePath(workspaceId, legacyWorkspacePath)` the **single** path authority. NOTE: the current body **ignores its `legacyWorkspacePath` arg** and always returns `<root>/<workspaceId>` (line 39-44) despite the doc-comment claiming a two-tier "honor legacy column" bridge — the doc and the code disagree. Reconcile this: either (a) honor the legacy column when set (matching the doc + the tree/sync read path), or (b) commit fully to workspace-id paths AND migrate legacy on-disk dirs. The decision is the crux of the fix — see Phase 2.
- `apps/web-platform/app/api/kb/tree/route.ts` — replace inline `path.join(userData.workspace_path, "knowledge-base")` (line 35) with the unified resolver; select `workspaces.id` if needed for the UUID scheme.
- `apps/web-platform/app/api/kb/sync/route.ts` — replace `userData.workspace_path` (line 116-121) with the unified resolver so manual "Sync now" targets the same dir the tree reads AND the reconcile writes.
- `apps/web-platform/server/kb-route-helpers.ts` — `authenticateAndResolveKbPath` (line 131) and `resolveUserKbRoot` (line 275) both build `kbRoot` from `userData.workspace_path`; route through the unified resolver. **Sibling-query audit (per `hr-type-widening-cross-consumer-grep`): every site that does `path.join(<...>.workspace_path, "knowledge-base")` must be swept** — grep below.
- `apps/web-platform/server/inngest/functions/workspace-reconcile-on-push.ts` — already uses `workspacePathForWorkspaceId` (line 223); confirm it agrees with the unified resolver post-fix (it is the *correct* side IF we commit to workspace-id, the *wrong* side if we honor legacy).
- `apps/web-platform/server/kb-route-helpers.ts` `syncWorkspace` (line 293-326) — classify the `git pull --ff-only` failure (non-fast-forward vs auth vs timeout) instead of one opaque `sync_failed`, so `kb_sync_history.error_class` is actionable and the desync chip (`kb-sync-status.tsx:61`) is accurate. Pairs with Observability section.
- `apps/web-platform/server/session-sync.ts` — `syncPull` (line 410) uses `users.workspace_path` indirectly via callers; confirm session-sync and reconcile target the SAME dir (agents must read the same tree the user sees).

## Files to Create

- `apps/web-platform/supabase/migrations/0XX_<reconcile_legacy_workspace_path>.sql` — ONLY if Phase 2 decides on-disk migration of legacy `<root>/<userId>` dirs to `<root>/<workspaceId>` is required. Read the 2-3 most-recent migrations first; this is a data/ops migration, not DDL — it may instead be a one-shot reconcile step in an Inngest function rather than a SQL file. Decide in Phase 2.
- `apps/web-platform/test/server/kb-sync-path-resolution.test.ts` — RED test asserting tree-read dir === manual-sync dir === reconcile-write dir for both a legacy (`users.workspace_path` set) and an ADR-044 (workspace-id) operator.

## Phase 0 — Confirm root cause on the live affected workspace (READ-ONLY, no prod writes)

> Per `hr-no-dashboard-eyeball-pull-data-yourself` + `hr-dev-prd-distinct-supabase-projects`: use read-only Supabase MCP / `doppler secrets get` probes against the affected operator's row; do NOT run integration suites against prod. All steps here are read-only.

0.1 Resolve the affected operator's `users` row: `workspace_path`, `workspace_status`, `repo_status`, `repo_url`, `github_installation_id`, and the matching `workspaces` row (`id`, `repo_url`, `github_installation_id`). Confirm the ADR-044 relocation state.
0.2 Compute BOTH candidate dirs: `users.workspace_path` (read path) and `<WORKSPACES_ROOT>/<workspaces.id>` (write path). `ls -la` + `git -C <dir> log --oneline -3` on each (read-only). Identify which holds the `design/` folder + 5w mtimes.
0.3 In the read dir: `git -C <readdir> status`, `git -C <readdir> remote -v`, and a **dry-run** `git -C <readdir> pull --ff-only --no-commit` (or `git fetch` + `git log HEAD..@{u}`) to observe whether a fast-forward is even possible — confirms/refutes H2.
0.4 Verify webhook-reconcile timeline (H3): when did webhook-reconcile + ADR-044 v=2 go live vs. the operator's last source push? `gh` / Inngest run history (read-only).
0.5 **Calibration:** read the actual current `resolveWorkspacePath` body and confirm the doc/code disagreement noted in Files to Edit. This determines whether the fix is "make code match doc (honor legacy)" or "make doc match code (commit to UUID) + migrate dirs."
0.6 Sibling-query sweep: `git grep -n 'workspace_path' apps/web-platform/server apps/web-platform/app | grep -i "join\|knowledge-base"` and `git grep -n 'workspacePathForWorkspaceId\|resolveWorkspacePath'` — enumerate EVERY path-resolution site so the fix is exhaustive, not whack-a-mole.

## Phase 1 — Make sync failures observable (RED first)

1.1 RED: test that a non-fast-forward `git pull` in `syncWorkspace` produces a distinct `error_class` (not the catch-all `sync_failed`) and a Sentry mirror with the actual git stderr.
1.2 GREEN: classify the `gitWithInstallationAuth(["pull","--ff-only"])` rejection in `syncWorkspace` (kb-route-helpers.ts:304) — detect non-fast-forward from git stderr; map to `ERROR_CLASS_NON_FAST_FORWARD` (already exported, `session-sync.ts:313`). Today the manual route hard-codes `sync_failed` (`sync/route.ts:138`) precisely because the helper cannot distinguish — close that gap.
1.3 Ensure the desync chip + reconnect affordance fire correctly (`kb-sync-status.tsx:61`) when `error_class` is non-fast-forward.

## Phase 2 — Unify path resolution (the core fix)

2.1 Decision gate (from Phase 0.5): honor-legacy vs. commit-to-UUID. **Default recommendation: honor legacy when `users.workspace_path` is set** (matches the read path that already serves existing operators and avoids an on-disk dir migration) AND fix the reconcile write path to use the SAME resolver so the webhook pulls into the dir the tree reads. This makes `resolveWorkspacePath` match its doc-comment and become the single authority.
2.2 RED: `kb-sync-path-resolution.test.ts` asserts read===sync===reconcile dir for legacy + ADR-044 operators.
2.3 GREEN: route `tree/route.ts`, `sync/route.ts`, `kb-route-helpers.ts` (both helpers), and `workspace-reconcile-on-push.ts` through `resolveWorkspacePath`. Reconcile must resolve via the workspace's owner's legacy `workspace_path` when set (the reconcile already has `ws.id` + `ownerId`; add the legacy lookup).
2.4 If Phase 0 shows ADR-044-provisioned operators with NO legacy path AND a reconcile writing to a UUID dir the tree can't read → the tree must also resolve via workspace-id; ensure `tree/route.ts` selects the workspace row, not just `users.workspace_path`.

## Phase 3 — Recover the already-stale workspace (the `design/` folder + frozen tree)

3.1 Once paths are unified, the affected dir still holds stale content (deleted `design/`, frozen mtimes) IF H2 (non-fast-forward) co-occurs. A `--ff-only` pull cannot delete `design/` if local history diverged. Provide a **bounded, allowlisted recovery**: per `session-sync.ts` the connected-repo git wrapper forbids `reset`/`clean`/`checkout` (`ALLOWED_GIT_SUBCOMMANDS`, line 38) — do NOT weaken that allowlist. Instead, the recovery for a genuinely diverged KB working tree is a re-provision (re-clone) of the workspace, or an operator-safe reconcile step. Decide in Phase 3 whether a one-shot reconcile Inngest function (re-clone into the canonical dir) is the right recovery — automate it; do NOT leave "operator re-clones manually" as an output (`hr-never-label-any-step-as-manual-without`).
3.2 Verify post-recovery: tree no longer shows `design/`, mtimes current, `kb_sync_history` latest row `ok:true`.

## Acceptance Criteria

### Pre-merge (PR)
- [ ] `kb-sync-path-resolution.test.ts` proves tree-read, manual-sync, and webhook-reconcile resolve the **identical** on-disk dir for (a) a legacy `users.workspace_path` operator and (b) an ADR-044 workspace-id operator.
- [ ] `syncWorkspace` classifies non-fast-forward distinctly from auth/timeout/IO; the manual `/api/kb/sync` route no longer hard-codes `sync_failed` for every failure (`sync/route.ts:138` gap closed).
- [ ] A unit test proves `resolveWorkspacePath` either honors `legacyWorkspacePath` when set (matching its doc) or the doc is corrected to match UUID-only behavior — code and doc agree.
- [ ] Sibling-query sweep (Phase 0.6) result pasted into PR body: every `workspace_path`+`knowledge-base` join site routes through the unified resolver.
- [ ] PR body uses `Ref #<issue>` (not `Closes`) if recovery of the live workspace is a post-merge operator/automation step; otherwise `Closes`.

### Post-merge (operator / automation)
- [ ] On the affected workspace, the KB tree shows current content (no `design/` folder), current timestamps, and `kb_sync_history` latest row `ok:true`. **Automation:** prefer a one-shot reconcile Inngest function fired on merge (per Phase 3.1) over an operator step; if genuinely operator-only, justify with `Automation: not feasible because <X>`.

## Domain Review

**Domains relevant:** Engineering, Product (Product/UX Gate — ADVISORY: no new UI surface, but the KB tree's correctness is the user-facing artifact).

### Engineering
**Status:** reviewed
**Assessment:** Core defect is a read/write path-resolution seam opened by ADR-044. Fix unifies resolution through `workspace-resolver.ts` and adds failure observability. Risk: on-disk dir migration for legacy operators if UUID-only is chosen — prefer honor-legacy to avoid it.

### Product/UX Gate
**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none
**Skipped specialists:** none
**Pencil available:** N/A

#### Findings
No new interactive surface; the change makes the existing KB tree reflect reality. The user-facing artifact is correctness of the tree + accuracy of the sync chip, covered by ACs.

## Observability

```yaml
liveness_signal:
  what: kb_sync_history latest-row ok:true + sync_completed_at advancing per webhook push / manual sync
  cadence: per push (webhook reconcile) + on-demand (manual sync)
  alert_target: Sentry (workspace-reconcile-push feature) + Better Stack pino drain
  configured_in: apps/web-platform/server/session-sync.ts (appendKbSyncRow), workspace-reconcile-on-push.ts
error_reporting:
  destination: Sentry via reportSilentFallback (feature kb-route-helpers / workspace-reconcile-push)
  fail_loud: true — non-fast-forward now classified distinctly (Phase 1.2), no longer swallowed as opaque sync_failed
failure_modes:
  - mode: non-fast-forward pull (divergent local working tree)
    detection: git stderr classification in syncWorkspace
    alert_route: kb_sync_history.error_class=non_fast_forward → desync chip + Sentry
  - mode: path-resolution divergence (read dir != write dir)
    detection: kb-sync-path-resolution.test.ts (regression guard); runtime invariant — resolver is single authority
    alert_route: compile-time (single resolver) + test
  - mode: webhook fan-out matches zero workspaces (repo_url parity drift)
    detection: existing pino info log skip-no-workspace-match (workspace-reconcile-on-push.ts:193)
    alert_route: Better Stack (intentionally not Sentry per #4666)
logs:
  where: Better Stack (pino) + Sentry; kb_sync_history JSONB (per-operator, capped 100)
  retention: Better Stack default; kb_sync_history last 100 rows
discoverability_test:
  command: "curl -s -H 'cookie: <session>' https://app.soleur.ai/api/kb/tree | jq '.tree.children[].name, .lastSync'"
  expected_output: "no 'design' entry; lastSync.ok == true with recent sync_completed_at"
```

## Open Code-Review Overlap

None — no open `code-review`-labelled issue names the path-resolution files (tree/route.ts, sync/route.ts, workspace-resolver.ts, kb-route-helpers.ts). (Phase 0.6 sweep will re-confirm against the live issue list at /work time.)

## Test Scenarios

1. Legacy operator (`users.workspace_path` set): push to source deletes a folder → webhook reconcile pulls into the SAME dir the tree reads → tree reflects the deletion. (Pre-fix: fails — different dirs.)
2. ADR-044 operator (workspace-id path, no legacy): same push → tree + reconcile agree.
3. Non-fast-forward: local KB working tree diverged → `syncWorkspace` returns classified non-fast-forward → desync chip shows "Workspace out of sync", not a false "Synced".
4. Manual "Sync now" pulls into the dir the tree reads (regression guard for the read===sync invariant).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (This plan's section is filled.)
- `resolveWorkspacePath`'s doc-comment claims a two-tier legacy bridge but the **code ignores `legacyWorkspacePath` and always returns the UUID path** — do not trust the doc; the Phase 2 decision hinges on which behavior is correct. Confirm against the live affected operator's on-disk dirs in Phase 0 before choosing.
- Do NOT weaken `session-sync.ts` `ALLOWED_GIT_SUBCOMMANDS` (forbids `reset`/`clean`/`checkout`) to force-recover a diverged tree — that allowlist exists for #2905's failure class. Recovery of a diverged working tree is a re-provision, not a `git reset`.
- `git pull --ff-only` cannot delete an upstream-removed folder if local history diverged — Phase 3 recovery must account for this; a plain re-pull will NOT remove `design/` on a diverged tree.
- The `~5w` window: relative to the 2026-05-31 screenshot, ADR-044 (#4559) merged ~6 days prior, but the operator's last *good* sync was ~5w ago — meaning the freeze likely began BEFORE ADR-044 (candidate: the webhook-reconcile feature #4224 itself, or an earlier non-fast-forward). Phase 0.4 must pin the actual freeze-onset date against the deploy timeline before attributing causation — do not assume ADR-044 is the sole cause.
