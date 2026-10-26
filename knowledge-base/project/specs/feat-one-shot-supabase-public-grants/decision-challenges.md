# Decision Challenges — feat-one-shot-supabase-public-grants

Headless planning run (one-shot planning subagent; no Task/spawn capability in this harness). Technical rulings that would have gone to the CTO agent are recorded `pending - assumed:` per the pipeline delegation rule; the ship gate renders these for resolution.

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| Per-table explicit GRANTs in each creating migration vs ALTER DEFAULT PRIVILEGES restoring auto-expose | technical | pending - assumed: per-table explicit grants (Supabase-recommended remediation; ADP-restore re-opens the over-exposure Supabase is closing, contradicts issue 4027's narrowing direction, and ADR-112 established a mis-scoped ADP under supabase_admin is a silent no-op pending the 6340 live probe) |
| Backfill content: generated prd-catalog snapshot vs hand-audited tightening during backfill | technical | pending - assumed: generated snapshot of current effective privileges verbatim (zero prd behavior change); per-table narrowing deferred to a follow-up issue paired with 4027 |
| Static lint shape: bash lint-migration-api-grants.sh with --from-pr-diff vs vitest module in test/migration-lint/ | technical | pending - assumed: bash lint wired into tenant-integration.yml beside lint-migration-fk-preconditions.sh (the established migration PR-diff chokepoint; fails fast pre-DB), runtime fuzz gate stays authoritative per ADR-112 |
| Relation scope of the backfill and guards: tables only vs tables plus views, materialized views, sequences | technical | pending - assumed: all four relkinds (the Supabase change revokes api-role privileges on tables, views, sequences and functions; functions are already covered by ADR-112 machinery; sequences lose USAGE which breaks serial/identity Data API inserts) |
| .down.sql for migration 164: REVOKE-down vs documented no-op | technical | pending - assumed: documented no-op (REVOKE removes ACL entries regardless of origin, so a revoke-down strips pre-existing default-era access on prd, strictly worse than the forward state) |
| Local-stack parity mechanism: [api] auto_expose_new_tables = false in config.toml vs post-start normalize step in supabase-local.sh | technical | pending - assumed: config flag primary (deterministic, declarative, models the post-10-30 world exactly); supabase-local.sh normalize fallback only if the key is unsupported on pinned CLI 2.84.2 — verify at implementation per CLI-verification gate |
| CPO sign-off required before soleur:work (plan declares requires_cpo_signoff at single-user-incident threshold) | operator (authorization) | pending - CPO could not be consulted in this headless run; plan frontmatter carries requires_cpo_signoff: true and the sign-off must land before work begins |
