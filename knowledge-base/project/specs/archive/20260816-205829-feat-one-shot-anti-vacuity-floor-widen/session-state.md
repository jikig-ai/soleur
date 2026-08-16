# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-08-16-feat-widen-anti-vacuity-floor-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)
- Scope verification: `git diff origin/main...HEAD --name-only` returned only
  `knowledge-base/project/plans/` + `knowledge-base/project/specs/` — subagent stayed in mandate.
- Post-planning collision re-probe: no-op. Plan frontmatter carries no `issue:`/`closes:` field,
  so planning did not re-target an issue the Step 0a.5 gate had not already seen.

### Errors
None. All deepen-plan halt gates passed (4.6 User-Brand Impact, 4.7 Observability, 4.8 PAT-shaped,
4.9 UI-wireframe, 4.10 Encryption, 4.11 Guard Contract); `lint-guard-contract.py` and
`lint-infra-no-human-steps.py` both green.

One transient self-corrected: the first draft's `## Observability` section was written as
"skipped — not applicable" per plan Phase 2.9's narrower trigger set, but deepen-plan Phase 4.7
skips only for pure-docs plans. The gate applied and failed with 0 of 5 fields; the section was
rewritten against the full 5-field schema before proceeding.

### Decisions
- **Population is 7 files / 11 floors, not the brief's 5 / 7.** `test-contention.test.sh` and
  `tmpfs-guard.test.sh` are true positives that a prior review discarded for the wrong reason —
  they carry BOTH a disk-watermark floor and an assertion-cardinality guard routed through `fail`.
  `preflight-check10-suite-integrity.test.sh` carries a fourth floor (its own dispatch floor) the
  brief missed.
- **The mutation oracle was reporting its own baseline.** `build_mutant` slices from the floor's
  `if`, leaving a threshold assigned on the preceding line unbound; under `set -u` the mutant dies
  BEFORE reaching the floor, exiting non-zero for both pre-fix and post-fix forms. 8 of 11 target
  floors are equivalent mutants this way (reproduced: `MIN_ASSERTS: unbound variable`). The arm
  must assert the REASON, not the exit code. Highest-value change in the plan.
- **Cut the declared-contract design after disproving it by construction.** A declaration-free
  `build_mutant` using `command_not_found_handle() { return 0; }` discriminated 8/8, including the
  `ok`/`bad` case the rejection had been built on — removing 33 comment-only file edits and making
  the guard self-widening.
- **Corpus is 74 floor-bearing suites, not 40**, and the sweep was originally specified as the
  non-recursive glob `scripts/*.test.sh` (59 files vs 78), which would have excluded a suite the
  plan had itself classified into the population.
- **Scoped 40 covered / 34 deferred behind a closure identity** (`covered + deferred == repo-wide
  total`) rather than a shrink-only exemption ledger, which would fail CI on bookkeeping the moment
  a legitimate new suite appeared. Deferred set is `apps/web-platform/infra/`, `.claude/hooks/`,
  `plugins/soleur/skills/*/test/`, `apps/web-platform/scripts/`, `scripts/lib/` — held in a
  directory-level ledger with a tracking issue (`wg-when-deferring-a-capability-create-a`).
- **Conservation retained but re-specified as call-site increments** (22–27 sites per suite) plus a
  call-site lint and an automated loop arm: stubbing `bad()` drops the verdict AND the count
  together, so the helper-internal form is tautological in 3 of 7 targets and inexpressible in the
  other 4 (measured `conservation GREEN — defect hidden`, RC=0).

### Open Items Carried Into Work
- **ADR-193 is provisional.** Highest on disk is ADR-186; highest claimed across 69 `origin/*` refs
  is ADR-190. Re-derive the number before merge.
- The open `SOLEUR_SUBAGENT` issue was verified still open and deliberately left unbundled and
  unreferenced, per the brief.

### Components Invoked
- `Skill: soleur:plan`, `Skill: soleur:deepen-plan`
- Agents: `repo-research-analyst`, `learnings-researcher`, `git-history-analyzer`,
  `architecture-strategist`, `test-design-reviewer`, `code-simplicity-reviewer`
- `scripts/lint-guard-contract.py`, `scripts/lint-infra-no-human-steps.py`, `scripts/test-all.sh`
  (registration checks), `gh issue list/view`, direct suite execution for all floor measurements
