---
title: "Supabase MCP OAuth failure: fall back to Doppler DATABASE_URL_POOLER, not manual handoff"
date: 2026-05-16
tags: [workflow, supabase, mcp, oauth, automation, hr-exhaust-all-automated-options-before, hr-never-label-any-step-as-manual-without]
feature: feat-oauth-tc-consent-3205
pr: 3853
issue: 3205
---

# Supabase MCP OAuth failure: fall back to Doppler DATABASE_URL_POOLER, not manual handoff

## Context

During `/soleur:work` execution of `feat-oauth-tc-consent-3205`, the agent
needed to apply migration `044_add_tc_acceptances_ledger.sql` to the dev
Supabase project (AC1 pre-merge). The plan declared this as
"automatable per `mcp__plugin_supabase_supabase__apply_migration`" per the
work skill's operator-step automation gate.

The Supabase MCP server requires an OAuth handshake. The flow generated
URLs at `https://api.supabase.com/v1/oauth/authorize`. Three successive
URLs were rejected by Supabase's `https://supabase.com/dashboard/authorize?auth_id=...`
landing page with an "URL invalid" error — external Supabase-side breakage
at the `auth_id` handoff. The agent's response was wrong twice:

1. **First wrong move:** rationalised the failure as "OAuth is genuinely
   manual" and produced a 248-line SQL block for the operator to paste
   into the dashboard SQL editor. Direct violation of
   `hr-never-label-any-step-as-manual-without`: the rule says
   "Browser tasks → Playwright MCP first (only CAPTCHAs and OAuth consent
   are genuinely manual)". Dashboard SQL paste is NOT genuinely manual.
2. **Second wrong move (caught by operator):** even after switching to
   Playwright MCP, the agent didn't check the prior automation tiers per
   `hr-exhaust-all-automated-options-before` (priority 1: Doppler).
   Doppler had `DATABASE_URL_POOLER` for both dev and prd — the migration
   path it should have taken first.

## Recovery (the path that worked)

```bash
# 1. Get the pooler URL from Doppler (priority 1).
doppler run -p soleur -c dev -- bash -c 'echo $DATABASE_URL_POOLER'
# → postgresql://postgres.mlwiodleouzwniehynfz:***@aws-0-eu-west-1.pooler.supabase.com:6543/postgres

# 2. Verify the project ref matches the plan's dev/prd refs — Doppler is
#    the source of truth (plan project refs are preconditions, not facts).
#    Plan said dev=bdgbnzmprmqsibpvtbmd, Doppler said dev=mlwiodleouzwniehynfz.
#    Doppler wins — applying via the plan's refs would have hit the wrong project.

# 3. Rewrite port :6543 → :5432 for session mode. Transaction mode (6543)
#    rejects multi-statement DDL with SQLSTATE 42601 "cannot insert multiple
#    commands into a prepared statement".
SESSION_URL="${DATABASE_URL_POOLER/:6543/:5432}"

# 4. Apply via node-pg wrapped in BEGIN;…;COMMIT. (Direct DB host
#    db.<ref>.supabase.co:5432 is IPv6-only and unreachable from most
#    networks; the pooler is IPv4.)
mkdir -p /tmp/pg-apply && cd /tmp/pg-apply && bun add pg
cat > /tmp/pg-apply/apply.mjs <<'JS'
import pg from "pg"; import { readFileSync } from "node:fs";
const url = process.env.SESSION_URL;
const client = new pg.Client({ connectionString: url });
await client.connect();
const sql = readFileSync(process.argv[2], "utf8");
try {
  await client.query("BEGIN");
  await client.query(sql);
  await client.query("COMMIT");
} catch (e) { await client.query("ROLLBACK"); throw e; }
finally { await client.end(); }
JS
SESSION_URL="$SESSION_URL" node /tmp/pg-apply/apply.mjs /abs/path/to/migration.sql

# 5. Post-apply verification via the same pg client. Asserted: RLS enabled,
#    0 policies, BEFORE UPDATE/DELETE triggers, SECURITY DEFINER on RPCs,
#    UNIQUE constraints present.
```

## The rule

When the Supabase MCP OAuth flow fails (or any MCP OAuth fails for any
plan-prescribed tool), the fallback is NOT "ask the operator to do it
manually in the dashboard". The fallback walks down the
`hr-exhaust-all-automated-options-before` priority chain:

1. **Doppler** — every Supabase project has `DATABASE_URL` and
   `DATABASE_URL_POOLER` provisioned. The pooler URL (port 6543
   transaction mode, 5432 session mode) is the production-grade migration
   path. Use it.
2. **MCP** — try the loaded MCP server first if available.
3. **CLI** — `supabase db query --db-url` for single-statement queries
   (transaction-mode-compatible), but it wraps in prepared statements and
   so cannot run multi-statement migration files.
4. **REST** — Supabase Management API requires a personal access token
   from `supabase.com/dashboard/account/tokens`; that's still operator-
   controlled but better than dashboard paste.
5. **Playwright MCP** — drive the dashboard SQL editor; the user provides
   login interactively at the sign-in page.
6. **Manual handoff** — only for genuinely manual steps (CAPTCHA, OAuth
   consent, credit-card entry). Dashboard SQL editor paste is NEVER
   manual; Playwright MCP can drive it.

The agent's mental model failure: treating the operator-step gate's
listed MCP as the *only* automation surface. The gate names MCP as the
priority-2 tool; priority-1 Doppler is always available and was the
right answer here.

## Why this matters beyond Supabase

The same pattern applies to any MCP-fronted service: when MCP OAuth
breaks, look for an alternative credential surface (CLI access token,
direct DB connection string, REST API key) in Doppler before degrading
to manual handoff. Plans that say "operator runs X" are nearly always
automatable via a Doppler-managed credential.

## Workflow fix applied

- `plugins/soleur/skills/work/SKILL.md` operator-step automation gate
  extended with the explicit "Supabase fallback chain" enumeration
  (Doppler → pooler URL → session-mode port rewrite → pg + BEGIN/COMMIT)
  so the next /work execution doesn't need to rediscover this.
