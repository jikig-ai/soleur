---
date: 2026-10-26
category: integration-issues
---

# Supabase Data API auto-grant removal (2026-10-30): remediate by snapshot, not by defaults

When a platform removes implicit grants (Supabase stopping auto-`GRANT` on new `public` tables), the correct backfill is a **generated snapshot of the live effective catalog** (`aclexplode(relacl)` + `pg_attribute.attacl`), not `ALTER DEFAULT PRIVILEGES` to restore auto-expose — ADP is per-creator-role, mis-scopes silently under `supabase_admin`, and re-opens the over-exposure the vendor is closing. REVOKE-bearing down-migrations are strictly worse on prod (they can't distinguish grant provenance) — the honest down is a documented no-op.

Two harness traps measured here: (a) the local Supabase image's bootstrap defacls are owned by `supabase_admin`, and `postgres` cannot `ALTER DEFAULT PRIVILEGES FOR ROLE` another role — a normalize step must connect AS the owner/superuser; (b) a CLI config key (`[api] auto_expose_new_tables`) must be existence-checked against the PINNED CLI version before a plan prescribes it — it was added in supabase/cli#5239, after our pinned 2.84.2.
