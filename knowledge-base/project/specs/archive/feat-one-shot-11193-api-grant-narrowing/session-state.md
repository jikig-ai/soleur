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

## Review Phase (2026-10-26, second session)
- Status: complete. Class `code`, tier `single-user incident` (plan frontmatter). `Reviewed-Coverage: sequential-fallback 15/15` — the session has no subagent spawn surface; every panel role's lens was executed inline sequentially (git-history, pattern-recognition, architecture, security-sentinel R1–R6, performance, data-integrity, agent-native, code-quality, code-simplicity, user-impact, test-design, data-migration, deployment-verification, structural-enumeration, semgrep+custom rules [0 results], gdpr-gate [5 checks all N/A], anti-slop tier1 inline [clean], coverage consult).
- Census re-verified call-site-by-call-site: all non-census `users` writes service-client; `api_keys`/`audit_*`/`dsar_export_jobs` writes all service-client; authenticated surfaces = SELECT + {email, onboarding_completed_at, pwa_banner_dismissed_at, runtime_explainer_dismissed_at, nudges_dismissed}. Structural enumeration: views all `security_invoker` (no widening); authenticated-callable functions all DEFINER or non-touching; no PUBLIC grants.
- Findings: 1 total (P3) — verify/178 probed the enumerated universe but not the complement: stray `attacl` column grants survive `REVOKE ALL ON TABLE` and passed the sentinel silently (fuzz gate backstopped). Fixed inline: `aeab414a04` (complement row `no_uncovered_col_grants_narrowed`) + `12e21381a5` (widened to service_role for _schema_migrations). Live-verified on local stack: 31/31 bad=0; positive control (planted `GRANT UPDATE(tc_accepted_at)` / `GRANT SELECT(filename)`) fires bad=1 then 0 after revoke.
- Fix round 1: seats resolved via fix-round-seats.sh (9), executed inline — caught the service_role gap above. One verification pass: live verify + positive controls + vitest 66/66 + lint-migration-api-grants green.
- Trailer emitted `e2d297609e`; Review-Evidence comment posted. domain-ruling=CTO (recorded) + CPO sign-off.
- CI cycles: pushed aeab414a04 + 12e21381a5 + e2d297609e.

## QA Phase (2026-10-26, second session)
- Task 3.5 PASS: SET-ROLE/jwt-claims probe matrix on local stack — 5/5 auth SELECTs, 5/5 census UPDATEs, 7/7 denied, RPC reroute lands row, anon denied, service_role correct.
- Plan API-verify steps: RLS_FUZZ_LOCAL=1 rls-grants 7/7 green; run-verify.sh on local stack — verify/178 31/31 bad=0.
- **P1 found in QA:** verify/174 asserted pre-178 grants — post-178 deploy would red 15 rows in `verify-migrations` (which `deploy` needs) → every later deploy blocked. Fixed inline: removed the 15 superseded rows + supersession comment; 150/150 rows bad=0 locally. Same class as review's sentinel-complement finding (verify files probe stated posture, not current truth).
