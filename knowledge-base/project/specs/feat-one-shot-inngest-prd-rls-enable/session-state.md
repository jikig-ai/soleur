# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-06-29-security-inngest-prd-enable-rls-lockdown-plan.md
- Status: complete

### Errors
- IaC-routing PreToolUse hook (`hr-all-infrastructure-provisioning-servers`) blocked the initial Write and two Edits on "operator/apply" framing. Resolved by adding the documented `<!-- iac-routing-ack: plan-phase-2-8-reviewed -->` opt-out (apply path is a merge/schedule-triggered GH-Actions workflow via the Management API — no SSH, no manual infra step). No other errors. All 4 deepen agents completed.

### Decisions
- Live-grounded the finding (did NOT assume): queried `soleur-inngest-prd` (`pigsfuxruiopinouvjwy`) read-only via the Supabase Management API (PAT from Doppler `soleur/prd_terraform`). Confirmed exactly 14 flagged tables (Inngest run-state + 2 migration trackers); advisor worst-case is REAL — `anon`+`authenticated` hold full DML on all 14, PostgREST serves `public,graphql_public`, default ACLs auto-grant future tables.
- Remediation = enable RLS (NOT FORCE) + revoke anon/authenticated (tables+sequences) + revoke postgres default privileges, applied as a standalone SQL artifact under `apps/web-platform/infra/inngest-rls/` (NOT `supabase/migrations/`, which targets the web-platform project — wrong-DB hazard) via a unified push+schedule GH-Actions workflow. No SECURITY DEFINER funcs → search_path-pin gate N/A.
- Safety verified: owner `postgres` bypasses non-forced RLS → Inngest unaffected; pooler role confirmed `postgres`. 7 load-bearing Postgres/Supabase semantics confirmed against authoritative docs.
- Deepen hardening: lock-timeout guard + retry, fail-closed project-identity preflight, GraphQL `/graphql/v1` test, authoritative catalog gate over advisor latency, dual log scrubbers + SHA-pinned actions + anon-key masking, self-healing daily re-apply (no deferred monitor), ADR-030 invariant I8, C4 corrected.

### GDPR escalation status
- Confirmed REAL internet-facing reachability of tables that can embed personal data (event payloads, step I/O, account_id/workspace_id), but NO evidence of actual unauthorized access found during planning → hard STOP (CLO/Art. 33) NOT triggered. Plan makes actual-access investigation a blocking Phase-0 gate in /work (anon + service_role key-exposure check; access-log analysis with log-retention-horizon caveat — partial-window "clean" returns inconclusive → CLO, never "no breach"). If /work finds actual access, STOP and escalate.

### Components Invoked
- Skills: soleur:plan, soleur:deepen-plan
- Agents: Explore; deepen — general-purpose/sonnet (Postgres/Supabase semantics), security-sentinel, data-integrity-guardian, architecture-strategist
- Tooling: Supabase Management API (read-only advisors + database/query), Doppler, git/grep
