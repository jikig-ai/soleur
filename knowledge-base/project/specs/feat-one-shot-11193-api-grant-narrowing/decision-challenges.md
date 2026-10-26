# Decision Challenges — feat-one-shot-11193-api-grant-narrowing

No agent-spawn capability on this harness (Devin CLI subagent, no Task tool): technical rulings are recorded `pending - assumed:` per the ruling contract, for `ship` to surface.

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| `users.kb_sync_history` write path after re-narrowing table-level UPDATE: reroute `recordKbSyncHistory` through `append_kb_sync_row` (053 definer RPC, `p_cap: 14`) vs adding `UPDATE(kb_sync_history)` to the column grant | technical | pending - assumed: reroute through the RPC — the repo's own comment names it "the only tenant-callable write path" and it adds row-lock atomicity; documented fallback is the column grant |
| `authenticated` on `api_keys`: table-level `SELECT` vs column-level `SELECT` excluding `encrypted_key`/`iv`/`auth_tag` | technical | pending - assumed: table-level SELECT (matches today's reads; RLS already scopes to owner rows; column-level deferred to a follow-up per plan Future Considerations) |
| `flag_flip_audit`: keep `service_role` full grants vs INTERNAL (zero api-role grants) | technical | pending - assumed: keep `service_role` — migration 175's documented convention is "service-role-only is the documented shape" |
| `_schema_migrations`: `INTERNAL` (zero api-role grants) vs `service_role`-only | technical | pending - assumed: INTERNAL via an OVERRIDES kind-INTERNAL entry, contingent on the Phase-1 census confirming no api-role reader (the INTERNAL registry map mechanically cannot hold it — it collides with the parsed 174 snapshot entry) |
| CPO sign-off required by `requires_cpo_signoff: true` (threshold `single-user incident`, matching ADR-303's declared threshold for this grant surface) | operator (priority/schedule) | pending - no CPO agent spawn available on this harness; surfaced for the pipeline to obtain or waive |
