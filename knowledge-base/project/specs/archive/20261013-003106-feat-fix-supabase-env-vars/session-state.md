# Session State

> **Spec dir divergence (intentional):** This directory is named
> `feat-fix-supabase-env-vars/` while the branch is
> `feat-one-shot-2887-supabase-env-isolation/`. The plan subagent named
> the artifact directory; we kept it to avoid a rename mid-pipeline.
> The branch and PR are the canonical anchor — search by branch
> (`feat-one-shot-2887-...`) or by issue number (#2887) when archiving.

## Plan Phase
- Plan file: /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-2887-supabase-env-isolation/knowledge-base/project/plans/2026-04-27-fix-supabase-env-isolation-plan.md
- Status: complete

### Errors
- Context7 MCP returned "Monthly quota exceeded" for the Supabase library query — fell back to authoritative WebSearch hits on supabase.com docs (Managing Environments, Branching).
- Supabase MCP unauthenticated — project provisioning automation documented as CLI/dashboard fallback rather than MCP-driven.

### Decisions
- Detail level: A LOT — P0 security with multiple workstreams (provisioning + Doppler rotation + permanent enforcement + ADR + runbook) merits the full template.
- Two-project separation, not Supabase branching. Branching is Pro-only and preview-oriented; separate projects is Supabase's recommended pattern for dev/prd isolation and stays on Free tier.
- Issue closure via `Ref #2887`, not `Closes #2887`. Classification is `ops-only-prod-write` — actual remediation runs post-merge by operator. Auto-closing at merge would falsely resolve the issue before the rotation completes.
- Preflight Check 5 with canonical-hostname regex (`^[a-z0-9]{20}\.supabase\.co$`) AFTER CNAME resolution, defending against subdomain-bypass per learning `2026-04-23-hostname-prefix-guard-and-strict-mode-pipefail`. Strict-mode resilient (`dig … || true` + explicit empty-handling).
- Bootstrap-trap exposed in `run-migrations.sh`: inserts sentinel rows for migrations 001–010 when `_schema_migrations` is empty — wrong on a fresh dev project. Phase 1.3 documents the manual backfill required and recommends a follow-up issue to add a `--bootstrap=skip` flag.
- Phase 5 (staging project) deferred to follow-up GH issue, milestoned to "Phase 3: Make it Sticky" or "Post-MVP / Later" — load-bearing fix is dev/prd isolation; staging is incremental hardening.

### Components Invoked
- soleur:plan (skill)
- soleur:deepen-plan (skill)
- WebSearch (Supabase docs grounding)
- mcp__plugin_soleur_context7__query-docs (quota-exceeded; fell back to WebSearch)
- gh CLI (issue view, list)
- doppler CLI (configs list + secrets enumeration)
- ripgrep / grep audits across `apps/web-platform/`, `.github/workflows/`, `knowledge-base/`
