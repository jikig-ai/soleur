# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-06-03-fix-cron-workspace-gc-and-kb-reconcile-isolation-plan.md
- Status: complete

### Errors
None. Two stale-premise corrections surfaced during planning (both fixed in the plan, not blockers):
- The incident said "add it to `manual-trigger-allowlist.ts`" — but that file is **derived** from `EXPECTED_CRON_FUNCTIONS` (cron-manifest.ts); the real edit is the manifest entry + the function's own `{ event: "cron/workspace-gc.manual-trigger" }` trigger. Editing the allowlist file directly would break the drift guard.
- The incident said "verify #4846 appears" as a reconcile-resumed signal — but **#4846 is a MERGED PR for an unrelated chat-RLS incident**, not a kb_sync_history marker. Success criterion corrected to: a fresh `webhook_push` `kb_sync_history` `ok:true` row written after the GC frees disk.

### Decisions
- GC is an in-process Inngest cron (not dispatch-hybrid) modeled on `cron-supabase-disk-io.ts` — pure local-fs statfs+sweep, no credentials/claude, own Sentry monitor slug, runs in-container against the mounted volume.
- Isolation = `CRON_WORKSPACE_ROOT=/workspaces/.cron` subdir (MVP, no new Terraform volume) set in `ci-deploy.sh` at both docker-run sites; separate `hcloud_volume` deferred to a tracking issue.
- Destructive-sweep safety is structural: matches only `soleur-*` prefix + `maxdepth 1` + age>1h, runs in `.cron` (below the UUID workspace dirs), with a unit test asserting a 36-char UUID dir is never swept.
- Deepen finding folded in as MANDATORY: `ci-deploy.test.sh:1186-1235` uses `grep -qF` (substring) so `/workspaces/.cron` false-passes — plan mandates updating the assertion literal.
- Threshold = single-user incident → requires_cpo_signoff: true; data-min satisfied (Sentry payload = free-MB + swept count + root path, no UUIDs/PII). Ref #4882 (does not close); #4878 untouched.

### Components Invoked
- soleur:plan, soleur:deepen-plan (inline research/review — Task tool unavailable in subagent context)
- Two git commits (plan+tasks creation; deepen pass)

## Out-of-band UI fix (user request mid-pipeline)
- Gold-tinted the "Sync now" button (`kb-sync-status.tsx`) for UX consistency — committed as eb17071a, behavior-safe color-only change, folded into this branch.
