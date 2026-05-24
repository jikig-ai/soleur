---
title: Migration checklist — feat-4124 (mig 064)
date: 2026-05-22
plan: knowledge-base/project/plans/2026-05-22-feat-wire-today-card-spawn-agent-buttons-pr-a-plan.md
migration: apps/web-platform/supabase/migrations/064_action_sends_acknowledgment.sql
---

# Migration checklist — `064_action_sends_acknowledgment.sql`

This migration adds three nullable acknowledgment columns to
`public.action_sends` (`acknowledged_at`, `artifact_url`, `failure_reason`)
and reshapes the existing WORM `action_sends_no_update` trigger from a
pure-reject `BEFORE UPDATE FOR EACH STATEMENT` to a column-list-scoped
`BEFORE UPDATE OF <pre-064 immutable columns>` so UPDATEs touching ONLY
the new columns are admitted while every pre-064 column remains
immutable.

Renumbered from plan-time `062` → `064` because `main` shipped
`062_workspace_member_removals` and `063_workspace_member_actions` between
plan authorship and `/work` execution.

## dev apply — pending

The migration applies cleanly on dev via the Supabase migration runner
once #4124 PR opens (CI will exercise the apply path). The schema-shape
test at `apps/web-platform/test/supabase-migrations/064-action-sends-acknowledgment.test.ts`
already passes (9/9 assertions covering ADD COLUMN nullability, trigger
reshape, column-list exhaustiveness against mig 051, COMMENTs, and
down-migration restore-of-pure-reject).

## prd apply — pending

prd application is deferred to merge time. The
`verify-migrations` CI job in `web-platform-release.yml` runs the
schema-shape sentinels on every prd deploy and auto-closes any
follow-through issue referencing the migration filename.

Post-merge verification: confirm columns exist in production via the
Supabase REST API:

```bash
SUPABASE_URL=$(doppler secrets get NEXT_PUBLIC_SUPABASE_URL -p soleur -c prd --plain)
SUPABASE_KEY=$(doppler secrets get SUPABASE_SERVICE_ROLE_KEY -p soleur -c prd --plain)
for col in acknowledged_at artifact_url failure_reason; do
  curl -fsS "$SUPABASE_URL/rest/v1/action_sends?select=$col&limit=1" \
    -H "apikey: $SUPABASE_KEY" -H "Authorization: Bearer $SUPABASE_KEY" \
    >/dev/null && echo "✓ $col present" || echo "✗ $col missing"
done
```

WORM trigger reshape verification (cannot be observed via REST):

```sql
-- Run via Supabase MCP or pg connection to prd.
SELECT tgname, tgtype, pg_get_triggerdef(oid)
FROM pg_trigger
WHERE tgrelid = 'public.action_sends'::regclass
  AND tgname = 'action_sends_no_update';
```

Expected: `BEFORE UPDATE OF id, user_id, message_id, action_class,
tier_at_send, template_hash, per_send_body_sha256, recipient_id_hash,
clicked_at, confirmed_typed, approval_signature_sha256, grant_id ON
public.action_sends FOR EACH STATEMENT EXECUTE FUNCTION
public.action_sends_no_mutate()`.

## Rollback

`apps/web-platform/supabase/migrations/064_action_sends_acknowledgment.down.sql`
drops the three new columns AFTER restoring the pure-reject UPDATE
trigger (ordering matters: re-arm trigger first so any in-flight UPDATE
between the two steps remains rejected). No data loss — the acknowledgment
artifacts live on GitHub independently; the operator retains the canonical
view via the linked PR comment / issue label.
