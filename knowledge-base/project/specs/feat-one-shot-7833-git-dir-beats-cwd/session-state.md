# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-09-04-fix-test-fixture-git-env-scrub-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)
- Scope check: PASS — subagent touched only knowledge-base/{INDEX.md,project/plans,project/specs}
- Collision re-probe after planning: plan frontmatter `closes: 7833` — same target as Step 0a.5
  cleared. No re-target, no new refs to probe.

### Errors
- deepen-plan gate 4.7 rejected the first run: `## Observability` lacked the required `logs:` field.
  Added `where`/`retention`; all five fields pass.
- AC15's citation loop flagged a forward reference the plan had introduced
  (`.../mutation-matrices.md`, created by /work). Reworded to cite the directory.
- First-draft architecture was wrong and was replaced before commit: it aimed a new
  `fixture-scan.py --rule gitenv` at ~900 test files. Two independent reviews converged on the
  recurring assembly being the hook entry points; measurement falsified the helper shape.
- Cross-reference nit (not blocking): decision-challenges.md cites `## Deferral`; the section is
  `### Deferral` under `## Files to Edit`. Content anchor resolves.

### Decisions
- The environment is the write boundary, not the operand. `git -C <abs>` and `cwd:` are both
  overridden by `GIT_DIR`; with `GIT_DIR` scrubbed, an absolute `GIT_INDEX_FILE` still retargets
  `git add` into the victim's index. Both measured (M-1, M-3).
- Mechanism is worktree-conditional: a lefthook `pre-commit` command inherits absolute
  `GIT_DIR`/`GIT_INDEX_FILE` only in a LINKED WORKTREE; a plain clone inherits neither. Every
  feature branch here is a worktree, so the hazardous arm is the normal one — and anyone
  reproducing in a fresh clone would wrongly conclude the issue is stale.
- Detector re-aimed (Challenge 1, ACCEPTED): guard over the closed hook-entry-point set
  (26 `run:` lines, 2 test-runner invocations, 2 `scripts/hooks/` files) + a fail-loud runtime
  tripwire (bunfig `[test] preload`, measured rc=97 dirty / rc=0 clean), instead of a shape rule
  over an unenumerable ~900-file corpus. Covers transitive spawns no source scan can see.
- Sweep re-scoped (Challenge 2, ACCEPTED): sentinel sites are the entry points, pinned
  mechanically; the ~48 fixture suites are beneficiaries. Three Bun suites + two python suites
  converted now; rest deferred to a tracked follow-up, gated by AC14 (issue must exist and be open).
- Reporter's suggested fix corrected (Challenge 3): `GIT_CEILING_DIRECTORIES: <fixture dir>` does
  NOT stop escape when git's cwd equals it — the PARENT is the working spelling. The `undefined`
  spelling is fine; the real hazard is that under Bun 1.3.11 `delete process.env.GIT_DIR` does not
  reach a child spawned without an explicit `env` (Node propagates it correctly). Hence the scrub
  belongs on the invocation, not inside the runtime.
- #7833 is the SECOND occurrence in the SAME lefthook command: `welcome-hook.test.ts` was fixed
  per-file for this exact defect on 2026-04-03, and a sibling suite in the same directory
  reproduced it five months later. A per-file fix has been tried and did not generalise one
  directory over.

### Components Invoked
soleur:plan; soleur:deepen-plan; agents repo-research-analyst, learnings-researcher,
functional-discovery, architecture-strategist, spec-flow-analyzer, code-simplicity-reviewer,
kieran-rails-reviewer, scoped fable advisor consult; scripts lint-guard-contract.py,
lint-infra-no-human-steps.py, fixture-scan.py; ten local measurement probes.
