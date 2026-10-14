# Session State

## Plan Phase

- Plan file: knowledge-base/project/plans/2026-09-07-fix-repo-write-boundary-tag-shared-store-softening-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)
- Draft PR: #7908
- Scope check: `git diff origin/main...HEAD --name-only` → plans/, specs/, and the
  hook-regenerated `knowledge-base/INDEX.md` only. No product-code breach.
- Target re-probe: plan frontmatter `closes: 7795` matches the ref cleared at Step 0a.5.
  No newly-discovered target to re-gate.

### Errors

- First commit rejected by lefthook markdown-lint (MD032); fixed and re-committed.
- Two of the planning subagent's own scope claims were falsified during its review passes
  and are recorded in the plan as withdrawn claims: (1) `run-migrations.sh` asserted
  not-battery-reachable on a `head -5`-truncated grep — it IS reachable; (2) plan v1 claimed
  the `git-data-client.ts` graft "lands on the FATAL side" — false, a forced refspec creates
  as readily as it moves.
- A research subagent mis-attributed quotes to ADR-133 (contains zero `shared_store`/`refs/tags`
  mentions); caught before it propagated.
- MCP `plugin:github:github` and `playwright` failed to connect; neither needed (`gh` CLI used).

### Decisions

- Create-only softening, NOT the issue's Option 1 as written. A live probe showed `git fetch`
  CREATES tags but cannot MOVE one, and `--prune` without `--prune-tags` cannot delete one.
  Only the creation cell softens, leaving the existing anti-laundering test arm 43 green verbatim.
- Rejected Option 2 (`git ls-remote`): discriminates the wrong property (a tag this run authored
  is also "on origin") and re-derives a classification input after the measurement window closes.
- Added a name-collision guard: `refs/tags/origin/main` shadows the remote ref, and `test-all.sh`
  plus the work/qa/ship gates all resolve that bare name. Free — 3054 tags contain zero slashes.
- Cut ~40% of the draft on DHH/simplicity review while adding the two arms review proved missing.
- Declared `single-user incident` brand-survival threshold; `requires_cpo_signoff: true`.

### Components Invoked

soleur:plan; soleur:deepen-plan; agents Explore, learnings-researcher, repo-research-analyst,
functional-discovery, cto, cpo, fable consult, escalated plan-review panel (dhh-rails-reviewer,
kieran-rails-reviewer, code-simplicity-reviewer, architecture-strategist, spec-flow-analyzer),
deepen passes (verify-the-negative, post-edit self-audit, test-design-reviewer,
observability-coverage-reviewer, security-sentinel); validators lint-guard-contract.py,
lint-infra-no-human-steps.py, run-migrations-schema-probe.test.sh.
