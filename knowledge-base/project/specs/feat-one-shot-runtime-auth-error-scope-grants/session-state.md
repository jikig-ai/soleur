# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-06-08-fix-scope-grants-runtimeautherror-rsc-prefetch-noise-plan.md
- Status: complete

### Errors
None. (One self-corrected mid-flight: an enhancement-summary edit initially broke YAML frontmatter; fixed and verified before commit.)

### Decisions
- Root cause reframed: `resolveBashAutonomous` (added by PR #4949) already catches `RuntimeAuthError`, fails closed to `false`, and deliberately mirrors to Sentry via `reportSilentFallback` at `level: "error"`. The Sentry event ("handled: yes") is that mirror, not an unhandled crash. The real defect is severity miscalibration.
- Fix = per-cause severity split, not a redirect. Downgrade transient `jwt_mint` cause to `warnSilentFallback`; keep `denied_jti`/`rotation` at `error`. Explicit guard against adding a redirect (would bounce a founder off their own settings page on a transient blip).
- Adopted existing precedent: `warnSilentFallback` established at 6+ sites; `mapRuntimeAuthCauseToErrorCode` already exists for this discrimination.
- Test runner: vitest (`./node_modules/.bin/vitest run`), never `bun test`. Existing `test/resolve-bash-autonomous.test.ts` updated, mock enriched to carry `cause`.
- All deepen-plan gates passed (4.6 User-Brand Impact threshold `none`, 4.7 Observability 5-field no-SSH, 4.8 PAT no-match, 4.9 UI-wireframe no-UI). Code-review overlap #3739 acknowledged as orthogonal.

### Components Invoked
- Skill: soleur:plan
- Skill: soleur:deepen-plan
- Supporting: Bash, Read, Edit, Write
