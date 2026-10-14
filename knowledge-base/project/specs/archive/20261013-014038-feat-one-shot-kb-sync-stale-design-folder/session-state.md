# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-05-31-fix-kb-sync-stale-design-folder-frozen-timestamps-plan.md
- Status: evidence-complete v3 (writeup only, no fix implemented — operator chose "full data writeup, then decide")

## TRUE root cause (v3, data-confirmed via Doppler prd pooler, read-only)
- Screenshot workspace = 754ee124 (ops@jikigai.com / github.com/jikig-ai/soleur), NOT 52af49c2 (that's jean.deruelle/chatte).
- 754ee124: repo_status=ready, github_installation_id=NULL, last sync 2026-04-23, kb_sync_history=0 rows.
- Webhook reconcile selects `WHERE github_installation_id=<push id> AND repo_url=…`; NULL never matches → workspace unreachable, zero ledger rows.
- Migrations NOT behind (114 applied, latest 088). Only installation in the system is 122213433 (chatte); NO GitHub App install exists for jikig-ai/soleur (audit_github_token_use empty for soleur). Legacy pre-App connection, never re-authorized.

## Remedies (operator to choose)
1. Data recovery: install/authorize GitHub App on jikig-ai/soleur → set installation_id on user+ws 754ee124 → dispatch reconcile (consent gate, Playwright only to consent screen).
2. Systemic guard: detect ready+NULL-install workspaces → needs_reauth state + UI reconnect + Sentry breadcrumb.
3. Observability backstop: Inngest cron alert when a ready workspace has no successful kb_sync_history row in N days.

## Diagnostic errors retracted (4) — NO migrations applied
H1 path-divergence; H2 shallow-clone non-ff; "#4666 shadows 52af49c2" (wrong id→repo map); "prod 5 migrations behind" (false — 088 applied).

## Components Invoked
- Skills: soleur:plan, soleur:deepen-plan (produced the disproven v1/v2 plan)
- Live diagnosis: Doppler DATABASE_URL_POOLER (prd) + pg in /tmp; git archaeology
- Plan rewritten by orchestrator against evidence; autonomous one-shot pipeline halted at user direction
