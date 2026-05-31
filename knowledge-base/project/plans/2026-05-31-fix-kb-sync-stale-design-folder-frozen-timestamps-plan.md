---
title: "fix: KB sync stale — reconcile short-circuits ignored-repo before matching a real connected workspace"
type: bug
status: draft
created: 2026-05-31
branch: feat-one-shot-kb-sync-stale-design-folder
lane: single-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# 🐛 fix: Knowledge Base sync is stale — `design/` folder persists, timestamps frozen at ~5 weeks

> **This plan was rewritten 2026-05-31 against live production data.** The original v1/deepen plan hypothesized H1 (read/write path-resolution divergence) and H2 (silent non-fast-forward against a `--depth 1` shallow clone). **Both are disproven by the production `kb_sync_history` ledger** (see Evidence). They are retained only as "Rejected Hypotheses" so the disconfirming evidence is on record. The real cause is a reconcile **short-circuit ordering bug** introduced by PR #4666.

## Evidence (live prod, read-only via Doppler `DATABASE_URL_POOLER`, 2026-05-31)

Affected operator: `jean.deruelle@jikigai.com`, user/workspace id `52af49c2-d68e-477b-ba76-129e41807c7c`. **Solo** (workspace id == user id → migration-053 N2 invariant holds, so read-dir == write-dir; H1 cannot bite). The `ops@jikigai.com` row in the screenshot has `repo_url=null`/`workspace_path=null` and views the tree via the shared/org workspace — the connected workspace under the hood is `52af49c2`.

| Probe | Result | Implication |
|---|---|---|
| `users.repo_last_synced_at` (52af49c2) | `2026-04-26T10:30:31Z` | The "~5w ago" freeze onset, exactly. |
| `users.kb_sync_history` length / outcomes | **50 rows, ALL `ok=true`** (49 `webhook_push` + 1 `manual_sync`), spanning **only 2026-04-25 → 2026-04-26**, newest = `2026-04-26T10:30:31Z` | The ledger is a rolling cap. Newest entry is Apr 26 ⇒ **no reconcile has produced a sync since Apr 26.** Zero `ok=false` rows ever ⇒ **the sync is not failing — it stopped being attempted.** This disproves H2 (a failing `--ff-only` pull would write `ok=false` rows). |
| Git archaeology around freeze | #2799 (`--depth 1`, Apr 26) + #2802 (`--ff-only`, Apr 26); **the current `workspace-reconcile-on-push` Inngest path was created LATER** — #2854 (Apr 28) + #2891 (webhook emits the event, Apr 30) | The 50 `ok=true` rows were the **legacy** sync path's last day. The current reconcile path went live *after* the freeze and has produced **zero ledger rows of any kind** for this workspace. |
| Reconcile resolution query, reproduced exactly: `workspaces WHERE github_installation_id=89473706 AND repo_url='https://github.com/jikig-ai/soleur'` | **matches exactly 1 row** — workspace `52af49c2`, `repo_status=connected`; `workspace_members` has the `owner` row | The workspace IS resolvable. The fan-out loop (and `syncWorkspace`) is simply **never reached**. |
| `workspace-reconcile-on-push.ts:149` short-circuit | `if (isIgnoredReconcileRepo(targetRepoUrl)) return {ok:false, reason:"ignored-internal-repo"}` runs **before** the resolution query | `jikig-ai/soleur` is the default ignore slug (PR #4666). The push is dropped before the matching workspace is ever queried. **Root cause.** |

**Why the ledger is silent rather than showing failures:** both `ignored-internal-repo` (line 150) and `no-workspace-match` (line 203) `return` **before** `appendKbSyncRow` is ever called. So this entire class of freeze is invisible in the ledger — which is exactly why it went unnoticed for 5 weeks and why a prior fix (looking at sync mechanics) missed it.

## Root Cause

PR #4666 (`fix(reconcile): drop benign no-workspace-match from Sentry + skip internal repos`, merged 2026-05-30) added `jikig-ai/soleur` to `RECONCILE_IGNORED_REPO_SLUGS` to suppress Sentry noise from pushes that match **zero** workspaces. The intent was correct (the platform's own dev repo normally has no customer workspace), but the **short-circuit is placed before workspace resolution** (`workspace-reconcile-on-push.ts:149`). The Soleur founder **dogfoods their own KB from `jikig-ai/soleur`** — they have a real, `connected` workspace on that exact repo. So the ignore gate now drops every push to `jikig-ai/soleur` *before* discovering that a genuine workspace is attached, permanently starving the founder's KB of reconciles.

The Apr 26 freeze onset predates #4666 by a month: the legacy sync path was retired (#2854/#2891, Apr 28–30) and replaced by the new reconcile path, which during Apr 28 → May 30 matched zero workspaces for this repo (workspaces.repo_url was not populated for it until the ADR-044 backfill, #4559, May 25). The ADR-044 backfill *would* have un-frozen it on May 25 — but #4666 landed May 30 and re-blocked it via the ignore gate before a reconcile happened to fire in that window. Net: a real connected workspace has been starved continuously since Apr 26, and is now hard-blocked by the ignore-ordering bug.

## Fix

**(A) Reorder the ignore short-circuit to run AFTER workspace resolution, gated on zero matches** (`workspace-reconcile-on-push.ts`). Pseudocode:

```
const rows = (await resolve-workspaces).rows ?? []
if (rows.length === 0) {
  if (isIgnoredReconcileRepo(targetRepoUrl)) return { ok:false, reason:"ignored-internal-repo" } // silent, preserves #4666
  logger.info({ op:"skip-no-workspace-match", ... })                                            // pino-only, preserves #4666
  return { ok:false, reason:"no-workspace-match" }
}
// rows.length > 0: a real workspace is connected — ALWAYS reconcile, even for an "ignored" repo
```

This preserves #4666's entire intent — zero-workspace pushes to `jikig-ai/soleur` still skip silently with no Sentry/log noise — while never starving a repo that has a genuinely connected workspace. The extra DB query for ignored repos is one indexed `select id` and only on pushes that currently short-circuit; negligible.

**(B) Make the silent freeze observable (the gap that hid this for 5 weeks).** A repo that has connected workspaces but is on the ignore-list is a *misconfiguration* worth one Sentry breadcrumb (not a flood — it fires at most once per push to such a repo, and after fix (A) the founder's repo is no longer in that state). Emit a `warnSilentFallback`/pino warning when `rows.length > 0 && isIgnoredReconcileRepo(targetRepoUrl)` so an ignore-list that shadows a real workspace can never again be silent. Keep `no-workspace-match` at pino-info per #4666.

**(C) Recover the already-frozen workspace.** Reconcile fix (A) only fixes *go-forward* pushes; the on-disk `52af49c2` workspace still holds the stale tree (deleted `design/`, Apr-26 mtimes). Recovery = dispatch one `platform/workspace.reconcile.requested` event for this installation/repo (the same path a push uses) so the existing reconcile pulls current `main` and the tree refreshes. This MUST be automation, not an operator step (`hr-never-label-any-step-as-manual-without`): trigger it via `inngest.send` from a one-shot event-triggered function (canonical per ADR-033; precedent: the `oneshot-*.ts` functions already registered in `app/api/inngest/route.ts`). If the pull cannot fast-forward the shallow clone (the H2 mechanism — possible but unconfirmed for this dir), the recovery function falls back to `removeWorkspaceDir` + `provisionWorkspaceWithRepo` (re-clone), reusing existing `workspace.ts` helpers; do NOT weaken `session-sync.ts` `ALLOWED_GIT_SUBCOMMANDS`.

## Rejected Hypotheses (from v1/deepen — disproven by Evidence)

- **H1 — read/write path-resolution divergence (ADR-044).** Disproven: the affected operator is solo (workspace id == user id, N2), so read-dir and write-dir are identical. Divergence cannot occur.
- **H2 — silent non-fast-forward against the `--depth 1` shallow clone.** Disproven: a failing `git pull --ff-only` writes an `ok=false` / `error_class=sync_failed` ledger row. The ledger has **zero** `ok=false` rows. The sync code is never reached, so its git mechanics are irrelevant to this freeze. (Retained as the fallback path inside recovery (C) only.)
- **H5 — `fullName` omission in the reconcile payload.** Already rejected at deepen; `webhook-push-reconcilable.ts:56` returns all fields. No change.

## Files to Edit

- `apps/web-platform/server/inngest/functions/workspace-reconcile-on-push.ts` — fix (A) reorder; fix (B) shadowed-workspace warning. The `isIgnoredReconcileRepo` / `repoSlug` / `RECONCILE_IGNORED_REPO_SLUGS` helpers are unchanged; only the call-site ordering moves.
- `apps/web-platform/test/server/inngest/workspace-reconcile-on-push.test.ts` (create or extend) — RED tests, see Test Scenarios.

## Files to Create

- `apps/web-platform/server/inngest/functions/oneshot-kb-reconcile-recovery.ts` — fix (C) one-shot recovery function (event-triggered, dispatches a reconcile for the stale workspace; self-disabling). Register in `app/api/inngest/route.ts`. Model on the existing `oneshot-4650-monitor-close.ts` pattern. **Only if Phase 0 confirms a plain reconcile does not self-recover the dir** — if dispatching one reconcile event un-freezes it, recovery is just that dispatch + verification, no new file.

## Phase 0 — Confirm fix sufficiency (READ-ONLY; live diagnosis already done)

The live diagnosis in Evidence is complete and authoritative. Phase 0 remaining:
0.1 Re-confirm at /work time (state can move): re-run the reconcile match query (must still return ≥1 row for `52af49c2`) and re-confirm `jikig-ai/soleur ∈ RECONCILE_IGNORED_REPO_SLUGS` default. (Both confirmed 2026-05-31.)
0.2 Confirm the on-disk dir `/data/workspaces/52af49c2-...` exists and is shallow — informs whether recovery (C) needs the re-clone fallback. **This requires the app host; do NOT SSH** (`hr-no-ssh-fallback-in-runbooks`). Instead: dispatch the recovery reconcile (C) and read the resulting `kb_sync_history` row — `ok=true` ⇒ plain reconcile sufficed; `ok=false error_class=non_fast_forward` ⇒ the re-clone fallback is needed. The ledger is the observability layer; no host access required.
0.3 Sweep for OTHER ignored repos that shadow a real workspace: `select w.id, w.repo_url from workspaces w where regexp_replace(regexp_replace(w.repo_url,'^https?://[^/]+/',''),'\.git$','') = any(string_to_array('jikig-ai/soleur', ','))`. If any non-founder workspace is also shadowed, fix (A) covers it automatically — note in PR body.

## Acceptance Criteria

### Pre-merge (PR)
- [ ] **(A)** RED test: a push to an ignored repo (`jikig-ai/soleur`) that HAS ≥1 connected workspace reconciles all matched workspaces (fan-out runs, `appendKbSyncRow` called) — fails on current `main` (short-circuits at `ignored-internal-repo`), passes after the reorder.
- [ ] **(A)** Regression test: a push to an ignored repo with ZERO connected workspaces still returns `ignored-internal-repo` with NO Sentry mirror and NO `kb_sync_history` row (preserves #4666).
- [ ] **(A)** Regression test: a push to a non-ignored repo with zero workspaces still returns `no-workspace-match` at pino-info, no Sentry (preserves #4666).
- [ ] **(B)** A push to an ignored repo that HAS connected workspaces emits exactly one shadowed-workspace warning (assert the mirror/log fires).
- [ ] Full `workspace-reconcile-on-push` suite green; `./node_modules/.bin/tsc --noEmit` clean in `apps/web-platform`.
- [ ] PR body uses `Closes #<issue>` if recovery is automated in-PR (fix C ships), else `Ref` + automated post-merge recovery.

### Post-merge (automation, not operator)
- [ ] **(C)** Recovery reconcile dispatched for `52af49c2`; verify via `kb_sync_history`: a new `ok=true` row dated post-merge, and the KB tree (via `/api/kb/tree`) shows **no `design/` folder** and current timestamps. Automated through the one-shot Inngest function / event dispatch — no operator step.

## Observability

```yaml
liveness_signal:
  what: kb_sync_history newest row ok:true with sync_completed_at advancing per push to a connected repo
  cadence: per webhook push (reconcile) + on-demand manual sync
  alert_target: Sentry (workspace-reconcile-push feature) + Better Stack pino drain
  configured_in: workspace-reconcile-on-push.ts (appendKbSyncRow), session-sync.ts
error_reporting:
  destination: Sentry via reportSilentFallback / warnSilentFallback (feature workspace-reconcile-push)
  fail_loud: true — shadowed-workspace (ignored repo WITH connected workspaces) now warns (fix B); previously silent
failure_modes:
  - mode: ignore-list shadows a real connected workspace (THIS bug)
    detection: fix (B) warnSilentFallback when rows.length>0 && isIgnoredReconcileRepo
    alert_route: Sentry breadcrumb + pino
  - mode: push matches zero workspaces (benign)
    detection: pino info skip-no-workspace-match (preserved from #4666)
    alert_route: Better Stack only (intentionally not Sentry per #4666)
  - mode: sync git failure (non-fast-forward etc.)
    detection: appendKbSyncRow ok=false error_class in the fan-out loop
    alert_route: kb_sync_history.error_class → desync chip + Sentry
logs:
  where: Better Stack (pino) + Sentry; users.kb_sync_history JSONB (per-operator, rolling cap)
  retention: Better Stack default; kb_sync_history rolling cap
discoverability_test:
  command: "curl -s -H 'cookie: <session>' https://app.soleur.ai/api/kb/tree | jq '.tree.children[].name, .lastSync'"
  expected_output: "no 'design' entry; lastSync.ok == true with recent sync_completed_at"
```

## User-Brand Impact

- **If this lands broken, the user experiences:** the KB tree keeps showing a deleted `design/` folder and frozen "5w ago" timestamps — the product's core "your knowledge base, always current" promise is visibly false on every page load, and agents read 5-week-stale KB context into prompts (the workspace dir feeds both the tree and agent sessions).
- **If this leaks:** no data-leak vector (same-tenant, RLS-scoped). The exposure is workflow trust: decisions and agent context built on a stale KB.
- **Brand-survival threshold:** single-user incident — the founder's own KB frozen for 5 weeks on a knowledge-base product. CPO sign-off required (frontmatter); `user-impact-reviewer` invoked at review time.

## Domain Review

**Domains relevant:** Engineering (single-domain — one Inngest function + one recovery function). Product/UX: advisory only (no new UI surface; the user-facing artifact is the KB tree reflecting reality, covered by ACs).

### Engineering
**Status:** reviewed
**Assessment:** Single-domain reconcile-ordering fix. The defect is a short-circuit placed before workspace resolution (PR #4666); the fix reorders it to gate on zero-matches, preserving the Sentry-noise suppression while never starving a connected workspace. Recovery of the already-frozen dir is an event dispatch reusing the existing reconcile path (re-clone fallback via existing `workspace.ts` helpers). No path-resolution change (N2 makes solo dirs aligned), no schema change, no allowlist weakening.

### Product/UX Gate
**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none
**Skipped specialists:** none
**Pencil available:** N/A

#### Findings
No new interactive surface; the change makes the existing KB tree reflect reality.

## Test Scenarios

1. **Ignored repo WITH connected workspace** (the bug): event for `jikig-ai/soleur`, installation 89473706, with a matching `workspaces` row → fan-out reconciles it, `appendKbSyncRow` called. (Pre-fix: returns `ignored-internal-repo`, no sync.)
2. **Ignored repo with ZERO workspaces** (preserve #4666): event for `jikig-ai/soleur` with no matching workspace → `ignored-internal-repo`, no Sentry, no ledger row.
3. **Non-ignored repo, zero workspaces** (preserve #4666): → `no-workspace-match` at pino-info, no Sentry.
4. **Shadowed-workspace warning** (fix B): ignored repo with ≥1 workspace emits exactly one warning mirror.
5. **Recovery** (fix C): dispatching the recovery event for `52af49c2` produces a fresh `ok=true` ledger row and a tree with no `design/`.

## Sharp Edges

- The ignore-list (`RECONCILE_IGNORED_REPO_SLUGS`) is still valuable for *zero-workspace* internal pushes — do NOT delete it; only move WHERE it is evaluated (after resolution, gated on `rows.length===0`).
- `users.kb_sync_history` short-circuit blindness: `ignored-internal-repo` and `no-workspace-match` write no ledger row by design. Fix (B) adds a Sentry breadcrumb only for the shadowed-workspace case, not for benign zero-workspace skips — keep that distinction or #4666's noise returns.
- Recovery (C) must be automation, not an operator step (`hr-never-label-any-step-as-manual-without`). The dispatch + ledger-read verification needs no host SSH (`hr-no-ssh-fallback-in-runbooks`).
- Solo-user N2 invariant (migration 053): workspace id == user id for solo operators, so the founder's read-dir == write-dir. Do not reintroduce H1 path-unification work — it is a no-op for this incident.
- If Phase 0.3 finds other shadowed workspaces, fix (A) covers them; surface the list in the PR body so the founder knows the blast radius.
