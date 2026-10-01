# Phase 3 — live retirement evidence (#8028)

Run 2026-09-13 from the worktree via the plan's Phase 3 script (scratch file, values never printed).

```text
dev: doppler secrets delete rc=0
dev: SUPABASE_PAT deleted, verified absent
prd: doppler secrets delete rc=0
prd: SUPABASE_PAT deleted, verified absent
dev_personal: SUPABASE_PAT already absent
dev_scheduled: SUPABASE_PAT already absent
prd_cla: SUPABASE_PAT already absent
prd_ghcr: SUPABASE_PAT already absent
prd_kb_drift_walker: SUPABASE_PAT already absent
prd_scheduled: SUPABASE_PAT already absent
prd_terraform: SUPABASE_PAT already absent
prd_workspaces_luks: SUPABASE_PAT already absent
ci: absent (never carried it)
cli: absent (never carried it)
cli_ops: absent (never carried it)
```

## Live negative control (after retirement, dev project, --best-effort, malformed sbp_ token)

```text
::error::postgrest-reload-schema: Supabase rejected SUPABASE_ACCESS_TOKEN (HTTP 401) from Doppler config 'dev' (ref=mlwiodleouzwniehynfz). Rotate it per knowledge-base/engineering/operations/secret-scanning.md §SUPABASE_ACCESS_TOKEN, then re-run this job. Response: {"message":"JWT could not be decoded"}
rc=2
```

## Phase 1.12 strict-mode dev reload with the prd_terraform token

```text
postgrest-reload-schema: reload acknowledged (ref=mlwiodleouzwniehynfz, HTTP 201).
```

## AC12 (SUPABASE_PAT) — thirteen configs

dev, dev_personal, dev_scheduled, ci, prd, prd_cla, prd_ghcr, prd_kb_drift_walker, prd_scheduled, prd_terraform, prd_workspaces_luks, cli, cli_ops: all `absent`; no `UNREACHABLE`.

## AC13 (SUPABASE_ACCESS_TOKEN)

`present` in prd + prd_cla, prd_ghcr, prd_kb_drift_walker, prd_scheduled, prd_terraform, prd_workspaces_luks; `absent` in dev, dev_personal, dev_scheduled, ci, cli, cli_ops. `gh secret list` shows exactly one SUPABASE_ACCESS_TOKEN.
