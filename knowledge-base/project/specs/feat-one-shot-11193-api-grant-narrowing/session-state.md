# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-10-26-chore-narrow-default-era-api-grants-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)
- Pipeline: one-shot #11193 — branch feat-one-shot-11193-api-grant-narrowing, draft PR #11253

### Errors
- `dsar_export_audit_pii` in the issue body's audit list is stale — migration `175_tom4_shape_iv_client_grant_revokes` (already on main) revoked its anon/authenticated grants; plan treats it as a no-op verification row.
- No agent-spawn capability inside the planning subagent — skill-prescribed fan-outs executed inline; pipeline parent discharged rulings (below).
- Plan-review panel could not fan out — noted for the pipeline (Devin: sequential-fallback coverage applies).

### Rulings (technical-ruling gate, 2026-10-26)
- `cto_spawns=1` — soleur:engineering:cto Rule spawn ruled all 4 technical rows (kb_sync_history reroute confirmed + column-grant fallback struck as dead-on-arrival via 017 RESTRICTIVE policy; api_keys table-level SELECT confirmed — column-level refuted by 4 live authenticated ciphertext call sites; flag_flip_audit keeps service_role; _schema_migrations INTERNAL via OVERRIDES kind-INTERNAL).
- `cpo_spawns=1` — soleur:product:cpo signed off (`single-user incident` threshold) with 3 conditions recorded in plan §User-Brand Impact + decision-challenges.md.
- technical-ruling-gate.sh --branch: PASS (5 rows).
- Plan amended for ruling deltas (Note B fallback struck; rejected-alternatives rows 119–120 corrected).

### Decisions
- Migration number 178 (176 = open PR #11224; 177 = open WIP PR #11115).
- Per-relation targets: `_schema_migrations` → INTERNAL via OVERRIDES kind-INTERNAL; `api_keys`/`audit_byok_use`/`audit_github_token_use`/`dsar_export_jobs` → anon:none, authenticated:SELECT, service_role:full; `flag_flip_audit` → service_role-only; `users` → authenticated SELECT + column-level UPDATE on census set.
- `users.kb_sync_history`: reroute `recordKbSyncHistory` through `append_kb_sync_row` RPC (p_cap 14) — assumed ruling.
- Threshold `single-user incident`; `requires_cpo_signoff: true` pending.
- `runtime_mint_intent` untouched (already narrowed via 049, coordinates with #4027).

### Components Invoked
- soleur:plan (full run), soleur:deepen-plan (full run, halt gates passed), soleur:gdpr-gate (inline advisory — no findings)
