# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-07-11-security-definer-grant-hygiene-baseline-plan.md
- Status: complete

### Errors
- Two Write attempts initially blocked and self-corrected during planning: IaC-routing hook false-positive (resolved via `iac-routing-ack` opt-out) and an accidental bare-repo-path write (corrected to worktree path). No content lost.
- deepen-plan Observability gate (4.7) initially non-compliant; fixed by declaring the CI-check-surface schema.

### Decisions
- Reframed against merged #6256: durable class-level guard (runtime rls-authz-fuzz.yml AC8, live pg_proc.proacl introspection) already exists. Real residual gap = static `migration-rpc-grants.test.ts` lint is case-sensitive + `AS $$`-only, silently missing the 5 lowercase `security definer` files → false confidence.
- Scoped fix to hardening the static pre-filter (case-insensitive detection, corpus-wide revoke-union of {public,anon,authenticated}, RETURNS TRIGGER excluded, type-precise signatures, .down.sql excluded) + non-vacuity/live-catalog-parity guard. Deferred option (a) ALTER DEFAULT PRIVILEGES as optional defense-in-depth pending live role-scope probe.
- Recorded decision in new ADR-112 (amends ADR-101, ADR-111) rather than frontmatter-less amendment.
- Folded a P0 security correctness bug found in v1 (assertion dropped `public` from forbidden set) and cut a YAGNI comment-marker convention for an explicit allowlist.
- Brand-survival threshold: aggregate pattern.

### Components Invoked
- Skill: soleur:plan (#6328)
- Skill: soleur:deepen-plan
- Agents (6, parallel): security-sentinel, data-integrity-guardian, architecture-strategist, code-simplicity-reviewer, spec-flow-analyzer, Explore
- Deepen-plan gates: 4.6 (pass), 4.7 (fixed→pass), 4.8 (pass), 4.9 (pass)
