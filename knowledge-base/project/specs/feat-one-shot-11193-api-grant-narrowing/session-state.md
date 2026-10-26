# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-10-26-chore-narrow-default-era-api-grants-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)
- Pipeline: one-shot #11193 — branch feat-one-shot-11193-api-grant-narrowing, draft PR #11253

### Errors
- `dsar_export_audit_pii` in the issue body's audit list is stale — migration `175_tom4_shape_iv_client_grant_revokes` (already on main) revoked its anon/authenticated grants; plan treats it as a no-op verification row.
- No agent-spawn capability inside the planning subagent — skill-prescribed fan-outs executed inline; technical rulings recorded `pending - assumed:` in decision-challenges.md; CPO sign-off (requires_cpo_signoff) pending.
- Plan-review panel could not fan out — noted for the pipeline (Devin: sequential-fallback coverage applies).

### Decisions
- Migration number 178 (176 = open PR #11224; 177 = open WIP PR #11115).
- Per-relation targets: `_schema_migrations` → INTERNAL via OVERRIDES kind-INTERNAL; `api_keys`/`audit_byok_use`/`audit_github_token_use`/`dsar_export_jobs` → anon:none, authenticated:SELECT, service_role:full; `flag_flip_audit` → service_role-only; `users` → authenticated SELECT + column-level UPDATE on census set.
- `users.kb_sync_history`: reroute `recordKbSyncHistory` through `append_kb_sync_row` RPC (p_cap 14) — assumed ruling.
- Threshold `single-user incident`; `requires_cpo_signoff: true` pending.
- `runtime_mint_intent` untouched (already narrowed via 049, coordinates with #4027).

### Components Invoked
- soleur:plan (full run), soleur:deepen-plan (full run, halt gates passed), soleur:gdpr-gate (inline advisory — no findings)
