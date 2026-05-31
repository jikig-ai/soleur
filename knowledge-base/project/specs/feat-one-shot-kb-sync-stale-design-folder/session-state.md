# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-05-31-fix-kb-sync-stale-design-folder-frozen-timestamps-plan.md
- Status: complete (rewritten 2026-05-31 against live prod data; original H1/H2 disproven)

### Errors
- Planning subagent (and my initial scratch note) anchored on H1 (path divergence) / H2 (shallow-clone non-fast-forward). Both disproven by the live `kb_sync_history` ledger. Plan rewritten.

### Root cause (data-confirmed, prod read-only via Doppler DATABASE_URL_POOLER)
- Affected workspace `52af49c2` (jean.deruelle@jikigai.com, solo → N2 holds), connected to `https://github.com/jikig-ai/soleur`.
- `repo_last_synced_at = 2026-04-26T10:30:31Z`; `kb_sync_history` = 50 rows ALL `ok=true`, newest Apr 26 → no reconcile since Apr 26; zero failure rows ⇒ sync not failing, it stopped being attempted.
- Legacy sync path retired; current `workspace-reconcile-on-push` (Inngest, #2854/#2891) created AFTER the freeze.
- `workspace-reconcile-on-push.ts:149` `isIgnoredReconcileRepo` short-circuit runs BEFORE workspace resolution; PR #4666 (May 30) added `jikig-ai/soleur` to the ignore-list. Founder dogfoods their KB from that exact repo → every push dropped before the matching workspace is queried.
- Reproduced reconcile match query: matches exactly 1 workspace (52af49c2, connected, owner row present) — fan-out is simply never reached.

### Fix
- (A) Reorder ignore short-circuit to AFTER resolution, gated on `rows.length===0` (preserves #4666's zero-workspace silence; never starves a connected workspace).
- (B) Warn (Sentry breadcrumb) when an ignored repo HAS connected workspaces (the gap that hid this for 5 weeks).
- (C) Automated recovery: dispatch one reconcile event for 52af49c2 (re-clone fallback via workspace.ts if non-ff); verify via ledger row + /api/kb/tree (no SSH).

### Components Invoked
- Skill: soleur:plan, soleur:deepen-plan (produced the disproven plan)
- Live diagnosis: Doppler DATABASE_URL_POOLER (prd) + pg (/tmp), git archaeology
- Plan rewritten by orchestrator against evidence
