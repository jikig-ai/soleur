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

## Enhancement Summary (deepen-pass, 2026-05-31)

**Verified corrections applied to the v1 plan (each grep/read-confirmed against the codebase):**

1. **N2 invariant re-ranks the hypotheses.** Migration 053 (`053_organizations_and_workspace_members.sql:35,63`) + ADR-044 §42 establish `workspaces.id == users.id` for **solo** users. So `users.workspace_path` (`/workspaces/<userId>`, read path) and `workspacePathForWorkspaceId(ws.id)` (`/workspaces/<workspaceId>`, write path) point at the **SAME directory for a solo operator** — **H1 path-divergence does NOT bite solo users**, only non-solo org members whose active workspace ≠ solo workspace. For the likely (solo) screenshot subject, **H2 (silent non-fast-forward) is the prime suspect**, not H1.
2. **Shallow-clone amplifies H2.** Provisioning clones `--depth 1` (`workspace.ts:173`); `syncWorkspace` runs `git pull --ff-only` (`kb-route-helpers.ts:304`) via `promisify(execFile)` (rejects on non-zero → throws → swallowed by `reportSilentFallback`). A depth-1 tree cannot fast-forward across an upstream rebase/squash/force-push (no merge base) → `--ff-only` aborts → frozen tree. This is the most likely concrete mechanism.
3. **H5 (reconcile payload field omission) investigated and REJECTED.** A partial grep suggested `webhook-push-reconcilable.ts` dropped `fullName`/`defaultBranch` from its `ok:true` return; the **full file read disproves it** — line 56 returns all fields and fail-closes on missing `full_name`. No action. (Recorded as a worked example of why deepen full-file reads beat grep previews.)
4. **Phantom-function correction.** The v1 Files-to-Edit referenced `resolveWorkspacePath(workspaceId, legacyWorkspacePath)` with a "doc vs code disagreement." **No such function exists.** Real exports: `workspacePathForWorkspaceId(workspaceId)` (resolver:265) and `resolveWorkspacePathForUser(userId, supabase)` (resolver:250). Corrected in Files-to-Edit + Phase 2 below.
5. **Sibling-query sweep (per `hr-type-widening-cross-consumer-grep`).** `users.workspace_path` is read at 9 production sites; the H1 fix (if pursued for org members) must address each — but per N2 all are CORRECT for solo users. Enumerated in Files-to-Edit.

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

**H2 — Silent non-fast-forward against a SHALLOW clone (deepen-pass prime suspect for solo users).** Provisioning clones `--depth 1` (`workspace.ts:173`). `syncWorkspace` runs `git pull --ff-only` (`kb-route-helpers.ts:304`); `gitWithInstallationAuth` uses `promisify(execFile)` which rejects on non-zero exit, so a failed pull throws and is swallowed by `reportSilentFallback`. A depth-1 tree cannot fast-forward across an upstream rebase/squash/force-push/history-rewrite (the shallow history lacks the merge base) → `--ff-only` aborts → the `design/` delete + 5w of commits never land. Local auto-commits (`session-sync.ts` auto-commits `knowledge-base/`) compound it. Confirm: `git -C <readdir> rev-parse --is-shallow-repository` (expect `true`), `git -C <readdir> status`, `git -C <readdir> log --oneline -5`, then a dry-run `git -C <readdir> pull --ff-only` to observe the non-ff abort. Fix candidates: `git fetch --unshallow` before the ff-only pull, OR re-clone on non-ff. (Note: `syncPull` session path uses `--no-rebase --autostash` and may merge where reconcile/manual `--ff-only` freeze.)

**H1 — Path-resolution divergence (org members only — NOT solo users, per N2).** Read path (`users.workspace_path`) ≠ write path (`<WORKSPACES_ROOT>/<workspace_id>`) ONLY when a member's active workspace ≠ their solo workspace (ADR-044 §49 names exactly this rollback hazard). For solo users, migration 053's `workspaces.id == users.id` backfill makes them the SAME directory. Confirm the affected operator's membership shape FIRST: if solo, deprioritize H1 → pursue H2. If org member, resolve both dirs and `ls` each: the one with `design/` + 5w mtimes is the read dir; the one with current content (if any) is the write dir.

**H3 — Webhook never dispatched.** The push that deleted `design/` (5w ago) predates the #4224 webhook-reconcile feature (merged later) OR predates ADR-044's v=2 schema. v=1 envelopes drain to `{ok:false}` via the schema-gate (`workspace-reconcile-on-push.ts:123-139`); a push from before the webhook existed never reconciled at all. Confirm: was webhook-reconcile live at the time the operator's last source change landed? If not, only the manual "Sync now" path could recover — test it explicitly.

**H4 — `repo_status`/`workspace_status` gate blocks the read.** `/api/kb/tree` 404s if `repo_status === "not_connected"` and 503s if `workspace_status !== "ready"` (`tree/route.ts:17,21`). Stale tree implies the gates pass, so the row IS `ready`/connected — but confirm the row's `repo_url` matches the repo the webhook fires for (ADR-044 `compose-before-normalize` parity, `workspace-reconcile-on-push.ts:144`), else the fan-out matches zero workspaces and silently skips.

## Files to Edit

> Deepen-pass: scope depends on which hypothesis Phase 0 confirms. **If H2 (shallow-clone non-ff) is confirmed** (likely for solo users), the fix centers on `syncWorkspace` (unshallow + recovery + failure classification) — NOT the resolver unification. The resolver work applies ONLY to H1 (org-member divergence). Do NOT over-build; pursue the confirmed hypothesis.

- `apps/web-platform/server/kb-route-helpers.ts` **(H2 — likely the fix)** — `syncWorkspace` (line 293-326) runs only `git pull --ff-only` against a `--depth 1` clone. Add: (a) classify the non-fast-forward failure from git stderr → `ERROR_CLASS_NON_FAST_FORWARD` (already exported, `session-sync.ts:313`) instead of opaque `sync_failed`; (b) on non-ff, `git fetch --unshallow` (idempotent if already complete) then retry `pull --ff-only`, OR trigger re-clone recovery (Phase 3). NOTE: `syncWorkspace` calls `gitWithInstallationAuth` directly (NOT the `session-sync` connected-repo wrapper), so `fetch --unshallow` is reachable here without weakening any allowlist — confirm in Phase 0.
- `apps/web-platform/server/webhook-push-reconcilable.ts` — **H5 REJECTED, no change.** Verified `:56` returns all required fields (`defaultBranch`, `fullName`) and fail-closes on missing `full_name`. Listed only to record it was checked.
- `apps/web-platform/server/workspace-resolver.ts` — **no new function needed** (H1 path only). The unified authority is the EXISTING `workspacePathForWorkspaceId(await resolveCurrentWorkspaceId(userId, tenant))` chain (ADR-044 §42 directive). The phantom `resolveWorkspacePath(workspaceId, legacy)` from the v1 plan does not exist — do not introduce it.
- `apps/web-platform/app/api/kb/tree/route.ts` (line 35) — **H1 only.** Replace inline `path.join(userData.workspace_path, "knowledge-base")` with the resolver chain. Note: route currently uses a SERVICE client; the resolver chain needs a tenant client — auth-context change.
- `apps/web-platform/app/api/kb/sync/route.ts` (line 116-121) — **H1 only.** Same resolver chain so manual "Sync now" targets the dir the tree reads AND the reconcile writes.
- `apps/web-platform/server/kb-route-helpers.ts` — `authenticateAndResolveKbPath` (line 131) + `resolveUserKbRoot` (line 275) build `kbRoot` from `users.workspace_path`; route through the resolver chain for H1.
- `apps/web-platform/server/inngest/functions/workspace-reconcile-on-push.ts` (line 223) — already uses `workspacePathForWorkspaceId(ws.id)` (the ADR-044-correct side). No change for H1; for H2 it inherits the `syncWorkspace` fix automatically.
- `apps/web-platform/server/session-sync.ts` — `syncPull`/`syncPush` operate on a caller-passed `workspacePath` (agent-runner). Confirm agent-runner (`agent-runner.ts:944`) resolves the same dir post-fix so agents read the tree the user sees.

**Sibling-query sweep result (Phase 0.6, run at deepen — `hr-type-widening-cross-consumer-grep`):** `users.workspace_path` is read at 9 production sites — `kb-route-helpers.ts` (×2), `kb-document-resolver.ts:93` (agent KB read), `kb-share.ts:687/779` (share/preview), `kb/upload/route.ts:76/237`, `kb/tree/route.ts:35`, `kb/sync/route.ts:116`, `agent-runner.ts:936/944`, `attachment-pipeline.ts:133`, `dsar-export.ts:1985`. Per N2 all are CORRECT for solo users today; only org members diverge. Address EACH only if H1 (org-member divergence) is the confirmed root cause — do NOT rewrite all 9 for an H2 (shallow-clone) bug.

## Files to Create

- `apps/web-platform/supabase/migrations/0XX_<reconcile_legacy_workspace_path>.sql` — ONLY if Phase 2 decides on-disk migration of legacy `<root>/<userId>` dirs to `<root>/<workspaceId>` is required. Read the 2-3 most-recent migrations first; this is a data/ops migration, not DDL — it may instead be a one-shot reconcile step in an Inngest function rather than a SQL file. Decide in Phase 2.
- `apps/web-platform/test/server/kb-sync-path-resolution.test.ts` — RED test asserting tree-read dir === manual-sync dir === reconcile-write dir for both a legacy (`users.workspace_path` set) and an ADR-044 (workspace-id) operator.

## Phase 0 — Confirm root cause on the live affected workspace (READ-ONLY, no prod writes)

> Per `hr-no-dashboard-eyeball-pull-data-yourself` + `hr-dev-prd-distinct-supabase-projects`: use read-only Supabase MCP / `doppler secrets get` probes against the affected operator's row; do NOT run integration suites against prod. All steps here are read-only.

0.0 **H2 shallow-clone check FIRST (cheapest, highest-value).** On the affected operator's read dir: `git -C <readdir> rev-parse --is-shallow-repository` (expect `true`), then a read-only `git -C <readdir> pull --ff-only` to observe the abort. A `fatal: Not possible to fast-forward` confirms H2 — the shallow clone can't fast-forward across the upstream history that deleted `design/`. (H5 — a suspected `fullName` omission — was checked at deepen and REJECTED; `webhook-push-reconcilable.ts:56` returns all fields. Do not re-investigate.)
0.1 Resolve the affected operator's `users` row: `workspace_path`, `workspace_status`, `repo_status`, `repo_url`, `github_installation_id`, and the matching `workspaces` row (`id`, `repo_url`, `github_installation_id`). **Determine membership shape: solo (workspace_id == user_id, N2) or org member.** If solo, H1 is ruled out (read dir == write dir per migration 053) → focus H2.
0.2 Compute BOTH candidate dirs: `users.workspace_path` (read path) and `<WORKSPACES_ROOT>/<workspaces.id>` (write path). For solo users these are identical (N2); for org members they may differ. `ls -la` + `git -C <dir> log --oneline -3` on each (read-only). Identify which holds the `design/` folder + 5w mtimes.
0.3 In the read dir: `git -C <readdir> status`, `git -C <readdir> remote -v`, `--is-shallow-repository`, and a **dry-run** `git -C <readdir> pull --ff-only` to observe whether a fast-forward is even possible — confirms/refutes H2.
0.4 Verify webhook-reconcile timeline (H3): when did webhook-reconcile (#4224) + ADR-044 v=2 go live vs. the operator's last source push? `gh` / Inngest run history (read-only).
0.5 **Calibration:** read the actual `workspace-resolver.ts` exports (`workspacePathForWorkspaceId`, `resolveWorkspacePathForUser`, `resolveCurrentWorkspaceId`) — there is NO `resolveWorkspacePath(workspaceId, legacy)` function. Confirm the resolver chain `workspacePathForWorkspaceId(resolveCurrentWorkspaceId(...))` is the ADR-044 §42 directive before any H1 work.
0.6 Sibling-query sweep: `git grep -n 'workspace_path' apps/web-platform/server apps/web-platform/app | grep -i "join\|knowledge-base"` and `git grep -n 'workspacePathForWorkspaceId\|resolveCurrentWorkspaceId'` — enumerate EVERY path-resolution site (9 known, listed in Files to Edit) so an H1 fix is exhaustive.

## Phase 1 — Make sync failures observable (RED first)

1.1 RED: test that a non-fast-forward `git pull` in `syncWorkspace` produces a distinct `error_class` (not the catch-all `sync_failed`) and a Sentry mirror with the actual git stderr.
1.2 GREEN: classify the `gitWithInstallationAuth(["pull","--ff-only"])` rejection in `syncWorkspace` (kb-route-helpers.ts:304) — detect non-fast-forward from git stderr; map to `ERROR_CLASS_NON_FAST_FORWARD` (already exported, `session-sync.ts:313`). Today the manual route hard-codes `sync_failed` (`sync/route.ts:138`) precisely because the helper cannot distinguish — close that gap.
1.3 Ensure the desync chip + reconnect affordance fire correctly (`kb-sync-status.tsx:61`) when `error_class` is non-fast-forward.

## Phase 2 — Unify path resolution (H1 only — org-member divergence)

> Run this phase ONLY if Phase 0 confirms H1 (org member whose active workspace ≠ solo workspace). For a solo operator with H2 confirmed, SKIP to Phase 3 recovery — the read and write dirs already agree per N2.

2.1 The unification target is the EXISTING resolver chain `workspacePathForWorkspaceId(await resolveCurrentWorkspaceId(userId, tenant))` (ADR-044 §42 directive) — NOT a new function. The reconcile already uses `workspacePathForWorkspaceId(ws.id)` (correct side); the KB read endpoints use the `users.workspace_path` denorm cache (the divergent side for org members). Align the read endpoints to the reconcile's authority.
2.2 RED: `kb-sync-path-resolution.test.ts` asserts tree-read === manual-sync === reconcile dir for (a) a solo operator (N2: already equal) and (b) a non-solo org member whose active workspace ≠ solo workspace.
2.3 GREEN: route `tree/route.ts` (line 35), `sync/route.ts` (line 116), `kb-route-helpers.ts` (both helpers) through `workspacePathForWorkspaceId(resolveCurrentWorkspaceId(...))`. The reconcile (`workspace-reconcile-on-push.ts:223`) already resolves correctly — no change.
2.4 Confirm the agent KB read path (`kb-document-resolver.ts:93`) and share path (`kb-share.ts:687`) also align, or document why they may legitimately lag (sibling-query sweep hits).

## Phase 3 — Recover the already-stale workspace (the `design/` folder + frozen tree)

3.1 The affected dir holds stale content (deleted `design/`, frozen mtimes) because the shallow `--ff-only` pull aborted non-fast-forward (H2). A `--ff-only` pull cannot delete `design/` across a diverged/rewritten upstream history on a shallow clone. Recovery options, in preference order: (a) `git fetch --unshallow` then `git pull --ff-only` (reachable from `syncWorkspace` which calls `gitWithInstallationAuth` directly, bypassing the `session-sync` wrapper allowlist); (b) if still non-ff (genuine local divergence), re-provision via teardown + re-clone reusing `removeWorkspaceDir` + `provisionWorkspaceWithRepo` (`workspace.ts`). Do NOT weaken `session-sync.ts` `ALLOWED_GIT_SUBCOMMANDS` (forbids `reset`/`clean`/`checkout` per #2905). Automate the recovery as a one-shot event-triggered Inngest function (canonical per ADR-033, 32 `cron-*.ts` precedents) — do NOT leave "operator re-clones manually" as an output (`hr-never-label-any-step-as-manual-without`).
3.2 Verify post-recovery: tree no longer shows `design/`, mtimes current, `kb_sync_history` latest row `ok:true`.

## Precedent-Diff (deepen Phase 4.4)

- **Scheduled-work:** reconcile is already an Inngest function (canonical per ADR-033; 32 `cron-*.ts` precedents). Phase 3 recovery, if it needs a one-shot re-clone, is a new event-triggered Inngest function — NOT GH Actions. Re-clone precedent: `provisionWorkspaceWithRepo` + `removeWorkspaceDir` (`workspace.ts`); recovery = teardown + re-provision, no novel pattern.
- **Path resolution:** ADR-044 §42 (`workspacePathForWorkspaceId(resolveCurrentWorkspaceId(...))`) is the canonical directive; the reconcile already follows it, the KB read endpoints do not. The H1 fix propagates an established pattern — no new pattern.
- **Failure classification:** `ERROR_CLASS_NON_FAST_FORWARD` already exists/exported (`session-sync.ts:313`) and is consumed by the reconcile; the manual route just never produces it. The fix wires existing constants. No `SECURITY DEFINER`/atomic-write/lock precedent applies (no SQL function or concurrent-write primitive introduced).

## Acceptance Criteria

### Pre-merge (PR)
- [ ] **(H2)** `syncWorkspace` classifies a non-fast-forward `git pull --ff-only` failure as `ERROR_CLASS_NON_FAST_FORWARD` (not opaque `sync_failed`) AND attempts shallow→full recovery (`fetch --unshallow` retry, or re-clone); a test drives a shallow-clone-vs-rebased-upstream fixture and asserts the recovery lands the upstream deletion. (RED first.)
- [ ] The manual `/api/kb/sync` route no longer hard-codes `sync_failed` for every failure (`sync/route.ts:138` gap closed).
- [ ] **(H1, only if confirmed)** `kb-sync-path-resolution.test.ts` proves tree-read === manual-sync === reconcile dir for (a) a solo operator (N2: already equal) and (b) a non-solo org member whose active workspace ≠ solo workspace.
- [ ] Sibling-query sweep (Phase 0.6) result pasted into PR body: the 9 `users.workspace_path` read sites are each scoped-in (H1) or scoped-out (N2-correct) with rationale.
- [ ] PR body uses `Ref #<issue>` (not `Closes`) if recovery of the live workspace is a post-merge operator/automation step; otherwise `Closes`.

### Post-merge (operator / automation)
- [ ] On the affected workspace, the KB tree shows current content (no `design/` folder), current timestamps, and `kb_sync_history` latest row `ok:true`. **Automation:** prefer a one-shot reconcile Inngest function fired on merge (per Phase 3.1) over an operator step; if genuinely operator-only, justify with `Automation: not feasible because <X>`.

## Domain Review

**Domains relevant:** Engineering, Product (Product/UX Gate — ADVISORY: no new UI surface, but the KB tree's correctness is the user-facing artifact).

### Engineering
**Status:** reviewed
**Assessment:** Deepen-pass re-frame — for solo operators (N2) the core defect is H2 (silent non-fast-forward against a `--depth 1` shallow clone), fixed in `syncWorkspace` with failure classification + unshallow/re-clone recovery. For org members only, H1 (read/write path seam from ADR-044) applies and is fixed by routing KB read endpoints through the existing `workspacePathForWorkspaceId(resolveCurrentWorkspaceId(...))` chain (ADR-044 §42). No on-disk dir migration needed (N2 makes solo dirs already-aligned).

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
- **Deepen-verified:** there is NO `resolveWorkspacePath(workspaceId, legacy)` function — the v1 plan invented it. Real exports: `workspacePathForWorkspaceId` (pure, resolver:265), `resolveWorkspacePathForUser` (async, resolver:250), `resolveCurrentWorkspaceId` (resolver:94). Use `workspacePathForWorkspaceId(resolveCurrentWorkspaceId(...))` per ADR-044 §42; do not re-introduce the phantom function at /work.
- **Deepen-verified:** H5 (suspected `fullName` omission in the reconcile payload) REJECTED — `webhook-push-reconcilable.ts:56` returns all required fields and fail-closes on missing `full_name`. Do not pursue.
- **Shallow clone (`workspace.ts:173`, `--depth 1`) is the H2 amplifier:** a plain re-pull will NOT remove an upstream-deleted `design/` across a rewritten history without `--unshallow` or re-clone. Phase 3.1 recovery accounts for this.
- Do NOT weaken `session-sync.ts` `ALLOWED_GIT_SUBCOMMANDS` (forbids `reset`/`clean`/`checkout`) to force-recover a diverged tree — that allowlist exists for #2905's failure class. Recovery of a diverged working tree is a re-provision, not a `git reset`.
- `git pull --ff-only` cannot delete an upstream-removed folder if local history diverged — Phase 3 recovery must account for this; a plain re-pull will NOT remove `design/` on a diverged tree.
- The `~5w` window: relative to the 2026-05-31 screenshot, ADR-044 (#4559) merged ~6 days prior, but the operator's last *good* sync was ~5w ago — the freeze likely began BEFORE ADR-044 (candidate: the webhook-reconcile feature #4224 itself, or an earlier shallow-clone non-fast-forward). Phase 0.4 must pin the actual freeze-onset date before attributing causation — do not assume ADR-044 is the sole cause.
- **Deepen-verified:** the v1 plan cited a non-existent `resolveWorkspacePath(workspaceId, legacyWorkspacePath)` function with a fabricated "doc vs code disagreement." Corrected — real exports are `workspacePathForWorkspaceId` (pure, resolver:265) and `resolveWorkspacePathForUser` (async, resolver:250). Do not re-introduce the phantom function at /work.
- **Deepen-verified:** H5 (a suspected `fullName` omission in the reconcile payload) was investigated and REJECTED — `webhook-push-reconcilable.ts:56` returns all required fields and fail-closes on missing `full_name`. Do not pursue H5.
- **Shallow clone is the H2 amplifier:** `workspace.ts:173` clones `--depth 1`; a plain re-pull will NOT remove an upstream-deleted `design/` across a rewritten history without `--unshallow` or re-clone. Recovery must account for this (Phase 3.1).
