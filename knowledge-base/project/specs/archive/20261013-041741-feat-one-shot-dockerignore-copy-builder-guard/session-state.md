# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-07-03-feat-dockerignore-copy-builder-guard-plan.md
- Status: complete

### Errors
None. CWD verified on first attempt. All deepen-plan halt gates (User-Brand Impact, Observability, PAT-shaped, UI-wireframe) passed; no telemetry emitted.

### Decisions
- Git-tracked discriminator is the core design: an in-context COPY --from/RUN-script src that `git ls-files` tracks must survive `.dockerignore`; untracked srcs (.next, dist/server, next.config.mjs) are build-generated and skipped — self-maintaining, non-flaky (rejected on-disk existsSync).
- Simplified evaluator: reuse existing dockerignoreInfraReincludes() Set+prefix pattern instead of a general glob engine (all real in-scope excludes are literal dir prefixes; all re-includes exact `!<path>`). Functions inline in one new test file — no separate lib/ module.
- Wholesale scope: extended beyond COPY --from=builder to also cover builder-stage `RUN bash scripts/<x>.sh` — identical exit-127 release-break class.
- TDD RED-first: two synthetic fixtures (COPY + RUN, no re-include) must produce violations against a stub; real-repo assertion must be zero violations (repo currently clean — no Dockerfile/.dockerignore change needed).
- Threshold `none`, lane `single-domain`: test-only tooling change; no UI, regulated data, infra, or ADR.

### Components Invoked
- Bash CWD verification
- Skill soleur:plan
- Skill soleur:deepen-plan
- Agents: code-simplicity-reviewer, architecture-strategist (parallel)
